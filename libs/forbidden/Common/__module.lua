local storage = remoteRequire("libs/forbidden/Common/Storage")
local typehelp = remoteRequire("libs/forbidden/Common/TypeHelp")

return {
    GetForbiddenStorageFolder = storage.GetForbiddenStorageFolder,
    GetForbiddenTemporaryWorkspaceFolder = storage.GetForbiddenTemporaryWorkspaceFolder,
    GetForbiddenWSPartsFolder = storage.GetForbiddenWSPartsFolder,
    GetBasePart = typehelp.GetBasePart,
    GetDistanceFromNPCToTarget = typehelp.GetDistanceFromNPCToTarget,
    TriggerCleanupTypeHelp = typehelp.TriggerCleanup
}