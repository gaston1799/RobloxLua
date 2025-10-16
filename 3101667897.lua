--[[
    Legend of Speed automation split.  Provides orb farming helpers extracted
    from the original RevampLua monolith while keeping the public API
    intentionally small while restoring the historical Auto Race toggle.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local LegendOfSpeed = {
    PlaceId = 3101667897,
    Services = {
        Players = Players,
        RunService = RunService,
        PathfindingService = PathfindingService,
        ReplicatedStorage = ReplicatedStorage,
    },
    Data = {
        OrbSpawns = {},
        RebirthRemote = nil,
        RebirthRequirement = nil,
        RacePads = {},
    },
    State = {
        autoOrbs = false,
        autoRebirth = false,
        autoRace = false,
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
local rebirthWarnedMissing = false
local rebirthWarnedFailure = false

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

LegendOfSpeed.Modules.Utilities.orbFolder = orbFolder
LegendOfSpeed.Modules.Utilities.collectOrb = collectOrb
LegendOfSpeed.Modules.Utilities.collectAllOrbs = collectAllOrbs

local function isRacePad(instance)
    if not instance or not instance:IsA("BasePart") then
        return false
    end
    local name = instance.Name:lower()
    if not name:find("race") then
        return false
    end
    return name:find("pad") or name:find("join") or name:find("start")
end

local function rebuildRacePads()
    local pads = {}
    local seen = {}
    local candidates = {
        workspace:FindFirstChild("RacePads"),
        workspace:FindFirstChild("RaceStarts"),
        workspace:FindFirstChild("Races"),
    }
    for _, container in ipairs(candidates) do
        if container then
            for _, descendant in ipairs(container:GetDescendants()) do
                if isRacePad(descendant) and not seen[descendant] then
                    table.insert(pads, descendant)
                    seen[descendant] = true
                end
            end
        end
    end
    if #pads == 0 then
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if isRacePad(descendant) and not seen[descendant] then
                table.insert(pads, descendant)
                seen[descendant] = true
            end
        end
    end
    table.sort(pads, function(a, b)
        return a.Name < b.Name
    end)
    LegendOfSpeed.Data.RacePads = pads
    return pads
end

local function getRacePads()
    if #LegendOfSpeed.Data.RacePads == 0 then
        return rebuildRacePads()
    end
    local pads = {}
    for _, pad in ipairs(LegendOfSpeed.Data.RacePads) do
        if pad and pad:IsDescendantOf(workspace) then
            table.insert(pads, pad)
        end
    end
    if #pads == 0 then
        return rebuildRacePads()
    end
    LegendOfSpeed.Data.RacePads = pads
    return pads
end

LegendOfSpeed.Modules.Utilities.isRacePad = isRacePad
LegendOfSpeed.Modules.Utilities.getRacePads = getRacePads
LegendOfSpeed.Modules.Utilities.rebuildRacePads = rebuildRacePads

---------------------------------------------------------------------
-- Farming helpers
---------------------------------------------------------------------

local autoOrbTask
local autoRebirthTask
local autoRaceTask

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
    elseif not value and autoOrbTask then
        while autoOrbTask do
            task.wait()
        end
    end
end

local function getRebirthRequirement()
    local requirement = LegendOfSpeed.Data.RebirthRequirement
    if requirement and requirement > 0 then
        return requirement
    end
    local containers = {
        LocalPlayer:FindFirstChild("dataFolder"),
        LocalPlayer:FindFirstChild("DataFolder"),
        LocalPlayer:FindFirstChild("leaderstats"),
    }
    for _, folder in ipairs(containers) do
        if folder then
            local value = folder:FindFirstChild("RebirthRequirement") or folder:FindFirstChild("rebirthRequirement")
            if value and typeof(value.Value) == "number" then
                LegendOfSpeed.Data.RebirthRequirement = value.Value
                return value.Value
            end
        end
    end
    return requirement
end

local function resolveRebirthRemote()
    local cached = LegendOfSpeed.Data.RebirthRemote
    if cached and cached.Parent then
        return cached
    end
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            if descendant.Name:lower():find("rebirth") then
                LegendOfSpeed.Data.RebirthRemote = descendant
                return descendant
            end
        end
    end
    LegendOfSpeed.Data.RebirthRemote = nil
    return nil
end

local function tryRebirth()
    local remote = resolveRebirthRemote()
    if not remote then
        if not rebirthWarnedMissing then
            rebirthWarnedMissing = true
            warn("[LegendOfSpeed] Unable to locate a rebirth remote. Auto rebirth will retry.")
        end
        return
    end
    rebirthWarnedMissing = false
    local success, err
    if remote:IsA("RemoteFunction") then
        success, err = pcall(remote.InvokeServer, remote)
    else
        success, err = pcall(remote.FireServer, remote)
    end
    if not success and not rebirthWarnedFailure then
        rebirthWarnedFailure = true
        warn("[LegendOfSpeed] Rebirth remote rejected call:", err)
    elseif success then
        rebirthWarnedFailure = false
    end
end

local function autoRebirthLoop()
    while LegendOfSpeed.State.autoRebirth do
        local stats = LocalPlayer:FindFirstChild("leaderstats")
        local steps = stats and stats:FindFirstChild("Steps")
        local requirement = getRebirthRequirement()
        if steps and requirement and steps.Value >= requirement then
            tryRebirth()
        else
            tryRebirth()
        end
        task.wait(5)
    end
    autoRebirthTask = nil
end

local function setAutoRebirth(value)
    LegendOfSpeed.State.autoRebirth = value
    if value and not autoRebirthTask then
        autoRebirthTask = task.spawn(autoRebirthLoop)
    elseif not value and autoRebirthTask then
        while autoRebirthTask do
            task.wait()
        end
    end
end

local function joinRacePad(pad)
    if not pad or not pad:IsA("BasePart") then
        return
    end
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoidRoot then
        return
    end
    local original = humanoidRoot.CFrame
    local originalState = humanoid:GetState()
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoidRoot.CFrame = pad.CFrame + Vector3.new(0, pad.Size.Y / 2 + 2, 0)
    task.wait(0.25)
    humanoidRoot.CFrame = original
    humanoid:ChangeState(originalState)
end

LegendOfSpeed.Modules.Utilities.joinRacePad = joinRacePad

local function autoRaceLoop()
    local index = 1
    while LegendOfSpeed.State.autoRace do
        local pads = getRacePads()
        if #pads == 0 then
            task.wait(5)
        else
            if index > #pads then
                index = 1
            end
            local pad = pads[index]
            index = index + 1
            local success, err = pcall(joinRacePad, pad)
            if not success then
                warn("[LegendOfSpeed] auto race join failed", err)
            end
            task.wait(2.5)
        end
    end
    autoRaceTask = nil
end

local function setAutoRace(value)
    LegendOfSpeed.State.autoRace = value
    if value and not autoRaceTask then
        autoRaceTask = task.spawn(autoRaceLoop)
    elseif not value and autoRaceTask then
        while autoRaceTask do
            task.wait()
        end
    end
end

LegendOfSpeed.Modules.Farming.collectAllOrbs = collectAllOrbs
LegendOfSpeed.Modules.Farming.startAutoOrbs = startAutoOrbs
LegendOfSpeed.Modules.Farming.setAutoRebirth = setAutoRebirth
LegendOfSpeed.Modules.Farming.setAutoRace = setAutoRace
LegendOfSpeed.Modules.Farming.joinRacePad = joinRacePad

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
        toggled = LegendOfSpeed.State.autoOrbs,
        callback = startAutoOrbs,
    })

    local progressionSection = losPage:addSection({title = "Progression"})

    progressionSection:addToggle({
        title = "Auto Rebirth",
        toggled = LegendOfSpeed.State.autoRebirth,
        callback = setAutoRebirth,
    })

    local racesSection = losPage:addSection({title = "Races"})

    racesSection:addButton({
        title = "Refresh pads",
        callback = rebuildRacePads,
    })

    racesSection:addToggle({
        title = "Auto Race",
        toggled = LegendOfSpeed.State.autoRace,
        callback = setAutoRace,
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
    rebuildRacePads()
    buildUI():SelectPage(1)
end

return LegendOfSpeed

