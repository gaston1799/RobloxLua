--[[
    Animal Simulator PVP Bot - Intent-Based (Legitimate)
    - WASD intents for movement (no teleporting)
    - Hitbox collision detection for attacks
    - Intent key Q on hit
    - Auto-sprint support
    - Auto re-engage after death
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local INTENT_SERVER = "http://127.0.0.1:3636/intent"
local COLLISION_RANGE = 6 -- studs for melee hitbox
local POLL_RATE = 0.1

-- Bot State
local BotState = {
    enabled = false,
    autoSprintEnabled = false,
    autoReengageEnabled = false,
    selectedTarget = nil,
    lastTarget = nil,
    inCombat = false,
    currentMovementKeys = {},
}

-- Movement state tracking
local MovementState = {
    pressedKeys = {w = false, a = false, s = false, d = false},
}

-- Collision hitbox for bot
local function getBotHitbox()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return {
        pos = root.Position,
        size = Vector3.new(3, 5, 3),
    }
end

-- Get target hitbox
local function getTargetHitbox(player)
    if not player or not player.Character then return nil end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return {
        pos = root.Position,
        size = Vector3.new(3, 5, 3),
    }
end

-- AABB collision detection
local function checkCollision(box1, box2)
    if not box1 or not box2 then return false end
    local p1, s1 = box1.pos, box1.size
    local p2, s2 = box2.pos, box2.size

    local min1 = p1 - s1/2
    local max1 = p1 + s1/2
    local min2 = p2 - s2/2
    local max2 = p2 + s2/2

    return min1.X < max2.X and max1.X > min2.X and
           min1.Y < max2.Y and max1.Y > min2.Y and
           min1.Z < max2.Z and max1.Z > min2.Z
end

-- Distance check
local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

-- Send intent to server
local function sendIntent(key, state)
    local payload = {
        key = key,
        state = state,
    }
    local json = game:GetService("HttpService"):JSONEncode(payload)
    local ok, err = pcall(function()
        game:HttpPost(INTENT_SERVER, json, Enum.HttpContentType.ApplicationJson)
    end)
    if not ok then
        warn("[Intent] Failed to send", key, state, ":", err)
    end
end

-- Press key via intent
local function pressKey(key)
    if not MovementState.pressedKeys[key] then
        MovementState.pressedKeys[key] = true
        sendIntent(key, "down")
    end
end

-- Release key via intent
local function releaseKey(key)
    if MovementState.pressedKeys[key] then
        MovementState.pressedKeys[key] = false
        sendIntent(key, "up")
    end
end

-- Release all keys
local function releaseAllKeys()
    for key, _ in pairs(MovementState.pressedKeys) do
        releaseKey(key)
    end
end

-- Press Q (attack) via intent
local function attackWithQ()
    sendIntent("q", "down")
    task.wait(0.05)
    sendIntent("q", "up")
end

-- Toggle sprint via Shift
local function setSprint(enabled)
    if enabled then
        sendIntent("lshift", "down")
    else
        sendIntent("lshift", "up")
    end
end

-- Get camera direction normalized
local function getCameraDirection()
    local camera = workspace.CurrentCamera
    if not camera then return Vector3.new(0, 0, -1) end
    return camera.CFrame.LookVector
end

-- Calculate WASD input based on target position relative to camera
local function calculateMovementInput(targetPos)
    local char = LocalPlayer.Character
    if not char then return {w=false, a=false, s=false, d=false} end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return {w=false, a=false, s=false, d=false} end

    local dirToTarget = (targetPos - root.Position).Unit
    local camDir = getCameraDirection()

    -- Get camera right and forward vectors
    local camRight = Vector3.new(camDir.Z, 0, -camDir.X).Unit
    local camForward = Vector3.new(-camDir.Z, 0, camDir.X).Unit

    -- Project target direction onto camera axes
    local forwardDot = dirToTarget:Dot(camForward)
    local rightDot = dirToTarget:Dot(camRight)

    local input = {w=false, a=false, s=false, d=false}

    -- Forward/backward based on camera
    if forwardDot > 0.3 then
        input.w = true
    elseif forwardDot < -0.3 then
        input.s = true
    end

    -- Left/right based on camera
    if rightDot > 0.3 then
        input.d = true
    elseif rightDot < -0.3 then
        input.a = true
    end

    return input
end

-- Apply movement input
local function applyMovement(input)
    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

-- Find closest player
local function findClosestPlayer()
    local closest = nil
    local closestDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if humanoid and humanoid.Health > 0 and root then
                local dist = getDistance(root.Position, LocalPlayer.Character.HumanoidRootPart.Position)
                if dist < closestDist then
                    closestDist = dist
                    closest = player
                end
            end
        end
    end

    return closest
end

-- Main bot loop
local function botLoop()
    while BotState.enabled do
        local char = LocalPlayer.Character
        if not char then
            releaseAllKeys()
            task.wait(0.5)
            continue
        end

        local root = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChildOfClass("Humanoid")

        if not root or not humanoid or humanoid.Health <= 0 then
            releaseAllKeys()
            BotState.inCombat = false
            task.wait(POLL_RATE)
            continue
        end

        -- Get target
        local target = BotState.selectedTarget or findClosestPlayer()

        if target and target.Character then
            local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")

            if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
                BotState.lastTarget = target
                BotState.inCombat = true

                -- Check collision
                local botBox = getBotHitbox()
                local targetBox = getTargetHitbox(target)
                local colliding = checkCollision(botBox, targetBox)

                if colliding then
                    -- In range - attack!
                    releaseAllKeys()
                    attackWithQ()

                    -- Sprint if enabled
                    if BotState.autoSprintEnabled then
                        setSprint(true)
                    end
                else
                    -- Out of range - move toward target
                    local moveInput = calculateMovementInput(targetRoot.Position)
                    applyMovement(moveInput)

                    -- Sprint if enabled
                    if BotState.autoSprintEnabled then
                        setSprint(true)
                    end
                end
            else
                releaseAllKeys()
                if BotState.autoReengageEnabled and BotState.lastTarget and BotState.lastTarget.Character then
                    -- Reengage after death - already handled by loop
                    task.wait(0.5)
                end
            end
        else
            releaseAllKeys()
            if BotState.inCombat and BotState.autoReengageEnabled and BotState.lastTarget then
                BotState.selectedTarget = BotState.lastTarget
            else
                BotState.inCombat = false
            end
        end

        task.wait(POLL_RATE)
    end

    releaseAllKeys()
end

-- Start bot
local function startBot()
    if BotState.enabled then return end
    BotState.enabled = true
    task.spawn(botLoop)
    print("[PVP Bot] Started")
end

-- Stop bot
local function stopBot()
    BotState.enabled = false
    releaseAllKeys()
    print("[PVP Bot] Stopped")
end

-- Export for UI control
_G.PVPBot = {
    state = BotState,
    start = startBot,
    stop = stopBot,
    toggle = function()
        if BotState.enabled then stopBot() else startBot() end
    end,
    setAutoSprint = function(val) BotState.autoSprintEnabled = val end,
    setAutoReengage = function(val) BotState.autoReengageEnabled = val end,
    setTarget = function(player) BotState.selectedTarget = player end,
}

print("[PVP Bot] Loaded - Ready for UI integration")
