--[[
    Hit-to-Kill Ratio Probe
    Calculates damage per hit based on level
    Shows how many hits to kill players vs how many to kill us

    Formula: Level * 2 = damage per normal attack
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n[Damage Probe] ========== HIT-TO-KILL CALCULATOR ==========\n")

local function getPlayerLevel(player)
    -- Try to find level attribute/value in player or character
    if player:FindFirstChild("Level") then
        local level = player:FindFirstChild("Level")
        if level:IsA("IntValue") or level:IsA("NumberValue") then
            return level.Value
        end
    end

    -- Check in character
    if player.Character then
        if player.Character:FindFirstChild("Level") then
            local level = player.Character:FindFirstChild("Level")
            if level:IsA("IntValue") or level:IsA("NumberValue") then
                return level.Value
            end
        end
    end

    -- Not found
    return nil
end

local function getPlayerHealth(player)
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return humanoid.Health
        end
    end
    return nil
end

local function calculateDamage(level)
    if not level then return 0 end
    return level * 2
end

-- Print own stats
local myLevel = getPlayerLevel(LocalPlayer)
local myHealth = getPlayerHealth(LocalPlayer)
local myDamage = calculateDamage(myLevel)

print(string.format("[YOU] Level: %s | Health: %.0f | Damage/Hit: %.0f",
    myLevel or "?", myHealth or 0, myDamage))
print(string.format("  → Multipliers: x0.1=%.0f | x0.5=%.0f | x1=%.0f | x1.5=%.0f | x2=%.0f",
    myDamage*0.1, myDamage*0.5, myDamage*1, myDamage*1.5, myDamage*2))

-- Calculate for each player
print("\n[Damage Probe] ========== PLAYER COMPARISONS ==========\n")

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        local level = getPlayerLevel(player)
        local health = getPlayerHealth(player)
        local damage = calculateDamage(level)

        if level and health then
            -- Hits to kill them
            local hitsToKillThem = math.ceil(health / myDamage)

            -- Hits to kill us (if they attack)
            local hitsToKillUs = math.ceil(myHealth / damage)

            -- Ratio (lower = we kill faster)
            local ratio = hitsToKillThem / hitsToKillUs

            print(string.format("[%s] Lvl %s | HP: %.0f | Dmg/Hit: %.0f",
                player.Name, level, health, damage))
            print(string.format("  → They need %.0f hits to kill us", hitsToKillUs))
            print(string.format("  → We need %.0f hits to kill them", hitsToKillThem))
            print(string.format("  → Ratio: %.2f (1=equal | <1=we win | >1=they win)", ratio))
            print("")
        else
            print(string.format("[%s] ✗ Could not read level/health\n", player.Name))
        end
    end
end

-- Watch for changes
print("\n[Damage Probe] Watching for level/health changes...\n")

local lastUpdate = tick()
task.spawn(function()
    while true do
        task.wait(2)

        if tick() - lastUpdate > 5 then
            print("\n[Damage Probe] ========== LIVE UPDATE ==========\n")

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local level = getPlayerLevel(player)
                    local health = getPlayerHealth(player)
                    local damage = calculateDamage(level)

                    if level and health then
                        local hitsToKillThem = math.ceil(health / myDamage)
                        local hitsToKillUs = math.ceil(myHealth / damage)

                        print(string.format("[%s] Lvl %s | HP: %.0f | Hits to kill us: %s | Hits kill them: %s",
                            player.Name, level, health, hitsToKillUs, hitsToKillThem))
                    end
                end
            end

            lastUpdate = tick()
        end
    end
end)

print("[Damage Probe] Ready!\n")
