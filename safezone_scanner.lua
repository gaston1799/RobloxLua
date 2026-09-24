--[[
    SafeZone Scanner - Visual Labeler
    Finds ALL parts containing "safezone" in name
    Shows transparent cube + GUI label with index and path
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 70))
print("SAFE ZONE SCANNER - Find All SafeZone Objects")
print(string.rep("=", 70) .. "\n")

-- Find all parts with "safezone" or "fightingzone" in name
local candidates = {}

print("[Searching] Finding safe zone parts...\n")

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Part") and (
        obj.Name:lower():find("safezone") or
        obj.Name:lower():find("safe zone") or
        obj.Name:lower():find("fightingzone") or
        obj.Name:lower():find("fighting zone")
    ) then
        table.insert(candidates, obj)
        print("[Found] " .. obj.Name .. " (" .. obj.ClassName .. ")")
    end
end

if #candidates == 0 then
    print("\n[ERROR] No SafeZone parts found!")
    print("[TIP] Check the exact naming in Dex Explorer")
    print(string.rep("=", 70) .. "\n")
    return
end

print("\n[Total Found] " .. #candidates .. " SafeZone part(s)\n")
print("[Visualizing] Creating cubes and labels...\n")

-- Create visualization for each candidate
local visualizations = {}

for i, part in ipairs(candidates) do
    -- Create semi-transparent cube matching part geometry
    local cube = Instance.new("Part")
    cube.Name = "SafeZoneVisualization_" .. i
    cube.Shape = Enum.PartType.Block
    cube.Size = part.Size
    cube.Color = Color3.fromRGB(0, 150, 255)
    cube.Material = Enum.Material.Neon
    cube.Transparency = 0.7
    cube.CanCollide = false
    cube.CFrame = part.CFrame
    cube.Parent = workspace

    -- Create BillboardGui with object path and index
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(4, 0, 2, 0)
    billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 5, 0)
    billboard.MaxDistance = 500
    billboard.Parent = cube

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.BackgroundTransparency = 0.3
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    textLabel.TextSize = 14
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Parent = billboard

    -- Build object path
    local path = part.Name
    local current = part.Parent
    while current and current ~= workspace do
        path = current.Name .. " > " .. path
        current = current.Parent
    end

    -- Set label text
    textLabel.Text = "[" .. i .. "]\n" .. path

    table.insert(visualizations, {cube = cube, billboard = billboard, part = part, index = i, path = path})

    print("  [" .. i .. "] " .. part.Name)
    print("      Path: " .. path)
    print("      Size: " .. string.format("%.1f x %.1f x %.1f", part.Size.X, part.Size.Y, part.Size.Z))
    print("      Pos: " .. string.format("%.1f, %.1f, %.1f", part.Position.X, part.Position.Y, part.Position.Z))
    print("")
end

print(string.rep("=", 70))
print("SCAN COMPLETE - All SafeZone parts are now labeled with blue cubes")
print(string.rep("=", 70))
print("\n[Instructions]")
print("  1. Look for the LARGEST cube (likely the actual safe zone building)")
print("  2. Note the [index] number (e.g., [1], [2], etc.)")
print("  3. Check the path to understand object hierarchy")
print("  4. Walk inside - if you can't damage, it's the real safe zone!")
print("\n[Copy the coordinates for the correct one to update the script]\n")
