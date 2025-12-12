-- Simple standalone overlay + HUD demo with color cycling.
-- Drop into an executor to verify overlay creation without the full Miner's Haven script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OVERLAY_PAD = 0.5   -- thickness of overlay box
local MARGIN = 2
local ARMED_TIME = 1

local function getOverlayHeight(base)
    -- thin plate overlay; tweak OVERLAY_PAD for thickness
    return OVERLAY_PAD
end

local function sizeAndPositionOverlay(part, base)
    if not part or not base then
        return
    end
    local height = getOverlayHeight(base)
    part.Size = Vector3.new(base.Size.X, height, base.Size.Z)
    -- bottom of overlay = top of base
    local offsetY = (base.Size.Y + height) * 0.5
    part.CFrame = base.CFrame * CFrame.new(0, offsetY, 0)
end

local function createOverlay(base)
    local part = Instance.new("Part")
    part.Name = "DemoOverlayBox"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 0.45
    part.Color = Color3.fromRGB(255, 70, 70)
    part.Material = Enum.Material.ForceField
    part.CastShadow = false
    if base and base.Size then
        sizeAndPositionOverlay(part, base)
    else
        part.Size = Vector3.new(60, getOverlayHeight(), 60)
        part.CFrame = CFrame.new(0, part.Size.Y * 0.5, 0)
    end
    part.Parent = workspace
    return part
end

local function attachHud(overlay)
    local hud = Instance.new("BillboardGui")
    hud.Name = "DemoOverlayHud"
    hud.AlwaysOnTop = true
    hud.Size = UDim2.new(0, 240, 0, 50)
    hud.StudsOffsetWorldSpace = Vector3.new(0, overlay.Size.Y * 0.5 + 2, 0)
    hud.Adornee = overlay
    hud.Parent = overlay

    local label = Instance.new("TextLabel")
    label.Name = "Status"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.3
    label.Text = "Overlay demo"
    label.Parent = hud

    return hud, label
end

local function getBasePart()
    local lp = Players.LocalPlayer
    if not lp then
        return nil
    end
    local tycoonValue = lp:FindFirstChild("PlayerTycoon")
    local tycoon = tycoonValue and tycoonValue.Value
    if not tycoon then
        return nil
    end
    local base = tycoon:FindFirstChild("Base") or tycoon.Base or tycoon.PrimaryPart
    if base and base:IsA("Model") then
        base = base.PrimaryPart or base:FindFirstChildWhichIsA("BasePart")
    end
    return base
end

local basePart = getBasePart()
if not basePart then
    warn("overlay_demo.lua: could not resolve base part; overlay will not render")
    return
end

local overlay = createOverlay(basePart)
local hud, label = attachHud(overlay)

local overlayState = "off"
local overlayEnterTime = 0

local function isWithinBase(base, point)
    if not base or not point then
        return false
    end
    local localPos = base.CFrame:PointToObjectSpace(point)
    local half = base.Size * 0.5
    local horizontalInside = math.abs(localPos.X) <= half.X + MARGIN
        and math.abs(localPos.Z) <= half.Z + MARGIN
    if not horizontalInside then
        return false
    end
    if localPos.Y < -MARGIN then
        return false
    end
    if localPos.Y <= half.Y + OVERLAY_PAD + MARGIN then
        return true
    end
    return localPos.Y <= half.Y + OVERLAY_PAD + MARGIN + 200
end

RunService.Heartbeat:Connect(function(step)
    if not overlay or not overlay.Parent then
        return
    end
    local base = getBasePart()
    if base then
        sizeAndPositionOverlay(overlay, base)
        hud.Adornee = overlay
        hud.StudsOffsetWorldSpace = Vector3.new(0, overlay.Size.Y * 0.5 + 2, 0)
    else
        -- keep overlay at origin if base disappears
        overlay.CFrame = CFrame.new(0, overlay.Size.Y * 0.5, 0)
    end

    local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local onBase = root and base and isWithinBase(base, root.Position)

    if onBase then
        if overlayState ~= "arming" and overlayState ~= "on" then
            overlayState = "arming"
            overlayEnterTime = os.clock()
        elseif overlayState == "arming" and os.clock() - overlayEnterTime >= ARMED_TIME then
            overlayState = "on"
        end
    else
        overlayState = "off"
    end

    local partColor = Color3.fromRGB(255, 70, 70)
    local textColor = Color3.fromRGB(255, 180, 180)
    local msg = "Off base"

    if overlayState == "arming" then
        partColor = Color3.fromRGB(255, 255, 80)
        textColor = Color3.fromRGB(255, 255, 180)
        msg = "Arming"
    elseif overlayState == "on" then
        partColor = Color3.fromRGB(120, 255, 120)
        textColor = Color3.fromRGB(170, 255, 170)
        msg = "On base"
    end

    overlay.Color = partColor
    if label then
        label.TextColor3 = textColor
        label.Text = string.format("Overlay demo: %s", msg)
    end
end)
