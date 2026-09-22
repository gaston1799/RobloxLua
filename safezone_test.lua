--[[
    Safe Zone Test
    Press P to check if you're in safe zone
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Hardcoded safe zone (same as main script)
local SAFE_ZONE_CORNERS = {
    corner1 = {x = -114.77, z = 403.65},
    corner2 = {x = -46.92, z = 588.14},
    corner3 = {x = -276.40, z = 672.85},
    corner4 = {x = -344.77, z = 486.62},
}

local function isInsideSafeZone(position)
    local minX = math.min(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local maxX = math.max(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local minZ = math.min(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)
    local maxZ = math.max(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)

    return position.X >= minX and position.X <= maxX and
           position.Z >= minZ and position.Z <= maxZ
end

print("[SafeZone Test] Ready! Press P to check position")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.P then
        local char = LocalPlayer.Character
        if not char then
            print("[SafeZone Test] No character")
            return
        end

        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then
            print("[SafeZone Test] No root part")
            return
        end

        local pos = root.Position
        local inSafeZone = isInsideSafeZone(pos)

        print("\n" .. string.rep("=", 60))
        print("[SafeZone Test] Position Check")
        print(string.rep("=", 60))
        print("X: " .. string.format("%.2f", pos.X))
        print("Y: " .. string.format("%.2f", pos.Y))
        print("Z: " .. string.format("%.2f", pos.Z))
        print("")
        print("Safe Zone Bounds:")
        print("  X: -344.77 to -46.92")
        print("  Z: 403.65 to 672.85")
        print("")
        if inSafeZone then
            print("✓ YOU ARE IN SAFE ZONE (cannot PVP)")
        else
            print("✗ YOU ARE OUTSIDE SAFE ZONE (can PVP)")
        end
        print(string.rep("=", 60) .. "\n")
    end
end)
