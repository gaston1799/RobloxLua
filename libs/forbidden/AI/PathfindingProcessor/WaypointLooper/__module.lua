--[[ 7/20/25
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs
]]--

-- == Services == --
local run = game:GetService("RunService")


-- == References == --
local ForbiddenDir = script.Parent.Parent.Parent


-- == Forbidden Types == --
local AIT                   = remoteRequire("libs/forbidden/AI/Types")


-- == Forbidden Modules & Architecture == --
local ConfigHandler         = remoteRequire("libs/forbidden/AI/ConfigHandler")
local WaypointVisualizer    = remoteRequire("libs/forbidden/AI/Visualization/WaypointsVisualization")
local ForbiddenDebugging    = remoteRequire("libs/forbidden/AI/Debugging")


-- == Initialization == --
local API = {}
local ActiveContinuities: {[Instance]: {
    RequestId: number, 
    Target: any, 
    index: number, 
    waypoints: {PathWaypoint},
    CompletedSignal: () -> ()
}} = {}

local function isValid(NPC: Instance): boolean
    local NPCHuman = NPC:FindFirstChildOfClass("Humanoid")
    if NPCHuman == nil then return false end
    if NPCHuman.Health == 0 then return false end
    
    return true
end

local function LoopThroughWaypoints(NPC: Instance)
    
    -- Validate
    local NPCHuman = NPC:FindFirstChildOfClass("Humanoid")
    if NPCHuman == nil then error("nil human") end

    -- Get config
    local config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)

    
    -- Dereferencing from the table
    local thisCont = ActiveContinuities[NPC]
    
    local thisId                = thisCont.RequestId
    local thisTarget            = thisCont.Target
    local theseWaypoints        = thisCont.waypoints
    local thisCompletedSignal   = thisCont.CompletedSignal
    local thisWaypointCount     = #theseWaypoints
    
    local timesStuck        = 0
    
    task.spawn(config.Hooks.PathingStarted, NPC, theseWaypoints)
    -- Visualize
    if config.Visualization.Enabled then
        if config.Visualization.Path then
            WaypointVisualizer.VisualizeWaypoints(NPC, theseWaypoints)
        end
    end

    -- Loop Through Waypoints
    for i=1, thisWaypointCount, 1 do

        -- Verify this is the most recent request & it is not stopped
        if thisId ~= ActiveContinuities[NPC].RequestId then break end

        -- Verify the NPC is valid
        if not isValid(NPC) then break end

        -- Verify waypoint
        local wp = theseWaypoints[i]
        if not wp then break end

        local function formatString(number: number)
            return string.format("%.2f", number)
        end

        if config.Debugging.MovingToWaypoint then
            ForbiddenDebugging.Log(NPC, "Moving to waypoint: ", "(", formatString(wp.Position.X), ", ", formatString(wp.Position.Y), ", ", formatString(wp.Position.Z), ") ", " with action: ", wp.Action, " and label: ", wp.Label)
        end

        -- If it is a pathfinding link (code after the if statement is skipped if so)
        if wp.Action == Enum.PathWaypointAction.Custom then
            task.spawn(config.Hooks.MovingToWaypoint, NPC, wp, "PathfindingLink")
            local PathfindingLinkResult = config.Hooks.PathfindingLinkReached(NPC, wp)
            if PathfindingLinkResult then continue end
            error("The PathfindingLinkReached returned false or nil, meaning it was unsuccessful for the Label: " .. wp.Label)
        end

        -- If it is a jump waypoint
        if wp.Action == Enum.PathWaypointAction.Jump then NPCHuman.Jump = true end

        -- Move to the waypoint position
        NPCHuman:MoveTo(wp.Position)
        if wp.Label == "ForbiddenDirectMoveTo" then
            task.spawn(config.Hooks.MovingToWaypoint, NPC, wp, "DirectMoveTo")
        else
            task.spawn(config.Hooks.MovingToWaypoint, NPC, wp, "Pathing")
        end
        local success = NPCHuman.MoveToFinished:Wait()
        
        if not success and config.Unstucking.Enabled then
            ForbiddenDebugging.Log(NPC, "Failed to move to waypoint: ", "(", formatString(wp.Position.X), ", ", formatString(wp.Position.Y), ", ", formatString(wp.Position.Z), ") with action: ", wp.Action, " and label: ", wp.Label)
            timesStuck += 1

            if timesStuck >= config.Unstucking.MaxStuckCount then
                ForbiddenDebugging.Log(NPC, "Max stuck count reached, breaking out of the loop.")
                task.spawn(config.Hooks.PathingFailed, NPC, "Stuck Limit Reached")
                break
            end

            -- can have waits!
            if config.Unstucking.FireStuckHook then 
                if config.Hooks.Stuck(NPC, thisTarget) then
                    if thisId ~= ActiveContinuities[NPC].RequestId then break end
                    ForbiddenDebugging.Log(NPC, "Stuck hook was successful, continuing to next waypoint.")
                else
                    if thisId ~= ActiveContinuities[NPC].RequestId then break end
                    ForbiddenDebugging.Log(NPC, "Stuck hook was unsuccessful, breaking out of the loop.")
                    break
                end
            end
        end

        if not success and not config.Unstucking.Enabled then 
            task.spawn(config.Hooks.PathingFailed, NPC, "Stuck Limit Reached")
            break 
        end
    end

    if thisId == thisCont.RequestId then
        thisCompletedSignal() -- if same request, call the completed signal (used for transition back to Idle)
        config.Hooks.GoalReached(NPC, thisCont.Target) -- not necessary to spawn this (at end of an async func) (keep in mind)
        API.EndContinuity(NPC)
    end

end

API.StartContinuity = function(NPC: Instance, Target: any, WPs: {PathWaypoint}, CompletedSignal: () -> ())
    if not ActiveContinuities[NPC] then
        ActiveContinuities[NPC] = {RequestId = 0, Target = nil, index = 1, waypoints = {}, CompletedSignal = function() end}
    end
    
    local thisCont = ActiveContinuities[NPC]

    thisCont.RequestId = ActiveContinuities[NPC].RequestId + 1
    thisCont.Target = Target
    thisCont.index = 1 -- Start at the first waypoint
    thisCont.waypoints = WPs
    thisCont.CompletedSignal = CompletedSignal

    task.spawn(LoopThroughWaypoints, NPC)
end

API.EndContinuity = function(NPC: Instance)
    local thisCont = ActiveContinuities[NPC]
    if thisCont == nil then return end

    thisCont.RequestId = ActiveContinuities[NPC].RequestId + 1
    thisCont.Target = nil
    thisCont.index = 1 -- Start at the first waypoint
    thisCont.waypoints = {}
    thisCont.CompletedSignal = function() end
end

API.TriggerCleanup = function(NPC: Instance)
    ActiveContinuities[NPC] = nil
end

return API