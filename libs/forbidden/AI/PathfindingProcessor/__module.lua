--[[ 6/26/25
Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs


TODO://
    states?
]]--

-- == Services == --
local rs                    = game:GetService("ReplicatedStorage")
local PathfindingService    = game:GetService("PathfindingService")
local debris                = game:GetService("Debris")


-- == Libraries == --
local RBLXStateMachineLib = remoteRequire("libs/forbidden/Packages/robloxstatemachine")


-- == Forbidden Modules & Architecture == --
local root          = script.Parent.Parent
local ConfigHandler = remoteRequire("libs/forbidden/AI/ConfigHandler")
-- local MessageQueue  = require(root.AI.MessageQueue)
local DirectMoveTo  = remoteRequire("libs/forbidden/AI/DirectMoveTo")
-- local MathModule    = require(root.Math)
local Common        = remoteRequire("libs/forbidden/Common")
local ForbiddenDebugging = remoteRequire("libs/forbidden/AI/Debugging")
local TriggerCleanup = remoteRequire("libs/forbidden/AI/PathfindingProcessor/TriggerCleanup")


-- == External Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")


-- == Internal Functions == --



-- == Setup == --
local API = {}
local StateMachines: {
    [Instance]: {
        State: {
            Data: {
                time: number,
                Config: AIT.Config,
                UpdateRequired: boolean
            },
            Name: string
        },
        Destroy: (self: any) -> ()
    }
} = {}
local BlockedIndices: {[Instance]: {number}} = {}
local Paths: {[Instance]: {AgentInfo: AIT.AgentInfo, PathObject: Path, UsingPathfind: boolean}} = {}

-- == API Functions == --
API.InitializeStateMachine = function(NPC: Instance)
    if StateMachines[NPC] then return end

    local NPCHuman = NPC:FindFirstChildOfClass("Humanoid")
    if NPCHuman == nil then error("NPC Human is nil!") end

    local states = RBLXStateMachineLib:LoadDirectory(script.States)

    local thisStateMachine = RBLXStateMachineLib.new(
        "Idle", -- Initial State
        states,
        { -- data
            -- time = tick(), -- Sends the current tick
            Config = ConfigHandler.GetActiveConfig(NPC),
            NPC = NPC,
            Target = nil,
            Waypoints = {},
            LastTrackingRecall = 0,
            RecallType = "DirectMoveTo",
            UpdateRequired = false
        }
    )

    thisStateMachine.StateChanged:Connect(function()
        local prevState = thisStateMachine:GetPreviousState()
        local newState = thisStateMachine:GetCurrentState()
        ForbiddenDebugging.Log(NPC, "State Changed: [", prevState, "] -> [", newState, "]")
    end)
    
    thisStateMachine.Data.StateMachine = thisStateMachine

    StateMachines[NPC] = thisStateMachine

    -- cleanup
    local function DestroyStateMachine()

        ForbiddenDebugging.Log(NPC, "Destroying State Machine for NPC: ", NPC:GetFullName())

        if not StateMachines[NPC] then return end
        
        StateMachines[NPC]:Destroy()
        StateMachines[NPC] = nil
        if Paths[NPC].PathObject then
            Paths[NPC].PathObject:Destroy()
        end
        Paths[NPC] = nil
        BlockedIndices[NPC] = nil

        TriggerCleanup(NPC)

        collectgarbage("count") -- if someone sees this, please tell me if this is useful or not.
    end

    NPCHuman.Died:Connect(DestroyStateMachine)
    NPC.Destroying:Connect(DestroyStateMachine)
end


API.PrintStateMachines = function()
    print(StateMachines)
end


--[=[
Computes a path with the current configuration settings for the NPC.

@param NPC <strong>Instance</strong> The NPC to compute the path from. a.k.a. Origin
@param Target <strong>any</strong> The location or instance to compute the path to. a.k.a. Destination

@return <strong>{ PathWaypoint } A table of PathWaypoints to the destination.
]=]

local function onPathBlocked(NPC: Instance, WaypointIndexNumber: number)
    -- do stuff here.
    if StateMachines[NPC] == nil then return end
    if StateMachines[NPC].State.Name == "Idle" then return end -- not active path.
    StateMachines[NPC].Data.UpdateRequired = true
end

local function onPathUnblocked(NPC: Instance, WaypointIndexNumber: number)
    if StateMachines[NPC] == nil then return end
    if StateMachines[NPC].State.Name == "Idle" then return end -- not active path.
    StateMachines[NPC].Data.UpdateRequired = false
end


local function ConfigurePath(NPC: Instance, Path: Path)
    if Paths[NPC] == nil then 
		Paths[NPC] = {
			AgentInfo = ConfigHandler.GetActiveConfig(NPC).AgentInfo,
			PathObject = Path,
			UsingPathfind = false
		}
	else
		Paths[NPC].PathObject = Path
	end
    Paths[NPC].UsingPathfind = true
    BlockedIndices[NPC] = {}
end

local function TablesAreEqual(Table1: {any}, Table2: {any}): boolean
    if #Table1 ~= #Table2 then return false end
    for i, v in pairs(Table1) do
        local Val1isTbl = typeof(v) == "table"
        local Val2isTbl = Table2[i] == "table"
        if (Val1isTbl and not Val2isTbl) or (Val2isTbl and not Val1isTbl) then return false end
        if Val1isTbl and Val2isTbl then if not TablesAreEqual(v, Table2[i]) then return false end end
        if v ~= Table2[i] then return false end
    end
    return true 
end

local function GetPath(NPC: Instance): Path
    -- Get the !active! config for the NPC
    local Config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)
    
    if Paths[NPC] and Paths[NPC].PathObject and TablesAreEqual(Paths[NPC].AgentInfo, Config.AgentInfo) then return Paths[NPC].PathObject end

    local path = PathfindingService:CreatePath(Config.AgentInfo)
    path.Blocked:Connect(function(wpi: number) onPathBlocked(NPC, wpi) end)
    path.Unblocked:Connect(function(wpi: number) onPathUnblocked(NPC, wpi) end)

    if not Paths[NPC] then
		Paths[NPC] = {} :: any
	end
	
	if Paths[NPC].PathObject then
        debris:AddItem(Paths[NPC].PathObject, 0)
	end
	
    Paths[NPC].AgentInfo = Config.AgentInfo
    Paths[NPC].PathObject = path

    return path
end

-- local LastPathSuccesful: {[Instance]: boolean} = {} 
API.ComputePath = function(NPC: Instance, Target: any): {PathWaypoint}?
    
    -- Get the !active! config for the NPC
    local Config: AIT.Config = ConfigHandler.GetActiveConfig(NPC)

    local TargetActual = Common.GetBasePart(Target, true, NPC)
    if TargetActual == nil then error("Could not convert Target into an Actual Instance") end


    -- Direct move to stuff.
    if DirectMoveTo.CanUseDirectMoveTo(NPC, Target) then
		if Paths[NPC] == nil then Paths[NPC] = {} :: any end
        Paths[NPC].UsingPathfind = false
        return {PathWaypoint.new(DirectMoveTo.GetDirectMoveToPosition(NPC, Target), Enum.PathWaypointAction.Walk, "ForbiddenDirectMoveTo")}
    end

    -- Get the path
    local Path: Path = GetPath(NPC)
    ConfigurePath(NPC, Path)

    local NPCActual = Common.GetBasePart(NPC)
    local TargetActual = Common.GetBasePart(Target, true, NPC)

    Path:ComputeAsync(NPCActual.Position, TargetActual.Position)
    if Path.Status == Enum.PathStatus.Success then
        return Path:GetWaypoints()
    end

    -- Pathing Failed Hook
    task.spawn(Config.Hooks.PathingFailed, NPC, "Path Not Found")

    -- default, no path
    return nil
end


-- TEMP
API.RawCompute = function(Origin: Vector3, Destination: Vector3, AgentInfo: AIT.AgentInfo): {PathWaypoint}?
    local path: Path = PathfindingService:CreatePath(AgentInfo)
    path:ComputeAsync(Origin, Destination)
    if path.Status == Enum.PathStatus.Success then
        return path:GetWaypoints()
    else
        return nil
    end
end

return API