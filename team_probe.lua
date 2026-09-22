--[[
    Team/Clan Structure Probe
    Inspects how teams work in Animal Simulator
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 60))
print("TEAM/CLAN STRUCTURE PROBE")
print(string.rep("=", 60) .. "\n")

-- Check Teams service
local TeamsService = game:GetService("Teams")
print("[Teams Service]")
print("  Teams count:", #TeamsService:GetTeams())
for _, team in ipairs(TeamsService:GetTeams()) do
    print("  - Team:", team.Name, "| Color:", team.TeamColor, "| Players:", #team:GetPlayers())
end

-- Check Workspace for teams/clans
print("\n[Workspace Structure]")
if workspace:FindFirstChild("Teams") then
    print("  ✓ Found 'Teams' folder in workspace")
    local teamsFolder = workspace.Teams
    print("    Team folders:", #teamsFolder:GetChildren())
    for _, teamFolder in ipairs(teamsFolder:GetChildren()) do
        print("\n    - Team: " .. teamFolder.Name .. " | Type: " .. teamFolder.ClassName)
        if teamFolder:IsA("Folder") then
            local members = teamFolder:GetChildren()
            print("      Members: " .. #members)
            for _, member in ipairs(members) do
                print("        • " .. member.Name .. " (" .. member.ClassName .. ")")
            end
        end
    end
else
    print("  ✗ No 'Teams' folder in workspace")
end

-- Check for clan-related objects
print("\n[Workspace Clans/Groups]")
for _, obj in ipairs(workspace:GetChildren()) do
    if obj.Name:lower():find("clan") or obj.Name:lower():find("group") or obj.Name:lower():find("team") then
        print("  Found:", obj.Name, "| Type:", obj.ClassName, "| Children:", #obj:GetChildren())
    end
end

-- Check local player's team
print("\n[Local Player]")
print("  Name:", LocalPlayer.Name)
print("  Team:", LocalPlayer.Team and LocalPlayer.Team.Name or "None")
print("  UserId:", LocalPlayer.UserId)

-- Check for clan/group detection
print("\n[Clan/Group Detection]")
local char = LocalPlayer.Character
if char then
    -- Check for clan tags or labels
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("TextLabel") or part:IsA("BillboardGui") then
            if part.Name:lower():find("clan") or part.Name:lower():find("tag") or part.Name:lower():find("group") then
                print("  Found:", part.Name, "=", part:IsA("TextLabel") and part.Text or "BillboardGui")
            end
        end
    end

    -- Check humanoid for team tags
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        print("  Humanoid.Team:", humanoid.Team and humanoid.Team.Name or "None")
    end
end

-- Check all players and their teams
print("\n[All Players]")
for _, player in ipairs(Players:GetPlayers()) do
    local teamName = player.Team and player.Team.Name or "No Team"
    print("  -", player.Name, "| Team:", teamName)

    -- Check if they're an ally
    if player.Team == LocalPlayer.Team and player ~= LocalPlayer then
        print("    ✓ ALLY (same team)")
    elseif player.Team ~= LocalPlayer.Team then
        print("    ✗ ENEMY (different team)")
    end
end

-- Check for custom team detection methods
print("\n[Custom Detection Methods]")
local function checkAlly(player)
    if not player then return false end

    -- Method 1: Team comparison
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
        return true
    end

    -- Method 2: Check character for clan tag
    if player.Character then
        local tag = player.Character:FindFirstChild("ClanTag") or player.Character:FindFirstChild("TeamTag")
        if tag then
            print("  Found tag on", player.Name, ":", tag.Name)
        end
    end

    return false
end

print("  Checking ally detection...")
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        local isAlly = checkAlly(player)
        print("    ", player.Name, "->", isAlly and "ALLY" or "ENEMY")
    end
end

print("\n" .. string.rep("=", 60))
print("PROBE COMPLETE")
print(string.rep("=", 60) .. "\n")

print("[Instructions] Run this while in-game to inspect team structure")
print("[Next] Share results so we can plan AutoZone logic\n")
