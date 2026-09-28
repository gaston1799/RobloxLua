--[[
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Services == --

-- == Libraries == --


-- == Forbidden Modules & Architecture == --

-- == Types == --


-- == Setup == --
local API = {}


-- == API Functions == --
--[=[
    Returns the closest position on the ground beneath a position, cannot exceed a height limit.
    
    @param Position <strong>Vector3</strong> Origin position of the raycast.
    @param HeightLimit <strong>number?</strong> The limit of the distance the raycast can be grounded by. (default: 3 studs)
    
    @return <strong>Vector3?</strong> Returns the grounded position or <strong>nil</strong> if not possible.
]=]
API.GetGroundedPosition = function(Position: Vector3, PartsToFilter: {BasePart}, HeightLimit: number?): Vector3?

    -- 10/24/24 @rman501, added adjustedTargetPos.
    local raycastParams = RaycastParams.new()
    local filterTable = {PartsToFilter}
    
    raycastParams.FilterDescendantsInstances = filterTable
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.RespectCanCollide = true
    -- raycastParams:AddToFilter(???) -- can be table or instance

    local range = 3
    if HeightLimit then range = HeightLimit end

    local result = workspace:Raycast(Position, Vector3.new(0, -1, 0) * range, raycastParams)

    if result == nil then return nil end -- 10/26/24 @rman501, edge case.
    if result.Instance then
        --print(part.CFrame.Position - hitPoint)
        return result.Position + Vector3.new(0,2,0) -- 8/31/24 add slight y offset
    end

    return Position
end

-- these todos in ComputePath
-- TODO:// use dir between 2 wps and dist ??? (for offsetting a pf (no track, or maybe even w/ track))
-- TODO:// if dist < offset then return cur pos?
--[=[
    Returns a position in the direction of <code>Origin</code> from Target, the magnitude of which is determined by Offset.
    
    @param Position <strong>Vector3</strong> Origin position of the raycast.
    @param HeightLimit <strong>number?</strong> The limit of the distance the raycast can be grounded by. (default: 3 studs)
    
    @return <strong>Vector3?</strong> Returns the grounded position or <strong>nil</strong> if not possible.
]=]
API.GetCollinearTargetPositionOffset = function(Origin: Vector3, Target: Vector3, Offset: number): Vector3
    local delta: Vector3 = Target - Origin
    if Offset == 0 then return Origin end

    if delta.Magnitude == 0 then
        return Origin
    end

    if delta.Magnitude < Offset then
        return Target
    end

    return Origin + (delta.Unit * Offset)
end

API.PredictMovement = function(target_part: BasePart, PredictionMagnitude: number): Vector3

    local target_pos = target_part.CFrame.Position
    if PredictionMagnitude <= 0 then return target_pos end

    if target_part.AssemblyLinearVelocity.Magnitude < 0.1 then
            -- If the target is not moving, then we can just use the target position.
        return target_pos
    end

    local tR_Velo_Corrected = Vector3.new(target_part.AssemblyLinearVelocity.X, 0, target_part.AssemblyLinearVelocity.Z).Unit

    -- source: https://devforum.roblox.com/t/how-do-i-check-if-a-value-is-nan/1262807/2
    -- source: https://stackoverflow.com/questions/37753694/lua-check-if-a-number-value-is-nan
    if tR_Velo_Corrected.X ~= tR_Velo_Corrected.X then -- nan check
        return target_pos    
    end

    target_pos = target_pos + tR_Velo_Corrected * PredictionMagnitude

    return target_pos
end

return API