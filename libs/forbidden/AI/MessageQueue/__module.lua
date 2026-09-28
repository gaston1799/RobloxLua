--[[
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs


TODO://
    How do we handle the active request?
    Store prev path data here?
        prob in PathfindingProcessor store following:
            which path failed in past?
            which path was most recently successful in past?
                to the same target?
]]--

-- == Libraries == --
local TablesLibrary = remoteRequire("libs/forbidden/Libraries/Tables")

-- == External Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")

-- == Forbidden Modules & Architecture == --
local Defaults = remoteRequire("libs/forbidden/AI/ConfigHandler/Defaults")


-- == Internal Types == --
type StopRequest = {
    ["RequestType"]: "Stop",
    ["Time"]: number,
    ["Yields"]: boolean, 
    ["Priority"]: number, -- Compares with the StartRequest, if greater, it will be processed first. (only matters if the time is the same)
    ["ProcessingState"]: AIT.ProcessingState,
    ["FinishedSignal"]: BindableEvent?
}

type StartRequest = {
    ["RequestType"]: "Start",
    ["Time"]: number,
    ["Yields"]: boolean,
    ["Target"]: any?, -- can be any type, but usually a Model or Instance or Location
    ["Priority"]: number, -- Compares with the EndRequest, if greater, it will be processed first (only matters if the time is the same)
    ["ProcessingState"]: AIT.ProcessingState,
    ["FinishedSignal"]: BindableEvent?
}

type MQ_Singleton = {
    ["ActiveConfig"]: AIT.Config,
    ["NewestStartRequest"]: StartRequest,
    ["NewestStopRequest"]: StopRequest,
    ["ActiveRequest"]: StartRequest? | StopRequest?,
    ["LastSuccessfulPath"]: {time: number, wps: {PathWaypoint}}?
}

type MQ = {
    [Instance]: MQ_Singleton
}

local Messages: MQ = {}

local API = {}


-- == Assisting Functions == --
local function InitializeMQ(NPC: Instance)
    
    -- If there is already a MQ_Singleton for this NPC, do not initialize again
    if Messages[NPC] then return end
    
    -- Create a new MQ_Singleton for the NPC
    Messages[NPC] = {
        ActiveConfig = TablesLibrary.DeepCopy(Defaults),
        NewestStartRequest = {
            RequestType = "Start",
            Time = os.clock(),
            Yields = false,
            Target = nil,
            Priority = AIT.RequestPriority.ConvertPriorityToNumber("DefaultStart"), -- default priority
            ProcessingState = "Processed"
        },
        NewestStopRequest = {
            RequestType = "Stop",
            Time = os.clock(),
            Yields = false,
            Priority = AIT.RequestPriority.ConvertPriorityToNumber("DefaultStop"), -- default priority
            ProcessingState = "Processed"
        },
        LastSuccessfulPath = {time = os.clock(), wps = {}},
        ActiveRequest = nil,
        Processing = false
    }
end

local function GetMQSingleton(NPC: Instance): MQ_Singleton
    -- Get the MQ_Singleton for the NPC, if it does not exist, initialize it
    if not Messages[NPC] then
        InitializeMQ(NPC)
    end

    return Messages[NPC]
end

-- == API Functions == --


API.SetLastSuccessfulPath = function(NPC: Instance, Waypoints: {PathWaypoint})
    if Waypoints == nil then warn("Waypoints table was nil!") end
    Messages[NPC].LastSuccessfulPath = {time = os.clock(), wps = Waypoints}
end

API.GetLastSuccessfulPath = function(NPC: Instance, TimeoutSeconds: number): {PathWaypoint}? -- TODO:// determine type stuff
    local LastPathInfo = Messages[NPC].LastSuccessfulPath
    
    if LastPathInfo.time + 1 < os.clock() then return nil end
    
    return LastPathInfo.wps
end


API.SetActiveRequest = function(NPC: Instance, Request: StartRequest | StopRequest)
    Request.ProcessingState = "Processing"
    GetMQSingleton(NPC).ActiveRequest = Request
end


API.PrintOutRequests = function(NPC: Instance)
    print(Messages)
end

API.GetNewRequest = function(NPC: Instance)
    local MQ_Singleton = GetMQSingleton(NPC)

    -- assisting vars
    local startExists = MQ_Singleton.NewestStartRequest.ProcessingState == "Requested"
    local stopExists  = MQ_Singleton.NewestStopRequest.ProcessingState == "Requested"

    -- IF NEITHER EXISTS, RETURN NIL
    if not startExists and not stopExists then
        return nil
    end

    -- IF 1 EXISTS AND THE OTHER DOES NOT, RETURN THE ONE THAT EXISTS
    if startExists and not stopExists then
        return MQ_Singleton.NewestStartRequest
    end

    if stopExists and not startExists then
        return MQ_Singleton.NewestStopRequest
    end

    -- IF BOTH EXIST, RETURN THE ONE WITH THE HIGHEST PRIORITY
    -- IF SAME, PREFER NEW START
    local function GetPrioritizedRequest()
        -- Priorities
        local startPriority = MQ_Singleton.NewestStartRequest.Priority
        local stopPriority  = MQ_Singleton.NewestStopRequest.Priority
    
        if startPriority > stopPriority then
            return MQ_Singleton.NewestStartRequest
        end
    
        if stopPriority > startPriority then
            return MQ_Singleton.NewestStopRequest
        end

        -- if same prio, prefer start
        return MQ_Singleton.NewestStartRequest
    end

    -- IF BOTH EXIST, RETURN THE ONE WITH THE LATEST TIME
    -- IF SAME, PREFER NEW START
    local function GetLatestRequest()
        -- Priorities
        local startTime = MQ_Singleton.NewestStartRequest.Time
        local stopTime  = MQ_Singleton.NewestStopRequest.Time

        if startTime > stopTime then
            return MQ_Singleton.NewestStartRequest
        end
    
        if stopTime > startTime then
            return MQ_Singleton.NewestStopRequest
        end

        -- if same time, prefer start
        return MQ_Singleton.NewestStartRequest
    end

    -- Prefer a higher priority?
    if not MQ_Singleton.ActiveConfig.RequestPrioritization.PreferTimeOverPriority.Enabled then
        return GetPrioritizedRequest()
    end

    -- Prefer a later time?
    if MQ_Singleton.ActiveConfig.RequestPrioritization.PreferTimeOverPriority.Enabled then
        local LatestRequest = GetLatestRequest()

        -- Reset older requests, if setting is enabled
        if MQ_Singleton.ActiveConfig.RequestPrioritization.PreferTimeOverPriority.ResetOlderRequests then

            if LatestRequest.RequestType == "Start" then
                MQ_Singleton.NewestStopRequest.ProcessingState = "Processed"
            end

            if LatestRequest.RequestType == "Stop" then
                MQ_Singleton.NewestStartRequest.ProcessingState = "Processed"
            end

        end

        -- Return latest
        return LatestRequest
    end


    error("this shouldn't be showing, if you can replicate contact @crit-dev")
    return nil
end


API.IsProcessingStartRequest = function(NPC: Instance): boolean
    local MQ_Singleton = GetMQSingleton(NPC)
    return MQ_Singleton.NewestStartRequest.ProcessingState == "Processing"
end


API.IsProcessingEndRequest = function(NPC: Instance): boolean
    local MQ_Singleton = GetMQSingleton(NPC)
    return MQ_Singleton.NewestStopRequest.ProcessingState == "Processing"
end

--[[
Returns true if the API is currently processing either a start or end request.
]]--
API.IsProcessing = function(NPC: Instance): boolean
    return API.IsProcessingStartRequest(NPC) or API.IsProcessingEndRequest(NPC)
end

API.SendStartMessage = function(NPC: Instance, Target: any, Yields: boolean?, Priority: AIT.RequestPriority? | number?): RBXScriptSignal?
    local MQ_Singleton = GetMQSingleton(NPC)

    local prio: number = AIT.RequestPriority.ConvertPriorityToNumber("DefaultStart")
    if Priority ~= nil then -- can be 0
        prio = AIT.RequestPriority.GetPriorityNumber(Priority)
    end

    -- If current request is not yet considered
    if MQ_Singleton.NewestStartRequest.ProcessingState == "Requested" then
        if MQ_Singleton.NewestStartRequest.Priority > prio then return end -- if non-processed req has greater prio then ignore new call
    end

    -- old: worked
    -- MQ_Singleton.NewestStartRequest.Time = os.clock()
    -- MQ_Singleton.NewestStartRequest.Target = Target
    -- MQ_Singleton.NewestStartRequest.Yields = Yields or false
    -- MQ_Singleton.NewestStartRequest.Priority = prio
    -- MQ_Singleton.NewestStartRequest.ProcessingState = "Requested"

    -- new: need it for BindableEvents
    MQ_Singleton.NewestStartRequest = {
        Time = os.clock(),
        Target = Target,
        Yields = Yields or false,
        Priority = prio,
        ProcessingState = "Requested",
        RequestType = "Start",
        FinishedSignal = nil
    }

    local event = nil
    if Yields then
        event = Instance.new("BindableEvent")
        MQ_Singleton.NewestStartRequest.FinishedSignal = event
    end

    return event
end


API.SendStopMessage = function(NPC: Instance, Yields: boolean?, Priority: AIT.RequestPriority? | number?): RBXScriptSignal?
    local MQ_Singleton = GetMQSingleton(NPC)

    local prio: number = AIT.RequestPriority.ConvertPriorityToNumber("DefaultStop")
    if Priority ~= nil then -- can be 0
        prio = AIT.RequestPriority.GetPriorityNumber(Priority)
    end

    -- If current request is not yet considered
    if MQ_Singleton.NewestStopRequest.ProcessingState == "Requested" then
        if MQ_Singleton.NewestStopRequest.Priority > prio then return end -- if non-processed req has greater prio then ignore new call
    end

    MQ_Singleton.NewestStopRequest = {
        Time = os.clock(),
        Yields = Yields or false,
        Priority = prio,
        ProcessingState = "Requested",
        RequestType = "Stop",
        FinishedSignal = nil
    }

    local event = nil
    if Yields then
        event = Instance.new("BindableEvent")
        MQ_Singleton.NewestStopRequest.FinishedSignal = event
    end

    return event
end

return API