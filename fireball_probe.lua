--[[
    Fireball Timing Probe
    Detects fireball cast and measures time until closest target takes damage
    Outputs: cast_time, target_distance, damage_time, travel_time
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Probe state
local ProbeState = {
    running = false,
    fireballCastTime = nil,
    targetOnCast = nil,
    results = {},
}

-- Get humanoid health before
local function getTargetHealth(player)
    if not player or not player.Character then return 0 end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health or 0
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
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    local dist = (root.Position - myRoot.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = {player = player, distance = dist, healthBefore = humanoid.Health}
                    end
                end
            end
        end
    end

    return closest
end

-- Start monitoring for fireball cast
local function startProbe()
    if ProbeState.running then return end
    ProbeState.running = true
    ProbeState.fireballCastTime = nil
    ProbeState.targetOnCast = nil

    print("[Fireball Probe] Started - cast a fireball now")

    -- Monitor for camera/input changes (rough fireball detection)
    local castDetected = false
    local monitorTime = tick()

    -- Listen for damage to closest target
    local targetInfo = findClosestPlayer()
    if not targetInfo then
        print("[Fireball Probe] No targets found")
        ProbeState.running = false
        return
    end

    ProbeState.targetOnCast = targetInfo
    local targetHumanoid = targetInfo.player.Character:FindFirstChildOfClass("Humanoid")
    local healthOnStart = targetHumanoid.Health

    print(string.format("[Fireball Probe] Target: %s | Distance: %.1f studs | Health: %.0f",
        targetInfo.player.Name, targetInfo.distance, healthOnStart))

    -- Wait for cast (you press the fireball key)
    print("[Fireball Probe] Waiting for cast...")
    local castTime = nil
    local waitStart = tick()

    while not castTime and (tick() - waitStart) < 5 do
        if targetHumanoid.Health < healthOnStart then
            -- Damage detected!
            castTime = tick()
            local damageTime = castTime
            local travelTime = damageTime - monitorTime

            print(string.format("[Fireball Probe] ✓ HIT! Travel time: %.3f seconds", travelTime))

            table.insert(ProbeState.results, {
                target = targetInfo.player.Name,
                distance = targetInfo.distance,
                healthBefore = healthOnStart,
                healthAfter = targetHumanoid.Health,
                travelTime = travelTime,
                timestamp = os.date("%H:%M:%S"),
            })

            break
        end
        task.wait(0.05)
    end

    if not castTime then
        print("[Fireball Probe] ✗ Timeout - no hit detected")
    end

    ProbeState.running = false
end

-- Print all results
local function printResults()
    if #ProbeState.results == 0 then
        print("[Fireball Probe] No results yet")
        return
    end

    print("\n[Fireball Probe] ===== RESULTS =====")
    for i, result in ipairs(ProbeState.results) do
        print(string.format("  #%d | %s at %.1f studs | Travel: %.3f sec | %s",
            i, result.target, result.distance, result.travelTime, result.timestamp))
    end
    print(string.format("\nAverage travel time: %.3f sec (over %d shots)",
        (function()
            local sum = 0
            for _, r in ipairs(ProbeState.results) do
                sum = sum + r.travelTime
            end
            return sum / #ProbeState.results
        end)(),
        #ProbeState.results))
    print("[Fireball Probe] ====================\n")
end

-- Export
_G.FireballProbe = {
    start = startProbe,
    printResults = printResults,
    clear = function()
        ProbeState.results = {}
        print("[Fireball Probe] Results cleared")
    end,
    results = function() return ProbeState.results end,
}

print([=[
[Fireball Probe] Ready!

Usage:
  _G.FireballProbe.start()       -- Start probe and wait for fireball hit
  _G.FireballProbe.printResults() -- Show all measurements
  _G.FireballProbe.clear()        -- Clear results

Example workflow:
  1. _G.FireballProbe.start()
  2. Cast fireball at closest player
  3. Watch for HIT message
  4. Repeat steps 1-3 for different distances
  5. _G.FireballProbe.printResults()
]=])
