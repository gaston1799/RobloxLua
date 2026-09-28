--[[
Common Math & LOS Pre-Written Here
/!\ Forbidden Use Only /!\
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Setup == --
local API = {}


-- == Forbidden Modules & Architecture == --
local root = script.Parent.Parent
local Common        = remoteRequire("libs/forbidden/Common")
local MathModule    = remoteRequire("libs/forbidden/Math")
local ConfigHandler = remoteRequire("libs/forbidden/AI/ConfigHandler")
local ForbiddenDebugging = remoteRequire("libs/forbidden/AI/Debugging")
local MathVisualization = remoteRequire("libs/forbidden/Math/MathVisualization")

-- == API Functions == --
-- Target should be best of class (i.e. if char should be the model,   if part should be a part,   if pos should be the Common.GetBasePart)
API.CanMoveToRaycast = function(NPC: Instance, Target: Instance): boolean

    -- == Config == --
    local config = ConfigHandler.GetActiveConfig(NPC)
    if not config.DirectMoveTo.Raycast.Enabled then return true end

    local RaycastSettings: MathModule.RaycastSettings = config.DirectMoveTo.Raycast :: any


    return MathModule.LineOfSight(NPC, Target, RaycastSettings)
end

-- Checks if the floor is crossable (heuristic)
API.CanCrossFloorRaycast = function(NPC: Instance, Target: any): boolean
    local config = ConfigHandler.GetActiveConfig(NPC)

    local npc_main = Common.GetBasePart(NPC, true, NPC)
    local target_main = Common.GetBasePart(Target, true, NPC)

    if npc_main == nil then
        error("Cannot get BasePart in NPC: " .. NPC:GetFullName())
    end

    if target_main == nil then
        local targetName = typeof(Target) == "Instance" and Target:GetFullName() or tostring(Target)
        error("Cannot get BasePart in Target: " .. targetName)
    end

    local failHeight = config.DirectMoveTo.CheckFloor.FailHeight
    local spacing = config.DirectMoveTo.CheckFloor.RaycastSpacing
    local firstDist = config.DirectMoveTo.CheckFloor.AlwaysRaycastThisDistance

    if failHeight <= 0 then
        error("FailHeight must be > 0")
    end

    if spacing <= 0 then
        error("RaycastSpacing must be > 0")
    end

    local subv3 = target_main.Position - npc_main.Position
    local dist = subv3.Magnitude
    if dist == 0 then
        return true
    end

    local dir = subv3.Unit

    local function ValidRaycastToGround(position: Vector3)

        local raycastParams = RaycastParams.new()
        local filterTable = {NPC}

        if typeof(Target) == "Instance" then
            table.insert(filterTable, Target)
        elseif target_main then
            table.insert(filterTable, target_main)
        end

        raycastParams.FilterDescendantsInstances = filterTable
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.RespectCanCollide = true

        local result = workspace:Raycast(
            position,
            Vector3.new(0, -failHeight, 0),
            raycastParams
        )

        -- if config.Debugging.Enabled and config.Visualization.Enabled then

        --     if not result then
        --         MathVisualization.VisualizeRaycast(
        --             config.NPC, 
        --             position, 
        --             Vector3.new(0, -failHeight, 0), 
        --             result ~= nil
        --         )
        --     end
        -- end

        if result then
            ForbiddenDebugging.LogWithVerbosity(
                NPC,
                5,
                "Distance To Ground: " .. tostring(result.Distance) ..
                " | Position: (" ..
                string.format("%.3f", result.Position.X) .. ", " ..
                string.format("%.3f", result.Position.Y) .. ", " ..
                string.format("%.3f", result.Position.Z) .. ")"
            )
        end

        return result ~= nil
    end

    if firstDist > 0 then
        local sampleDist = math.min(dist, firstDist)
        if not ValidRaycastToGround(npc_main.Position + dir * sampleDist) then
            return false
        end
    end

    local distRemaining = dist
    while distRemaining - spacing > firstDist do
        distRemaining -= spacing
        if not ValidRaycastToGround(npc_main.Position + dir * distRemaining) then
            return false
        end
    end

    return true
end

return API