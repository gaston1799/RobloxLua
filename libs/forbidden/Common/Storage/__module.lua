--[[
Temporary Organization & Storage Assistance

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Setup == --
local API = {}

local fbdn_workspace_temp = nil
API.GetForbiddenTemporaryWorkspaceFolder = function(): Folder
    
    if fbdn_workspace_temp ~= nil then return fbdn_workspace_temp end
    
    fbdn_workspace_temp           = Instance.new("Folder")
    fbdn_workspace_temp.Name      = "ForbiddenTemporaryFolder"
    fbdn_workspace_temp.Parent    = workspace
    
    return fbdn_workspace_temp
end

local fbdn_workspace_ws_temp = nil
API.GetForbiddenWSPartsFolder = function(): Folder

    if fbdn_workspace_ws_temp ~= nil then return fbdn_workspace_ws_temp end

    local forbidden_temp_part_folder = Instance.new("Folder")
    forbidden_temp_part_folder.Name     = "Common-Parts"
    forbidden_temp_part_folder.Parent   = API.GetForbiddenTemporaryWorkspaceFolder()

    return fbdn_workspace_ws_temp
end

local fbdn_workspace_storage_temp = nil
API.GetForbiddenStorageFolder = function(): Folder
    if fbdn_workspace_storage_temp ~= nil then return fbdn_workspace_storage_temp end

    fbdn_workspace_storage_temp           = Instance.new("Folder")
    fbdn_workspace_storage_temp.Name      = "ForbiddenStorageFolder"
    fbdn_workspace_storage_temp.Parent    = workspace

    return fbdn_workspace_storage_temp
end

return API