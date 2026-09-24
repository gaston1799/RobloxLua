--[[
    Animal Simulator - Advanced PVP Bot v2
    Integrated UI + State Machine Bot
    PlaceID: 5712833750
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ===== INTENT SERVER SETUP =====
local INTENT_SERVER = "http://127.0.0.1:3636/intent"

local function sendIntent(key, state)
    local payload = {key = key, state = state}
    local json = game:GetService("HttpService"):JSONEncode(payload)
    local ok, err = pcall(function()
        game:HttpPost(INTENT_SERVER, json)
    end)
    if not ok then
        print("[Intent Server] ERROR: " .. tostring(err))
    else
        print("[Intent Server] Sent: " .. key .. " = " .. state)
    end
end

-- ===== ADVANCED PVP BOT - EMBEDDED =====

local BotState = {
    enabled = false,
    current_state = "idle",
    target = nil,
    target_last_y = nil,
    last_q_time = 0,
    last_fireball_time = 0,
    last_eat_time = 0,
    last_t_spam_time = 0,
    movement_keys = {w=false, a=false, s=false, d=false},
    auto_eat_enabled = false,
    auto_fireball_enabled = false,
    follow_ally_enabled = false,
    autozone_enabled = false,
    closest_ally = nil,
    target_enemy_clan = "Any Enemy",
}

-- Auto-detect player's team/clan
local function autoDetectClan()
    if workspace:FindFirstChild("Teams") then
        for _, teamFolder in ipairs(workspace.Teams:GetChildren()) do
            if teamFolder:FindFirstChild(LocalPlayer.Name) then
                return teamFolder.Name
            end
        end
    end
    return "enter clan name here"
end

local Config = {
    melee_range = 6,
    combat_radius = 25,
    q_cooldown = 0.65,
    fireball_cooldown = 1.4,
    eat_cooldown = 2.0,
    eat_hp_threshold = 0.8,
    approach_speed = "normal",
    t_spam_interval = 0.125,
    autozone_ally_follow_dist = 15,
    autozone_engage_range = 30,
    follow_ally_dist = 20,
    ally_clan_name = autoDetectClan(),
}

-- ===== AUTO PVP STATE =====

local AutoPVPState = {
    enabled = false,
    auto_reengage = false,
    last_attacker = nil,
    last_damage_time = 0,
    damage_threshold = 0.5,
}

-- ===== HUD STATE =====

local HUDState = {
    enabled = false,
    overhead_entries = {},
    overhead_connections = {},
}

local function getPlayerLevel(player)
    if not player then return nil end
    local stats = player:FindFirstChild("leaderstats")
    if not stats then return nil end
    local levelValue = stats:FindFirstChild("Level") or stats:FindFirstChild("level")
    if not levelValue then return nil end
    return tonumber(levelValue.Value)
end

local function estimatePlayerDamage(player)
    if not player then return nil end
    local level = getPlayerLevel(player)
    if level then
        return (level * 2) + 10
    end
    return nil
end

local function getCharacterHealth(player)
    local character = player and player.Character
    if not character then return nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local current = humanoid.Health
        local max = humanoid.MaxHealth
        if max <= 0 then max = current end
        return current, math.max(current, max)
    end
    return nil, nil
end

local function computeHitCount(health, damage)
    if not health or health <= 0 or not damage or damage <= 0 then
        return "?"
    end
    local hits = math.ceil(health / damage)
    if hits < 1 then hits = 1 end
    return tostring(hits)
end

local function computeOverheadStats(targetPlayer)
    local localPlayer = LocalPlayer
    if not localPlayer or not targetPlayer then
        return "?", "?", "?", 0
    end

    local localHealth, localMaxHealth = getCharacterHealth(localPlayer)
    local enemyHealth, enemyMaxHealth = getCharacterHealth(targetPlayer)
    local enemyDamage = estimatePlayerDamage(targetPlayer)
    local localDamage = estimatePlayerDamage(localPlayer)

    local hitsToKillEnemy = computeHitCount(enemyMaxHealth or enemyHealth, localDamage)
    local hitsToKillYou = computeHitCount(localMaxHealth or localHealth, enemyDamage)
    local hpValue = enemyHealth or enemyMaxHealth
    local hpText = hpValue and string.format("%.0f", hpValue) or "?"
    local ratio = 0
    if enemyHealth and enemyMaxHealth and enemyMaxHealth > 0 then
        ratio = math.clamp(enemyHealth / enemyMaxHealth, 0, 1)
    end

    return hitsToKillEnemy, hitsToKillYou, hpText, ratio
end

local function createGuiForPlayer(player, character)
    if player == LocalPlayer then return end
    if not character then return end

    local adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not adornee then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "HitToKillHUD"
    billboard.Size = UDim2.new(0, 170, 0, 70)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 200
    billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    billboard.Adornee = adornee
    billboard.Parent = adornee

    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.Parent = billboard

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "Info"
    infoLabel.BackgroundTransparency = 1
    infoLabel.Size = UDim2.new(1, -10, 0, 32)
    infoLabel.Position = UDim2.new(0, 5, 0, 5)
    infoLabel.Font = Enum.Font.GothamSemibold
    infoLabel.TextSize = 14
    infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoLabel.TextStrokeTransparency = 0.6
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextWrapped = true
    infoLabel.Text = "Hits (You->Them): ?\nHits (Them->You): ?"
    infoLabel.Parent = frame

    local barBackground = Instance.new("Frame")
    barBackground.Name = "HPBar"
    barBackground.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    barBackground.BorderColor3 = Color3.fromRGB(10, 10, 10)
    barBackground.BorderSizePixel = 0
    barBackground.Size = UDim2.new(1, -10, 0, 10)
    barBackground.Position = UDim2.new(0, 5, 0, 44)
    barBackground.Parent = frame

    local barFill = Instance.new("Frame")
    barFill.Name = "Fill"
    barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    barFill.BorderSizePixel = 0
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.Parent = barBackground

    local hpLabel = Instance.new("TextLabel")
    hpLabel.Name = "HPLabel"
    hpLabel.BackgroundTransparency = 1
    hpLabel.Size = UDim2.new(1, -10, 0, 16)
    hpLabel.Position = UDim2.new(0, 5, 0, 56)
    hpLabel.Font = Enum.Font.Gotham
    hpLabel.TextSize = 12
    hpLabel.TextColor3 = Color3.fromRGB(215, 215, 215)
    hpLabel.TextStrokeTransparency = 0.8
    hpLabel.TextXAlignment = Enum.TextXAlignment.Left
    hpLabel.Text = "HP: ?"
    hpLabel.Parent = frame

    HUDState.overhead_entries[player] = {
        gui = billboard,
        info = infoLabel,
        hpLabel = hpLabel,
        barFill = barFill
    }
end

local function destroyPlayerGui(player)
    local entry = HUDState.overhead_entries[player]
    if entry then
        if entry.gui then
            entry.gui:Destroy()
        end
        HUDState.overhead_entries[player] = nil
    end
end

local function stopTrackingPlayer(player)
    destroyPlayerGui(player)
    local connections = HUDState.overhead_connections[player]
    if connections then
        for _, connection in pairs(connections) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        HUDState.overhead_connections[player] = nil
    end
end

local function trackPlayer(player)
    if player == LocalPlayer then return end

    stopTrackingPlayer(player)

    local connections = {}
    connections.characterAdded = player.CharacterAdded:Connect(function(character)
        task.spawn(function()
            createGuiForPlayer(player, character)
        end)
    end)
    connections.characterRemoving = player.CharacterRemoving:Connect(function()
        destroyPlayerGui(player)
    end)
    HUDState.overhead_connections[player] = connections

    if player.Character then
        task.spawn(function()
            createGuiForPlayer(player, player.Character)
        end)
    end
end

local hudUpdateConnection
local function enableHUD()
    if HUDState.enabled then return end
    HUDState.enabled = true

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        trackPlayer(otherPlayer)
    end

    Players.PlayerAdded:Connect(function(player)
        if HUDState.enabled then
            task.spawn(function()
                trackPlayer(player)
            end)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        stopTrackingPlayer(player)
    end)

    if not hudUpdateConnection then
        hudUpdateConnection = RunService.Heartbeat:Connect(function()
            if not HUDState.enabled then return end

            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

            local toCleanup = {}
            for player, entry in pairs(HUDState.overhead_entries) do
                if not player.Parent then
                    table.insert(toCleanup, player)
                elseif not entry.gui or not entry.gui.Parent then
                    table.insert(toCleanup, player)
                else
                    local isVisible = true
                    if localRoot then
                        local enemyRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if enemyRoot then
                            local distance = (enemyRoot.Position - localRoot.Position).Magnitude
                            isVisible = distance <= 150
                        end
                    end

                    entry.gui.Enabled = isVisible
                    if isVisible then
                        local hitsToKillEnemy, hitsToKillYou, hpText, ratio = computeOverheadStats(player)
                        entry.info.Text = string.format("Hits (You->Them): %s\nHits (Them->You): %s", hitsToKillEnemy, hitsToKillYou)
                        entry.hpLabel.Text = "HP: " .. hpText
                        entry.barFill.Size = UDim2.new(ratio, 0, 1, 0)

                        if ratio > 0.6 then
                            entry.barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
                        elseif ratio > 0.3 then
                            entry.barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 70)
                        else
                            entry.barFill.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
                        end

                        -- Color-code info text by hit-to-kill ratio
                        local hitRatio = tonumber(hitsToKillEnemy) and tonumber(hitsToKillYou) and (tonumber(hitsToKillEnemy) / tonumber(hitsToKillYou)) or 0
                        if hitRatio < 1.0 then
                            entry.info.TextColor3 = Color3.fromRGB(80, 200, 120) -- GREEN: Easy to kill (we need fewer hits)
                        else
                            entry.info.TextColor3 = Color3.fromRGB(240, 80, 80) -- RED: Harder to kill (we need more hits)
                        end
                    end
                end
            end

            for _, player in ipairs(toCleanup) do
                stopTrackingPlayer(player)
            end
        end)
    end

    print("[HUD] Enabled")
end

local function disableHUD()
    if not HUDState.enabled then return end
    HUDState.enabled = false

    for player, _ in pairs(HUDState.overhead_entries) do
        stopTrackingPlayer(player)
    end

    if hudUpdateConnection then
        hudUpdateConnection:Disconnect()
        hudUpdateConnection = nil
    end

    print("[HUD] Disabled")
end

local lastKeyRefreshTime = 0
local KEY_REFRESH_INTERVAL = 1.5  -- Resend held keys every 1.5s (before 2.1s watchdog)

local function pressKey(key)
    if not BotState.movement_keys[key] then
        BotState.movement_keys[key] = true
        sendIntent(key, "down")
    end
end

local function releaseKey(key)
    if BotState.movement_keys[key] then
        BotState.movement_keys[key] = false
        sendIntent(key, "up")
    end
end

local function refreshHeldKeys()
    local now = tick()
    if now - lastKeyRefreshTime < KEY_REFRESH_INTERVAL then
        return
    end
    lastKeyRefreshTime = now

    for key, held in pairs(BotState.movement_keys) do
        if held then
            sendIntent(key, "down")
        end
    end
end

local function releaseAllKeys()
    for key in pairs(BotState.movement_keys) do
        releaseKey(key)
    end
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function getDirection(from, to)
    return (to - from).Unit
end

local function getCameraDirection()
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
end

local function aimCameraAtTarget(targetRoot)
    if not targetRoot then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- Aim camera at target position
    local dirToTarget = (targetRoot.Position - root.Position).Unit
    local distance = (targetRoot.Position - root.Position).Magnitude
    local behindDist = math.max(5, distance * 0.3)
    local cameraPos = root.Position - (dirToTarget * behindDist) + Vector3.new(0, 1, 0)

    camera.CFrame = CFrame.new(cameraPos, targetRoot.Position)
end

local function toggleShiftLock(enabled)
    if enabled then
        print("[Bot] Enabling shift lock...")
        sendIntent("shift", "down")
        task.wait(0.1)
        sendIntent("shift", "up")
    else
        print("[Bot] Disabling shift lock...")
        sendIntent("shift", "down")
        task.wait(0.1)
        sendIntent("shift", "up")
    end
end

local function moveTowardWithInterception(targetRoot)
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- Handle both Vector3 (old style) and root part (new style with velocity prediction)
    local targetPos = targetRoot
    if typeof(targetRoot) == "Instance" then
        -- Predict target position based on velocity (0.2s prediction)
        local velocity = targetRoot.AssemblyLinearVelocity
        targetPos = targetRoot.Position + (velocity * 0.2)
    end

    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    local camRight = camDir:Cross(Vector3.new(0, 1, 0)).Unit
    local camForward = camDir

    local forwardDot = dirToTarget:Dot(camForward)
    local rightDot = dirToTarget:Dot(camRight)

    local input = {w=false, a=false, s=false, d=false}

    if forwardDot > 0.2 then
        input.w = true
    elseif forwardDot < -0.2 then
        input.s = true
    end

    if rightDot > 0.1 then
        input.d = true
    elseif rightDot < -0.1 then
        input.a = true
    end

    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

local function strafeBaitDodge(targetRoot)
    -- Stay at 10-15 studs and strafe left-right to dodge fireballs
    if not targetRoot then return end

    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetRoot.Position)
    local dirToTarget = getDirection(root.Position, targetRoot.Position)
    local camDir = getCameraDirection()

    local camRight = camDir:Cross(Vector3.new(0, 1, 0)).Unit
    local camForward = camDir

    local input = {w=false, a=false, s=false, d=false}

    -- Maintain 10-15 stud range
    local baitMinDist = 10
    local baitMaxDist = 15

    if dist < baitMinDist then
        -- Too close, back up
        input.s = true
    elseif dist > baitMaxDist then
        -- Too far, move closer
        local forwardDot = dirToTarget:Dot(camForward)
        if forwardDot > 0.2 then
            input.w = true
        elseif forwardDot < -0.2 then
            input.s = true
        end
    end

    -- Continuous strafing to dodge (sine wave pattern)
    local strafeLeft = math.sin(tick() * 3) > 0
    if strafeLeft then
        input.a = true
    else
        input.d = true
    end

    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

local function fireballBait(targetPos)
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetPos)
    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    local camRight = camDir:Cross(Vector3.new(0, 1, 0)).Unit
    local camForward = camDir

    local rightDot = dirToTarget:Dot(camRight)

    local input = {w=false, a=false, s=false, d=false}

    if dist < Config.combat_radius * 0.6 then
        input.s = true
    elseif dist > Config.combat_radius * 0.9 then
        local forwardDot = dirToTarget:Dot(camForward)
        if forwardDot > 0.1 then
            input.w = true
        end
    end

    local strafeLeft = math.sin(tick() * 3) > 0
    if strafeLeft then
        input.a = true
    else
        input.d = true
    end

    for key, shouldPress in pairs(input) do
        if shouldPress then
            pressKey(key)
        else
            releaseKey(key)
        end
    end
end

local function attackWithQ()
    sendIntent("q", "down")
    task.wait(0.05)
    sendIntent("q", "up")
    BotState.last_q_time = tick()
end

local function fireballAttack()
    sendIntent("e", "down")
    task.wait(0.1)
    sendIntent("e", "up")
    BotState.last_fireball_time = tick()
end

local function doubleHit()
    fireballAttack()
    task.wait(0.05)
    attackWithQ()
end

-- ===== AUTO EAT & FIREBALL =====

local function equipItem(itemName)
    local char = LocalPlayer.Character
    if not char then return false end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end

    local item = backpack:FindFirstChild(itemName)
    if not item then return false end

    -- Equip by moving to character
    item.Parent = char
    return true
end

local function useFood()
    if not BotState.auto_eat_enabled then return end

    local char = LocalPlayer.Character
    if not char then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- Check if HP is below threshold and cooldown ready
    local hpPercent = humanoid.Health / humanoid.MaxHealth
    local eatReady = (tick() - BotState.last_eat_time) > Config.eat_cooldown

    if hpPercent < Config.eat_hp_threshold and eatReady then
        if equipItem("Food") then
            print("[Auto Eat] Equipped food (HP: " .. string.format("%.0f%%", hpPercent * 100) .. ")")
            task.wait(0.1)
            sendIntent("f", "down")
            task.wait(0.05)
            sendIntent("f", "up")
            BotState.last_eat_time = tick()

            -- Re-equip fireball after eating
            task.wait(0.2)
            if equipItem("Fireball") then
                print("[Auto Fireball] Re-equipped fireball")
            end
        end
    end
end

local function ensureFireballEquipped()
    if not BotState.auto_fireball_enabled then return end

    local char = LocalPlayer.Character
    if not char then return end

    -- Check if fireball is already equipped
    if char:FindFirstChild("Fireball") then
        return
    end

    -- Equip fireball
    if equipItem("Fireball") then
        print("[Auto Fireball] Equipped fireball")
    end
end

-- ===== T SPAM (Stance animation) =====

local function spamT()
    local now = tick()
    if now - BotState.last_t_spam_time < Config.t_spam_interval then return end
    BotState.last_t_spam_time = now
    sendIntent("t", "down")
    task.wait(0.02)
    sendIntent("t", "up")
end

-- ===== ALLY DETECTION & AUTOZONE =====

local function findClosestAlly()
    local char = LocalPlayer.Character
    if not char then return nil end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local closestAlly = nil
    local closestDist = math.huge

    -- Find closest ally (same clan as us)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            -- Check if same clan
            local backpack = LocalPlayer:FindFirstChild("Backpack")
            if backpack then
                local teamFolder = workspace.Teams and workspace.Teams:FindFirstChild(Config.ally_clan_name)
                if teamFolder then
                    local isAlly = teamFolder:FindFirstChild(player.Name) ~= nil
                    if isAlly then
                        local allyRoot = player.Character:FindFirstChild("HumanoidRootPart")
                        if allyRoot then
                            local dist = getDistance(root.Position, allyRoot.Position)
                            if dist < closestDist then
                                closestDist = dist
                                closestAlly = player
                            end
                        end
                    end
                end
            end
        end
    end

    return closestAlly
end

local function updateAutozoneTarget()
    if not BotState.autozone_enabled then return end
    if BotState.target then return end  -- Already have target from manual/PVP

    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- Find closest ally
    local ally = findClosestAlly()
    if not ally or not ally.Character then return end

    local allyRoot = ally.Character:FindFirstChild("HumanoidRootPart")
    if not allyRoot then return end

    -- Check if ally is in safe zone
    if isInsideSafeZone(allyRoot.Position) then return end

    -- Find closest enemy within engage range of ally
    local closestEnemy = nil
    local closestEnemyDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local enemyRoot = player.Character:FindFirstChild("HumanoidRootPart")
            local enemyHumanoid = player.Character:FindFirstChildOfClass("Humanoid")

            if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
                -- Check if enemy matches target clan (or "Any Enemy")
                local isTargetClan = false
                if BotState.target_enemy_clan == "Any Enemy" then
                    isTargetClan = true
                else
                    local teamFolder = workspace.Teams and workspace.Teams:FindFirstChild(BotState.target_enemy_clan)
                    if teamFolder then
                        isTargetClan = teamFolder:FindFirstChild(player.Name) ~= nil
                    end
                end

                if isTargetClan then
                    -- Check if enemy is outside safe zone
                    if not isInsideSafeZone(enemyRoot.Position) then
                        -- Check if within engage range of ally
                        local distToAlly = getDistance(allyRoot.Position, enemyRoot.Position)
                        if distToAlly <= Config.autozone_engage_range then
                            local distToUs = getDistance(root.Position, enemyRoot.Position)
                            if distToUs < closestEnemyDist then
                                closestEnemyDist = distToUs
                                closestEnemy = player
                            end
                        end
                    end
                end
            end
        end
    end

    if closestEnemy then
        if not isWinnableBattle(closestEnemy) then
            print("[AutoZone] " .. closestEnemy.Name .. " is unkillable (bad ratio), skipping")
        elseif not isInAutoZone(closestEnemy) then
            print("[AutoZone] " .. closestEnemy.Name .. " is in safe zone, skipping")
        else
            _G.AdvancedPVPBot.setTarget(closestEnemy)
            print("[AutoZone] ✓ Engaging enemy near ally:", closestEnemy.Name)
        end
    end
end

-- ===== AUTO PVP DAMAGE DETECTION =====

local function isWinnableBattle(player)
    if not player or not player.Character then return false end

    local ourHumanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not ourHumanoid then return false end

    local theirHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not theirHumanoid or theirHumanoid.Health <= 0 then return false end

    -- Calculate hit-to-kill ratio
    local ourLevel = getPlayerLevel(LocalPlayer) or 1
    local theirLevel = getPlayerLevel(player) or 1

    local ourDamage = (ourLevel * 2) + 10
    local theirDamage = (theirLevel * 2) + 10

    local ourMaxHealth = ourHumanoid.MaxHealth
    local theirMaxHealth = theirHumanoid.MaxHealth

    local hitsToKillThem = math.ceil(theirMaxHealth / ourDamage)
    local hitsToKillUs = math.ceil(ourMaxHealth / theirDamage)

    -- Get damage multiplier slider value (0.1 to 2.0)
    local multiplier = tonumber(_G.DamageMultiplier) or 1.0

    -- Calculate ratio: hitsToKillThem / hitsToKillUs
    -- Ratio <= multiplier means target is within acceptable range (lower is better for us)
    local ratio = hitsToKillThem / hitsToKillUs
    local acceptable = ratio <= multiplier

    if acceptable then
        print("[Auto PVP] " .. player.Name .. " | Ratio: " .. string.format("%.2f", ratio) .. " >= " .. multiplier .. " | ACCEPTED")
    else
        print("[Auto PVP] " .. player.Name .. " | Ratio: " .. string.format("%.2f", ratio) .. " < " .. multiplier .. " | REJECTED")
    end

    return acceptable
end

-- ===== HARDCODED SAFE ZONE (Recorded: 4 corners) =====
local SAFE_ZONE_CORNERS = {
    corner1 = {x = -113.61, z = 401.64},
    corner2 = {x = -45.67, z = 588.11},
    corner3 = {x = -276.38, z = 672.11},
    corner4 = {x = -345.77, z = 486.77},
}

local function isInsideSafeZone(position)
    -- Check if position is within safe zone rectangle (X,Z only)
    local minX = math.min(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local maxX = math.max(SAFE_ZONE_CORNERS.corner1.x, SAFE_ZONE_CORNERS.corner2.x, SAFE_ZONE_CORNERS.corner3.x, SAFE_ZONE_CORNERS.corner4.x)
    local minZ = math.min(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)
    local maxZ = math.max(SAFE_ZONE_CORNERS.corner1.z, SAFE_ZONE_CORNERS.corner2.z, SAFE_ZONE_CORNERS.corner3.z, SAFE_ZONE_CORNERS.corner4.z)

    return position.X >= minX and position.X <= maxX and
           position.Z >= minZ and position.Z <= maxZ
end

local function isInAutoZone(player)
    if not player or not player.Character then return false end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    -- Check if outside safe zone (returns true if OUTSIDE)
    return not isInsideSafeZone(root.Position)
end

-- ===== SAFE ZONE VISUALIZER =====
local safeZoneVisualizerFolder = nil

local function createSafeZoneVisualizer()
    -- Cleanup if already exists
    if safeZoneVisualizerFolder then
        safeZoneVisualizerFolder:Destroy()
        safeZoneVisualizerFolder = nil
    end

    safeZoneVisualizerFolder = Instance.new("Folder")
    safeZoneVisualizerFolder.Name = "SafeZoneVisualizer"
    safeZoneVisualizerFolder.Parent = workspace

    local corners = {
        SAFE_ZONE_CORNERS.corner1,
        SAFE_ZONE_CORNERS.corner2,
        SAFE_ZONE_CORNERS.corner3,
        SAFE_ZONE_CORNERS.corner4,
    }

    -- Calculate bounds
    local minX = math.min(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local maxX = math.max(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local minZ = math.min(corners[1].z, corners[2].z, corners[3].z, corners[4].z)
    local maxZ = math.max(corners[1].z, corners[2].z, corners[3].z, corners[4].z)

    local centerX = (minX + maxX) / 2
    local centerZ = (minZ + maxZ) / 2
    local centerY = 200

    local sizeX = maxX - minX
    local sizeZ = maxZ - minZ
    local sizeY = 400

    -- Create semi-transparent box
    local box = Instance.new("Part")
    box.Name = "SafeZoneBox"
    box.Shape = Enum.PartType.Block
    box.Size = Vector3.new(sizeX, sizeY, sizeZ)
    box.Color = Color3.fromRGB(0, 255, 0)
    box.Material = Enum.Material.Neon
    box.Transparency = 0.6
    box.CanCollide = false
    box.CFrame = CFrame.new(centerX, centerY, centerZ)
    box.Parent = safeZoneVisualizerFolder

    -- Add red corner markers
    for i, corner in ipairs(corners) do
        local marker = Instance.new("Part")
        marker.Name = "Corner" .. i
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(4, 4, 4)
        marker.Color = Color3.fromRGB(255, 0, 0)
        marker.Material = Enum.Material.Neon
        marker.CanCollide = false
        marker.CFrame = CFrame.new(corner.x, centerY, corner.z)
        marker.Parent = safeZoneVisualizerFolder
    end

    print("[SafeZone Visualizer] Semi-transparent green box rendered")
end

local function destroySafeZoneVisualizer()
    if safeZoneVisualizerFolder then
        safeZoneVisualizerFolder:Destroy()
        safeZoneVisualizerFolder = nil
        print("[SafeZone Visualizer] Destroyed")
    end
end

local function findAttackerByDamage(damageTaken)
    if not damageTaken or damageTaken <= 0 then
        print("[Auto PVP] Invalid damage: " .. tostring(damageTaken))
        return nil
    end

    local localCharacter = LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        print("[Auto PVP] No local root")
        return nil
    end

    local bestPlayer = nil
    local bestScore = math.huge
    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")

            if humanoidInstance and humanoidInstance.Health > 0 and root then
                local level = getPlayerLevel(player) or 1
                local estimatedDamage = (level * 2) + 10
                local diff = math.abs(estimatedDamage - damageTaken)
                local tolerance = math.max(30, estimatedDamage * 0.5)
                local distance = (root.Position - localRoot.Position).Magnitude
                local score = diff + (distance * 0.02)

                print("[Auto PVP] Checking " .. player.Name .. " | Level: " .. level .. " | Est DMG: " .. estimatedDamage .. " | Actual: " .. damageTaken .. " | Diff: " .. diff .. " | Tolerance: " .. tolerance)

                -- Only match if damage aligns
                if diff <= tolerance then
                    if score < bestScore then
                        bestScore = score
                        bestPlayer = player
                        print("[Auto PVP] ✓ Match found!")
                    end
                end
            end
        end
    end

    if bestPlayer then
        print("[Auto PVP] ✓ Selected: " .. bestPlayer.Name)
    else
        print("[Auto PVP] ✗ No match found")
    end

    return bestPlayer
end

local lastHealthValue = nil
local function setupDamageDetection()
    local char = LocalPlayer.Character
    if not char then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    lastHealthValue = humanoid.Health

    if humanoid:FindFirstChild("_DamageDetected") then
        return
    end

    -- Mark that damage detection is set up for this humanoid
    local flag = Instance.new("BoolValue")
    flag.Name = "_DamageDetected"
    flag.Parent = humanoid

    humanoid.HealthChanged:Connect(function(health)
        -- Check if bot died
        if health <= 0 then
            print("[Auto PVP] Bot died, stopping...")
            _G.AdvancedPVPBot.stop()
            lastHealthValue = health
            return
        end

        if not AutoPVPState.enabled then
            lastHealthValue = health
            return
        end

        -- Check if current target is dead or escaped to safe zone
        if BotState.target then
            -- Safety: check if target player still exists
            local targetStillExists = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p == BotState.target then
                    targetStillExists = true
                    break
                end
            end

            if not targetStillExists then
                print("[Auto PVP] Target left the game, clearing target")
                BotState.target = nil
                BotState.target_last_y = nil
                _G.AdvancedPVPBot.stop()
                lastHealthValue = health
                return
            end

            local targetChar = BotState.target.Character
            local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

            -- Check if dead
            if not targetHumanoid or targetHumanoid.Health <= 0 then
                print("[Auto PVP] Target " .. BotState.target.Name .. " is dead")
                BotState.target = nil
                BotState.target_last_y = nil

                if AutoPVPState.auto_reengage then
                    print("[Auto PVP] Auto Re-engage ON: waiting for next attacker...")
                else
                    print("[Auto PVP] Auto Re-engage OFF: stopping bot")
                    _G.AdvancedPVPBot.stop()
                    lastHealthValue = health
                    return
                end
            -- Check if target escaped to safe zone
            elseif targetRoot and isInsideSafeZone(targetRoot.Position) then
                print("[Auto PVP] Target " .. BotState.target.Name .. " escaped to safe zone, disengaging")
                BotState.target = nil
                BotState.target_last_y = nil
                _G.AdvancedPVPBot.stop()
                lastHealthValue = health
                return
            -- Check if target used bird morph (Y jump > 3 studs = flying away)
            elseif targetRoot and BotState.target_last_y then
                local yDiff = targetRoot.Position.Y - BotState.target_last_y
                if yDiff > 3 then
                    print("[Auto PVP] Target " .. BotState.target.Name .. " flew away (bird morph), disengaging")
                    BotState.target = nil
                    BotState.target_last_y = nil
                    _G.AdvancedPVPBot.stop()
                    lastHealthValue = health
                    return
                end
                BotState.target_last_y = targetRoot.Position.Y
            end
        end

        if lastHealthValue and lastHealthValue > health then
            local damageTaken = lastHealthValue - health
            AutoPVPState.last_damage_time = tick()

            -- If already have target, stay locked (don't switch on new damage)
            if BotState.target then
                print("[Auto PVP] Already targeting " .. BotState.target.Name .. ", ignoring new attacker")
                lastHealthValue = health
                return
            end

            -- Only find new attacker if no target
            local attacker = findAttackerByDamage(damageTaken)
            if attacker and attacker.Character then
                local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
                local inSafeZone = attackerRoot and isInsideSafeZone(attackerRoot.Position) or false

                print("[Auto PVP] Attacker: " .. attacker.Name .. " | Pos: X=" .. string.format("%.1f", attackerRoot.Position.X) .. ", Z=" .. string.format("%.1f", attackerRoot.Position.Z) .. " | In SafeZone: " .. tostring(inSafeZone))

                -- Check if battle is winnable
                if not isWinnableBattle(attacker) then
                    print("[Auto PVP] " .. attacker.Name .. " is too strong, ignoring")
                    lastHealthValue = health
                    return
                end

                -- Check if in AutoZone (outside safe zone)
                if not isInAutoZone(attacker) then
                    print("[Auto PVP] " .. attacker.Name .. " is in safe zone, ignoring")
                    lastHealthValue = health
                    return
                end

                AutoPVPState.last_attacker = attacker
                if BotState.enabled then
                    _G.AdvancedPVPBot.setTarget(attacker)
                    print("[Auto PVP] Hit by " .. attacker.Name .. "! Engaging (winnable)...")
                else
                    _G.AdvancedPVPBot.setTarget(attacker)
                    _G.AdvancedPVPBot.start()
                    print("[Auto PVP] Hit by " .. attacker.Name .. "! Bot started (winnable)...")
                end
            end
        end

        lastHealthValue = health
    end)
end

local characterDetectionHooked = false
local function setupAutoCharacterDetection()
    if characterDetectionHooked then return end
    characterDetectionHooked = true

    LocalPlayer.CharacterAdded:Connect(function(char)
        if not AutoPVPState.enabled then return end

        print("[Auto PVP] Character respawned, re-hooking damage detection...")

        -- Wait for humanoid to be ready
        local humanoid = char:WaitForChild("Humanoid", 5)
        if not humanoid then
            print("[Auto PVP] ERROR: Humanoid not found after respawn")
            return
        end

        task.wait(0.2)
        lastHealthValue = nil
        setupDamageDetection()
        print("[Auto PVP] ✓ Damage detection re-hooked after respawn")
    end)
end

local updateCounter = 0

local function updateMovement()
    -- Independent movement system: maintain position based on Q cooldown or follow ally
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        releaseAllKeys()
        return
    end

    -- Follow ally if enabled and no combat target
    if BotState.follow_ally_enabled and not BotState.target then
        local ally = findClosestAlly()
        if ally and ally.Character then
            local allyRoot = ally.Character:FindFirstChild("HumanoidRootPart")
            if allyRoot then
                local distToAlly = getDistance(root.Position, allyRoot.Position)

                -- If too far from ally, move closer
                if distToAlly > Config.follow_ally_dist then
                    moveTowardWithInterception(allyRoot)
                    if updateCounter % 30 == 0 then
                        print("[Follow Ally] Following " .. ally.Name .. " | Dist: " .. string.format("%.1f", distToAlly))
                    end
                    return
                else
                    -- Close enough, stop moving
                    releaseAllKeys()
                    return
                end
            end
        end
        releaseAllKeys()
        return
    end

    -- Combat mode: maintain position based on Q cooldown
    if not BotState.enabled or not BotState.target then
        releaseAllKeys()
        return
    end

    local targetChar = BotState.target.Character
    if not targetChar then
        releaseAllKeys()
        return
    end

    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
        releaseAllKeys()
        return
    end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetRoot.Position)
    local qReady = (tick() - BotState.last_q_time) > Config.q_cooldown

    -- Aim camera at target (or ally if following)
    if BotState.follow_ally_enabled and not BotState.target then
        local ally = findClosestAlly()
        if ally and ally.Character then
            local allyRoot = ally.Character:FindFirstChild("HumanoidRootPart")
            if allyRoot then
                aimCameraAtTarget(allyRoot)
            end
        end
    else
        aimCameraAtTarget(targetRoot)
    end

    if qReady then
        -- Q is ready: move to melee range (6 studs) for attack
        BotState.current_state = "approaching"
        if dist > Config.melee_range then
            moveTowardWithInterception(targetRoot)
        else
            releaseAllKeys()
        end
    else
        -- Q on cooldown: stay at 10-15 studs and bait/strafe to dodge fireballs
        BotState.current_state = "baiting"
        strafeBaitDodge(targetRoot)
    end
end

local function updateHitting()
    -- Independent hitting system: fire Q whenever ready and in range
    if not BotState.enabled or not BotState.target then
        return
    end

    local targetChar = BotState.target.Character
    if not targetChar then return end

    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
        return
    end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetRoot.Position)
    local qReady = (tick() - BotState.last_q_time) > Config.q_cooldown

    -- Spam T when in hit range (stance animation)
    if dist <= Config.melee_range then
        spamT()
    end

    -- Fire Q whenever ready and in melee range
    if qReady and dist <= Config.melee_range then
        attackWithQ()
    end
end

local function updateBotState()
    updateCounter = updateCounter + 1

    refreshHeldKeys()

    if not BotState.enabled or not BotState.target then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    if updateCounter % 30 == 0 then
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local targetChar = BotState.target.Character
        local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if root and targetRoot then
            local dist = getDistance(root.Position, targetRoot.Position)
            print("[Bot] State: " .. BotState.current_state .. " | Dist: " .. string.format("%.1f", dist) .. " | Target: " .. BotState.target.Name)
        end
    end

    -- Independent systems
    updateMovement()
    updateHitting()

    -- AutoZone target search
    if BotState.autozone_enabled then
        updateAutozoneTarget()
    end

    -- Auto item management
    if BotState.enabled then
        ensureFireballEquipped()
        useFood()
    end
end

local botLoop
_G.AdvancedPVPBot = {
    state = BotState,
    config = Config,
    autoPVP = AutoPVPState,

    start = function()
        if BotState.enabled then return end
        BotState.enabled = true
        toggleShiftLock(true)
        if not botLoop then
            botLoop = RunService.Heartbeat:Connect(updateBotState)
        end
        print("[Advanced PVP Bot] Started with Shift Lock enabled")
    end,

    stop = function()
        BotState.enabled = false
        releaseAllKeys()
        toggleShiftLock(false)
        print("[Advanced PVP Bot] Stopped, Shift Lock disabled")
    end,

    toggle = function()
        if BotState.enabled then _G.AdvancedPVPBot.stop() else _G.AdvancedPVPBot.start() end
    end,

    setTarget = function(player)
        BotState.target = player
        if player then
            print("[Advanced PVP Bot] Target:", player.Name)
        end
    end,

    getState = function()
        return BotState.current_state
    end,

    setAutoPVP = function(enabled)
        AutoPVPState.enabled = enabled
        if enabled then
            print("[Auto PVP] Enabled - listening for damage")
            setupDamageDetection()
            setupAutoCharacterDetection()
        else
            print("[Auto PVP] Disabled")
            _G.AdvancedPVPBot.stop()
            BotState.target = nil
            print("[Auto PVP] Target cleared")
        end
    end,

    getAutoPVP = function()
        return AutoPVPState.enabled
    end,
}

print([[
[Advanced PVP Bot] Loaded!

States:
  idle      - Waiting for target
  approaching - Moving to enemy (non-headon intercept)
  attacking - In range, sending Q (double-hit if fireball ready)
  baiting   - Cooldown, strafing to dodge fireballs

Strategy:
  1. Approach with interception (not headon)
  2. Attack when in range (Q + Fireball simultaneous if ready)
  3. Bait fireballs during cooldown (strafe at safe distance)
  4. Never disengage (stay in combat radius)
]])

-- ===== UI BUILDER =====

local function buildUI(venyx)
    if not venyx then
        error("[AnimalSim] Venyx UI library required")
    end

    -- UI is already created by main.lua, just add pages to it
    local ui = venyx
    local mainPage = ui:addPage({title = "Main"})

    local function collectPlayerNames()
        local names = {}
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player ~= game:GetService("Players").LocalPlayer then
                table.insert(names, player.Name)
            end
        end
        table.sort(names)
        return names
    end

    -- ===== COMBAT SECTION =====
    local combatSection = mainPage:addSection({title = "Combat"})

    local targetDropdown = combatSection:addDropdown({
        title = "Set Target Player",
        list = collectPlayerNames(),
        callback = function(playerName)
            if playerName then
                local selectedPlayer = game:GetService("Players"):FindFirstChild(playerName)
                if selectedPlayer then
                    print("[Combat] Selected target:", playerName)
                end
            end
        end,
    })

    combatSection:addToggle({
        title = "Auto PVP",
        toggled = false,
        callback = function(val)
            if _G.AdvancedPVPBot then
                _G.AdvancedPVPBot.setAutoPVP(val)
            end
        end,
    })

    combatSection:addToggle({
        title = "Show Player HUD",
        toggled = false,
        callback = function(val)
            if val then
                enableHUD()
            else
                disableHUD()
            end
        end,
    })

    combatSection:addToggle({
        title = "Auto Eat",
        toggled = false,
        callback = function(val)
            print("[Combat] Auto Eat:", val)
        end,
    })

    combatSection:addToggle({
        title = "Auto Fireball (Engaged)",
        toggled = false,
        callback = function(val)
            print("[Combat] Auto Fireball:", val)
        end,
    })

    combatSection:addButton({
        title = "Damage Player",
        callback = function()
            print("[Combat] Damage info requested")
        end,
    })

    -- ===== PVP BOT SECTION =====
    local pvpBotSection = mainPage:addSection({title = "PVP Bot"})

    pvpBotSection:addToggle({
        title = "Enable PVP Bot",
        toggled = false,
        callback = function(val)
            if _G.AdvancedPVPBot then
                if val then _G.AdvancedPVPBot.start() else _G.AdvancedPVPBot.stop() end
            end
        end,
    })

    pvpBotSection:addToggle({
        title = "Auto Sprint",
        toggled = false,
        callback = function(val)
            Config.approach_speed = val and "sprint" or "normal"
            print("[PVP Bot] Auto Sprint:", val)
        end,
    })

    pvpBotSection:addToggle({
        title = "Auto Re-engage",
        toggled = false,
        callback = function(val)
            if _G.AdvancedPVPBot then
                AutoPVPState.auto_reengage = val
                print("[Auto PVP] Auto Re-engage:", val and "ON (hunt new attackers)" or "OFF (stop after kill)")
            end
        end,
    })

    local botTargetDropdown = pvpBotSection:addDropdown({
        title = "PVP Bot Target",
        list = collectPlayerNames(),
        callback = function(playerName)
            if playerName and _G.AdvancedPVPBot then
                local player = game:GetService("Players"):FindFirstChild(playerName)
                if player then _G.AdvancedPVPBot.setTarget(player) end
            end
        end,
    })

    -- ===== AUTOZONE SECTION =====
    local autozoneSection = mainPage:addSection({title = "AutoZone"})

    autozoneSection:addToggle({
        title = "AutoZone Enabled",
        toggled = false,
        callback = function(val)
            BotState.autozone_enabled = val
            print("[AutoZone]", val and "Enabled (engage enemies near allies)" or "Disabled")
        end,
    })

    autozoneSection:addToggle({
        title = "Follow Ally",
        toggled = false,
        callback = function(val)
            BotState.follow_ally_enabled = val
            print("[Follow Ally]", val and "Enabled" or "Disabled")
        end,
    })

    -- Enemy clan dropdown (auto-updating)
    local function getEnemyClanOptions()
        local clans = {}
        if workspace:FindFirstChild("Teams") then
            for _, teamFolder in ipairs(workspace.Teams:GetChildren()) do
                -- Exclude player's own clan
                if teamFolder.Name ~= Config.ally_clan_name then
                    table.insert(clans, teamFolder.Name)
                end
            end
        end
        table.insert(clans, "Any Enemy")
        return clans
    end

    local enemyClanDropdown = autozoneSection:addDropdown({
        title = "Zone Enemy Clan",
        list = getEnemyClanOptions(),
        callback = function(clanName)
            BotState.target_enemy_clan = clanName
            print("[AutoZone] Zoning clan:", clanName)
        end,
    })

    autozoneSection:addButton({
        title = "Refresh Clans",
        callback = function()
            local freshClans = getEnemyClanOptions()
            enemyClanDropdown.Options:SetOptions(freshClans)
            print("[AutoZone] Clan list refreshed (" .. #freshClans .. " options)")
        end,
    })

    autozoneSection:addSlider({
        title = "Ally Follow Distance",
        min = 5,
        max = 50,
        default = 15,
        precision = 0,
        callback = function(val)
            Config.autozone_ally_follow_dist = tonumber(val) or 15
            print("[AutoZone] Ally follow dist:", val)
        end,
    })

    autozoneSection:addSlider({
        title = "Enemy Engage Range",
        min = 10,
        max = 100,
        default = 30,
        precision = 0,
        callback = function(val)
            Config.autozone_engage_range = tonumber(val) or 30
            print("[AutoZone] Engage range:", val)
        end,
    })

    autozoneSection:addButton({
        title = "Debug AutoZone",
        callback = function()
            print("\n[AutoZone Debug]")
            print("  Enabled:", BotState.autozone_enabled)
            print("  Target Clan:", BotState.target_enemy_clan)
            local ally = findClosestAlly()
            print("  Closest Ally:", ally and ally.Name or "None found")
            if ally and ally.Character then
                print("    Ally in safe zone:", isInsideSafeZone(ally.Character:FindFirstChild("HumanoidRootPart").Position))
            end
            print()
        end,
    })

    -- ===== HIT-TO-KILL SECTION =====
    local ratioSection = mainPage:addSection({title = "Hit-to-Kill Ratio"})

    ratioSection:addSlider({
        title = "Damage Multiplier",
        min = 0.1,
        max = 2,
        default = 1,
        precision = 1,
        callback = function(val)
            _G.DamageMultiplier = tonumber(val) or 1
            print("[Ratio] Damage Multiplier:", val)
        end,
    })

    ratioSection:addButton({
        title = "Show Damage Info",
        callback = function()
            print("[Ratio] Run damage_ratio_probe for live calculations")
        end,
    })

    -- ===== AUTO ITEMS SECTION =====
    local itemsSection = mainPage:addSection({title = "Auto Items"})

    itemsSection:addToggle({
        title = "Auto Eat",
        toggled = false,
        callback = function(val)
            BotState.auto_eat_enabled = val
            print("[Auto Eat]", val and "Enabled" or "Disabled")
        end,
    })

    itemsSection:addToggle({
        title = "Auto Fireball",
        toggled = false,
        callback = function(val)
            BotState.auto_fireball_enabled = val
            print("[Auto Fireball]", val and "Enabled (keep equipped)" or "Disabled")
        end,
    })

    itemsSection:addSlider({
        title = "Eat HP Threshold",
        min = 0.1,
        max = 1,
        default = 0.8,
        precision = 1,
        callback = function(val)
            Config.eat_hp_threshold = tonumber(val) or 0.8
            print("[Auto Eat] HP Threshold:", string.format("%.0f%%", Config.eat_hp_threshold * 100))
        end,
    })

    -- ===== MISC SECTION =====
    local miscSection = mainPage:addSection({title = "Misc"})

    miscSection:addToggle({
        title = "Safe Zone Visualizer",
        toggled = false,
        callback = function(val)
            if val then
                createSafeZoneVisualizer()
            else
                destroySafeZoneVisualizer()
            end
        end,
    })

    miscSection:addToggle({
        title = "Remember Walkspeed",
        toggled = false,
        callback = function(val)
            print("[Misc] Remember Walkspeed:", val)
        end,
    })

    miscSection:addToggle({
        title = "Movement Visualizer",
        toggled = false,
        callback = function(val)
            print("[Misc] Movement Visualizer:", val)
        end,
    })

    miscSection:addToggle({
        title = "Use Target",
        toggled = false,
        callback = function(val)
            print("[Misc] Use Target:", val)
        end,
    })

    miscSection:addButton({
        title = "Load AW Script",
        callback = function()
            print("[Misc] AW Script loaded")
        end,
    })

    miscSection:addButton({
        title = "Debug: Show Clan",
        callback = function()
            print("\n[Clan Detection]")
            print("  Your Clan: " .. Config.ally_clan_name)
            print("  Detected from: workspace.Teams")
            print("\n[All Available Clans]")
            if workspace:FindFirstChild("Teams") then
                for _, teamFolder in ipairs(workspace.Teams:GetChildren()) do
                    print("  • " .. teamFolder.Name)
                end
            else
                print("  ✗ No Teams folder found")
            end
            print("")
        end,
    })

    return ui
end

-- ===== INITIALIZATION =====

if game:IsLoaded() then
    if _G.venyx then
        print("[Animal Sim v2] Building UI with passed Venyx...")
        buildUI(_G.venyx)
    else
        print("[Animal Sim v2] ERROR: Venyx not found in _G")
    end
else
    game.Loaded:Wait()
    if _G.venyx then
        print("[Animal Sim v2] Building UI with passed Venyx...")
        buildUI(_G.venyx)
    else
        print("[Animal Sim v2] ERROR: Venyx not found in _G")
    end
end

print("[Animal Sim v2] Script loaded! Advanced PVP Bot ready.")
