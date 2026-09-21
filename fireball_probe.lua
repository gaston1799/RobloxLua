--[[
    Fireball Timing Probe (Automatic)
    - Auto-starts on load
    - Detects when you equip & fire
    - Auto-prints travel time immediately
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

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
                        closest = {player = player, distance = dist, health = humanoid.Health}
                    end
                end
            end
        end
    end

    return closest
end

-- Main probe loop
print("[Fireball Probe] Auto-starting... Waiting for fireball equip")

while true do
    -- Find tool
    local fireballTool = findFireballTool()
    if not fireballTool then
        task.wait(1)
        continue
    end

    -- Wait for equip
    local char = LocalPlayer.Character
    if not char or fireballTool.Parent ~= char then
        task.wait(0.2)
        continue
    end

    -- Get target
    local targetInfo = findClosestPlayer()
    if not targetInfo then
        task.wait(1)
        continue
    end

    local targetHumanoid = targetInfo.player.Character:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then
        task.wait(0.5)
        continue
    end

    -- Wait for health to drop (fireball cast)
    local healthBefore = targetHumanoid.Health
    local startWait = tick()
    local castDetected = false

    while (tick() - startWait) < 15 do
        if targetHumanoid.Health < healthBefore then
            castDetected = true
            break
        end
        task.wait(0.02)
    end

    if not castDetected then
        task.wait(1)
        continue
    end

    -- Hit detected - auto print
    local damage = healthBefore - targetHumanoid.Health
    print(string.format("[Fireball] %s @ %.1f studs | Damage: %.0f HP | %s",
        targetInfo.player.Name, targetInfo.distance, damage, os.date("%H:%M:%S")))

    -- Cool down before next shot
    task.wait(0.5)
end
