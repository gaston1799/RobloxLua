--[[
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Forbidden Modules & Architecture == --
local root          = script.Parent.Parent
local ConfigHandler = remoteRequire("libs/forbidden/AI/ConfigHandler")


-- == Setup == --
local API = {}


-- == API Functions == --
--[=[
    Returns the closest position on the ground beneath a position, cannot exceed a height limit.
    
    @param Position <strong>Vector3</strong> Origin position of the raycast.
    @param HeightLimit <strong>number?</strong> The limit of the distance the raycast can be grounded by. (default: 3 studs)
    
    @return <strong>Vector3?</strong> Returns the grounded position or <strong>nil</strong> if not possible.
]=]

API.GetDynamicRetrackTimer = function(NPC: Instance, Target: Instance, MovementType: "Pathfind" | "DirectMoveTo"): number
    local config = ConfigHandler.GetActiveConfig(NPC)

    if MovementType == "DirectMoveTo" then
        local timer = config.Tracking.DynamicRetrack.MoveTo.GetRetrackTimeFunction(NPC, Target)
        if timer == nil then 
            return config.Tracking.DynamicRetrack.MoveTo.MaxTimer 
        end 
        return math.clamp(
            timer, 
            config.Tracking.DynamicRetrack.MoveTo.MinTimer, 
            config.Tracking.DynamicRetrack.MoveTo.MaxTimer
        )
    end

    if MovementType == "Pathfind" then
        local timer = config.Tracking.DynamicRetrack.Pathfind.GetRetrackTimeFunction(NPC, Target)
        if timer == nil then 
            return config.Tracking.DynamicRetrack.Pathfind.MaxTimer 
        end 
        return math.clamp(
            timer, 
            config.Tracking.DynamicRetrack.Pathfind.MinTimer, 
            config.Tracking.DynamicRetrack.Pathfind.MaxTimer
        )
    end

    warn("this should not occur")
    return 1
end


-- TODO://
-- readd movement based retrack: but with more flex
    -- if pathfind op, then no
    -- if direct move to op, then yes?  
API.ShouldRetrack = function(NPC: Instance, Target: Instance, MovementType: "Pathfind" | "DirectMoveTo"): boolean
    local config = ConfigHandler.GetActiveConfig(NPC)

    -- local TargetDistanceMoved = (Target.Position - NPC.Position).Magnitude

    if MovementType == "DirectMoveTo" then
        local result = config.Tracking.DynamicRetrack.MoveTo.ShouldRetrackFunction(NPC, Target)
        if result == nil then
            return config.Tracking.DynamicRetrack.MoveTo.MaxTimer
        end
        return result
    end

    if MovementType == "Pathfind" then
        local result = config.Tracking.DynamicRetrack.Pathfind.ShouldRetrackFunction(NPC, Target)
        if result == nil then
            return config.Tracking.DynamicRetrack.Pathfind.MaxTimer
        end
        return result
    end

    warn("this should not occur")
    return false
end

return API