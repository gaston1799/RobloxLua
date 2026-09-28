--[[
The end-user API for the whole module. 

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- == Services == --


-- == Libraries == --
-- local StateMachine = require(script.Parent.Packages.robloxstatemachine)

-- == Types == --
local AIT = remoteRequire("libs/forbidden/AI/Types")
export type Config = AIT.Config -- AI.Config
export type StopType = AIT.StopType -- AI.StopType
export type RequestPriority = AIT.RequestPriority -- AI.RequestPriority

-- == Forbidden Modules & Architecture == --
local MessageQueue          = remoteRequire("libs/forbidden/AI/MessageQueue")
local PathfindingProcessor  = remoteRequire("libs/forbidden/AI/PathfindingProcessor")
local ConfigHandler         = remoteRequire("libs/forbidden/AI/ConfigHandler")

-- == Forbidden References == --
local DefaultAntilag = script.antilag

local API = {}

API.SmartPathfind = function(NPC: Instance, Target: any, Yields: boolean?, Priority: RequestPriority? | number?)
    Yields = Yields or false
    Priority = Priority or "DefaultStart"
    PathfindingProcessor.InitializeStateMachine(NPC) -- will return if already initialized
    local signal = MessageQueue.SendStartMessage(NPC, Target, Yields, Priority)
    if Yields and signal then
        signal.Event:Wait()
    end
end


--[=[
    Triggers the pathfinding system to stop all related operations with the NPC provided.

    The stop method can be customized with `config.StopType`.

    <strong>If you are recalling immediately and want the AI to <ul>transition smoothly</ul>,
    <ul>do not call</ul> AI.Stop</strong>

    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent
    local someTarget = nil -- your target here.

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    AI.SmartPathfind(myNPC, someTarget)
    config.Visualization.Enabled = true
    config:ApplyNow()
    ```

    @param NPC <strong>Model</strong> The NPC to stop.
]=]
API.Stop = function(NPC: Instance, Yields: boolean?, Priority: RequestPriority? | number?)
    Yields = Yields or false
    Priority = Priority or "DefaultStop"
    local signal = MessageQueue.SendStopMessage(NPC, Yields, Priority)
    if Yields and signal then
        signal.Event:Wait()
    end
end


--[=[
    Returns a config for the NPC given.

    <strong>NOTICE:</strong> All edits made to the config are not read by the system until
    the next call. You can force them to be seen with config:ApplyNow() (i.e. if you had a
    tracking call)

    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent
    local someTarget = nil -- your target here.

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    AI.SmartPathfind(myNPC, someTarget)
    config.Visualization.Enabled = true
    config:ApplyNow()
    ```

    @param NPC <strong>Model</strong> The NPC to obtain the config of.
]=]
API.GetConfig = function(NPC: Instance): Config
    return ConfigHandler.GetConfig(NPC)
end


--[=[
    Prevents stuttering when getting near a player.

    For a more in-depth explanation of why this is needed. See the anti-lag script.
    This is the function the ChaseAI uses by default to insert anti-lag when enabled.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    AI.InsertAntiLag(myNPC) -- Normally, you will not use the other 2 variables. Scroll down for an explanation
    ```

    @param NPC <strong>Model</strong> The model you wish to add the anti-lag to.
    @param UseExtremeCase <strong>boolean?</strong> A loop-based system of the anti-lag, aims to prevent network owner from switching in extreme-cases.
    @param IgnoreHumanoidCheck <strong>boolean?</strong> Whether or not to ignore the check for a humanoid (call validity reasons)
]=]
API.InsertAntiLag = function(NPC: Instance, UseExtremeCase: boolean?, IgnoreHumanoidCheck: boolean?)
    
    -- Validity Checks
    if NPC == nil then error("NPC is nil! Cannot insert the anti-lag script.") end
    if NPC:FindFirstChildOfClass("Humanoid") == nil and not IgnoreHumanoidCheck then error("Cannot find the humanoid in this NPC. Cannot insert the anti-lag script.") end

    -- Default case
    if not UseExtremeCase then
        DefaultAntilag:Clone().Parent = NPC
        DefaultAntilag.Enabled = true
    end

    -- TODO:// implement extreme case here
    -- that being the loop that checks GetNetworkOwnershipAuto every heartbeat
    -- use pcall and SetNetworkOwner(nil) if auto
    if UseExtremeCase then
        DefaultAntilag:Clone().Parent = NPC
        DefaultAntilag.Enabled = true
    end
end


API.InsertAntiLag = function(NPC: Instance, UseExtremeCase: boolean?, IgnoreHumanoidCheck: boolean?)
    warn("Forbidden injected build: AI.InsertAntiLag is not supported.")
    return nil
end

return API

--[[ EX DOCS
https://luals.github.io/wiki/annotations/ ?
-- exs from rblx state machine

--[=[
    Gets the custom data of this state machine object.

    ```lua
    local stateMachine = RobloxStateMachine.new("Start", {state1, state2}, {health = 20})

    print(stateMachine:GetData().health) -- 20
    ```

    @return {[string]: any}
]=]
func here.


]]--