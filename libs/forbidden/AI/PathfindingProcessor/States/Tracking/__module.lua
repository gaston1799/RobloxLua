--[[ 6/26/25
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs


TODO: Trigger check for new op in this file?
]]--

-- == Services == --
local rs = game:GetService("ReplicatedStorage")


-- == Packages == --
local RBLXStateMachineLib = remoteRequire("libs/forbidden/Packages/robloxstatemachine")


-- == References == --
local ForbiddenDir = script.Parent.Parent.Parent.Parent


-- == Forbidden Modules & Architecture == --
local ForbiddenDebugging     = remoteRequire("libs/forbidden/AI/Debugging")
local MessageQueue           = remoteRequire("libs/forbidden/AI/MessageQueue")
local PathfindingProcessor   = remoteRequire("libs/forbidden/AI/PathfindingProcessor")
local WaypointLooper         = remoteRequire("libs/forbidden/AI/PathfindingProcessor/WaypointLooper")
local RetrackingOptimization = remoteRequire("libs/forbidden/AI/RetrackingOptimization") 
local DirectMoveTo           = remoteRequire("libs/forbidden/AI/DirectMoveTo")
local Common                 = remoteRequire("libs/forbidden/Common")


-- == Forbidden Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")


-- == Setup == --
local Tracking = RBLXStateMachineLib.State.new("Tracking") -- The name of our state


local function NewRequestHandler(data)

    local config: AIT.Config = data.Config
    
    -- If the state was entered by a Stop Request (or there is an extraneous stop request / none), then acknowledge & return.
    local NextRequest = MessageQueue.GetNewRequest(config.NPC)
    if NextRequest == nil then return end
    
    -- Update State
    data.StateMachine:ChangeState("Idle")

end

-- == Methods == --
function Tracking:OnInit() -- This gets called as soon as the state machine is created
    -- state machine created
end

function Tracking:Pathfind(data): boolean
    -- Compute the path to the target.
    local config: AIT.Config = data.Config
    local target: Instance? = data.Target
    if not target then
        ForbiddenDebugging.Log(config.NPC, "No target set for Tracking state, cannot compute path.")
        return false
    end

    local waypoints = PathfindingProcessor.ComputePath(config.NPC, target)
    
    if not waypoints then
        ForbiddenDebugging.Log(config.NPC, "Failed to compute path for Tracking state.")
        return false
    end

    if config.WaypointSkipping.TrackingPathfindSkip > 1 then
        -- Skip to the waypoint specified by SkipToWaypoint
        local skipIndex = math.min(config.WaypointSkipping.TrackingPathfindSkip, #waypoints)
        waypoints = {table.unpack(waypoints, skipIndex)}
    end

    -- Set the waypoints in the state data.
    data.StateMachine:ChangeData("Waypoints", waypoints)
    if #waypoints > 1 then
        data.StateMachine:ChangeData("RecallType", "Pathfind")
    else
        data.StateMachine:ChangeData("RecallType", "DirectMoveTo")
    end

    -- Start the waypoint looper.
    local function completedSignal()
        -- This function is called when the waypoint looper completes.
        -- not needed for tracking.
    end

    WaypointLooper.StartContinuity(config.NPC, target, waypoints, completedSignal)
    return true
end

function Tracking:OnEnter(data) -- Called whenever the state changes into "Blue"

    if not data.NPC then error("No NPC in data!") end

    ForbiddenDebugging.Log(data.NPC, "Tracking: " .. data.NPC:GetFullName())
    -- Could also write: data.part.Color
    data.StateMachine:ChangeData("LastTrackingRecall", 0)
    data.StateMachine:ChangeData("LastTargetPosition", Vector3.new(math.huge, math.huge, math.huge))
    data.StateMachine:ChangeData("Waypoints", {})
end

function Tracking:OnHeartbeat(data) -- Called every heartbeat
    NewRequestHandler(data)

    local config: AIT.Config = data.Config
    local NPC: Instance = config.NPC

    -- Validate NPC
    local NPCHuman: Humanoid? = NPC:FindFirstChildOfClass("Humanoid")
    if NPC == nil or NPCHuman == nil or NPCHuman.Health == 0 then
        ForbiddenDebugging.Log(NPC, "NPC is nil, has no Humanoid, or is dead in Tracking state, cannot continue.")
        data.StateMachine:ChangeState("Idle")
        return
    end

    -- Validate Target
    if data.Target == nil then
        ForbiddenDebugging.Log(NPC, "Target is nil or invalid in Tracking state, cannot continue.")
        data.StateMachine:ChangeState("Idle")
        return
    end

    local TargetBasePart = Common.GetBasePart(data.Target, true, NPC)
    if TargetBasePart == nil then
        ForbiddenDebugging.Log(NPC, "Target is nil or invalid in Tracking state, cannot continue.")
        data.StateMachine:ChangeState("Idle")
        return
    end

    -- Jump Handling
    if config.DirectMoveTo.JumpHandler.Enabled and #data.Waypoints > 0 and data.Waypoints[1].Label == "ForbiddenDirectMoveTo" then
        DirectMoveTo.DoJumpTick(config.NPC, data.Target)
    end


    -- The following 3 blockers below block the current attempt to retrack if any of the following conditions are true:
        -- A timer since the last recall has not been exceeded.
        -- The target has not exceeded a distance moved requirement from when the last retrack occured.
        -- The user has supplied a custom function which determined the AI should not retrack.

    -- RECALL TIMER
    -- Is it time to recall?
    local NextRecallTime = data.LastTrackingRecall + RetrackingOptimization.GetDynamicRetrackTimer(NPC, data.Target, data.RecallType)
    -- print(string.format("%.3f seconds until next recall.", NextRecallTime - os.clock()))
    if os.clock() < NextRecallTime then return end -- not time to recall yet.
    
    -- RECALL DISTANCE BLOCKER
    local distanceMoved = (data.LastTargetPosition - TargetBasePart.CFrame.Position).Magnitude
    if distanceMoved < config.Tracking.DistanceMovedThreshold and not data.UpdateRequired then
        ForbiddenDebugging.LogWithVerbosity(NPC, 7, string.format("Distance moved requirement not exceeded. (%.3f)", distanceMoved))
        return
    end
    
    -- USER RECALL BLOCKER
    -- Is the recall request blocked?
    -- 12/31/25 @rman501, linked to Path.Blocked event
    if not RetrackingOptimization.ShouldRetrack(NPC, data.Target, data.RecallType) and not data.UpdateRequired then return end


    -- Change timer blocker data here
    -- not last known pos as if the pf fails, we still want it to try?
        -- may change / add setting. (@rman501)
    data.StateMachine:ChangeData("LastTrackingRecall", os.clock())
    
    -- Recall pathfind
    ForbiddenDebugging.Log("Recalling!")
    local success = Tracking:Pathfind(data)
    if success then data.UpdateRequired = false end
    if not success then ForbiddenDebugging.Log(NPC, "Recall failed! Target: ", data.Target) end
    
    -- Change distance blocker data here
    data.StateMachine:ChangeData("LastTargetPosition", TargetBasePart.CFrame.Position)
    
end

function Tracking:OnLeave(data) -- Called whenever the state is left even if target gets destroyed
    local config: AIT.Config = data.Config
    ForbiddenDebugging.Log(config.NPC, "Leaving Tracking State for ", config.NPC:GetFullName())
    data.UpdateRequired = false
    -- data reset elsewhere
end

return Tracking