local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

--//AntiAFK Credits to: https://v3rmillion.net/showthread.php?tid=772135
local antiAfkConnection
local function ensureAntiAfk()
    if antiAfkConnection then
        return
    end
    antiAfkConnection = LocalPlayer.Idled:Connect(function()
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        VirtualUser:Button2Down(Vector2.new(0, 0), camera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), camera.CFrame)
    end)
end
ensureAntiAfk()
--//AntiAFK Credits to: https://v3rmillion.net/showthread.php?tid=772135

local DEFAULT_THEME = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255),
}

local LOG_PREFIX = "[RevampLoader]"
local ERROR_THRESHOLD = 6
local errorCount = 0
local lastRecovery = 0
local attemptRecovery -- forward declaration

local function logInfo(tag, message)
    print(string.format("%s %s: %s", LOG_PREFIX, tag, message))
end

local function handleError(tag, err)
    errorCount = errorCount + 1
    warn(string.format("%s %s error: %s", LOG_PREFIX, tag, tostring(err)))
    if errorCount >= ERROR_THRESHOLD and (tick() - lastRecovery) > 3 then
        lastRecovery = tick()
        errorCount = 0
        if attemptRecovery then
            attemptRecovery(tag, err)
        end
    end
end

local function safeCall(tag, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        handleError(tag, result)
        return nil
    end
    return result
end

local function safeConnect(signal, tag, handler)
    return signal:Connect(function(...)
        local ok, err = pcall(handler, ...)
        if not ok then
            handleError(tag, err)
        end
    end)
end

local function startLoop(tag, interval, fn)
    interval = interval or 0
    local running = true
    task.spawn(function()
        while running do
            local ok, err = pcall(fn)
            if not ok then
                handleError(tag, err)
            end
            if not running then
                break
            end
            if interval > 0 then
                task.wait(interval)
            else
                task.wait()
            end
        end
    end)
    return function()
        running = false
    end
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local movementDefaults = {
    walkSpeed = 16,
    jumpPower = 50,
    gravity = workspace.Gravity,
    fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70,
}

local movementState = {
    speedMultiplier = 1,
    jumpPower = movementDefaults.jumpPower,
    gravity = movementDefaults.gravity,
    fov = movementDefaults.fov,
}

local clickTeleportState = {
    enabled = false,
    connection = nil,
}

local infiniteJumpState = {
    enabled = false,
    connection = nil,
}

local flyState = {
    enabled = false,
    speed = 80,
    bodyVelocity = nil,
    bodyGyro = nil,
    inputBeganConn = nil,
    inputEndedConn = nil,
    heartbeatConn = nil,
    characterAddedConn = nil,
    controls = {
        forward = 0,
        backward = 0,
        left = 0,
        right = 0,
        up = 0,
        down = 0,
    },
}

local flyKeyMap = {
    [Enum.KeyCode.W] = "forward",
    [Enum.KeyCode.S] = "backward",
    [Enum.KeyCode.A] = "left",
    [Enum.KeyCode.D] = "right",
    [Enum.KeyCode.Space] = "up",
    [Enum.KeyCode.E] = "up",
    [Enum.KeyCode.LeftShift] = "down",
    [Enum.KeyCode.Q] = "down",
}

local visualState = {
    trailEnabled = false,
    trailInstances = {},
    rainbowEnabled = false,
    rainbowConnection = nil,
    rainbowOriginals = {},
    nightVisionEnabled = false,
    nightVisionSaved = nil,
    flashlightEnabled = false,
    flashlight = nil,
    flashlightConnection = nil,
    invisibleEnabled = false,
    invisibleOriginals = {},
}

local trickState = {
    ragdollEnabled = false,
    ragdollCache = {},
    followEnabled = false,
    followConnection = nil,
    fakeLagEnabled = false,
    fakeLagStop = nil,
    emoteLoopEnabled = false,
    emoteLoopStop = nil,
    bubbleSpamEnabled = false,
    bubbleSpamStop = nil,
}

local customAnimationState = {
    id = "",
    track = nil,
}

local utilitySelections = { teleportTarget = nil }
local statsState = {
    enabled = false,
    gui = nil,
    connection = nil,
}

local teleportDropdownModule
local savedLocations = {
    Slot1 = nil,
    Slot2 = nil,
    Slot3 = nil,
}

local freecamState = {
    enabled = false,
    cameraConnection = nil,
    inputBeganConn = nil,
    inputEndedConn = nil,
    scrollConn = nil,
    savedCameraType = nil,
    savedCameraSubject = nil,
    savedCameraCF = nil,
    moveVector = Vector3.new(),
    speed = 80,
}

local function setClickTeleport(enabled)
    if clickTeleportState.enabled == enabled then
        return
    end
    clickTeleportState.enabled = enabled

    if enabled then
        if clickTeleportState.connection then
            clickTeleportState.connection:Disconnect()
        end
        local mouse = LocalPlayer:GetMouse()
        clickTeleportState.connection = safeConnect(mouse.Button1Down, "ClickTeleport", function()
            if not clickTeleportState.enabled then
                return
            end
            if UserInputService:GetFocusedTextBox() then
                return
            end
            local hit = mouse.Hit
            if not hit then
                return
            end
            local targetPosition = hit.Position or hit.p
            if not targetPosition then
                return
            end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))
            end
        end)
    else
        if clickTeleportState.connection then
            clickTeleportState.connection:Disconnect()
            clickTeleportState.connection = nil
        end
    end
end

local function setInfiniteJump(enabled)
    if infiniteJumpState.enabled == enabled then
        return
    end
    infiniteJumpState.enabled = enabled

    if enabled then
        if infiniteJumpState.connection then
            infiniteJumpState.connection:Disconnect()
        end
        infiniteJumpState.connection = safeConnect(UserInputService.JumpRequest, "InfiniteJump", function()
            if not infiniteJumpState.enabled then
                return
            end
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    else
        if infiniteJumpState.connection then
            infiniteJumpState.connection:Disconnect()
            infiniteJumpState.connection = nil
        end
    end
end

local function updateMovementDefaultsFromHumanoid()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end
    local previousJump = movementDefaults.jumpPower
    movementDefaults.walkSpeed = humanoid.WalkSpeed
    if humanoid.UseJumpPower ~= false then
        movementDefaults.jumpPower = humanoid.JumpPower
    else
        movementDefaults.jumpPower = humanoid.JumpHeight
    end
    if movementState.jumpPower == previousJump then
        movementState.jumpPower = movementDefaults.jumpPower
    end
end

local function applyMovementSettings()
    local humanoid = getHumanoid()
    if humanoid then
        humanoid.WalkSpeed = movementDefaults.walkSpeed * movementState.speedMultiplier
        if humanoid.UseJumpPower ~= false then
            humanoid.JumpPower = movementState.jumpPower or movementDefaults.jumpPower
        else
            humanoid.JumpHeight = movementState.jumpPower or movementDefaults.jumpPower
        end
    end
    workspace.Gravity = movementState.gravity
    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = movementState.fov
    end
end

local function resetMovementSettings()
    movementState.speedMultiplier = 1
    movementState.jumpPower = movementDefaults.jumpPower
    movementState.gravity = movementDefaults.gravity
    movementState.fov = movementDefaults.fov
    applyMovementSettings()
end

local function setSpeedMultiplier(multiplier)
    movementState.speedMultiplier = math.clamp(multiplier, 0.1, 10)
    applyMovementSettings()
end

local function setJumpPower(value)
    movementState.jumpPower = math.clamp(value, 0, 1000)
    applyMovementSettings()
end

local function setGravity(value)
    movementState.gravity = math.clamp(value, 0, 1000)
    applyMovementSettings()
end

local function setFOV(value)
    movementState.fov = math.clamp(value, 40, 120)
    applyMovementSettings()
end

local function performDash()
    local root = getRootPart()
    if not root then
        return
    end
    local camera = workspace.CurrentCamera
    local direction = camera and camera.CFrame.LookVector or root.CFrame.LookVector
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bodyVelocity.Velocity = direction * 120
    bodyVelocity.Parent = root
    Debris:AddItem(bodyVelocity, 0.2)

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxassetid://241594419" -- spark texture
    emitter.Speed = NumberRange.new(12, 18)
    emitter.Lifetime = NumberRange.new(0.2, 0.4)
    emitter.Rate = 200
    emitter.EmissionDirection = Enum.NormalId.Front
    emitter.Parent = root
    Debris:AddItem(emitter, 0.2)
end

local function getCharacterParts()
    local character = getCharacter()
    if not character then
        return {}
    end
    local parts = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end
    return parts
end

local function updateTrailAttachments()
    local character = getCharacter()
    if not character then
        return
    end
    if not visualState.trailEnabled then
        return
    end
    if visualState.trailInstances.emitter and visualState.trailInstances.emitter.Parent then
        return
    end
    local root = getRootPart()
    if not root then
        return
    end
    local emitter = Instance.new("ParticleEmitter")
    emitter.LightInfluence = 0
    emitter.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 118, 203)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(118, 233, 255))
    }
    emitter.Speed = NumberRange.new(10, 15)
    emitter.Lifetime = NumberRange.new(0.3, 0.6)
    emitter.Rate = 120
    emitter.Rotation = NumberRange.new(-180, 180)
    emitter.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 0)
    }
    emitter.Parent = root
    visualState.trailInstances.emitter = emitter
end

local function setParticleTrailEnabled(value)
    visualState.trailEnabled = value
    if value then
        updateTrailAttachments()
    else
        for _, inst in pairs(visualState.trailInstances) do
            if typeof(inst) == "Instance" then
                inst:Destroy()
            end
        end
        visualState.trailInstances = {}
    end
end

local function stopRainbowCycle()
    if visualState.rainbowConnection then
        visualState.rainbowConnection:Disconnect()
        visualState.rainbowConnection = nil
    end
    if not visualState.rainbowOriginals then
        return
    end
    for part, color in pairs(visualState.rainbowOriginals) do
        if part and part.Parent then
            part.BrickColor = color
        end
    end
    visualState.rainbowOriginals = {}
end

local function setRainbowEnabled(value)
    if visualState.rainbowEnabled == value then
        if value and not visualState.rainbowConnection then
            -- reinitialise if connection was lost (e.g., character respawn)
        else
            return
        end
    end
    visualState.rainbowEnabled = value
    if value then
        stopRainbowCycle()
        visualState.rainbowOriginals = {}
        for _, part in ipairs(getCharacterParts()) do
            visualState.rainbowOriginals[part] = part.BrickColor
        end
        local startTick = tick()
        visualState.rainbowConnection = safeConnect(RunService.RenderStepped, "RainbowCycle", function()
            local hue = ((tick() - startTick) * 0.5) % 1
            local color = Color3.fromHSV(hue, 0.8, 1)
            for _, part in ipairs(getCharacterParts()) do
                part.Color = color
            end
        end)
    else
        stopRainbowCycle()
    end
end

local function setNightVisionEnabled(value)
    if visualState.nightVisionEnabled == value then
        return
    end
    visualState.nightVisionEnabled = value
    if value then
        visualState.nightVisionSaved = {
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            Brightness = Lighting.Brightness,
            ExposureCompensation = Lighting.ExposureCompensation,
        }
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 4
        Lighting.ExposureCompensation = 0.5
    else
        if visualState.nightVisionSaved then
            Lighting.Ambient = visualState.nightVisionSaved.Ambient
            Lighting.OutdoorAmbient = visualState.nightVisionSaved.OutdoorAmbient
            Lighting.Brightness = visualState.nightVisionSaved.Brightness
            Lighting.ExposureCompensation = visualState.nightVisionSaved.ExposureCompensation
        end
        visualState.nightVisionSaved = nil
    end
end

local function setFlashlightEnabled(value)
    visualState.flashlightEnabled = value
    if visualState.flashlight and visualState.flashlight.Parent then
        visualState.flashlight:Destroy()
        visualState.flashlight = nil
    end
    if value then
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        local light = Instance.new("PointLight")
        light.Range = 25
        light.Brightness = 4
        light.Color = Color3.fromRGB(255, 244, 214)
        light.Parent = camera
        visualState.flashlight = light
    end
end

local function setInvisibleEnabled(value)
    visualState.invisibleEnabled = value
    if value then
        visualState.invisibleOriginals = {}
        for _, part in ipairs(getCharacterParts()) do
            visualState.invisibleOriginals[part] = {
                Transparency = part.Transparency,
                LocalTransparencyModifier = part.LocalTransparencyModifier,
            }
            part.LocalTransparencyModifier = 1
        end
        local character = getCharacter()
        if character then
            for _, child in ipairs(character:GetDescendants()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    child.Transparency = 1
                end
            end
        end
    else
        for part, info in pairs(visualState.invisibleOriginals) do
            if part and part.Parent then
                part.LocalTransparencyModifier = info.LocalTransparencyModifier
                part.Transparency = info.Transparency
            end
        end
        visualState.invisibleOriginals = {}
        local character = getCharacter()
        if character then
            for _, child in ipairs(character:GetDescendants()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    child.Transparency = 0
                end
            end
        end
    end
end

local function resetVisualSettings()
    setParticleTrailEnabled(false)
    setRainbowEnabled(false)
    setNightVisionEnabled(false)
    setFlashlightEnabled(false)
    setInvisibleEnabled(false)
    setFOV(movementDefaults.fov)
end

local function spinCharacter()
    local root = getRootPart()
    if not root then
        return
    end
    local tween = TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = root.CFrame * CFrame.Angles(0, math.rad(360), 0),
    })
    tween:Play()
end

local function flipCharacter()
    local root = getRootPart()
    if not root then
        return
    end
    local tween = TweenService:Create(root, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = root.CFrame * CFrame.Angles(math.rad(360), 0, 0),
    })
    tween:Play()
end

local function setRagdollEnabled(value)
    trickState.ragdollEnabled = value
    local character = getCharacter()
    if not character then
        return
    end
    if value then
        trickState.ragdollCache = trickState.ragdollCache or {}
        for _, motor in ipairs(character:GetDescendants()) do
            if motor:IsA("Motor6D") then
                trickState.ragdollCache[motor] = motor.Enabled
                pcall(function()
                    motor.Enabled = false
                end)
            end
        end
        local humanoid = getHumanoid()
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
        end
    else
        for motor, enabled in pairs(trickState.ragdollCache or {}) do
            if motor and motor.Parent then
                pcall(function()
                    motor.Enabled = enabled ~= false
                end)
            end
        end
        trickState.ragdollCache = {}
        local humanoid = getHumanoid()
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
end

local function followClosestPlayerStep()
    if not trickState.followEnabled then
        return
    end
    local root = getRootPart()
    local humanoid = getHumanoid()
    if not (root and humanoid) then
        return
    end
    local closest
    local closestDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (player.Character.HumanoidRootPart.Position - root.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = player
            end
        end
    end
    if closest and closest.Character and closest.Character:FindFirstChild("HumanoidRootPart") then
        local targetPos = closest.Character.HumanoidRootPart.Position
        humanoid:MoveTo(targetPos)
    end
end

local function setFollowClosestPlayerEnabled(value)
    if trickState.followEnabled == value then
        return
    end
    trickState.followEnabled = value
    if value then
        if trickState.followConnection then
            trickState.followConnection:Disconnect()
        end
        trickState.followConnection = safeConnect(RunService.Heartbeat, "FollowClosestPlayer", followClosestPlayerStep)
    else
        if trickState.followConnection then
            trickState.followConnection:Disconnect()
            trickState.followConnection = nil
        end
        local humanoid = getHumanoid()
        if humanoid then
            humanoid:Move(Vector3.new())
        end
    end
end

local function setFakeLagEnabled(value)
    trickState.fakeLagEnabled = value
    if value then
        if trickState.fakeLagStop then
            trickState.fakeLagStop()
        end
        trickState.fakeLagStop = startLoop("FakeLag", 0, function()
            local root = getRootPart()
            if root then
                root.Anchored = true
            end
            task.wait(math.random(5, 15) / 100)
            if root then
                root.Anchored = false
            end
            task.wait(math.random(8, 20) / 100)
        end)
    else
        if trickState.fakeLagStop then
            trickState.fakeLagStop()
            trickState.fakeLagStop = nil
        end
        local root = getRootPart()
        if root then
            root.Anchored = false
        end
    end
end

local emotesList = { "wave", "cheer", "dance", "dance2", "dance3", "backflip", "floss" }
local bubblePhrases = { "Wow!", "LOL", "???", "bruh", "Catch me if you can!", "Zzz..." }

local function playRandomDance()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end
    local emote = emotesList and emotesList[math.random(1, #emotesList)]
    pcall(function()
        humanoid:PlayEmote(emote)
    end)
end

local function setEmoteLoopEnabled(value)
    trickState.emoteLoopEnabled = value
    if value then
        if trickState.emoteLoopStop then
            trickState.emoteLoopStop()
        end
        trickState.emoteLoopStop = startLoop("EmoteLoop", 0, function()
            playRandomDance()
            task.wait(5)
        end)
    else
        if trickState.emoteLoopStop then
            trickState.emoteLoopStop()
            trickState.emoteLoopStop = nil
        end
    end
end

local function setBubbleSpamEnabled(value)
    trickState.bubbleSpamEnabled = value
    if value then
        if trickState.bubbleSpamStop then
            trickState.bubbleSpamStop()
        end
        trickState.bubbleSpamStop = startLoop("BubbleSpam", 0, function()
            pcall(function()
                StarterGui:SetCore("ChatMakeSystemMessage", {
                    Text = bubblePhrases[math.random(1, #bubblePhrases)],
                    Color = Color3.fromHSV(math.random(), 0.7, 1),
                    Font = Enum.Font.GothamBold,
                })
            end)
            task.wait(1.5)
        end)
    else
        if trickState.bubbleSpamStop then
            trickState.bubbleSpamStop()
            trickState.bubbleSpamStop = nil
        end
    end
end

local function setCustomAnimationId(value)
    local sanitized = tostring(value or ""):match("%d+")
    customAnimationState.id = sanitized or ""
end

local function stopCustomAnimation()
    if customAnimationState.track then
        pcall(function()
            customAnimationState.track:Stop()
            customAnimationState.track:Destroy()
        end)
        customAnimationState.track = nil
    end
end

local function playCustomAnimation()
    if customAnimationState.id == "" then
        warn("[CustomAnimation] No animation id provided")
        return
    end
    stopCustomAnimation()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end
    local productInfo
    local okProduct, productResult = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(tonumber(customAnimationState.id) or 0, Enum.InfoType.Asset)
    end)
    if okProduct then
        productInfo = productResult
    else
        warn(("[CustomAnimation] Unable to fetch asset info (%s)"):format(tostring(productResult)))
    end
    if productInfo and productInfo.AssetTypeId == Enum.AssetType.Emote.Value then
        local okEmote, emoteResult = pcall(function()
            return humanoid:PlayEmote(productInfo.Name or tostring(customAnimationState.id))
        end)
        if okEmote and emoteResult ~= false then
            -- Humanoid:PlayEmote succeeded or yielded a truthy result.
            return
        end
        warn(("[CustomAnimation] Asset %s is an Emote; PlayEmote failed or not owned (%s)"):format(customAnimationState.id, tostring(emoteResult)))
        -- fall through to try as animation id anyway
    elseif productInfo and productInfo.AssetTypeId ~= Enum.AssetType.Animation.Value then
        warn(("[CustomAnimation] Asset %s is not an Animation (type %s)"):format(customAnimationState.id, tostring(productInfo.AssetTypeId)))
        return
    end
    local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    local animation = Instance.new("Animation")
    animation.AnimationId = ("rbxassetid://%s"):format(customAnimationState.id)
    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if ok and trackOrErr then
        local track = trackOrErr
        customAnimationState.track = track
        track:Play()
    else
        warn(("[CustomAnimation] Failed to load animation with sanitized ID rbxassetid://%s: %s"):format(customAnimationState.id, tostring(trackOrErr)))
    end
end

local function cloneCharacterDummy()
    local character = getCharacter()
    if not character then
        return
    end
    local clone = character:Clone()
    for _, humanoid in ipairs(clone:GetDescendants()) do
        if humanoid:IsA("Humanoid") or humanoid:IsA("Animator") then
            humanoid:Destroy()
        end
    end
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
        end
    end
    clone.Parent = workspace
    Debris:AddItem(clone, 30)
end

local function setStatsEnabled(value)
    statsState.enabled = value
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        or LocalPlayer:FindFirstChild("PlayerGui")
        or (function()
            local ok, result = pcall(function()
                return LocalPlayer:WaitForChild("PlayerGui", 2)
            end)
            if ok then
                return result
            end
            return nil
        end)()
    if not playerGui then
        return
    end
    if value then
        if statsState.gui then
            statsState.gui:Destroy()
        end
        local gui = Instance.new("ScreenGui")
        gui.Name = "RevampStatsDisplay"
        gui.ResetOnSpawn = false
        gui.Parent = playerGui

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0, 200, 0, 50)
        label.Position = UDim2.new(0, 20, 0, 20)
        label.BackgroundTransparency = 0.5
        label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.Text = "FPS: --\nPing: --"
        label.Parent = gui

        statsState.gui = gui

        local lastSample = tick()
        local frameCounter = 0
        if statsState.connection then
            statsState.connection:Disconnect()
        end
        statsState.connection = safeConnect(RunService.RenderStepped, "StatsOverlay", function()
            frameCounter = frameCounter + 1
            local now = tick()
            if now - lastSample >= 0.5 then
                local fps = math.floor(frameCounter / (now - lastSample))
                frameCounter = 0
                lastSample = now
                local ping = math.floor(Stats and Stats.Network and Stats.Network.ServerStatsItem["Data Ping"] and Stats.Network.ServerStatsItem["Data Ping"]:GetValue() or 0)
                label.Text = ("FPS: %s\nPing: %sms"):format(fps, ping)
            end
        end)
    else
        if statsState.connection then
            statsState.connection:Disconnect()
            statsState.connection = nil
        end
        if statsState.gui then
            statsState.gui:Destroy()
            statsState.gui = nil
        end
    end
end

local function collectPlayerNames()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    table.sort(names)
    return names
end

local function refreshTeleportDropdown()
    local names = collectPlayerNames()
    if utilitySelections.teleportTarget and not table.find(names, utilitySelections.teleportTarget) then
        utilitySelections.teleportTarget = nil
    end
    if teleportDropdownModule and teleportDropdownModule.Options and teleportDropdownModule.Options.Update then
        teleportDropdownModule.Options:Update({
            list = names,
        })
    end
end

local function teleportToPlayer(name)
    if not name or name == "" then
        return
    end
    local player = Players:FindFirstChild(name)
    if not player or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return
    end
    local root = getRootPart()
    if root then
        root.CFrame = player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -3)
    end
end

local function saveLocation(slot)
    local root = getRootPart()
    if root then
        savedLocations[slot] = root.CFrame
        pcall(function()
            StarterGui:SetCore("ChatMakeSystemMessage", {
                Text = ("Saved location %s"):format(slot),
                Color = Color3.fromRGB(120, 209, 255),
            })
        end)
    end
end

local function teleportToSavedLocation(slot)
    local cframe = savedLocations[slot]
    if cframe then
        local root = getRootPart()
        if root then
            root.CFrame = cframe
        end
    end
end

local function setFreecamEnabled(value)
    if freecamState.enabled == value then
        return
    end
    freecamState.enabled = value

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    if value then
        freecamState.moveVector = Vector3.new()
        freecamState.speed = 80
        freecamState.savedCameraType = camera.CameraType
        freecamState.savedCameraSubject = camera.CameraSubject
        freecamState.savedCameraCF = camera.CFrame
        camera.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false

        local cameraCF = camera.CFrame
        local position = cameraCF.Position
        local pitch, yaw = cameraCF:ToEulerAnglesYXZ()

        if freecamState.cameraConnection then
            freecamState.cameraConnection:Disconnect()
        end
        freecamState.cameraConnection = safeConnect(RunService.RenderStepped, "FreecamStep", function(dt)
            local move = freecamState.moveVector
            if move.Magnitude > 0 then
                move = move.Unit * freecamState.speed * dt
                local lookVector = Vector3.new(math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw))
                local rightVector = Vector3.new(math.sin(yaw - math.pi/2), 0, math.cos(yaw - math.pi/2))
                local upVector = Vector3.new(0, 1, 0)
                position = position + (lookVector * move.Z) + (rightVector * move.X) + (upVector * move.Y)
            end
            camera.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
        end)

        local function setMove(dir, value)
            if dir == "forward" then
                freecamState.moveVector = Vector3.new(freecamState.moveVector.X, freecamState.moveVector.Y, value)
            elseif dir == "backward" then
                freecamState.moveVector = Vector3.new(freecamState.moveVector.X, freecamState.moveVector.Y, -value)
            elseif dir == "left" then
                freecamState.moveVector = Vector3.new(-value, freecamState.moveVector.Y, freecamState.moveVector.Z)
            elseif dir == "right" then
                freecamState.moveVector = Vector3.new(value, freecamState.moveVector.Y, freecamState.moveVector.Z)
            elseif dir == "up" then
                freecamState.moveVector = Vector3.new(freecamState.moveVector.X, value, freecamState.moveVector.Z)
            elseif dir == "down" then
                freecamState.moveVector = Vector3.new(freecamState.moveVector.X, -value, freecamState.moveVector.Z)
            end
        end

        if freecamState.inputBeganConn then
            freecamState.inputBeganConn:Disconnect()
        end
        freecamState.inputBeganConn = safeConnect(UserInputService.InputBegan, "FreecamInputBegan", function(input, gameProcessed)
            if gameProcessed then
                return
            end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.W then setMove("forward", 1) end
                if input.KeyCode == Enum.KeyCode.S then setMove("backward", 1) end
                if input.KeyCode == Enum.KeyCode.A then setMove("left", 1) end
                if input.KeyCode == Enum.KeyCode.D then setMove("right", 1) end
                if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then setMove("up", 1) end
                if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftShift then setMove("down", 1) end
            end
        end)

        if freecamState.inputEndedConn then
            freecamState.inputEndedConn:Disconnect()
        end
        freecamState.inputEndedConn = safeConnect(UserInputService.InputEnded, "FreecamInputEnded", function(input)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.W then setMove("forward", 0) end
                if input.KeyCode == Enum.KeyCode.S then setMove("backward", 0) end
                if input.KeyCode == Enum.KeyCode.A then setMove("left", 0) end
                if input.KeyCode == Enum.KeyCode.D then setMove("right", 0) end
                if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then setMove("up", 0) end
                if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftShift then setMove("down", 0) end
            end
        end)

        if freecamState.scrollConn then
            freecamState.scrollConn:Disconnect()
        end
        freecamState.scrollConn = safeConnect(UserInputService.InputChanged, "FreecamInputChanged", function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Delta
                yaw = yaw - delta.X * 0.002
                pitch = math.clamp(pitch - delta.Y * 0.002, -1.2, 1.2)
            elseif input.UserInputType == Enum.UserInputType.MouseWheel then
                freecamState.speed = math.clamp(freecamState.speed + input.Position.Z * 5, 10, 500)
            end
        end)
    else
        if freecamState.cameraConnection then
            freecamState.cameraConnection:Disconnect()
            freecamState.cameraConnection = nil
        end
        if freecamState.inputBeganConn then
            freecamState.inputBeganConn:Disconnect()
            freecamState.inputBeganConn = nil
        end
        if freecamState.inputEndedConn then
            freecamState.inputEndedConn:Disconnect()
            freecamState.inputEndedConn = nil
        end
        if freecamState.scrollConn then
            freecamState.scrollConn:Disconnect()
            freecamState.scrollConn = nil
        end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
        if freecamState.savedCameraType then
            camera.CameraType = freecamState.savedCameraType
        end
        if freecamState.savedCameraSubject then
            camera.CameraSubject = freecamState.savedCameraSubject
        end
        if freecamState.savedCameraCF then
            camera.CFrame = freecamState.savedCameraCF
        end
        freecamState.moveVector = Vector3.new()
        freecamState.speed = 80
    end
end

local function resetFlyControls()
    for key in pairs(flyState.controls) do
        flyState.controls[key] = 0
    end
end

local function destroyFlyBodies(restoreStand)
    if flyState.bodyVelocity then
        flyState.bodyVelocity:Destroy()
        flyState.bodyVelocity = nil
    end
    if flyState.bodyGyro then
        flyState.bodyGyro:Destroy()
        flyState.bodyGyro = nil
    end
    if restoreStand then
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
        end
    end
end

local function applyFlyToCharacter(character)
    destroyFlyBodies(false)
    character = character or LocalPlayer.Character
    if not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.PlatformStand = true
    end
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = Vector3.new()
    bodyVelocity.Parent = root
    flyState.bodyVelocity = bodyVelocity

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.P = 10000
    bodyGyro.Parent = root
    flyState.bodyGyro = bodyGyro
end

local function updateFlyVelocity()
    if not flyState.enabled then
        return
    end
    local bodyVelocity = flyState.bodyVelocity
    local bodyGyro = flyState.bodyGyro
    if not (bodyVelocity and bodyVelocity.Parent and bodyGyro and bodyGyro.Parent) then
        return
    end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera
    if not (root and camera) then
        return
    end

    local forward = flyState.controls.forward - flyState.controls.backward
    local right = flyState.controls.right - flyState.controls.left
    local up = flyState.controls.up - flyState.controls.down

    local move = Vector3.new()
    if math.abs(forward) > 0 then
        move = move + camera.CFrame.LookVector * forward
    end
    if math.abs(right) > 0 then
        move = move + camera.CFrame.RightVector * right
    end
    if math.abs(up) > 0 then
        move = move + Vector3.new(0, up, 0)
    end

    if move.Magnitude > 0 then
        move = move.Unit
    end

    bodyVelocity.Velocity = move * flyState.speed
    bodyGyro.CFrame = CFrame.new(root.Position, root.Position + camera.CFrame.LookVector)
end

local function setFlyEnabled(enabled)
    if flyState.enabled == enabled then
        return
    end

    flyState.enabled = enabled
    if enabled then
        resetFlyControls()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        applyFlyToCharacter(character)

        if flyState.heartbeatConn then
            flyState.heartbeatConn:Disconnect()
        end
        flyState.heartbeatConn = safeConnect(RunService.RenderStepped, "FlyStep", updateFlyVelocity)

        if flyState.inputBeganConn then
            flyState.inputBeganConn:Disconnect()
        end
        flyState.inputBeganConn = safeConnect(UserInputService.InputBegan, "FlyInputBegan", function(input, gameProcessed)
            if not flyState.enabled or gameProcessed then
                return
            end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local control = flyKeyMap[input.KeyCode]
                if control then
                    flyState.controls[control] = 1
                    updateFlyVelocity()
                end
            end
        end)

        if flyState.inputEndedConn then
            flyState.inputEndedConn:Disconnect()
        end
        flyState.inputEndedConn = safeConnect(UserInputService.InputEnded, "FlyInputEnded", function(input)
            if not flyState.enabled then
                return
            end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local control = flyKeyMap[input.KeyCode]
                if control then
                    flyState.controls[control] = 0
                    updateFlyVelocity()
                end
            end
        end)

        if not flyState.characterAddedConn then
            flyState.characterAddedConn = safeConnect(LocalPlayer.CharacterAdded, "FlyCharacterAdded", function(newCharacter)
                if flyState.enabled then
                    task.wait(0.2)
                    applyFlyToCharacter(newCharacter)
                    updateFlyVelocity()
                end
            end)
        end

        updateFlyVelocity()
    else
        if flyState.inputBeganConn then
            flyState.inputBeganConn:Disconnect()
            flyState.inputBeganConn = nil
        end
        if flyState.inputEndedConn then
            flyState.inputEndedConn:Disconnect()
            flyState.inputEndedConn = nil
        end
        if flyState.heartbeatConn then
            flyState.heartbeatConn:Disconnect()
            flyState.heartbeatConn = nil
        end
        destroyFlyBodies(true)
        resetFlyControls()
    end
end

local function addMiscPage(ui)
    local miscPage = ui:addPage({title = "Misc"})
    local movementSection = miscPage:addSection({title = "Movement"})

    movementSection:addToggle({
        title = "Click Teleport",
        default = false,
        callback = setClickTeleport,
    })

    movementSection:addToggle({
        title = "Fly",
        default = false,
        callback = setFlyEnabled,
    })

    movementSection:addSlider({
        title = "Fly Speed",
        min = 10,
        max = 200,
        precision = 0,
        default = flyState.speed,
        callback = function(value)
            local numeric = tonumber(value) or value
            if typeof(numeric) == "number" then
                flyState.speed = numeric
                updateFlyVelocity()
            end
        end,
    })

    movementSection:addToggle({
        title = "Infinite Jump",
        default = false,
        callback = setInfiniteJump,
    })

    movementSection:addSlider({
        title = "Speed Multiplier",
        min = 0.1,
        max = 6,
        precision = 2,
        default = movementState.speedMultiplier,
        callback = function(value)
            setSpeedMultiplier(tonumber(value) or movementState.speedMultiplier)
        end,
    })

    movementSection:addSlider({
        title = "Jump Power",
        min = 0,
        max = 300,
        precision = 0,
        default = movementDefaults.jumpPower,
        callback = function(value)
            setJumpPower(tonumber(value) or movementState.jumpPower)
        end,
    })

    movementSection:addSlider({
        title = "Gravity",
        min = 0,
        max = 400,
        precision = 0,
        default = movementDefaults.gravity,
        callback = function(value)
            setGravity(tonumber(value) or movementState.gravity)
        end,
    })

    movementSection:addSlider({
        title = "Field of View",
        min = 40,
        max = 120,
        precision = 0,
        default = movementState.fov,
        callback = function(value)
            setFOV(tonumber(value) or movementState.fov)
        end,
    })

    movementSection:addButton({
        title = "Dash Forward",
        callback = performDash,
    })

    movementSection:addButton({
        title = "Reset Movement",
        callback = resetMovementSettings,
    })

    local utilitySection = miscPage:addSection({title = "Utilities"})
    utilitySection:addButton({
        title = "Reset Character",
        callback = function()
            local character = LocalPlayer.Character
            if character then
                local root = character:FindFirstChild("HumanoidRootPart")
                if root then
                    local emitter = Instance.new("ParticleEmitter")
                    emitter.Texture = "rbxassetid://301880916"
                    emitter.Speed = NumberRange.new(15, 25)
                    emitter.Lifetime = NumberRange.new(0.4, 0.6)
                    emitter.Rate = 200
                    emitter.SpreadAngle = Vector2.new(360, 360)
                    emitter.Parent = root
                    Debris:AddItem(emitter, 0.4)
                end
                character:BreakJoints()
            end
        end,
    })

    return miscPage
end

local function addVisualPage(ui)
    local visualPage = ui:addPage({title = "Visuals"})
    local effectsSection = visualPage:addSection({title = "Effects"})

    effectsSection:addToggle({
        title = "Particle Trail",
        default = false,
        callback = setParticleTrailEnabled,
    })

    effectsSection:addToggle({
        title = "Rainbow Character",
        default = false,
        callback = setRainbowEnabled,
    })

    effectsSection:addToggle({
        title = "Night Vision",
        default = false,
        callback = setNightVisionEnabled,
    })

    effectsSection:addToggle({
        title = "Flashlight Mode",
        default = false,
        callback = setFlashlightEnabled,
    })

    effectsSection:addToggle({
        title = "Invisible Character",
        default = false,
        callback = setInvisibleEnabled,
    })

    effectsSection:addButton({
        title = "Reset Visuals",
        callback = resetVisualSettings,
    })

    return visualPage
end

local function addTricksPage(ui)
    local tricksPage = ui:addPage({title = "Tricks"})
    local tricksSection = tricksPage:addSection({title = "Moves"})

    tricksSection:addButton({
        title = "Spin",
        callback = spinCharacter,
    })

    tricksSection:addButton({
        title = "Flip",
        callback = flipCharacter,
    })

    tricksSection:addButton({
        title = "Sit Anywhere",
        callback = function()
            local humanoid = getHumanoid()
            if humanoid then
                humanoid.Sit = true
            end
        end,
    })

    tricksSection:addToggle({
        title = "Ragdoll",
        default = false,
        callback = setRagdollEnabled,
    })

    tricksSection:addToggle({
        title = "Follow Closest Player",
        default = false,
        callback = setFollowClosestPlayerEnabled,
    })

    tricksSection:addToggle({
        title = "Fake Lag",
        default = false,
        callback = setFakeLagEnabled,
    })

    local customAnimationSection = tricksPage:addSection({title = "Custom Animation"})

    customAnimationSection:addTextbox({
        title = "Animation Asset ID",
        default = "Paste animation id",
        callback = function(value, focusLost)
            if not focusLost then
                return
            end
            setCustomAnimationId(value)
        end,
    })

    customAnimationSection:addButton({
        title = "Play Animation",
        callback = playCustomAnimation,
    })

    customAnimationSection:addButton({
        title = "Stop Animation",
        callback = stopCustomAnimation,
    })

    return tricksPage
end

local function addUtilityPage(ui)
    local utilityPage = ui:addPage({title = "Utilities"})
    local statsSection = utilityPage:addSection({title = "Diagnostics"})

    statsSection:addToggle({
        title = "Show FPS/Ping",
        default = false,
        callback = setStatsEnabled,
    })

    local teleportSection = utilityPage:addSection({title = "Teleport"})

    teleportDropdownModule = teleportSection:addDropdown({
        title = "Target Player",
        list = collectPlayerNames(),
        callback = function(playerName)
            utilitySelections.teleportTarget = playerName
        end,
    })

    teleportSection:addButton({
        title = "Teleport to Selected",
        callback = function()
            teleportToPlayer(utilitySelections.teleportTarget)
        end,
    })

    teleportSection:addButton({
        title = "Refresh Player List",
        callback = function()
            refreshTeleportDropdown()
        end,
    })

    local locationSection = utilityPage:addSection({title = "Saved Locations"})
    for index = 1, 3 do
        locationSection:addButton({
            title = ("Save Slot %d"):format(index),
            callback = function()
                saveLocation("Slot" .. index)
            end,
        })
        locationSection:addButton({
            title = ("Teleport Slot %d"):format(index),
            callback = function()
                teleportToSavedLocation("Slot" .. index)
            end,
        })
    end

    local cameraSection = utilityPage:addSection({title = "Camera"})
    cameraSection:addToggle({
        title = "Freecam Mode",
        default = false,
        callback = setFreecamEnabled,
    })

    return utilityPage
end

local function addFunPage(ui)
    local funPage = ui:addPage({title = "Fun"})
    local funSection = funPage:addSection({title = "Party Tricks"})

    funSection:addButton({
        title = "Clone Me",
        callback = cloneCharacterDummy,
    })

    funSection:addButton({
        title = "Random Dance",
        callback = playRandomDance,
    })

    funSection:addToggle({
        title = "Emote Loop",
        default = false,
        callback = setEmoteLoopEnabled,
    })

    funSection:addToggle({
        title = "Bubble Chat Spam",
        default = false,
        callback = setBubbleSpamEnabled,
    })

    return funPage
end

attemptRecovery = function(tag, err)
    logInfo("Recovery", string.format("Attempting recovery after %s (%s)", tostring(tag), tostring(err)))
    setClickTeleport(false)
    setInfiniteJump(false)
    setFlyEnabled(false)
    resetVisualSettings()
    setFollowClosestPlayerEnabled(false)
    setFakeLagEnabled(false)
    setEmoteLoopEnabled(false)
    setBubbleSpamEnabled(false)
    setFreecamEnabled(false)
    stopCustomAnimation()
    if statsState.enabled then
        setStatsEnabled(false)
    end
    resetMovementSettings()
end

local function reapplyCharacterStates()
    updateMovementDefaultsFromHumanoid()
    applyMovementSettings()
    if clickTeleportState.enabled then
        setClickTeleport(true)
    end
    if infiniteJumpState.enabled then
        setInfiniteJump(true)
    end
    if flyState.enabled then
        applyFlyToCharacter(getCharacter())
    end
    if visualState.trailEnabled then
        setParticleTrailEnabled(true)
    end
    if visualState.rainbowEnabled then
        setRainbowEnabled(true)
    end
    if visualState.invisibleEnabled then
        setInvisibleEnabled(true)
    end
    if visualState.flashlightEnabled then
        setFlashlightEnabled(true)
    end
    if trickState.ragdollEnabled then
        setRagdollEnabled(true)
    end
end

safeConnect(Players.PlayerAdded, "PlayerAdded", function()
    refreshTeleportDropdown()
end)

safeConnect(Players.PlayerRemoving, "PlayerRemoving", function()
    refreshTeleportDropdown()
end)

safeConnect(LocalPlayer.CharacterAdded, "ReapplyStates", function()
    stopCustomAnimation()
    task.defer(reapplyCharacterStates)
end)

local function applyThemeDefaults(library, defaults)
    local source = defaults or DEFAULT_THEME
    local palette = {}
    for themeName, color in pairs(source) do
        palette[themeName] = color
        local ok, err = pcall(function()
            library:setTheme(themeName, color)
        end)
        if not ok then
            warn(("[Loader] Failed to apply theme '%s': %s"):format(tostring(themeName), tostring(err)))
        end
    end
    return palette
end

local function addThemePage(library, ui, defaults)
    local source = defaults or DEFAULT_THEME
    local palette = {}
    for themeName, color in pairs(source) do
        palette[themeName] = color
    end

    local themePage = ui:addPage({title = "Theme"})
    local colorsSection = themePage:addSection({title = "Colors"})
    for themeName, color in pairs(palette) do
        colorsSection:addColorPicker({
            title = themeName,
            default = color,
            callback = function(newColor)
                library:setTheme(themeName, newColor)
            end,
        })
    end

    applyThemeDefaults(library, palette)
    return themePage
end

local placeID = game.PlaceId
local url = ("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/%s.lua"):format(placeID)

local success, response = pcall(function()
    return game:HttpGet(url)
end)

print(("[Loader] Loading script for placeID: %s - Success: %s"):format(placeID, tostring(success)))

if success and response and response ~= "" then
    local moduleTable = loadstring(response)()
    local initResult
    if type(moduleTable) == "table" and type(moduleTable.init) == "function" then
        initResult = moduleTable.init()
    end

    if initResult and initResult.ui and initResult.library then
        local ui = initResult.ui
        local library = initResult.library

        local themeDefaults = initResult.defaultTheme
            or (initResult.module and initResult.module.UI and initResult.module.UI.defaults and initResult.module.UI.defaults.theme)
            or DEFAULT_THEME

        updateMovementDefaultsFromHumanoid()
        movementDefaults.gravity = workspace.Gravity
        movementDefaults.fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or movementDefaults.fov
        movementState.gravity = movementDefaults.gravity
        movementState.fov = movementDefaults.fov
        addMiscPage(ui)
        addVisualPage(ui)
        addTricksPage(ui)
        addUtilityPage(ui)
        addFunPage(ui)
        addThemePage(library, ui, themeDefaults)
        refreshTeleportDropdown()
        reapplyCharacterStates()
        local defaultPage = initResult.defaultPageIndex or 1
        local ok = pcall(function()
            ui:SelectPage(defaultPage)
        end)
        if not ok and type(defaultPage) == "number" then
            local pages = ui.Pages or ui.pages or ui.tabs or ui.Tabs
            local pageObject = type(pages) == "table" and pages[defaultPage] or nil
            if pageObject then
                pcall(function()
                    ui:SelectPage(pageObject)
                end)
            end
        end
    end

    print("Done")
else
    warn("[Loader] Failed to load script for placeID:", placeID)
end
