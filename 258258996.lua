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
        Settings = {
            teleportFallback = true,
            returnHomeOnIdle = true,
            teleportToBoxOnPathFail = false,
            jumpOnDownSlope = false,
        },
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
            teleportForAutoRebirth = true,
            layoutSelections = {
                first = "Layout1",
                second = "Layout2",
                third = "Layout3",
            },
            teleportToTycoon = true,
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

local Settings = MinersHaven.Data.Settings
local FetchItemModule = nil
local touchedMHBoxes = {}
local boxFailCounts = {}
local LegitPathing = false
local pathfindingBusy = false
local humanoid
local humanoidRoot
local pathSegments = {}
local boxHudLookup = {}
local rebirthHudBillboard
local rebirthHudLabel
local rebirthHudConnection
local baseDetectorPart
local baseDetectorLabel
local baseVisualsWatcherConnection
local lastReturnHome = 0
local goToTycoonBase
local getTycoonBasePart
local returnToTycoonBaseIfIdle
local startCollectBoxes
local startCollectClovers
local startOpenBoxes
local startAutoRebirth
local startRebirthFarm
local waypointBillboard
local waypointLabel
local currentWaypointIndex = 0
local totalWaypoints = 0
local currentWaypointPosition
local currentGoalPosition
local stuckTimer = 0
local lastRootPosition
local stuckRepathRequested = false
local stuckConnection
local createPathForHumanoid
local simplifyCharacterCollisions
local createWaypointVisualizer
local updateWaypointVisualizer
local attachStuckDetection
local getBoxesContainer
local simplifyWaypoints
local getSegmentSlopeInfo
local createSlopeHud
local updateSlopeHud
local ensurePositionedAtBaseForBoxes
local ensureOnBaseForLayouts
local ensureRebirthHud
local updateRebirthHud
local getPlayerCash
local loadLayout
local ensureBaseDetector
local updateBaseDetectorHud
local ensureBaseVisuals

local STUCK_DISTANCE_THRESHOLD = 0.2
local STUCK_TIME_THRESHOLD = 0.75
local STEEP_UP_ANGLE_THRESHOLD = 20
local BOX_FARM_BASE_RADIUS = 30
local BASE_ON_TOP_RADIUS = 10
local BASE_ON_TOP_MARGIN = 2
local BASE_ON_TOP_HEIGHT_PAD = 10
local BASE_DETECTOR_EXTRA_HEIGHT = 100

local function simplifyCharacterCollisions(character)
    local coreParts = {
        HumanoidRootPart = true,
        UpperTorso = true,
        LowerTorso = true,
        Torso = true,
        Head = true,
    }

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and not coreParts[part.Name] then
            part.CanCollide = false
        end
    end
end

createPathForHumanoid = function(humanoidObj)
    local agentHeight = humanoidObj and humanoidObj.HipHeight and (humanoidObj.HipHeight * 2 + 2) or 8
    local pathParams = {
        AgentRadius = 3.5,
        AgentHeight = agentHeight,
        AgentCanJump = true,
        AgentCanClimb = true,
    }
    return PathfindingService:CreatePath(pathParams)
end

local function createWaypointVisualizer(character)
    local root = character:WaitForChild("HumanoidRootPart")

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "WaypointVisualizer"
    billboard.Adornee = root
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = character

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.3
    label.Name = "InfoLabel"
    label.Text = "Idle"
    label.Parent = billboard

    return billboard, label
end

updateWaypointVisualizer = function(label, humanoidObj, root, waypointIndex, waypointTotal, waypointPosition)
    if not label or not humanoidObj or not root then
        return
    end
    if not waypointPosition then
        label.Text = "No path"
        return
    end
    local distance = (waypointPosition - root.Position).Magnitude
    local speed = humanoidObj.WalkSpeed > 0 and humanoidObj.WalkSpeed or 1
    local eta = distance / speed

    label.Text = string.format(
        "WP %d/%d | Dist: %.1f | ETA: %.2fs",
        waypointIndex or 0,
        waypointTotal or 0,
        distance,
        eta
    )
end

local function clearPathVisualizer()
    for _, part in ipairs(pathSegments) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    table.clear(pathSegments)
end

local function addPathVisualizer(waypoints)
    clearPathVisualizer()
    if not waypoints or #waypoints < 2 then
        return
    end
    local baseColor = Color3.fromRGB(60, 170, 255)
    local darkRed = Color3.fromRGB(180, 40, 40)
    for i = 1, #waypoints - 1 do
        local fromPos = waypoints[i].Position
        local toPos = waypoints[i + 1].Position
        local slopeInfo = getSegmentSlopeInfo(waypoints[i], waypoints[i + 1])
        local segmentColor = baseColor
        if slopeInfo and slopeInfo.dy > 0 then
            local factor = math.clamp(math.abs(slopeInfo.angleDeg) / 45, 0, 1)
            segmentColor = baseColor:lerp(darkRed, factor)
        end
        local segment = Instance.new("Part")
        segment.Name = "MH_PathSegment"
        segment.Anchored = true
        segment.CanCollide = false
        segment.Material = Enum.Material.Neon
        segment.Color = segmentColor
        segment.Transparency = 0.3
        local distance = (toPos - fromPos).Magnitude
        segment.Size = Vector3.new(0.15, 0.15, distance)
        segment.CFrame = CFrame.new(fromPos, toPos) * CFrame.new(0, 0, -distance / 2)
        segment.Parent = workspace
        table.insert(pathSegments, segment)
    end
end

getSegmentSlopeInfo = function(a, b)
    if not a or not b or not a.Position or not b.Position then
        return nil
    end
    local p1 = a.Position
    local p2 = b.Position
    local dy = p2.Y - p1.Y
    local horizontalVec = Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z)
    local horizontalDist = horizontalVec.Magnitude
    local angleDeg
    if horizontalDist <= 0.0001 then
        angleDeg = 90
    else
        angleDeg = math.deg(math.atan2(dy, horizontalDist))
    end
    local midpoint = (p1 + p2) * 0.5
    return {
        dy = dy,
        horizontalDist = horizontalDist,
        angleDeg = angleDeg,
        midpoint = midpoint,
    }
end

createSlopeHud = function()
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.5, 0.5, 0.5)
    part.Name = "SegmentSlopeMarker"
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SegmentSlopeHud"
    billboard.Size = UDim2.new(0, 160, 0, 40)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.3
    label.Name = "SlopeLabel"
    label.Parent = billboard

    return part, label
end

updateSlopeHud = function(info, part, label)
    if not info or not part or not label then
        return
    end
    part.Position = info.midpoint
    label.Text = string.format(
        "Slope: %.1f deg  dy=%.2f  horiz=%.2f",
        info.angleDeg,
        info.dy,
        info.horizontalDist
    )
end

ensureRebirthHud = function()
    if type(getTycoonBasePart) ~= "function" then
        return
    end
    local basePart = getTycoonBasePart()
    if not basePart then
        return
    end
    if rebirthHudBillboard and rebirthHudBillboard.Adornee ~= basePart then
        rebirthHudBillboard:Destroy()
        rebirthHudBillboard = nil
        rebirthHudLabel = nil
    end
    if not rebirthHudBillboard or not rebirthHudLabel or not rebirthHudBillboard.Parent then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RebirthProgressHud"
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.new(0, 220, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 6, 0)
        billboard.Adornee = basePart
        billboard.Parent = basePart

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.SourceSansBold
        label.TextScaled = true
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.2
        label.Name = "RebirthInfo"
        label.Parent = billboard

        rebirthHudBillboard = billboard
        rebirthHudLabel = label
    end
    if rebirthHudConnection then
        return
    end
    rebirthHudConnection = RunService.Heartbeat:Connect(function()
        updateRebirthHud()
    end)
end

updateRebirthHud = function()
    if not rebirthHudLabel then
        return
    end
    local priceNumber = getRebirthPriceFromUI()
    local currentCash = getPlayerCash()
    if not priceNumber or priceNumber <= 0 then
        rebirthHudLabel.Text = string.format("Cash: %.2e | Rebirth: --", currentCash or 0)
        return
    end
    local progress = math.clamp((currentCash or 0) / priceNumber, 0, 1)
    rebirthHudLabel.Text = string.format("Rebirth %.2f%% | Cash: %.2e / %.2e", progress * 100, currentCash or 0, priceNumber)
end

ensureBaseDetector = function()
    local basePart = getTycoonBasePart and getTycoonBasePart()
    if not basePart then
        return nil
    end
    -- Use a robust id for detecting base changes; avoid methods that may be unavailable
    local ok, baseId = pcall(function()
        return typeof(basePart.GetDebugId) == "function" and basePart:GetDebugId() or tostring(basePart)
    end)
    if not ok then
        baseId = tostring(basePart)
    end
    -- Recreate if base changed
    if baseDetectorPart and baseDetectorPart.Parent and baseDetectorPart:GetAttribute("BaseId") ~= baseId then
        baseDetectorPart:Destroy()
        baseDetectorPart = nil
        baseDetectorLabel = nil
    end
    if not baseDetectorPart or not baseDetectorPart.Parent then
        local detector = Instance.new("Part")
        detector.Name = "MH_BaseDetector"
        detector.Anchored = true
        detector.CanCollide = false
        detector.CanTouch = true
        detector.CanQuery = true
        detector.Material = Enum.Material.ForceField
        detector.Color = Color3.fromRGB(0, 200, 255)
        detector.Transparency = 0.7
        detector:SetAttribute("BaseId", baseId)
        baseDetectorPart = detector

        local hud = Instance.new("BillboardGui")
        hud.Name = "BaseDetectorHud"
        hud.Adornee = detector
        hud.Size = UDim2.new(0, 180, 0, 40)
        hud.StudsOffset = Vector3.new(0, 3, 0)
        hud.AlwaysOnTop = true
        hud.Parent = detector

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.SourceSansBold
        label.TextScaled = true
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.25
        label.Name = "State"
        label.Text = "Base checker"
        label.Parent = hud
        baseDetectorLabel = label
    end

    -- Size and position: match base footprint, extend height
    local sizeY = basePart.Size.Y + BASE_DETECTOR_EXTRA_HEIGHT
    baseDetectorPart.Size = Vector3.new(basePart.Size.X + BASE_ON_TOP_MARGIN * 2, sizeY, basePart.Size.Z + BASE_ON_TOP_MARGIN * 2)
    -- Center the detector so its bottom sits on the base and extends upward
    local yOffset = (sizeY / 2) + (basePart.Size.Y / 2)
    baseDetectorPart.CFrame = basePart.CFrame * CFrame.new(0, yOffset, 0)
    baseDetectorPart.Parent = workspace
    return baseDetectorPart
end

updateBaseDetectorHud = function(isInside)
    if not baseDetectorLabel then
        return
    end
    if isInside then
        baseDetectorLabel.Text = "On Base"
        baseDetectorLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
    else
        baseDetectorLabel.Text = "Off Base"
        baseDetectorLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
    end
end

ensureBaseVisuals = function()
    ensureRebirthHud()
    ensureBaseDetector()
end

simplifyWaypoints = function(waypoints, dotThreshold)
    dotThreshold = dotThreshold or 0.995
    local count = #waypoints
    if count <= 2 then
        return waypoints
    end
    local simplified = {}
    table.insert(simplified, waypoints[1])
    for i = 2, count - 1 do
        local prev = waypoints[i - 1]
        local curr = waypoints[i]
        local nextWp = waypoints[i + 1]

        local v1 = (curr.Position - prev.Position)
        local v2 = (nextWp.Position - curr.Position)

        if v1.Magnitude == 0 or v2.Magnitude == 0 then
            table.insert(simplified, curr)
        else
            local dir1 = v1.Unit
            local dir2 = v2.Unit
            local dot = dir1:Dot(dir2)
            if dot < dotThreshold then
                table.insert(simplified, curr)
            else
                -- Same direction; skip curr
            end
        end
    end
    table.insert(simplified, waypoints[count])
    return simplified
end

attachStuckDetection = function()
    if stuckConnection then
        stuckConnection:Disconnect()
        stuckConnection = nil
    end
    stuckTimer = 0
    stuckConnection = RunService.Heartbeat:Connect(function(dt)
        if not humanoidRoot then
            return
        end
        if not lastRootPosition then
            lastRootPosition = humanoidRoot.Position
            return
        end
        if not currentGoalPosition or not pathfindingBusy then
            lastRootPosition = humanoidRoot.Position
            stuckTimer = 0
            return
        end
        local currentPos = humanoidRoot.Position
        if (currentPos - lastRootPosition).Magnitude < STUCK_DISTANCE_THRESHOLD then
            stuckTimer += dt
            if stuckTimer > STUCK_TIME_THRESHOLD then
                stuckTimer = 0
                stuckRepathRequested = true
            end
        else
            stuckTimer = 0
        end
        lastRootPosition = currentPos
    end)
end

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
    simplifyCharacterCollisions(character)
    lastRootPosition = humanoidRoot.Position
    if waypointBillboard then
        waypointBillboard:Destroy()
    end
    waypointBillboard, waypointLabel = createWaypointVisualizer(character)
    attachStuckDetection()
    ensureBaseVisuals()
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

local boxesFolder = workspace:FindFirstChild("Boxes")

getBoxesContainer = function()
    if boxesFolder and boxesFolder.Parent then
        return boxesFolder
    end
    local ok, folder = pcall(function()
        return workspace:WaitForChild("Boxes", 2)
    end)
    if ok and folder then
        boxesFolder = folder
        return boxesFolder
    end
    return nil
end

local function cleanupTouchedMHBoxes()
    for box, timestamp in pairs(touchedMHBoxes) do
        if not box or not box.Parent then
            touchedMHBoxes[box] = nil
            boxFailCounts[box] = nil
        elseif timestamp + 30 < os.clock() then
            touchedMHBoxes[box] = nil
        end
    end
    for box, _ in pairs(boxFailCounts) do
        if not box or not box.Parent then
            boxFailCounts[box] = nil
        end
    end
end

local function getBoxBasePart(part)
    if not part then
        return nil
    end
    if part:IsA("Model") then
        return part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
    end
    if part:IsA("BasePart") then
        return part
    end
    return nil
end

local function updateBoxHud(part, key, text, color)
    local basePart = getBoxBasePart(part)
    if not basePart then
        return
    end
    local entry = boxHudLookup[key]
    if not entry or not entry.billboard or not entry.label or not entry.billboard.Parent then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "MH_BoxStatus"
        billboard.Adornee = basePart
        billboard.Size = UDim2.new(0, 140, 0, 36)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = workspace

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.SourceSansBold
        label.TextScaled = true
        label.TextStrokeTransparency = 0.3
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Name = "Status"
        label.Parent = billboard

        entry = {billboard = billboard, label = label}
        boxHudLookup[key] = entry
    end
    entry.label.Text = text or ""
    if color then
        entry.label.TextColor3 = color
    end
end

local function cleanupBoxHuds()
    for key, entry in pairs(boxHudLookup) do
        local billboard = entry.billboard
        if not billboard or not billboard.Parent or not billboard.Adornee or not billboard.Adornee.Parent then
            boxHudLookup[key] = nil
            if billboard and billboard.Parent then
                billboard:Destroy()
            end
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

local function moveTo(position, options)
    options = options or {}
    local allowTeleportFallback = options.allowTeleportFallback
    if allowTeleportFallback == nil then
        allowTeleportFallback = true
    end
    if not humanoid or not humanoidRoot then
        return false
    end
    if not LegitPathing then
        humanoidRoot.CFrame = CFrame.new(position)
        updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, 0, 0, nil)
        clearPathVisualizer()
        return true
    end
    if pathfindingBusy then
        return false
    end
    lastRootPosition = humanoidRoot.Position
    pathfindingBusy = true
    clearPathVisualizer()
    currentGoalPosition = position
    stuckRepathRequested = false

    local function computePath()
        local pathObj = createPathForHumanoid(humanoid)
        pathObj:ComputeAsync(humanoidRoot.Position, currentGoalPosition)
        local status = pathObj.Status
        local waypoints = pathObj:GetWaypoints()
        waypoints = simplifyWaypoints(waypoints)
        totalWaypoints = #waypoints
        currentWaypointIndex = 0
        return pathObj, status, waypoints
    end

    currentWaypointPosition = nil
    local pathObj, status, waypoints = computePath()
    if status ~= Enum.PathStatus.Success or #waypoints == 0 then
        pathfindingBusy = false
        local fallbackTarget = currentGoalPosition or position
        currentGoalPosition = nil
        currentWaypointPosition = nil
        if Settings.teleportFallback and allowTeleportFallback and fallbackTarget then
            humanoidRoot.CFrame = CFrame.new(fallbackTarget)
            updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, 0, 0, nil)
            clearPathVisualizer()
            return true
        end
        return false
    end
    addPathVisualizer(waypoints)

    local slopeHudPart, slopeHudLabel = createSlopeHud()
    local prevWaypoint = nil
    local i = 0
    while i < #waypoints do
        i += 1
        local waypoint = waypoints[i]
        currentWaypointIndex = i
        currentWaypointPosition = waypoint.Position
        updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, currentWaypointIndex, totalWaypoints, currentWaypointPosition)

        local slopeInfo
        local forceJumpThisSegment = false
        if waypoints[i + 1] then
            slopeInfo = getSegmentSlopeInfo(waypoint, waypoints[i + 1])
        elseif prevWaypoint then
            slopeInfo = getSegmentSlopeInfo(prevWaypoint, waypoint)
        end
        if slopeInfo then
            updateSlopeHud(slopeInfo, slopeHudPart, slopeHudLabel)
            local goingUp = slopeInfo.dy > 0
            local goingDown = slopeInfo.dy < 0
            local steepEnough = math.abs(slopeInfo.angleDeg) >= STEEP_UP_ANGLE_THRESHOLD
            if steepEnough and (goingUp or (Settings.jumpOnDownSlope and goingDown)) then
                forceJumpThisSegment = true
            end
        end

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
            task.wait(0.25)
        end

        local reached = false
        local connection
        connection = humanoid.MoveToFinished:Connect(function(success)
            reached = success
        end)

        humanoid:MoveTo(waypoint.Position)
        local startTime = os.clock()
        local jumpedForSlope = false
        while not reached and os.clock() - startTime < 2 do
            task.wait(0.05)
            updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, currentWaypointIndex, totalWaypoints, currentWaypointPosition)
            if stuckRepathRequested then
                break
            end
            if forceJumpThisSegment and not jumpedForSlope then
                local distanceToWaypoint = (humanoidRoot.Position - waypoint.Position).Magnitude
                if distanceToWaypoint <= 6 then
                    humanoid.UseJumpPower = true
                    if humanoid.JumpPower <= 0 then
                        humanoid.JumpPower = 50
                    end
                    humanoid.Jump = true
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    jumpedForSlope = true
                end
            end
            if (humanoidRoot.Position - waypoint.Position).Magnitude < 2 then
                reached = true
                break
            end
        end

        if connection and connection.Connected then
            connection:Disconnect()
        end

        if stuckRepathRequested then
            stuckRepathRequested = false
            pathObj, status, waypoints = computePath()
            if status ~= Enum.PathStatus.Success or #waypoints == 0 then
                pathfindingBusy = false
                local fallbackTarget = currentGoalPosition or position
                currentGoalPosition = nil
                currentWaypointPosition = nil
                if Settings.teleportFallback and allowTeleportFallback and fallbackTarget then
                    humanoidRoot.CFrame = CFrame.new(fallbackTarget)
                    updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, 0, 0, nil)
                    clearPathVisualizer()
                    return true
                end
                return false
            end
            addPathVisualizer(waypoints)
            i = 0
            continue
        end

        if not reached then
            -- Treat as interrupted: recompute the path instead of teleporting
            pathObj, status, waypoints = computePath()
            if status ~= Enum.PathStatus.Success or #waypoints == 0 then
                pathfindingBusy = false
                local fallbackTarget = currentGoalPosition or position
                currentGoalPosition = nil
                currentWaypointPosition = nil
                if Settings.teleportFallback and allowTeleportFallback and fallbackTarget then
                    humanoidRoot.CFrame = CFrame.new(fallbackTarget)
                    updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, 0, 0, nil)
                    clearPathVisualizer()
                    return true
                end
                return false
            end
            addPathVisualizer(waypoints)
            prevWaypoint = nil
            i = 0
            continue
        end
        prevWaypoint = waypoint
    end
    pathfindingBusy = false
    currentGoalPosition = nil
    currentWaypointPosition = nil
    updateWaypointVisualizer(waypointLabel, humanoid, humanoidRoot, 0, 0, nil)
    clearPathVisualizer()
    if slopeHudPart then
        slopeHudPart:Destroy()
    end
    return true
end

local function waitForBoxTouch(target)
    if not target then
        return
    end
    if target:IsA("Model") then
        target = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
    end
    if not target or not target:IsA("BasePart") then
        return
    end
    local touched = false
    local connection
    connection = target.Touched:Connect(function(hit)
        local character = LocalPlayer.Character
        if not hit or not character then
            return
        end
        if hit:IsDescendantOf(character) then
            touched = true
            if connection then
                connection:Disconnect()
            end
        end
    end)
    local deadline = os.clock() + 2
    while not touched and os.clock() < deadline do
        task.wait(0.05)
    end
    if connection and connection.Connected then
        connection:Disconnect()
    end
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

local function stopAllAutomation()
    startCollectBoxes(false)
    startCollectClovers(false)
    startOpenBoxes(false)
    startAutoRebirth(false)
    startRebirthFarm(false)
end

local function collectBoxesLoop()
    while MinersHaven.State.collectBoxes do
        cleanupTouchedMHBoxes()
        cleanupBoxHuds()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local rootPart = character:WaitForChild("HumanoidRootPart")
        ensurePositionedAtBaseForBoxes()
        local candidateBoxes = {}
        local boxContainer = getBoxesContainer()

        if boxContainer then
            -- NEW BEHAVIOR: treat ALL children inside workspace.Boxes as boxes
            for _, child in ipairs(boxContainer:GetChildren()) do
                local basePart = getBoxBasePart(child)
                if basePart then
                    local key = getMinerHavenBoxKey(child)
                    if not touchedMHBoxes[key] then
                        table.insert(candidateBoxes, {
                            part = child,
                            key = key,
                            basePart = basePart,
                        })
                        updateBoxHud(child, key, "Ready", Color3.fromRGB(85, 255, 127))
                    else
                        updateBoxHud(child, key, "Collected", Color3.fromRGB(160, 160, 160))
                    end
                end
            end
        else
            -- fallback to the original name-based detection system
            local searchSpace = workspace:GetDescendants()
            for _, descendant in ipairs(searchSpace) do
                if isMinerHavenBox(descendant) then
                    local key = getMinerHavenBoxKey(descendant)
                    local basePart = getBoxBasePart(descendant)
                    if basePart then
                        if not touchedMHBoxes[key] then
                            table.insert(candidateBoxes, {
                                part = descendant,
                                key = key,
                                basePart = basePart,
                            })
                            updateBoxHud(descendant, key, "Ready", Color3.fromRGB(85, 255, 127))
                        else
                            updateBoxHud(descendant, key, "Collected", Color3.fromRGB(160, 160, 160))
                        end
                    end
                end
            end
        end

        if #candidateBoxes == 0 then
            returnToTycoonBaseIfIdle()
            task.wait(0.35)
            continue
        end

        table.sort(candidateBoxes, function(a, b)
            local ap = a.basePart or getBoxBasePart(a.part)
            local bp = b.basePart or getBoxBasePart(b.part)
            if not ap or not bp then
                return false
            end
            return (ap.Position - rootPart.Position).Magnitude <
                (bp.Position - rootPart.Position).Magnitude
        end)

        for _, entry in ipairs(candidateBoxes) do
            if not MinersHaven.State.collectBoxes then
                break
            end
            if entry.part and entry.part.Parent then
                local fails = boxFailCounts[entry.key] or 0
                if fails >= 10 and not Settings.teleportToBoxOnPathFail then
                    updateBoxHud(entry.part, entry.key, "No path (skipped)", Color3.fromRGB(255, 120, 120))
                    continue
                end
                local before = rootPart.CFrame
                local targetPart = entry.basePart or getBoxBasePart(entry.part)
                if targetPart and targetPart:IsA("BasePart") then
                    updateBoxHud(targetPart, entry.key, "Pathing...", Color3.fromRGB(60, 170, 255))
                    local success = moveTo(targetPart.Position, {allowTeleportFallback = Settings.teleportToBoxOnPathFail})
                    if success then
                        boxFailCounts[entry.key] = 0
                        waitForBoxTouch(targetPart)
                        updateBoxHud(targetPart, entry.key, "Collected", Color3.fromRGB(160, 160, 160))
                    else
                        fails = fails + 1
                        boxFailCounts[entry.key] = fails
                        updateBoxHud(targetPart, entry.key, "No path", Color3.fromRGB(255, 120, 120))
                    end
                end
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
            returnToTycoonBaseIfIdle()
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
            returnToTycoonBaseIfIdle()
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

local function getTycoonBasePart()
    local base = getTycoonBase()
    if not base then
        return nil
    end
    if base:IsA("BasePart") then
        return base
    end
    if base.PrimaryPart then
        return base.PrimaryPart
    end
    return base:FindFirstChildWhichIsA("BasePart")
end

-- Initialize the rebirth HUD once base info is resolvable
ensureRebirthHud()

goToTycoonBase = function()
    local targetPart = getTycoonBasePart()
    if not targetPart or not targetPart:IsA("BasePart") then
        return false
    end
    if not humanoidRoot then
        return false
    end
    return moveTo(targetPart.Position)
end

returnToTycoonBaseIfIdle = function()
    if not Settings.returnHomeOnIdle then
        return
    end
    local now = os.clock()
    if now - lastReturnHome < 2 then
        return
    end
    if goToTycoonBase() then
        lastReturnHome = now
    end
end

MinersHaven.Modules.Pathing.goToTycoonBase = goToTycoonBase

ensurePositionedAtBaseForBoxes = function()
    local basePart = getTycoonBasePart()
    if not basePart or not humanoidRoot then
        return
    end
    local distance = (humanoidRoot.Position - basePart.Position).Magnitude
    if distance <= BOX_FARM_BASE_RADIUS then
        return
    end
    ensureOnBaseForLayouts(1, true)
    local layoutConfig = MinersHaven.Data.LayoutAutomation
    local firstLayout = layoutConfig.layoutSelections.first or LAYOUT_OPTIONS[1]
    loadLayout(firstLayout, false)
end

ensureOnBaseForLayouts = function(minSeconds, allowTeleport)
    minSeconds = minSeconds or 1
    local stableStart = nil
    while true do
        local basePart = ensureBaseDetector()
        if not basePart or not humanoidRoot then
            return false
        end
        local localPos = basePart.CFrame:PointToObjectSpace(humanoidRoot.Position)
        local halfSize = basePart.Size * 0.5
        local onTop =
            math.abs(localPos.X) <= halfSize.X and
            math.abs(localPos.Z) <= halfSize.Z and
            localPos.Y >= -halfSize.Y and
            localPos.Y <= halfSize.Y

        if not onTop then
            stableStart = nil
            if LegitPathing then
                moveTo(basePart.Position, {allowTeleportFallback = false})
            elseif allowTeleport then
                humanoidRoot.CFrame = CFrame.new(basePart.Position)
            else
                moveTo(basePart.Position, {allowTeleportFallback = true})
            end
            task.wait(0.2)
            updateBaseDetectorHud(false)
        else
            if not stableStart then
                stableStart = os.clock()
            end
            if os.clock() - stableStart >= minSeconds then
                updateBaseDetectorHud(true)
                ensureRebirthHud()
                return true
            end
            task.wait(0.1)
        end
    end
end

local function executeAtTycoonBase(action, allowTeleport)
    if type(action) ~= "function" then
        return false, "missing action"
    end
    local shouldTeleport = MinersHaven.Data.LayoutAutomation.teleportToTycoon ~= false
    if allowTeleport ~= nil then
        shouldTeleport = allowTeleport
    end
    local base = getTycoonBase()
    if not base then
        warn("[MinersHaven] Unable to locate tycoon base for layout work.")
        return false, "no base"
    end
    local targetPart = getTycoonBasePart()
    if not targetPart then
        warn("[MinersHaven] Tycoon base has no usable part.")
        return false, "no surface"
    end
    local teleported = false
    savedLayoutPosition = nil
    if shouldTeleport and humanoidRoot then
        local distance = (humanoidRoot.Position - targetPart.Position).Magnitude
        if distance > BASE_ON_TOP_RADIUS then
            savedLayoutPosition = humanoidRoot.CFrame
            moveTo(targetPart.Position, {allowTeleportFallback = true})
            teleported = true
        end
    end
    local positioned = ensureOnBaseForLayouts(1, shouldTeleport)
    if not positioned then
        return false, "not on base"
    end
    local ok, result = pcall(action)
    if teleported and savedLayoutPosition then
        moveTo(savedLayoutPosition.Position)
        savedLayoutPosition = nil
    end
    return ok, result
end

local function loadLayout(layoutName, allowTeleport)
    if not layoutName or layoutName == "" then
        return false
    end
    if not LayoutsService then
        warn("[MinersHaven] Layout service unavailable.")
        return false
    end
    local ok, err = executeAtTycoonBase(function()
        LayoutsService:InvokeServer("Load", layoutName)
    end, allowTeleport)
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

local function runLayoutSequence(teleportOverride)
    if not MinersHaven.State.rebirthFarm then
        return
    end
    local config = MinersHaven.Data.LayoutAutomation
    local firstLayout = config.layoutSelections.first or LAYOUT_OPTIONS[1]
    loadLayout(firstLayout, teleportOverride)
    if config.layout2Enabled and MinersHaven.State.rebirthFarm then
        if not waitForCashThreshold(config.layout2Cost) then
            return
        end
        if config.layout2Withdraw then
            destroyAll()
        end
        local secondLayout = config.layoutSelections.second or LAYOUT_OPTIONS[2]
        loadLayout(secondLayout, teleportOverride)
    end
    if config.layout3Enabled and MinersHaven.State.rebirthFarm then
        if not waitForCashThreshold(config.layout3Cost) then
            return
        end
        if config.layout3Withdraw then
            destroyAll()
        end
        local thirdLayout = config.layoutSelections.third or LAYOUT_OPTIONS[3]
        loadLayout(thirdLayout, teleportOverride)
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
    if value then
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
        -- 1) Get current rebirth cost from UI
        local priceNumber = getRebirthPriceFromUI()

        if not priceNumber or priceNumber <= 0 then
            -- Couldn't read price, try again in a bit
            task.wait(1)
            continue
        end

        -- 2) Check if we have enough money yet
        local currentCash = getPlayerCash()

        if currentCash >= priceNumber then
            -- We can rebirth

            -- 3) Actually rebirth
            ReplicatedStorage.Rebirth:InvokeServer()
            -- Small cooldown so we don't spam
            task.wait(0.5)
            -- If rebirth farm is ON, load layouts before/around the rebirth
            if MinersHaven.State.rebirthFarm then
                runLayoutSequence(MinersHaven.Data.LayoutAutomation.teleportForAutoRebirth)
            end
        else
            -- Not enough money yet, poll again soon
            task.wait(0.1)
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
MinersHaven.Modules.Farming.stopAll = stopAllAutomation

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

    boxesSection:addToggle({
        title = "Teleport fallback on path fail",
        default = Settings.teleportFallback,
        callback = function(value)
            Settings.teleportFallback = value
        end,
    })

    boxesSection:addToggle({
        title = "Return home when idle",
        default = Settings.returnHomeOnIdle,
        callback = function(value)
            Settings.returnHomeOnIdle = value
        end,
    })

    boxesSection:addToggle({
        title = "Teleport to box on path fail",
        default = Settings.teleportToBoxOnPathFail,
        callback = function(value)
            Settings.teleportToBoxOnPathFail = value
        end,
    })

    boxesSection:addToggle({
        title = "Jump on down slopes",
        default = Settings.jumpOnDownSlope,
        callback = function(value)
            Settings.jumpOnDownSlope = value
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

    autoRebirthSection:addToggle({
        title = "Teleport to Tycoon for layouts",
        default = layoutConfig.teleportToTycoon,
        callback = function(value)
            layoutConfig.teleportToTycoon = value
        end,
    })

    autoRebirthSection:addToggle({
        title = "Teleport to Tycoon during Auto Rebirth",
        default = layoutConfig.teleportForAutoRebirth,
        callback = function(value)
            layoutConfig.teleportForAutoRebirth = value
        end,
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

    local utilitiesSection = minersPage:addSection({title = "Utilities"})

    utilitiesSection:addButton({
        title = "Return to Tycoon",
        callback = function()
            goToTycoonBase()
        end,
    })

    utilitiesSection:addButton({
        title = "Stop all automation",
        callback = stopAllAutomation,
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
        if not baseVisualsWatcherConnection then
            baseVisualsWatcherConnection = RunService.Heartbeat:Connect(function()
                local basePart = getTycoonBasePart()
                if basePart then
                    ensureBaseVisuals()
                end

                local ready = rebirthHudLabel ~= nil
                    and rebirthHudBillboard ~= nil
                    and rebirthHudBillboard.Parent ~= nil
                    and baseDetectorPart ~= nil
                    and baseDetectorPart.Parent ~= nil

                if ready then
                    baseVisualsWatcherConnection:Disconnect()
                    baseVisualsWatcherConnection = nil
                end
            end)
        end
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
