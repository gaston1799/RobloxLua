--[[ 6/26/25
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs


TODO: Trigger check for new op in this file?
]]--

-- == Services == --
local rs = game:GetService("ReplicatedStorage")


-- == References == --
local ForbiddenDir = script.Parent.Parent.Parent.Parent


-- == Packages == --
local RBLXStateMachineLib = remoteRequire("libs/forbidden/Packages/robloxstatemachine")


-- == Forbidden Types == --
local AIT                   = remoteRequire("libs/forbidden/AI/Types")


-- == Forbidden Modules & Architecture == --
local ForbiddenDebugging    = remoteRequire("libs/forbidden/AI/Debugging")
local MessageQueue          = remoteRequire("libs/forbidden/AI/MessageQueue")
local ConfigHandler         = remoteRequire("libs/forbidden/AI/ConfigHandler")
local WaypointLooper        = remoteRequire("libs/forbidden/AI/PathfindingProcessor/WaypointLooper")
local WaypointVisualizer    = remoteRequire("libs/forbidden/AI/Visualization/WaypointsVisualization")
local Common                = remoteRequire("libs/forbidden/Common")


-- == Setup == --
local Idle = RBLXStateMachineLib.State.new("Idle") -- The name of our state


-- == Assisting Functions == --
local function StopNPCByStopType(config: AIT.Config)
    -- Key: LastPathfind, Value: {CurrentIndex: number, Waypoints: {PathWaypoint} }
    

    -- Same Position
    if config.StopType == "CurrentPosition" then
        local ActualNPC = Common.GetBasePart(config.NPC)
        local NPCHuman = config.NPC:FindFirstChildOfClass("Humanoid")
        if ActualNPC and NPCHuman then
            NPCHuman:MoveTo(ActualNPC.CFrame.Position)
            ActualNPC.CFrame = ActualNPC.CFrame -- maybe not necessary 
        else
            ForbiddenDebugging.Log(config.NPC, "StopNPCByStopType: No ActualNPC or NPCHuman found.")
        end
    end


    -- Next Waypoint
    if config.StopType == "NoStopLogic" then
        -- ! /|\ Developer using Forbidden could code their own here ig. but its intended to be done right after the AI.Stop call. 
    end
end

local function NewRequestHandler(data)

    local config: AIT.Config = data.Config
    
    -- If the state was entered by a Stop Request (or there is an extraneous stop request / none), then acknowledge & return.
    local NextRequest = MessageQueue.GetNewRequest(config.NPC)
    if NextRequest == nil then return end
    if NextRequest.ProcessingState == "Processing" or NextRequest.ProcessingState == "Processed" then return end -- redundant

    MessageQueue.SetActiveRequest(config.NPC, NextRequest) -- sets processing state to Processing

    if NextRequest.RequestType == "Stop" then
        if data.Request == nil then return end -- No request to stop, return.
        data.Request.ProcessingState = "Processed"
        WaypointLooper.EndContinuity(config.NPC)
        task.spawn(config.Hooks.StopAcknowledged, config.NPC, NextRequest.Target)
        WaypointVisualizer.DeleteVisualization(config.NPC)
        if data.Target ~= nil then
            -- stop the NPC.
            StopNPCByStopType(config)
        end
        NextRequest.ProcessingState = "Processed" -- Set the request as processed.
        data.StateMachine:ChangeData("Target", nil)
        -- stop acknowledged hook could go here.
        return 
    end
    
    -- Update Data
    data.StateMachine:ChangeData("Request", NextRequest)
    data.StateMachine:ChangeData("Target", NextRequest.Target)
    data.Request.FinishedSignal = NextRequest.FinishedSignal -- whoops. Fixed!


    -- Change State
    if NextRequest.Target then
        -- print(ConfigHandler.GetConfig(config.NPC).Tracking.Enabled)
        -- print(ConfigHandler.GetActiveConfig(config.NPC).Tracking.Enabled)
        if config.NPC == nil then
            -- this would mean the NPC no longer exists, and would trigger error in console.
            ForbiddenDebugging.Log("NPC NO LONGER EXISTS IN CONFIG REFERENCE | POSSIBLY DESTROYED.")
            return
        end
        config:ApplyNow() -- Apply the config to the NPC.
        task.spawn(config.Hooks.StartAcknowledged, config.NPC, NextRequest.Target)
        if config.Tracking.Enabled and typeof(NextRequest.Target) == "Instance" then
            data.StateMachine:ChangeState("Tracking")
        else
            data.StateMachine:ChangeState("Pathing")
        end
    else
        ForbiddenDebugging.Log(config.NPC, "No target set for Idle state, cannot change to Pathing or Tracking.")
    end

end


-- == Methods == --
function Idle:OnInit() -- This gets called as soon as the state machine is created
    -- state machine created
end

-- important to have this as it allows an instant recast of another state. (i.e. Tracking -> Idle -> Tracking in 1 hb) (theory)
function Idle:OnEnter(data) -- Called whenever the state changes into "Blue"

    if not data.NPC then error("No NPC in data!") end

    ForbiddenDebugging.Log(data.NPC, "Idle: " .. data.NPC:GetFullName())
    -- Could also write: self.Data.part.Color

    -- Finished Signal
    -- send old signal finished

    if data.Request and data.Request.FinishedSignal then
        ForbiddenDebugging.Log("Sending end signal!")
        data.Request.FinishedSignal:Fire()
    end

    -- -- If another request, then continue.
    -- local success, err = pcall(function()
    --     NewRequestHandler(data)
    -- end)
    -- if not success then
    --     print("StateMachine error:", err)
    -- end
end

function Idle:OnHeartbeat(data) -- Called every heartbeat
    -- Get next request
    -- If stop request, acknowledge it.
    -- If a real request, it will continue

    local success, err = pcall(function()
        NewRequestHandler(data)
    end)

    if not success then
        print("StateMachine error:", err)
    end
end

function Idle:OnLeave() -- Called whenever the state is left even if target gets destroyed
    local config: AIT.Config = self.Data.Config
    ForbiddenDebugging.Log(config.NPC, "Leaving Idle State for ", config.NPC:GetFullName())
end

return Idle