--[[
Stuff related to types, though it stretches that definition quite a bit.
Utilized to make sure the scripts in behavior 

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Services == --
local debris = game:GetService("Debris")


-- == Setup == --
local updateList: {[Instance]: BasePart} = {}
local API = {}


-- == Forbidden Modules & Architecture == --
local Storage = remoteRequire("libs/forbidden/Common/Storage")


-- == Internal Functions == --
local nameseq = 0
local function GetNumberedName()
    nameseq += 1
    return "AUTO-NAMED " .. tostring(nameseq)
end

local function _MakePart(v3: Vector3, DoUpdateObject: Instance?): Part
    
    local part = nil
    if DoUpdateObject then
        part = updateList[DoUpdateObject]
    end


    if part == nil then
        part = Instance.new("Part")
        part.Transparency   = 1
        part.CanCollide     = false
        part.Anchored       = true
        part.CastShadow     = true
        part.Material       = Enum.Material.Neon
        part.Color          = Color3.fromHex("#FFFF00")
        part.Size           = Vector3.new(1,1,1)
        part.Name           = GetNumberedName()
        part.Parent         = Storage.GetForbiddenWSPartsFolder()

        if DoUpdateObject then
            updateList[DoUpdateObject] = part
        end
    end

    part.Position = v3
    
    return part
end


local function GetBasePartFromModel(Model: Model): BasePart?
     if Model:FindFirstChildOfClass("Humanoid") then
            
        -- Return the HRT if available.
        local partToReturn = Model:FindFirstChild("HumanoidRootPart")
            if partToReturn ~= nil then return partToReturn end
        
        -- Return the Torso if available.
        partToReturn = Model:FindFirstChild("Torso")
            if partToReturn ~= nil then return partToReturn end
    end

    if Model.PrimaryPart then
        return Model.PrimaryPart
    end

    local ffoc = Model:FindFirstChildOfClass("BasePart")
    if ffoc then
        return ffoc
    end

    return nil
end 


-- == API Functions == --
API.GetBasePart = function(Object: any, MakePart: boolean?, DoUpdateOwner: Instance?): BasePart?
    
    local ObjectType = typeof(Object)

    if ObjectType == "Instance" then
        if Object:IsA("BasePart") then
            return Object
        end

        if Object:IsA("Model") then
           return GetBasePartFromModel(Object)
        end

        if Object:IsA("Player") then
            local character = Object.Character
            if character then
                return GetBasePartFromModel(character)
            end
        end
    end

    if ObjectType == "CFrame" then
        if MakePart then
            return _MakePart(Object.Position, DoUpdateOwner)
        end
    end

    if ObjectType == "Vector3" then
        if MakePart then
            return _MakePart(Object, DoUpdateOwner)
        end
    end

    return nil
end

API.GetDistanceFromNPCToTarget = function(NPC: Instance, Target: Instance): number

    local NPCActual = API.GetBasePart(NPC)
    local TargetActual = API.GetBasePart(Target, true, NPC)

    if NPCActual == nil then error("NPC Actual nil") end
    if TargetActual == nil then error("Target Actual nil") end

    local dist = (NPCActual.CFrame.Position - TargetActual.CFrame.Position).Magnitude
    return dist
end

API.TriggerCleanup = function(NPC: Instance)
    if not updateList[NPC] then return end
    debris:AddItem(updateList[NPC], 0)
    updateList[NPC] = nil
end

return API