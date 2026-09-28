--[[ 7/21/25
Visualization for waypoints

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--


-- == Services == --
local debris = game:GetService("Debris")

-- == Forbidden Modules & Architecture == --
local root = script.Parent.Parent.Parent
local AIT               = remoteRequire("libs/forbidden/AI/Types")
local ConfigHandler     = remoteRequire("libs/forbidden/AI/ConfigHandler")
local Common            = remoteRequire("libs/forbidden/Common")


-- == Initialization == --
local API = {}
local Folders: {[Instance]: Folder} = {}

local storageFolderWS = Common.GetForbiddenStorageFolder()
local VisualizationFolder = Instance.new("Folder")
VisualizationFolder.Name = "Visualization"
VisualizationFolder.Parent = storageFolderWS


-- == Functions == --
local function CreateVisualizedParts(config: AIT.Config, nodes: {PathWaypoint}): {Part}
    local partsList: {Part} = {}

    local function createPart(index: number, node: PathWaypoint): Part
        local newPart       = Instance.new("Part")

        newPart.Shape           = Enum.PartType.Ball
        newPart.Color           = config.Visualization.PathColor
        newPart.Material        = Enum.Material.Neon
        newPart.CFrame          = CFrame.new(node.Position)
        newPart.Name            = tostring(index)
        newPart.Anchored        = true
        newPart.Size            = Vector3.new(1,1,1)
        newPart.CanCollide      = false
        newPart.CanQuery        = false

        return newPart
    end

    for index: number, node: PathWaypoint in pairs(nodes) do
        table.insert(partsList, createPart(index, node))
    end

    return partsList
end

local function DeleteVisualizedParts(folder: Folder)
    for _, part: Instance in pairs(folder:GetChildren()) do
        debris:AddItem(part, 0)
    end
end

local function ParentVisualizedParts(NPC: Instance, parts: {Part})
    local folder = Folders[NPC]
    for _, part: Instance in pairs(parts) do
        part.Parent = folder
    end
end

API.VisualizeWaypoints = function(NPC: Instance, nodes: {PathWaypoint}): Folder
    local config = ConfigHandler.GetConfig(NPC)
    
    if Folders[NPC] then
        -- make new parts
        local newParts = CreateVisualizedParts(config, nodes)

        -- destroy old parts
        DeleteVisualizedParts(Folders[NPC])

        -- parent new parts
        ParentVisualizedParts(NPC, newParts)
    end
    
    if not Folders[NPC] then 
        -- make folder
        local thisFolder = Instance.new("Folder")
        thisFolder.Name     = NPC:GetFullName()
        thisFolder.Parent   = VisualizationFolder 
        Folders[NPC] = thisFolder

        -- make new parts
        local newParts = CreateVisualizedParts(config, nodes)

        -- parent parts
        ParentVisualizedParts(NPC, newParts)
    end

    return Folders[NPC]
end

API.DeleteVisualization = function(NPC: Instance)

    -- Validate
    if NPC == nil then return end
    if not Folders[NPC] then return end
    if #Folders[NPC]:GetChildren() < 1 then return end

    -- Delete parts
    DeleteVisualizedParts(Folders[NPC])
end

API.TriggerCleanup = function(NPC: Instance)
    -- Validate
    if not Folders[NPC] then return end

    -- Delete parts
    DeleteVisualizedParts(Folders[NPC])

    -- Remove folder
    Folders[NPC]:Destroy()
    Folders[NPC] = nil
end

return API