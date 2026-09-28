-- [External Types] --
local TConfig = remoteRequire("libs/forbidden/AI/Types/TConfig")
local TRequestPriority = remoteRequire("libs/forbidden/AI/Types/TRequestPriority")

-- [Exported Types] --
export type Config = TConfig.Config

-- local StopTypes = table.freeze({
--     CurrentPosition = 0,
--     NoStopLogic = 1, -- this means the NPC will stop at the next waypoint, i.e. forbidden let's the current MoveTo finish, and does not care about what happens in between.
-- })
export type StopType = TConfig.StopType

-- local ProcessingState = table.freeze({
--     Requested = 0, -- a request has been made, but not yet processed
--     Processing = 1, -- a request is being processed
--     Processed = 2, -- a request has been processed
-- })
export type ProcessingState = "Requested" | "Processing" | "Processed" | string

export type RequestPriority = TRequestPriority.RequestPriority

export type AgentInfo = TConfig.AgentInfo

-- enums
return {
    -- StopType = StopTypes,
    RequestPriority = TRequestPriority,
    -- ProcessingState = ProcessingState,
}