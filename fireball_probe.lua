--[[
    Fireball Timing Probe (Smart Detection)
    - Looks for "Fireball" tool in backpack
    - Waits for you to equip it
    - Detects when fired (tool unequipped)
    - Measures time from fire to closest target taking damage
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Probe state
local ProbeState = {
    running = false,
    results = {},
}

-- Find fireball in backpack
local function findFireballTool()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return nil end

    for _, item in ipairs(backpack:GetChildren()) do
        if item.Name == "Fireball" or item.Name:lower():match("fireball") then
            return item
        end
    end
    return nil
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

-- Start probe
local function startProbe()
    if ProbeState.running then
        print("[Fireball Probe] Already running!")
        return
    end
    ProbeState.running = true

    print("[Fireball Probe] Searching for Fireball tool...")
    task.wait(0.5)

    -- Find fireball tool
    local fireballTool = findFireballTool()
    if not fireballTool then
        print("[Fireball Probe] ✗ Fireball tool not found in backpack")
        ProbeState.running = false
        return
    end

    print("[Fireball Probe] ✓ Found Fireball | Waiting for you to equip it...")

    -- Wait for equip (tool moves to character)
    local equipTimeout = tick()
    while (tick() - equipTimeout) < 30 do
        local char = LocalPlayer.Character
        if char and fireballTool.Parent == char then
            print("[Fireball Probe] ✓ Fireball equipped!")
            break
        end
        task.wait(0.1)
    end

    local char = LocalPlayer.Character
    if not char or fireballTool.Parent ~= char then
        print("[Fireball Probe] ✗ Timeout waiting for equip")
        ProbeState.running = false
        return
    end

    -- Get target info before fire
    local targetInfo = findClosestPlayer()
    if not targetInfo then
        print("[Fireball Probe] ✗ No targets found")
        ProbeState.running = false
        return
    end

    print(string.format("[Fireball Probe] Target: %s | Distance: %.1f studs | Health: %.0f",
        targetInfo.player.Name, targetInfo.distance, targetInfo.healthBefore))
    print("[Fireball Probe] Watching for fire... (use fireball now)")

    -- Wait for fire (tool unequipped from character)
    local fireTimeout = tick()
    local fireTime = nil

    while (tick() - fireTimeout) < 10 do
        if fireballTool.Parent ~= char then
            -- Tool was unequipped - fireball fired!
            fireTime = tick()
            print("[Fireball Probe] ✓ Fireball fired! Measuring travel time...")
            break
        end
        task.wait(0.05)
    end

    if not fireTime then
        print("[Fireball Probe] ✗ Timeout - fireball not fired")
        ProbeState.running = false
        return
    end

    -- Monitor for damage on target
    local targetHumanoid = targetInfo.player.Character:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then
        print("[Fireball Probe] ✗ Target lost")
        ProbeState.running = false
        return
    end

    local healthOnFire = targetHumanoid.Health
    local hitTime = nil
    local hitTimeout = tick()

    while (tick() - hitTimeout) < 5 do
        if targetHumanoid.Health < healthOnFire then
            -- HIT!
            hitTime = tick()
            local travelTime = hitTime - fireTime
            local damageDealt = healthOnFire - targetHumanoid.Health

            print(string.format("[Fireball Probe] ✓ HIT! Travel: %.3f sec | Damage: %.0f HP",
                travelTime, damageDealt))

            table.insert(ProbeState.results, {
                target = targetInfo.player.Name,
                distance = targetInfo.distance,
                damageDealt = damageDealt,
                travelTime = travelTime,
                timestamp = os.date("%H:%M:%S"),
            })

            break
        end
        task.wait(0.05)
    end

    if not hitTime then
        print("[Fireball Probe] ✗ No hit detected (may have missed target)")
    end

    ProbeState.running = false
    print("[Fireball Probe] Ready for next shot!")
end

-- Print results
local function printResults()
    if #ProbeState.results == 0 then
        print("[Fireball Probe] No results yet")
        return
    end

    print("\n[Fireball Probe] ===== RESULTS =====")
    for i, result in ipairs(ProbeState.results) do
        print(string.format("  #%d | %s at %.1f studs | Travel: %.3f sec | Damage: %.0f | %s",
            i, result.target, result.distance, result.travelTime, result.damageDealt, result.timestamp))
    end

    local avgTravel = 0
    for _, r in ipairs(ProbeState.results) do
        avgTravel = avgTravel + r.travelTime
    end
    avgTravel = avgTravel / #ProbeState.results

    print(string.format("\nAverage travel time: %.3f sec (from %d shots)", avgTravel, #ProbeState.results))
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

print([[
[Fireball Probe] Ready! (Smart detection)

Usage:
  _G.FireballProbe.start()        -- Auto-detect fireball, wait for equip/fire
  _G.FireballProbe.printResults() -- Show all measurements
  _G.FireballProbe.clear()        -- Clear results

Workflow:
  1. Call _G.FireballProbe.start()
  2. Equip the Fireball tool
  3. Fire it at closest player
  4. Probe auto-measures travel time
  5. Call _G.FireballProbe.start() again for more samples
  6. _G.FireballProbe.printResults() to see average
]])
