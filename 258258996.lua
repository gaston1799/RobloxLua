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
local PREFIX_TABLE_URL = "https://raw.githubusercontent.com/gaston1799/HostedFiles/refs/heads/main/table.lua"

local prefixEntries = {}
do
    local ok, chunk = pcall(function()
        return loadstring(game:HttpGet(PREFIX_TABLE_URL))
    end)
    if ok and type(chunk) == "function" then
        local success, result = pcall(chunk)
        if success and type(result) == "table" then
            prefixEntries = result
        end
    end
end

local prefixScale = {[""] = 1}
local sortedPrefixes = {}
for _, entry in ipairs(prefixEntries or {}) do
    local prefix = entry.prefix or ""
    local number = entry.number or 1
    prefixScale[prefix:lower()] = number
    if prefix ~= "" then
        table.insert(sortedPrefixes, {prefix = prefix, number = number})
    end
end
table.sort(sortedPrefixes, function(a, b)
    return #a.prefix > #b.prefix
end)

local function parseCurrency(value)
    if type(value) == "number" then
        return value
    end
    if not value then
        return 0
    end
    local normalized = tostring(value)
    normalized = normalized:gsub("[%$,]", "")
    local base = normalized
    local suffix = ""
    for _, entry in ipairs(sortedPrefixes) do
        local prefix = entry.prefix
        if prefix ~= "" and #base >= #prefix then
            local candidate = base:sub(-#prefix)
            if candidate:lower() == prefix:lower() then
                suffix = candidate
                base = base:sub(1, -#prefix - 1)
                break
            end
        end
    end
    base = (base and base:match("^%s*(.-)%s*$")) or ""
    if base == "" then
        return 0
    end
    local amount = tonumber(base)
    if not amount then
        return 0
    end
    local multiplier = 1
    if suffix ~= "" then
        multiplier = prefixScale[suffix:lower()] or 1
    end
    return amount * multiplier
end

local REBIRTH_UI_TAIL =
    "PlayerGui.Rebirth.Frame.Rebirth_Content.Content.Rebirth.Frame.Bottom.Reborn"

local function getInstanceFromTail(tail)
    local current = Players.LocalPlayer
    if not current then
        return nil
    end
    for part in tail:gmatch("[^%.]+") do
        current = current:FindFirstChild(part)
        if not current then
            return nil
        end
    end
    return current
end

local function getRebirthPriceFromUI()
    local ui = getInstanceFromTail(REBIRTH_UI_TAIL)
    if not ui then
        return nil, nil, nil, nil
    end
    if not (ui:IsA("TextLabel") or ui:IsA("TextButton")) then
        ui = ui:FindFirstChildWhichIsA("TextLabel") or ui:FindFirstChildWhichIsA("TextButton")
        if not ui then
            return nil, nil, nil, nil
        end
    end
    local fullText = ui.Text or ""
    local valueStr = fullText:match(":%s*(.+)$") or fullText
    local priceNumber = parseCurrency(valueStr)
    return priceNumber, ui, valueStr, fullText
end

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
        Items = {},
        Evolved = {},
        LayoutAutomation = {
            layout2Enabled = false,
            layout3Enabled = false,
            layout2Cost = "10M",
            layout3Cost = "10qd",
            layout2Withdraw = false,
            layout3Withdraw = false,
            rebirthWithLayout = false,
            rebirthLayout = "Layout1",
            rebirthWithdraw = false,
            layoutSelections = {
                first = "Layout1",
                second = "Layout2",
                third = "Layout3",
            },
        },
    },
    State = {
        collectBoxes = false,
        autoOpenBoxes = false,
        collectClovers = false,
        legitPathing = false,
        autoRebirth = false,
        rebirthFarm = false,
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
MinersHaven.Modules.Utilities.parseCurrency = parseCurrency
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

local LAYOUT_OPTIONS = {"Layout1", "Layout2", "Layout3"}
local LayoutsService = ReplicatedStorage:WaitForChild("Layouts")
local needsLayoutNextRebirth = false
local layoutPrepRunning = false
local savedLayoutPosition

local function getTycoonBase()
    local tycoonValue = LocalPlayer:FindFirstChild("PlayerTycoon")
    if not tycoonValue or not tycoonValue.Value then
        return nil
    end
    return tycoonValue.Value:FindFirstChild("Base") or tycoonValue.Value.Base
end

local function executeAtTycoonBase(action)
    if type(action) ~= "function" then
        return false, "missing action"
    end
    local base = getTycoonBase()
    if not base then
        warn("[MinersHaven] Unable to locate tycoon base for layout work.")
        return false, "no base"
    end
    local targetPart
    if base:IsA("BasePart") then
        targetPart = base
    elseif base.PrimaryPart then
        targetPart = base.PrimaryPart
    else
        targetPart = base:FindFirstChildWhichIsA("BasePart")
    end
    if not targetPart then
        warn("[MinersHaven] Tycoon base has no usable part.")
        return false, "no surface"
    end
    if humanoidRoot then
        savedLayoutPosition = humanoidRoot.CFrame
        moveTo(targetPart.Position)
    end
    local ok, result = pcall(action)
    if savedLayoutPosition then
        moveTo(savedLayoutPosition.Position)
        savedLayoutPosition = nil
    end
    return ok, result
end

local function loadLayout(layoutName)
    if not layoutName or layoutName == "" then
        return false
    end
    if not LayoutsService then
        warn("[MinersHaven] Layout service unavailable.")
        return false
    end
    local ok, err = executeAtTycoonBase(function()
        LayoutsService:InvokeServer("Load", layoutName)
    end)
    if not ok then
        warn("[MinersHaven] Failed to load layout:", layoutName, err)
    end
    return ok
end

local function getPlayerCash()
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    local cashStat = stats and stats:FindFirstChild("Cash")
    if not cashStat then
        return 0
    end
    return parseCurrency(cashStat.Value)
end

local function waitForCashThreshold(cost)
    local required = parseCurrency(cost)
    if required <= 0 then
        return true
    end
    while MinersHaven.State.rebirthFarm and getPlayerCash() < required do
        task.wait(0.25)
    end
    return MinersHaven.State.rebirthFarm
end

local function runLayoutSequence()
    if not MinersHaven.State.rebirthFarm then
        return
    end
    local config = MinersHaven.Data.LayoutAutomation
    local firstLayout = config.layoutSelections.first or LAYOUT_OPTIONS[1]
    loadLayout(firstLayout)
    if config.layout2Enabled and MinersHaven.State.rebirthFarm then
        if not waitForCashThreshold(config.layout2Cost) then
            return
        end
        if config.layout2Withdraw then
            destroyAll()
        end
        local secondLayout = config.layoutSelections.second or LAYOUT_OPTIONS[2]
        loadLayout(secondLayout)
    end
    if config.layout3Enabled and MinersHaven.State.rebirthFarm then
        if not waitForCashThreshold(config.layout3Cost) then
            return
        end
        if config.layout3Withdraw then
            destroyAll()
        end
        local thirdLayout = config.layoutSelections.third or LAYOUT_OPTIONS[3]
        loadLayout(thirdLayout)
    end
end

local function runLayoutPrep()
    if not MinersHaven.State.rebirthFarm or not needsLayoutNextRebirth then
        return
    end
    runLayoutSequence()
    needsLayoutNextRebirth = false
end

local function startRebirthFarm(value)
    MinersHaven.State.rebirthFarm = value
    needsLayoutNextRebirth = value
    if not MinersHaven.State.autoRebirth and value then
        runLayoutPrep()
    end
end

local function prepareRebirthLayout()
    local config = MinersHaven.Data.LayoutAutomation
    if not config.rebirthWithLayout or not config.rebirthLayout or config.rebirthLayout == "" then
        return true
    end
    if config.rebirthWithdraw then
        destroyAll()
    end
    return loadLayout(config.rebirthLayout)
end

local function autoRebirthLoop()
    ensureLibraries()
    while MinersHaven.State.autoRebirth do
        if MinersHaven.State.rebirthFarm and needsLayoutNextRebirth then
            runLayoutPrep()
        end

        local targetCost = getRebirthPriceFromUI()
        if not targetCost or targetCost <= 0 then
            task.wait(1)
            continue
        end

        while MinersHaven.State.autoRebirth and getPlayerCash() < targetCost do
            task.wait(1)
        end
        if not MinersHaven.State.autoRebirth then
            break
        end

        if prepareRebirthLayout() then
            ReplicatedStorage.Rebirth:InvokeServer()
            repeat
                task.wait(0.5)
            until not MinersHaven.State.autoRebirth or getPlayerCash() < targetCost
            needsLayoutNextRebirth = MinersHaven.State.rebirthFarm
        else
            task.wait(1)
        end
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
MinersHaven.Modules.Farming.rebirthFarm = startRebirthFarm
MinersHaven.Modules.Farming.loadLayouts = runLayoutSequence
MinersHaven.Modules.Farming.prepareRebirthLayout = prepareRebirthLayout

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


    local layoutConfig = MinersHaven.Data.LayoutAutomation
    local autoRebirthSection = minersPage:addSection({title = "Auto Rebirth"})

    autoRebirthSection:addToggle({
        title = "Rebirth Farm",
        default = MinersHaven.State.rebirthFarm,
        callback = startRebirthFarm,
    })

    autoRebirthSection:addToggle({
        title = "Auto Rebirth",
        default = MinersHaven.State.autoRebirth,
        callback = startAutoRebirth,
    })

    autoRebirthSection:addDropdown({
        title = "First layout",
        list = LAYOUT_OPTIONS,
        default = layoutConfig.layoutSelections.first,
        callback = function(selection)
            layoutConfig.layoutSelections.first = selection
        end,
    })

    autoRebirthSection:addDropdown({
        title = "Second layout",
        list = LAYOUT_OPTIONS,
        default = layoutConfig.layoutSelections.second,
        callback = function(selection)
            layoutConfig.layoutSelections.second = selection
        end,
    })

    autoRebirthSection:addDropdown({
        title = "Third layout",
        list = LAYOUT_OPTIONS,
        default = layoutConfig.layoutSelections.third,
        callback = function(selection)
            layoutConfig.layoutSelections.third = selection
        end,
    })

    autoRebirthSection:addToggle({
        title = "Load Layout 2",
        default = layoutConfig.layout2Enabled,
        callback = function(value)
            layoutConfig.layout2Enabled = value
        end,
    })

    autoRebirthSection:addTextbox({
        title = "Layout 2 cost",
        default = layoutConfig.layout2Cost,
        callback = function(value, focusLost)
            if not focusLost or not value then
                return
            end
            layoutConfig.layout2Cost = value
        end,
    })

    autoRebirthSection:addToggle({
        title = "Withdraw before Layout 2",
        default = layoutConfig.layout2Withdraw,
        callback = function(value)
            layoutConfig.layout2Withdraw = value
        end,
    })

    autoRebirthSection:addToggle({
        title = "Load Layout 3",
        default = layoutConfig.layout3Enabled,
        callback = function(value)
            layoutConfig.layout3Enabled = value
        end,
    })

    autoRebirthSection:addTextbox({
        title = "Layout 3 cost",
        default = layoutConfig.layout3Cost,
        callback = function(value, focusLost)
            if not focusLost or not value then
                return
            end
            layoutConfig.layout3Cost = value
        end,
    })

    autoRebirthSection:addToggle({
        title = "Withdraw before Layout 3",
        default = layoutConfig.layout3Withdraw,
        callback = function(value)
            layoutConfig.layout3Withdraw = value
        end,
    })

    autoRebirthSection:addToggle({
        title = "Rebirth with layout",
        default = layoutConfig.rebirthWithLayout,
        callback = function(value)
            layoutConfig.rebirthWithLayout = value
        end,
    })

    autoRebirthSection:addDropdown({
        title = "Rebirth layout",
        list = LAYOUT_OPTIONS,
        default = layoutConfig.rebirthLayout,
        callback = function(selection)
            layoutConfig.rebirthLayout = selection
        end,
    })

    autoRebirthSection:addToggle({
        title = "Withdraw before rebirth layout",
        default = layoutConfig.rebirthWithdraw,
        callback = function(value)
            layoutConfig.rebirthWithdraw = value
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
        }
    end
end

return MinersHaven

