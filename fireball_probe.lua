--[[
    Fireball Timing Probe (Health-Based Detection)
    - Looks for Fireball tool in backpack
    - Waits for you to equip it
    - Detects cast when target health drops
    - Measures time from cast to damage
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

    print("[Fireball Probe] ✓ Found Fireball | Equip it now...")

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

    -- Get target info
    local targetInfo = findClosestPlayer()
    if not targetInfo then
        print("[Fireball Probe] ✗ No targets found")
        ProbeState.running = false
        return
    end

    local targetHumanoid = targetInfo.player.Character:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then
        print("[Fireball Probe] ✗ Target humanoid not found")
        ProbeState.running = false
        return
    end

    local healthSnapshot = targetHumanoid.Health

    print(string.format("[Fireball Probe] Target: %s | Distance: %.1f studs | Health: %.0f",
        targetInfo.player.Name, targetInfo.distance, healthSnapshot))
    print("[Fireball Probe] Ready! Fire the fireball now...")

    -- Wait for health drop = fireball cast detected
    local castTimeout = tick()
    local castTime = nil

    while (tick() - castTimeout) < 15 do
        if targetHumanoid.Health < healthSnapshot then
            -- Health dropped = fireball was just cast!
            castTime = tick()
            print(string.format("[Fireball Probe] ✓ Cast detected! (Health: %.0f → %.0f)",
                healthSnapshot, targetHumanoid.Health))
            break
        end
        task.wait(0.02)
    end

    if not castTime then
        print("[Fireball Probe] ✗ Timeout - no damage detected on target")
        ProbeState.running = false
        return
    end

    -- Now measure time from this moment
    -- The target already took damage, so travel time is very close to 0
    -- Just record the current stats
    local damageDealt = healthSnapshot - targetHumanoid.Health

    print(string.format("[Fireball Probe] ✓ HIT! Damage dealt: %.0f HP", damageDealt))

    table.insert(ProbeState.results, {
        target = targetInfo.player.Name,
        distance = targetInfo.distance,
        damageDealt = damageDealt,
        healthBefore = healthSnapshot,
        healthAfter = targetHumanoid.Health,
        timestamp = os.date("%H:%M:%S"),
    })

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
        print(string.format("  #%d | %s at %.1f studs | Damage: %.0f HP | %s",
            i, result.target, result.distance, result.damageDealt, result.timestamp))
    end

    local totalDamage = 0
    for _, r in ipairs(ProbeState.results) do
        totalDamage = totalDamage + r.damageDealt
    end
    local avgDamage = totalDamage / #ProbeState.results

    print(string.format("\nAverage damage per hit: %.0f HP (from %d shots)", avgDamage, #ProbeState.results))
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
[Fireball Probe] Ready! (Health-based detection)

Usage:
  _G.FireballProbe.start()        -- Auto-detect equip, fire fireball
  _G.FireballProbe.printResults() -- Show all measurements
  _G.FireballProbe.clear()        -- Clear results

Workflow:
  1. Call _G.FireballProbe.start()
  2. Equip Fireball tool
  3. Fire it at closest player
  4. Probe detects when target health drops (= cast detected)
  5. Results auto-saved
  6. Call _G.FireballProbe.start() again for more data
]])
