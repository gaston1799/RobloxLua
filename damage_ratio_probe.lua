--[[
    Hit-to-Kill Ratio Probe (FIXED)
    Reads level from leaderstats
    Listens to actual damage via HealthChanged
    Formula: Level * 2 = damage per hit
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n[Damage Probe] ========== HIT-TO-KILL CALCULATOR ==========\n")

local playerDamageTracking = {}

local function getPlayerLevel(player)
    -- Level is stored in leaderstats.Level
    if player:FindFirstChild("leaderstats") then
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats:FindFirstChild("Level") then
            local level = leaderstats:FindFirstChild("Level")
            if level:IsA("IntValue") or level:IsA("NumberValue") then
                return level.Value
            end
        end
    end
    return nil
end

local function calculateDamage(level)
    if not level then return 0 end
    return level * 2
end

-- Track each player's health changes
local function trackPlayer(player)
    if player == LocalPlayer then return end
    if playerDamageTracking[player] then return end

    playerDamageTracking[player] = true

    -- Listen to character spawns
    local function onCharacterAdded(character)
        local humanoid = character:WaitForChild("Humanoid")
        local level = getPlayerLevel(player)
        local damage = calculateDamage(level)

        print(string.format("\n[%s] Spawned | Level: %s | Damage/Hit: %.0f",
            player.Name, level or "?", damage))

        local lastHealth = humanoid.Health

        -- Listen to health changes
        humanoid.HealthChanged:Connect(function(health)
            if health < lastHealth then
                local damageDealt = lastHealth - health
                local myHealthObj = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")

                if myHealthObj then
                    local myLevel = getPlayerLevel(LocalPlayer)
                    local myDamage = calculateDamage(myLevel)
                    local myHealth = myHealthObj.Health

                    if myDamage > 0 then
                        -- Calculate ratios
                        local hitsToKillThem = math.ceil(health / myDamage)
                        local hitsToKillUs = math.ceil(myHealth / damage)

                        print(string.format("[%s] Took damage: %.0f | Health: %.0f → %.0f",
                            player.Name, damageDealt, lastHealth, health))
                        print(string.format("  → Hits to kill them: %.0f | Hits to kill us: %.0f | Ratio: %.2f",
                            hitsToKillThem, hitsToKillUs, hitsToKillThem/hitsToKillUs))
                    end
                end
            end
            lastHealth = health
        end)
    end

    if player.Character then
        onCharacterAdded(player.Character)
    end

    player.CharacterAdded:Connect(onCharacterAdded)
end

-- Track all current players
for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end

-- Track new players
Players.PlayerAdded:Connect(function(player)
    print(string.format("\n[+] %s joined", player.Name))
    trackPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
    playerDamageTracking[player] = nil
    print(string.format("[-] %s left\n", player.Name))
end)

print("[Damage Probe] Ready! Listening for damage...\n")
