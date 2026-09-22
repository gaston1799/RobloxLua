--[[
    Hit-to-Kill Ratio Probe (Working Version)
    Listens to actual damage on players
    Formula: Level * 2 = damage per hit
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n[Damage Probe] ========== HIT-TO-KILL CALCULATOR ==========\n")

local playerDamageTracking = {}

local function getPlayerLevel(player)
    if player:FindFirstChild("Level") then
        local level = player:FindFirstChild("Level")
        if level:IsA("IntValue") or level:IsA("NumberValue") then
            return level.Value
        end
    end
    if player.Character then
        if player.Character:FindFirstChild("Level") then
            local level = player.Character:FindFirstChild("Level")
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
                local myHealth = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")

                if myHealth then
                    local myLevel = getPlayerLevel(LocalPlayer)
                    local myDamage = calculateDamage(myLevel)

                    -- Calculate ratios
                    local hitsToKillThem = math.ceil(health / myDamage)
                    local hitsToKillUs = math.ceil(myHealth.Health / damage)

                    print(string.format("[%s] Took damage: %.0f | Health: %.0f → %.0f | Hits needed: us→%s | them→%s",
                        player.Name, damageDealt, lastHealth, health, hitsToKillUs, hitsToKillThem))
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
    print(string.format("[+] %s joined", player.Name))
    trackPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
    playerDamageTracking[player] = nil
    print(string.format("[-] %s left\n", player.Name))
end)

print("[Damage Probe] Ready! Listening for damage...\n")
