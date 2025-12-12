-- Simple external overlay color controller.
-- This script ONLY changes the overlay Color based on whether the player is on their base.
-- The main Miner's Haven script is responsible for HUD + sizing/positioning.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
if not lp then
    warn("[OverlayDemo] No LocalPlayer; aborting.")
    return
end

local OVERLAY_HEIGHT = 80

local COLORS = {
    OFF   = Color3.fromRGB(255, 70, 70),   -- red
    EARLY = Color3.fromRGB(255, 255, 80),  -- yellow
    STABLE= Color3.fromRGB(120, 255, 120), -- green
}

-- ////////////////////////////////////////////////////////////
-- Tycoon / base helpers
-- ////////////////////////////////////////////////////////////

local function getTycoon()
    local tv = lp:FindFirstChild("PlayerTycoon")
    if not tv then
        return nil
    end
    return tv.Value
end

local function getBasePart()
    local tycoon = getTycoon()
    if not tycoon then
        return nil
    end

    local base = tycoon:FindFirstChild("Base") or tycoon.Base or tycoon.PrimaryPart
    if base and base:IsA("Model") then
        base = base.PrimaryPart or base:FindFirstChildWhichIsA("BasePart")
    end
    return base
end

local function getHRP()
    local char = lp.Character or lp.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart")
end

-- ////////////////////////////////////////////////////////////
-- Overlay resolution / creation
-- ////////////////////////////////////////////////////////////

local function findExistingOverlay()
    local overlay = workspace:FindFirstChild("TycoonOverlayBox")
    if overlay and overlay:IsA("BasePart") then
        return overlay
    end
    overlay = workspace:FindFirstChild("DemoOverlayBox")
    if overlay and overlay:IsA("BasePart") then
        return overlay
    end
    return nil
end

local function createOverlay(basePart)
    local part = Instance.new("Part")
    part.Name = "DemoOverlayBox"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 0.45
    part.Color = COLORS.OFF
    part.Material = Enum.Material.ForceField
    part.CastShadow = false
    part.Size = Vector3.new(60, OVERLAY_HEIGHT, 60)
    part.CFrame = basePart.CFrame * CFrame.new(0, (basePart.Size.Y * 0.5) + (OVERLAY_HEIGHT * 0.5), 0)
    part.Parent = workspace
    return part
end

local overlay = findExistingOverlay()
if not overlay then
    local basePart = getBasePart()
    if not basePart then
        warn("[OverlayDemo] Could not resolve base part; overlay will not be created.")
        return
    end
    overlay = createOverlay(basePart)
end

-- ////////////////////////////////////////////////////////////
-- "On base" detection (footprint check)
-- ////////////////////////////////////////////////////////////

local function isOnBase(basePart, hrp)
    if not basePart or not hrp then
        return false
    end
    local localPos = basePart.CFrame:PointToObjectSpace(hrp.Position)
    local halfSize = basePart.Size * 0.5

    -- Small margins so it's a bit forgiving
    local marginXZ = 2
    local heightPad = math.max(OVERLAY_HEIGHT, 10)

    local inX = math.abs(localPos.X) <= halfSize.X + marginXZ
    local inZ = math.abs(localPos.Z) <= halfSize.Z + marginXZ
    local inY = localPos.Y >= -marginXZ and localPos.Y <= halfSize.Y + heightPad

    return inX and inZ and inY
end

-- ////////////////////////////////////////////////////////////
-- Color state machine
-- ////////////////////////////////////////////////////////////

local onBase = false
local enterTime = 0
local currentColorState = "OFF"

RunService.Heartbeat:Connect(function()
    if not overlay or not overlay.Parent then
        -- Try to re-resolve it if something deleted/replaced it
        overlay = findExistingOverlay()
        if not overlay then
            return
        end
    end

    local basePart = getBasePart()
    local hrp = getHRP()
    if not basePart or not hrp then
        -- If we can't read state, treat as off base
        onBase = false
    else
        onBase = isOnBase(basePart, hrp)
    end

    local now = tick()
    local newState

    if onBase then
        if enterTime == 0 then
            enterTime = now
        end
        local elapsed = now - enterTime
        if elapsed >= 1 then
            newState = "STABLE"
        else
            newState = "EARLY"
        end
    else
        enterTime = 0
        newState = "OFF"
    end

    if newState ~= currentColorState then
        currentColorState = newState
        if newState == "OFF" then
            overlay.Color = COLORS.OFF
        elseif newState == "EARLY" then
            overlay.Color = COLORS.EARLY
        elseif newState == "STABLE" then
            overlay.Color = COLORS.STABLE
        end
    end
end)
