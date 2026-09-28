--[[
Handles the efficient pathfind bypassing of Forbidden. Instead of pathfinding, if decided, it will use th

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--


-- == Forbidden Modules & Architecture == --
local root = script.Parent.Parent
local ConfigHandler             = remoteRequire("libs/forbidden/AI/ConfigHandler")
local Common                    = remoteRequire("libs/forbidden/Common")
local MathModule                = remoteRequire("libs/forbidden/Math")
local CMathRequests             = remoteRequire("libs/forbidden/AI/CommonMathRequests")
local ForbiddenDebugging        = remoteRequire("libs/forbidden/AI/Debugging")
local PositionalOptimization    = remoteRequire("libs/forbidden/AI/PositionalOptimization")


-- == External Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")

-- == Setup == --
local API = {}
local TimedRequests: {[Instance]: {
    LastCheckFloorFailTime: number,
    LastCheckFloorTime: number,
    JumpStuckTime: number,
    JumpDebounceTime: number
}} = {}

-- target has to be instance at this point.
-- which means computing fake point elsewhere.
-- needs to be fore raycast.
local timed = 0
local function GetPathCheckBox(NPC: Instance, NPCActual: BasePart, TargetActual: BasePart, dist: number)
    -- Positions
    local npcPos = NPCActual.Position
    local targetPos = TargetActual.Position

    -- Direction from NPC to Target
    local direction = targetPos - npcPos
    local distance = direction.Magnitude

    if distance <= 0 then
        return nil, nil
    end

    local config = ConfigHandler.GetActiveConfig(NPC)

    -- Midpoint between NPC & Target
    local midpoint = npcPos + (direction * 0.5)

    -- Orientation facing toward the target
    local lookCFrame = CFrame.lookAt(midpoint, targetPos)

    -- Box size
    local size = Vector3.new(
        config.AgentInfo.AgentRadius * 2,                                               -- Width
        config.DirectMoveTo.CollisionInferencing.YSizeOfCollider,                       -- Height
        math.min(distance, config.DirectMoveTo.CollisionInferencing.MaxColliderRange)   -- Length along path
    )

    if config.Visualization.Enabled and config.Visualization.CollisionInferencing then
        if timed + 0.5 < os.time() then
            local part = Instance.new("Part")
            part.Size = size
            part.CFrame = lookCFrame
            part.Anchored = true
            part.CanCollide = false
            part.Transparency = 0.5
            part.Parent = workspace
            timed = os.time()
        end

    end

    return lookCFrame, size
end

API.isPathObstructedByColliders = function(NPC: Instance, Target: any): boolean

	-- Get HumanoidRootPart and its collision group
	
    local NPCActual = Common.GetBasePart(NPC)
    local TargetActual = Common.GetBasePart(Target, true, NPC)
    if TargetActual == nil then error("This should not happen!") end

    -- Positions
    local npcPos = NPCActual.Position
    local targetPos = TargetActual.Position

    -- Direction from NPC to Target
    local direction = targetPos - npcPos
    local distance = direction.Magnitude

    local config = ConfigHandler.GetActiveConfig(NPC)

    -- if it is closer than the check minimum, just skip it.
    if distance < config.DirectMoveTo.CollisionInferencing.MinColliderRange then return false end

	-- Compute model's bounding box
	local cframe, size = GetPathCheckBox(
        NPC,
        NPCActual,
        TargetActual,
        distance
    )

    if cframe and size then
        local params = OverlapParams.new()
        params.CollisionGroup = NPCActual.CollisionGroup
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {NPC, TargetActual, config.DirectMoveTo.Raycast.FilterTable}
        -- print(Target)
        -- print(typeof(Target) == "Instance")
        -- print(Target:IsA("BasePart"))
        if typeof(Target) == "Instance" then
            if Target:IsA("Player") then
                params:AddToFilter(Target.Character)
            else
                params:AddToFilter(Target)
            end
        end

        local hits = workspace:GetPartBoundsInBox(cframe, size, params)

        for _, part in ipairs(hits) do
            if part.CanCollide then
                -- print(part)
                return true
            end
        end
    end

    return false
end

API.CanUseDirectMoveTo = function(NPC: Instance, Target: Instance): boolean
    
    local Config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)
    if not Config.DirectMoveTo.Enabled then return false end 
    
    -- Check if req is blocked
    -- outside getRes bc otherwise infinite loop of time getting updated.
    if not TimedRequests[NPC] then TimedRequests[NPC] = {LastCheckFloorFailTime = 0, LastCheckFloorTime = 0, JumpStuckTime = 0, JumpDebounceTime = 0} end
    if os.clock() < TimedRequests[NPC].LastCheckFloorFailTime + Config.DirectMoveTo.CheckFloor.BlockDirectMoveToTimer then return false end

    -- If not an instance, then it is a position, which means it is non-tracking, which means we do not need this setting.
    local function getRes(): boolean
        if typeof(Target) ~= "Instance" then return false end


        if Config.DirectMoveTo.TrackingOnly and not Config.Tracking.Enabled then return false end
        -- if not Config.Tracking.Enabled then return false end     -- maybe use this if path does not compute ?
            -- either way it would not be here.


        local npc_part: BasePart? = Common.GetBasePart(Target)
        if npc_part == nil then error("NO NPC BASE") end
        
        local target_part: BasePart? = Common.GetBasePart(Target, true, NPC)
        if target_part == nil then error("NO NPC BASE") end

        local npc_pos = npc_part.CFrame.Position
        local target_pos = target_part.CFrame.Position

        local dist = (npc_pos - target_pos).Magnitude
        if Config.DirectMoveTo.ActivationDistance < dist then return false end

        local yDist = npc_pos.Y - target_pos.Y
        if Config.DirectMoveTo.HeightLimit < yDist then return false end

        if Config.DirectMoveTo.Raycast.Enabled then
            -- TODO:// update math module and settings to be config handler based ?
            -- TODO:// add check to arms & multiple raycast hitboxes.
            if not CMathRequests.CanMoveToRaycast(NPC, Target) then ForbiddenDebugging.LogWithVerbosity(NPC, 5, "[" .. NPC:GetFullName() .. "] cannot see target."); return false end
        end

        if Config.DirectMoveTo.CollisionInferencing.Enabled then
            if API.isPathObstructedByColliders(NPC, Target) then ForbiddenDebugging.Log(NPC, "Failed CollisionInferencing"); return false end
        end

        if Config.DirectMoveTo.CheckFloor.Enabled then
            local freqCheck = os.clock() > TimedRequests[NPC].LastCheckFloorTime + Config.DirectMoveTo.CheckFloor.CheckFrequencyTimer
            local distCheck = Common.GetDistanceFromNPCToTarget(NPC, Target) > Config.DirectMoveTo.CheckFloor.DisableIfDistanceIsLessThan

            if distCheck and freqCheck then
                if not CMathRequests.CanCrossFloorRaycast(NPC, Target) then 
                    ForbiddenDebugging.Log(NPC, "Failed cross floor check to target.") 
                    TimedRequests[NPC].LastCheckFloorFailTime = os.clock()
                    return false 
                end
                TimedRequests[NPC].LastCheckFloorTime = os.clock()
            end
        end

        if Config.DirectMoveTo.AvoidUseHook() then
            ForbiddenDebugging.Log(NPC, "DirectMoveTo was avoided by the user hook.")
            return false
        end

        return true
    end

    local result = getRes()
    if not result then
        TimedRequests[NPC].LastCheckFloorFailTime = os.clock()
    end
    return result
end

API.GetDirectMoveToPosition = function(NPC: Instance, Target: Instance): Vector3
    
    -- validation
    local npc_part: BasePart? = Common.GetBasePart(NPC)
    if npc_part == nil then error("NO NPC BASE") end

    local target_part: BasePart? = Common.GetBasePart(Target, true, NPC)
    if target_part == nil then error("NO TARGET BASE") end

    -- get pos
    local npc_pos = npc_part.CFrame.Position
    local target_pos = target_part.CFrame.Position

    -- get the config
    local config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)

    -- predict the movement with a magnitude as follows.
    if config.Tracking.Enabled and config.Tracking.PredictionMagnitude > 0 then
        target_pos = PositionalOptimization.PredictMovement(target_part, config.Tracking.PredictionMagnitude)
    end

    -- offset from the predicted point of the target toward the NPC
    local goToPos = PositionalOptimization.GetCollinearTargetPositionOffset(target_pos, npc_pos, config.Tracking.CollinearTargetPositionOffset)
    
    return goToPos
end

API.DoJumpTick = function(NPC: Instance, Target: any)

    local NPCHuman: Humanoid? = NPC:FindFirstChildOfClass("Humanoid")
    if NPCHuman == nil then return end -- should not happen, but just in case.

    if not TimedRequests[NPC] then TimedRequests[NPC] = {LastCheckFloorFailTime = 0, JumpStuckTime = 0, JumpDebounceTime = 0, LastCheckFloorTime = 0} end
    local config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)
    if config.DirectMoveTo.JumpHandler.CustomJumpFunction then
        if config.DirectMoveTo.JumpHandler.CustomJumpFunction(NPC, Target) then
            ForbiddenDebugging.Log(NPC, "Custom jump function returned true, jumping.")
            NPCHuman.Jump = true
            return true
        end
    end
    
    if not config.AgentInfo.AgentCanJump then return end
    if not config.DirectMoveTo.TrackingOnly and config.Tracking.Enabled then return end
    if not config.DirectMoveTo.JumpHandler.Enabled then return end


    local NPCActual = Common.GetBasePart(NPC)
    local TargetActual = Common.GetBasePart(Target, true, NPC)
    if TargetActual == nil then error("This should not happen!") end

    -- TODO:// revamp this
        -- add settings
    local dist = (TargetActual.CFrame.Position - NPCActual.CFrame.Position).Magnitude 
    
    -- idea behind it: i.e. is stuck against something, we need to jump
        -- also, the AI's velo is not ~0 which means it is trying to move.
    -- local VeloMin = true -- NPCActual.AssemblyLinearVelocity.Magnitude > NPCHuman.WalkSpeed * .1
    local VeloMax = NPCActual.AssemblyLinearVelocity.Magnitude < NPCHuman.WalkSpeed * .5
    local AdditionalVeloCheck = (Vector3.new(NPCActual.AssemblyLinearVelocity.X, 0, NPCActual.AssemblyLinearVelocity.Z).Magnitude < NPCHuman.WalkSpeed * .33)
        local MoveToCheck = (NPCHuman.WalkToPoint - NPCActual.CFrame.Position).Magnitude > config.DirectMoveTo.JumpHandler.DistanceFromMoveToPoint
    local TooCloseToTarget = (not config.Tracking.Enabled) or (dist < config.Tracking.CollinearTargetPositionOffset + config.Tracking.DistanceMovedThreshold + 0.1)
    -- local TooFarFromTarget = false -- dist > math.clamp(config.AgentInfo.AgentRadius * 5, 10, 100)
    
    -- if not VeloMin then print("min") end
    -- if not VeloMax then print("max") end
    -- if not ((not AdditionalVeloCheck) and MoveToCheck) then print("additional velo check") end
    -- if TooCloseToTarget then print("too close to target") end

    -- if not VeloMin then
        -- ForbiddenDebugging.LogWithVerbosity(NPC, 5, "Did not reach velo min for JumpHandler: ", string.format("%.3f", NPCActual.AssemblyLinearVelocity.Magnitude))
    -- end

    -- if not VeloMax then
        -- ForbiddenDebugging.LogWithVerbosity(NPC, 5, "Exceeded velo max for JumpHandler: ", string.format("%.3f", NPCActual.AssemblyLinearVelocity.Magnitude))
    -- end

    -- if VeloMin and VeloMax and TooCloseToTarget then
    --     ForbiddenDebugging.LogWithVerbosity(NPC, 5, "JumpHandler success with velo: ", string.format("%.1f", NPCActual.AssemblyLinearVelocity.Magnitude))
    --     return false
    -- end

    if 
        -- VeloMin
            -- and
        VeloMax -- using MoveTo??
            and
        AdditionalVeloCheck
            and
        MoveToCheck -- prevent jump loop
            and
        not TooCloseToTarget
            -- and
        -- not TooFarFromTarget
    then 
        -- meets criterie
        
        if TimedRequests[NPC].JumpStuckTime + config.DirectMoveTo.JumpHandler.MinConditionReachedTime < os.clock() then -- stuck for the min amount of time
            if TimedRequests[NPC].JumpDebounceTime + config.DirectMoveTo.JumpHandler.NextJumpMinTime > os.clock() then return false end -- not blocked by debounce timer
            NPCHuman.Jump = true
            TimedRequests[NPC].JumpDebounceTime = os.clock()
            ForbiddenDebugging.Log(NPC, "Jumping")
            return true
        end
    else
        TimedRequests[NPC].JumpStuckTime = os.clock()
    end

    return false
end


API.TriggerCleanup = function(NPC: Instance)
    TimedRequests[NPC] = nil
end

return API