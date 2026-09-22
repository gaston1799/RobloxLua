--[[
    Safe Zone Recorder
    Records 4 X,Z corners of safe zone (one time, then hardcode)
    F1 = Record Corner 1
    F2 = Record Corner 2
    F3 = Record Corner 3
    F4 = Record Corner 4
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

local RecordedCorners = {
    corner1 = nil,
    corner2 = nil,
    corner3 = nil,
    corner4 = nil,
}

local function recordCorner(num)
    local char = LocalPlayer.Character
    if not char then
        print("[SafeZone] No character")
        return
    end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then
        print("[SafeZone] No root part")
        return
    end

    local x = root.Position.X
    local z = root.Position.Z

    if num == 1 then
        RecordedCorners.corner1 = {x = x, z = z}
        print("[SafeZone] Corner 1 recorded: X=" .. string.format("%.2f", x) .. ", Z=" .. string.format("%.2f", z))
    elseif num == 2 then
        RecordedCorners.corner2 = {x = x, z = z}
        print("[SafeZone] Corner 2 recorded: X=" .. string.format("%.2f", x) .. ", Z=" .. string.format("%.2f", z))
    elseif num == 3 then
        RecordedCorners.corner3 = {x = x, z = z}
        print("[SafeZone] Corner 3 recorded: X=" .. string.format("%.2f", x) .. ", Z=" .. string.format("%.2f", z))
    elseif num == 4 then
        RecordedCorners.corner4 = {x = x, z = z}
        print("[SafeZone] Corner 4 recorded: X=" .. string.format("%.2f", x) .. ", Z=" .. string.format("%.2f", z))
        printHardcodedValues()
    end
end

local function printHardcodedValues()
    if not (RecordedCorners.corner1 and RecordedCorners.corner2 and RecordedCorners.corner3 and RecordedCorners.corner4) then
        print("[SafeZone] Not all corners recorded yet")
        return
    end

    print("\n" .. string.rep("=", 60))
    print("SAFE ZONE COORDINATES (HARDCODE THIS)")
    print(string.rep("=", 60))
    print([[
local SAFE_ZONE_CORNERS = {
    corner1 = {x = ]] .. RecordedCorners.corner1.x .. [[, z = ]] .. RecordedCorners.corner1.z .. [[},
    corner2 = {x = ]] .. RecordedCorners.corner2.x .. [[, z = ]] .. RecordedCorners.corner2.z .. [[},
    corner3 = {x = ]] .. RecordedCorners.corner3.x .. [[, z = ]] .. RecordedCorners.corner3.z .. [[},
    corner4 = {x = ]] .. RecordedCorners.corner4.x .. [[, z = ]] .. RecordedCorners.corner4.z .. [[},
}

local function isInsideSafeZone(position)
    -- Check if position is within safe zone rectangle
    local minX = math.min(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local maxX = math.max(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local minZ = math.min(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)
    local maxZ = math.max(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)

    return position.X >= minX and position.X <= maxX and
           position.Z >= minZ and position.Z <= maxZ
end
]])
    print(string.rep("=", 60) .. "\n")
end

print("\n[SafeZone Recorder] Ready!")
print("F1 = Record Corner 1")
print("F2 = Record Corner 2")
print("F3 = Record Corner 3")
print("F4 = Record Corner 4")
print("\nWalk to each corner of the safe zone and press the corresponding key.\n")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F1 then
        recordCorner(1)
    elseif input.KeyCode == Enum.KeyCode.F2 then
        recordCorner(2)
    elseif input.KeyCode == Enum.KeyCode.F3 then
        recordCorner(3)
    elseif input.KeyCode == Enum.KeyCode.F4 then
        recordCorner(4)
    end
end)
