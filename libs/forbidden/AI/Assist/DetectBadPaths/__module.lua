--[[
This file takes in a table of nodes & determines if it a path is possible from those nodes.
Optionally, provide an NPC to check with its config.

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs
]]--

-- == Forbidden Modules & Architecture == --
local root  = script.Parent.Parent.Parent
local AI    = root.AI
local AIT                   = remoteRequire("libs/forbidden/AI/Types")
-- local ConfigHandler         = require(AI.ConfigHandler)
local Defaults              = remoteRequire("libs/forbidden/AI/ConfigHandler/Defaults")
local PathfindingProcessor  = remoteRequire("libs/forbidden/AI/PathfindingProcessor")

-- == Initialization == --
local API = {}

-- == Assisting Functions == --
API.NodeTableExpander = function(nodes: any): {BasePart}
	local final = {}

	local function isAlreadyInTable(part: BasePart)
		for _, v in ipairs(final) do
			if v == part then
				return true
			end
		end
		return false
	end

	local function addBasePartsFrom(instance: Instance)
		if instance:IsA("BasePart") and not isAlreadyInTable(instance) then
			table.insert(final, instance)
		end
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") and not isAlreadyInTable(descendant) then
				table.insert(final, descendant)
			end
		end
	end

	if typeof(nodes) == "Instance" then
		addBasePartsFrom(nodes)
	elseif typeof(nodes) == "table" then
		for _, v in ipairs(nodes) do
			if typeof(v) == "Instance" then
				addBasePartsFrom(v)
			end
		end
	end

	return final
end


API.CheckPath = function(config: AIT.Config, Node1: BasePart, Node2: BasePart): boolean

	local returned = PathfindingProcessor.RawCompute(Node1.CFrame.Position, Node2.CFrame.Position, config.AgentInfo)
	return returned ~= nil
end

-- == API Functions == --
API.DetectBadPaths = function(Nodes: {BasePart}, config: AIT.Config?, CheckBothWays: boolean?): {{From: BasePart, To: BasePart, Omnidirectional: boolean?}}

	if not config then config = Defaults end

	if not config then
		error("no cfg!, this is unusual!")
	end

	local BadPaths = {}
	local NodeStats = {} -- track failures per node

	local function InsertBadPath(node1: BasePart, node2: BasePart)
		table.insert(BadPaths, {From = node1, To = node2, Omnidirectional = false})
		NodeStats[node1] = NodeStats[node1] or {Fails = 0, Total = 0, Name = node1.Name, Ref = node1}
		NodeStats[node2] = NodeStats[node2] or {Fails = 0, Total = 0, Name = node2.Name, Ref = node2}
		NodeStats[node1].Fails += 1
		NodeStats[node2].Fails += 1
	end

	local function CountAttempt(node1: BasePart, node2: BasePart)
		NodeStats[node1] = NodeStats[node1] or {Fails = 0, Total = 0, Name = node1.Name, Ref = node1}
		NodeStats[node2] = NodeStats[node2] or {Fails = 0, Total = 0, Name = node2.Name, Ref = node2}
		NodeStats[node1].Total += 1
		NodeStats[node2].Total += 1
	end

	local tbl = API.NodeTableExpander(Nodes)
	print("The API is running for a group of [" .. tostring(#tbl) .. "] nodes.")

	-- == Progress Timer System ==
	local totalPairs = (#tbl * (#tbl - 1)) / 2
	local processedCount = 0
	local startTime = os.clock()
	local done = false

	task.spawn(function()
		while not done do
			task.wait(5)
			local elapsed = os.clock() - startTime
			local percent = math.clamp(processedCount / totalPairs, 0, 1)
			local estTotal = elapsed / (percent > 0 and percent or 0.0001)
			local remaining = math.max(estTotal - elapsed, 0)
			print(string.format(
				"[DetectBadPaths] Progress: %.1f%% | %d/%d pairs | Elapsed: %.1fs | Est. Remaining: %.1fs",
				percent * 100, processedCount, totalPairs, elapsed, remaining
				))
		end
	end)

	-- == Pairwise Checking ==
	for i = 1, #tbl - 1 do
		for j = i + 1, #tbl do
			local n1, n2 = tbl[i], tbl[j]
			CountAttempt(n1, n2)

			local success1 = API.CheckPath(config, n1, n2)
			if not success1 then InsertBadPath(n1, n2) end

			if CheckBothWays then
				CountAttempt(n2, n1)
				local success2 = API.CheckPath(config, n2, n1)
				if not success2 then
					if not success1 then
						BadPaths[#BadPaths].Omnidirectional = true
					else
						InsertBadPath(n2, n1)
					end
				end
			end

			processedCount += 1
		end
	end

	done = true
	local totalTime = os.clock() - startTime
	print(string.format("[DetectBadPaths] Finished! Processed %d pairs in %.2fs", totalPairs, totalTime))

	-- == Failure Ranking ==
	local Ranked = {}
	for _, stat in pairs(NodeStats) do
		local failRate = (stat.Fails / stat.Total) * 100
		table.insert(Ranked, {Name = stat.Name, Fails = stat.Fails, Total = stat.Total, Rate = failRate, Ref = stat.Ref})
	end

	table.sort(Ranked, function(a, b)
		return a.Rate > b.Rate
	end)

	print("\n===== FAILURE RANKING =====")
	for i, data in ipairs(Ranked) do
		print(string.format("%2d. %-20s | %.1f%% failed (%d/%d)", i, data.Name, data.Rate, data.Fails, data.Total))
	end
	print("============================\n")

	-- == Clickable Table Print ==
	local orderedParts = {}
	for _, data in ipairs(Ranked) do
		table.insert(orderedParts, data.Ref)
	end
	print("Failure ranking (clickable):", orderedParts)

	return BadPaths
end

return API