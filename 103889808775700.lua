-- LocalScript (client-sided)
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- ✅ your keyword lists
local WordInThenAutoActivate = { "Chest", "chest" }
local WordInThenDontActivate = { "old", "Old" }

-- helper fn to check if a string contains any word
local function containsWord(str, list)
	str = string.lower(str or "")
	for _, word in ipairs(list) do
		if string.find(str, string.lower(word)) then
			return true
		end
	end
	return false
end

-- 🔔 when any prompt is shown
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local objectText = prompt.ObjectText or ""
	local actionText = prompt.ActionText or ""
	local combined = objectText .. " " .. actionText

	print("Prompt Detected!")
	print("Object Text:", objectText)
	print("Action Text:", actionText)
	print("Full Message: Press", prompt.KeyboardKeyCode.Name, "to", actionText)

	-- 🚫 skip unwanted words
	if containsWord(combined, WordInThenDontActivate) then
		print("[SKIP] Blocked word found:", combined)
		return
	end

	-- ⚡ auto-activate approved prompts
	if containsWord(combined, WordInThenAutoActivate) then
		print("[AUTO] Activating:", combined)
		pcall(function()
			fireproximityprompt(prompt)
		end)
	end
end)

-- 💤 when hidden
ProximityPromptService.PromptHidden:Connect(function(prompt)
	print("Prompt hidden:", prompt.Name)
end)

-- ✅ when actually triggered
ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWhoTriggered)
	if playerWhoTriggered == player then
		print("You activated:", prompt.Name)
	end
end)

print("Active Scripter 🧠")
