--[[ Contains common math functions...

]]--

-- == References == --


-- == Libraries == -- 
local MathLibrary = remoteRequire("libs/forbidden/Math")
local root              = script.Parent.Parent
local Common            = remoteRequire("libs/forbidden/Common")
local TablesLibrary     = remoteRequire("libs/forbidden/Libraries/Tables")


-- == Types == -
export type RaycastSettings = MathLibrary.RaycastSettings


-- == Initialization == --
local API = {}


-- note for future devs: this is a direct copy of the one in the Math.
-- reason why it is like this?
-- because of the time I had to develop this.
-- please remove this duplicate sys if you can and have time :)
-- == API Functions == --
--[=[
    Checks if there is a line of sight between two objects.
    @param FromCharacter <strong>Model</strong> The object to raycast from (the character).
    @param TargetParent <strong>Model</strong> The parent model of the target object.
    @param TargetParts <strong>{BasePart}</strong> The parts of the target object to check against.
    @param RaycastSettings <strong>RaycastSettings</strong> A table containing settings for the raycast (RaycastSettings).
    @return boolean indicating if there is a line of sight.

    <code>
    type RaycastSettings = {

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
    </code>
]=]--
API.CheckLoSByProvidedLimits = function(FromCharacter: Model, TargetParent: Model, TargetParts: {BasePart}, RaycastSettings: RaycastSettings): boolean

    -- Validate inputs
    if FromCharacter == nil then error("FromCharacter was nil!") end
	if TargetParent == nil then error("TargetParent was nil!") end
    if TargetParts == nil then error("TargetParts was nil!") end
    if typeof(TargetParts) ~= "table" then error("TargetParts is not a table.") end
    if #TargetParts < 1 then error("No target parts!") end


    -- Set default values for raycastSettings if not provided
    local raycastSettings                         = RaycastSettings or {} :: RaycastSettings
    raycastSettings.OriginPart                  = RaycastSettings.OriginPart or nil 
    raycastSettings.Range                       = RaycastSettings.Range or 100
    raycastSettings.SeeThroughTransparentParts  = RaycastSettings.SeeThroughTransparentParts or false
    raycastSettings.SeeThroughNonCollidable     = RaycastSettings.SeeThroughNonCollidable or false
    raycastSettings.MinimumTransparency         = RaycastSettings.MinimumTransparency or 0.001
    raycastSettings.FilterTable                 = RaycastSettings.FilterTable or {FromCharacter}
    raycastSettings.FilterAttempts              = RaycastSettings.FilterAttempts or 10
    raycastSettings.OffsetFromOrigin            = RaycastSettings.OffsetFromOrigin or Vector3.new(0, 0, 0)
    raycastSettings.OffsetFromTarget            = RaycastSettings.OffsetFromTarget or Vector3.new(0, 0, 0)
    -- raycastSettings.VisualizeRaycast            = RaycastSettings.VisualizeRaycast or false
    raycastSettings.OutputCollision             = RaycastSettings.OutputCollision or false
    raycastSettings.FilterFunction              = RaycastSettings.FilterFunction or function() return false end

    
    local function RaycastForTargetPart(tarPart: BasePart): boolean

        -- == Main Bodies == --
        local OriginMainBody = raycastSettings.OriginPart
        if OriginMainBody == nil then
            OriginMainBody = Common.GetBasePart(FromCharacter)
        end
        local TargetMainBody = tarPart

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
        -- print(direction)

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

        for i=1, raycastSettings.FilterAttempts, 1 do
            -- initialize result
            local result: RaycastResult? = doRaycast()
            if result == nil or result.Instance == nil then return false end -- out of range, then exit.
            if raycastSettings.OutputCollision then print(result.Instance) end
            if not (result.Instance:IsA("BasePart") or result.Instance:IsA("Model")) then return false end  -- terrain hit, then exit
            if isDescendantOfTarget(result.Instance, TargetParent) then return true end -- if target hit, then all is good.
            if isFiltered(result.Instance) then raycastParams:AddToFilter(result.Instance); continue end -- if filter, add and continue
            return false
        end

        -- reached limit
        return false
    end

    for _, tarPart in pairs(TargetParts) do
        if RaycastForTargetPart(tarPart) then return true end
    end

    -- none can see
    return false 
end

--[=[
    Checks if there is a line of sight between two characters.

    Auto checks the arms, and center of mass, and head.

    @param FromCharacter <strong>Model</strong> The object to raycast from (the character).
    @param TargetParent <strong>Model</strong> The parent model of the target object.
    @param TargetParts <strong>{BasePart}</strong> The parts of the target object to check against.
    @param RaycastSettings <strong>RaycastSettings</strong> A table containing settings for the raycast (RaycastSettings).
    @return boolean indicating if there is a line of sight.

    <code>
    type RaycastSettings = {

        Range: number, 

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
    </code>
]=]--
API.CheckLoSByAutomaticLimits = function(FromCharacter: Model, TargetParent: Model, RaycastSettings: RaycastSettings): boolean
    local targetParts = {}

    local function SearchAndAdd(PartName: string)
        local part = TargetParent:FindFirstChild(PartName)
        if not part then return end
        table.insert(targetParts, part)
    end

    -- r15
    SearchAndAdd("RightLowerArm")
    SearchAndAdd("LeftLowerArm")

    -- both
    SearchAndAdd("Head")
    SearchAndAdd("HumanoidRootPart")

    -- r6
    SearchAndAdd("Right Arm")
    SearchAndAdd("Left Arm")

    return API.CheckLoSByProvidedLimits(FromCharacter, TargetParent, targetParts, RaycastSettings)
end

return API