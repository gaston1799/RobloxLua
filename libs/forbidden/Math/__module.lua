--[[
A collection of Raycasting and Visibility functions.

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--


-- == Services == --


-- == Forbidden Architecture & Libraries == --
local root              = script.Parent
local int_Forbidden     = script.Parent
local MathVisualization     = remoteRequire("libs/forbidden/Math/MathVisualization")
local Common                = remoteRequire("libs/forbidden/Common")

-- == Libraries == --
local TablesLibrary = remoteRequire("libs/forbidden/Libraries/Tables")


-- == Initialization == --
local API = {}


-- == Type Definitions == --
export type RaycastSettings = {
	Range: number, 
    OriginPart: BasePart?,
	SeeThroughTransparentParts: boolean, 
	SeeThroughNonCollidable: boolean, 
	MinimumTransparency: number, 
	FilterTable: {}, 
	FilterAttempts: number,
	OffsetFromOrigin: Vector3,
	OffsetFromTarget: Vector3,
	-- VisualizeRaycast: boolean,
	OutputCollision: boolean,
    FilterFunction: (hit: BasePart) -> (boolean)
}


API.LineOfSight = function(Object1: Instance, Object2: Instance, raycastSettings: RaycastSettings): boolean
    
    -- Validate inputs
    if Object1 == nil then error("Object1 was nil!") end
	if Object2 == nil then error("Object2 was nil!") end

    -- Set default values for raycastSettings if not provided
    raycastSettings                         = raycastSettings or {} :: RaycastSettings
    raycastSettings.OriginPart                  = raycastSettings.OriginPart or nil
    raycastSettings.Range                       = raycastSettings.Range or 100
    raycastSettings.SeeThroughTransparentParts  = raycastSettings.SeeThroughTransparentParts or false
    raycastSettings.SeeThroughNonCollidable     = raycastSettings.SeeThroughNonCollidable or false
    raycastSettings.MinimumTransparency         = raycastSettings.MinimumTransparency or 0.001
    raycastSettings.FilterTable                 = raycastSettings.FilterTable or {Object1}
    raycastSettings.FilterAttempts              = raycastSettings.FilterAttempts or 10
    raycastSettings.OffsetFromOrigin            = raycastSettings.OffsetFromOrigin or Vector3.new(0, 0, 0)
    raycastSettings.OffsetFromTarget            = raycastSettings.OffsetFromTarget or Vector3.new(0, 0, 0)
    -- raycastSettings.VisualizeRaycast            = raycastSettings.VisualizeRaycast or false
    raycastSettings.OutputCollision             = raycastSettings.OutputCollision or false
    raycastSettings.FilterFunction              = raycastSettings.FilterFunction or function() return false end

    -- == Main Bodies == --
    local OriginMainBody = raycastSettings.OriginPart
    if OriginMainBody == nil then
        OriginMainBody = Common.GetBasePart(Object1)
    end
    local TargetMainBody = Common.GetBasePart(Object2)

    -- Perform the line of sight check using PhysicsService
    local OriginFinalPosition = OriginMainBody.CFrame.Position + raycastSettings.OffsetFromOrigin
    local TargetFinalPosition = TargetMainBody.CFrame.Position + raycastSettings.OffsetFromTarget

    -- Check distance (cheap & quick)
    if (TargetFinalPosition - OriginFinalPosition).Magnitude > raycastSettings.Range then
        if raycastSettings.OutputCollision then print("Out of range!") end
        return false
    end

    -- dir math
    local direction = (TargetFinalPosition - OriginFinalPosition).Unit

    -- Setup raycast params
    local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = TablesLibrary.DeepCopy(raycastSettings.FilterTable)
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.CollisionGroup = OriginMainBody.CollisionGroup -- 5/17/25 @add collision group to raycast.

    local function isFiltered(hit: BasePart): boolean
        
        -- Transparency Filter
        if raycastSettings.SeeThroughTransparentParts then
            if hit.Transparency >= raycastSettings.MinimumTransparency then return true end
        end

        -- Can Collide Filter
        if raycastSettings.SeeThroughNonCollidable then
            if not hit.CanCollide then return true end
        end
        
        -- Custom Filter
        if raycastSettings.FilterFunction(hit) then return true end
        
        return false
    end

    local function isDescendantOfTarget(hit: Instance, parent: Instance): boolean
        local p = hit
        local limit = 5
        
		if hit == parent then return true end

        for i=1,limit,1 do
            if p.Parent == nil then return false end
            p = p.Parent
            if p == parent then return true end
        end

        return false
    end

    local function doRaycast(): RaycastResult?
		return workspace:Raycast(OriginFinalPosition, direction * raycastSettings.Range, raycastParams)
    end

    -- loop through attempts.
    local parentTarget = TargetMainBody
    if typeof(Object2) == "Instance" then
        
        if Object2:IsA("Model") or Object2:IsA("BasePart") then
            parentTarget = Object2
        end

        if Object2:IsA("Player") then
            parentTarget = Object2.Character
        end
    end
    for i=1, raycastSettings.FilterAttempts, 1 do
        -- initialize result
        local result: RaycastResult? = doRaycast()
        if result == nil or result.Instance == nil then return false end -- out of range, then exit.
        if raycastSettings.OutputCollision then print(result.Instance) end
        if not (result.Instance:IsA("BasePart") or result.Instance:IsA("Model")) then return false end  -- terrain hit, then exit
        if isDescendantOfTarget(result.Instance, parentTarget) then return true end -- if target hit, then all is good.
        if isFiltered(result.Instance) then raycastParams:AddToFilter(result.Instance); continue end -- if filter, add and continue
        return false
    end

    -- reached limit
    return false
end

 -- For Players
API.IsOnScreen = function(PartToCheck: BasePart, doRaycast: boolean): boolean

    if PartToCheck == nil then error("[Forbidden.Math.InPlayerView] PartToCheck was nil!") end

	local losCharacter = true

	local player = game.Players.LocalPlayer
	local camera = game.Workspace.CurrentCamera
	local final = PartToCheck

	if PartToCheck:IsA("Model") then
		if PartToCheck.PrimaryPart ~= nil then
			final = PartToCheck.PrimaryPart
		end
	end

	-- In viewport check
	local _vector, inViewport = camera:WorldToViewportPoint(final.Position)

	if doRaycast then
        local raycastSettings: RaycastSettings = {Range = 100, SeeThroughTransparentParts = true, FilterTable = {player.Character}} :: RaycastSettings
		losCharacter = API.LineOfSight(player.Character, PartToCheck, raycastSettings)
	end

	-- Check if all values are correct
	local isVisible = inViewport and losCharacter
	if isVisible then
		return true
	end

	return false
end

-- For Any Humanoid
API.IsInView = function(FromCharacter: Instance, TargetOther: Instance, detectionFOV: number, doRaycast: boolean, raycastSets: RaycastSettings): boolean

    -- Validate inputs
    if FromCharacter == nil then error("[Forbidden.Math.InPlayerView] FromCharacter was nil!") end
    if TargetOther == nil then error("[Forbidden.Math.InPlayerView] TargetOther was nil!") end

	-- Defaults
	if detectionFOV == nil then detectionFOV = 70 end
	if doRaycast == nil then doRaycast = false end

	-- Error Protection
	if detectionFOV < 0 then detectionFOV = 0 end
	if detectionFOV > 180 then detectionFOV = 180 end

	-- Get HRT
	local FromActual = FromCharacter:FindFirstChild("HumanoidRootPart")
    local ActualOther = Common.GetBasePart(TargetOther)

	if FromActual == nil then error("[Forbidden.Math.InPlayerView] The NPC provided does not contain a HumanoidRootPart!") end
    if ActualOther == nil then error("[Forbidden.Math.InPlayerView] The Target provided does not contain a BasePart!") end

	-- Make sure these components are not nil.
	if raycastSets == nil then raycastSets = {} :: RaycastSettings end
	if raycastSets.FilterTable == nil then
		raycastSets.FilterTable = {FromCharacter}
	end


	-- Raycast
	if doRaycast then
		if not API.LineOfSight(FromActual, TargetOther, raycastSets) then return false end
	end

	-- FOV Check
    local angle = math.acos(FromActual.CFrame.LookVector:Dot((ActualOther.CFrame.Position-FromActual.CFrame.Position).Unit))
    local isInFOVAngle = angle < detectionFOV * (math.pi / 180) -- 0: Ahead  PI: Behind 	(symmetrical on left and right sides of AI)
    
    if not isInFOVAngle then return false end

	return true
end


return API