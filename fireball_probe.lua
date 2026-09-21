--[[
    Fireball Timing Probe (Debug Version)
    - Shows what's happening at each step
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("[Fireball Probe] Starting debug version...")
print("[Fireball Probe] Your name:", LocalPlayer.Name)

-- Find fireball in backpack
local function findFireballTool()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then
        print("[Fireball Probe] ✗ No backpack found")
        return nil
    end

    print("[Fireball Probe] Backpack found, contents:")
    for _, item in ipairs(backpack:GetChildren()) do
        print("  -", item.Name, "(" .. item.ClassName .. ")")
    end

    for _, item in ipairs(backpack:GetChildren()) do
        if item.Name == "Fireball" or item.Name:lower():match("fireball") then
            print("[Fireball Probe] ✓ Found Fireball tool")
            return item
        end
    end

    print("[Fireball Probe] ✗ Fireball not found in backpack")
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
                        closest = {player = player, distance = dist, health = humanoid.Health}
                    end
                end
            end
        end
    end

    if closest then
        print(string.format("[Fireball Probe] ✓ Target: %s @ %.1f studs", closest.player.Name, closest.distance))
    else
        print("[Fireball Probe] ✗ No valid targets found")
    end

    return closest
end

-- Main probe loop
print("[Fireball Probe] ============ AUTO-LOOP STARTED ============")
print("[Fireball Probe] Waiting for you to equip Fireball tool...\n")

local shotCount = 0

while true do
    local fireballTool = findFireballTool()

    if fireballTool then
        local char = LocalPlayer.Character
        if char and fireballTool.Parent == char then
            print("[Fireball Probe] ✓✓✓ FIREBALL EQUIPPED - watching target...")

            -- Get target
            local targetInfo = findClosestPlayer()
            if targetInfo then
                local targetHumanoid = targetInfo.player.Character:FindFirstChildOfClass("Humanoid")
                if targetHumanoid then
                    local healthBefore = targetHumanoid.Health
                    print(string.format("[Fireball Probe] Target health before: %.0f", healthBefore))

                    -- Wait for health to drop
                    local startWait = tick()
                    while (tick() - startWait) < 10 do
                        local currentHealth = targetHumanoid.Health
                        if currentHealth < healthBefore then
                            local damage = healthBefore - currentHealth
                            shotCount = shotCount + 1
                            print(string.format("\n[FIREBALL HIT #%d] %s @ %.1f studs | Damage: %.0f HP | Time: %s\n",
                                shotCount, targetInfo.player.Name, targetInfo.distance, damage, os.date("%H:%M:%S")))

                            -- Wait for tool to unequip
                            task.wait(1)
                            break
                        end
                        task.wait(0.05)
                    end

                    print("[Fireball Probe] Waiting for unequip...\n")
                    while fireballTool.Parent == char do
                        task.wait(0.1)
                    end
                end
            end
        end
    end

    task.wait(0.5)
end
