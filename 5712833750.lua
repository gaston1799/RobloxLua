--[[
    Animal Simulator automation module extracted from RevampLua.lua.

    The goal of this split file is to retain only the functionality that is
    required when the loader detects we are inside Animal Simulator
    (PlaceId 5712833750).  All helpers that were previously exposed through
    the `Revamp` table are reorganised below under the `AnimalSim` namespace.

    The implementation is intentionally faithful to the original logic so the
    in‑game behaviour remains unchanged while still keeping the local count of
    this file well under Roblox's limit.  Shared helpers that are reused by the
    other games will be duplicated in their respective split files.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

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
        autoFlightChase = false,
        autoFireball = false,
        followTarget = false,
        followDistance = 10,
        selectedPlayer = nil,
        legitMode = true,
        autoSelectTarget = false,
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
local autoZoneBaseCF
local autoZoneCancelToken = 0
local followTaskRunning = false
local autoJumpEnabled = false
local autoJumpConnection
local autoJumpCharacterConnection
local mantisTeleportActive = false
local mantisTeleportReturnCF

local AUTO_PVP_POLL_RATE = 0.35
local AUTO_ZONE_POLL_RATE = 0.6

local function teamCheck(name)
    if not name then
        return false
    end
    local playerTeam
    for _, team in ipairs(workspace.Teams:GetChildren()) do
        if team:FindFirstChild(LocalPlayer.Name) then
            playerTeam = team
            break
        end
    end
    if not playerTeam then
        return false
    end
    return playerTeam:FindFirstChild(name) ~= nil
end

local function myTeam(name)
    name = name or LocalPlayer.Name
    local foundLeader
    local foundTeam
    for _, team in ipairs(workspace.Teams:GetChildren()) do
        local teamLeader
        local hasMember = false
        for _, member in ipairs(team:GetChildren()) do
            local ok, value = pcall(function()
                return member.Value
            end)
            if member.Name == "leader" and ok then
                teamLeader = typeof(value) == "Instance" and value.Name or value
            end
            if ok and (value == name or (typeof(value) == "Instance" and value.Name == name)) then
                hasMember = true
            end
        end
        if hasMember then
            foundLeader = teamLeader
            foundTeam = team.Name
            break
        end
    end
    return {foundLeader, foundTeam}
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

local playersService
local selfPlayer
local char
local root
local mouse
local rebirthValue
local finding = false
local pathfindingComplete = true
local doneMoving = true
local LegitPathing = AnimalSim.State.legitMode

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

local function defineNilLocals()
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
        local selected = AnimalSim.State.selectedPlayer
        local character = LocalPlayer.Character
        if not (selected and character and humanoidRoot and selected.Character) then
            continue
        end
        local targetRoot = selected.Character:FindFirstChild("HumanoidRootPart")
        if not targetRoot then
            continue
        end
        local distance = (targetRoot.Position - humanoidRoot.Position).Magnitude
        if distance > (AnimalSim.State.followDistance or 10) then
            humanoidRoot.CFrame = CFrame.new(targetRoot.Position - targetRoot.CFrame.LookVector * (AnimalSim.State.followDistance or 10))
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
end

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
        local condition = ((pi.Y > z) ~= (pj.Y > z)) and
            (x < (pj.X - pi.X) * (z - pi.Y) / math.max(pj.Y - pi.Y, 1e-9) + pi.X)
        if condition then
            inside = not inside
        end
        j = i
    end
    return inside
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

local function moveToTarget(target, humanoidInstance, options)
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
        iterations += 1
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
            continue
        end
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
    return useTeleporter(best, humanoidInstance, options)
end

local function fireFireballAtPosition(targetPosition)
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer.Backpack
    local tool = character:FindFirstChildWhichIsA("Tool") or (backpack and backpack:FindFirstChildWhichIsA("Tool"))
    if not tool then
        return false
    end
    local remote = tool:FindFirstChildOfClass("RemoteEvent")
    if not remote then
        return false
    end
    local ok, err = pcall(remote.FireServer, remote, targetPosition)
    if not ok then
        warn("Failed to fire projectile", err)
        return false
    end
    return true
end

local function getAutoFireballTargetPosition()
    local selected = AnimalSim.State.selectedPlayer
    if selected and selected.Character and selected.Character.PrimaryPart then
        return PredictPlayerPosition(selected)
    end
    local closest = findClosestPlayer()
    if closest then
        return PredictPlayerPosition(closest)
    end
    if LocalPlayer.Character and LocalPlayer.Character.PrimaryPart then
        return LocalPlayer.Character.PrimaryPart.Position + LocalPlayer.Character.PrimaryPart.CFrame.LookVector * 60
    end
    return nil
end

local function startAutoFireball()
    if autoFireballEnabled then
        return
    end
    autoFireballEnabled = true
    AnimalSim.State.autoFireball = true
    if autoFireballTask then
        return
    end
    autoFireballTask = task.spawn(function()
        while autoFireballEnabled do
            local waitTime = 0.4
            local ok, fired = pcall(function()
                local targetPosition = getAutoFireballTargetPosition()
                if not targetPosition then
                    return false
                end
                return fireFireballAtPosition(targetPosition)
            end)
            if not ok then
                warn("[AutoFireball]", fired)
                waitTime = 0.8
            elseif not fired then
                waitTime = 0.6
            end
            task.wait(waitTime)
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

local function autoEatLoop()
    local function getFoodTool()
        local character = LocalPlayer.Character
        if character then
            local equipped = character:FindFirstChild("Food")
            if equipped and equipped:IsA("Tool") then
                return equipped
            end
        end
        local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer.Backpack
        if backpack then
            local tool = backpack:FindFirstChild("Food")
            if tool and tool:IsA("Tool") then
                return tool
            end
        end
        return nil
    end

    while autoEatEnabled do
        local tool = getFoodTool()
        if not tool then
            task.wait(0.5)
            continue
        end
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
        end
        task.wait(2)
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
    localHumanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if localHumanoid.Health < 1 then
            deathPose = LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame
            justDied = true
        end
        if localHumanoid.Health < oldHealth then
            local enemy = getClosestEnemyHumanoid()
            if enemy then
                hitHumanoid(enemy)
            end
        end
        oldHealth = localHumanoid.Health
    end)
end

---------------------------------------------------------------------
-- Combat routines
---------------------------------------------------------------------

local auraTask
local auraActive = false
local farmTask
local farmActive = false
local DMGTask
local DMGActive = false

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
        local ok, targetHumanoid = pcall(getClosestEnemyHumanoid)
        if ok and targetHumanoid then
            local hitOk, err = pcall(hitHumanoid, targetHumanoid)
            if not hitOk then
                warn("[AnimalSim] auraLoop hit failed:", err)
            end
        elseif not ok then
            warn("[AnimalSim] auraLoop target lookup failed:", targetHumanoid)
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

local function damageplayer(targetName)
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

local function findZoneTarget()
    local character = LocalPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return nil
    end
    local closestPlayer
    local closestDistance = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not teamCheck(player.Name) then
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

local function autoPVPLoop()
    while autoPVPEnabled do
        defineNilLocals()
        local target = findClosestEnemy()
        if target then
            local ok, err = pcall(function()
                if AnimalSim.State.autoFight then
                    damageplayer(target.Name)
                else
                    engageEnemy(target)
                end
            end)
            if not ok then
                warn("[AnimalSim] auto PVP failed", err)
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
        local target = findZoneTarget()
        if target then
            local ok, err = pcall(function()
                if AnimalSim.State.autoFight then
                    damageplayer(target.Name)
                else
                    engageEnemy(target)
                end
            end)
            if not ok then
                warn("[AnimalSim] auto zone error", err)
            end
        elseif autoZoneBaseCF and humanoidRoot then
            moveToTarget(autoZoneBaseCF.Position, humanoid, {arrivalDistance = 8})
        end
        task.wait(AUTO_ZONE_POLL_RATE)
    end
    if autoZoneBaseCF and humanoidRoot then
        pcall(function()
            humanoidRoot.CFrame = autoZoneBaseCF
        end)
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
        autoZoneCancelToken += 1
        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            autoZoneBaseCF = rootPart.CFrame
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
        autoZoneCancelToken += 1
        while autoZoneTask do
            task.wait()
        end
        autoZoneBaseCF = nil
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
AnimalSim.Modules.Utilities.loadUraniumHub = loadUraniumHub
AnimalSim.Modules.Utilities.loadAwScript = loadAwScript

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
AnimalSim.Modules.Combat.BloxFruit = loadUraniumHub

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

local initialHealth = {}

local function LogDamage(player, damageAmount)
    if damageAmount < 0 then
        damageAmount = -damageAmount
    end
    print(player.Name .. " took " .. damageAmount .. " damage")
    local humanoidInstance = getClosestEnemyHumanoid()
    if humanoidInstance then
        hitHumanoid(humanoidInstance)
    end
end

local function LogEvent(player, event)
    print(player.Name .. " " .. event)
end

local function ConnectHealthChanged(player)
    local function bind()
        repeat task.wait() until player.Character and player.Character:FindFirstChild("Humanoid")
        local humanoidInstance = player.Character:FindFirstChild("Humanoid")
        if not humanoidInstance then
            return
        end
        initialHealth[player] = humanoidInstance.Health
        humanoidInstance:GetPropertyChangedSignal("Health"):Connect(function()
            local current = humanoidInstance.Health
            local previous = initialHealth[player] or current
            LogDamage(player, previous - current)
            LogEvent(player, "health changed by " .. (previous - current))
            initialHealth[player] = current
        end)
    end
    task.spawn(bind)
end

AnimalSim.Modules.Logging.selectedPlayers = selectedPlayers
AnimalSim.Modules.Logging.LogDamage = LogDamage
AnimalSim.Modules.Logging.LogEvent = LogEvent
AnimalSim.Modules.Logging.ConnectHealthChanged = ConnectHealthChanged
AnimalSim.Modules.Logging.initialHealth = initialHealth

local function loadUraniumHub()
    local ok, err =
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Augustzyzx/UraniumMobile/main/UraniumKak.lua"))()
        end)
    if not ok then
        warn("[AnimalSim] Failed to load Uranium Hub:", err)
    end
end

local function loadAwScript()
    local ok, err =
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/AWdadwdwad2/net/refs/heads/main/h"))()
        end)
    if not ok then
        warn("[AnimalSim] Failed to load AW script:", err)
    end
end

---------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    local ui = venyx.new({title = "Revamp - Animal Simulator"})

    local gameplayPage = ui:addPage({title = "Animal Sim"})
    local gameplaySection = gameplayPage:addSection({title = "Gameplay"})

    local playerOptions = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(playerOptions, player.Name)
        end
    end

    gameplaySection:addDropdown({
        title = "Set Target Player",
        list = playerOptions,
        callback = function(playerName)
            AnimalSim.State.selectedPlayer = Players:FindFirstChild(playerName)
        end,
    })

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
        title = "autoFireball",
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
        title = "Uranium Hub",
        callback = loadUraniumHub,
    })

    scriptsSection:addButton({
        title = "Load AW Script",
        callback = loadAwScript,
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

    AnimalSim.UI.instances.library = venyx
    AnimalSim.UI.instances.ui = ui

    return ui
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
    clearTeleporters()
    for name, config in pairs(AnimalSim.Data.Teleporters) do
        registerTeleporter(name, config)
    end
    local ui = buildUI()
    if ui then
        ui:SelectPage(1)
    end
end

return AnimalSim

