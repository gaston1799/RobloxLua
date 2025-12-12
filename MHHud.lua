-- Simple standalone overlay + HUD demo with color cycling.
-- Drop into an executor to verify overlay creation without the full Miner's Haven script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OVERLAY_HEIGHT = 80
local COLOR_CYCLE = {
    Color3.fromRGB(255, 70, 70),
    Color3.fromRGB(255, 255, 80),
    Color3.fromRGB(120, 255, 120),
}
local COLOR_STEP = 1.5

local function createOverlay(basePosition)
    local part = Instance.new("Part")
    part.Name = "DemoOverlayBox"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 0.45
    part.Color = Color3.fromRGB(255, 70, 70)
    part.Material = Enum.Material.ForceField
    part.CastShadow = false
    part.Size = Vector3.new(60, OVERLAY_HEIGHT, 60)
    part.CFrame = CFrame.new(basePosition) * CFrame.new(0, OVERLAY_HEIGHT * 0.5, 0)
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

local overlay = createOverlay(basePart.Position)
local hud, label = attachHud(overlay)

RunService.Heartbeat:Connect(function(step)
    if not overlay or not overlay.Parent then
        return
    end
    local base = getBasePart()
    if base then
        overlay.Size = Vector3.new(base.Size.X, OVERLAY_HEIGHT, base.Size.Z)
        overlay.CFrame = base.CFrame * CFrame.new(0, (base.Size.Y * 0.5) + (OVERLAY_HEIGHT * 0.5), 0)
        hud.Adornee = overlay
        hud.StudsOffsetWorldSpace = Vector3.new(0, overlay.Size.Y * 0.5 + 2, 0)
    end
    if COLOR_STEP and COLOR_STEP > 0 then
        local idx = math.floor((tick() / COLOR_STEP) % #COLOR_CYCLE) + 1
        overlay.Color = COLOR_CYCLE[idx]
    end
end)
