--[[
    Safe Zone Auto-Detector - Player Position Based
    Finds SafeZone by filtering objects that contain player's current position
    Run this while standing INSIDE the safe zone
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 70))
print("SAFE ZONE AUTO-DETECTOR - Position Based Search")
print(string.rep("=", 70) .. "\n")

local char = LocalPlayer.Character
if not char then
    print("[ERROR] No character found")
    return
end

local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
if not humanoidRoot then
    print("[ERROR] No HumanoidRootPart found")
    return
end

local playerPos = humanoidRoot.Position
print("[Player Position] X=" .. string.format("%.2f", playerPos.X) .. " Y=" .. string.format("%.2f", playerPos.Y) .. " Z=" .. string.format("%.2f", playerPos.Z) .. "\n")

-- Function to check if point is inside part
local function isPointInPart(point, part)
    if not part:IsA("Part") then return false end
    local relPos = part.CFrame:VectorToObjectSpace(point)
    local size = part.Size / 2
    return math.abs(relPos.X) <= size.X and math.abs(relPos.Y) <= size.Y and math.abs(relPos.Z) <= size.Z
end

-- Find all parts that contain player position
local candidates = {}

print("[Searching] Finding objects that contain your position...\n")

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Part") then
        if isPointInPart(playerPos, obj) then
            table.insert(candidates, obj)
            print("[Contains You] " .. obj.Name .. " (" .. obj.Parent.Name .. ")")
        end
    end
end

if #candidates == 0 then
    print("\n[ERROR] No objects contain your position!")
    print("[TIP] Make sure you're standing INSIDE the safe zone building")
    print(string.rep("=", 70) .. "\n")
    return
end

print("\n[Found " .. #candidates .. " object(s) containing you]")
print("\n[Visualizing] Creating blue boxes...\n")

-- Visualize each candidate
local boxes = {}
for i, obj in ipairs(candidates) do
    local size = obj.Size
    local pos = obj.Position

    local box = Instance.new("Part")
    box.Name = "SafeZone_Candidate_" .. i
    box.Shape = Enum.PartType.Block
    box.Size = size
    box.Color = Color3.fromRGB(0, 0, 255)
    box.Material = Enum.Material.Neon
    box.Transparency = 0.5
    box.CanCollide = false
    box.CFrame = obj.CFrame
    box.Parent = workspace

    table.insert(boxes, box)

    print("  [" .. i .. "] " .. obj.Name)
    print("      Size: " .. string.format("%.0f x %.0f x %.0f", size.X, size.Y, size.Z))
    print("      Parent: " .. obj.Parent.Name)
end

print("\n[Next Steps]")
print("  - Blue boxes show objects containing your position")
print("  - Find the LARGEST box (likely the safe zone building)")
print("  - Check its Parent name in the list above")
print("  - That's your SafeZone building!\n")

-- Find the largest candidate (likely the actual building)
local largest = candidates[1]
for i = 2, #candidates do
    local vol1 = largest.Size.X * largest.Size.Y * largest.Size.Z
    local vol2 = candidates[i].Size.X * candidates[i].Size.Y * candidates[i].Size.Z
    if vol2 > vol1 then
        largest = candidates[i]
    end
end

print("[Best Candidate] " .. largest.Name)
print("  └─ Parent: " .. largest.Parent.Name)
print("  └─ Size: " .. string.format("%.0f x %.0f x %.0f", largest.Size.X, largest.Size.Y, largest.Size.Z))

-- Extract bounds from largest
local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge

local function processPart(part)
    if part:IsA("Part") then
        local pos = part.Position
        local size = part.Size / 2
        minX = math.min(minX, pos.X - size.X)
        maxX = math.max(maxX, pos.X + size.X)
        minY = math.min(minY, pos.Y - size.Y)
        maxY = math.max(maxY, pos.Y + size.Y)
        minZ = math.min(minZ, pos.Z - size.Z)
        maxZ = math.max(maxZ, pos.Z + size.Z)
    end
end

if largest.Parent:IsA("Model") then
    for _, part in ipairs(largest.Parent:GetDescendants()) do
        processPart(part)
    end
else
    processPart(largest)
end

local corner1 = {x = minX, z = minZ}
local corner2 = {x = maxX, z = minZ}
local corner3 = {x = maxX, z = maxZ}
local corner4 = {x = minX, z = maxZ}

print("\n" .. string.rep("=", 70))
print("DETECTED SAFE ZONE CORNERS (Copy to script)")
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
