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
    auto_sprint_enabled = false,     -- "shift" is a sprint toggle in this game
    sprint_on = false,               -- what we believe the game's sprint state currently is
    sprint_last_sync = 0,
    follow_ally_enabled = false,
    follow_leader_enabled = false,   -- Follow Ally targets the clan's "leader" entry instead of the nearest ally
    follow_moving = false,           -- hysteresis latch for the follow distance
    autozone_enabled = false,
    closest_ally = nil,
    target_enemy_clan = "Any Target",
}

-- ===== TEAM / CLAN STRUCTURE (as observed in this game) =====
-- workspace.Teams
--   └── <ClanName>      (Folder; .Name is the clan name)
--         ├── leader    (value object; .Value = the creator's USERNAME)
--         └── <member>  (value object; .Value = that member's USERNAME)
-- Every clan always has a "leader" entry, and one entry per additional member.
-- .Value holds the plain USERNAME (no "@", never the display name), so it is compared
-- against Player.Name / LocalPlayer.Name and never against DisplayName.
local CLAN_PLACEHOLDER = "enter clan name here"

-- Read the username stored in a member entry (tolerates ObjectValues holding a Player).
local function entryUsername(member)
    local ok, value = pcall(function() return member.Value end)
    if not ok or value == nil then return nil end
    if typeof(value) == "Instance" then return value.Name end
    return tostring(value)
end

-- Is this player listed in this clan folder, as leader or as a member?
local function teamHasPlayer(teamFolder, username)
    if not teamFolder or not username then return false end
    for _, member in ipairs(teamFolder:GetChildren()) do
        if member.Name == username then return true end
        if entryUsername(member) == username then return true end
    end
    return false
end

-- The clan's leader username, from the mandatory "leader" entry.
local function getTeamLeaderName(teamFolder)
    local leaderEntry = teamFolder and teamFolder:FindFirstChild("leader")
    if not leaderEntry then return nil end
    return entryUsername(leaderEntry)
end

-- Auto-detect player's team/clan. Matches on membership (.Value), because the child names
-- are not guaranteed to be the usernames.
local function autoDetectClan()
    if not LocalPlayer then return CLAN_PLACEHOLDER end
    if workspace:FindFirstChild("Teams") then
        for _, teamFolder in ipairs(workspace.Teams:GetChildren()) do
            if teamHasPlayer(teamFolder, LocalPlayer.Name) then
                return teamFolder.Name
            end
        end
    end
    return CLAN_PLACEHOLDER
end

-- Safely call autoDetectClan with fallback
local function getSafeClanName()
    local ok, result = pcall(autoDetectClan)
    if ok and result then
        return result
    end
    return CLAN_PLACEHOLDER
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
    follow_ally_stop_dist = 15,   -- keep closing until this close, so it does not jitter at follow_ally_dist
    ally_clan_name = getSafeClanName(),
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

            -- Players who are tracked but have no GUI yet (character was not ready when they were
            -- tracked, or arrived after CharacterAdded fired) get one created here. Without this
            -- retry, late joiners showed no overhead at all.
            for player in pairs(HUDState.overhead_connections) do
                if player.Parent and player.Character and not HUDState.overhead_entries[player] then
                    createGuiForPlayer(player, player.Character)
                end
            end

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

                        -- Colour by the same threshold the winnability check uses - the Damage
                        -- Multiplier slider (_G.DamageMultiplier) - so green/red always agrees with
                        -- whether the fight is actually accepted. The loop runs every frame, so
                        -- moving the slider recolours with no toggle.
                        local multiplier = tonumber(_G.DamageMultiplier) or 1.0
                        local hitRatio = tonumber(hitsToKillEnemy) and tonumber(hitsToKillYou) and (tonumber(hitsToKillEnemy) / tonumber(hitsToKillYou)) or 0
                        if hitRatio <= multiplier then
                            entry.info.TextColor3 = Color3.fromRGB(80, 200, 120) -- GREEN: within the multiplier, fight accepted
                        else
                            entry.info.TextColor3 = Color3.fromRGB(240, 80, 80) -- RED: needs more hits than the multiplier allows
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

-- ===== AUTO SPRINT =====
-- "shift" TOGGLES sprint in this game. It starts OFF, and the game resets it to OFF on join
-- and on every respawn / character change. So we keep a belief of the current state and press
-- the toggle once whenever the desired state (the Auto Sprint toggle) disagrees with it. The
-- CharacterAdded handler below resets the belief, so the next tick re-applies the press.
local SPRINT_RESYNC_INTERVAL = 0.5

local function syncSprint()
    if BotState.auto_sprint_enabled == BotState.sprint_on then return end

    local now = tick()
    if now - BotState.sprint_last_sync < SPRINT_RESYNC_INTERVAL then return end
    BotState.sprint_last_sync = now

    local desired = BotState.auto_sprint_enabled
    -- Spawned so the Heartbeat handler never yields on the 0.1s press.
    task.spawn(function()
        sendIntent("shift", "down")
        task.wait(0.1)
        sendIntent("shift", "up")
        BotState.sprint_on = desired
        print("[Auto Sprint]", desired and "ON" or "OFF")
    end)
end

-- Respawn / character change turns sprint off in-game, so forget the belief and let
-- syncSprint() press it back on.
LocalPlayer.CharacterAdded:Connect(function()
    BotState.sprint_on = false
end)

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

local warnedNoClan = false

-- Forward declarations for the zone machinery, which is defined BELOW but is called from here.
-- Without these the calls below resolved to globals and blew up at runtime with
-- 'attempt to call a nil value', aborting the rest of that Heartbeat tick.
local isInsideSafeZone, isInAutoZone, characterInSafeZone

local function findClosestAlly()
    local char = LocalPlayer.Character
    if not char then return nil end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    -- Config.ally_clan_name is resolved once at load time, but workspace.Teams is usually not
    -- populated yet at that point, which leaves the placeholder in place forever and makes
    -- every ally lookup return nil. Retry while it is still the placeholder.
    if Config.ally_clan_name == CLAN_PLACEHOLDER then
        local detected = autoDetectClan()
        if detected and detected ~= CLAN_PLACEHOLDER then
            Config.ally_clan_name = detected
            print("[Follow Ally] Clan resolved late: " .. detected)
        end
    end

    -- Resolved once per call instead of once per player.
    local teamFolder = workspace.Teams and workspace.Teams:FindFirstChild(Config.ally_clan_name)
    if not teamFolder then
        if not warnedNoClan then
            warnedNoClan = true
            print("[Follow Ally] No '" .. tostring(Config.ally_clan_name) .. "' folder under workspace.Teams - ally detection will find nothing")
        end
        return nil
    end

    local closestAlly = nil
    local closestDist = math.huge

    -- Find closest ally (same clan as us)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            -- teamFolder is resolved once at the top of this function
            if teamFolder then
                -- Membership lives in the entry's .Value (the username), so use the shared
                -- helper rather than assuming the child is named after the player.
                local isAlly = teamHasPlayer(teamFolder, player.Name)

                if isAlly then
                    local allyHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    local allyRoot = player.Character:FindFirstChild("HumanoidRootPart")
                    if allyRoot and allyHumanoid and allyHumanoid.Health > 0 then
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

    return closestAlly
end

local function updateAutozoneTarget()
    if not BotState.autozone_enabled then return end
    if BotState.target then return end  -- Already have target from manual/PVP

    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- You cannot fight from inside the safe zone, so never acquire a target while there
    -- (otherwise this would set a target and the tick would clear it again every frame).
    if characterInSafeZone(char) then return end

    -- The ally is an OPTIONAL anchor. While Follow Ally is on we stay inside that ally's zone
    -- (targets within engage range of them). With Follow Ally off - solo, or on a team but not
    -- following - there is no zone to stay in and the dropdown selection alone decides the scope:
    -- one specific clan, or Any Target. The ratio check still has to pass either way.
    local ally = nil
    local allyRoot = nil
    if BotState.follow_ally_enabled then
        ally = findClosestAlly()
        if ally and ally.Character then
            local candidate = ally.Character:FindFirstChild("HumanoidRootPart")
            if candidate and not characterInSafeZone(ally.Character) then
                allyRoot = candidate
            end
        end
    end

    -- Find closest enemy within engage range of ally
    local closestEnemy = nil
    local closestEnemyDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local enemyRoot = player.Character:FindFirstChild("HumanoidRootPart")
            local enemyHumanoid = player.Character:FindFirstChildOfClass("Humanoid")

            if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
                -- Check if enemy matches the selected clan (or "Any Target")
                local isTargetClan = false
                if BotState.target_enemy_clan == "Any Target" then
                    isTargetClan = true
                else
                    local teamFolder = workspace.Teams and workspace.Teams:FindFirstChild(BotState.target_enemy_clan)
                    if teamFolder then
                        isTargetClan = teamHasPlayer(teamFolder, player.Name)
                    end
                end

                if isTargetClan then
                    -- Check if enemy is outside safe zone
                    if not characterInSafeZone(player.Character) then
                        -- With an anchor, stay in the ally's zone (within engage range of them).
                        -- Solo there is no zone to stay in: anyone outside the safe zone qualifies
                        -- and the ratio check decides.
                        local inRange = true
                        if allyRoot then
                            inRange = getDistance(allyRoot.Position, enemyRoot.Position) <= Config.autozone_engage_range
                        end
                        if inRange then
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
            -- Arm the bot if it is not running, so "engage" actually moves and hits instead of
            -- only setting a target (the damage path does the same thing).
            if not BotState.enabled then
                _G.AdvancedPVPBot.start()
            end
            _G.AdvancedPVPBot.setTarget(closestEnemy)
            print("[AutoZone] ✓ Engaging " .. closestEnemy.Name .. (allyRoot
                and (" within " .. Config.autozone_engage_range .. " studs of ally " .. ally.Name)
                or " (no ally anchor - dropdown scope)"))
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

-- ===== AUTO-DETECT SAFE ZONE =====
local SAFE_ZONE_OBJECT = nil
local SAFE_ZONE_CORNERS = {}

local function autoDetectSafeZone()
    print("[SafeZone] Auto-detecting FightingZonePart...")

    -- Find FightingZonePart
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "FightingZonePart" and obj:IsA("Part") then
            SAFE_ZONE_OBJECT = obj
            print("[SafeZone] ✓ Found FightingZonePart")
            break
        end
    end

    if not SAFE_ZONE_OBJECT then
        print("[SafeZone] ✗ FightingZonePart not found, using fallback")
        SAFE_ZONE_CORNERS = {
            corner1 = {x = -113.61, z = 401.64},
            corner2 = {x = -45.67, z = 588.11},
            corner3 = {x = -276.38, z = 672.11},
            corner4 = {x = -345.77, z = 486.77},
        }
        return
    end

    -- Extract corners from actual object
    local pos = SAFE_ZONE_OBJECT.Position
    local size = SAFE_ZONE_OBJECT.Size / 2

    local minX = pos.X - size.X
    local maxX = pos.X + size.X
    local minZ = pos.Z - size.Z
    local maxZ = pos.Z + size.Z

    SAFE_ZONE_CORNERS = {
        corner1 = {x = minX, z = minZ},
        corner2 = {x = maxX, z = minZ},
        corner3 = {x = maxX, z = maxZ},
        corner4 = {x = minX, z = maxZ},
    }

    print(string.format("[SafeZone] ✓ FightingZonePart size=(%.1f, %.1f, %.1f) orientation=(%.1f, %.1f, %.1f)",
        SAFE_ZONE_OBJECT.Size.X, SAFE_ZONE_OBJECT.Size.Y, SAFE_ZONE_OBJECT.Size.Z,
        SAFE_ZONE_OBJECT.Orientation.X, SAFE_ZONE_OBJECT.Orientation.Y, SAFE_ZONE_OBJECT.Orientation.Z))
end

-- autoDetectSafeZone() -- Disabled: runs when buildUI is called instead

-- FightingZonePart is ROTATED, so an axis-aligned min/max box around its position does not
-- match the real zone: it accepts points outside the zone and rejects points inside it, which
-- is why Auto PVP never disengaged when standing in the zone. When the part is available the
-- test runs in its own object space (rotation included - the same approach that worked in
-- safezone_direct.lua); the recorded four-corner fallback uses a same-side test, which also
-- copes with a rotated quad instead of collapsing it into an AABB.
local SAFE_ZONE_RECHECK_INTERVAL = 5
local nextSafeZoneCheck = 0

-- NAMING TRAP: the part is called FightingZonePart and sits under Workspace.FightingArea, but
-- standing inside it IS THE SAFE ZONE (confirmed in game). The name means nothing - the geometry
-- is what counts. So a point inside this part is safe, and every check in this file that talks
-- about being "inside the safe zone" means "inside this part".
-- POLARITY, settled by MEASUREMENT rather than by toggling or by the part's name. Log line from
-- 20:29:11: a fight at X=303.9, Z=491.9 reported 'In SafeZone: true' with distFromCentre=503.3
-- against halfX=46.6 / halfZ=97.3 - i.e. a fighter 500 studs away from the part was being called
-- safe, and 'Ignoring <name> - is in the safe zone' followed. So inside this part IS the safe
-- zone and the fight area is outside it. The Misc toggle shows as ON; flip it if a future zone
-- is authored the other way round.
local ZONE_PART_IS_SAFE = true

-- The zone part may not be streamed in when buildUI runs, so retry now and then.
local function ensureSafeZone()
    if SAFE_ZONE_OBJECT then return true end
    local now = tick()
    if now < nextSafeZoneCheck then return false end
    nextSafeZoneCheck = now + SAFE_ZONE_RECHECK_INTERVAL
    autoDetectSafeZone()
    return SAFE_ZONE_OBJECT ~= nil
end

local function pointInQuad(px, pz, quad)
    local sign = nil
    for i = 1, #quad do
        local a = quad[i]
        local b = quad[i % #quad + 1]
        if a and b then
            local cross = (b.x - a.x) * (pz - a.z) - (b.z - a.z) * (px - a.x)
            if math.abs(cross) > 1e-6 then
                local positive = cross > 0
                if sign == nil then
                    sign = positive
                elseif sign ~= positive then
                    return false
                end
            end
        end
    end
    return sign ~= nil
end

function isInsideSafeZone(position)
    if position == nil then return false end

    -- Preferred: the real part, tested in its own space so rotation is accounted for.
    if ensureSafeZone() then
        local rel = SAFE_ZONE_OBJECT.CFrame:PointToObjectSpace(position)
        local half = SAFE_ZONE_OBJECT.Size / 2
        local insidePart = math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z
        if ZONE_PART_IS_SAFE then return insidePart end
        return not insidePart
    end

    -- Fallback: the four recorded corners treated as a (possibly rotated) quad.
    local quad = {
        SAFE_ZONE_CORNERS.corner1, SAFE_ZONE_CORNERS.corner2,
        SAFE_ZONE_CORNERS.corner3, SAFE_ZONE_CORNERS.corner4,
    }
    if not (quad[1] and quad[2] and quad[3] and quad[4]) then
        return false
    end
    local insideQuad = pointInQuad(position.X, position.Z, quad)
    if ZONE_PART_IS_SAFE then return insideQuad end
    return not insideQuad
end

-- Compact one-line explanation of how a position was classified, for settling the zone polarity
-- in game: whether the part was found, the raw inside-part result (before the switch) and how
-- far the position sits from the part's centre.
local function zoneDebug(position)
    if position == nil then return " | zone: n/a" end
    if not ensureSafeZone() then
        return " | zone: FightingZonePart NOT FOUND (recorded-corner fallback)"
    end
    local rel = SAFE_ZONE_OBJECT.CFrame:PointToObjectSpace(position)
    local half = SAFE_ZONE_OBJECT.Size / 2
    local insidePart = math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z
    local fromCentre = (SAFE_ZONE_OBJECT.Position - position).Magnitude
    return string.format(" | part=%s rawInsidePart=%s partIsSafe=%s distFromCentre=%.1f halfX=%.1f halfZ=%.1f",
        SAFE_ZONE_OBJECT.Name, tostring(insidePart), tostring(ZONE_PART_IS_SAFE),
        fromCentre, half.X, half.Z)
end

function isInAutoZone(player)
    if not player or not player.Character then return false end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    -- Check if outside safe zone (returns true if OUTSIDE)
    return not characterInSafeZone(player.Character)
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

    ensureSafeZone()

    -- Preferred: mirror the real part exactly. Same CFrame means the same rotation, which is the
    -- "rotation fix to match" that made the earlier direct-script box line up.
    if SAFE_ZONE_OBJECT then
        local zone = Instance.new("Part")
        zone.Name = "SafeZoneBox"
        zone.Shape = Enum.PartType.Block
        zone.Size = SAFE_ZONE_OBJECT.Size + Vector3.new(0, 60, 0)
        zone.CFrame = SAFE_ZONE_OBJECT.CFrame * CFrame.new(0, 30, 0)
        zone.Color = Color3.fromRGB(0, 255, 0)
        zone.Material = Enum.Material.Neon
        zone.Transparency = 0.6
        zone.CanCollide = false
        zone.Anchored = true          -- without this the box fell out of the world immediately
        zone.Parent = safeZoneVisualizerFolder

        print(string.format("[SafeZone Visualizer] boxing FightingZonePart: size=(%.1f, %.1f, %.1f) pos=(%.1f, %.1f, %.1f) rot=(%.1f, %.1f, %.1f)",
            SAFE_ZONE_OBJECT.Size.X, SAFE_ZONE_OBJECT.Size.Y, SAFE_ZONE_OBJECT.Size.Z,
            SAFE_ZONE_OBJECT.Position.X, SAFE_ZONE_OBJECT.Position.Y, SAFE_ZONE_OBJECT.Position.Z,
            SAFE_ZONE_OBJECT.Orientation.X, SAFE_ZONE_OBJECT.Orientation.Y, SAFE_ZONE_OBJECT.Orientation.Z))
        return
    end

    -- Fallback: no part found, so draw the recorded corners at your own height (the old code
    -- hardcoded Y = 200, which could put the box nowhere near the zone).
    local minX = math.min(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local maxX = math.max(corners[1].x, corners[2].x, corners[3].x, corners[4].x)
    local minZ = math.min(corners[1].z, corners[2].z, corners[3].z, corners[4].z)
    local maxZ = math.max(corners[1].z, corners[2].z, corners[3].z, corners[4].z)

    local centerY = 0
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then centerY = root.Position.Y end

    local box = Instance.new("Part")
    box.Name = "SafeZoneBox"
    box.Shape = Enum.PartType.Block
    box.Size = Vector3.new(maxX - minX, 100, maxZ - minZ)
    box.Color = Color3.fromRGB(0, 255, 0)
    box.Material = Enum.Material.Neon
    box.Transparency = 0.6
    box.CanCollide = false
    box.Anchored = true
    box.CFrame = CFrame.new((minX + maxX) / 2, centerY, (minZ + maxZ) / 2)
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
        marker.Anchored = true
        marker.CFrame = CFrame.new(corner.x, centerY, corner.z)
        marker.Parent = safeZoneVisualizerFolder
    end

    print("[SafeZone Visualizer] no FightingZonePart found - drew the recorded corners at your height instead")
end

local function destroySafeZoneVisualizer()
    if safeZoneVisualizerFolder then
        safeZoneVisualizerFolder:Destroy()
        safeZoneVisualizerFolder = nil
        print("[SafeZone Visualizer] Destroyed")
    end
end

-- ===== ZONE CUBE (touch-based membership) =====
-- A real cube mirroring the zone part's CFrame and Size - exactly the bounds the visualizer draws
-- - with Touched / TouchEnded so entries and exits are DETECTED rather than inferred by maths.
-- TouchEnded fires per body part, so leaving is confirmed by a short re-check, and a periodic
-- reconcile rebuilds the member set from GetTouchingParts so a missed event cannot leave a stale
-- entry. Every enter/leave is logged, which also makes the geometry verifiable in game.
local ZONE_RECONCILE_INTERVAL = 1
local zoneCube = nil
local zoneInside = {}
local zoneNextReconcile = 0

local function zoneCharacterOf(part)
    local model = part and part:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then return model end
    return nil
end

local function zoneLabel(character)
    local player = Players:GetPlayerFromCharacter(character)
    return player and player.Name or character.Name
end

local function zoneSetMember(character, inside)
    if not character then return end
    if inside and not zoneInside[character] then
        zoneInside[character] = true
        print("[Zone Cube] ENTER " .. zoneLabel(character))
    elseif not inside and zoneInside[character] then
        zoneInside[character] = nil
        print("[Zone Cube] LEAVE " .. zoneLabel(character))
    end
end

-- True when the cube currently sees this player or character inside. Available for game logic.
local function zoneTrackerHas(target)
    if not target then return false end
    if typeof(target) == "Instance" and target:IsA("Player") then
        return target.Character ~= nil and zoneInside[target.Character] == true
    end
    local character = (typeof(target) == "Instance" and zoneCharacterOf(target)) or target
    return zoneInside[character] == true
end

local function buildZoneCube()
    if zoneCube and zoneCube.Parent then return zoneCube end
    if not ensureSafeZone() then return nil end

    local cube = Instance.new("Part")
    cube.Name = "ZoneCube"
    cube.Shape = Enum.PartType.Block
    cube.Size = SAFE_ZONE_OBJECT.Size
    cube.CFrame = SAFE_ZONE_OBJECT.CFrame
    cube.Anchored = true
    cube.CanCollide = false
    cube.CanTouch = true          -- Touched / TouchEnded / GetTouchingParts all require this
    cube.CanQuery = true
    cube.Transparency = 1
    cube.CastShadow = false
    cube.Parent = workspace

    cube.Touched:Connect(function(part)
        zoneSetMember(zoneCharacterOf(part), true)
    end)

    cube.TouchEnded:Connect(function(part)
        local character = zoneCharacterOf(part)
        if character and zoneInside[character] then
            -- Only clear once no part of that character still overlaps the cube.
            task.delay(0.2, function()
                if not zoneInside[character] then return end
                for _, other in ipairs(cube:GetTouchingParts()) do
                    if zoneCharacterOf(other) == character then return end
                end
                zoneSetMember(character, false)
            end)
        end
    end)

    zoneCube = cube
    print(string.format("[Zone Cube] built: size (%.1f, %.1f, %.1f) at (%.1f, %.1f, %.1f)",
        cube.Size.X, cube.Size.Y, cube.Size.Z, cube.Position.X, cube.Position.Y, cube.Position.Z))
    return cube
end

local function zoneTrackerTick()
    if not buildZoneCube() then return end
    local now = tick()
    if now < zoneNextReconcile then return end
    zoneNextReconcile = now + ZONE_RECONCILE_INTERVAL

    local present = {}
    for _, part in ipairs(zoneCube:GetTouchingParts()) do
        local character = zoneCharacterOf(part)
        if character then present[character] = true end
    end

    for character in pairs(present) do
        zoneSetMember(character, true)
    end
    for character in pairs(zoneInside) do
        if not present[character] then zoneSetMember(character, false) end
    end
end

-- THE decision the rest of the script uses. Prefers the engine's own touch detection from the
-- zone cube (same volume the visualizer draws), and only falls back to the maths when the cube is
-- not available - i.e. when the zone part has not been found yet.
function characterInSafeZone(character)
    if not character then return false end

    if zoneCube and zoneCube.Parent then
        local insidePart = zoneInside[character] == true
        if ZONE_PART_IS_SAFE then return insidePart end
        return not insidePart
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    return root ~= nil and isInsideSafeZone(root.Position)
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

                -- Only match if damage aligns. The detail line lives inside this branch now: it used
                -- to print for EVERY player on EVERY damage guess, which buried the rest of the log.
                if diff <= tolerance then
                    if score < bestScore then
                        bestScore = score
                        bestPlayer = player
                        print(string.format("[Auto PVP] ✓ Match: %s | Level %s | Est DMG %s | Actual %s | Diff %s | Tolerance %s",
                            player.Name, tostring(level), tostring(estimatedDamage), tostring(damageTaken), tostring(diff), tostring(tolerance)))
                    end
                end
            end
        end
    end

    if bestPlayer then
        print("[Auto PVP] ✓ Selected: " .. bestPlayer.Name)
    else
        print("[Auto PVP] ✗ No attacker matched damage " .. tostring(damageTaken) .. " (checked " .. #Players:GetPlayers() .. " players)")
    end

    return bestPlayer
end

-- A target is only worth holding onto while the player still exists with a live character.
local function isTargetLive(target)
    if not target then return false end
    local char = target.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return char:FindFirstChild("HumanoidRootPart") ~= nil
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
            -- A dead bot has no valid engagement: drop the target, otherwise it stays locked across
            -- the respawn and the next hit says "already targeting <old name>" instead of engaging.
            if BotState.target then
                print("[Auto PVP] Dropping target " .. BotState.target.Name .. " because we died")
                BotState.target = nil
                BotState.target_last_y = nil
            end
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
            elseif targetRoot and characterInSafeZone(BotState.target.Character) then
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

            -- Stay locked onto the current target (don't switch on every new hit) - but only while
            -- that target is still real. A dead or vanished target used to hold this lock forever,
            -- which is how "already targeting X" printed while nothing was actually being engaged.
            if BotState.target and isTargetLive(BotState.target) then
                print("[Auto PVP] Already targeting " .. BotState.target.Name .. ", ignoring new attacker")
                lastHealthValue = health
                return
            elseif BotState.target then
                print("[Auto PVP] Previous target " .. BotState.target.Name .. " is no longer live - releasing the lock")
                BotState.target = nil
                BotState.target_last_y = nil
            end

            -- Only find new attacker if no target
            local attacker = findAttackerByDamage(damageTaken)
            if attacker and attacker.Character then
                local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
                local inSafeZone = characterInSafeZone(attacker.Character)

                if attackerRoot then
                    print("[Auto PVP] Attacker: " .. attacker.Name
                        .. " | Pos: X=" .. string.format("%.1f", attackerRoot.Position.X)
                        .. ", Z=" .. string.format("%.1f", attackerRoot.Position.Z)
                        .. " | In SafeZone: " .. tostring(inSafeZone)
                        .. zoneDebug(attackerRoot.Position))
                else
                    print("[Auto PVP] Attacker: " .. attacker.Name .. " has no HumanoidRootPart (streamed out?)")
                end

                -- Check if battle is winnable
                if not isWinnableBattle(attacker) then
                    print("[Auto PVP] " .. attacker.Name .. " is too strong, ignoring")
                    lastHealthValue = health
                    return
                end

                -- Check if in AutoZone (outside safe zone)
                if not isInAutoZone(attacker) then
                    -- Say WHY, because a missing character/root also lands here and used to be
                    -- reported as "is in safe zone".
                    local why = "is in the safe zone"
                    if not attacker.Character then
                        why = "has no character (streamed out?)"
                    elseif not attacker.Character:FindFirstChild("HumanoidRootPart") then
                        why = "has no HumanoidRootPart (streamed out?)"
                    end
                    print("[Auto PVP] Ignoring " .. attacker.Name .. " - " .. why)
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
        local ally = nil

        -- Optional: follow the clan's leader entry (its creator) instead of whoever is
        -- closest. Falls back to the nearest ally whenever the leader is unavailable.
        if BotState.follow_leader_enabled then
            local myTeamFolder = workspace.Teams and workspace.Teams:FindFirstChild(Config.ally_clan_name)
            local leaderName = getTeamLeaderName(myTeamFolder)
            if leaderName and leaderName ~= LocalPlayer.Name then
                ally = Players:FindFirstChild(leaderName)
            end
        end

        if not ally then
            ally = findClosestAlly()
        end

        if ally and ally.Character then
            local allyRoot = ally.Character:FindFirstChild("HumanoidRootPart")
            if allyRoot then
                local distToAlly = getDistance(root.Position, allyRoot.Position)

                -- Hysteresis: start closing past follow_ally_dist, keep closing until
                -- follow_ally_stop_dist, so it cannot stop/start on the threshold.
                if distToAlly > Config.follow_ally_dist then
                    BotState.follow_moving = true
                elseif distToAlly < Config.follow_ally_stop_dist then
                    BotState.follow_moving = false
                end

                if BotState.follow_moving then
                    -- moveTowardWithInterception picks keys relative to the CAMERA, so the
                    -- camera has to face the ally first or W/S/A/D push the wrong way.
                    aimCameraAtTarget(allyRoot)
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

    -- Aim camera at the combat target. The "or ally if following" branch that used to live
    -- here was unreachable: this code only runs when BotState.target is set (checked above),
    -- and following is handled before that gate in updateBotState().
    aimCameraAtTarget(targetRoot)

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

    -- Auto Sprint re-syncs every tick, with or without the combat bot running.
    syncSprint()

    -- Zone cube membership runs every tick too, so enter/leave is tracked even while idle.
    zoneTrackerTick()

    -- Follow Ally needs only its own toggle now: movement must not depend on the PVP bot
    -- having been started, which is exactly what used to gate it.
    if BotState.follow_ally_enabled and not BotState.target then
        BotState.current_state = "following"
        updateMovement()
        return
    end

    -- Target maintenance used to run ONLY from the HealthChanged handler, so a target that died
    -- while we were not being hit stayed locked in and blocked every later engagement. Poll it.
    if BotState.target then
        local myChar = LocalPlayer.Character
        local myHumanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
        if not myHumanoid or myHumanoid.Health <= 0 then
            print("[Auto PVP] We are dead or have no character - clearing target " .. BotState.target.Name)
            BotState.target = nil
            BotState.target_last_y = nil
        end
    end

    if BotState.target and not isTargetLive(BotState.target) then
        print("[Auto PVP] Target " .. BotState.target.Name .. " is no longer live - clearing")
        BotState.target = nil
        BotState.target_last_y = nil
        if not AutoPVPState.auto_reengage then
            _G.AdvancedPVPBot.stop()
        else
            print("[Auto PVP] Auto Re-engage ON: waiting for next attacker...")
        end
    end

    -- Nothing combat-related may run while OUR OWN character is inside the safe zone. Every
    -- existing check looked at the ally, the target or the attacker - never us - which is why
    -- Auto PVP kept going when you walked into the zone.
    if BotState.target then
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot and characterInSafeZone(myChar) then
            print("[Auto PVP] We are in the safe zone - dropping " .. tostring(BotState.target.Name) .. " and disengaging")
            BotState.target = nil
            BotState.target_last_y = nil
            releaseAllKeys()
        end
    end

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

    -- Auto item management. These are gated by their own toggles (useFood checks
    -- auto_eat_enabled, ensureFireballEquipped checks auto_fireball_enabled), so they must NOT sit
    -- behind BotState.enabled - that flag is combat-armed and is now only ever set automatically.
    ensureFireballEquipped()
    useFood()
end

local botLoop
_G.AdvancedPVPBot = {
    state = BotState,
    config = Config,
    autoPVP = AutoPVPState,

    start = function()
        if BotState.enabled then return end
        BotState.enabled = true
        -- The tick loop is created by buildUI; the shift key belongs to Auto Sprint now.
        if not botLoop then
            botLoop = RunService.Heartbeat:Connect(updateBotState)
        end
        print("[Advanced PVP Bot] Started")
    end,

    stop = function()
        BotState.enabled = false
        releaseAllKeys()
        print("[Advanced PVP Bot] Stopped (Auto Sprint untouched)")
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

-- ===== UI BUILDER =====

local function buildUI(ui)
    if not ui then
        error("[AnimalSim] UI object required from main.lua")
        return
    end

    print("[AnimalSim] Building game-specific pages...")

    -- Auto-detect safe zone when UI loads
    autoDetectSafeZone()

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

    -- Auto Eat and Auto Fireball used to be duplicated here as print-only toggles that set no state,
    -- which made it look like there were 2-3 of each. The working ones live in the Auto Items
    -- section (they set BotState.auto_eat_enabled / BotState.auto_fireball_enabled, which the tick
    -- actually reads), so the duplicates are gone. "Auto Fireball (Engaged)" - fireball only while
    -- engaged - was never implemented by anything.

    combatSection:addButton({
        title = "Damage Player",
        callback = function()
            print("[Combat] Damage info requested")
        end,
    })

    -- ===== PVP BOT SECTION =====
    local pvpBotSection = mainPage:addSection({title = "PVP Bot"})

    -- 'Enable PVP Bot' used to live here. Arming is automatic now: the damage path starts the bot
    -- when someone hits us, and AutoZone arms it when it engages. The loop itself always runs, so
    -- nothing needs a manual start button.

    pvpBotSection:addToggle({
        title = "Auto Sprint",
        toggled = false,
        callback = function(val)
            -- Real effect this time: "shift" is a toggle in this game. The old callback only
            -- set Config.approach_speed, which nothing ever read.
            BotState.auto_sprint_enabled = val
            print("[Auto Sprint]", val and "Enabled" or "Disabled")
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

    -- 'PVP Bot Target' dropdown used to live here. Targeting is done by the AutoZone Targets
    -- dropdown instead (plus the damage path, which picks whoever hit us).

    -- ===== AUTOZONE SECTION =====
    local autozoneSection = mainPage:addSection({title = "AutoZone"})

    autozoneSection:addToggle({
        title = "AutoZone Enabled",
        toggled = false,
        callback = function(val)
            BotState.autozone_enabled = val
            print("[AutoZone]", val and "Enabled (engage enemies near the ally you follow)" or "Disabled")
            if val then
                print("[AutoZone] Scope: " .. tostring(BotState.target_enemy_clan)
                    .. " | ally anchor: " .. (BotState.follow_ally_enabled and "on (stay near the ally you follow)" or "off (targets anywhere outside the safe zone)"))
            end
        end,
    })

    autozoneSection:addToggle({
        title = "Follow Ally",
        toggled = false,
        callback = function(val)
            BotState.follow_ally_enabled = val
            print("[Follow Ally]", val and "Enabled" or "Disabled")
            if val and not BotState.enabled then
                print("[Follow Ally] NOTE: the bot is not started - turn on 'Bot Enabled' or nothing will move")
            end
        end,
    })

    autozoneSection:addToggle({
        title = "Follow Leader (not nearest ally)",
        toggled = false,
        callback = function(val)
            BotState.follow_leader_enabled = val
            print("[Follow Ally]", val and "Targeting the clan leader" or "Targeting the nearest ally")
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
        table.insert(clans, "Any Target")
        return clans
    end

    local enemyClanDropdown = autozoneSection:addDropdown({
        title = "AutoZone Targets",
        list = getEnemyClanOptions(),
        callback = function(clanName)
            BotState.target_enemy_clan = clanName
            print("[AutoZone] Targets:", clanName)
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
        default = 20,
        precision = 0,
        callback = function(val)
            -- This has to write the key the follow logic actually reads. It used to set
            -- Config.autozone_ally_follow_dist, which nothing ever reads, so the slider
            -- did nothing at all.
            Config.follow_ally_dist = tonumber(val) or 20
            Config.autozone_ally_follow_dist = Config.follow_ally_dist
            print("[Follow Ally] Follow distance:", val)
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
            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myRoot then
                print("  YOU in safe zone:", isInsideSafeZone(myRoot.Position))
                print("  zone part:", SAFE_ZONE_OBJECT ~= nil and SAFE_ZONE_OBJECT.Name or "NOT FOUND", "| part counts as safe area:", ZONE_PART_IS_SAFE)
                print("  raw:" .. zoneDebug(myRoot.Position))
                print("  tracker says you are inside:", zoneTrackerHas(LocalPlayer))
                print("  maths (fallback) says you are inside:", isInsideSafeZone(myRoot.Position))
                print("  DECISION - what the bot actually uses:", characterInSafeZone(LocalPlayer.Character))
                if BotState.target then
                    print("  tracker says target " .. BotState.target.Name .. " is inside:", zoneTrackerHas(BotState.target))
                end
                local insideNames = {}
                for character in pairs(zoneInside) do
                    table.insert(insideNames, zoneLabel(character))
                end
                print("  zone cube sees inside:", #insideNames > 0 and table.concat(insideNames, ", ") or "nobody")
                if SAFE_ZONE_OBJECT then
                    print(string.format("  part centre: (%.1f, %.1f, %.1f)  size: (%.1f, %.1f, %.1f)  rotation: (%.1f, %.1f, %.1f)",
                        SAFE_ZONE_OBJECT.Position.X, SAFE_ZONE_OBJECT.Position.Y, SAFE_ZONE_OBJECT.Position.Z,
                        SAFE_ZONE_OBJECT.Size.X, SAFE_ZONE_OBJECT.Size.Y, SAFE_ZONE_OBJECT.Size.Z,
                        SAFE_ZONE_OBJECT.Orientation.X, SAFE_ZONE_OBJECT.Orientation.Y, SAFE_ZONE_OBJECT.Orientation.Z))
                end
            end
            print()
        end,
    })

    -- ===== HIT-TO-KILL SECTION =====
    local ratioSection = mainPage:addSection({title = "Hit-to-Kill Ratio"})

    ratioSection:addSlider({
        title = "Damage Multiplier",
        min = 0.1,
        max = 10,      -- the hit-to-kill ratio grows with (enemy level / your level)^2, so a 2x level
                       -- gap is already ~4.0 and a 3x gap ~9.0 - a max of 2 could only ever accept
                       -- fights against players close to your own level
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

    -- Kept as a switch because the part's name is actively misleading: it is called a fighting area
    -- but standing inside it is the safe zone (confirmed in game). ON = inside the part is safe.
    miscSection:addToggle({
        title = "Zone Part = Safe Area",
        toggled = ZONE_PART_IS_SAFE,
        callback = function(val)
            ZONE_PART_IS_SAFE = val
            print("[SafeZone] Zone part is now treated as:", val and "the SAFE area (inside = safe)" or "the ARENA (outside = safe)")
            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myRoot then
                print("[SafeZone] With you standing here: inSafeZone =", isInsideSafeZone(myRoot.Position))
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
            local myTeam = workspace.Teams and workspace.Teams:FindFirstChild(Config.ally_clan_name)
            print("  Leader: " .. tostring(getTeamLeaderName(myTeam)))
            print("\n[All Available Clans]")
            if workspace:FindFirstChild("Teams") then
                for _, teamFolder in ipairs(workspace.Teams:GetChildren()) do
                    local entries = teamFolder:GetChildren()
                    print("  • " .. teamFolder.Name .. "  (leader: " .. tostring(getTeamLeaderName(teamFolder)) .. ", " .. #entries .. " entries)")
                end
            else
                print("  ✗ No Teams folder found")
            end
            print("")
        end,
    })

    -- Own the tick loop here rather than inside the PVP bot: follow-ally and auto-sprint have
    -- to run whether or not the PVP bot was ever started.
    if not botLoop then
        botLoop = RunService.Heartbeat:Connect(updateBotState)
    end

    return ui
end

-- ===== INITIALIZATION =====
-- Store buildUI globally so main.lua can call it. Wrapped so that a loader which ALSO
-- calls the hook after we have self-built cannot create duplicate pages.
_G.buildAnimalSimUI = function(target)
    -- Keyed on the window itself rather than a plain boolean: a fresh run of the loader
    -- creates a fresh window, so re-running the script still builds. Only a second call
    -- with the SAME window (loader + self-build in one run) is skipped.
    if _G.__animalSimUIBuiltWindow == target then
        print("[Animal Sim v2] UI already built for this window - skipping duplicate build")
        return
    end
    _G.__animalSimUIBuiltWindow = target
    return buildUI(target)
end

print("[Animal Sim v2] Script loaded! Ready for UI injection.")

-- Some main.lua revisions download and execute this script but never call the hook above
-- (they only publish the window). Build directly in that case so the pages never go missing.
-- Lookup order: the argument main.lua hands over, then _G.venyx, then getgenv().venyx for
-- executors that give each script its own _G.
local window = ...
if window == nil then window = _G.venyx end
if window == nil and type(getgenv) == "function" then
    local genv = getgenv()
    if type(genv) == "table" then window = genv.venyx end
end

if window ~= nil then
    print("[Animal Sim v2] Window found - building pages directly")
    local ok, err = pcall(_G.buildAnimalSimUI, window)
    if not ok then
        print("[Animal Sim v2] ERROR building UI: " .. tostring(err))
    end
else
    print("[Animal Sim v2] No window yet - waiting for the loader to call buildAnimalSimUI(ui)")
end
