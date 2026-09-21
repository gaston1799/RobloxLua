-- Improved PVP Bot - Human-like Movement
-- Strafes left/right, predicts movement, not just tailgating

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

local bot = {
    enabled = true,
    difficulty = 2,
    targetName = "PuRgE_aLt20",

    cooldowns = {
        q = { last = 0, duration = 0.65 },
        fireball = { last = 0, duration = 1.4 },
    },

    combat = {
        target = nil,
        targetDistance = 0,
        lastPos = nil,
    },

    abilities = {
        fireballIncoming = false,
    },

    sprint = { active = false },

    movement = {
        strafeDir = 1, -- 1 = right, -1 = left
        strafeTimer = 0,
        strafeInterval = 2, -- Change strafe direction every 2s
    }
}

-- ===== INTENT CLIENT =====
local function post(payload)
    payload = payload or {}
    local url = "http://127.0.0.1:3636/intent"
    local body = HttpService:JSONEncode(payload)

    local requester = (syn and syn.request) or http_request or request
    local ok

    if requester then
        ok = pcall(requester, {
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    else
        ok = pcall(HttpService.PostAsync, HttpService, url, body, Enum.HttpContentType.ApplicationJson, false)
    end

    return ok
end

local function tapKey(key)
    return post({ event = "press", key = string.upper(key) })
end

local function holdKey(key, down)
    return post({ event = down and "keydown" or "keyup", key = string.upper(key) })
end

local function releaseAll()
    holdKey("W", false)
    holdKey("S", false)
    holdKey("A", false)
    holdKey("D", false)
end

local function toggleSprint(on)
    if on and not bot.sprint.active then
        tapKey("LSHIFT")
        bot.sprint.active = true
    elseif not on and bot.sprint.active then
        tapKey("LSHIFT")
        bot.sprint.active = false
    end
end

-- ===== TARGETING =====
local function findTarget()
    for _, p in ipairs(Players:GetPlayers()) do
        if (p.Name == bot.targetName or p.DisplayName == bot.targetName) and p.Character and p.Character.Parent then
            return p.Character
        end
    end
    return nil
end

local function getDistance(targetChar)
    if not (char and targetChar and char.Parent and targetChar.Parent) then return math.huge end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then return math.huge end

    return (myRoot.Position - targetRoot.Position).Magnitude
end

local function getTargetDirection(targetChar)
    if not (char and targetChar and char.Parent and targetChar.Parent) then
        return Vector3.new(0, 0, 1), Vector3.new(0, 0, 0)
    end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then
        return Vector3.new(0, 0, 1), Vector3.new(0, 0, 0)
    end

    local toTarget = (targetRoot.Position - myRoot.Position)
    return toTarget.Unit, toTarget
end

-- ===== HIT DETECTION =====
local function setupHitDetection()
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local lastHealth = humanoid.Health
    local lastHitTime = 0

    humanoid.HealthChanged:Connect(function(health)
        local damage = lastHealth - health
        lastHealth = health

        if damage <= 0 then return end

        local now = tick()
        local timeSinceLastHit = now - lastHitTime

        if timeSinceLastHit <= 0.3 then
            print("[Bot] Fireball detected!")
            bot.abilities.fireballIncoming = true
        end

        lastHitTime = now
    end)
end

-- ===== ABILITIES =====
local function canCast(ability)
    local cd = bot.cooldowns[ability]
    return cd and (tick() - cd.last) >= cd.duration
end

local function recordCast(ability)
    local cd = bot.cooldowns[ability]
    if cd then cd.last = tick() end
end

local function botQ()
    if not canCast("q") then return false end

    local target = bot.combat.target
    if not target then return false end

    local dist = getDistance(target)
    if dist > 15 then return false end

    tapKey("Q")
    recordCast("q")
    return true
end

local function botFireball()
    if not canCast("fireball") then return false end

    local target = bot.combat.target
    if not target then return false end

    local dist = getDistance(target)
    if dist > 150 or dist < 15 then return false end

    tapKey("E")
    recordCast("fireball")
    return true
end

-- ===== MOVEMENT - HUMAN LIKE =====
local function botMovement()
    local target = bot.combat.target
    if not target then
        releaseAll()
        toggleSprint(false)
        return
    end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local targetRoot = target:FindFirstChild("HumanoidRootPart")

    if not (myRoot and targetRoot) then return end

    local dist = getDistance(target)
    local qReady = canCast("q")
    local fireballReady = canCast("fireball")

    local dirToTarget, vectorToTarget = getTargetDirection(target)

    -- Calculate lateral offset (predict where target is moving)
    local myRight = myRoot.CFrame.RightVector
    local lateralComponent = vectorToTarget:Dot(myRight)

    -- Update strafe timing
    bot.movement.strafeTimer = bot.movement.strafeTimer + 0.05
    if bot.movement.strafeTimer >= bot.movement.strafeInterval then
        bot.movement.strafeDir = bot.movement.strafeDir * -1 -- Switch strafe direction
        bot.movement.strafeTimer = 0
    end

    -- ===== AGGRESSIVE PHASE: Move towards target =====
    if qReady or fireballReady then
        if dist > 20 then
            -- Only use W when approaching, not diagonal rushing
            holdKey("W", true)
            holdKey("S", false)

            -- Strafe left/right based on target position or predict lateral movement
            if lateralComponent > 5 then
                holdKey("D", true)
                holdKey("A", false)
            elseif lateralComponent < -5 then
                holdKey("A", true)
                holdKey("D", false)
            else
                -- If centered, strafe randomly for positioning
                if bot.movement.strafeDir > 0 then
                    holdKey("D", true)
                    holdKey("A", false)
                else
                    holdKey("A", true)
                    holdKey("D", false)
                end
            end

            toggleSprint(true)
        else
            -- In range, stop moving forward, just circle
            holdKey("W", false)
            holdKey("S", false)

            if bot.movement.strafeDir > 0 then
                holdKey("D", true)
                holdKey("A", false)
            else
                holdKey("A", true)
                holdKey("D", false)
            end

            toggleSprint(false)
        end
    else
        -- ===== COOLDOWN PHASE: Maintain distance with strafing =====
        local preferredDist = 50

        if dist < preferredDist - 15 then
            -- Too close, back away
            holdKey("W", false)
            holdKey("S", true)
            holdKey("A", false)
            holdKey("D", false)
            toggleSprint(true)
        elseif dist > preferredDist + 15 then
            -- Too far, move closer (only forward, not diagonal)
            holdKey("W", true)
            holdKey("S", false)

            -- Light strafing while approaching
            if lateralComponent > 3 then
                holdKey("D", true)
                holdKey("A", false)
            elseif lateralComponent < -3 then
                holdKey("A", true)
                holdKey("D", false)
            else
                holdKey("A", false)
                holdKey("D", false)
            end

            toggleSprint(true)
        else
            -- Good distance, circle strafe
            holdKey("W", false)
            holdKey("S", false)

            if bot.movement.strafeDir > 0 then
                holdKey("D", true)
                holdKey("A", false)
            else
                holdKey("A", true)
                holdKey("D", false)
            end

            toggleSprint(false)
        end
    end
end

-- ===== DODGE =====
local function botDodge()
    holdKey("A", true)
    spawn(function()
        wait(0.15)
        holdKey("A", false)
    end)

    bot.abilities.fireballIncoming = false
end

-- ===== MAIN LOOP =====
local function botTick()
    if not bot.enabled or not char or not char.Parent then return end

    -- Priority 1: Dodge fireball
    if bot.abilities.fireballIncoming then
        botDodge()
        return
    end

    -- Find target
    bot.combat.target = findTarget()
    bot.combat.targetDistance = bot.combat.target and getDistance(bot.combat.target) or 0

    if not bot.combat.target then return end

    -- Priority 2: Attack
    botQ()
    botFireball()

    -- Priority 3: Movement
    botMovement()
end

-- ===== CONTROLS =====
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.K then
        bot.enabled = not bot.enabled
        if not bot.enabled then releaseAll() end
        print("[Bot] Enabled: " .. tostring(bot.enabled))
    end

    if input.KeyCode == Enum.KeyCode.O then
        bot.difficulty = (bot.difficulty % 3) + 1
        print("[Bot] Difficulty: " .. bot.difficulty)
    end
end)

-- ===== INIT =====
print("[Bot] Improved PVP Bot Loaded!")
print("[Bot] Human-like strafing movement")
print("[Bot] K=Toggle, O=Difficulty")

setupHitDetection()

wait(0.5)
toggleSprint(true)

spawn(function()
    while true do
        botTick()
        wait(0.05)
    end
end)

-- Handle respawn
player.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp = char:WaitForChild("HumanoidRootPart")
    bot.cooldowns.q.last = 0
    bot.cooldowns.fireball.last = 0
    bot.sprint.active = false
    releaseAll()
    wait(0.1)
    toggleSprint(true)
    setupHitDetection()
end)
