--[[
\tAnimal Simulator automation module extracted from RevampLua.lua.
    Version: 1.04

    The goal of this split file is to retain only the functionality that is
    required when the loader detects we are inside Animal Simulator
    (PlaceId 5712833750). All helpers that were previously exposed through
    the `Revamp` table are reorganised below under the `AnimalSim` namespace.

    The implementation is intentionally faithful to the original logic so the
    in-game behaviour remains unchanged while still keeping the local count of
    this file well under Roblox's limit. Shared helpers that are reused by the
    other games will be duplicated in their respective split files.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

local DEFAULT_THEME = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255),
}

local AnimalSim = {
    PlaceId = 5712833750,
    Services = {
        Players = Players,
        RunService = RunService,
        PathfindingService = PathfindingService,
        UserInputService = UserInputService,
        ReplicatedStorage = ReplicatedStorage,
    },
    Data = {
        SafeZones = {},
        Teleporters = {},
        prefixes = {},
        Zones = {},
    },
    State = {
        autoPVP = false,
        killAura = false,
        autoJump = false,
        autoEat = false,
        autoFight = false,
        autoZone = false,
        followAlly = false,
        autoZoneFakeouts = false,
        autoFlightChase = false,
        autoFireball = false,
        followTarget = false,
        followDistance = 10,
        selectedPlayer = nil,
	        legitMode = true,
	        autoSelectTarget = false,
	        visualizerEnabled = false,
	        version = 1.04,
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
-- Data bootstrap
---------------------------------------------------------------------

local prefixes = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/gaston1799/HostedFiles/refs/heads/main/table.lua"
))()

AnimalSim.Data.prefixes = prefixes

local SAFE_ZONE_POLYGON = {
    Vector2.new(-47.553, 585.940),
    Vector2.new(-277.322, 672.467),
    Vector2.new(-344.602, 483.516),
    Vector2.new(-114.346, 401.818),
}

AnimalSim.Data.SafeZones.Main = {polygon = SAFE_ZONE_POLYGON}

Players.PlayerRemoving:Connect(function(player)
    if AnimalSim.State.selectedPlayer == player then
        AnimalSim.State.selectedPlayer = nil
    end
end)

local MANTIS_TELEPORT_ENTRY = Vector3.new(200.921, 708.134, -16601.699)
local MANTIS_RETURN_POSITION = Vector3.new(67.475, 641.687, 476.413)
local MANTIS_INSIDE_POSITION = Vector3.new(283.289, 660.560, -16678.158)

AnimalSim.Data.Teleporters.MantisEntry = {
    entry = MANTIS_TELEPORT_ENTRY,
    destination = Vector3.new(591.384, 647.570, -16412.795),
    waitTime = 0.75,
}

AnimalSim.Data.Teleporters.MantisPortal = {
    entry = MANTIS_TELEPORT_ENTRY,
    destination = MANTIS_INSIDE_POSITION,
    waitTime = 0.8,
    arrivalRadius = 30,
    penalty = 0,
    minDirectDistance = 0,
    teleporterName = "MantisPortal",
    insidePosition = MANTIS_INSIDE_POSITION,
    returnPosition = MANTIS_RETURN_POSITION,
}

---------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------

local DAMAGE_REMOTE = ReplicatedStorage:FindFirstChild("jdskhfsIIIllliiIIIdchgdIiIIIlIlIli", true)
local TELEPORTERS = {}

local humanoid
local humanoidRoot
local prefixesBySuffix = prefixes
local deathPose
local justDied = false
local incDMG = 100
local autoEatTask
local autoEatEnabled = false
local autoFireballTask
local autoFireballEnabled = false
local autoZoneTask
local autoZoneEnabled = false
local autoPVPTask
local autoPVPEnabled = false
local autoFlightChaseTask
local autoFlightChaseEnabled = false
local autoZoneCancelToken = 0
local followTaskRunning = false
local autoJumpEnabled = false
local autoJumpConnection
local autoJumpCharacterConnection
local characterAddedConnection
local characterRemovingConnection

local AUTO_PVP_POLL_RATE = 0.35
local AUTO_ZONE_POLL_RATE = 0.35
local AUTO_ZONE_PREDICTION_TIME = 0.25
local AUTO_ZONE_RENDER_LERP = 0.22
AnimalSim.Modules.Combat.AutoZoneConfig = AnimalSim.Modules.Combat.AutoZoneConfig or {
    cameraDistance = 10,
    cameraHeight = 7,
    cameraPosLerp = 0.35,
    indicatorTransparency = 0.85,
    indicatorPadding = Vector3.new(0.25, 0.25, 0.25),
    projectileCooldown = 1.8,
    fireballMouseLockDuration = 0.12,
    followAllyMinDistance = 3,
    followAllyTargetRange = 20,
}
local DEBUG_DAMAGE_LOG = true
local FALLBACK_ATTACKER_RADIUS = 45

local autoZoneIndicatorPart
local autoZoneDesiredAimPoint
local autoZoneRenderConnection
local autoZoneLastIndicatorCF
local autoZoneDebugMyBox
local autoZoneDebugTargetBox
local autoAimOldCameraType
local autoAimOldCameraSubject
local autoAimLockCount = 0
local fireballMouseLockCount = 0
local fireballOldMouseBehavior

local ensureAutoZoneIndicator
local hideAutoZoneIndicator
local findZoneTarget
local aimAndFireAtPlayer

local function acquireAimLock()
    autoAimLockCount = autoAimLockCount + 1
    if autoAimLockCount > 1 then
        return
    end

    local camera = workspace.CurrentCamera
    if camera then
        autoAimOldCameraType = camera.CameraType
        autoAimOldCameraSubject = camera.CameraSubject
        camera.CameraType = Enum.CameraType.Scriptable
    end
end

local function releaseAimLock()
    if autoAimLockCount <= 0 then
        autoAimLockCount = 0
        return
    end
    autoAimLockCount = autoAimLockCount - 1
    if autoAimLockCount > 0 then
        return
    end

    local camera = workspace.CurrentCamera
    if camera and autoAimOldCameraType then
        camera.CameraType = autoAimOldCameraType
        if autoAimOldCameraSubject then
            camera.CameraSubject = autoAimOldCameraSubject
        end
    end

    autoAimOldCameraType = nil
    autoAimOldCameraSubject = nil
end

local function flashFireballMouseLock(durationSeconds)
    durationSeconds = tonumber(durationSeconds) or 0.12
    if durationSeconds <= 0 then
        durationSeconds = 0.12
    end

    fireballMouseLockCount = fireballMouseLockCount + 1
    if fireballMouseLockCount == 1 then
        pcall(function()
            fireballOldMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end)
    end

    task.delay(durationSeconds, function()
        if fireballMouseLockCount <= 0 then
            fireballMouseLockCount = 0
            return
        end
        fireballMouseLockCount = fireballMouseLockCount - 1
        if fireballMouseLockCount > 0 then
            return
        end
        pcall(function()
            if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                if fireballOldMouseBehavior then
                    UserInputService.MouseBehavior = fireballOldMouseBehavior
                else
                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                end
            end
        end)
        fireballOldMouseBehavior = nil
    end)
end

local canEngagePlayer
local damageplayer
local loadAwScript
local function isInsideSafeZone(position)
    local polygon = AnimalSim.Data.SafeZones.Main.polygon
    if not polygon or #polygon < 3 then
        return false
    end
    local x = position.X
    local z = position.Z
    local inside = false
    local j = #polygon
    for i = 1, #polygon do
        local pi = polygon[i]
        local pj = polygon[j]
        local denom = pj.Y - pi.Y
        local condition = ((pi.Y > z) ~= (pj.Y > z)) and (x < (pj.X - pi.X) * (z - pi.Y) / denom + pi.X)
        if condition then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function getPackInfo(playerName)
    local teamsFolder = workspace:FindFirstChild("Teams")
    if not teamsFolder then
        return nil, nil
    end

    for _, team in ipairs(teamsFolder:GetChildren()) do
        local teamLeader
        local hasMember = false

        for _, member in ipairs(team:GetChildren()) do
            local ok, value = pcall(function()
                return member.Value
            end)
            if ok then
                local resolvedName = value
                if typeof(value) == "Instance" then
                    resolvedName = value.Name
                end

                if member.Name == "leader" then
                    teamLeader = resolvedName
                end

                if resolvedName == playerName then
                    hasMember = true
                end
            end
        end

        if hasMember then
            return teamLeader, team.Name
        end
    end

    return nil, nil
end

local function teamCheck(name)
    if not name then
        return false
    end

    local myLeader, myTeamName = getPackInfo(LocalPlayer.Name)
    local otherLeader, otherTeamName = getPackInfo(name)

    if myLeader and otherLeader and myLeader == otherLeader then
        return true
    end
    if myTeamName and otherTeamName and myTeamName == otherTeamName then
        return true
    end

    return false
end

local function myTeam(name)
    name = name or LocalPlayer.Name
    local leader, teamName = getPackInfo(name)
    return {leader, teamName}
end

local function findClosestPlayer()
    local localCharacter = LocalPlayer.Character
    if not localCharacter then
        return nil
    end
    local localRoot = localCharacter.PrimaryPart
    if not localRoot then
        return nil
    end
    local closest
    local closestDistance = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character.PrimaryPart
            if humanoidInstance and humanoidInstance.Health > 0 and root and not teamCheck(player.Name) then
                local distance = (localRoot.Position - root.Position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closest = player
                end
            end
        end
    end
    return closest
end

local function findClosestEnemy()
    local localCharacter = LocalPlayer.Character
    if not localCharacter then
        return nil
    end
    local localRoot = localCharacter.PrimaryPart
    if not localRoot then
        return nil
    end
    local myInfo = myTeam()
    local myLeader = myInfo[1]
    local myTeamName = myInfo[2]
    local closest
    local closestDistance = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if humanoidInstance and humanoidInstance.Health > 0 and root then
                local otherInfo = {}
                local ok, result = pcall(myTeam, character and character.Name or player.Name)
                if ok then
                    otherInfo = result or {}
                end
                local sameLeader = myLeader ~= nil and otherInfo[1] == myLeader
                local sameTeam = myTeamName ~= nil and otherInfo[2] == myTeamName
                if not sameLeader and not sameTeam then
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closest = player
                    end
                end
            end
        end
    end
    return closest
end

local Visualizer
local drawLineBetweenPositions
local defineNilLocals
local moveToTarget
local LegitPathing = AnimalSim.State.legitMode

local function PredictPlayerPosition(player, deltaTime)
    local character = player and player.Character
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    deltaTime = deltaTime or 0.2
    local velocity = root.AssemblyLinearVelocity or root.Velocity or Vector3.zero
    return root.Position + velocity * deltaTime
end

local function teleportInFrontOfPlayer(targetPlayerName)
    local targetPlayer = Players:FindFirstChild(targetPlayerName)
    if not targetPlayer then
        return
    end
    local targetCharacter = targetPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not (targetCharacter and targetRoot) then
        return
    end
    local predictedPosition = targetRoot.Position + (targetRoot.Velocity or Vector3.zero)
    local character = LocalPlayer.Character
    if character and character.PrimaryPart then
        if Visualizer.enabled then
            drawLineBetweenPositions(character.PrimaryPart.Position, predictedPosition, Color3.fromRGB(170, 120, 255), 0.8)
        end
        if LegitPathing then
            defineNilLocals()
            local humanoidInstance = humanoid
            if humanoidInstance then
                local ok, err = pcall(function()
                    moveToTarget(predictedPosition, humanoidInstance, {
                        cancelled = function()
                            return not LegitPathing
                        end,
                        arrivalDistance = 6,
                    })
                end)
                if not ok then
                    warn("[AnimalSim] failed to walk in front of player", err)
                end
            end
        else
            character:SetPrimaryPartCFrame(CFrame.new(predictedPosition))
        end
    end
end

local function increaseByPercentage(number, percentage)
    number = tonumber(number)
    percentage = tonumber(percentage)
    if not number or not percentage then
        error("Both arguments must be valid numbers.")
    end
    if percentage < 0 then
        error("Percentage should be a positive value.")
    end
    return number + number * (percentage / 100)
end

local function conv(cash)
    for _, prefix in ipairs(prefixesBySuffix) do
        if typeof(cash) == "string" and cash:match(prefix.Prefix) then
            local numeric = tonumber(cash:split(prefix.Prefix)[1])
            if numeric then
                return numeric * prefix.Number
            end
        end
    end
    return tonumber(cash) or 0
end

local function comparCash(a)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
    local ownCash = cashValue and tonumber(string.split(cashValue.Value, "$")[2]) or 0
    return conv(a) < ownCash
end

Visualizer = {
    enabled = false,
    folder = nil,
    defaultColor = Color3.fromRGB(45, 170, 255),
    defaultDuration = 1.25,
}

local SAFE_ZONE_VIZ_COLOR = Color3.fromRGB(80, 255, 120)
local SAFE_ZONE_VIZ_TRANSPARENCY = 0.78
local SAFE_ZONE_VIZ_THICKNESS = 0.15
local SAFE_ZONE_EDGE_THICKNESS = 0.22

local safeZoneVizPlane
local safeZoneVizEdges = {}
local safeZoneVizY

local FOLLOW_RANGE_MIN_COLOR = Color3.fromRGB(120, 185, 255)
local FOLLOW_RANGE_MAX_COLOR = Color3.fromRGB(255, 215, 90)
local FOLLOW_RANGE_VIZ_TRANSPARENCY = 0.62
local FOLLOW_RANGE_VIZ_THICKNESS = 0.2

local followRangeVizMin
local followRangeVizMax

local function ensureVisualizerFolder()
    if Visualizer.folder and Visualizer.folder.Parent then
        return Visualizer.folder
    end
    local folder = Instance.new("Folder")
    folder.Name = "AnimalSimVisualizer"
    folder.Parent = workspace
    Visualizer.folder = folder
    return folder
end

local function computeSafeZoneBounds()
    local polygon = AnimalSim.Data.SafeZones.Main and AnimalSim.Data.SafeZones.Main.polygon
    if not polygon or #polygon < 3 then
        return nil
    end

    local minX = math.huge
    local maxX = -math.huge
    local minZ = math.huge
    local maxZ = -math.huge

    for _, point in ipairs(polygon) do
        minX = math.min(minX, point.X)
        maxX = math.max(maxX, point.X)
        minZ = math.min(minZ, point.Y)
        maxZ = math.max(maxZ, point.Y)
    end

    return minX, maxX, minZ, maxZ
end

local function sampleGroundYAt(x, z)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.IgnoreWater = true

    local blacklist = {}
    if Visualizer.folder then
        table.insert(blacklist, Visualizer.folder)
    end
    if LocalPlayer.Character then
        table.insert(blacklist, LocalPlayer.Character)
    end
    raycastParams.FilterDescendantsInstances = blacklist

    local origin = Vector3.new(x, 5000, z)
    local ok, result = pcall(function()
        return workspace:Raycast(origin, Vector3.new(0, -10000, 0), raycastParams)
    end)
    if ok and result then
        return result.Position.Y
    end

    local fallback = (humanoidRoot and humanoidRoot.Position.Y) or 0
    return fallback
end

local function ensureSafeZoneVisualization()
    if not Visualizer.enabled then
        return
    end

    local minX, maxX, minZ, maxZ = computeSafeZoneBounds()
    if not minX then
        return
    end

    local folder = ensureVisualizerFolder()

    local centerX = (minX + maxX) / 2
    local centerZ = (minZ + maxZ) / 2
    if not safeZoneVizY then
        safeZoneVizY = sampleGroundYAt(centerX, centerZ)
    end

    if not safeZoneVizPlane then
        safeZoneVizPlane = Instance.new("Part")
        safeZoneVizPlane.Name = "SafeZonePlane"
        safeZoneVizPlane.Anchored = true
        safeZoneVizPlane.CanCollide = false
        safeZoneVizPlane.CanQuery = false
        safeZoneVizPlane.CanTouch = false
        safeZoneVizPlane.Material = Enum.Material.Neon
    end

    safeZoneVizPlane.Color = SAFE_ZONE_VIZ_COLOR
    safeZoneVizPlane.Transparency = SAFE_ZONE_VIZ_TRANSPARENCY
    safeZoneVizPlane.Size = Vector3.new(
        math.max(1, maxX - minX),
        SAFE_ZONE_VIZ_THICKNESS,
        math.max(1, maxZ - minZ)
    )
    safeZoneVizPlane.CFrame = CFrame.new(centerX, safeZoneVizY + SAFE_ZONE_VIZ_THICKNESS / 2, centerZ)
    safeZoneVizPlane.Parent = folder

    local polygon = AnimalSim.Data.SafeZones.Main.polygon
    local edgeY = safeZoneVizY + SAFE_ZONE_VIZ_THICKNESS + 0.03
    for index = 1, #polygon do
        local a2 = polygon[index]
        local b2 = polygon[(index % #polygon) + 1]
        local a = Vector3.new(a2.X, edgeY, a2.Y)
        local b = Vector3.new(b2.X, edgeY, b2.Y)
        local offset = b - a
        local length = offset.Magnitude
        local edge = safeZoneVizEdges[index]
        if not edge then
            edge = Instance.new("Part")
            edge.Name = ("SafeZoneEdge_%02d"):format(index)
            edge.Anchored = true
            edge.CanCollide = false
            edge.CanQuery = false
            edge.CanTouch = false
            edge.Material = Enum.Material.Neon
            edge.Transparency = 0.15
            edge.Color = SAFE_ZONE_VIZ_COLOR
            safeZoneVizEdges[index] = edge
        end
        edge.Size = Vector3.new(SAFE_ZONE_EDGE_THICKNESS, SAFE_ZONE_EDGE_THICKNESS, math.max(0.1, length))
        edge.CFrame = CFrame.new(a, b) * CFrame.new(0, 0, -length / 2)
        edge.Parent = folder
    end
end

local function clearSafeZoneVisualization()
    safeZoneVizY = nil
    if safeZoneVizPlane then
        pcall(function()
            safeZoneVizPlane:Destroy()
        end)
        safeZoneVizPlane = nil
    end
    for index, edge in pairs(safeZoneVizEdges) do
        if edge then
            pcall(function()
                edge:Destroy()
            end)
        end
        safeZoneVizEdges[index] = nil
    end
end

local function clearFollowRangeVisualization()
    if followRangeVizMin then
        pcall(function()
            followRangeVizMin:Destroy()
        end)
        followRangeVizMin = nil
    end
    if followRangeVizMax then
        pcall(function()
            followRangeVizMax:Destroy()
        end)
        followRangeVizMax = nil
    end
end

local function ensureFollowRangeCircle(existing, name, color)
    if existing and existing.Parent then
        return existing
    end
    local folder = ensureVisualizerFolder()
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Shape = Enum.PartType.Cylinder
    part.Material = Enum.Material.Neon
    part.Transparency = FOLLOW_RANGE_VIZ_TRANSPARENCY
    part.Color = color
    part.CastShadow = false
    part.Parent = folder
    return part
end

local function updateFollowRangeVisualization(centerPosition, minDistance, maxRange)
    if not Visualizer.enabled then
        return
    end
    if not centerPosition then
        local localRoot = humanoidRoot or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
        centerPosition = localRoot and localRoot.Position or nil
    end
    if not centerPosition then
        clearFollowRangeVisualization()
        return
    end

    minDistance = math.max(0, tonumber(minDistance) or 0)
    maxRange = math.max(minDistance, tonumber(maxRange) or 0)
    if maxRange <= 0 then
        clearFollowRangeVisualization()
        return
    end

    local thickness = FOLLOW_RANGE_VIZ_THICKNESS
    do
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.IgnoreWater = true

        local blacklist = {}
        if Visualizer.folder then
            table.insert(blacklist, Visualizer.folder)
        end
        if LocalPlayer.Character then
            table.insert(blacklist, LocalPlayer.Character)
        end
        local anchor = AnimalSim.Modules.Combat._followAllyAnchor
        if anchor and anchor.Character then
            table.insert(blacklist, anchor.Character)
        end
        raycastParams.FilterDescendantsInstances = blacklist

        local origin = centerPosition + Vector3.new(0, 80, 0)
        local result = workspace:Raycast(origin, Vector3.new(0, -300, 0), raycastParams)
        if result then
            centerPosition = Vector3.new(centerPosition.X, result.Position.Y, centerPosition.Z)
        end
    end
    local y = centerPosition.Y + thickness / 2 + 0.05

    followRangeVizMin = ensureFollowRangeCircle(followRangeVizMin, "FollowRangeMin", FOLLOW_RANGE_MIN_COLOR)
    followRangeVizMax = ensureFollowRangeCircle(followRangeVizMax, "FollowRangeMax", FOLLOW_RANGE_MAX_COLOR)

    local minDiameter = math.max(0.2, minDistance * 2)
    local maxDiameter = math.max(0.2, maxRange * 2)
    followRangeVizMin.Size = Vector3.new(minDiameter, thickness, minDiameter)
    followRangeVizMax.Size = Vector3.new(maxDiameter, thickness, maxDiameter)
    followRangeVizMin.CFrame = CFrame.new(centerPosition.X, y, centerPosition.Z)
    followRangeVizMax.CFrame = CFrame.new(centerPosition.X, y, centerPosition.Z)
end

local function clearVisualizerFolder()
    if Visualizer.folder then
        Visualizer.folder:Destroy()
        Visualizer.folder = nil
    end
    clearSafeZoneVisualization()
    clearFollowRangeVisualization()
end

local function setVisualizerEnabled(enabled)
    if Visualizer.enabled == enabled then
        return
    end
    Visualizer.enabled = enabled
    AnimalSim.State.visualizerEnabled = enabled
    if enabled then
        ensureVisualizerFolder()
        ensureSafeZoneVisualization()
    else
        clearVisualizerFolder()
    end
end

local function drawSegment(startPos, endPos, color, duration)
    if not Visualizer.enabled then
        return
    end
    local folder = ensureVisualizerFolder()
    local offset = endPos - startPos
    local length = offset.Magnitude
    if length < 0.05 then
        local point = Instance.new("Part")
        point.Shape = Enum.PartType.Ball
        point.Size = Vector3.new(0.45, 0.45, 0.45)
        point.Anchored = true
        point.CanCollide = false
        point.Material = Enum.Material.Neon
        point.Transparency = 0.25
        point.Color = color or Visualizer.defaultColor
        point.CFrame = CFrame.new(startPos)
        point.Name = "VizPoint"
        point.Parent = folder
        Debris:AddItem(point, duration or Visualizer.defaultDuration)
        return
    end

    local bar = Instance.new("Part")
    bar.Anchored = true
    bar.CanCollide = false
    bar.Material = Enum.Material.Neon
    bar.Transparency = 0.35
    bar.Color = color or Visualizer.defaultColor
    bar.Size = Vector3.new(0.18, 0.18, length)
    bar.CFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -length / 2)
    bar.Name = "VizSegment"
    bar.Parent = folder
    Debris:AddItem(bar, duration or Visualizer.defaultDuration)
end

local function drawPath(waypoints, color, duration)
    if not Visualizer.enabled or not waypoints then
        return
    end
    for index = 1, #waypoints - 1 do
        local startWaypoint = waypoints[index]
        local finishWaypoint = waypoints[index + 1]
        local startPos = (startWaypoint and startWaypoint.Position) or startWaypoint
        local endPos = (finishWaypoint and finishWaypoint.Position) or finishWaypoint
        if startPos and endPos then
            drawSegment(startPos, endPos, color, duration)
        end
    end
end

drawLineBetweenPositions = function(fromPosition, toPosition, color, duration)
    if not Visualizer.enabled then
        return
    end
    drawSegment(fromPosition, toPosition, color, duration)
end

local function trimTrailingZeros(numberString)
    local integer, fractional = numberString:match("^(%-?%d+)%.(%d+)$")
    if not integer then
        return numberString
    end
    fractional = fractional:gsub("0+$", "")
    if fractional == "" then
        return integer
    end
    return integer .. "." .. fractional
end

local function getPrefixNumber(entry)
    if not entry then
        return 1
    end
    return entry.Number or entry.number or entry.Value or entry.value or 1
end

local function getPrefixText(entry)
    if not entry then
        return ""
    end
    return entry.Prefix or entry.prefix or entry.Suffix or entry.suffix or ""
end

local function formatCombatNumber(value)
    local number = tonumber(value)
    if not number then
        return value ~= nil and tostring(value) or "?"
    end
    local absNumber = math.abs(number)
    local chosenPrefix
    if prefixes and #prefixes > 0 then
        chosenPrefix = prefixes[1]
        for index = #prefixes, 1, -1 do
            local candidate = prefixes[index]
            if absNumber >= getPrefixNumber(candidate) then
                chosenPrefix = candidate
                break
            end
        end
    end
    local scale = getPrefixNumber(chosenPrefix)
    if scale <= 0 then
        scale = 1
    end
    local scaled = number / scale
    local formatted
    if absNumber < 1 then
        formatted = string.format("%.2f", scaled)
    elseif math.abs(scaled) >= 100 then
        formatted = string.format("%.0f", scaled)
    elseif math.abs(scaled) >= 10 then
        formatted = string.format("%.1f", scaled)
    else
        formatted = string.format("%.2f", scaled)
    end
    formatted = trimTrailingZeros(formatted)
    if formatted == "-0" then
        formatted = "0"
    end
    local prefixText = getPrefixText(chosenPrefix)
    if prefixText ~= "" then
        formatted = formatted .. prefixText
    end
    return formatted
end

local DAMAGE_STAT_NAMES = {"Damage", "damage", "DMG", "Dmg"}

local function getPlayerLevel(player)
    if not player then
        return nil
    end
    local stats = player:FindFirstChild("leaderstats")
    if not stats then
        return nil
    end
    local levelValue = stats:FindFirstChild("Level") or stats:FindFirstChild("level")
    if not levelValue then
        return nil
    end
    return tonumber(levelValue.Value)
end

local function getPlayerHumanoid(player)
    local character = player and player.Character
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function getCharacterHealth(player)
    local humanoid = getPlayerHumanoid(player)
    if humanoid then
        local current = humanoid.Health
        local max = humanoid.MaxHealth
        if max <= 0 then
            max = current
        end
        return current, math.max(current, max)
    end
    local level = getPlayerLevel(player)
    if level then
        local estimated = level * 20
        return estimated, estimated
    end
    return nil, nil
end

local function estimatePlayerDamage(player)
    if not player then
        return nil
    end
    local stats = player:FindFirstChild("leaderstats")
    if stats then
        for _, name in ipairs(DAMAGE_STAT_NAMES) do
            local stat = stats:FindFirstChild(name)
            if stat then
                local value = tonumber(stat.Value)
                if value then
                    return value
                end
            end
        end
    end
    local level = getPlayerLevel(player)
    if level then
        if level < 40 then
            return (level * 2) + 10
        end
        return level * 2
    end
    local _, maxHealth = getCharacterHealth(player)
    if maxHealth and maxHealth > 0 then
        return maxHealth / 10
    end
    return nil
end

local function computeHitCount(health, damage)
    if not health or health <= 0 or not damage or damage <= 0 then
        return "?"
    end
    local hits = math.ceil(health / damage)
    if hits < 1 then
        hits = 1
    end
    return tostring(hits)
end

local OVERHEAD_TAG_NAME = "AnimalSimOverhead"
local OVERHEAD_UPDATE_INTERVAL = 0.25
local OverheadEntries = {}
local OverheadConnections = {}
local overheadAccumulator = 0

local function destroyPlayerGui(player)
    local entry = OverheadEntries[player]
    if entry then
        if entry.gui then
            entry.gui:Destroy()
        end
        OverheadEntries[player] = nil
    end
end

local function stopTrackingPlayer(player)
    destroyPlayerGui(player)
    local connections = OverheadConnections[player]
    if connections then
        for _, connection in pairs(connections) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        OverheadConnections[player] = nil
    end
end

local function computeOverheadStats(targetPlayer)
    local localPlayer = LocalPlayer
    if not localPlayer or not targetPlayer then
        return "?", "?", "?", 0
    end
    local localHealth, localMaxHealth = getCharacterHealth(localPlayer)
    local enemyHealth, enemyMaxHealth = getCharacterHealth(targetPlayer)
    local enemyDamage = estimatePlayerDamage(targetPlayer)
    local localDamage = estimatePlayerDamage(localPlayer)

    local hitsToKillEnemy = computeHitCount(enemyMaxHealth or enemyHealth, localDamage)
    local hitsToKillYou = computeHitCount(localMaxHealth or localHealth, enemyDamage)
    local hpValue = enemyHealth or enemyMaxHealth
    local hpText = hpValue and formatCombatNumber(hpValue) or "?"
    local ratio = 0
    if enemyHealth and enemyMaxHealth and enemyMaxHealth > 0 then
        ratio = math.clamp(enemyHealth / enemyMaxHealth, 0, 1)
    end
    return hitsToKillEnemy, hitsToKillYou, hpText, ratio
end

local function createGuiForCharacter(player, character)
    if player == LocalPlayer then
        return
    end
    if not character then
        return
    end
    destroyPlayerGui(player)
    local adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not adornee then
        local ok, result = pcall(function()
            return character:WaitForChild("Head", 2)
        end)
        if ok then
            adornee = result
        end
    end
    if not adornee then
        return
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = OVERHEAD_TAG_NAME
    billboard.Size = UDim2.new(0, 170, 0, 70)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 200
    billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    billboard.Adornee = adornee
    billboard.Parent = adornee

    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.Parent = billboard

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "Info"
    infoLabel.BackgroundTransparency = 1
    infoLabel.Size = UDim2.new(1, -10, 0, 32)
    infoLabel.Position = UDim2.new(0, 5, 0, 5)
    infoLabel.Font = Enum.Font.GothamSemibold
    infoLabel.TextSize = 14
    infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoLabel.TextStrokeTransparency = 0.6
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextWrapped = true
    infoLabel.Text = "Hits (You->Them): ?\nHits (Them->You): ?"
    infoLabel.Parent = frame

    local barBackground = Instance.new("Frame")
    barBackground.Name = "HPBar"
    barBackground.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    barBackground.BorderColor3 = Color3.fromRGB(10, 10, 10)
    barBackground.BorderSizePixel = 0
    barBackground.Size = UDim2.new(1, -10, 0, 10)
    barBackground.Position = UDim2.new(0, 5, 0, 44)
    barBackground.Parent = frame

    local barFill = Instance.new("Frame")
    barFill.Name = "Fill"
    barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    barFill.BorderSizePixel = 0
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.Parent = barBackground

    local hpLabel = Instance.new("TextLabel")
    hpLabel.Name = "HPLabel"
    hpLabel.BackgroundTransparency = 1
    hpLabel.Size = UDim2.new(1, -10, 0, 16)
    hpLabel.Position = UDim2.new(0, 5, 0, 56)
    hpLabel.Font = Enum.Font.Gotham
    hpLabel.TextSize = 12
    hpLabel.TextColor3 = Color3.fromRGB(215, 215, 215)
    hpLabel.TextStrokeTransparency = 0.8
    hpLabel.TextXAlignment = Enum.TextXAlignment.Left
    hpLabel.Text = "HP: ?"
    hpLabel.Parent = frame

    OverheadEntries[player] = {
        gui = billboard,
        info = infoLabel,
        hpLabel = hpLabel,
        barFill = barFill
    }
end

local function trackPlayer(player)
    if player == LocalPlayer then
        return
    end

    stopTrackingPlayer(player)

    local connections = {}
    connections.characterAdded = player.CharacterAdded:Connect(function(character)
        task.spawn(function()
            createGuiForCharacter(player, character)
        end)
    end)
    connections.characterRemoving = player.CharacterRemoving:Connect(function()
        destroyPlayerGui(player)
    end)
    OverheadConnections[player] = connections

    if player.Character then
        task.spawn(function()
            createGuiForCharacter(player, player.Character)
        end)
    end
end

RunService.Heartbeat:Connect(function(dt)
    if next(OverheadEntries) == nil then
        overheadAccumulator = 0
        return
    end

    overheadAccumulator = overheadAccumulator + dt
    if overheadAccumulator < OVERHEAD_UPDATE_INTERVAL then
        return
    end
    overheadAccumulator = 0

    local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

    local toCleanup = {}
    for player, entry in pairs(OverheadEntries) do
        if not player.Parent then
            table.insert(toCleanup, player)
        elseif not entry.gui or not entry.gui.Parent then
            table.insert(toCleanup, player)
        else
            local enemyRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local distance = math.huge
            if localRoot and enemyRoot then
                distance = (enemyRoot.Position - localRoot.Position).Magnitude
            end
            local isVisible = distance <= 100
            if isVisible and AnimalSim.State.autoZone and AnimalSim.State.followAlly and not teamCheck(player.Name) then
                local config = AnimalSim.Modules.Combat.AutoZoneConfig
                local anchor = AnimalSim.Modules.Combat._followAllyAnchor
                local anchorRoot = anchor and anchor.Character and anchor.Character:FindFirstChild("HumanoidRootPart")
                if AnimalSim.Modules.Combat._autoZoneLockedTarget ~= player then
                    if anchorRoot and enemyRoot then
                        local maxRange = tonumber(config and config.followAllyTargetRange) or 20
                        local inRange = (enemyRoot.Position - anchorRoot.Position).Magnitude <= maxRange
                        if not inRange then
                            isVisible = false
                        end
                    else
                        isVisible = false
                    end
                end
            end
            entry.gui.Enabled = isVisible
            if isVisible then
                local hitsToKillEnemy, hitsToKillYou, hpText, ratio = computeOverheadStats(player)
                entry.info.Text = string.format("Hits (You->Them): %s\nHits (Them->You): %s", hitsToKillEnemy, hitsToKillYou)
                entry.hpLabel.Text = "HP: " .. hpText
                entry.barFill.Size = UDim2.new(ratio, 0, 1, 0)
                if ratio > 0.6 then
                    entry.barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
                elseif ratio > 0.3 then
                    entry.barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 70)
                else
                    entry.barFill.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
                end
            end
        end
    end

    for _, player in ipairs(toCleanup) do
        stopTrackingPlayer(player)
    end
end)

for _, otherPlayer in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        trackPlayer(otherPlayer)
    end)
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        trackPlayer(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    stopTrackingPlayer(player)
end)

local lastAttacker = {player = nil, timestamp = 0, damage = 0}
local RECENT_ATTACK_WINDOW = 8

local function recordRecentAttacker(player, damage)
    if not player or player == LocalPlayer then
        return
    end
    if teamCheck(player.Name) then
        return
    end
    lastAttacker.player = player
    lastAttacker.timestamp = os.clock()
    lastAttacker.damage = damage or 0
end

local function clearRecentAttacker(player)
    if not player or lastAttacker.player == player then
        lastAttacker.player = nil
        lastAttacker.timestamp = 0
        lastAttacker.damage = 0
    end
end

local function getRecentAttackerPlayer()
    if lastAttacker.player and lastAttacker.player.Parent then
        if os.clock() - lastAttacker.timestamp <= RECENT_ATTACK_WINDOW then
            return lastAttacker.player
        end
    end
    return nil
end

Players.PlayerRemoving:Connect(clearRecentAttacker)

local function findAttackerByDamage(damageTaken)
    if not damageTaken or damageTaken <= 0 then
        return nil
    end
    local localCharacter = LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    local bestPlayer
    local bestScore = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not teamCheck(player.Name) then
            local estimate = estimatePlayerDamage(player)
            if estimate and estimate > 0 then
                local diff = math.min(
                    math.abs(estimate - damageTaken),
                    math.abs((estimate + 10) - damageTaken),
                    math.abs((math.max(0, estimate - 10)) - damageTaken)
                )
                local tolerance = math.max(20, estimate * 0.4)
                if diff <= tolerance then
                    local score = diff
                    if localRoot then
                        local enemyRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if enemyRoot then
                            local distance = (enemyRoot.Position - localRoot.Position).Magnitude
                            score = score + distance * 0.05
                        end
                    end
                    if score < bestScore then
                        bestScore = score
                        bestPlayer = player
                    end
                end
            end
        end
    end
    return bestPlayer
end

local function findClosestEnemyOutsideSafeZone(maxDistance)
    if typeof(isInsideSafeZone) ~= "function" then
        print('WTH? isInsideSafeZone is not a function', typeof(isInsideSafeZone))
        return nil
    end

    local localCharacter = LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return nil
    end

    local closestPlayer
    local closestDistance = maxDistance or math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not teamCheck(player.Name) then
            local character = player.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if humanoidInstance and humanoidInstance.Health > 0 and root then
                if not isInsideSafeZone(root.Position) then
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
    end

    return closestPlayer
end


local playersService
local selfPlayer
local char
local root
local mouse
local rebirthValue
local finding = false
local pathfindingComplete = true
local doneMoving = true

local function waitForChar()
    while not Players.LocalPlayer.Character do
        task.wait()
    end
    return Players.LocalPlayer.Character
end

local function defineLocals()
    waitForChar()
    local success, result

    success, result = pcall(function()
        playersService = Players
        selfPlayer = playersService.LocalPlayer
    end)
    if not success then
        warn("Failed to resolve players service", result)
        return
    end

    success, result = pcall(function()
        char = selfPlayer.Character
    end)
    if not success then
        warn("Failed to resolve character", result)
        return
    end

    success, result = pcall(function()
        humanoid = char:WaitForChild("Humanoid")
        humanoidRoot = char:WaitForChild("HumanoidRootPart")
    end)
    if not success then
        warn("Failed to resolve humanoid", result)
        return
    end

    mouse = selfPlayer:GetMouse()

    success, result = pcall(function()
        rebirthValue = selfPlayer:FindFirstChild("Rebirths")
    end)
    if not success then
        warn("Failed to resolve rebirth value", result)
    end

    pathfindingComplete = true
    finding = false
    doneMoving = true
end

defineNilLocals = function()
    if not playersService then
        playersService = Players
    end
    if not selfPlayer then
        selfPlayer = playersService.LocalPlayer
    end
    if not char then
        char = selfPlayer and selfPlayer.Character or waitForChar()
    end
    if not humanoid and char then
        humanoid = char:FindFirstChildOfClass("Humanoid")
    end
    if not humanoidRoot and char then
        humanoidRoot = char:FindFirstChild("HumanoidRootPart")
    end
    if not mouse and selfPlayer then
        mouse = selfPlayer:GetMouse()
    end
    if not rebirthValue and selfPlayer then
        rebirthValue = selfPlayer:FindFirstChild("Rebirths")
    end
end

local function waitDoneMove()
    while not doneMoving do
        task.wait()
    end
    return true
end

local function getClosest(instances)
    if not humanoidRoot then
        return nil
    end
    local closestPart
    local closestDistance = math.huge
    for _, instance in ipairs(instances) do
        local part = instance
        if instance:IsA("Model") then
            part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
        end
        if part and part:IsA("BasePart") then
            local distance = (part.Position - humanoidRoot.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestPart = part
            end
        end
    end
    return closestPart, closestDistance
end

local function getPos()
    local inSafe = {}
    local safeZone1 = {86.3, 493.6}
    local safeZone2 = {-3.5, 388.2}
    local mine = myTeam() or {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not (character and humanoidInstance and rootPart) then
            inSafe[player.Name] = true
        else
            local x = rootPart.Position.X
            local z = rootPart.Position.Z
            local ok, otherInfo = pcall(myTeam, character.Name)
            if not ok then
                otherInfo = {}
            end
            local sameTeam = mine[2] and otherInfo[2] == mine[2]
            if safeZone1[1] > x and safeZone1[2] > z and safeZone2[1] < x and safeZone2[2] < z then
                if (not mine[2]) or humanoidInstance.Health == 0 or sameTeam then
                    inSafe[player.Name] = true
                end
            end
        end
    end
    return inSafe
end

local function stayNearPlayer()
    while AnimalSim.State.followTarget do
        task.wait()
        defineNilLocals()
        local selected = AnimalSim.State.selectedPlayer
        local character = LocalPlayer.Character
        if selected and character and humanoidRoot and selected.Character then
            local targetRoot = selected.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local distance = (targetRoot.Position - humanoidRoot.Position).Magnitude
                if distance > (AnimalSim.State.followDistance or 10) then
                    local followDistance = AnimalSim.State.followDistance or 10
                    local velocity = targetRoot.AssemblyLinearVelocity or targetRoot.Velocity or Vector3.zero
                    local speed = velocity.Magnitude
                    local isMoving = speed > 1
                    if isMoving then
                        local predictedPosition = PredictPlayerPosition(selected, 0.2)
                        if predictedPosition then
                            local forward = (speed > 0) and velocity.Unit or targetRoot.CFrame.LookVector
                            local destination = predictedPosition - forward * followDistance
                            drawLineBetweenPositions(humanoidRoot.Position, destination, Color3.fromRGB(255, 200, 90), 0.4)
                            humanoidRoot.CFrame = CFrame.new(destination, destination + forward)
                        else
                            humanoidRoot.CFrame = targetRoot.CFrame
                        end
                    else
                        local destination = targetRoot.Position - targetRoot.CFrame.LookVector * followDistance
                        drawLineBetweenPositions(humanoidRoot.Position, destination, Color3.fromRGB(255, 200, 90), 0.4)
                        humanoidRoot.CFrame = CFrame.new(destination, targetRoot.Position)
                    end
                end
            end
        end
    end
end

local function runFollowLoop()
    followTaskRunning = true
    stayNearPlayer()
    followTaskRunning = false
end

local function setFollowTargetEnabled(value)
    AnimalSim.State.followTarget = value
    AnimalSim.State.autoSelectTarget = value
    if value then
        defineNilLocals()
        if not followTaskRunning then
            task.spawn(runFollowLoop)
        end
    else
        local timeout = os.clock() + 2
        while followTaskRunning and os.clock() < timeout do
            task.wait()
        end
    end
end

local function setLegitMode(value)
    LegitPathing = value
    AnimalSim.State.legitMode = value
end

local function bindAutoJumpToHumanoid(humanoidInstance)
    if autoJumpConnection then
        autoJumpConnection:Disconnect()
        autoJumpConnection = nil
    end
    if not humanoidInstance then
        return
    end
    autoJumpConnection = humanoidInstance.StateChanged:Connect(function(_, newState)
        if autoJumpEnabled and newState == Enum.HumanoidStateType.Landed then
            task.delay(0.1, function()
                if autoJumpEnabled and humanoidInstance.Parent then
                    humanoidInstance.Jump = true
                end
            end)
        end
    end)
end

local function setAutoJump(value)
    autoJumpEnabled = value
    AnimalSim.State.autoJump = value
    defineNilLocals()
    local humanoidInstance = humanoid
    if value then
        if humanoidInstance then
            bindAutoJumpToHumanoid(humanoidInstance)
            humanoidInstance.Jump = true
        end
        if not autoJumpCharacterConnection then
            autoJumpCharacterConnection = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
                if not autoJumpEnabled then
                    return
                end
                local newHumanoid = newCharacter:WaitForChild("Humanoid")
                bindAutoJumpToHumanoid(newHumanoid)
                newHumanoid.Jump = true
            end)
        end
    else
        if autoJumpConnection then
            autoJumpConnection:Disconnect()
            autoJumpConnection = nil
        end
    end
end

local function setAutoFight(value)
    AnimalSim.State.autoFight = value
    if DEBUG_DAMAGE_LOG then
        print(("[AnimalSim][Damage] AutoFight set to %s"):format(tostring(value)))
    end
end


local function getPathToPosition(targetPosition, humanoidInstance)
    local startPosition = humanoidInstance.RootPart.Position
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,
        AgentHeight = 6,
        AgentCanJump = true,
        AgentCanClimb = true,
        Costs = {
            Water = 20,
            Neon = math.huge,
        },
    })
    path:ComputeAsync(startPosition, targetPosition)
    return path
end

moveToTarget = function(target, humanoidInstance, options)
    options = options or {}
    humanoidInstance = humanoidInstance or humanoid
    if not humanoidInstance then
        return false
    end
    local targetPosition
    if typeof(target) == "CFrame" then
        targetPosition = target.Position
    elseif typeof(target) == "Vector3" then
        targetPosition = target
    elseif typeof(target) == "Instance" and target:IsA("BasePart") then
        targetPosition = target.Position
    else
        warn("Invalid moveToTarget target")
        return false
    end
    local path = getPathToPosition(targetPosition, humanoidInstance)
    if path.Status ~= Enum.PathStatus.Success then
        return false
    end
    doneMoving = false
    drawPath(path:GetWaypoints(), Visualizer.defaultColor, 1.2)
    for _, waypoint in ipairs(path:GetWaypoints()) do
        if options.cancelled and options.cancelled() then
            break
        end
        humanoidInstance:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoidInstance.Jump = true
        end
        humanoidInstance.MoveToFinished:Wait()
    end
    doneMoving = true
    return true
end

local function waitWithCancel(duration, cancelled)
    local deadline = os.clock() + duration
    while os.clock() < deadline do
        if cancelled and cancelled() then
            return false
        end
        task.wait(0.05)
    end
    return true
end

local function registerTeleporter(name, config)
    if typeof(name) ~= "string" then
        return false
    end
    config = config or {}
    local entry = config.entry
    local destination = config.destination
    if typeof(entry) == "CFrame" then
        entry = entry.Position
    end
    if typeof(destination) == "CFrame" then
        destination = destination.Position
    end
    if not entry or not destination then
        warn(string.format("[AnimalSim] Teleporter '%s' missing entry or destination", name))
        return false
    end
    TELEPORTERS[name] = {
        entry = entry,
        destination = destination,
        waitTime = config.waitTime or 0.75,
        arrivalRadius = config.arrivalRadius or 12,
        penalty = config.penalty or 40,
        enabled = config.enabled ~= false,
        maxEntryDistance = config.maxEntryDistance,
        minDirectDistance = config.minDirectDistance,
        snapOnFail = config.snapOnFail ~= false,
        cooldown = config.cooldown or 0,
        lastUsed = 0,
        description = config.description,
        postDelay = config.postDelay or 0,
        teleporterName = config.teleporterName,
        returnPosition = config.returnPosition,
        insidePosition = config.insidePosition,
    }
    return true
end

local function useTeleporter(name, humanoidInstance, options)
    local tele = TELEPORTERS[name]
    if not tele or not tele.enabled then
        return false
    end
    humanoidInstance = humanoidInstance or humanoid
    if not humanoidInstance then
        return false
    end
    if tele.cooldown > 0 and (os.clock() - tele.lastUsed) < tele.cooldown then
        return false
    end
    local cancelled = options and options.cancelled
    if tele.maxEntryDistance then
        local rootPart = humanoidInstance.RootPart
        if not rootPart or (rootPart.Position - tele.entry).Magnitude > tele.maxEntryDistance then
            return false
        end
    end
    if not moveToTarget(tele.entry, humanoidInstance, {cancelled = cancelled}) then
        return false
    end
    if not waitWithCancel(tele.waitTime, cancelled) then
        return false
    end
    local rootPart = humanoidInstance.RootPart
    if not rootPart then
        return false
    end
    if (rootPart.Position - tele.destination).Magnitude > tele.arrivalRadius then
        if tele.snapOnFail then
            local ok = pcall(function()
                rootPart.CFrame = CFrame.new(tele.destination)
            end)
            if not ok then
                return false
            end
        else
            return false
        end
    end
    if tele.postDelay > 0 and not waitWithCancel(tele.postDelay, cancelled) then
        return false
    end
    tele.lastUsed = os.clock()
    return true
end

local function clearTeleporters()
    table.clear(TELEPORTERS)
end

local function followDynamicTarget(targetPlayer, humanoidInstance, options)
    options = options or {}
    humanoidInstance = humanoidInstance or humanoid
    if not humanoidInstance or not targetPlayer then
        return false
    end
    local arrivalDistance = options.arrivalDistance or 140
    local repathDistance = options.repathDistance or 18
    local maxIterations = options.maxIterations or 12
    local path = PathfindingService:CreatePath({
        AgentRadius = humanoidInstance.HipHeight / 2,
        AgentHeight = humanoidInstance.HipHeight,
        AgentCanJump = true,
        AgentJumpHeight = humanoidInstance.JumpHeight,
        AgentMaxSlope = humanoidInstance.MaxSlopeAngle,
        AgentMaxStepHeight = humanoidInstance.HipHeight,
    })
    local lastGoal
    local iterations = 0
    local reachedGoal = false
    while iterations < maxIterations do
        iterations = iterations + 1
        if options.cancelled and options.cancelled() then
            break
        end
        local targetCharacter = targetPlayer.Character
        local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
        local rootPart = humanoidInstance.RootPart
        if not (targetRoot and rootPart) then
            break
        end
        local currentDistance = (targetRoot.Position - rootPart.Position).Magnitude
        if currentDistance <= arrivalDistance then
            reachedGoal = true
            humanoidInstance:Move(Vector3.new())
            break
        end
        local needRepath = not lastGoal or (targetRoot.Position - lastGoal).Magnitude >= repathDistance
        if needRepath then
            path:ComputeAsync(rootPart.Position, targetRoot.Position)
            lastGoal = targetRoot.Position
        end
        if path.Status ~= Enum.PathStatus.Success then
            task.wait(0.1)
        else
            drawPath(path:GetWaypoints(), Color3.fromRGB(110, 90, 255), 0.9)
            for _, waypoint in ipairs(path:GetWaypoints()) do
                if options.cancelled and options.cancelled() then
                    break
                end
                humanoidInstance:MoveTo(waypoint.Position)
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoidInstance.Jump = true
                end
                humanoidInstance.MoveToFinished:Wait()
                rootPart = humanoidInstance.RootPart
                targetCharacter = targetPlayer.Character
                targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
                if not (targetRoot and rootPart) then
                    break
                end
                currentDistance = (targetRoot.Position - rootPart.Position).Magnitude
                if currentDistance <= arrivalDistance then
                    reachedGoal = true
                    humanoidInstance:Move(Vector3.new())
                    return true
                end
                if (targetRoot.Position - lastGoal).Magnitude >= repathDistance then
                    break
                end
            end
        end
    end
    humanoidInstance:Move(Vector3.new())
    return reachedGoal
end

local function tryTeleportRoute(humanoidInstance, targetPosition, options)
    local rootPart = humanoidInstance and humanoidInstance.RootPart
    if not rootPart then
        return false
    end
    local directDistance = (rootPart.Position - targetPosition).Magnitude
    local best
    local bestCost
    local now = os.clock()
    local margin = options and options.margin or 30
    for name, tele in pairs(TELEPORTERS) do
        if tele.enabled then
            local passesMin = not tele.minDirectDistance or directDistance >= tele.minDirectDistance
            local passesCooldown = not (tele.cooldown > 0 and (now - tele.lastUsed) < tele.cooldown)
            if passesMin and passesCooldown then
                local distToEntry = (tele.entry - rootPart.Position).Magnitude
                local withinEntry = not tele.maxEntryDistance or distToEntry <= tele.maxEntryDistance
                if withinEntry then
                    local cost = distToEntry + tele.penalty
                    if not best or cost + margin < bestCost then
                        best = name
                        bestCost = cost
                    end
                end
            end
        end
    end
    if not best then
        return false
    end
    if Visualizer.enabled then
        local chosen = TELEPORTERS[best]
        if chosen and humanoidInstance and humanoidInstance.RootPart then
            drawLineBetweenPositions(humanoidInstance.RootPart.Position, chosen.entry, Color3.fromRGB(90, 255, 180), 1.2)
            drawLineBetweenPositions(chosen.entry, chosen.destination, Color3.fromRGB(90, 255, 180), 1.2)
        end
    end
    return useTeleporter(best, humanoidInstance, options)
end

local function startAutoFireball()
    if autoFireballEnabled then
        return
    end
    autoFireballEnabled = true
    AnimalSim.State.autoFireball = true
    acquireAimLock()
    if autoFireballTask then
        return
    end
    autoFireballTask = task.spawn(function()
        while autoFireballEnabled do
            defineNilLocals()
            local indicator = ensureAutoZoneIndicator()
            local target
            if AnimalSim.State.followTarget then
                local selected = AnimalSim.State.selectedPlayer
                if selected and selected.Parent and selected ~= LocalPlayer and not teamCheck(selected.Name) then
                    local humanoidInstance = getPlayerHumanoid(selected)
                    if humanoidInstance and humanoidInstance.Health > 0 then
                        target = selected
                    end
                end
            else
                local selected = AnimalSim.State.selectedPlayer
                if selected and selected.Parent and selected ~= LocalPlayer and not teamCheck(selected.Name) then
                    local humanoidInstance = getPlayerHumanoid(selected)
                    if humanoidInstance and humanoidInstance.Health > 0 then
                        target = selected
                    end
                end
                if not target then
                    target = findZoneTarget(false)
                end
            end
            local ok, err = pcall(function()
                if target and canEngagePlayer(target) then
                    aimAndFireAtPlayer(target, indicator, true)
                    if autoZoneDesiredAimPoint then
                        local targetCF, targetSize = AnimalSim.Modules.Combat.computeAutoZoneIndicatorBounds(target, autoZoneDesiredAimPoint)
                        pcall(function()
                            indicator.Parent = workspace
                            if targetSize then
                                indicator.Size = targetSize
                            end
                            if targetCF then
                                indicator.CFrame = targetCF
                            end
                        end)
                        local camera = workspace.CurrentCamera
                        local myChar = LocalPlayer.Character
                        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                        if camera and myRoot then
                            local rootPos = myRoot.Position
                            local delta = autoZoneDesiredAimPoint - rootPos
                            local dir = delta.Magnitude > 1e-3 and delta.Unit or myRoot.CFrame.LookVector
                            local config = AnimalSim.Modules.Combat.AutoZoneConfig
                            local desiredPos = rootPos - dir * config.cameraDistance + Vector3.new(0, config.cameraHeight, 0)
                            local desired = CFrame.lookAt(desiredPos, autoZoneDesiredAimPoint)
                            camera.CFrame = camera.CFrame:Lerp(desired, config.cameraPosLerp)
                        end
                    end
                else
                    if not autoZoneEnabled then
                        autoZoneDesiredAimPoint = nil
                    end
                    hideAutoZoneIndicator()
                end
            end)
            if not ok then
                warn("[AutoFire] failed", err)
                task.wait(0.3)
            else
                task.wait(0.08)
            end
        end
        autoFireballTask = nil
    end)
end

local function stopAutoFireball()
    if not autoFireballEnabled then
        return
    end
    autoFireballEnabled = false
    AnimalSim.State.autoFireball = false
    while autoFireballTask do
        task.wait()
    end
    if not autoZoneEnabled then
        autoZoneDesiredAimPoint = nil
        hideAutoZoneIndicator()
    end
    releaseAimLock()
    if not autoZoneEnabled and autoZoneRenderConnection then
        autoZoneRenderConnection:Disconnect()
        autoZoneRenderConnection = nil
    end
end

local function hitHumanoid(targetHumanoid)
    if not targetHumanoid or not targetHumanoid.Parent then
        return false
    end
    local ok, err = pcall(DAMAGE_REMOTE.FireServer, DAMAGE_REMOTE, targetHumanoid, 1)
    if not ok then
        warn("Failed to strike humanoid:", err)
        return false
    end
    return true
end

local function getClosestEnemyHumanoid()
    local enemy = findClosestEnemy()
    local character = enemy and enemy.Character
    local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
    return humanoidInstance
end

local function getSelectedTargetHumanoid()
    local selected = AnimalSim.State.selectedPlayer
    if not selected then
        return nil
    end
    if teamCheck(selected.Name) then
        return nil
    end
    local character = selected.Character
    if not character then
        return nil
    end
    local humanoidInstance = character:FindFirstChildOfClass("Humanoid")
    if humanoidInstance and humanoidInstance.Health > 0 then
        return humanoidInstance
    end
    return nil
end

local function autoEatLoop()
    local foodToolIndex = 1
    local foodCooldowns = {}

    local function collectFoodTools()
        local tools = {}
        local character = LocalPlayer.Character
        if character then
            for _, tool in ipairs(character:GetChildren()) do
                if tool:IsA("Tool") and tool.Name == "Food" then
                    table.insert(tools, tool)
                end
            end
        end
        local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer.Backpack
        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and tool.Name == "Food" then
                    table.insert(tools, tool)
                end
            end
        end
        return tools
    end

    local function getNextFoodTool()
        local tools = collectFoodTools()
        local toolCount = #tools
        if toolCount == 0 then
            return nil, 0.5
        end
        if foodToolIndex > toolCount then
            foodToolIndex = 1
        end

        local now = os.clock()
        local shortestWait = 2
        for _ = 1, toolCount do
            local tool = tools[foodToolIndex]
            local lastUsed = foodCooldowns[tool]
            local remaining = lastUsed and (2 - (now - lastUsed)) or 0

            foodToolIndex = foodToolIndex + 1
            if foodToolIndex > toolCount then
                foodToolIndex = 1
            end

            if remaining <= 0 then
                return tool, 0.1
            end
            if remaining < shortestWait then
                shortestWait = remaining
            end
        end

        return nil, math.max(shortestWait, 0.1)
    end

    while autoEatEnabled do
        local tool, waitTime = getNextFoodTool()
        if not tool then
            task.wait(waitTime or 0.5)
        else
            local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local humanoidInstance = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
            if humanoidInstance.Health < humanoidInstance.MaxHealth then
                if tool.Parent == LocalPlayer.Backpack then
                    humanoidInstance:EquipTool(tool)
                    task.wait(0.1)
                end
                pcall(function()
                    tool:Activate()
                end)
                foodCooldowns[tool] = os.clock()
            end
            task.wait(waitTime or 0.1)
        end
    end
    autoEatTask = nil
end

local function startAutoEat()
    if autoEatEnabled then
        return
    end
    autoEatEnabled = true
    AnimalSim.State.autoEat = true
    autoEatTask = task.spawn(autoEatLoop)
end

local function stopAutoEat()
    if not autoEatEnabled then
        return
    end
    autoEatEnabled = false
    AnimalSim.State.autoEat = false
    while autoEatTask do
        task.wait()
    end
end

local function hptp()
    local localHumanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not localHumanoid then
        return
    end
    local oldHealth = localHumanoid.Health
    if DEBUG_DAMAGE_LOG then
        print(("[AnimalSim][Damage] Bound health listener. HP=%.1f/%.1f"):format(oldHealth, localHumanoid.MaxHealth))
    end
    localHumanoid:GetPropertyChangedSignal("Health"):Connect(function()
        local newHealth = localHumanoid.Health
        if newHealth < 1 then
            deathPose = LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame
            justDied = true
            if DEBUG_DAMAGE_LOG then
                print("[AnimalSim][Damage] Died; captured deathPose")
            end
        end
        if newHealth < oldHealth then
            local damageTaken = oldHealth - newHealth
            local attackerByDamage = findAttackerByDamage(damageTaken)
            local recentAttacker = getRecentAttackerPlayer()
            local fallbackAttacker = findClosestEnemyOutsideSafeZone(FALLBACK_ATTACKER_RADIUS)
            local attacker = attackerByDamage or recentAttacker or fallbackAttacker
            if DEBUG_DAMAGE_LOG then
                print(("[AnimalSim][Damage] Took %.1f damage (%.1f -> %.1f). attacker=%s autoFight=%s"):format(
                    damageTaken,
                    oldHealth,
                    newHealth,
                    attacker and attacker.Name or "nil",
                    tostring(AnimalSim.State.autoFight)
                ))
                if attackerByDamage then
                    print("[AnimalSim][Damage] attackerByDamage:", attackerByDamage.Name)
                end
                if recentAttacker then
                    print("[AnimalSim][Damage] recentAttacker:", recentAttacker.Name)
                end
                if fallbackAttacker then
                    print("[AnimalSim][Damage] fallbackClosest:", fallbackAttacker.Name)
                end
            end
            if attacker then
                recordRecentAttacker(attacker, damageTaken)
                local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
                if attackerRoot and isInsideSafeZone(attackerRoot.Position) then
                    if DEBUG_DAMAGE_LOG then
                        print("[AnimalSim][Damage] Attacker in safe zone; ignoring:", attacker.Name)
                    end
                    clearRecentAttacker(attacker)
                else
                    local engageAllowed = canEngagePlayer(attacker)
                    if DEBUG_DAMAGE_LOG then
                        print(("[AnimalSim][Damage] teamCheck=%s canEngage=%s"):format(
                            tostring(teamCheck(attacker.Name)),
                            tostring(engageAllowed)
                        ))
                    end
                    if AnimalSim.State.autoFight and engageAllowed then
                        damageplayer(attacker.Name)
                        clearRecentAttacker(attacker)
                    end
                end
            end
        end
        oldHealth = newHealth
    end)
end

local function onLocalCharacterAdded(newCharacter)
    if not newCharacter then
        return
    end

    char = newCharacter
    humanoid = nil
    humanoidRoot = nil
    defineNilLocals()

    local successHumanoid, newHumanoid = pcall(function()
        return newCharacter:WaitForChild("Humanoid", 5)
    end)
    if successHumanoid and newHumanoid then
        humanoid = newHumanoid
        if autoJumpEnabled then
            bindAutoJumpToHumanoid(newHumanoid)
            newHumanoid.Jump = true
        end
    end

    local successRoot, newRoot = pcall(function()
        return newCharacter:WaitForChild("HumanoidRootPart", 5)
    end)
    if successRoot and newRoot then
        humanoidRoot = newRoot
    end

    hptp()

    if AnimalSim.State.followTarget and not followTaskRunning then
        task.spawn(runFollowLoop)
    end
end

local function onLocalCharacterRemoving()
    char = nil
    humanoid = nil
    humanoidRoot = nil
    if autoJumpConnection then
        autoJumpConnection:Disconnect()
        autoJumpConnection = nil
    end
end

---------------------------------------------------------------------
-- Combat routines
---------------------------------------------------------------------

local auraTask
local auraActive = false
local farmTask
local farmActive = false

local function farmPassive()
    while farmActive do
        local ok, targetHumanoid = pcall(getClosestEnemyHumanoid)
        if ok and targetHumanoid then
            local hitOk, err = pcall(hitHumanoid, targetHumanoid)
            if not hitOk then
                warn("[AnimalSim] farmPassive hit failed:", err)
            end
        elseif not ok then
            warn("[AnimalSim] farmPassive target lookup failed:", targetHumanoid)
        end
        task.wait(0.25)
    end
    farmTask = nil
end

local function startFarmLoop()
    if farmTask then
        return
    end
    farmTask = task.spawn(farmPassive)
end

local function stopFarmLoop()
    if not farmTask then
        return
    end
    farmActive = false
    while farmTask do
        task.wait()
    end
    farmTask = nil
end

local function setFarmActive(value)
    if farmActive == value then
        return
    end
    farmActive = value
    AnimalSim.State.autoFight = value
    if value then
        startFarmLoop()
    else
        stopFarmLoop()
    end
end

local function auraLoop()
    while auraActive do
        local targetHumanoid
        if AnimalSim.State.followTarget then
            targetHumanoid = getSelectedTargetHumanoid()
        end
        if not targetHumanoid then
            local ok, closest = pcall(getClosestEnemyHumanoid)
            if ok then
                targetHumanoid = closest
            else
                warn("[AnimalSim] auraLoop target lookup failed:", closest)
            end
        end
        if targetHumanoid then
            local hitOk, err = pcall(hitHumanoid, targetHumanoid)
            if not hitOk then
                warn("[AnimalSim] auraLoop hit failed:", err)
            end
        end
        task.wait(0.1)
    end
    auraTask = nil
end

local function setAuraActive(value)
    if auraActive == value then
        return
    end
    auraActive = value
    AnimalSim.State.killAura = value
    if value and not auraTask then
        auraTask = task.spawn(auraLoop)
    elseif not value and auraTask then
        while auraTask do
            task.wait()
        end
        auraTask = nil
    end
end

damageplayer = function(targetName)
    local target = targetName and Players:FindFirstChild(targetName) or getClosestEnemyHumanoid()
    if typeof(target) == "Instance" and target:IsA("Humanoid") then
        hitHumanoid(target)
        return true
    end
    if target and target.Character then
        local humanoidInstance = target.Character:FindFirstChildOfClass("Humanoid")
        if humanoidInstance then
            hitHumanoid(humanoidInstance)
            return true
        end
    end
    return false
end

local function engageEnemy(enemyPlayer)
    if not enemyPlayer then
        return
    end
    local targetCharacter = enemyPlayer.Character
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then
        return
    end
    if isInsideSafeZone(targetHumanoid.RootPart.Position) then
        return
    end
    tryTeleportRoute(humanoid, targetHumanoid.RootPart.Position, {margin = 30})
    followDynamicTarget(enemyPlayer, humanoid, {})
    hitHumanoid(targetHumanoid)
end

canEngagePlayer = function(targetPlayer)
    if not targetPlayer then
        return false
    end
    local localLevel = getPlayerLevel(LocalPlayer)
    local targetLevel = getPlayerLevel(targetPlayer)
    if localLevel and targetLevel then
        local allowedLevel = increaseByPercentage(localLevel, incDMG)
        return allowedLevel >= targetLevel
    end
    return true
end

findZoneTarget = function(ignoreTeamCheck)
    local character = LocalPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return nil
    end
    local closestPlayer
    local closestDistance = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (ignoreTeamCheck or not teamCheck(player.Name)) then
            local targetCharacter = player.Character
            local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
            local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
            if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
                if not isInsideSafeZone(targetRoot.Position) then
                    local distance = (targetRoot.Position - localRoot.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
    end
    return closestPlayer
end

local function getClosestAllyWithin(range)
    if not humanoidRoot then
        return nil, nil, nil
    end

    local myPosition = humanoidRoot.Position
    local bestPlayer = nil
    local bestDistance = range or math.huge
    local bestRoot = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and teamCheck(player.Name) then
            local character = player.Character
            local allyRoot = character and character:FindFirstChild("HumanoidRootPart")
            local allyHumanoid = character and character:FindFirstChildOfClass("Humanoid")
            if allyRoot and allyHumanoid and allyHumanoid.Health > 0 then
                local distance = (allyRoot.Position - myPosition).Magnitude
                if distance <= bestDistance then
                    bestDistance = distance
                    bestPlayer = player
                    bestRoot = allyRoot
                end
            end
        end
    end

    return bestPlayer, bestDistance, bestRoot
end

local function followAllyStepForAutoZone()
    if not (autoZoneEnabled and AnimalSim.State.followAlly) then
        AnimalSim.Modules.Combat._followAllyAnchor = nil
        return nil, nil
    end
    if not humanoidRoot then
        return nil, nil
    end

    local config = AnimalSim.Modules.Combat.AutoZoneConfig
    local minDistance = tonumber(config and config.followAllyMinDistance) or 3
    local maxRange = tonumber(config and config.followAllyTargetRange) or 20
    minDistance = math.max(0, minDistance)
    maxRange = math.max(minDistance, maxRange)
    if config then
        config.followAllyMinDistance = minDistance
        config.followAllyTargetRange = maxRange
    end

    local acquireRange = math.max(maxRange, minDistance + 10, 50)
    local keepRange = math.max(acquireRange * 2, 200)

    local allyPlayer
    local allyDistance
    local allyRoot

    do
        local currentAnchor = AnimalSim.Modules.Combat._followAllyAnchor
        if currentAnchor and currentAnchor.Parent and currentAnchor ~= LocalPlayer and teamCheck(currentAnchor.Name) then
            local character = currentAnchor.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 then
                local distance = (root.Position - humanoidRoot.Position).Magnitude
                if distance <= keepRange then
                    allyPlayer = currentAnchor
                    allyDistance = distance
                    allyRoot = root
                end
            end
        end
    end

    if not allyPlayer then
        allyPlayer, allyDistance, allyRoot = getClosestAllyWithin(acquireRange)
        AnimalSim.Modules.Combat._followAllyAnchor = allyPlayer
    end

    if not allyPlayer then
        local selected = AnimalSim.State.selectedPlayer
        if selected and selected.Parent and selected ~= LocalPlayer then
            local character = selected.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 then
                local distance = (root.Position - humanoidRoot.Position).Magnitude
                if distance <= keepRange then
                    allyPlayer = selected
                    allyDistance = distance
                    allyRoot = root
                    AnimalSim.Modules.Combat._followAllyAnchor = allyPlayer
                end
            end
        end
    end

    if not (allyPlayer and allyRoot and allyDistance) then
        return nil, nil
    end

    return allyPlayer, allyRoot
end

local function computeFollowAllyAimPoint(anchorRoot, radius)
    if not (anchorRoot and humanoidRoot) then
        return nil
    end

    radius = math.max(0.25, tonumber(radius) or 0)

    local center = anchorRoot.Position
    local delta = humanoidRoot.Position - center
    delta = Vector3.new(delta.X, 0, delta.Z)

    local baseDir
    if delta.Magnitude > 0.35 then
        baseDir = delta.Unit
    else
        local look = anchorRoot.CFrame.LookVector
        look = Vector3.new(look.X, 0, look.Z)
        baseDir = (look.Magnitude > 1e-3) and (-look.Unit) or Vector3.new(1, 0, 0)
    end

    local tangent = Vector3.new(-baseDir.Z, 0, baseDir.X)
    local now = os.clock()
    local wiggle = math.sin(now * 4.2) * math.min(math.max(1, radius * 0.6), 7)
    local pushPull = math.sin(now * 2.1) * math.min(radius * 0.25, 3.5)

    return center + baseDir * radius + tangent * wiggle + baseDir * pushPull
end

local function isTargetAllowedByFollowAlly(targetPlayer)
    if not (autoZoneEnabled and AnimalSim.State.followAlly) then
        return true
    end

    if AnimalSim.Modules.Combat._autoZoneLockedTarget == targetPlayer then
        return true
    end

    local allyPlayer = AnimalSim.Modules.Combat._followAllyAnchor
    if not allyPlayer or not allyPlayer.Parent then
        return false
    end
    local allyRoot = allyPlayer.Character and allyPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not (allyRoot and targetRoot) then
        return false
    end
    local config = AnimalSim.Modules.Combat.AutoZoneConfig
    local maxRange = (config and config.followAllyTargetRange) or 20
    return (targetRoot.Position - allyRoot.Position).Magnitude <= maxRange
end

AnimalSim.Modules.Combat.computeAutoZoneIndicatorBounds = function(targetPlayer, predictedPosition)
    if not predictedPosition then
        return nil, nil
    end

    local character = targetPlayer and targetPlayer.Character
    if not character then
        return CFrame.new(predictedPosition), Vector3.new(3, 3, 3)
    end

    local ok, cf, size = pcall(function()
        return character:GetBoundingBox()
    end)
    if not ok or not cf or not size then
        return CFrame.new(predictedPosition), Vector3.new(3, 3, 3)
    end

    local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    local shift = Vector3.zero
    if root then
        shift = predictedPosition - root.Position
    end

    local rotationOnly = cf - cf.Position
    local config = AnimalSim.Modules.Combat.AutoZoneConfig
    return rotationOnly + (cf.Position + shift), size + config.indicatorPadding
end

ensureAutoZoneIndicator = function()
    if autoZoneIndicatorPart then
        autoZoneIndicatorPart.Parent = workspace
        return autoZoneIndicatorPart
    end
    local part = Instance.new("Part")
    part.Name = "AutoZonePredicted"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = true
    part.CanTouch = true
    part.Size = Vector3.new(3, 3, 3)
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 80, 80)
    part.Transparency = AnimalSim.Modules.Combat.AutoZoneConfig.indicatorTransparency
    part.Parent = workspace
    autoZoneIndicatorPart = part
    return part
end

local function ensureAutoZoneDebugBox(existing, name, color)
    if existing then
        existing.Parent = workspace
        return existing
    end
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Size = Vector3.new(3, 3, 3)
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.88
    part.Parent = workspace
    return part
end

local function hideAutoZoneDebugBoxes()
    if autoZoneDebugMyBox then
        autoZoneDebugMyBox.Parent = nil
    end
    if autoZoneDebugTargetBox then
        autoZoneDebugTargetBox.Parent = nil
    end
end

hideAutoZoneIndicator = function()
    if autoZoneIndicatorPart then
        autoZoneIndicatorPart.Parent = nil
    end
    hideAutoZoneDebugBoxes()
end

local function destroyAutoZoneIndicator()
    if autoZoneIndicatorPart then
        pcall(function()
            autoZoneIndicatorPart:Destroy()
        end)
        autoZoneIndicatorPart = nil
    end
    autoZoneLastIndicatorCF = nil
    if autoZoneDebugMyBox then
        pcall(function()
            autoZoneDebugMyBox:Destroy()
        end)
        autoZoneDebugMyBox = nil
    end
    if autoZoneDebugTargetBox then
        pcall(function()
            autoZoneDebugTargetBox:Destroy()
        end)
        autoZoneDebugTargetBox = nil
    end
end

local function findZoneProjectileTool()
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer.Backpack

    local function matches(tool)
        if not (tool and tool:IsA("Tool")) then
            return false
        end
        local name = string.lower(tool.Name)
        return name == "fireball" or name == "lightningball" or string.find(name, "fireball", 1, true) ~= nil or string.find(name, "lightningball", 1, true) ~= nil
    end

    local function scan(container)
        if not container then
            return nil
        end
        for _, child in ipairs(container:GetChildren()) do
            if matches(child) then
                return child
            end
        end
        return nil
    end

    return scan(character) or scan(backpack)
end

local function isCharacterOverlappingBox(characterModel, boxCF, boxSize, boxPart)
    if not characterModel then
        return false
    end
    if not (boxCF and boxSize) then
        if not boxPart then
            return false
        end
        boxCF = boxPart.CFrame
        boxSize = boxPart.Size
    end
    if not (boxCF and boxSize) then
        return false
    end

    do
        local touching = false
        pcall(function()
            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { characterModel }
            params.RespectCanCollide = false

            if workspace.GetPartBoundsInBox then
                touching = #workspace:GetPartBoundsInBox(boxCF, boxSize, params) > 0
                return
            end

            if boxPart and workspace.GetPartsInPart then
                touching = #workspace:GetPartsInPart(boxPart, params) > 0
                return
            end

            if boxPart and boxPart.GetTouchingParts then
                for _, hit in ipairs(boxPart:GetTouchingParts()) do
                    if hit and hit:IsDescendantOf(characterModel) then
                        touching = true
                        return
                    end
                end
            end
        end)
        if touching then
            return true
        end
    end

    local half = (boxSize * 0.5) + Vector3.new(0.05, 0.05, 0.05)

    for _, descendant in ipairs(characterModel:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local partCF = descendant.CFrame
            local partHalf = descendant.Size * 0.5

            local minX, minY, minZ = math.huge, math.huge, math.huge
            local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

            local signs = { -1, 1 }
            for _, sx in ipairs(signs) do
                for _, sy in ipairs(signs) do
                    for _, sz in ipairs(signs) do
                        local cornerWorld = partCF:PointToWorldSpace(Vector3.new(sx * partHalf.X, sy * partHalf.Y, sz * partHalf.Z))
                        local cornerLocal = boxCF:PointToObjectSpace(cornerWorld)
                        minX = math.min(minX, cornerLocal.X)
                        minY = math.min(minY, cornerLocal.Y)
                        minZ = math.min(minZ, cornerLocal.Z)
                        maxX = math.max(maxX, cornerLocal.X)
                        maxY = math.max(maxY, cornerLocal.Y)
                        maxZ = math.max(maxZ, cornerLocal.Z)
                    end
                end
            end

            if (minX <= half.X and maxX >= -half.X) and (minY <= half.Y and maxY >= -half.Y) and (minZ <= half.Z and maxZ >= -half.Z) then
                return true
            end

            local boxCenterInPart = partCF:PointToObjectSpace(boxCF.Position)
            if math.abs(boxCenterInPart.X) <= partHalf.X and math.abs(boxCenterInPart.Y) <= partHalf.Y and math.abs(boxCenterInPart.Z) <= partHalf.Z then
                return true
            end
        end
    end

    return false
end

aimAndFireAtPlayer = function(targetPlayer, indicatorPart, allowProjectile)
    allowProjectile = (allowProjectile ~= false)
    local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return false
    end
    if not isTargetAllowedByFollowAlly(targetPlayer) then
        return false
    end

    AnimalSim.Modules.Combat._debugEngageTarget = targetPlayer
    AnimalSim.Modules.Combat._debugEngageAt = os.clock()
    if isInsideSafeZone(targetRoot.Position) then
        return false
    end

    local predicted = PredictPlayerPosition(targetPlayer, AUTO_ZONE_PREDICTION_TIME) or targetRoot.Position
    if not predicted or isInsideSafeZone(predicted) then
        return false
    end

    autoZoneDesiredAimPoint = predicted
    if indicatorPart then
        indicatorPart.Parent = workspace
    end

    do
        local walkState = AnimalSim.Modules.Combat._autoZoneWalk
        if walkState then
            walkState.targetPlayer = targetPlayer
        end
    end

    local character = LocalPlayer.Character
    local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")

	    if allowProjectile then
	        local now = os.clock()
	        local aimState = AnimalSim.Modules.Combat._autoAimState or {}
	        local lastAt = aimState.projectileLastAt or 0
	        if (now - lastAt) >= AnimalSim.Modules.Combat.AutoZoneConfig.projectileCooldown then
	            local tool = findZoneProjectileTool()
	            if humanoidInstance and tool then
	                pcall(flashFireballMouseLock, AnimalSim.Modules.Combat.AutoZoneConfig.fireballMouseLockDuration)
	                if tool.Parent ~= character then
	                    pcall(function()
	                        humanoidInstance:EquipTool(tool)
	                    end)
	                    task.wait(0.05)
	                end
                pcall(function()
                    tool:Activate()
                end)
                aimState.projectileLastAt = now
                AnimalSim.Modules.Combat._autoAimState = aimState
            end
        end
    end

    if indicatorPart then
        local now = os.clock()
        local aimState = AnimalSim.Modules.Combat._autoAimState or {}
        local lastAt = aimState.shovelLastAt or 0
        local myRoot = character and character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            if isInsideSafeZone(myRoot.Position) then
                return true
            end
            local touchingHitbox = isCharacterOverlappingBox(character, nil, nil, indicatorPart)
            pcall(function()
                indicatorPart.Color = touchingHitbox and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
            end)
            if not touchingHitbox then
                return true
            end
            if (now - lastAt) < (1 / 1.7) then
                return true
            end
            local targetHumanoid = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            if targetHumanoid and targetHumanoid.Health > 0 then
                AnimalSim.Modules.Combat._autoAimState = aimState

                local shovelTool
                local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer.Backpack
                for _, container in ipairs({character, backpack}) do
                    if container then
                        for _, child in ipairs(container:GetChildren()) do
                            if child:IsA("Tool") and string.lower(child.Name) == "shovel" then
                                shovelTool = child
                                break
                            end
                        end
                    end
                    if shovelTool then
                        break
                    end
                end

                if shovelTool and humanoidInstance then
                    if shovelTool.Parent ~= character then
                        pcall(function()
                            humanoidInstance:EquipTool(shovelTool)
                        end)
                        task.wait(0.03)
                    end
                    pcall(function()
                        shovelTool:Activate()
                    end)
                end

                pcall(function()
                    hitHumanoid(targetHumanoid)
                end)
                aimState.shovelLastAt = now
                AnimalSim.Modules.Combat._autoAimState = aimState
            end
        end
    end

    return true
end

local function autoPVPLoop()
    while autoPVPEnabled do
        defineNilLocals()
        local target = getRecentAttackerPlayer()
        if target then
            local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot and isInsideSafeZone(targetRoot.Position) then
                clearRecentAttacker(target)
            else
                if canEngagePlayer(target) then
                    local ok, err = pcall(function()
                        local fired = aimAndFireAtPlayer(target, nil, true)
                        if not fired then
                            if AnimalSim.State.autoFight then
                                damageplayer(target.Name)
                                clearRecentAttacker(target)
                            else
                                engageEnemy(target)
                            end
                        end
                    end)
                    if not ok then
                        warn("[AnimalSim] auto PVP failed", err)
                    end
                else
                    clearRecentAttacker(target)
                end
            end
        end
        task.wait(AUTO_PVP_POLL_RATE)
    end
    autoPVPTask = nil
end

local function setAutoPVP(value)
    if autoPVPEnabled == value then
        return
    end
    autoPVPEnabled = value
    AnimalSim.State.autoPVP = value
    if value then
        if not autoPVPTask then
            autoPVPTask = task.spawn(autoPVPLoop)
        end
    else
        while autoPVPTask do
            task.wait()
        end
    end
end

local function autoZoneLoop(myToken)
    while autoZoneEnabled and autoZoneCancelToken == myToken do
        defineNilLocals()

        local allyRoot
        if AnimalSim.State.followAlly then
            local ok, anchorRoot = pcall(function()
                local _, root = followAllyStepForAutoZone()
                return root
            end)
            if ok then
                allyRoot = anchorRoot
            end
        else
            AnimalSim.Modules.Combat._followAllyAnchor = nil
        end

        local target
        do
            local locked = AnimalSim.Modules.Combat._autoZoneLockedTarget
            if locked and locked.Parent then
                local lockedHumanoid = getPlayerHumanoid(locked)
                local lockedRoot = locked.Character and locked.Character:FindFirstChild("HumanoidRootPart")
                if lockedHumanoid and lockedHumanoid.Health > 0 and lockedRoot and not isInsideSafeZone(lockedRoot.Position) then
                    target = locked
                else
                    AnimalSim.Modules.Combat._autoZoneLockedTarget = nil
                end
            elseif locked then
                AnimalSim.Modules.Combat._autoZoneLockedTarget = nil
            end
        end

        if AnimalSim.State.followTarget then
            local selected = AnimalSim.State.selectedPlayer
            if selected and selected.Parent and selected ~= LocalPlayer and not teamCheck(selected.Name) then
                local humanoidInstance = getPlayerHumanoid(selected)
                if humanoidInstance and humanoidInstance.Health > 0 then
                    target = target or selected
                end
            end
        else
            target = target or findZoneTarget(false)
        end

        if target and AnimalSim.State.followAlly and AnimalSim.Modules.Combat._autoZoneLockedTarget ~= target and not isTargetAllowedByFollowAlly(target) then
            target = nil
        end

        if target then
            AnimalSim.Modules.Combat._autoZoneFollowMode = false
            local indicator = ensureAutoZoneIndicator()
            local fired = aimAndFireAtPlayer(target, indicator, false)
            if fired then
                AnimalSim.Modules.Combat._autoZoneLockedTarget = target
            else
                hideAutoZoneIndicator()
                if AnimalSim.Modules.Combat._autoZoneLockedTarget == target then
                    AnimalSim.Modules.Combat._autoZoneLockedTarget = nil
                end
                if not autoFireballEnabled then
                    autoZoneDesiredAimPoint = nil
                end
            end
        else
            local followMode = AnimalSim.State.followAlly and allyRoot ~= nil
            AnimalSim.Modules.Combat._autoZoneFollowMode = followMode
            if followMode then
                local config = AnimalSim.Modules.Combat.AutoZoneConfig
                autoZoneDesiredAimPoint = computeFollowAllyAimPoint(allyRoot, config and config.followAllyMinDistance or 3)
                do
                    local walkState = AnimalSim.Modules.Combat._autoZoneWalk
                    if walkState then
                        walkState.targetPlayer = nil
                    end
                end
            else
                hideAutoZoneIndicator()
                if not autoFireballEnabled then
                    autoZoneDesiredAimPoint = nil
                end
            end
        end

        task.wait(AUTO_ZONE_POLL_RATE)
    end

    if not autoFireballEnabled then
        destroyAutoZoneIndicator()
        autoZoneDesiredAimPoint = nil
    end
    autoZoneTask = nil
end

local function setAutoZone(value)
    if value then
        if autoZoneEnabled then
            return
        end
        defineNilLocals()
        autoZoneEnabled = true
        AnimalSim.State.autoZone = true
        autoZoneCancelToken = autoZoneCancelToken + 1
        acquireAimLock()

        do
            local walkState = AnimalSim.Modules.Combat._autoZoneWalk or {}
            walkState.enabled = true
            walkState.cancelToken = (walkState.cancelToken or 0) + 1
            walkState.pathPoints = walkState.pathPoints or table.create(18)
            walkState.targetPlayer = nil
            walkState.fakeout = walkState.fakeout or {}
            AnimalSim.Modules.Combat._autoZoneWalk = walkState

            if not walkState.task then
                local function startWalkTask()
                    local myToken = walkState.cancelToken
                    walkState.task = task.spawn(function()
                        local PATH_POINTS = 18
                        local WAYPOINT_RADIUS = 2.5
                        local WAYPOINT_TIMEOUT = 1.4
                        local LOOP_DELAY = 0.03

                        while autoZoneEnabled and walkState.enabled and walkState.cancelToken == myToken do
                            local character = LocalPlayer.Character
                            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
                            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                            if not (humanoidInstance and rootPart) then
                                task.wait(0.25)
                            elseif not autoZoneDesiredAimPoint then
                                task.wait(0.06)
                            else
                                for index = 2, PATH_POINTS do
                                    if not (autoZoneEnabled and walkState.enabled and walkState.cancelToken == myToken) then
                                        break
                                    end

                                    local waypoint = walkState.pathPoints[index]
                                    if not waypoint then
                                        break
                                    end
                                    if not isInsideSafeZone(waypoint) then
                                        humanoidInstance:MoveTo(waypoint)
                                        local timeoutAt = os.clock() + WAYPOINT_TIMEOUT
                                        while autoZoneEnabled and walkState.enabled and walkState.cancelToken == myToken and os.clock() < timeoutAt do
                                            local currentRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                            if not currentRoot then
                                                break
                                            end
                                            if (currentRoot.Position - waypoint).Magnitude <= WAYPOINT_RADIUS then
                                                break
                                            end
                                            task.wait(LOOP_DELAY)
                                        end
                                    end
                                end

                                task.wait(LOOP_DELAY)
                            end
                        end

                        walkState.task = nil
                    end)
                end

                startWalkTask()
            end
        end

        if not autoZoneRenderConnection then
            autoZoneRenderConnection = RunService.RenderStepped:Connect(function(dt)
                if not autoZoneEnabled then
                    return
                end
                local walkState = AnimalSim.Modules.Combat._autoZoneWalk
                local targetPlayer = walkState and walkState.targetPlayer or nil

                local config = AnimalSim.Modules.Combat.AutoZoneConfig
                local anchorPlayer = AnimalSim.Modules.Combat._followAllyAnchor
                local anchorRoot = anchorPlayer and anchorPlayer.Character and anchorPlayer.Character:FindFirstChild("HumanoidRootPart")

                if Visualizer.enabled and AnimalSim.State.followAlly then
                    updateFollowRangeVisualization(
                        anchorRoot and anchorRoot.Position or nil,
                        config and config.followAllyMinDistance or 3,
                        config and config.followAllyTargetRange or 20
                    )
                elseif followRangeVizMin or followRangeVizMax then
                    clearFollowRangeVisualization()
                end

                local followMode = AnimalSim.State.followAlly and AnimalSim.Modules.Combat._autoZoneFollowMode
                if followMode and anchorRoot then
                    autoZoneDesiredAimPoint = computeFollowAllyAimPoint(anchorRoot, config and config.followAllyMinDistance or 3)
                end

                local aimPoint = autoZoneDesiredAimPoint
                if not aimPoint then
                    hideAutoZoneIndicator()
                    return
                end

                if not targetPlayer then
                    hideAutoZoneIndicator()
                else
                    local indicator = ensureAutoZoneIndicator()
                    indicator.Parent = workspace

                    local targetCF, targetSize = AnimalSim.Modules.Combat.computeAutoZoneIndicatorBounds(targetPlayer, aimPoint)
                    if targetSize then
                        indicator.Size = targetSize
                    end
                    if not autoZoneLastIndicatorCF then
                        autoZoneLastIndicatorCF = targetCF
                    else
                        autoZoneLastIndicatorCF = autoZoneLastIndicatorCF:Lerp(targetCF, AUTO_ZONE_RENDER_LERP)
                    end
                    indicator.CFrame = autoZoneLastIndicatorCF
                end

                do
                    local now = os.clock()
                    local engagedAt = AnimalSim.Modules.Combat._debugEngageAt
                    local engagedTarget = AnimalSim.Modules.Combat._debugEngageTarget
                    if engagedAt and (now - engagedAt) < 1.25 and engagedTarget and engagedTarget.Parent then
                        local myChar = LocalPlayer.Character
                        if myChar then
                            local ok, cf, size = pcall(function()
                                return myChar:GetBoundingBox()
                            end)
                            if ok and cf and size then
                                autoZoneDebugMyBox = ensureAutoZoneDebugBox(autoZoneDebugMyBox, "AutoZoneMyBox", Color3.fromRGB(80, 160, 255))
                                autoZoneDebugMyBox.CFrame = cf
                                autoZoneDebugMyBox.Size = size
                            end
                        end

                        local targetChar = engagedTarget.Character
                        if targetChar then
                            local ok, cf, size = pcall(function()
                                return targetChar:GetBoundingBox()
                            end)
                            if ok and cf and size then
                                autoZoneDebugTargetBox = ensureAutoZoneDebugBox(autoZoneDebugTargetBox, "AutoZoneTargetBox", Color3.fromRGB(255, 220, 80))
                                autoZoneDebugTargetBox.CFrame = cf
                                autoZoneDebugTargetBox.Size = size
                            end
                        end
                    else
                        hideAutoZoneDebugBoxes()
                    end
                end

                do
                    local walkState = AnimalSim.Modules.Combat._autoZoneWalk
                    if walkState and walkState.enabled and walkState.pathPoints then
                        local character = LocalPlayer.Character
                        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local startPos3 = rootPart.Position
                            local startY = startPos3.Y
                            local startPos = Vector3.new(startPos3.X, startY, startPos3.Z)
                            local endPos = Vector3.new(aimPoint.X, startY, aimPoint.Z)
                            local delta = endPos - startPos
                            local distance = delta.Magnitude
                            if distance > 1e-3 then
                                local forward = delta.Unit
                                local up = Vector3.new(0, 1, 0)
                                local right = forward:Cross(up)
                                if right.Magnitude < 1e-3 then
                                    right = Vector3.new(1, 0, 0)
                                else
                                    right = right.Unit
                                end
                                local amplitude = math.clamp(distance * 0.18, 4, 18)

                                local function pointAt(t, sideSign)
                                    local baseStart = startPos
                                    local baseEnd = endPos
                                    local mode = walkState.fakeout and walkState.fakeout.mode

                                    if mode == "overshoot" then
                                        local cutT = (walkState.fakeout and walkState.fakeout.cutT) or 0.83
                                        local ghost = walkState.fakeout and walkState.fakeout.ghostEnd
                                        if ghost and typeof(ghost) == "Vector3" then
                                            if t < cutT then
                                                baseEnd = ghost
                                                t = t / cutT
                                            else
                                                baseStart = ghost
                                                t = (t - cutT) / (1 - cutT)
                                            end
                                        end
                                    elseif mode == "stutter" then
                                        local slowT = (walkState.fakeout and walkState.fakeout.slowT) or 0.26
                                        if t < slowT then
                                            t = t * ((walkState.fakeout and walkState.fakeout.slowScale) or 0.42)
                                        end
                                    end

                                    local base = baseStart:Lerp(baseEnd, t)
                                    local lateral = math.sin((math.pi * 2) * t)
                                    local forwardWiggle = math.sin((math.pi * 4) * t)

                                    local signedSide = sideSign
                                    if mode == "swap" then
                                        local swapT = (walkState.fakeout and walkState.fakeout.swapT) or 0.46
                                        local width = (walkState.fakeout and walkState.fakeout.swapWidth) or 0.09
                                        local blend = math.clamp(((t - swapT) / width) * 0.5 + 0.5, 0, 1)
                                        blend = blend * blend * (3 - 2 * blend)
                                        signedSide = sideSign * (1 - 2 * blend)
                                    end

                                    local extra = Vector3.zero
                                    if mode == "juke" then
                                        local center = (walkState.fakeout and walkState.fakeout.jukeCenter) or 0.28
                                        local width = (walkState.fakeout and walkState.fakeout.jukeWidth) or 0.16
                                        local u = 1 - math.abs((t - center) / width)
                                        if u > 0 then
                                            u = u * u * (3 - 2 * u)
                                            extra = extra + right * (sideSign * ((walkState.fakeout and walkState.fakeout.jukeMag) or (amplitude * 0.75)) * u)
                                        end
                                    elseif mode == "stutter" then
                                        local center = (walkState.fakeout and walkState.fakeout.backCenter) or 0.12
                                        local width = (walkState.fakeout and walkState.fakeout.backWidth) or 0.09
                                        local u = 1 - math.abs((t - center) / width)
                                        if u > 0 then
                                            u = u * u * (3 - 2 * u)
                                            extra = extra - forward * (((walkState.fakeout and walkState.fakeout.backMag) or math.clamp(distance * 0.06, 2, 6)) * u)
                                        end
                                    end
                                    return base
                                        + right * (signedSide * amplitude * lateral)
                                        + forward * (amplitude * 0.35 * forwardWiggle)
                                        + extra
                                end

                                local sideSign = 1
                                local enemyPlayer = walkState.targetPlayer

                                do
                                    local fake = walkState.fakeout
                                    if AnimalSim.State.autoZoneFakeouts then
                                        if not fake then
                                            fake = {}
                                            walkState.fakeout = fake
                                        end
                                        if not fake.rng then
                                            fake.rng = Random.new()
                                        end

                                        local now = os.clock()
                                        local targetId = enemyPlayer and enemyPlayer.UserId or 0
                                        if fake.targetId ~= targetId then
                                            fake.targetId = targetId
                                            fake.untilAt = 0
                                            fake.mode = nil
                                        end

                                        if now >= (fake.untilAt or 0) then
                                            local roll = fake.rng:NextNumber()
                                            local mode
                                            if roll < 0.25 then
                                                mode = nil
                                            elseif roll < 0.52 then
                                                mode = "swap"
                                                fake.swapT = fake.rng:NextNumber(0.32, 0.62)
                                                fake.swapWidth = fake.rng:NextNumber(0.07, 0.11)
                                            elseif roll < 0.73 then
                                                mode = "juke"
                                                fake.jukeCenter = fake.rng:NextNumber(0.18, 0.42)
                                                fake.jukeWidth = fake.rng:NextNumber(0.12, 0.22)
                                                fake.jukeMag = amplitude * fake.rng:NextNumber(0.65, 1.05)
                                            elseif roll < 0.88 then
                                                mode = "overshoot"
                                                fake.cutT = fake.rng:NextNumber(0.78, 0.88)
                                                local overshootDist = math.clamp(distance * 0.22, 6, 22) * fake.rng:NextNumber(0.8, 1.15)
                                                local ghostEnd = endPos + forward * overshootDist
                                                if not isInsideSafeZone(ghostEnd) then
                                                    fake.ghostEnd = ghostEnd
                                                else
                                                    mode = "swap"
                                                    fake.swapT = fake.rng:NextNumber(0.32, 0.62)
                                                    fake.swapWidth = fake.rng:NextNumber(0.07, 0.11)
                                                    fake.ghostEnd = nil
                                                end
                                            else
                                                mode = "stutter"
                                                fake.slowT = fake.rng:NextNumber(0.20, 0.32)
                                                fake.slowScale = fake.rng:NextNumber(0.35, 0.55)
                                                fake.backCenter = fake.rng:NextNumber(0.09, 0.16)
                                                fake.backWidth = fake.rng:NextNumber(0.07, 0.12)
                                                fake.backMag = math.clamp(distance * 0.06, 2, 6) * fake.rng:NextNumber(0.8, 1.2)
                                            end

                                            fake.mode = mode
                                            fake.untilAt = now + fake.rng:NextNumber(0.65, 1.35)
                                        end
                                    elseif fake then
                                        fake.mode = nil
                                        fake.untilAt = 0
                                    end
                                end

                                local enemyRoot = enemyPlayer and enemyPlayer.Character and enemyPlayer.Character:FindFirstChild("HumanoidRootPart")
                                local enemyPos = enemyRoot and enemyRoot.Position or nil
                                if enemyPos then
                                    local enemyMove = endPos - enemyPos
                                    enemyMove = Vector3.new(enemyMove.X, 0, enemyMove.Z)
                                    if enemyMove.Magnitude > 1 then
                                        local enemyRight = enemyMove.Unit:Cross(up)
                                        enemyRight = Vector3.new(enemyRight.X, 0, enemyRight.Z)
                                        if enemyRight.Magnitude > 1e-3 then
                                            enemyRight = enemyRight.Unit
                                            local side = (startPos - enemyPos):Dot(enemyRight)
                                            sideSign = (side >= 0) and 1 or -1
                                        end
                                    end
                                else
                                    local lv = rootPart.AssemblyLinearVelocity or rootPart.Velocity or Vector3.zero
                                    lv = Vector3.new(lv.X, 0, lv.Z)
                                    if lv.Magnitude > 2 then
                                        local lvUnit = lv.Unit
                                        local tProbe = 0.18
                                        local dirPlus = (pointAt(tProbe, 1) - startPos)
                                        local dirMinus = (pointAt(tProbe, -1) - startPos)
                                        local plusScore = (dirPlus.Magnitude > 1e-3) and lvUnit:Dot(dirPlus.Unit) or -1
                                        local minusScore = (dirMinus.Magnitude > 1e-3) and lvUnit:Dot(dirMinus.Unit) or -1
                                        sideSign = (minusScore > plusScore) and -1 or 1
                                    end
                                end

                                for index = 1, 18 do
                                    local t = (index - 1) / 17
                                    walkState.pathPoints[index] = pointAt(t, sideSign)
                                end
                            end
                            if distance <= 1e-3 then
                                for index = 1, 18 do
                                    walkState.pathPoints[index] = startPos
                                end
                            end
                        end
                    end
                end

                local camera = workspace.CurrentCamera
                if camera then
                    local character = LocalPlayer.Character
                    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        local rootPos = rootPart.Position
                        local delta = aimPoint - rootPos
                        local dir = delta.Magnitude > 1e-3 and delta.Unit or rootPart.CFrame.LookVector
                        local config = AnimalSim.Modules.Combat.AutoZoneConfig
                        local desiredPos = rootPos - dir * config.cameraDistance + Vector3.new(0, config.cameraHeight, 0)
                        local desired = CFrame.lookAt(desiredPos, aimPoint)
                        camera.CFrame = camera.CFrame:Lerp(desired, config.cameraPosLerp)
                    end
                end
            end)
        end

        local myToken = autoZoneCancelToken
        autoZoneTask = task.spawn(function()
            autoZoneLoop(myToken)
        end)
    else
        if not autoZoneEnabled then
            return
        end
        autoZoneEnabled = false
        AnimalSim.State.autoZone = false
        autoZoneCancelToken = autoZoneCancelToken + 1
        while autoZoneTask do
            task.wait()
        end
        if autoZoneRenderConnection and not autoFireballEnabled then
            autoZoneRenderConnection:Disconnect()
            autoZoneRenderConnection = nil
        end
        do
            local walkState = AnimalSim.Modules.Combat._autoZoneWalk
            if walkState then
                walkState.enabled = false
                walkState.cancelToken = (walkState.cancelToken or 0) + 1
                walkState.targetPlayer = nil
            end
        end
        AnimalSim.Modules.Combat._autoZoneLockedTarget = nil
        AnimalSim.Modules.Combat._autoZoneFollowMode = false
        AnimalSim.Modules.Combat._followAllyAnchor = nil
        if followRangeVizMin or followRangeVizMax then
            clearFollowRangeVisualization()
        end
        releaseAimLock()
    end
end

local function startAutoFlightChase()
    if autoFlightChaseEnabled then
        return
    end
    autoFlightChaseEnabled = true
    AnimalSim.State.autoFlightChase = true
    autoFlightChaseTask = task.spawn(function()
        while autoFlightChaseEnabled do
            local character = LocalPlayer.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            local camera = workspace.CurrentCamera
            if character and humanoidInstance and rootPart and camera then
                local targetPlayer = findClosestEnemy()
                local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetRoot.Position)
                    rootPart.CFrame = CFrame.lookAt(rootPart.Position, targetRoot.Position)
                    humanoidInstance:Move(Vector3.new(0, 0, -1), true)
                else
                    humanoidInstance:Move(Vector3.new(), true)
                end
            end
            task.wait(0.1)
        end
        autoFlightChaseTask = nil
    end)
end

local function stopAutoFlightChase()
    if not autoFlightChaseEnabled then
        return
    end
    autoFlightChaseEnabled = false
    AnimalSim.State.autoFlightChase = false
    while autoFlightChaseTask do
        task.wait()
    end
end

AnimalSim.Modules.Utilities.teamCheck = teamCheck
AnimalSim.Modules.Utilities.myTeam = myTeam
AnimalSim.Modules.Utilities.findClosestPlayer = findClosestPlayer
AnimalSim.Modules.Utilities.findClosestEnemy = findClosestEnemy
AnimalSim.Modules.Utilities.PredictPlayerPosition = PredictPlayerPosition
AnimalSim.Modules.Utilities.teleportInFrontOfPlayer = teleportInFrontOfPlayer
AnimalSim.Modules.Utilities.increaseByPercentage = increaseByPercentage
AnimalSim.Modules.Utilities.comparCash = comparCash
AnimalSim.Modules.Utilities.conv = conv
AnimalSim.Modules.Utilities.defineLocals = defineLocals
AnimalSim.Modules.Utilities.defineNilLocals = defineNilLocals
AnimalSim.Modules.Utilities.waitForChar = waitForChar
AnimalSim.Modules.Utilities.waitDoneMove = waitDoneMove
AnimalSim.Modules.Utilities.getClosest = getClosest
AnimalSim.Modules.Utilities.getPos = getPos
AnimalSim.Modules.Utilities.stayNearPlayer = stayNearPlayer
AnimalSim.Modules.Utilities.setFollowTarget = setFollowTargetEnabled
AnimalSim.Modules.Utilities.isInsideSafeZone = isInsideSafeZone
AnimalSim.Modules.Utilities.registerTeleporter = registerTeleporter
AnimalSim.Modules.Utilities.useTeleporter = useTeleporter
AnimalSim.Modules.Utilities.clearTeleporters = clearTeleporters
AnimalSim.Modules.Utilities.getPlayerLevel = getPlayerLevel
AnimalSim.Modules.Utilities.formatCombatNumber = formatCombatNumber
AnimalSim.Modules.Utilities.setVisualizerEnabled = setVisualizerEnabled
AnimalSim.Modules.Utilities.drawPath = drawPath
AnimalSim.Modules.Utilities.drawSegment = drawSegment
AnimalSim.Modules.Utilities.estimatePlayerDamage = estimatePlayerDamage
AnimalSim.Modules.Utilities.computeHitCount = computeHitCount
AnimalSim.Modules.Utilities.loadAwScript = function(...)
    return loadAwScript(...)
end

AnimalSim.Modules.Pathing.moveToTarget = moveToTarget
AnimalSim.Modules.Pathing.followDynamicTarget = followDynamicTarget
AnimalSim.Modules.Pathing.tryTeleportRoute = tryTeleportRoute

AnimalSim.Modules.Combat.toggleFarm = setFarmActive
AnimalSim.Modules.Combat.toggleAura = setAuraActive
AnimalSim.Modules.Combat.farm = startFarmLoop
AnimalSim.Modules.Combat.farmPassive = farmPassive
AnimalSim.Modules.Combat.stopFarm = stopFarmLoop
AnimalSim.Modules.Combat.damageplayer = damageplayer
AnimalSim.Modules.Combat.engageEnemy = engageEnemy
AnimalSim.Modules.Combat.startAutoEat = startAutoEat
AnimalSim.Modules.Combat.stopAutoEat = stopAutoEat
AnimalSim.Modules.Combat.startAutoFireball = startAutoFireball
AnimalSim.Modules.Combat.stopAutoFireball = stopAutoFireball
AnimalSim.Modules.Combat.startAutoFlightChase = startAutoFlightChase
AnimalSim.Modules.Combat.stopAutoFlightChase = stopAutoFlightChase
AnimalSim.Modules.Combat.setLegitMode = setLegitMode
AnimalSim.Modules.Combat.setAutoJump = setAutoJump
AnimalSim.Modules.Combat.setAutoFight = setAutoFight
AnimalSim.Modules.Combat.setAutoPVP = setAutoPVP
AnimalSim.Modules.Combat.setAutoZone = setAutoZone

---------------------------------------------------------------------
-- Logging helpers
---------------------------------------------------------------------

local selectedPlayers = {
    "notime4crazy", "282475249a7auto", "9", "Allaboutsuki", "DefNotRealMe",
    "Doornextguythat", "Little_Puppywolf", "ProGammerMove_1", "RektBySuki",
    "RektBySukisAlt", "Rockyrode112", "Rose_altl5", "Sakura_Mirai",
    "SimpleDisasters", "TheBestAccount_mom", "TheFreeAccount_Free1",
    "TheOneMyth", "Unicornzzz6109", "baby46793", "batman_kite",
    "foalsarecut", "iwillendUmadaf4", "Miner_havennoob", "naypolm",
    "naypolm005", "naypolm05", "naypolm12", "naypolm1789", "qwertyPCLOL",
    "ll_BANX", "xXxnothingxXx274", "dexvilxtails", "ninja1098583",
    "J_esusTheCreator", "L_ilBoomStick", "TheReal_SigmaG",
    "SpongeBobStartFish", "HeyNo_ThatsBa", "PeanutNox2180", "Tsubakidoki",
}

AnimalSim.Modules.Logging.selectedPlayers = selectedPlayers
AnimalSim.Modules.Logging.initialHealth = AnimalSim.Modules.Logging.initialHealth or {}

AnimalSim.Modules.Logging.LogDamage = function(player, damageAmount)
    if damageAmount < 0 then
        damageAmount = -damageAmount
    end
    print(player.Name .. " took " .. damageAmount .. " damage")
    local humanoidInstance = getClosestEnemyHumanoid()
    if humanoidInstance then
        hitHumanoid(humanoidInstance)
    end
end

AnimalSim.Modules.Logging.LogEvent = function(player, event)
    print(player.Name .. " " .. event)
end

AnimalSim.Modules.Logging.ConnectHealthChanged = function(player)
    local function bind()
        repeat task.wait() until player.Character and player.Character:FindFirstChild("Humanoid")
        local humanoidInstance = player.Character:FindFirstChild("Humanoid")
        if not humanoidInstance then
            return
        end
        local log = AnimalSim.Modules.Logging
        log.initialHealth[player] = humanoidInstance.Health
        humanoidInstance:GetPropertyChangedSignal("Health"):Connect(function()
            local current = humanoidInstance.Health
            local previous = log.initialHealth[player] or current
            log.LogDamage(player, previous - current)
            log.LogEvent(player, "health changed by " .. (previous - current))
            log.initialHealth[player] = current
        end)
    end
    task.spawn(bind)
end

AnimalSim.Modules.Utilities.runRemoteScript = function(url, label)
    local loader = rawget(getfenv(), "loadstring") or loadstring
    if type(loader) ~= "function" then
        warn(("[AnimalSim] %s requires an executor with loadstring support."):format(label))
        return false
    end

    local ok, source = pcall(game.HttpGet, game, url)
    if not ok then
        warn(("[AnimalSim] Failed to fetch %s: %s"):format(label, tostring(source)))
        return false
    end
    if type(source) ~= "string" or source == "" then
        warn(("[AnimalSim] Empty response while loading %s."):format(label))
        return false
    end

    local chunk, compileErr = loader(source)
    if not chunk then
        warn(("[AnimalSim] Failed to compile %s: %s"):format(label, tostring(compileErr)))
        return false
    end

    local ran, runtimeErr = pcall(chunk)
    if not ran then
        warn(("[AnimalSim] %s runtime error: %s"):format(label, tostring(runtimeErr)))
        return false
    end
    return true
end

loadAwScript = function()
    AnimalSim.Modules.Utilities.runRemoteScript("https://raw.githubusercontent.com/AWdadwdwad2/net/refs/heads/main/h", "AW script")
end

---------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------

AnimalSim.UI.buildUI = function()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/libRebound/Venyx.lua"))()
    local versionString = AnimalSim.State.version and string.format("%.2f", AnimalSim.State.version) or "1.00"
    local ui = venyx.new({title = ("Revamp - Animal Simulator v%s"):format(versionString)})

    local gameplayPage = ui:addPage({title = "Animal Sim"})
    local gameplaySection = gameplayPage:addSection({title = "Gameplay"})

    local function collectPlayerNames()
        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                table.insert(names, player.Name)
            end
        end
        table.sort(names)
        return names
    end

    local targetDropdown
    targetDropdown = gameplaySection:addDropdown({
        title = "Set Target Player",
        list = collectPlayerNames(),
        callback = function(playerName)
            AnimalSim.State.selectedPlayer = Players:FindFirstChild(playerName)
        end,
    })

    local function refreshTargetDropdown()
        if not (targetDropdown and targetDropdown.Options and targetDropdown.Options.Update) then
            return
        end
        targetDropdown.Options:Update({
            list = collectPlayerNames(),
        })
    end

    Players.PlayerAdded:Connect(function()
        refreshTargetDropdown()
    end)

    Players.PlayerRemoving:Connect(function(player)
        refreshTargetDropdown()
        if AnimalSim.State.selectedPlayer == player then
            AnimalSim.State.selectedPlayer = nil
        end
    end)

    AnimalSim.UI.instances.targetDropdown = targetDropdown

    gameplaySection:addToggle({
        title = "Auto EXP Farm",
        toggled = farmActive,
        callback = setFarmActive,
    })

    gameplaySection:addToggle({
        title = "Legit Mode",
        toggled = AnimalSim.State.legitMode,
        callback = setLegitMode,
    })

    gameplaySection:addToggle({
        title = "Kill aura",
        toggled = AnimalSim.State.killAura,
        callback = setAuraActive,
    })

    gameplaySection:addToggle({
        title = "Auto PVP",
        toggled = AnimalSim.State.autoPVP,
        callback = setAutoPVP,
    })

    gameplaySection:addToggle({
        title = "Auto Jump",
        toggled = AnimalSim.State.autoJump,
        callback = setAutoJump,
    })

    gameplaySection:addToggle({
        title = "Auto Eat",
        toggled = autoEatEnabled,
        callback = function(value)
            if value then
                startAutoEat()
            else
                stopAutoEat()
            end
        end,
    })

    gameplaySection:addToggle({
        title = "Auto Fight",
        toggled = AnimalSim.State.autoFight,
        callback = setAutoFight,
    })

    gameplaySection:addToggle({
        title = "Auto Fire",
        toggled = autoFireballEnabled,
        callback = function(value)
            if value then
                startAutoFireball()
            else
                stopAutoFireball()
            end
        end,
    })

    gameplaySection:addToggle({
        title = "Auto Zone",
        toggled = AnimalSim.State.autoZone,
        callback = setAutoZone,
    })

    gameplaySection:addToggle({
        title = "Follow Ally (AutoZone)",
        toggled = AnimalSim.State.followAlly,
        callback = function(value)
            AnimalSim.State.followAlly = value
        end,
    })

    local allyTargetRangeSlider

    gameplaySection:addSlider({
        title = "Ally Follow Min Dist",
        min = 0,
        max = 500,
        default = AnimalSim.Modules.Combat.AutoZoneConfig.followAllyMinDistance or 3,
        precision = 0,
        callback = function(value)
            local config = AnimalSim.Modules.Combat.AutoZoneConfig
            config.followAllyMinDistance = math.max(0, tonumber(value) or 0)
            if config.followAllyTargetRange and config.followAllyTargetRange < config.followAllyMinDistance then
                config.followAllyTargetRange = config.followAllyMinDistance
                if allyTargetRangeSlider then
                    allyTargetRangeSlider.Options.value = config.followAllyTargetRange
                    gameplaySection:updateSlider(allyTargetRangeSlider)
                end
            end
        end,
    })

    allyTargetRangeSlider = gameplaySection:addSlider({
        title = "Ally Target Range",
        min = 0,
        max = 500,
        default = AnimalSim.Modules.Combat.AutoZoneConfig.followAllyTargetRange or 20,
        precision = 0,
        callback = function(value)
            local config = AnimalSim.Modules.Combat.AutoZoneConfig
            local newValue = math.max(0, tonumber(value) or 0)
            if config.followAllyMinDistance and newValue < config.followAllyMinDistance then
                newValue = config.followAllyMinDistance
                if allyTargetRangeSlider then
                    allyTargetRangeSlider.Options.value = newValue
                    gameplaySection:updateSlider(allyTargetRangeSlider)
                end
            end
            config.followAllyTargetRange = newValue
        end,
    })

    gameplaySection:addToggle({
        title = "Auto Zone Fakeouts",
        toggled = AnimalSim.State.autoZoneFakeouts,
        callback = function(value)
            AnimalSim.State.autoZoneFakeouts = value
        end,
    })

    gameplaySection:addToggle({
        title = "Flight Chase",
        toggled = autoFlightChaseEnabled,
        callback = function(value)
            if value then
                startAutoFlightChase()
            else
                stopAutoFlightChase()
            end
        end,
    })

    gameplaySection:addToggle({
        title = "Movement Visualizer",
        toggled = AnimalSim.State.visualizerEnabled,
        callback = setVisualizerEnabled,
    })

    gameplaySection:addToggle({
        title = "Use target",
        toggled = AnimalSim.State.followTarget,
        callback = setFollowTargetEnabled,
    })

    gameplaySection:addButton({
        title = "Damage Player",
        callback = function()
            if AnimalSim.State.selectedPlayer then
                damageplayer(AnimalSim.State.selectedPlayer.Name)
            else
                damageplayer()
            end
        end,
    })

    gameplaySection:addTextbox({
        title = "Force Join Pack",
        default = "Case Sensitive",
        callback = function(value, focusLost)
            if not focusLost or not value or value == "" then
                return
            end
            local acceptEvent = ReplicatedStorage:FindFirstChild("acceptedEvent")
            if not acceptEvent then
                warn("[AnimalSim] acceptedEvent not found in ReplicatedStorage")
                return
            end
            for _, team in ipairs(workspace.Teams:GetChildren()) do
                if string.find(value, team.Name, 1, true) then
                    acceptEvent:FireServer(team.Name)
                end
            end
        end,
    })

    gameplaySection:addButton({
        title = "Print All Teams (F9)",
        callback = function()
            for _, team in ipairs(workspace.Teams:GetChildren()) do
                print(team.Name)
            end
        end,
    })

    gameplaySection:addTextbox({
        title = "Force Player Ride",
        default = "Case Sensitive",
        callback = function(value, focusLost)
            if not focusLost or not value or value == "" then
                return
            end
            local rideEvents = ReplicatedStorage:FindFirstChild("RideEvents")
            local acceptEvent = rideEvents and rideEvents:FindFirstChild("acceptEvent")
            if not acceptEvent then
                warn("[AnimalSim] RideEvents.acceptEvent not found in ReplicatedStorage")
                return
            end
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and string.find(player.Name, value, 1, true) then
                    acceptEvent:FireServer(player.Name)
                end
            end
        end,
    })

    local scriptsSection = gameplayPage:addSection({title = "Scripts/Hubs"})

    scriptsSection:addButton({
        title = "Load AW Script",
        callback = loadAwScript,
    })

    AnimalSim.UI.instances.library = venyx
    AnimalSim.UI.instances.ui = ui

    return venyx, ui
end

---------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------

function AnimalSim.init()
    if game.PlaceId ~= AnimalSim.PlaceId then
        return
    end
    defineLocals()
    hptp()
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
    end
    characterAddedConnection = LocalPlayer.CharacterAdded:Connect(onLocalCharacterAdded)
    if characterRemovingConnection then
        characterRemovingConnection:Disconnect()
    end
    characterRemovingConnection = LocalPlayer.CharacterRemoving:Connect(onLocalCharacterRemoving)
    clearTeleporters()
    for name, config in pairs(AnimalSim.Data.Teleporters) do
        registerTeleporter(name, config)
    end
    setVisualizerEnabled(AnimalSim.State.visualizerEnabled)
    local venyx, ui = AnimalSim.UI.buildUI()
    if venyx and ui then
        return {
            library = venyx,
            ui = ui,
            defaultTheme = DEFAULT_THEME,
            defaultPageIndex = 1,
            module = AnimalSim,
        }
    end
end

return AnimalSim
