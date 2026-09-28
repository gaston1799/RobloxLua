--[[
Contains the default configuration for the ConfigHandler when you request an NPC's config that isn't already initialized.

Recommended not to modify this file, instead use the ConfigHandler to create a preset before loading it.

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

local AIT = remoteRequire("libs/forbidden/AI/Types")

-- == Setup == --
local Defaults: AIT.Config = {} :: any
local function nullbind() end


-- == References == --
local root = script.Parent.Parent.Parent


-- == Libraries == --
local Common = remoteRequire("libs/forbidden/Common")


-- == Stop Configuration == --
Defaults.StopType = "CurrentPosition" -- Default stop type is CurrentPosition


-- == Unstucking Config == --
Defaults.Unstucking = {} :: any
Defaults.Unstucking.Enabled         = true
Defaults.Unstucking.FireStuckHook   = true -- The stuck hook allows for users to provide a solution if the AI gets stuck when going to a waypoint
    -- This is different then the PathingFailed hook, which fires if the MaxStuckCount was reached.
    -- Goal is to provide some recomputation solutions
Defaults.Unstucking.MaxStuckCount   = 2 -- It will get stuck once, call the Stuck hook, and then try to move again. If it gets stuck again, it will call PathingFailed hook and stop trying to loop through the waypoints.


-- == Request Prioritization == --
Defaults.RequestPrioritization = {} :: any
Defaults.RequestPrioritization.PreferTimeOverPriority = {} :: any
Defaults.RequestPrioritization.PreferTimeOverPriority.Enabled               = true -- if true, the AI will prioritize the latest request over a request with a higher priority
Defaults.RequestPrioritization.PreferTimeOverPriority.ResetOlderRequests    = true -- if true, the AI will ignore older requests when a new request is made, even after the latest request is processed


-- == Agent Info == --
-- look at link below for in-depth explanation.
-- resource link: https://create.roblox.com/docs/characters/pathfinding#create-paths:~:text=Default-,AgentRadius,-Agent%20radius%2C%20in
Defaults.AgentInfo = {} :: any
Defaults.AgentInfo.AgentRadius      = 2.5
Defaults.AgentInfo.AgentHeight      = 5
Defaults.AgentInfo.AgentCanJump     = true
Defaults.AgentInfo.AgentCanClimb    = false
Defaults.AgentInfo.WaypointSpacing  = 4
Defaults.AgentInfo.Costs            = {Obstacle = math.huge} -- {Water = 20, myPFLink = 10, etc...}


-- == Visualization Configuration == --
Defaults.Visualization = {} :: any
Defaults.Visualization.Enabled              = false -- Master control for visualization
Defaults.Visualization.Path                 = true -- Show the path the NPC will take
Defaults.Visualization.PathColor            = Color3.fromRGB(98, 87, 255) -- (RED) Color of the path visualization
Defaults.Visualization.Celling              = false -- celling visualization, if true, the NPC will visualize the offset of the path to avoid obstacles around it.
Defaults.Visualization.CellingColor         = Color3.fromRGB(0, 255, 0) -- (GREEN) Color of the celling visualization
Defaults.Visualization.MovetoRaycast        = false -- Show the raycast used for MoveTo
Defaults.Visualization.MovetoRaycastColor   = Color3.fromRGB(0, 0, 255) -- (BLUE) Color of the raycast visualization
Defaults.Visualization.Tether               = false -- Show the tether between the NPCs if they are tethered together
Defaults.Visualization.TetherColor          = Color3.fromRGB(255, 255, 0) -- (YELLOW) Color of the tether visualization
Defaults.Visualization.CollisionInferencing = false

-- == Tracking Configuration == --
Defaults.Tracking = {} :: any
Defaults.Tracking.Enabled                           = false -- Master control for tracking
Defaults.Tracking.CollinearTargetPositionOffset     = 2 -- If set, the NPC will offset the target's position by this amount when calculating the path (only when using Moveto ops)
Defaults.Tracking.PredictionMagnitude               = 2 -- If true, the NPC will predict the target's movement and adjust its path accordingly
Defaults.Tracking.DistanceMovedThreshold            = 1 -- studs moved before retrack


-- == Skip To Waypoint Settings == --
Defaults.WaypointSkipping = {} :: any -- skips to x waypoint, if set to 1 (or below), it will not skip any waypoints (will always track to last waypoint)      
Defaults.WaypointSkipping.RegularPathfindSkip   = 2 -- Skips to waypoint #x to avoid a stutter from where the first (or multiple) waypoint lie. (Regular PF)
Defaults.WaypointSkipping.TrackingPathfindSkip  = 3 -- Skips to waypoint #x to avoid a stutter from where the first (or multiple) waypoint lie. (Tracking)


-- == Dynamic Retrack Configuration == --
Defaults.Tracking.DynamicRetrack = {} :: any

Defaults.Tracking.DynamicRetrack.MoveTo = {} :: any
Defaults.Tracking.DynamicRetrack.MoveTo.MinTimer = 0 -- minimum retrack time if last op was a DirectMoveTo
Defaults.Tracking.DynamicRetrack.MoveTo.MaxTimer = 1 -- maximum retrack time if last op was a DirectMoveTo
Defaults.Tracking.DynamicRetrack.MoveTo.GetRetrackTimeFunction = function(NPC: Instance, Target: Instance): number
    local timer = math.max(Common.GetDistanceFromNPCToTarget(NPC, Target) - 20, 0) / 40 -- basically is 0s (immediate) for first 20studs, and scales at 1s per 40studs after
    -- print(timer) 
    return timer

    -- another function handles the clamping of the timer, so this function can return any value.
    -- by default it chooses max if there is an error.
end

Defaults.Tracking.DynamicRetrack.MoveTo.ShouldRetrackFunction = function(NPC: Instance, Target: any): boolean
    return true
end

Defaults.Tracking.DynamicRetrack.Pathfind = {} :: any
Defaults.Tracking.DynamicRetrack.Pathfind.MinTimer = 0.5 -- minimum retrack time if last op was a pathfind
Defaults.Tracking.DynamicRetrack.Pathfind.MaxTimer = 3 -- maximum retrack time if last op was a pathfind
Defaults.Tracking.DynamicRetrack.Pathfind.GetRetrackTimeFunction = function(NPC: Instance, Target: Instance): number
    local timer = Common.GetDistanceFromNPCToTarget(NPC, Target) / 80 -- basically is 1s per 80 studs
    -- print(timer)
    return timer
end

Defaults.Tracking.DynamicRetrack.Pathfind.ShouldRetrackFunction = function(NPC: Instance, Target: any): boolean
    return true
end

    -- it should be noted, theses functions/settings do not change even if a new cfg is used and the values are changed. (if they use a val)
    -- the function must be replaced.
    -- this is as we cannot use a cyclic dependency to the ConfigHandler file
    -- if someone wants to fix they can.

    
-- == Direct MoveTo Configuration == --
Defaults.DirectMoveTo = {} :: any
Defaults.DirectMoveTo.Enabled               = true
Defaults.DirectMoveTo.ActivationDistance    = 60    -- If the distance between the NPC & Target is less than this setting, it will be possible to use DirectMoveTo.
Defaults.DirectMoveTo.HeightLimit           = 10     -- If the difference between the Y position of the NPC & Target is less than this setting, it will be possible to use DirectMoveTo
Defaults.DirectMoveTo.TrackingOnly          = true
Defaults.DirectMoveTo.AvoidUseHook          = nullbind  -- Allows the user to add a custom function which is called every time DirectMoveTo could potentially be used, if a value of TRUE is returned, the system will NOT use DirectMoveTo.

-- == Direct MoveTo -> Raycast Settings
Defaults.DirectMoveTo.Raycast = {} :: any
Defaults.DirectMoveTo.Raycast.Enabled                       = true  -- Enables raycasting that must return a positive result to use the DirectMoveTo method.
Defaults.DirectMoveTo.Raycast.Range                         = Defaults.DirectMoveTo.ActivationDistance + 10  -- The maximum range the raycast will check for obstacles between the NPC & Target
Defaults.DirectMoveTo.Raycast.SeeThroughTransparentParts    = false  -- If true, the raycast will ignore parts with transparency greater than or equal to MinimumTransparency
Defaults.DirectMoveTo.Raycast.SeeThroughNonCollidable       = true  -- If true, the raycast will ignore non-collidable parts
Defaults.DirectMoveTo.Raycast.MinimumTransparency           = 0.001 -- The minimum transparency a part must have to be considered "see-through" if SeeThroughTransparentParts is true
-- Defaults.DirectMoveTo.Raycast.FilterTable                   = {}    -- A table of instances that the raycast will ignore (in addition to the NPC)
Defaults.DirectMoveTo.Raycast.FilterAttempts                = 10    -- The number of attempts the raycast will make to find a clear path (if the raycast hits something, it will retry up to this many times)
Defaults.DirectMoveTo.Raycast.OffsetFromOrigin              = Vector3.new(0, 0, 0) -- An offset added to the origin of the raycast (the NPC's position)
Defaults.DirectMoveTo.Raycast.OffsetFromTarget              = Vector3.new(0, 0, 0) -- An offset added to the target of the raycast (the Target's position)
Defaults.DirectMoveTo.Raycast.FilterFunction                = function(hit: Instance) return false end -- A function which can be used to filter any of the hit instances if True is returned.
-- Defaults.DirectMoveTo.Raycast.OutputCollision             = false -- If true, the raycast will output the part it collided with (for debugging purposes)

-- == Direct MoveTo -> Collision Inferencing Config == --
Defaults.DirectMoveTo.CollisionInferencing = {} :: any
Defaults.DirectMoveTo.CollisionInferencing.Enabled           = true  -- Enables a check between the NPC & Target to see if anything is colliding.
Defaults.DirectMoveTo.CollisionInferencing.MinColliderRange  = math.max(Defaults.Tracking.CollinearTargetPositionOffset, Defaults.AgentInfo.AgentRadius / 2)
Defaults.DirectMoveTo.CollisionInferencing.MaxColliderRange  = 3  -- Max range of the check
Defaults.DirectMoveTo.CollisionInferencing.YOffsetFromGround = 3     -- studs off ground
Defaults.DirectMoveTo.CollisionInferencing.YSizeOfCollider   = 1     -- studs tall    (i would recommend enabling visualization for this setting)
-- Defaults.DirectMoveTo.CollisionInferencing.Timeout           = 1     -- maybe implemented in future

-- == Direct MoveTo -> Jump Handler Config == --
Defaults.DirectMoveTo.JumpHandler = {} :: any
Defaults.DirectMoveTo.JumpHandler.Enabled                   = false  -- Allows Forbidden to make use of the JumpHandler when using DirectMoveTo
Defaults.DirectMoveTo.JumpHandler.MinConditionReachedTime   = .25   -- Has reach the stuck conditions for "x" seconds
Defaults.DirectMoveTo.JumpHandler.NextJumpMinTime           = 1     -- Cannot jump again for "x" seconds
Defaults.DirectMoveTo.JumpHandler.DistanceFromMoveToPoint   = 2     -- Distance from the designated point where the ai should be where it can jump 
Defaults.DirectMoveTo.JumpHandler.CustomJumpFunction        = nil -- if this returns true, the AI will jump (ignores all other conditions)

-- == Direct MoveTo -> Checking Floor Config == --
Defaults.DirectMoveTo.CheckFloor = {} :: any
Defaults.DirectMoveTo.CheckFloor.Enabled                     = true -- Before attempting a move to, it will check for voids in the floor.
Defaults.DirectMoveTo.CheckFloor.FailHeight                  = 12 -- If the distance from the raycast to the ground is this (or more), then it is considered a fail.
Defaults.DirectMoveTo.CheckFloor.RaycastSpacing              = 5 -- How spaced out should the raycast be to the target.
Defaults.DirectMoveTo.CheckFloor.AlwaysRaycastThisDistance   = 2 -- What distance should always be raycasted (in studs away from the NPC)
Defaults.DirectMoveTo.CheckFloor.CheckFrequencyTimer         = 1 -- How often should the checks be done? (if possible)
Defaults.DirectMoveTo.CheckFloor.BlockDirectMoveToTimer      = 3 -- How long should an attempt to do another DirectMoveTo call be blocked for. (ai safety)
Defaults.DirectMoveTo.CheckFloor.DisableIfDistanceIsLessThan = Defaults.AgentInfo.AgentRadius * 3 -- If the distance to the target is less than this, it will not check the floor


-- == Hooks Configuration == --
Defaults.Hooks = {} :: any
Defaults.Hooks.PathfindingLinkReached = function(NPC: Instance, Waypoint: PathWaypoint): boolean
    local NPCActual = Common.GetBasePart(NPC)
    if NPCActual then
        NPCActual.CFrame = CFrame.new(Waypoint.Position)
    end

    return true
end
Defaults.Hooks.MovingToWaypoint = nullbind
Defaults.Hooks.Stuck = function(NPC: Instance, Target: any): boolean -- if you come up with a better idea for this, let me know! (default func tho)
    -- 9/3/24 @rman501, forgot to add position of the NPC causing AI to go to ~0,0,0
	local NPCHuman = NPC:FindFirstChildOfClass("Humanoid")
    if NPCHuman == nil then return false end
    if NPCHuman.Health == 0 then return false end

	
	local NPCActual = Common.GetBasePart(NPC)
	if NPCActual == nil then return false end

	local NPCPos = NPCActual.CFrame.Position
    
    local randDir = Vector3.new(math.random(-1,1), 0, math.random(-1,1)).Unit
    if randDir.X ~= randDir.X then return false end -- rand dir was NaN


	NPCHuman:MoveTo(NPCPos + randDir * 10) -- 9/30/24 @rman501, stuck fix, pos wasnt added.
	NPCHuman.Jump = true

    task.wait(1)
    
    return true
end
Defaults.Hooks.GoalReached = nullbind
Defaults.Hooks.StartAcknowledged = nullbind
Defaults.Hooks.StopAcknowledged = nullbind
Defaults.Hooks.PathingFailed = nullbind
Defaults.Hooks.PathingStarted = nullbind


-- == Debugging Configuration == --
Defaults.Debugging = {} :: any
Defaults.Debugging.Enabled              = false -- Master control for debugging
Defaults.Debugging.OutputToConsole      = true
Defaults.Debugging.StateTransitioning   = true
Defaults.Debugging.MovingToWaypoint     = false -- if true, the AI will log when it is moving to a waypoint
Defaults.Debugging.Verbosity            = 3 -- a verbosity ("how much crap can be stuffed into the console that's useless? A LOT")
-- Defaults.Debugging.LogToScript = true -- prints all outputs from Forbidden AI to a file.

return Defaults

-- TODO:// Add more default values as needed (and we need xD)