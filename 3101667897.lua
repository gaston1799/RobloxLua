--[[
    Legend of Speed automation split.  Provides the orb collection and race
    helpers extracted from the original RevampLua monolith while keeping the
    public API intentionally small.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer

local LegendOfSpeed = {
    PlaceId = 3101667897,
    Services = {
        Players = Players,
        RunService = RunService,
        PathfindingService = PathfindingService,
    },
    Data = {
        OrbSpawns = {},
        Races = {},
    },
    State = {
        autoOrbs = false,
        autoRace = false,
        autoRebirth = false,
    },
    Modules = {
        Utilities = {},
        Pathing = {},
        Farming = {},
        Combat = {},
        Logging = {},
    },
    UI = {
        instances = {},
    },
}

---------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------

local humanoidRoot

local function refreshCharacter()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    humanoidRoot = character:WaitForChild("HumanoidRootPart")
end

refreshCharacter()
LocalPlayer.CharacterAdded:Connect(refreshCharacter)

local function orbFolder()
    local folder = workspace:FindFirstChild("orbFolder")
    if not folder then
        return nil
    end
    return folder:FindFirstChild("City") or folder
end

local function collectOrb(orbPart)
    if not orbPart or not orbPart:IsA("BasePart") then
        return
    end
    local before = humanoidRoot.CFrame
    humanoidRoot.CFrame = orbPart.CFrame
    task.wait(0.05)
    humanoidRoot.CFrame = before
end

local function collectAllOrbs()
    local container = orbFolder()
    if not container then
        warn("[LegendOfSpeed] orb folder not found")
        return
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            for _, part in ipairs(child:GetChildren()) do
                if part:IsA("BasePart") and not part.Name:match("Union") then
                    collectOrb(part)
                end
            end
        elseif child:IsA("BasePart") then
            collectOrb(child)
        end
    end
end

local function getRaceCheckpointFolder()
    return workspace:FindFirstChild("Races")
end

LegendOfSpeed.Modules.Utilities.orbFolder = orbFolder
LegendOfSpeed.Modules.Utilities.collectOrb = collectOrb
LegendOfSpeed.Modules.Utilities.collectAllOrbs = collectAllOrbs
LegendOfSpeed.Modules.Utilities.getRaceCheckpointFolder = getRaceCheckpointFolder

---------------------------------------------------------------------
-- Farming helpers
---------------------------------------------------------------------

local autoOrbTask

local function autoOrbsLoop()
    while LegendOfSpeed.State.autoOrbs do
        local success, err = pcall(collectAllOrbs)
        if not success then
            warn("[LegendOfSpeed] auto orb loop", err)
            task.wait(1)
        else
            task.wait(0.3)
        end
    end
    autoOrbTask = nil
end

local function startAutoOrbs(value)
    LegendOfSpeed.State.autoOrbs = value
    if value and not autoOrbTask then
        autoOrbTask = task.spawn(autoOrbsLoop)
    end
end

LegendOfSpeed.Modules.Farming.collectAllOrbs = collectAllOrbs
LegendOfSpeed.Modules.Farming.startAutoOrbs = startAutoOrbs

---------------------------------------------------------------------
-- Pathing helpers
---------------------------------------------------------------------

local function moveTo(position)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local path = PathfindingService:CreatePath({AgentCanJump = true})
    path:ComputeAsync(humanoidRoot.Position, position)
    if path.Status ~= Enum.PathStatus.Success then
        humanoidRoot.CFrame = CFrame.new(position)
        return
    end
    for _, waypoint in ipairs(path:GetWaypoints()) do
        humanoid:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        humanoid.MoveToFinished:Wait()
    end
end

LegendOfSpeed.Modules.Pathing.moveTo = moveTo

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    local ui = venyx.new({title = "Revamp - Legend of Speed"})

    local losPage = ui:addPage({title = "LoS"})
    local orbsSection = losPage:addSection({title = "Orbs"})

    orbsSection:addButton({
        title = "Get all",
        callback = collectAllOrbs,
    })

    orbsSection:addToggle({
        title = "Auto Orbs",
        callback = startAutoOrbs,
    })

    local themePage = ui:addPage({title = "Theme"})
    local colorsSection = themePage:addSection({title = "Colors"})
    for theme, color in pairs({
        Background = Color3.fromRGB(24, 24, 24),
        Glow = Color3.fromRGB(0, 0, 0),
        Accent = Color3.fromRGB(10, 10, 10),
        LightContrast = Color3.fromRGB(20, 20, 20),
        DarkContrast = Color3.fromRGB(14, 14, 14),
        TextColor = Color3.fromRGB(255, 255, 255),
    }) do
        colorsSection:addColorPicker({
            title = theme,
            default = color,
            callback = function(newColor)
                venyx:setTheme(theme, newColor)
            end,
        })
    end

    LegendOfSpeed.UI.instances.library = venyx
    LegendOfSpeed.UI.instances.ui = ui
    return ui
end

---------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------

function LegendOfSpeed.init()
    if game.PlaceId ~= LegendOfSpeed.PlaceId then
        return
    end
    buildUI():SelectPage(1)
end

return LegendOfSpeed

