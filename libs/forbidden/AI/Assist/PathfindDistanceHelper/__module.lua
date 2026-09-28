--[[
This file determines the distance of a pathfind to an object from an NPC

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs
]]--

-- == Forbidden Modules & Architecture == --
local root  = script.Parent.Parent.Parent
local AI    = root.AI
local AIT                   = remoteRequire("libs/forbidden/AI/Types")
local ConfigHandler         = remoteRequire("libs/forbidden/AI/ConfigHandler")
local Common                 = remoteRequire("libs/forbidden/Common")
-- local Defaults              = require(AI.ConfigHandler.Defaults)
local PathfindingProcessor  = remoteRequire("libs/forbidden/AI/PathfindingProcessor")

-- == Initialization == --
local API = {}

local function GetNodes(config: AIT.Config, Node1: BasePart, Node2: BasePart): {PathWaypoint}?
	local waypoints = PathfindingProcessor.RawCompute(Node1.CFrame.Position, Node2.CFrame.Position, config.AgentInfo)
	return waypoints
end

API.GetDistance = function(NPC: Instance, Target: any): number?
    
    local config = ConfigHandler.GetConfig(NPC)
    
    local NPCActual = Common.GetBasePart(NPC)
    local TargetActual = Common.GetBasePart(Target, true, NPC)
    
    local wps = GetNodes(config, NPCActual, TargetActual)
    
    if not wps then return nil end
    local dist = 0
    
    local lastwp = NPCActual
    for i, wp in pairs(wps) do
        dist += (wp.Position - lastwp.Position).Magnitude
        lastwp = wp
    end

    print(dist)

    return dist
end

return API