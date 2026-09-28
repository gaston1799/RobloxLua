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
local ForbiddenDebugging    = remoteRequire("libs/forbidden/AI/Debugging")
local MessageQueue          = remoteRequire("libs/forbidden/AI/MessageQueue")
local PathfindingProcessor  = remoteRequire("libs/forbidden/AI/PathfindingProcessor")
local WaypointLooper        = remoteRequire("libs/forbidden/AI/PathfindingProcessor/WaypointLooper")
local Common                = remoteRequire("libs/forbidden/Common")
local DirectMoveTo          = remoteRequire("libs/forbidden/AI/DirectMoveTo")


-- == Forbidden Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")


-- == Setup == --
local Pathing = RBLXStateMachineLib.State.new("Pathing") -- The name of our state


local function NewRequestHandler(data)

    local config: AIT.Config = data.Config

    -- If the state was entered by a Stop Request (or there is an extraneous stop request / none), then acknowledge & return.
    local NextRequest = MessageQueue.GetNewRequest(config.NPC)
    if NextRequest == nil then return end
    if data.Request == NextRequest then return end
    
    -- Update State
    data.StateMachine:ChangeState("Idle")
    return true
end
 
-- == Methods == --
function Pathing:OnInit() -- This gets called as soon as the state machine is created
    -- state machine created
end

function Pathing:Pathfind(data): boolean
    -- Compute the path to the target.
    local config: AIT.Config = data.Config
    local target: Instance? = data.Target
    if not target then
        ForbiddenDebugging.Log(config.NPC, "No target set for Pathing state, cannot compute path.")
        return false
    end

    local waypoints = PathfindingProcessor.ComputePath(config.NPC, target)
    
    if not waypoints then
        ForbiddenDebugging.Log(config.NPC, "Failed to compute path for Pathing state.")
        return false
    end
    
    if config.WaypointSkipping.RegularPathfindSkip > 1 then
        -- Skip to the waypoint specified by SkipToWaypoint
        local skipIndex = math.min(config.WaypointSkipping.RegularPathfindSkip, #waypoints)
        waypoints = {table.unpack(waypoints, skipIndex)}
    end
    
    -- Set the waypoints in the state data.
    data.StateMachine:ChangeData("Waypoints", waypoints)
    if #waypoints > 1 then
        data.StateMachine:ChangeData("RecallType", "Pathfind")
    else
        data.StateMachine:ChangeData("RecallType", "DirectMoveTo")
    end

    local request = data.Request
    local function completedSignal()
        -- This function is called when the waypoint looper completes.
        if data.StateMachine:GetCurrentState() ~= "Pathing" then
            ForbiddenDebugging.Log(config.NPC, "Pathing state has changed, stopping waypoint looper.")
            return
        end
        
        ForbiddenDebugging.Log(config.NPC, "Pathing completed for ", config.NPC:GetFullName())
        -- Optionally, you can change the state or perform other actions here.

        if request ~= data.Request then 
            ForbiddenDebugging.Log(config.NPC, "Request has changed during pathing, stopping current pathing.")
            return
        end

        data.Request.ProcessingState = "Processed"
        data.StateMachine:ChangeState("Idle")
    end
    WaypointLooper.StartContinuity(config.NPC, target, waypoints, completedSignal)
    return true
end

function Pathing:OnEnter(data) -- Called whenever the state changes into "Blue"

    --[[
    data.StateMachine:ChangeData("Waypoints", {})

    if not data.NPC then error("No NPC in data!") end
    
    ForbiddenDebugging.Log(data.NPC, "Pathing: " .. data.NPC:GetFullName())
    -- Could also write: self.Data.part.Color

    -- Compute the path to the target.
    local config: AIT.Config = data.Config
    local target: Instance? = data.Target
    if not target then
        ForbiddenDebugging.Log(config.NPC, "No target set for Pathing state, cannot compute path.")
        return
    end

    local waypoints = PathfindingProcessor.ComputePath(config.NPC, target)
    
    
    if not waypoints then
        ForbiddenDebugging.Log(config.NPC, "Failed to compute path for Pathing state.")
        return
    end
    
    if config.WaypointSkipping.RegularPathfindSkip > 1 then
        -- Skip to the waypoint specified by SkipToWaypoint
        local skipIndex = math.min(config.WaypointSkipping.RegularPathfindSkip, #waypoints)
        waypoints = {table.unpack(waypoints, skipIndex)}
    end
    
    -- Set the waypoints in the state data.
    data.StateMachine:ChangeData("Waypoints", waypoints)

    local request = data.Request
    -- Start the waypoint looper.
    local function completedSignal()
        -- This function is called when the waypoint looper completes.
        if data.StateMachine:GetCurrentState() ~= "Pathing" then
            ForbiddenDebugging.Log(config.NPC, "Pathing state has changed, stopping waypoint looper.")
            return
        end
        
        ForbiddenDebugging.Log(config.NPC, "Pathing completed for ", config.NPC:GetFullName())
        -- Optionally, you can change the state or perform other actions here.

        if request ~= data.Request then 
            ForbiddenDebugging.Log(config.NPC, "Request has changed during pathing, stopping current pathing.")
            return
        end

        data.Request.ProcessingState = "Processed"
        data.StateMachine:ChangeState("Idle")
    end
    WaypointLooper.StartContinuity(config.NPC, target, waypoints, completedSignal)
    -- Acknowledge the request is processed.
    ]]--
    local res = Pathing:Pathfind(data)
    if not res then -- emg. exit. 
        data.StateMachine:ChangeState("Idle")
    end
end

function Pathing:OnHeartbeat(data) -- Called every heartbeat
    if NewRequestHandler(data) then return end
    local config: AIT.Config = data.Config
    local target: Instance? = data.Target
    if not target then
        ForbiddenDebugging.Log(config.NPC, "No target set for Pathing state, cannot continue pathing.")
        return
    end

    if config.DirectMoveTo.JumpHandler.Enabled and not config.DirectMoveTo.TrackingOnly then
        if #data.Waypoints > 0 and data.Waypoints[1].Label == "ForbiddenDirectMoveTo" then
            DirectMoveTo.DoJumpTick(config.NPC, target)
        end
    end

    if data.UpdateRequired then
        Pathing:Pathfind(data)
    end
end

function Pathing:OnLeave(data) -- Called whenever the state is left even if target gets destroyed
    local config: AIT.Config = self.Data.Config
    ForbiddenDebugging.Log(config.NPC, "Leaving Pathing State for ", config.NPC:GetFullName())
    data.UpdateRequired = false
end

return Pathing