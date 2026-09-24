--[[
    Safe Zone Auto-Detector
    Finds the red SafeZone building and extracts corner coordinates
    Run this once to get accurate coordinates
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 70))
print("SAFE ZONE AUTO-DETECTOR")
print(string.rep("=", 70) .. "\n")

-- Search for safezone building
local function findSafeZoneBuilding()
    print("[Searching] Looking for SafeZone building...")

    -- Method 1: Search by part name
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("safezone") or obj.Name:lower():find("safe zone") then
            print("[Found] " .. obj.ClassName .. ": " .. obj.Name)
            if obj:IsA("Model") then
                print("  └─ Type: Model")
                return obj
            elseif obj:IsA("Part") then
                print("  └─ Type: Part")
                return obj
            end
        end
    end

    -- Method 2: Search by red color (barn likely red)
    print("[Scanning] Looking for red buildings...")
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name ~= "Baseplate" then
            local primaryPart = obj.PrimaryPart
            if primaryPart and primaryPart.Color == Color3.fromRGB(255, 0, 0) then
                print("[Found Red Model] " .. obj.Name)
                return obj
            end
        end
    end

    return nil
end

local safeZone = findSafeZoneBuilding()

if not safeZone then
    print("\n[ERROR] Could not find SafeZone building!")
    print("[TIP] Try standing near it and running this again")
    print(string.rep("=", 70) .. "\n")
    return
end

print("\n[SafeZone Found] " .. safeZone.Name .. " (" .. safeZone.ClassName .. ")")

-- Extract bounds
local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge

local function getSizeInfo(obj)
    if obj:IsA("Part") then
        local pos = obj.Position
        local size = obj.Size / 2
        minX = math.min(minX, pos.X - size.X)
        maxX = math.max(maxX, pos.X + size.X)
        minY = math.min(minY, pos.Y - size.Y)
        maxY = math.max(maxY, pos.Y + size.Y)
        minZ = math.min(minZ, pos.Z - size.Z)
        maxZ = math.max(maxZ, pos.Z + size.Z)
    end
end

if safeZone:IsA("Model") then
    for _, part in ipairs(safeZone:GetDescendants()) do
        getSizeInfo(part)
    end
elseif safeZone:IsA("Part") then
    getSizeInfo(safeZone)
end

print("\n[Bounds Detected]")
print("  X: " .. string.format("%.2f", minX) .. " to " .. string.format("%.2f", maxX))
print("  Y: " .. string.format("%.2f", minY) .. " to " .. string.format("%.2f", maxY))
print("  Z: " .. string.format("%.2f", minZ) .. " to " .. string.format("%.2f", maxZ))

-- Calculate 4 corners at Y=0 (ground level, ignoring height)
local corner1 = {x = minX, z = minZ}
local corner2 = {x = maxX, z = minZ}
local corner3 = {x = maxX, z = maxZ}
local corner4 = {x = minX, z = maxZ}

print("\n" .. string.rep("=", 70))
print("DETECTED SAFE ZONE CORNERS (Copy this to script)")
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

print("[Visualizing] SafeZone bounds...")

-- Create semi-transparent box showing detected area
local centerX = (minX + maxX) / 2
local centerZ = (minZ + maxZ) / 2
local centerY = (minY + maxY) / 2

local sizeX = maxX - minX
local sizeZ = maxZ - minZ
local sizeY = maxY - minY

local box = Instance.new("Part")
box.Name = "DetectedSafeZoneBox"
box.Shape = Enum.PartType.Block
box.Size = Vector3.new(sizeX, sizeY, sizeZ)
box.Color = Color3.fromRGB(0, 0, 255)
box.Material = Enum.Material.Neon
box.Transparency = 0.5
box.CanCollide = false
box.CFrame = CFrame.new(centerX, centerY, centerZ)
box.Parent = workspace
print("  ✓ Blue semi-transparent box rendered")

-- Add green corner markers
for i, corner in ipairs({corner1, corner2, corner3, corner4}) do
    local marker = Instance.new("Part")
    marker.Name = "SafeZoneCorner" .. i
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(5, 5, 5)
    marker.Color = Color3.fromRGB(0, 255, 0)
    marker.Material = Enum.Material.Neon
    marker.CanCollide = false
    marker.CFrame = CFrame.new(corner.x, centerY, corner.z)
    marker.Parent = workspace
    print("  Corner " .. i .. ": X=" .. string.format("%.2f", corner.x) .. ", Z=" .. string.format("%.2f", corner.z))
end

print("\n[Done] Blue box + green corners show detected SafeZone area")
print("[Verify] Walk inside/outside the box - confirm you can't damage inside!")
print("[Next] Copy the coordinates above and update the script\n")
