-- Complete PVP Bot with Adaptive Learning
-- Clean rebuild from scratch for Roblox fighting game

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

-- ===== BOT STATE =====
local bot = {
    enabled = true,
    learning = false,
    difficulty = 1, -- 1=easy, 2=normal, 3=hard
    targetName = "PuRgE_aLt20", -- Hardcoded target (set to nil for auto-target)

    -- Ability cooldowns
    cooldowns = {
        q = { last = 0, duration = 0.65 },
        fireball = { last = 0, duration = 1.4 },
    },

    -- Learning memory
    memory = {
        playerQPattern = {},        -- timestamps of when player Q'd
        fireballAimPattern = {},    -- angles/directions player aims
        playerSpacing = {},         -- distance player maintains
        dodgePattern = {},          -- directions player dodges
    },

    -- Combat tracking
    combat = {
        target = nil,
        targetDistance = 0,
        lastAttackTime = 0,
        inCombat = false,
    },

    -- Enemy ability detection
    enemyAbilities = {
        lastHitTime = 0,
        lastHitCount = 0,
        hitWindow = 0.3, -- If hits land within 0.3s, count as fireball
        fireballIncoming = false,
    },

    -- Sprint management
    sprint = {
        active = false,
        enabled = true,
    }
}

-- ===== INTENT CLIENT (Send inputs via Python server) =====
local IntentClient = {}

function IntentClient.post(payload)
    payload = payload or {}
    local url = "http://127.0.0.1:3636/intent"
    local body = HttpService:JSONEncode(payload)

    local requester = (syn and syn.request) or http_request or request
    local ok, response

    if requester then
        ok, response = pcall(requester, {
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    else
        ok, response = pcall(HttpService.PostAsync, HttpService, url, body, Enum.HttpContentType.ApplicationJson, false)
    end

    return ok
end

function IntentClient.tapKey(key)
    return IntentClient.post({ event = "press", key = string.upper(key) })
end

function IntentClient.holdKey(key, down)
    return IntentClient.post({ event = down and "keydown" or "keyup", key = string.upper(key) })
end

function IntentClient.moveMouse(dx, dy)
    return IntentClient.post({ mouseDx = dx or 0, mouseDy = dy or 0 })
end

function IntentClient.click(button)
    return IntentClient.post({ event = "press", button = string.lower(button or "left") })
end

-- ===== COLLISION DETECTION =====
local function isInMeleeRange(targetChar, padding)
    padding = padding or Vector3.new(1.5, 2, 1.5)

    if not (char and targetChar and char.Parent and targetChar.Parent) then return false end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then return false end

    local mySize = myRoot.Size * 0.5
    local targetSize = (targetRoot.Size + padding) * 0.5

    local delta = myRoot.Position - targetRoot.Position

    return math.abs(delta.X) <= mySize.X + targetSize.X
        and math.abs(delta.Y) <= mySize.Y + targetSize.Y
        and math.abs(delta.Z) <= mySize.Z + targetSize.Z
end

local function getDistanceTo(targetChar)
    if not (char and targetChar and char.Parent and targetChar.Parent) then return math.huge end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then return math.huge end

    return (myRoot.Position - targetRoot.Position).Magnitude
end

local function getDirectionTo(targetChar)
    if not (char and targetChar and char.Parent and targetChar.Parent) then return Vector3.new(0, 0, 1) end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then return Vector3.new(0, 0, 1) end

    return (targetRoot.Position - myRoot.Position).Unit
end

-- ===== TARGET SELECTION =====
local function findNearestEnemy()
    -- If hardcoded target is set, prioritize it
    if bot.targetName then
        for _, p in ipairs(Players:GetPlayers()) do
            if (p.Name == bot.targetName or p.DisplayName == bot.targetName) and p.Character and p.Character.Parent then
                return p.Character, getDistanceTo(p.Character)
            end
        end
        -- Hardcoded target not found, return nil
        return nil, math.huge
    end

    -- Auto-find nearest enemy
    local best = nil
    local bestDist = math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and p.Character.Parent then
            local dist = getDistanceTo(p.Character)
            if dist < bestDist then
                bestDist = dist
                best = p.Character
            end
        end
    end

    return best, bestDist
end

-- ===== PLAYER BEHAVIOR TRACKING =====
local function recordPlayerQ()
    if bot.learning then
        table.insert(bot.memory.playerQPattern, tick())
        if #bot.memory.playerQPattern > 50 then
            table.remove(bot.memory.playerQPattern, 1)
        end
    end
end

local function recordPlayerFireball(direction)
    if bot.learning and direction then
        local angle = math.atan2(direction.Z, direction.X)
        table.insert(bot.memory.fireballAimPattern, angle)
        if #bot.memory.fireballAimPattern > 30 then
            table.remove(bot.memory.fireballAimPattern, 1)
        end
    end
end

local function recordPlayerSpacing(distance)
    if bot.learning then
        table.insert(bot.memory.playerSpacing, distance)
        if #bot.memory.playerSpacing > 20 then
            table.remove(bot.memory.playerSpacing, 1)
        end
    end
end

local function getAverageQSpamRate()
    if #bot.memory.playerQPattern < 3 then return 0 end

    local recent = bot.memory.playerQPattern[#bot.memory.playerQPattern] -
                   bot.memory.playerQPattern[#bot.memory.playerQPattern - 2]
    return recent / 2
end

local function getCommonFireballAngle()
    if #bot.memory.fireballAimPattern == 0 then return 0 end

    local sum = 0
    for _, angle in ipairs(bot.memory.fireballAimPattern) do
        sum = sum + angle
    end
    return sum / #bot.memory.fireballAimPattern
end

local function getPreferredSpacing()
    if #bot.memory.playerSpacing == 0 then return 50 end

    local sum = 0
    for _, dist in ipairs(bot.memory.playerSpacing) do
        sum = sum + dist
    end
    return sum / #bot.memory.playerSpacing
end

-- ===== BOT COMBAT LOGIC =====
local function canCastAbility(abilityName)
    local cd = bot.cooldowns[abilityName]
    if not cd then return false end

    return (tick() - cd.last) >= cd.duration
end

local function recordAbilityCast(abilityName)
    local cd = bot.cooldowns[abilityName]
    if cd then cd.last = tick() end
end

-- Q Attack (melee)
local function botQ()
    if not canCastAbility("q") then return false end

    local target = bot.combat.target
    if not target then return false end

    -- Need to be in melee range
    if not isInMeleeRange(target) then return false end

    -- If learning: avoid some attacks based on spacing (more evasive)
    if bot.learning and bot.difficulty == 1 then
        if math.random() < 0.3 then return false end
    end

    IntentClient.tapKey("Q")
    recordAbilityCast("q")
    recordPlayerQ() -- Track our own attack pattern
    return true
end

-- Fireball (ranged, needs aiming)
local function botFireball()
    if not canCastAbility("fireball") then return false end

    local target = bot.combat.target
    if not target then return false end

    local dist = getDistanceTo(target)

    -- Fireball range ~150 studs
    if dist > 150 or dist < 10 then return false end

    -- Calculate aim direction
    local direction = getDirectionTo(target)

    -- When learning: predict where player usually aims
    if bot.learning and #bot.memory.fireballAimPattern > 5 then
        local commonAngle = getCommonFireballAngle()
        direction = Vector3.new(math.cos(commonAngle), 0, math.sin(commonAngle))
    else
        -- Random lead shots
        local offset = math.random() * 0.3 - 0.15
        direction = direction + Vector3.new(offset, 0, offset)
    end

    -- Aim by moving mouse (simplified)
    local aimX = math.random(-10, 10)
    local aimY = math.random(-10, 10)
    IntentClient.moveMouse(aimX, aimY)

    wait(0.05) -- Brief delay before casting

    IntentClient.tapKey("E") -- Fireball key (adjust if different)
    recordAbilityCast("fireball")
    recordPlayerFireball(direction)
    return true
end

-- Sprint management
local function botToggleSprint(shouldSprint)
    if shouldSprint and not bot.sprint.active then
        IntentClient.tapKey("LSHIFT")
        bot.sprint.active = true
    elseif not shouldSprint and bot.sprint.active then
        IntentClient.tapKey("LSHIFT")
        bot.sprint.active = false
    end
end

-- Movement/Spacing control
local function botManageSpacing()
    local target = bot.combat.target
    if not target then return end

    local dist = getDistanceTo(target)
    local preferredDist = bot.learning and getPreferredSpacing() or 50

    -- Cap maximum distance (don't stray too far)
    local maxDist = 120

    if bot.learning then
        recordPlayerSpacing(dist)
    end

    -- Keep distance by moving toward/away
    if dist < preferredDist - 10 then
        -- Move away (but not too far)
        if dist < maxDist then
            IntentClient.holdKey("S", true)
            botToggleSprint(true) -- Sprint while retreating
        else
            IntentClient.holdKey("S", false)
            IntentClient.holdKey("W", false)
            botToggleSprint(false)
        end
    elseif dist > preferredDist + 10 then
        -- Move closer
        IntentClient.holdKey("W", true)
        botToggleSprint(true) -- Sprint while approaching
    else
        IntentClient.holdKey("W", false)
        IntentClient.holdKey("S", false)
        botToggleSprint(false)
    end
end

-- Dodge incoming attacks
local function botDodge(urgent)
    urgent = urgent or false

    -- Urgent dodge (fireball detected)
    if urgent then
        local dodgeDir = math.random(1, 2)
        if dodgeDir == 1 then
            IntentClient.holdKey("A", true)
            spawn(function()
                wait(0.15)
                IntentClient.holdKey("A", false)
            end)
        else
            IntentClient.holdKey("D", true)
            spawn(function()
                wait(0.15)
                IntentClient.holdKey("D", false)
            end)
        end

        bot.enemyAbilities.fireballIncoming = false
        return true
    end

    -- Casual dodge (short burst)
    if math.random() < 0.2 then
        local dodgeDir = math.random(1, 2)
        if dodgeDir == 1 then
            IntentClient.holdKey("A", true)
            spawn(function()
                wait(0.1)
                IntentClient.holdKey("A", false)
            end)
        else
            IntentClient.holdKey("D", true)
            spawn(function()
                wait(0.1)
                IntentClient.holdKey("D", false)
            end)
        end
    end
end

-- ===== MAIN BOT LOOP =====
local function botTick()
    if not bot.enabled or not char or not char.Parent then return end

    -- Check for incoming fireball (highest priority)
    if bot.enemyAbilities.fireballIncoming then
        botDodge(true) -- Urgent dodge
        return
    end

    -- Find target
    bot.combat.target, bot.combat.targetDistance = findNearestEnemy()

    if bot.combat.target then
        bot.combat.inCombat = true

        -- Combat decision tree based on difficulty
        if bot.difficulty == 1 then
            -- Easy: mostly dodge, occasional attacks
            if math.random() < 0.5 then botDodge() end
            if math.random() < 0.3 then botQ() end
            if math.random() < 0.2 then botFireball() end

        elseif bot.difficulty == 2 then
            -- Normal: balanced aggression
            botManageSpacing()
            if math.random() < 0.6 then botQ() end
            if math.random() < 0.4 then botFireball() end

        else -- difficulty == 3
            -- Hard: aggressive spam
            if math.random() < 0.8 then botQ() end
            if math.random() < 0.6 then botFireball() end
        end

    else
        bot.combat.inCombat = false
        IntentClient.holdKey("W", false)
        IntentClient.holdKey("S", false)
        IntentClient.holdKey("A", false)
        IntentClient.holdKey("D", false)
    end
end

-- ===== KEYBOARD CONTROLS =====
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.L then
        bot.learning = not bot.learning
        print("[Bot] Learning: " .. tostring(bot.learning))
    end

    if input.KeyCode == Enum.KeyCode.K then
        bot.enabled = not bot.enabled
        print("[Bot] Enabled: " .. tostring(bot.enabled))
    end

    if input.KeyCode == Enum.KeyCode.O then
        bot.difficulty = (bot.difficulty % 3) + 1
        print("[Bot] Difficulty: " .. bot.difficulty)
    end

    if input.KeyCode == Enum.KeyCode.M then
        print("\n[Bot] Memory Stats:")
        print("  Q Pattern: " .. #bot.memory.playerQPattern .. " records (rate: " .. string.format("%.2f", getAverageQSpamRate()) .. "s)")
        print("  Fireball Angles: " .. #bot.memory.fireballAimPattern .. " records")
        print("  Spacing: " .. #bot.memory.playerSpacing .. " records (preferred: " .. string.format("%.1f", getPreferredSpacing()) .. " studs)")
        print("  Dodge Patterns: " .. #bot.memory.dodgePattern .. " records\n")
    end
end)

-- ===== HIT DETECTION (Detect enemy fireballs) =====
local function setupHitDetection()
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local lastHealth = humanoid.Health

    humanoid.HealthChanged:Connect(function(health)
        local damage = lastHealth - health
        lastHealth = health

        if damage <= 0 then return end

        local now = tick()
        local timeSinceLastHit = now - bot.enemyAbilities.lastHitTime

        -- Double-hit detection: if two hits land within 0.3s, it's a fireball
        if timeSinceLastHit <= bot.enemyAbilities.hitWindow then
            print("[Bot] Fireball detected! Dodging...")
            bot.enemyAbilities.fireballIncoming = true
        else
            -- Single hit = Q attack
            print("[Bot] Q attack detected")
        end

        bot.enemyAbilities.lastHitTime = now
        bot.enemyAbilities.lastHitCount = 1
    end)
end

-- ===== INIT =====
print("[Bot] Loaded! Controls: L=Learn, K=Toggle, O=Difficulty, M=Memory")
print("[Bot] Sprint auto-enabled. Give bot 7k account, fight on 6k account for practice.")

-- Setup hit detection
setupHitDetection()

-- Auto-enable sprint at start
wait(0.5)
botToggleSprint(true)

spawn(function()
    while true do
        botTick()
        wait(0.05) -- 20 Hz tick rate
    end
end)

-- Handle respawn
player.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp = char:WaitForChild("HumanoidRootPart")
    bot.cooldowns.q.last = 0
    bot.cooldowns.fireball.last = 0
    bot.sprint.active = false -- Reset sprint on respawn
    wait(0.1)
    botToggleSprint(true) -- Auto-enable sprint
end)
