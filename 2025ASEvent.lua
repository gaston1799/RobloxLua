-- Proximity Prompt Tracker (client-side)
-- Highlights prompts through walls, shows text+distance, draws a line to a target prompt,
-- and auto-presses selected prompts (for your own place testing).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ====== SETTINGS ======
local MAX_TRACK_DISTANCE = 2000
local AUTO_PRESS = true
local AUTO_PRESS_INTERVAL = 0.15
local MATCH_ONLY = true
local KEYWORDS = { "gift", "deliver", "wrap", "christmas", "xmas", "chrismess", "grab" }

-- Prompt overrides (server-side recommended; this applies them client-side too)
local FORCE_MAX_ACTIVATION_DISTANCE = 2000
local FORCE_REQUIRES_LINE_OF_SIGHT = false
local FORCE_HOLD_DURATION = 0 -- set nil to not override

-- Target prompt: arrow/line locks to closest matching ActionText (set nil to use closest prompt)
local LINE_TARGET_ACTION_TEXT = "Deliver Gift"

-- Also spam ActionText matches (case-insensitive exact)
local SPAM_ACTION_TEXTS = {
	["deliver gift"] = true,
	["grab gift"] = true,
}

-- HUD styling
local HUD_OFFSET = Vector3.new(0, 2.5, 0)
local HUD_MAX_DISTANCE = 10000

-- Line styling
local LINE_COLOR = Color3.fromRGB(90, 200, 255)
local LINE_TRANSPARENCY = 0.35
local LINE_THICKNESS = 0.12

-- ====== INTERNALS ======
local tracked = {}
local arrowGui = nil
local arrowLabel = nil
local linePart = nil

local function now()
	return os.clock()
end

local function norm(s)
	return string.lower(tostring(s or ""))
end

local function applyPromptOverrides(prompt)
	if FORCE_MAX_ACTIVATION_DISTANCE then
		pcall(function()
			prompt.MaxActivationDistance = FORCE_MAX_ACTIVATION_DISTANCE
		end)
	end
	if FORCE_REQUIRES_LINE_OF_SIGHT ~= nil then
		pcall(function()
			prompt.RequiresLineOfSight = FORCE_REQUIRES_LINE_OF_SIGHT
		end)
	end
	if FORCE_HOLD_DURATION ~= nil then
		pcall(function()
			prompt.HoldDuration = FORCE_HOLD_DURATION
		end)
	end
end

local function matchesKeywords(prompt)
	if not MATCH_ONLY then
		return true
	end

	local a = norm(prompt.ActionText)
	local o = norm(prompt.ObjectText)
	local n = norm(prompt.Name)

	for _, k in ipairs(KEYWORDS) do
		k = norm(k)
		if k ~= "" and (string.find(a, k, 1, true) or string.find(o, k, 1, true) or string.find(n, k, 1, true)) then
			return true
		end
	end
	return false
end

local function getAdorneePart(prompt)
	local p = prompt.Parent
	if p == nil then
		return nil
	end

	if p:IsA("BasePart") then
		return p
	end
	if p:IsA("Attachment") then
		local pp = p.Parent
		if pp and pp:IsA("BasePart") then
			return pp
		end
	end

	local cur = p
	for _ = 1, 6 do
		if cur == nil then
			break
		end
		if cur:IsA("BasePart") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function makeHighlight(adornee)
	local h = Instance.new("Highlight")
	h.Name = "PromptTrackerHighlight"
	h.Adornee = adornee
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillTransparency = 0.7
	h.OutlineTransparency = 0.0
	h.Parent = adornee
	return h
end

local function makeBillboard(adornee)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptTrackerHUD"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.MaxDistance = HUD_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffsetWorldSpace = HUD_OFFSET
	gui.Parent = adornee

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.TextScaled = true
	top.Font = Enum.Font.GothamBold
	top.Size = UDim2.new(1, -16, 0.55, 0)
	top.Position = UDim2.fromOffset(8, 4)
	top.TextXAlignment = Enum.TextXAlignment.Left
	top.Text = "ProximityPrompt"
	top.Parent = frame

	local bottom = Instance.new("TextLabel")
	bottom.BackgroundTransparency = 1
	bottom.TextScaled = true
	bottom.Font = Enum.Font.Gotham
	bottom.Size = UDim2.new(1, -16, 0.45, 0)
	bottom.Position = UDim2.new(0, 8, 0.55, 0)
	bottom.TextXAlignment = Enum.TextXAlignment.Left
	bottom.Text = "0.0 studs"
	bottom.Parent = frame

	return gui, top, bottom
end

local function ensureArrow()
	if arrowGui and arrowLabel then
		return
	end

	local pg = player:WaitForChild("PlayerGui")

	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptTrackerArrow"
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100000
	gui.Size = UDim2.fromOffset(120, 80)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	gui.Parent = pg

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = "v"
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = gui

	arrowGui = gui
	arrowLabel = label
end

local function setArrowTarget(part)
	ensureArrow()
	if arrowGui then
		arrowGui.Adornee = part
		arrowGui.Enabled = part ~= nil
	end
end

local function ensureLine()
	if linePart and linePart.Parent then
		return linePart
	end

	local part = Instance.new("Part")
	part.Name = "PromptTrackerLine"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = LINE_COLOR
	part.Transparency = LINE_TRANSPARENCY
	part.Parent = workspace
	linePart = part
	return part
end

local function updateLine(fromPos, toPos)
	if not (fromPos and toPos) then
		if linePart then
			linePart.Parent = nil
		end
		return
	end

	local delta = toPos - fromPos
	local dist = delta.Magnitude
	if dist < 0.05 then
		if linePart then
			linePart.Parent = nil
		end
		return
	end

	local part = ensureLine()
	part.Parent = workspace
	part.Size = Vector3.new(LINE_THICKNESS, LINE_THICKNESS, dist)
	part.CFrame = CFrame.new(fromPos, toPos) * CFrame.new(0, 0, -dist / 2)
end

local function addPrompt(prompt)
	if tracked[prompt] then
		return
	end

	applyPromptOverrides(prompt)
	if not matchesKeywords(prompt) then
		return
	end

	local adornee = getAdorneePart(prompt)
	if not adornee then
		return
	end

	local h = makeHighlight(adornee)
	local gui, top, bottom = makeBillboard(adornee)

	local action = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
	local obj = prompt.ObjectText ~= "" and prompt.ObjectText or adornee.Name
	top.Text = string.format("%s  ->  %s", action, obj)

	tracked[prompt] = {
		adornee = adornee,
		highlight = h,
		gui = gui,
		labelTop = top,
		labelBottom = bottom,
		lastPress = 0,
	}
end

local function removePrompt(prompt)
	local t = tracked[prompt]
	if not t then
		return
	end
	if t.highlight then
		t.highlight:Destroy()
	end
	if t.gui then
		t.gui:Destroy()
	end
	tracked[prompt] = nil
end

local function scanAllPrompts()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			applyPromptOverrides(inst)
			addPrompt(inst)
		end
	end
end

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		applyPromptOverrides(inst)
		addPrompt(inst)
	end
end)

workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		removePrompt(inst)
	end
end)

scanAllPrompts()

local function getRoot()
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function safeFirePrompt(prompt)
	if not prompt.Enabled then
		return false, "prompt disabled"
	end

	local root = getRoot()
	if not root then
		return false, "no HumanoidRootPart"
	end

	local adornee = getAdorneePart(prompt)
	if not adornee then
		return false, "no adornee part"
	end

	local dist = (root.Position - adornee.Position).Magnitude
	local maxDist = prompt.MaxActivationDistance
	if dist > maxDist + 0.1 then
		return false, string.format("out of range (%.1f > %.1f)", dist, maxDist)
	end

	pcall(function()
		fireproximityprompt(prompt)
	end)
	return true, "pressed"
end

RunService.Heartbeat:Connect(function()
	local root = getRoot()
	if not root then
		return
	end

	local rootPos = root.Position
	local targetKey = LINE_TARGET_ACTION_TEXT and norm(LINE_TARGET_ACTION_TEXT) or nil

	local closestPart = nil
	local closestDist = math.huge
	local closestTargetPart = nil
	local closestTargetDist = math.huge

	for prompt, t in pairs(tracked) do
		if prompt.Parent == nil or t.adornee.Parent == nil then
			removePrompt(prompt)
			continue
		end

		local actionText = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
		local objectText = prompt.ObjectText ~= "" and prompt.ObjectText or t.adornee.Name
		t.labelTop.Text = string.format("%s  ->  %s", actionText, objectText)

		local dist = (rootPos - t.adornee.Position).Magnitude
		t.labelBottom.Text = string.format("%.1f studs  |  max %.1f", dist, prompt.MaxActivationDistance)

		local inTrackRange = dist <= MAX_TRACK_DISTANCE
		t.gui.Enabled = inTrackRange
		t.highlight.Enabled = inTrackRange

		if inTrackRange and dist < closestDist then
			closestDist = dist
			closestPart = t.adornee
		end

		if targetKey and inTrackRange and norm(prompt.ActionText) == targetKey and dist < closestTargetDist then
			closestTargetDist = dist
			closestTargetPart = t.adornee
		end

		if AUTO_PRESS and inTrackRange then
			local dt = now() - (t.lastPress or 0)
			if dt >= AUTO_PRESS_INTERVAL then
				t.lastPress = now()

				local a = norm(prompt.ActionText)
				local o = norm(prompt.ObjectText)
				local shouldPress = (SPAM_ACTION_TEXTS[a] == true)
					or (targetKey ~= nil and a == targetKey)
					or (string.find(a, "deliver", 1, true) ~= nil)
					or (string.find(a, "wrap", 1, true) ~= nil)
					or (string.find(o, "gift", 1, true) ~= nil)
					or (string.find(o, "wrap", 1, true) ~= nil)

				if shouldPress and prompt.Enabled then
					safeFirePrompt(prompt)
				end
			end
		end
	end

	local chosenPart = closestTargetPart or closestPart
	local chosenDist = closestTargetPart and closestTargetDist or closestDist
	if chosenPart then
		setArrowTarget(chosenPart)
		if arrowLabel then
			arrowLabel.Text = string.format("v\n%.0f studs", chosenDist)
		end
		updateLine(rootPos, chosenPart.Position)
	else
		setArrowTarget(nil)
		updateLine(nil, nil)
	end
end)



-- ESP only the needed Toy# from the Find&Wrap UI (DeliveredNum)
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local MAX_DISTANCE = 50 -- studs
local UI_NAME = "ChristmasEvent(2025)"
local UI_DELIVERED_PATH = {"MainFrame", "DeliveredNum"} -- TextLabel with "24"

local function getNeededToyNumber()
	local pg = player:WaitForChild("PlayerGui")
	local ui = pg:FindFirstChild(UI_NAME)
	if not ui then return nil end

	local cur = ui
	for _, name in ipairs(UI_DELIVERED_PATH) do
		cur = cur:FindFirstChild(name)
		if not cur then return nil end
	end

	local delivered = tonumber(cur.Text)
	if not delivered then
		return nil
	end

	local total
	do
		local mainFrame = ui:FindFirstChild("MainFrame")
		local totalLabel = mainFrame and mainFrame:FindFirstChild("Total")
		total = totalLabel and tonumber(totalLabel.Text) or nil
	end

	local needed = delivered + 1
	if total and needed > total then
		return nil
	end
	return needed
end

local folder = workspace:FindFirstChild("ToyNumberLabels")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "ToyNumberLabels"
folder.Parent = workspace

local function getAdornee(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function clearESP()
	for _, c in ipairs(folder:GetChildren()) do
		c:Destroy()
	end
end

local function addESPForToy(toyInst, num)
	local adornee = getAdornee(toyInst)
	if not adornee then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = ("ToyLabel_%d"):format(num)
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.MaxDistance = MAX_DISTANCE
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(140, 60)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	bb.Parent = folder

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.Text = ("Toy %d"):format(num)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.Parent = bb

	local hl = Instance.new("Highlight")
	hl.Name = ("ToyHL_%d"):format(num)
	hl.Adornee = toyInst
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.Parent = folder
end

local function findToyByNumber(num)
	for _, inst in ipairs(workspace:GetDescendants()) do
		local n = tonumber(inst.Name:match("^Toy(%d+)$"))
		if n == num then
			return inst
		end
	end
	return nil
end

local function refresh()
	clearESP()

	local needed = getNeededToyNumber()
	if not needed then
		return
	end

	local toy = findToyByNumber(needed)
	if not toy then
		warn(("Toy%d not found in workspace"):format(needed))
		return
	end

	addESPForToy(toy, needed)
end

-- initial + update when UI number changes
refresh()

do
	local pg = player:WaitForChild("PlayerGui")
	local ui = pg:WaitForChild(UI_NAME)
	local delivered = ui:WaitForChild("MainFrame"):WaitForChild("DeliveredNum")
	delivered:GetPropertyChangedSignal("Text"):Connect(refresh)
end
