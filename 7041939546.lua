--[[
    Catalog Creator helper (PlaceId 7041939546)
    Features:
      - Select any player in the server and teleport directly to their HumanoidRootPart.
      - Optional Attach toggle keeps your character glued to the target CFrame each frame.
      - Tool spam toggle repeatedly activates the currently equipped tool (re-equips from backpack if needed).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local CatalogCreator = {
    PlaceId = 7041939546,
    State = {
        targetPlayer = nil,
        attachEnabled = false,
        toolSpamEnabled = false,
    },
    UI = {
        instances = {},
    },
}

local attachConnection
local toolSpamThread
local playerListenerConnection
local dropdownUpdateDebounce = 0
local playerRemovingConnection

local function copyMotorTransforms(sourceCharacter, destinationCharacter)
	if not (sourceCharacter and destinationCharacter) then return end

	local sourceMotors = {}
	for _, m in ipairs(sourceCharacter:GetDescendants()) do
		if m:IsA("Motor6D") then
			sourceMotors[m.Name] = m
		end
	end

	for _, m in ipairs(destinationCharacter:GetDescendants()) do
		if m:IsA("Motor6D") and sourceMotors[m.Name] then
			local sm = sourceMotors[m.Name]
			-- Copy current animation pose by matching joint CFrames
			local newC0 = sm.C0 * sm.Transform
			m.C0 = newC0
			m.C1 = sm.C1
		end
	end
end


local function getCharacter(player)
    player = player or LocalPlayer
    return player and player.Character
end

local function getHumanoid(player)
    local character = getCharacter(player)
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(player)
    local character = getCharacter(player)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function playerList()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(list, player.Name)
        end
    end
    table.sort(list)
    return list
end

local function resolveTarget(name)
    if not name or name == "" then
        return nil
    end
    return Players:FindFirstChild(name)
end

local function teleportToTarget()
    local target = CatalogCreator.State.targetPlayer
    if not target then
        warn("[CatalogCreator] No target selected for teleport.")
        return false
    end

    local targetRoot = getRootPart(target)
    local localRoot = getRootPart(LocalPlayer)
    if not (targetRoot and localRoot) then
        warn("[CatalogCreator] Missing root part for teleport.")
        return false
    end

    localRoot.CFrame = targetRoot.CFrame
    localRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
    localRoot.AssemblyAngularVelocity = targetRoot.AssemblyAngularVelocity

    return true
end

local function stopAttachLoop()
    if attachConnection then
        attachConnection:Disconnect()
        attachConnection = nil
    end
end

local function startAttachLoop()
    if attachConnection then
        attachConnection:Disconnect()
        attachConnection = nil
    end
    CatalogCreator.State.attachEnabled = true
    attachConnection = RunService.Heartbeat:Connect(function()
        local target = CatalogCreator.State.targetPlayer
        if not (CatalogCreator.State.attachEnabled and target and target.Parent) then
            local localHumanoid = getHumanoid(LocalPlayer)
            if localHumanoid then
                localHumanoid.PlatformStand = false
            end
            return
        end

        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local localCharacter = getCharacter(LocalPlayer)
        local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
        local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")

        if not (targetRoot and localRoot) then
            if localHumanoid then
                localHumanoid.PlatformStand = false
            end
            return
        end

        localRoot.CFrame = targetRoot.CFrame
        localRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
        localRoot.AssemblyAngularVelocity = targetRoot.AssemblyAngularVelocity

        if localHumanoid then
            localHumanoid.PlatformStand = true
        end

        copyMotorTransforms(target.Character, localCharacter)
    end)
end

local function setAttachEnabled(enabled)
    CatalogCreator.State.attachEnabled = enabled
    if enabled then
        startAttachLoop()
    else
        stopAttachLoop()
        local humanoid = getHumanoid(LocalPlayer)
        if humanoid then
            humanoid.PlatformStand = false
        end
        CatalogCreator.State.attachEnabled = false
    end
end

local function stopToolSpam()
    CatalogCreator.State.toolSpamEnabled = false
    if toolSpamThread then
        toolSpamThread = nil
    end
end

local function startToolSpam()
    stopToolSpam()
    CatalogCreator.State.toolSpamEnabled = true

    toolSpamThread = task.spawn(function()
        while CatalogCreator.State.toolSpamEnabled do
            local character = getCharacter(LocalPlayer)
            if not character then
                task.wait(0.2)
                continue
            end

            local humanoid = getHumanoid(LocalPlayer)
            local tool = character:FindFirstChildOfClass("Tool")

            if not tool then
                local backpack = LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack")
                if backpack then
                    tool = backpack:FindFirstChildOfClass("Tool")
                    if tool and humanoid then
                        humanoid:EquipTool(tool)
                    end
                end
            end

            if tool and tool.Activate then
                pcall(function()
                    tool:Activate()
                end)
            end
            task.wait(0.2)
        end
    end)
end

local function setToolSpamEnabled(enabled)
    CatalogCreator.State.toolSpamEnabled = enabled
    if enabled then
        startToolSpam()
    else
        stopToolSpam()
        local character = getCharacter(LocalPlayer)
        local tool = character and character:FindFirstChildOfClass("Tool")
        if tool and tool.Deactivate then
            pcall(function()
                tool:Deactivate()
            end)
        end
    end
end

local function refreshDropdown(dropdown)
    if not (dropdown and dropdown.Options and dropdown.Options.Update) then
        return
    end
    dropdown.Options:Update({
        list = playerList(),
    })
end

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    local ui = venyx.new({title = "Revamp - Catalog Creator"})

    local mainPage = ui:addPage({title = "Player Tools"})
    local selectionSection = mainPage:addSection({title = "Targeting"})

    local playerDropdown
    playerDropdown = selectionSection:addDropdown({
        title = "Select Target Player",
        list = playerList(),
        callback = function(playerName)
            CatalogCreator.State.targetPlayer = resolveTarget(playerName)
        end,
    })

    selectionSection:addButton({
        title = "Refresh Player List",
        callback = function()
            refreshDropdown(playerDropdown)
        end,
    })

    selectionSection:addButton({
        title = "Teleport To Target",
        callback = function()
            local success = teleportToTarget()
            if not success then
                warn("[CatalogCreator] Teleport failed. Ensure a target is selected and alive.")
            end
        end,
    })

    selectionSection:addToggle({
        title = "Attach To Target",
        default = false,
        callback = function(value)
            setAttachEnabled(value)
        end,
    })

    selectionSection:addToggle({
        title = "Spam Equipped Tool",
        default = false,
        callback = function(value)
            setToolSpamEnabled(value)
        end,
    })

    CatalogCreator.UI.instances.library = venyx
    CatalogCreator.UI.instances.ui = ui
    CatalogCreator.UI.instances.playerDropdown = playerDropdown

    return ui
end

local function disconnectPlayerListener()
    if playerListenerConnection then
        playerListenerConnection:Disconnect()
        playerListenerConnection = nil
    end
    if playerRemovingConnection then
        playerRemovingConnection:Disconnect()
        playerRemovingConnection = nil
    end
end

local function setupPlayerListener(dropdown)
    disconnectPlayerListener()

    playerListenerConnection = Players.PlayerAdded:Connect(function()
        if dropdown and tick() - dropdownUpdateDebounce > 0.25 then
            dropdownUpdateDebounce = tick()
            refreshDropdown(dropdown)
        end
    end)

    playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        if CatalogCreator.State.targetPlayer == player then
            CatalogCreator.State.targetPlayer = nil
            setAttachEnabled(false)
        end
        if dropdown and tick() - dropdownUpdateDebounce > 0.25 then
            dropdownUpdateDebounce = tick()
            refreshDropdown(dropdown)
        end
    end)
end

function CatalogCreator.init()
    if game.PlaceId ~= CatalogCreator.PlaceId then
        return
    end

    local ui = buildUI()
    if ui then
        ui:SelectPage(1)
    end

    local dropdown = CatalogCreator.UI.instances.playerDropdown
    setupPlayerListener(dropdown)
    refreshDropdown(dropdown)

    LocalPlayer.CharacterAdded:Connect(function()
        if CatalogCreator.State.attachEnabled then
            startAttachLoop()
        end
    end)
    LocalPlayer.CharacterRemoving:Connect(function(character)
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
        end
    end)
end

return CatalogCreator
