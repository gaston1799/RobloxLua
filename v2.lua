-- Adaptive PVP Bot with Learning Toggle
-- Uses IntentClient for legit inputs, MeleeHitbox for collision detection
-- Sends HTTP requests to Python intent server

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Bot Config
local bot = {
    enabled = true,
    learning = false,
    difficulty = 1, -- 1-3 (affects reaction time)

    -- IntentClient connection
    intent = {
        url = "http://127.0.0.1:3636/intent",
        releaseUrl = "http://127.0.0.1:3636/simulator/release",
        heldKeys = {},
    },

    -- Cooldowns (from your game)
    stats = {
        qCooldown = 0.65,
        fireballCooldown = 1.4,
        lastQTime = 0,
        lastFireballTime = 0,
    },

    -- Learning memory
    memory = {
        playerQTimestamps = {},      -- when player Q attacks
        playerFireballAngles = {},   -- aim angles of fireballs
        playerDodgeDirections = {},  -- dodge patterns
        playerPositions = {},        -- position tracking
    },

    -- Combat state
    state = {
        targetPosition = nil,
        targetRoot = nil,
        incomingFireball = nil,
        lastDodgeTime = 0,
    },
}

-- ===== INTENT CLIENT (HTTP to Python Server) =====
local function makeRequest(method, event, payload)
    if not payload then payload = {} end
    payload.event = event

    local body = HttpService:JSONEncode(payload)
    local requester = (syn and syn.request) or http_request or request

    local ok, response
    if requester then
        ok, response = pcall(requester, {
            Url = bot.intent.url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    else
        ok, response = pcall(HttpService.PostAsync, HttpService, bot.intent.url, body, Enum.HttpContentType.ApplicationJson, false)
    end

    return ok and response
end

local function botTapKey(key)
    return makeRequest("POST", "press", { key = string.upper(tostring(key)) })
end

local function botSetKey(key, down)
    key = string.upper(tostring(key))
    return makeRequest("POST", down and "keydown" or "keyup", { key = key })
end

local function botMoveMouse(dx, dy)
    return makeRequest("POST", "mousemove", { mouseDx = dx or 0, mouseDy = dy or 0 })
end

-- ===== HIT DETECTION (Similar to MeleeHitbox) =====
local function checkCollision(char1, char2, padding)
    padding = padding or Vector3.new(1.5, 2, 1.5)

    local root1 = char1:FindFirstChild("HumanoidRootPart")
    local root2 = char2:FindFirstChild("HumanoidRootPart")

    if not (root1 and root2) then return false end

    local size1 = root1.Size * 0.5
    local hitboxSize = root2.Size + padding
    local size2 = hitboxSize * 0.5

    local delta = root1.Position - root2.Position

    return math.abs(delta.X) <= size1.X + size2.X
        and math.abs(delta.Y) <= size1.Y + size2.Y
        and math.abs(delta.Z) <= size1.Z + size2.Z
end

-- ===== PLAYER BEHAVIOR TRACKING =====
local function trackPlayerQ()
    if bot.learning then
        table.insert(bot.memory.playerQTimestamps, tick())

        if #bot.memory.playerQTimestamps > 30 then
            table.remove(bot.memory.playerQTimestamps, 1)
        end
    end
end

local function trackPlayerFireball(aimDirection)
    if bot.learning and aimDirection then
        local angle = math.atan2(aimDirection.Z, aimDirection.X)
        table.insert(bot.memory.playerFireballAngles, angle)

        if #bot.memory.playerFireballAngles > 20 then
            table.remove(bot.memory.playerFireballAngles, 1)
        end
    end
end

local function trackPlayerDodge(dodgeDirection)
    if bot.learning then
        table.insert(bot.memory.playerDodgeDirections, dodgeDirection)

        if #bot.memory.playerDodgeDirections > 15 then
            table.remove(bot.memory.playerDodgeDirections, 1)
        end
    end
end

-- ===== BOT ATTACK LOGIC =====
local function botAttackQ()
    local timeSinceLastQ = tick() - bot.stats.lastQTime

    if timeSinceLastQ < bot.stats.qCooldown then
        return false
    end

    -- Get target (find nearest player)
    local target = nil
    local closestDist = math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local targetRoot = p.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local dist = (humanoidRootPart.Position - targetRoot.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    target = p.Character
                end
            end
        end
    end

    if not target then return false end

    -- Check if in melee range
    if checkCollision(character, target, Vector3.new(1.5, 2, 1.5)) then
        if bot.learning then
            -- Dodge if fireball is coming (predict based on learned patterns)
            -- For now: simple evasion
        end

        bot.stats.lastQTime = tick()
        botTapKey("Q")
        trackPlayerQ()
        return true
    end

    return false
end

local function botAttackFireball()
    local timeSinceLastFireball = tick() - bot.stats.lastFireballTime

    if timeSinceLastFireball < bot.stats.fireballCooldown then
        return false
    end

    -- Find target
    local target = nil
    local closestDist = math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local targetRoot = p.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local dist = (humanoidRootPart.Position - targetRoot.Position).Magnitude
                if dist < closestDist and dist < 150 then -- Within fireball range
                    closestDist = dist
                    target = targetRoot
                end
            end
        end
    end

    if not target then return false end

    -- Calculate aim direction
    local direction = (target.Position - humanoidRootPart.Position).Unit

    -- When learning: predict where player aims and aim there
    -- Otherwise: random lead shots
    if bot.learning and #bot.memory.playerFireballAngles > 5 then
        local sum = 0
        for _, angle in ipairs(bot.memory.playerFireballAngles) do
            sum = sum + angle
        end
        local commonAngle = sum / #bot.memory.playerFireballAngles
        direction = Vector3.new(math.cos(commonAngle), 0, math.sin(commonAngle))
    end

    -- Move mouse to aim (simplified - adjust mouse x/y based on screen position)
    local screenPos = humanoidRootPart.Position + direction * 30
    botMoveMouse(math.random(-20, 20), math.random(-20, 20))

    bot.stats.lastFireballTime = tick()
    botTapKey("E") -- Fireball key
    trackPlayerFireball(direction)
    return true
end

-- ===== DODGE INCOMING ATTACKS =====
local function botDodge()
    local now = tick()
    if now - bot.state.lastDodgeTime < 0.5 then return false end

    -- Simple dodge: move away from center of arena
    local dodgeDir = humanoidRootPart.Position.Unit * -1
    botMoveMouse(
        math.random(-15, 15),
        math.random(-15, 15)
    )

    bot.state.lastDodgeTime = now
    trackPlayerDodge(dodgeDir)
    return true
end

-- ===== MAIN BOT LOOP =====
local function botTick()
    if not bot.enabled or not character or not character.Parent then return end

    local target = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then target = p.Character break end
    end

    if not target then return end

    -- Combat decision tree
    botDodge()
    botAttackQ()
    botAttackFireball()
end

-- ===== KEYBOARD CONTROLS =====
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.L then
        bot.learning = not bot.learning
        print("[PVP Bot] Learning: " .. tostring(bot.learning))
    end

    if input.KeyCode == Enum.KeyCode.K then
        bot.enabled = not bot.enabled
        print("[PVP Bot] Enabled: " .. tostring(bot.enabled))
    end

    if input.KeyCode == Enum.KeyCode.O then
        bot.difficulty = (bot.difficulty % 3) + 1
        print("[PVP Bot] Difficulty: " .. bot.difficulty)
    end

    if input.KeyCode == Enum.KeyCode.M then
        print("[PVP Bot] Memory:")
        print("  Q Attacks: " .. #bot.memory.playerQTimestamps)
        print("  Fireball Aims: " .. #bot.memory.playerFireballAngles)
        print("  Dodge Patterns: " .. #bot.memory.playerDodgeDirections)
    end
end)

-- ===== INITIALIZE =====
print("[PVP Bot] Loaded!")
print("L = Toggle Learning | K = Toggle Bot | O = Cycle Difficulty | M = Show Memory")

spawn(function()
    while true do
        botTick()
        wait(0.05) -- Bot tick rate (20 Hz)
    end
end)

-- Handle respawn
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    bot.stats.lastQTime = 0
    bot.stats.lastFireballTime = 0
end)
