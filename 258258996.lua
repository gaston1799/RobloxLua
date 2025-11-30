--[[
    Miner's Haven automation module.  This script extracts only the portions
    of the original RevampLua file that are required when the loader detects
    we are inside Miner's Haven (PlaceId 258258996).

    The module keeps the public surface compatible with the previous
    `Revamp` table so other scripts can migrate gradually while the monolithic
    source is being retired.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local DEFAULT_THEME = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255),
}

local AUTO_REBIRTH_DATA_URL = "https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/autoRebirthData.lua"

local MinersHaven = {
    PlaceId = 258258996,
    Services = {
        Players = Players,
        RunService = RunService,
        PathfindingService = PathfindingService,
        UserInputService = UserInputService,
        ReplicatedStorage = ReplicatedStorage,
    },
    Data = {
        SafeZones = {},
        LayoutCosts = {},
        Items = {},
        Evolved = {},
    },
    State = {
        collectBoxes = false,
        autoOpenBoxes = false,
        collectClovers = false,
        legitPathing = false,
        autoRebirth = false,
    },
    Modules = {
        Utilities = {},
        Pathing = {},
        Combat = {},
        Farming = {},
        Inventory = {},
        Logging = {},
    },
    UI = {
        instances = {},
        defaults = {
            theme = DEFAULT_THEME,
        },
    },
}

---------------------------------------------------------------------
-- Local cache and convenience references
---------------------------------------------------------------------

local MoneyLibrary = nil
local FetchItemModule = nil
local touchedMHBoxes = {}
local LegitPathing = false
local pathfindingBusy = false
local humanoid
local humanoidRoot

local function ensureLibraries()
    if not FetchItemModule then
        local ok, module = pcall(function()
            return require(ReplicatedStorage:WaitForChild("FetchItem"))
        end)
        if ok then
            FetchItemModule = module
        else
            warn("[MinersHaven] failed to resolve FetchItem", module)
        end
    end
    if not MoneyLibrary then
        local ok, module = pcall(function()
            return require(ReplicatedStorage:WaitForChild("MoneyLib"))
        end)
        if ok then
            MoneyLibrary = module
        else
            warn("[MinersHaven] failed to resolve MoneyLib", module)
        end
    end
end

local function refreshCharacter()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    humanoidRoot = character:WaitForChild("HumanoidRootPart")
end

refreshCharacter()
LocalPlayer.CharacterAdded:Connect(refreshCharacter)

local function fetchAutoRebirthCatalog()
    local ok, source = pcall(function()
        return game:HttpGet(AUTO_REBIRTH_DATA_URL)
    end)
    if not ok then
        warn("[MinersHaven] Failed to download AutoRebirth catalog:", source)
        return nil
    end
    if not source or source == "" then
        warn("[MinersHaven] AutoRebirth catalog returned empty response.")
        return nil
    end

    local chunk, compileErr = loadstring(source)
    if not chunk then
        warn("[MinersHaven] AutoRebirth catalog compile error:", compileErr)
        return nil
    end

    local success, data = pcall(chunk)
    if not success then
        warn("[MinersHaven] AutoRebirth catalog execution failed:", data)
        return nil
    end
    if type(data) ~= "table" then
        warn("[MinersHaven] AutoRebirth catalog returned invalid type:", typeof(data))
        return nil
    end
    return data
end

---------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------

local function getItem(name)
    ensureLibraries()
    local success, item = pcall(function()
        return ReplicatedStorage.Items[name]
    end)
    if not success then
        warn("[MinersHaven] missing item", name, item)
        return nil
    end
    return item
end

local function ShopItems()
    ensureLibraries()
    for _, candidate in ipairs(getgc(true)) do
        if type(candidate) == "table" and rawget(candidate, "Miscs") then
            return candidate["All"]
        end
    end
    return {}
end

local function HasItem(name, returnCount)
    local owned = ReplicatedStorage:WaitForChild("HasItem"):InvokeServer(name) or 0
    if returnCount then
        return owned
    end
    return owned > 0
end

local function IsShopItem(itemId)
    for _, entry in ipairs(ShopItems()) do
        if tonumber(entry.ItemId.Value) == tonumber(itemId) then
            return true
        end
    end
    return false
end

local minerHavenBoxIncludePatterns = {
    "Box",
    "Gift",
    "Crate",
}

local minerHavenBoxExcludePatterns = {
    "overlay",
    "inside",
    "Lava",
    "Mine",
    "Handle",
    "Upgrade",
    "Conv",
    "Mesh",
    "Terrain",
}

local function cleanupTouchedMHBoxes()
    for box, timestamp in pairs(touchedMHBoxes) do
        if not box or not box.Parent then
            touchedMHBoxes[box] = nil
        elseif timestamp + 30 < os.clock() then
            touchedMHBoxes[box] = nil
        end
    end
end

local function getMinerHavenBoxKey(part)
    if part.Parent and part.Parent:IsA("Model") then
        return part.Parent
    end
    return part
end

local function isMinerHavenBox(part)
    if not part or not part:IsA("BasePart") then
        return false
    end
    for _, include in ipairs(minerHavenBoxIncludePatterns) do
        if part.Name:match(include) then
            for _, exclude in ipairs(minerHavenBoxExcludePatterns) do
                if part.Name:match(exclude) then
                    return false
                end
            end
            return true
        end
    end
    return false
end

local function getClosestPart(instances)
    if not humanoidRoot then
        return nil
    end
    local closest
    local closestDistance = math.huge
    for _, instance in ipairs(instances) do
        local candidate = instance
        if candidate:IsA("Model") then
            candidate = candidate.PrimaryPart or candidate:FindFirstChildWhichIsA("BasePart")
        end
        if candidate and candidate:IsA("BasePart") then
            local distance = (candidate.Position - humanoidRoot.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closest = candidate
            end
        end
    end
    return closest
end

local function moveTo(position)
    if not humanoid then
        return false
    end
    if not LegitPathing then
        humanoidRoot.CFrame = CFrame.new(position)
        return true
    end
    if pathfindingBusy then
        return false
    end
    pathfindingBusy = true
    local path = PathfindingService:CreatePath({
        AgentCanJump = true,
        AgentHeight = humanoid.HipHeight,
        AgentRadius = humanoid.HipHeight / 2,
    })
    path:ComputeAsync(humanoidRoot.Position, position)
    if path.Status ~= Enum.PathStatus.Success then
        pathfindingBusy = false
        return false
    end
    for _, waypoint in ipairs(path:GetWaypoints()) do
        humanoid:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        humanoid.MoveToFinished:Wait()
    end
    pathfindingBusy = false
    return true
end

MinersHaven.Modules.Utilities.getItem = getItem
MinersHaven.Modules.Utilities.ShopItems = ShopItems
MinersHaven.Modules.Utilities.HasItem = HasItem
MinersHaven.Modules.Utilities.IsShopItem = IsShopItem
MinersHaven.Modules.Utilities.getMinerHavenBoxKey = getMinerHavenBoxKey
MinersHaven.Modules.Utilities.isMinerHavenBox = isMinerHavenBox
MinersHaven.Modules.Utilities.getClosestPart = getClosestPart
MinersHaven.Modules.Utilities.moveTo = moveTo
MinersHaven.Modules.Pathing.moveTo = moveTo

---------------------------------------------------------------------
-- Farming helpers
---------------------------------------------------------------------

local collectBoxesTask
local collectCloversTask
local openBoxesTask
local rebirthTask

local function collectBoxesLoop()
    while MinersHaven.State.collectBoxes do
        cleanupTouchedMHBoxes()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local rootPart = character:WaitForChild("HumanoidRootPart")
        local candidateBoxes = {}
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if isMinerHavenBox(descendant) then
                local key = getMinerHavenBoxKey(descendant)
                if not touchedMHBoxes[key] then
                    table.insert(candidateBoxes, {part = descendant, key = key})
                end
            end
        end
        table.sort(candidateBoxes, function(a, b)
            return (a.part.Position - rootPart.Position).Magnitude <
                (b.part.Position - rootPart.Position).Magnitude
        end)
        for _, entry in ipairs(candidateBoxes) do
            if not MinersHaven.State.collectBoxes then
                break
            end
            if entry.part and entry.part.Parent then
                local before = rootPart.CFrame
                moveTo(entry.part.Position)
                touchedMHBoxes[entry.key] = os.clock()
                if not LegitPathing then
                    task.wait(0.1)
                    rootPart.CFrame = before
                end
            end
        end
        task.wait(0.35)
    end
    collectBoxesTask = nil
end

local function collectCloversLoop()
    while MinersHaven.State.collectClovers do
        local clovers = workspace:FindFirstChild("Clovers")
        if not clovers then
            task.wait(1)
            continue
        end
        local target = getClosestPart(clovers:GetChildren())
        if target then
            local before = humanoidRoot.CFrame
            moveTo(target.Position)
            task.wait(1.2)
            humanoidRoot.CFrame = before
        else
            task.wait(1)
        end
    end
    collectCloversTask = nil
end

local function openBoxesLoop()
    while MinersHaven.State.autoOpenBoxes do
        for _, crate in ipairs(LocalPlayer.Crates:GetChildren()) do
            ReplicatedStorage.MysteryBox:InvokeServer(crate.Name)
            task.wait(0.05)
        end
        task.wait(0.5)
    end
    openBoxesTask = nil
end

local function destroyAll()
    ReplicatedStorage.DestroyAll:InvokeServer()
    task.wait(0.7)
end

local function autoRebirthLoop()
    ensureLibraries()
    while MinersHaven.State.autoRebirth do
        local rebirths = LocalPlayer:FindFirstChild("Rebirths")
        if rebirths and MoneyLibrary then
            local nextCost = MoneyLibrary and MoneyLibrary.CalculateRebirthCost(rebirths.Value + 1)
            if nextCost then
                ReplicatedStorage.Rebirth:InvokeServer()
            end
        end
        task.wait(5)
    end
    rebirthTask = nil
end

local function startCollectBoxes(value)
    MinersHaven.State.collectBoxes = value
    if value and not collectBoxesTask then
        collectBoxesTask = task.spawn(collectBoxesLoop)
    end
end

local function startCollectClovers(value)
    MinersHaven.State.collectClovers = value
    if value and not collectCloversTask then
        collectCloversTask = task.spawn(collectCloversLoop)
    end
end

local function startOpenBoxes(value)
    MinersHaven.State.autoOpenBoxes = value
    if value and not openBoxesTask then
        openBoxesTask = task.spawn(openBoxesLoop)
    end
end

local function startAutoRebirth(value)
    MinersHaven.State.autoRebirth = value
    if value and not rebirthTask then
        rebirthTask = task.spawn(autoRebirthLoop)
    end
end

MinersHaven.Modules.Farming.collectBoxes = startCollectBoxes
MinersHaven.Modules.Farming.collectClovers = startCollectClovers
MinersHaven.Modules.Farming.autoOpenBoxes = startOpenBoxes
MinersHaven.Modules.Farming.destroyAll = destroyAll
MinersHaven.Modules.Farming.autoRebirth = startAutoRebirth

---------------------------------------------------------------------
-- Inventory helpers
---------------------------------------------------------------------

local defaultCatalysts = {
    ["Catalyst of Thunder"] = {
        name = "Draedon's Gauntlet",
        items = {
            "True Book of Knowledge",
            "Tempest Refiner",
            "Lightningbolt Predictor",
            "Azure Purifier",
        },
    },
}

local catalysts = fetchAutoRebirthCatalog() or defaultCatalysts
MinersHaven.Data.Catalysts = catalysts

local function hasCatalyst(name)
    return HasItem(name)
end

MinersHaven.Modules.Inventory.catalysts = catalysts
MinersHaven.Modules.Inventory.hasCatalyst = hasCatalyst

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------

local function buildAutoRebirthWindow()
    local source, gotSource = nil, false
    -- Fetch Wally UI library (previous URL missed the .lua extension and returned 404).
    local ok, err = pcall(function()
        source = game:HttpGet("https://raw.githubusercontent.com/bloodball/-back-ups-for-libs/main/wally%20ui%20library.lua")
        gotSource = source and source ~= ""
    end)
    if not ok or not gotSource then
        warn("[MinersHaven] Failed to fetch Wally UI library for AutoRebirth:", err or "empty response")
        return nil
    end

    local loader = loadstring(source)
    if type(loader) ~= "function" then
        warn("[MinersHaven] AutoRebirth UI loadstring failed.")
        return nil
    end

    local library = loader()
    if not library then
        warn("[MinersHaven] AutoRebirth UI library did not return a module.")
        return nil
    end
    local window = library:CreateWindow("Miner's Haven")
    local farmSection = window:CreateFolder("Farm")

    farmSection:Toggle("Rebirth Farm", function(value)
        startAutoRebirth(value)
    end)

    farmSection:Toggle("Auto Rebirth", function(value)
        startAutoRebirth(value)
    end)

    farmSection:Box("Time first layout", function(value)
        MinersHaven.Data.LayoutCosts.first = value
    end)

    farmSection:Box("Time second layout", function(value)
        MinersHaven.Data.LayoutCosts.second = value
    end)

    MinersHaven.UI.instances.rebirthLibrary = library
    MinersHaven.UI.instances.rebirthWindow = window
    return window
end

local function loadAutoRebirthUI()
    -- Build on demand so the button actually spawns the legacy window.
    if not MinersHaven.UI.instances.rebirthWindow then
        local window = buildAutoRebirthWindow()
        if not window then
            warn("[MinersHaven] AutoRebirth UI failed to build; check network/URL.")
            return nil
        end
        local lib = MinersHaven.UI.instances.rebirthLibrary
        if lib and lib.Init then
            lib:Init()
        end
    else
        local lib = MinersHaven.UI.instances.rebirthLibrary
        if lib and lib.ToggleUI then
            lib:ToggleUI()
        end
    end
    return MinersHaven.UI.instances.rebirthWindow
end

local function buildVenyxUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    local ui = venyx.new({title = "Revamp - Miner's Haven"})

    local minersPage = ui:addPage({title = "Miner's Haven"})
    local boxesSection = minersPage:addSection({title = "Boxes"})

    boxesSection:addToggle({
        title = "Collect Boxes",
        callback = startCollectBoxes,
    })

    boxesSection:addToggle({
        title = "Auto open Boxes",
        callback = startOpenBoxes,
    })

    boxesSection:addToggle({
        title = "Collect Clovers",
        callback = startCollectClovers,
    })

    boxesSection:addToggle({
        title = "Legit Pathing?",
        callback = function(value)
            LegitPathing = value
            MinersHaven.State.legitPathing = value
        end,
    })

    boxesSection:addTextbox({
        title = "layout 2 cost?",
        default = MinersHaven.Data.LayoutCosts.first or "10M",
        callback = function(value, focusLost)
            if not focusLost or not value or value == "" then
                return
            end
            MinersHaven.Data.LayoutCosts.first = value
        end,
    })

    boxesSection:addTextbox({
        title = "layout 3 cost?",
        default = MinersHaven.Data.LayoutCosts.second or "10qd",
        callback = function(value, focusLost)
            if not focusLost or not value or value == "" then
                return
            end
            MinersHaven.Data.LayoutCosts.second = value
        end,
    })

    boxesSection:addButton({
        title = "Load AutoRebirth",
        callback = function()
            loadAutoRebirthUI()
        end,
    })

    MinersHaven.UI.instances.library = venyx
    MinersHaven.UI.instances.ui = ui
    return venyx, ui
end

---------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------

function MinersHaven.init()
    if game.PlaceId ~= MinersHaven.PlaceId then
        return
    end
    ensureLibraries()
    local venyx, ui = buildVenyxUI()
    if venyx and ui then
        return {
            library = venyx,
            ui = ui,
            defaultTheme = DEFAULT_THEME,
            defaultPageIndex = 1,
            module = MinersHaven,
            extras = {
                rebirthWindow = MinersHaven.UI.instances.rebirthWindow,
            },
        }
    end
end

return MinersHaven

