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
        game:HttpPost(INTENT_SERVER, json, true)
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
    last_q_time = 0,
    last_fireball_time = 0,
    movement_keys = {w=false, a=false, s=false, d=false},
}

local Config = {
    melee_range = 6,
    combat_radius = 25,
    q_cooldown = 0.65,
    fireball_cooldown = 1.4,
    approach_speed = "normal",
}

-- ===== AUTO PVP STATE =====

local AutoPVPState = {
    enabled = false,
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

local function moveTowardWithInterception(targetPos)
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    local camRight = Vector3.new(camDir.Z, 0, -camDir.X).Unit
    local camForward = Vector3.new(-camDir.Z, 0, camDir.X).Unit

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

local function fireballBait(targetPos)
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetPos)
    local dirToTarget = getDirection(root.Position, targetPos)
    local camDir = getCameraDirection()

    local camRight = Vector3.new(camDir.Z, 0, -camDir.X).Unit
    local camForward = Vector3.new(-camDir.Z, 0, camDir.X).Unit

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

-- ===== AUTO PVP DAMAGE DETECTION =====

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

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoidInstance = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")

            if humanoidInstance and humanoidInstance.Health > 0 and root then
                -- Estimate damage based on level
                local level = getPlayerLevel(player) or 1
                local estimatedDamage = (level * 2) + 10
                local diff = math.abs(estimatedDamage - damageTaken)
                local tolerance = math.max(30, estimatedDamage * 0.5)
                local distance = (root.Position - localRoot.Position).Magnitude
                local score = diff + (distance * 0.02)

                print("[Auto PVP] Check: " .. player.Name .. " | Lvl:" .. level .. " | Est:" .. estimatedDamage .. " | Taken:" .. damageTaken .. " | Diff:" .. string.format("%.1f", diff) .. " | Tol:" .. string.format("%.1f", tolerance) .. " | Match: " .. (diff <= tolerance and "YES" or "NO"))

                if diff <= tolerance then
                    print("[Auto PVP]   → Score: " .. string.format("%.1f", score))
                    if score < bestScore then
                        bestScore = score
                        bestPlayer = player
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

    humanoid.HealthChanged:Connect(function(health)
        if not AutoPVPState.enabled then
            lastHealthValue = health
            return
        end

        if lastHealthValue and lastHealthValue > health then
            local damageTaken = lastHealthValue - health
            AutoPVPState.last_damage_time = tick()

            local attacker = findAttackerByDamage(damageTaken)
            if attacker and attacker.Character then
                AutoPVPState.last_attacker = attacker
                if BotState.enabled then
                    _G.AdvancedPVPBot.setTarget(attacker)
                    print("[Auto PVP] Hit by " .. attacker.Name .. "! Engaging...")
                else
                    _G.AdvancedPVPBot.setTarget(attacker)
                    _G.AdvancedPVPBot.start()
                    print("[Auto PVP] Hit by " .. attacker.Name .. "! Bot started")
                end
            end
        end

        lastHealthValue = health
    end)
end

local function setupAutoCharacterDetection()
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.1)
        lastHealthValue = nil
        setupDamageDetection()
    end)
end

local updateCounter = 0
local function updateBotState()
    updateCounter = updateCounter + 1

    if not BotState.enabled or not BotState.target then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local targetChar = BotState.target.Character
    if not targetChar then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
        BotState.current_state = "idle"
        releaseAllKeys()
        return
    end

    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dist = getDistance(root.Position, targetRoot.Position)
    local qReady = (tick() - BotState.last_q_time) > Config.q_cooldown
    local fireballReady = (tick() - BotState.last_fireball_time) > Config.fireball_cooldown

    if updateCounter % 30 == 0 then
        print("[Bot State] State: " .. BotState.current_state .. " | Dist: " .. string.format("%.1f", dist) .. " | Target: " .. BotState.target.Name)
    end

    if qReady and dist > Config.melee_range then
        BotState.current_state = "approaching"
        moveTowardWithInterception(targetRoot.Position)

    elseif qReady and dist <= Config.melee_range then
        BotState.current_state = "attacking"
        releaseAllKeys()

        if fireballReady then
            doubleHit()
        else
            attackWithQ()
        end

    else
        BotState.current_state = "baiting"
        if dist > Config.combat_radius then
            moveTowardWithInterception(targetRoot.Position)
        else
            fireballBait(targetRoot.Position)
        end
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
        if not botLoop then
            botLoop = RunService.Heartbeat:Connect(updateBotState)
        end
        print("[Advanced PVP Bot] Started")
    end,

    stop = function()
        BotState.enabled = false
        releaseAllKeys()
        print("[Advanced PVP Bot] Stopped")
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

    local ui = venyx.new({title = "Animal Sim PVP"})
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
            print("[PVP Bot] Auto Re-engage:", val)
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
        title = "Auto Zone (kills all outside safe)",
        toggled = false,
        callback = function(val)
            print("[AutoZone] Enabled:", val)
        end,
    })

    autozoneSection:addToggle({
        title = "Follow Ally",
        toggled = false,
        callback = function(val)
            print("[AutoZone] Follow Ally:", val)
        end,
    })

    autozoneSection:addSlider({
        title = "Ally Follow Min Dist",
        min = 0,
        max = 500,
        default = 3,
        precision = 0,
        callback = function(val)
            print("[AutoZone] Follow Min Dist:", val)
        end,
    })

    autozoneSection:addSlider({
        title = "Ally Target Range",
        min = 0,
        max = 500,
        default = 20,
        precision = 0,
        callback = function(val)
            print("[AutoZone] Target Range:", val)
        end,
    })

    autozoneSection:addToggle({
        title = "Auto Zone Fakeouts",
        toggled = false,
        callback = function(val)
            print("[AutoZone] Fakeouts:", val)
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

    -- ===== MISC SECTION =====
    local miscSection = mainPage:addSection({title = "Misc"})

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
