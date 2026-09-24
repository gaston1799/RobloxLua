--[[
    Direct SafeZone Detector - Finds FightingZonePart by name
    No position checking needed - just direct lookup
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 70))
print("DIRECT SAFE ZONE DETECTOR")
print(string.rep("=", 70) .. "\n")

-- Find FightingZonePart directly
local safeZone = nil

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj.Name == "FightingZonePart" and obj:IsA("Part") then
        safeZone = obj
        break
    end
end

if not safeZone then
    print("[ERROR] FightingZonePart not found!")
    print("[TIP] It should be at: Workspace > FightingArea > FightingZonePart")
    print(string.rep("=", 70) .. "\n")
    return
end

print("[Found] FightingZonePart")
print("  Parent: " .. safeZone.Parent.Name)
print("  Size: " .. string.format("%.1f x %.1f x %.1f", safeZone.Size.X, safeZone.Size.Y, safeZone.Size.Z))
print("  Position: " .. string.format("(%.1f, %.1f, %.1f)", safeZone.Position.X, safeZone.Position.Y, safeZone.Position.Z))

-- Extract bounds
local pos = safeZone.Position
local size = safeZone.Size / 2

local minX = pos.X - size.X
local maxX = pos.X + size.X
local minY = pos.Y - size.Y
local maxY = pos.Y + size.Y
local minZ = pos.Z - size.Z
local maxZ = pos.Z + size.Z

local corner1 = {x = minX, z = minZ}
local corner2 = {x = maxX, z = minZ}
local corner3 = {x = maxX, z = maxZ}
local corner4 = {x = minX, z = maxZ}

print("\n" .. string.rep("=", 70))
print("SAFE ZONE CORNERS (Copy to script)")
print(string.rep("=", 70))
print([[
local SAFE_ZONE_CORNERS = {
    corner1 = {x = ]] .. string.format("%.2f", corner1.x) .. [[, z = ]] .. string.format("%.2f", corner1.z) .. [[},
    corner2 = {x = ]] .. string.format("%.2f", corner2.x) .. [[, z = ]] .. string.format("%.2f", corner2.z) .. [[},
    corner3 = {x = ]] .. string.format("%.2f", corner3.x) .. [[, z = ]] .. string.format("%.2f", corner3.z) .. [[},
    corner4 = {x = ]] .. string.format("%.2f", corner4.x) .. [[, z = ]] .. string.format("%.2f", corner4.z) .. [[},
}
]])
print(string.rep("=", 70) .. "\n")

-- Create visualization
print("[Visualizing] Creating blue box...")

local centerX = (minX + maxX) / 2
local centerY = (minY + maxY) / 2
local centerZ = (minZ + maxZ) / 2
local sizeX = maxX - minX
local sizeY = maxY - minY
local sizeZ = maxZ - minZ

local box = Instance.new("Part")
box.Name = "SafeZoneVisualization"
box.Shape = Enum.PartType.Block
box.Size = Vector3.new(sizeX, sizeY, sizeZ)
box.Color = Color3.fromRGB(0, 0, 255)
box.Material = Enum.Material.Neon
box.Transparency = 0.5
box.CanCollide = false
box.Anchored = true
box.TopSurface = Enum.SurfaceType.Smooth
box.BottomSurface = Enum.SurfaceType.Smooth
box.CFrame = safeZone.CFrame
box.Parent = workspace

print("[Done] Blue box shows safe zone bounds\n")
