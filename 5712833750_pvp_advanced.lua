--[[
    Advanced PVP Bot - State Machine
    States: Approaching → Attacking → Fireball Baiting

    Strategy:
    - Non-headon approach with movement interception
    - Fireball baiting (strafing at safe distance during cooldown)
    - Double-hit timing (Q + Fireball simultaneous)
    - Never disengage - stay in combat radius
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local INTENT_SERVER = "http://127.0.0.1:3636/intent"

-- Bot Config
local Config = {
    melee_range = 6,           -- studs to attack
    combat_radius = 25,        -- studs to stay within
    q_cooldown = 0.65,         -- seconds
    fireball_cooldown = 1.4,   -- seconds
    approach_speed = "normal", -- sprint or normal
}

-- Bot State
local BotState = {
    enabled = false,
    current_state = "idle",    -- idle, approaching, attacking, baiting
    target = nil,
    last_q_time = 0,
    last_fireball_time = 0,
    movement_keys = {w=false, a=false, s=false, d=false},
}

-- ===== UTILITY FUNCTIONS =====

local function sendIntent(key, state)
    local payload = {key = key, state = state}
    local json = game:GetService("HttpService"):JSONEncode(payload)
    pcall(function()
        game:HttpPost(INTENT_SERVER, json, Enum.HttpContentType.ApplicationJson)
    end)
end

local function pressKey(key)
    if not BotState.movement_keys[key] then
        BotState.movement_keys[key] = true
        sendIntent(key, "down")
    end
end

local function releaseKey(key)
    if BotState.movement_keys[key] then
        BotState.movement_keys[key] = false
        sendIntent(key, "up")
    end
end

local function releaseAllKeys()
    for key in pairs(BotState.movement_keys) do
        releaseKey(key)
    end
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function getDirection(from, to)
    return (to - from).Unit
end

local function getCameraDirection()
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
end

-- ===== MOVEMENT FUNCTIONS =====

local function moveTowardWithInterception(targetPos)
    -- Non-headon approach: intercept predicted movement
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    -- Get camera axes
    local camRight = Vector3.new(camDir.Z, 0, -camDir.X).Unit
    local camForward = Vector3.new(-camDir.Z, 0, camDir.X).Unit

    -- Project target direction onto camera axes
    local forwardDot = dirToTarget:Dot(camForward)
    local rightDot = dirToTarget:Dot(camRight)

    -- Approach with slight angle (not headon)
    -- Add some strafe to approach angle
    local input = {w=false, a=false, s=false, d=false}

    if forwardDot > 0.2 then
        input.w = true
    elseif forwardDot < -0.2 then
        input.s = true
    end

    -- Add perpendicular strafe for non-headon approach
    if rightDot > 0.1 then
        input.d = true
    elseif rightDot < -0.1 then
        input.a = true
    end

    -- Apply movement
    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

local function fireballBait(targetPos)
    -- Strafe around enemy at safe distance
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetPos)
    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    local camRight = Vector3.new(camDir.Z, 0, -camDir.X).Unit
    local camForward = Vector3.new(-camDir.Z, 0, camDir.X).Unit

    local rightDot = dirToTarget:Dot(camRight)

    local input = {w=false, a=false, s=false, d=false}

    -- If too close, back up
    if dist < Config.combat_radius * 0.6 then
        input.s = true
    -- If too far, move closer
    elseif dist > Config.combat_radius * 0.9 then
        local forwardDot = dirToTarget:Dot(camForward)
        if forwardDot > 0.1 then
            input.w = true
        end
    end

    -- Constant strafing to dodge incoming attacks
    local strafeLeft = math.sin(tick() * 3) > 0
    if strafeLeft then
        input.a = true
    else
        input.d = true
    end

    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

-- ===== ATTACK FUNCTIONS =====

local function attackWithQ()
    sendIntent("q", "down")
    task.wait(0.05)
    sendIntent("q", "up")
    BotState.last_q_time = tick()
end

local function fireball()
    -- Fire right before or simultaneous with Q for double-hit
    sendIntent("e", "down")
    task.wait(0.1)
    sendIntent("e", "up")
    BotState.last_fireball_time = tick()
end

local function doubleHit()
    -- Fire fireball and Q almost simultaneously
    fireball()
    task.wait(0.05)
    attackWithQ()
end

-- ===== STATE MACHINE =====

local function updateState()
    if not BotState.enabled or not BotState.target then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local targetChar = BotState.target.Character
    if not targetChar then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetRoot.Position)
    local qReady = (tick() - BotState.last_q_time) > Config.q_cooldown
    local fireballReady = (tick() - BotState.last_fireball_time) > Config.fireball_cooldown

    -- ===== STATE: APPROACHING =====
    if qReady and dist > Config.melee_range then
        BotState.current_state = "approaching"
        moveTowardWithInterception(targetRoot.Position)

    -- ===== STATE: ATTACKING =====
    elseif qReady and dist <= Config.melee_range then
        BotState.current_state = "attacking"
        releaseAllKeys() -- Stop moving for precise attack

        -- Double-hit if fireball is also ready
        if fireballReady then
            doubleHit()
        else
            attackWithQ()
        end

    -- ===== STATE: FIREBALL BAITING =====
    else
        BotState.current_state = "baiting"
        -- Stay in combat radius, strafe to dodge incoming attacks
        if dist > Config.combat_radius then
            -- Move closer if too far
            moveTowardWithInterception(targetRoot.Position)
        else
            -- Strafe and dodge
            fireballBait(targetRoot.Position)
        end
    end
end

-- ===== MAIN LOOP =====

local loop
loop = RunService.Heartbeat:Connect(function()
    if not BotState.enabled then return end
    updateState()
end)

-- ===== EXPORTS =====

_G.AdvancedPVPBot = {
    state = BotState,
    config = Config,

    start = function()
        if BotState.enabled then return end
        BotState.enabled = true
        print("[Advanced PVP Bot] Started")
    end,

    stop = function()
        BotState.enabled = false
        releaseAllKeys()
        print("[Advanced PVP Bot] Stopped")
    end,

    toggle = function()
        if BotState.enabled then _G.AdvancedPVPBot.stop() else _G.AdvancedPVPBot.start() end
    end,

    setTarget = function(player)
        BotState.target = player
        if player then
            print("[Advanced PVP Bot] Target:", player.Name)
        end
    end,

    setAutoSprint = function(enabled)
        Config.approach_speed = enabled and "sprint" or "normal"
    end,

    setState = function(state)
        BotState.current_state = state
        print("[Advanced PVP Bot] State:", state)
    end,

    getState = function()
        return BotState.current_state
    end,
}

print([[
[Advanced PVP Bot] Loaded!

States:
  idle      - Waiting for target
  approaching - Moving to enemy (non-headon intercept)
  attacking - In range, sending Q (double-hit if fireball ready)
  baiting   - Cooldown, strafing to dodge fireballs

Strategy:
  1. Approach with interception (not headon)
  2. Attack when in range (Q + Fireball simultaneous if ready)
  3. Bait fireballs during cooldown (strafe at safe distance)
  4. Never disengage (stay in combat radius)

API:
  _G.AdvancedPVPBot.start()
  _G.AdvancedPVPBot.stop()
  _G.AdvancedPVPBot.setTarget(player)
  _G.AdvancedPVPBot.getState()
]])
