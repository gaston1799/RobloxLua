--[[
    Level Location Diagnostic
    Finds where player levels are actually stored in this game
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n[Level Probe] ========== SEARCHING FOR LEVEL STORAGE ==========\n")

local function searchInInstance(instance, depth, maxDepth)
    if depth > maxDepth then return end

    -- Check direct children
    for _, child in ipairs(instance:GetChildren()) do
        local name = child.Name:lower()

        -- Look for level-related names
        if name:match("level") or name:match("lvl") or name:match("exp") then
            print(string.format("%s[%s] %s = %s (%s)",
                string.rep("  ", depth), child.ClassName, child.Name,
                (child:IsA("ValueBase") and child.Value) or "?"))
        end

        -- Recurse
        if child:IsA("Instance") then
            searchInInstance(child, depth + 1, maxDepth)
        end
    end
end

-- Check own character
if LocalPlayer.Character then
    print("[YOU] Character structure:")
    searchInInstance(LocalPlayer.Character, 1, 3)
    print("")
end

-- Check each player
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        print(string.format("[%s] Searching structure:", player.Name))

        if player.Character then
            searchInInstance(player.Character, 1, 3)
        else
            print("  (No character)")
        end
        print("")
    end
end

print("[Level Probe] Also checking player object directly:")
if LocalPlayer:FindFirstChild("leaderstats") then
    print("[YOU] Has leaderstats:")
    for _, stat in ipairs(LocalPlayer.leaderstats:GetChildren()) do
        print(string.format("  %s = %s", stat.Name, stat.Value))
    end
else
    print("[YOU] No leaderstats found")
end

print("\n[Level Probe] ========== AUTO-SCAN NEW CHARACTERS ==========\n")

Players.PlayerAdded:Connect(function(player)
    print(string.format("[+] %s joined", player.Name))
    player.CharacterAdded:Connect(function(character)
        print(string.format("  [%s] Character spawned:", player.Name))
        for _, child in ipairs(character:GetChildren()) do
            if child.Name:lower():match("level") or child.Name:lower():match("lvl") then
                print(string.format("    Found: %s = %s", child.Name,
                    (child:IsA("ValueBase") and child.Value) or "?"))
            end
        end
    end)
end)

print("[Level Probe] Running - check console for level locations\n")
