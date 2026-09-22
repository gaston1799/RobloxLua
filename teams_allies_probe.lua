--[[
    Teams & Allies Detection Probe
    Shows team structure and ally detection logic
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n[Teams Probe] ========== TEAM STRUCTURE ==========")

local function getPackInfo(playerName)
    local teamsFolder = workspace:FindFirstChild("Teams")
    if not teamsFolder then
        print("[Teams Probe] ✗ No Teams folder found")
        return nil, nil
    end

    for _, team in ipairs(teamsFolder:GetChildren()) do
        local teamLeader = nil
        local hasMember = false

        for _, member in ipairs(team:GetChildren()) do
            local ok, value = pcall(function()
                return member.Value
            end)
            if ok then
                local resolvedName = value
                if typeof(value) == "Instance" then
                    resolvedName = value.Name
                end

                if member.Name == "leader" then
                    teamLeader = resolvedName
                end

                if resolvedName == playerName then
                    hasMember = true
                end
            end
        end

        if hasMember then
            return teamLeader, team.Name
        end
    end

    return nil, nil
end

-- Print all teams and members
local teamsFolder = workspace:FindFirstChild("Teams")
if teamsFolder then
    for _, team in ipairs(teamsFolder:GetChildren()) do
        print("\n[Team] " .. team.Name)
        for _, member in ipairs(team:GetChildren()) do
            local ok, value = pcall(function() return member.Value end)
            if ok then
                local display = tostring(value)
                if typeof(value) == "Instance" then
                    display = value.Name .. " (" .. value.ClassName .. ")"
                end
                print("  - " .. member.Name .. ": " .. display)
            end
        end
    end
else
    print("[Teams Probe] ✗ No Teams folder found")
end

-- Check each player's team affiliation
print("\n[Teams Probe] ========== PLAYER AFFILIATIONS ==========")
for _, player in ipairs(Players:GetPlayers()) do
    local leader, teamName = getPackInfo(player.Name)
    local marker = player == LocalPlayer and " (YOU)" or ""
    print(string.format("[%s%s] Leader: %s | Team: %s",
        player.Name, marker, leader or "None", teamName or "None"))
end

-- Auto-update on player changes
print("\n[Teams Probe] Watching for changes...")
Players.PlayerAdded:Connect(function(player)
    local leader, teamName = getPackInfo(player.Name)
    print(string.format("[+] %s joined - Leader: %s | Team: %s", player.Name, leader or "None", teamName or "None"))
end)

Players.PlayerRemoving:Connect(function(player)
    print(string.format("[-] %s left", player.Name))
end)

print("[Teams Probe] Running - teams update automatically\n")
