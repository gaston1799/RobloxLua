--[[
    RevampLua.lua
    This refactor wraps the legacy Miner's Haven automation script in a single file
    while organizing key helpers into logical buckets exposed through the `Revamp` table.
    The original behaviour is preserved, but consumers can now access focused modules such
    as `Revamp.Utilities`, `Revamp.Pathing`, `Revamp.Combat`, etc. for easier extension.
    AutoRebirth helpers initialise after the corresponding UI button runs; until then the
    exported stubs raise a descriptive error so you know the setup step is pending.
]]

local Revamp = {
    Utilities = {},
    Pathing = {},
    Combat = {},
    Farming = {},
    Inventory = {},
    Data = {},
    UI = {},
    Logging = {},
    Services = {},
    State = {}
}

local function teamCheck(name)
    local localPlayer = game.Players.LocalPlayer
    local playerTeam = nil

    for _, team in pairs(workspace.Teams:GetChildren()) do
        if team:FindFirstChild(localPlayer.Name) then
            playerTeam = team
            break
        end
    end

    if not playerTeam then
        return false
    end

    return playerTeam:FindFirstChild(name) ~= nil
end

Revamp.Utilities.teamCheck = teamCheck

local function findClosestPlayer()
    local players = game.Players:GetPlayers()
    local localPlayer = game.Players.LocalPlayer
    local localCharacter = localPlayer.Character
    if not localCharacter or not localCharacter.PrimaryPart then return nil end

    local localPosition = localCharacter.PrimaryPart.Position
    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in pairs(players) do
        if player ~= localPlayer then
            local character = player.Character
            if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
                local primaryPart = character.PrimaryPart
                if primaryPart then
                    local distance = (localPosition - primaryPart.Position).Magnitude
                    if distance < closestDistance and not teamCheck(player.Name) then
                        closestPlayer = player
                        closestDistance = distance
                    end
                end
            end
        end
    end

    return closestPlayer
end

Revamp.Utilities.findClosestPlayer = findClosestPlayer

print("Starting up")
--loadstring(game:HttpGet("https://raw.githubusercontent.com/naquangaston/HostedFiles/main/myscript.lua"))()
local incDMG_=100
local justDied=false
local prefixes = {
    { prefix = "", number = 1, term = "Ones" },
  { prefix = "k", number = 1e3, term = "Thousand" },
  { prefix = "M", number = 1e6, term = "Million" },
  { prefix = "B", number = 1e9, term = "Billion" },
  { prefix = "T", number = 1e12, term = "Trillion" },
  { prefix = "qd", number = 1e15, term = "Quadrillion" },
  { prefix = "Qn", number = 1e18, term = "Quintillion" },
  { prefix = "sx", number = 1e21, term = "Sextillion" },
  { prefix = "Sp", number = 1e24, term = "Septillion" },
  { prefix = "O", number = 1e27, term = "Octillion" },
  { prefix = "N", number = 1e30, term = "Nonillion" },
  { prefix = "de", number = 1e33, term = "Decillion" },
  { prefix = "Ud", number = 1e36, term = "Undecillion" },
  { prefix = "DD", number = 1e39, term = "Duodecillion" },
  { prefix = "tdD", number = 1e42, term = "Tredecillion" },
  { prefix = "qdD", number = 1e45, term = "Quattuordecillion" },
  { prefix = "QnD", number = 1e48, term = "Quindecillion" },
  { prefix = "sxD", number = 1e51, term = "Sedecillion" },
  { prefix = "SpD", number = 1e54, term = "Septendecillion" },
  { prefix = "OcD", number = 1e57, term = "Octodecillion" },
  { prefix = "NvD", number = 1e60, term = "Novemdecillion" },
  { prefix = "Vgn", number = 1e63, term = "Vigintillion" },
  { prefix = "UVg", number = 1e66, term = "Unvigintillion" },
  { prefix = "DVg", number = 1e69, term = "Duovigintillion" },
  { prefix = "TVg", number = 1e72, term = "Tresvigintillion" },
  { prefix = "qtV", number = 1e75, term = "Quattuorvigintillion" },
  { prefix = "QnV", number = 1e78, term = "Quinvigintillion" },
  { prefix = "SeV", number = 1e81, term = "Sesvigintillion" },
  { prefix = "SPG", number = 1e84, term = "Septemvigintillion" },
  { prefix = "OVG", number = 1e87, term = "Octovigintillion" },
  { prefix = "NVG", number = 1e90, term = "Novemvigintillion" },
  { prefix = "TGN", number = 1e93, term = "Trigintillion" },
  { prefix = "UTG", number = 1e96, term = "Untrigintillion" },
  { prefix = "DTG", number = 1e99, term = "Duotrigintillion" },
  { prefix = "tsTG", number = 1e102, term = "Trestrigintillion" },
  { prefix = "qtTG", number = 1e105, term = "Quattuortrigintillion" },
  { prefix = "QnTG", number = 1e108, term = "Quintrigintillion" },
  { prefix = "ssTG", number = 1e111, term = "Sestrigintillion" },
  { prefix = "SpTG", number = 1e114, term = "Septentrigintillion" },
  { prefix = "OcTG", number = 1e117, term = "Octotrigintillion" },
  { prefix = "NoTG", number = 1e120, term = "Novemtrigintillion" },
  { prefix = "QdDR", number = 1e123, term = "Quadragintillion" },
  { prefix = "uQDR", number = 1e126, term = "Unquadragintillion" },
  { prefix = "dQDR", number = 1e129, term = "Duoquadragintillion" },
  { prefix = "tQDR", number = 1e132, term = "Tresquadragintillion" },
  { prefix = "qdQDR", number = 1e135, term = "Quattuorquadragintillion" },
  { prefix = "QnQDR", number = 1e138, term = "Quinquadragintillion" },
  { prefix = "sxQDR", number = 1e141, term = "Sesquadragintillion" },
  { prefix = "SpQDR", number = 1e144, term = "Septenquadragintillion" },
  { prefix = "OQDDr", number = 1e147, term = "Octoquadragintillion" },
  { prefix = "NQDDr", number = 1e150, term = "Novemquadragintillion" },
  { prefix = "qQGNT", number = 1e153, term = "Quinquagintillion" },
  { prefix = "uQGNT", number = 1e156, term = "Unquinquagintillion" },
  { prefix = "dQGNT", number = 1e159, term = "Duoquinquagintillion" },
  { prefix = "tQGNT", number = 1e162, term = "Tresquinquagintillion" },
  { prefix = "qdQGNT", number = 1e165, term = "Quattuorquinquagintillion" },
  { prefix = "QnQGNT", number = 1e168, term = "Quinquinquagintillion" },
  { prefix = "sxQGNT", number = 1e171, term = "Sesquinquagintillion" },
  { prefix = "SpQGNT", number = 1e174, term = "Septenquinquagintillion" },
  { prefix = "OQQGNT", number = 1e177, term = "Octoquinquagintillion" },
  { prefix = "NQQGNT", number = 1e180, term = "Novemquinquagintillion" },
  { prefix = "SXGNTL", number = 1e183, term = "Sexagintillion" },
  { prefix = "USXGNTL", number = 1e186, term = "Unsexagintillion" },
  { prefix = "DSXGNTL", number = 1e189, term = "Duosexagintillion" },
  { prefix = "TSXGNTL", number = 1e192, term = "Tresexagintillion" },
  { prefix = "QTSXGNTL", number = 1e195, term = "Quattuorsexagintillion" },
  { prefix = "QNSXGNTL", number = 1e198, term = "Quinsexagintillion" },
  { prefix = "SXSXGNTL", number = 1e201, term = "Sesexagintillion" },
  { prefix = "SPSXGNTL", number = 1e204, term = "Septensexagintillion" },
  { prefix = "OSXGNTL", number = 1e207, term = "Octosexagintillion" },
  { prefix = "NVSXGNTL", number = 1e210, term = "Novemsexagintillion" },
  { prefix = "SPTGNTL", number = 1e213, term = "Septuagintillion" },
  { prefix = "USPTGNTL", number = 1e216, term = "Unseptuagintillion" },
  { prefix = "DSPTGNTL", number = 1e219, term = "Duoseptuagintillion" },
  { prefix = "TSPTGNTL", number = 1e222, term = "Treseptuagintillion" },
  { prefix = "QTSPTGNTL", number = 1e225, term = "Quattuorseptuagintillion" },
  { prefix = "QNSPTGNTL", number = 1e228, term = "Quinseptuagintillion" },
  { prefix = "SXSPTGNTL", number = 1e231, term = "Seseptuagintillion" },
  { prefix = "SPSPTGNTL", number = 1e234, term = "Septenseptuagintillion" },
  { prefix = "OSPTGNTL", number = 1e237, term = "Octoseptuagintillion" },
  { prefix = "NVSPTGNTL", number = 1e240, term = "Novemseptuagintillion" },
  { prefix = "OTGNTL", number = 1e243, term = "Octogintillion" },
  { prefix = "UOTGNTL", number = 1e246, term = "Unoctogintillion" },
  { prefix = "DOTGNTL", number = 1e249, term = "Duooctogintillion" },
  { prefix = "TOTGNTL", number = 1e252, term = "Treoctogintillion" },
  { prefix = "QTOTGNTL", number = 1e255, term = "Quattuoroctogintillion" },
  { prefix = "QNOTGNTL", number = 1e258, term = "Quinoctogintillion" },
  { prefix = "SXOTGNTL", number = 1e261, term = "Sexoctogintillion" },
  { prefix = "SPOTGNTL", number = 1e264, term = "Septemoctogintillion" },
  { prefix = "OTOTGNTL", number = 1e267, term = "Octooctogintillion" },
  { prefix = "NVOTGNTL", number = 1e270, term = "Novemoctogintillion" },
  { prefix = "NONGNTL", number = 1e273, term = "Nonagintillion" },
  { prefix = "UNONGNTL", number = 1e276, term = "Unnonagintillion" },
  { prefix = "DNONGNTL", number = 1e279, term = "Duononagintillion" },
  { prefix = "TNONGNTL", number = 1e282, term = "Trenonagintillion" },
  { prefix = "QTNONGNTL", number = 1e285, term = "Quattuornonagintillion" },
  { prefix = "QNNONGNTL", number = 1e288, term = "Quinnonagintillion" },
  { prefix = "SXNONGNTL", number = 1e291, term = "Senonagintillion" },
  { prefix = "SPNONGNTL", number = 1e294, term = "Septenonagintillion" },
  { prefix = "OTNONGNTL", number = 1e297, term = "Octononagintillion" },
  { prefix = "NONONGNTL", number = 1e300, term = "Novemnonagintillion" },
  { prefix = "CENT", number = 1e303, term = "Centillion" },
  { prefix = "UNCENT", number = 1e306, term = "Uncentillion" }
}

Revamp.Data.prefixes = prefixes

-- Safe-zone rectangle for AutoPVP/Kill Aura (X/Z only). Update with your captures.
local SafeZoneXZ = {
    x = {min = -344.031, max = -47.203},
    z = {min = 486.590, max = 588.073}
}

Revamp.Data.SafeZone = SafeZoneXZ

--Miner's Haven
local FetchItemModule
local TycoonBase
local MyTycoon
local MoneyLibary
local players
local self
local char
local root
local mouse
local value
local followEm

local userInputService = game:GetService("UserInputService")
local player = game:GetService("Players").LocalPlayer
local humanoid = nil
local LegitPathing = false
local pathfindingComplete = false

local function getItem(name)
    local success, result =
        pcall(function()
            return game.ReplicatedStorage.Items[name]
        end)
    if success then
        return result
    end
    warn("Failed to find item:", name, result)
    return nil
end

local function GetDistanceBetweenCFrame(cframe1, cframe2)
    local position1 = cframe1.Position
    local position2 = cframe2.Position
    return (position1 - position2).Magnitude
end

local function ShopItems()
    for _, possible in pairs(getgc(true)) do
        if type(possible) == "table" and rawget(possible, "Miscs") then
            return possible["All"]
        end
    end
    return {}
end

local function HasItem(Needed, count)
    local owned = game:GetService("ReplicatedStorage").HasItem:InvokeServer(Needed) or 0
    if count then
        return owned
    end
    return owned > 0
end

local function IsShopItem(Needed)
    for _, shopEntry in pairs(ShopItems()) do
        if tonumber(shopEntry.ItemId.Value) == tonumber(Needed) then
            return true
        end
    end
    return false
end

local function ItemPlaced(obj)
    local ok =
        pcall(function()
            return obj.name or obj.id
        end)
    if not ok then
        return false
    end
    if not MyTycoon then
        return false
    end
    for _, item in MyTycoon:GetChildren() do
        if item.ItemId.Value == obj.id or item.name == obj.Name then
            return true
        end
    end
    return false
end

local function uninitialisedHelper(name)
    return function()
        error(("RevampLua helper '%s' is not initialised yet. Run the AutoRebirth setup first."):format(name))
    end
end

local goTo = uninitialisedHelper("goTo")
local goBack = uninitialisedHelper("goBack")
local loadLayouts = uninitialisedHelper("loadLayouts")
local farmRebirth = uninitialisedHelper("farmRebirth")
local hasCat = uninitialisedHelper("hasCat")

local autoJump = false
local autoFight = false
local finding = false
local done_ = true
local legitCoin = true
local attacking_ = false
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local DamageRemote = game:GetService("ReplicatedStorage").jdskhfsIIIllliiIIIdchgdIiIIIlIlIli

local selectedPlayerName = "" -- Variable to store the name of the selected player
local selectedPlayer  -- Variable to store the instance of the selected player
local maxDistance = 10 -- Maximum distance to stay near the selected player

-- Function to predict future position of a player based on velocity
local function PredictPlayerPosition(player)
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local velocity = humanoid.WalkSpeed * humanoid.WalkDirection + humanoid.RootPart.Velocity
            local time = 1  -- You can adjust this value to predict the position at a specific time in the future

            local predictedPosition = character.PrimaryPart.Position + velocity * time
            return predictedPosition
        end
    end

    return nil  -- Return nil if prediction is not possible
end

local function teleportInFrontOfPlayer(targetPlayerName)
    local player = game.Players.LocalPlayer
    local targetPlayer = game.Players:FindFirstChild(targetPlayerName)

    if targetPlayer then
        local targetCharacter = targetPlayer.Character
        local targetHumanoid = targetCharacter and targetCharacter:FindFirstChild("Humanoid")

        if targetCharacter and targetHumanoid then
            local targetVelocity = targetCharacter.PrimaryPart.Velocity
            local predictedPosition = targetCharacter.PrimaryPart.Position + targetVelocity

            player.Character:SetPrimaryPartCFrame(CFrame.new(predictedPosition))
        end
    end
end

local function increaseByPercentage(number, percentage)
    number = tonumber(number)
    percentage = tonumber(percentage)

    if not number or not percentage then
        error("Both arguments must be valid numbers.")
    end

    if percentage < 0 then
        error("Percentage should be a positive value.")
    end

    local increaseAmount = number * (percentage / 100)
    local result = number + increaseAmount

    return result
end
local pathfindingService = game:GetService("PathfindingService")

local function getPathToPosition(targetPosition, humanoid)
    local startPosition = humanoid.RootPart.Position
    local path = pathfindingService:CreatePath({
        AgentRadius = humanoid.HipHeight / 2,
        AgentHeight = humanoid.HipHeight,
        AgentCanJump = true,
        AgentJumpHeight = humanoid.JumpHeight,
        AgentMaxSlope = humanoid.MaxSlopeAngle,
        AgentMaxStepHeight = humanoid.HipHeight,
    })
    path:ComputeAsync(startPosition, targetPosition)
    return path
end
local function moveToTarget(target, humanoid)
    local player = game.Players.LocalPlayer
    humanoid = humanoid or player.Character:WaitForChild("Humanoid")

    local targetPosition = target

    if typeof(target) == "CFrame" then
        targetPosition = target.Position
    elseif typeof(target) ~= "Vector3" then
        warn("Invalid target type. Expected CFrame or Vector3.")
        return
    end

    local path = getPathToPosition(targetPosition, humanoid)
    local waypoints = path:GetWaypoints()
    local currentWaypointIndex = 1
    local defaultDistance

    local function moveToFinished()
        humanoid.MoveToFinished:Wait()
    end

    while currentWaypointIndex <= #waypoints do
        if(attacking_ or  justDied) then break end
        local currentWaypoint = waypoints[currentWaypointIndex]

        if currentWaypointIndex == 1 then
            humanoid:MoveTo(currentWaypoint.Position)
            moveToFinished()
            wait(1)
            defaultDistance = (currentWaypoint.Position - humanoid.RootPart.Position).Magnitude
            print("defaultDistance:",defaultDistance)
        else
            local distanceToWaypoint = (currentWaypoint.Position - humanoid.RootPart.Position).Magnitude
            if currentWaypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump=true
            end
            while (distanceToWaypoint-3) > (defaultDistance or 5) do
                if(attacking_ or  justDied) then break end
                humanoid:MoveTo(currentWaypoint.Position)
                moveToFinished()
                distanceToWaypoint = (currentWaypoint.Position - humanoid.RootPart.Position).Magnitude
                wait(0) -- Adjust the delay as needed
            end
        end

        currentWaypointIndex = currentWaypointIndex + 1
    end
end


local function defineNilLocals()
    if FetchItemModule == nil then
        local success, result =
            pcall(
            function()
                FetchItemModule = require(game:GetService("ReplicatedStorage").FetchItem)
            end
        )
        if not success then
            warn("Failed to define FetchItemModule:", result)
        end
    end

    if TycoonBase == nil then
        local success, result =
            pcall(
            function()
                TycoonBase = player.PlayerTycoon.Value.Base
            end
        )
        if not success then
            warn("Failed to define TycoonBase:", result)
        end
    end

    if MyTycoon == nil then
        local success, result =
            pcall(
            function()
                MyTycoon = player.PlayerTycoon.Value
            end
        )
        if not success then
            warn("Failed to define MyTycoon:", result)
        end
    end

    if MoneyLibary == nil then
        local success, result =
            pcall(
            function()
                MoneyLibary = require(game:GetService("ReplicatedStorage").MoneyLib)
            end
        )
        if not success then
            warn("Failed to define MoneyLibary:", result)
        end
    end

    if players == nil then
        players = game:GetService("Players")
    end

    if self == nil then
        self = players.LocalPlayer
    end

    if char == nil then
        local success, result =
            pcall(
            function()
                char = self.Character
            end
        )
        if not success then
            warn("Failed to define char:", result)
        end
    end

    if root == nil then
        local success, result =
            pcall(
            function()
                root = char.HumanoidRootPart
            end
        )
        if not success then
            warn("Failed to define root:", result)
        end
    end

    if mouse == nil then
        mouse = self:GetMouse()
    end

    if value == nil then
        local success, result =
            pcall(
            function()
                value = self.Rebirths
            end
        )
        if not success then
            warn("Failed to define value:", result)
        end
    end
end

local function waitForChar()
    repeat
        wait()
    until game:GetService("Players").LocalPlayer.Character
end

local function defineLocals()
    print("waiting for character to load")
    repeat
        wait()
    until game:GetService("Players").LocalPlayer.Character
    local success, result

    success, result =
        pcall(
        function()
            FetchItemModule = require(game:GetService("ReplicatedStorage").FetchItem)
        end
    )
    if not success then
        warn("Failed to define FetchItemModule:", result)
    end

    success, result =
        pcall(
        function()
            TycoonBase = player.PlayerTycoon.Value.Base
        end
    )
    if not success then
        warn("Failed to define TycoonBase:", result)
    end

    success, result =
        pcall(
        function()
            MyTycoon = player.PlayerTycoon.Value
        end
    )
    if not success then
        warn("Failed to define MyTycoon:", result)
    end

    success, result =
        pcall(
        function()
            MoneyLibary = require(game:GetService("ReplicatedStorage").MoneyLib)
        end
    )
    if not success then
        warn("Failed to define MoneyLibary:", result)
    end

    players = game:GetService("Players")
    self = players.LocalPlayer

    success, result =
        pcall(
        function()
            char = self.Character
        end
    )
    if not success then
        warn("Failed to define char:", result)
        return
    end

    success, result =
        pcall(
        function()
            root = char.HumanoidRootPart
        end
    )
    if not success then
        warn("Failed to define root:", result)
        return
    end

    mouse = self:GetMouse()

    success, result =
        pcall(
        function()
            value = self.Rebirths
        end
    )
    if not success then
        warn("Failed to define value:", result)
    end

    humanoid = char:WaitForChild("Humanoid")

    pathfindingComplete = true
    finding = false
    done_ = true
    legitCoin = true
end
defineLocals()

local function updateSelectedPlayer()
    selectedPlayer = Players:FindFirstChild(selectedPlayerName)
end

local function stayNearPlayer()
    updateSelectedPlayer()
    while followEm do
        if selectedPlayer and selectedPlayer.Character then
            local targetPosition = selectedPlayer.Character.HumanoidRootPart.Position
            local distance = (targetPosition - humanoidRoot.Position).Magnitude

            if distance > maxDistance then
                local direction = (targetPosition - humanoidRoot.Position).Unit
                local newPosition = targetPosition - direction * maxDistance
                humanoidRoot.CFrame = CFrame.new(newPosition)
            end
        end
        wait() -- Adjust the wait time according to your needs
    end
    wait(1)
    stayNearPlayer()
end

local usertarget = false
-- Function to perform A* pathfinding
local function PathfindTo(target, time)
    waitForChar()
    repeat
        wait(0)
    until not finding

    if not LegitPathing then
        local targetCFrame = target
        if typeof(target) == "Vector3" then
            targetCFrame = CFrame.new(target)
        elseif typeof(target) == "Instance" and target:IsA("BasePart") then
            targetCFrame = target.CFrame
        end
        local ok =
            pcall(function()
                humanoidRoot.CFrame = targetCFrame
            end)
        if not ok then
            humanoidRoot.Position = targetCFrame.Position
        end
        pathfindingComplete = true
        finding = false
        spawn(
            function()
                wait(time or 1)
                finding = false
            end
        )
        return true
    end
    finding = true
    local path = game:GetService("PathfindingService"):FindPathAsync(humanoid.RootPart.Position, target.Position)

    if path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        local currentIndex = 1

        -- Enable flag to indicate pathfinding is in progress
        pathfindingComplete = false

        while currentIndex <= #waypoints do
            local waypoint = waypoints[currentIndex]

            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
                humanoid:MoveTo(waypoint.Position)
                currentIndex = currentIndex + 1 -- Move to the next waypoint immediately
            else
                humanoid:MoveTo(waypoint.Position)
                humanoid.MoveToFinished:Wait()

                -- Check if the pathfinding was interrupted
                if pathfindingComplete then
                    break
                end

                currentIndex = currentIndex + 1
            end
        end

        print("Reached target position!")
        finding = false
        return true
    else
        print("Failed to find a path to the target.")
        finding = false
        return true
    end

    -- Check the distance to the target position continuously
    while (humanoid.RootPart.Position - target.Position).Magnitude > 1 do
        if pathfindingComplete then
            break
        end
        wait()
    end

    print("Target position reached!")
    finding = false
    return true -- Return true to indicate the target was reached
end

-- Separate loop for handling jumps
spawn(
    function()
        while true do
            if humanoid.MoveToFinished:Wait() then
                if humanoid.MoveToPoint == nil and not pathfindingComplete then
                    humanoid.Jump = true
                end
            end
        end
    end
)

-- Event listener for player input
userInputService.InputBegan:Connect(
    function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard and not pathfindingComplete then
            humanoid:Move(Vector3.new()) -- Stop the character's movement
            pathfindingComplete = true -- Set the flag to interrupt pathfinding
        end
    end
)

local event = {current = humanoid:GetState(), last = humanoid:GetState()}

local events = {
    Landed = function()
        if autoJump then
            repeat
                wait(.1)
            until event.current.Name == "Running"
            game.Players.LocalPlayer.Character.Humanoid.Jump = true
        end
    end
}

local function Jump_()
    humanoid.Jump = true
end

local function v2()
    event.last = event.current
    if event.current ~= humanoid:GetState() then
        warn("State change", humanoid:GetState())
        event.current = humanoid:GetState()
        local eventFunction = events[humanoid:GetState().Name]
        if eventFunction then
            print("Running", humanoid:GetState().Name)
            eventFunction()
        end
    end
end

game:GetService("RunService").Heartbeat:Connect(v2)
local function CombineCFrameAndVector(cframe, vector)
    return cframe + vector
end
local function BloxFruit()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Augustzyzx/UraniumMobile/main/UraniumKak.lua"))()
end
local function heal()
    local Locations = {"Backpack", "Character"}
    local f = "Food"
    for i, Location in pairs(Locations) do
        --print(Location)
        for a, b in pairs(game.Players.LocalPlayer[Location]:GetChildren()) do
            if (b.Name == f) then
                print(f)
                for c, d in pairs(b.Script:GetChildren()) do
                    print(d)
                    for g, h in pairs(d:GetChildren()) do
                        print(h)
                    end
                end
            end
        end
    end
end
local function useAllFire(player_)
    local Balls = {"Fireball", "Lightningball"}
    local Locations = {"Backpack", "Character"}
    return false
    --[[for i, player in pairs(game.Players:GetChildren()) do
        for _, Ball in pairs(Balls) do
            for i, Location in pairs(Locations) do
                local CheckBall = player[Location]:FindFirstChild(Ball)
                if (CheckBall) then --print(player.Name.." has: "..Ball)
                    for a, b in pairs(CheckBall:GetChildren()) do
                        --print(b)
                    end
                    CheckBall.FireballEvent:FireServer(player_.Position)
                end
            end
            --if earlyreturn then return end
        end
    end
    --]]
end
local function useAllFire_(pos)
    return false
end
local function hitHumanoid(targetHumanoid)
    if not targetHumanoid or not targetHumanoid.Parent then
        return false
    end
    local ok, err = pcall(DamageRemote.FireServer, DamageRemote, targetHumanoid, 1)
    if not ok then
        warn("Failed to strike humanoid:", err)
        return false
    end
    return true
end
local function destroyAll()
    game.ReplicatedStorage.DestroyAll:InvokeServer()
    wait(.7)
end
local function conv(cash)
    local p = ""
    for _, prefix in pairs(prefixs) do
        if (cash:match(prefix.Prefix)) then
            p = _
        end
    end
    cash = tonumber(string.split(cash, prefixs[p].Prefix)[1]) * prefixs[p].Number
    return cash
end
local function comparCash(a)
    return conv(a) < conv(string.split(game.Players.LocalPlayer.leaderstats.Cash.value, "$")[2])
end
local function updated_()
    Players = game:GetService("Players")
    player = Players.LocalPlayer
    character = player.Character
    humanoid = character:WaitForChild("Humanoid")
    humanoidRoot = character:WaitForChild("HumanoidRootPart")
end

local path =
    PathfindingService:CreatePath(
    {
        AgentRadius = 3,
        AgentHeight = 6,
        AgentCanJump = true,
        AgentCanClimb = true,
        Costs = {
            Water = 20,
            Neon = math.huge
        }
    }
)

local waypoints
local nextWaypointIndex
local reachedConnection
local blockedConnection
local function followPath(destination)
    done_ = false
    -- Compute the path
    local success, errorMessage =
        pcall(
        function()
            path:ComputeAsync(character.PrimaryPart.Position, destination)
        end
    )
    if success and path.Status == Enum.PathStatus.Success then
        -- Get the path waypoints
        waypoints = path:GetWaypoints()
        -- Detect if path becomes blocked
        blockedConnection =
            path.Blocked:Connect(
            function(blockedWaypointIndex)
                -- Check if the obstacle is further down the path
                if blockedWaypointIndex >= nextWaypointIndex then
                    -- Stop detecting path blockage until path is re-computed
                    blockedConnection:Disconnect()
                    -- Call function to re-compute new path
                    followPath(destination)
                end
            end
        )
        -- Detect when movement to next waypoint is complete
        if not reachedConnection then
            reachedConnection =
                humanoid.MoveToFinished:Connect(
                function(reached)
                    if reached and nextWaypointIndex < #waypoints then
                        -- Increase waypoint index and move to next waypoint
                        nextWaypointIndex = nextWaypointIndex + 1
                        humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
                    else
                        done_ = true
                        print("D")
                        reachedConnection:Disconnect()
                        blockedConnection:Disconnect()
                    end
                end
            )
        end
        -- Initially move to second waypoint (first waypoint is path start; skip it)
        nextWaypointIndex = 2
        humanoid:MoveTo(waypoints[nextWaypointIndex].Position)
    else
        warn("Path not computed!", errorMessage)
    end
end
local function Clovers()
    return game.Workspace.Clovers:GetChildren()
end
local function Boxes()
    return game.Workspace.Boxes:GetChildren()
end
local function dist(a, b)
    return (a.Position - b.Position).Magnitude
end
local function waitDoneMove()
    while (not done_) do
        wait(0)
    end
    return true
end
local function getClosest(t)
    local _ = {}
    print(t)
    for i, v in pairs(t) do
        _[#_ + 1] = v
        print(dist(v, humanoidRoot))
    end
    table.sort(
        _,
        function(a, b)
            return dist(a, humanoidRoot) < dist(b, humanoidRoot)
        end
    )
    return _[1]
end
local function MoveTo(a)
    followPath(a.Position)
    return true
end

local function tp(coin)
    humanoidRoot.CFrame = coin.CFrame
    wait(.55)
end

local myLeader
local myT
local function myTeam(name)
    if (name == nil) then
        name = game.Players.LocalPlayer.name
    end
    local d = nil
    for i, v in pairs(game.Workspace.Teams:GetChildren()) do
        for i, _ in pairs(v:GetChildren()) do
            if (_.name == "leader") then
                myLeader = _.value
            end
            if (name == _.value) then
                myT = v.name
            end
        end
        return {myLeader, myT}
    end
end
local function getTeams()
    local My
    local Teams_ = {}
    local myTeam = nil
    for i, v in pairs(game.Workspace.Teams:GetChildren()) do
        for i, _ in pairs(v:GetChildren()) do
            table.insert(Teams_, {_.value, v.name})
        end
    end
    return Teams_
end
local function getPos()
    local InSafe = {}
    local SafeZone1 = {86.3, 493.6}
    local SafeZone2 = {-3.5, 388.2}
    local mine = myTeam()
    for _, v in pairs(game:GetService("Players"):GetPlayers()) do
        --print(v)
        local x = v.Character.HumanoidRootPart.Position.X
        local z = v.Character.HumanoidRootPart.Position.Z
        local eTeam = myTeam(v.Character.name)
        --print(v.name)
        --print(x,z,SafeZone1[1]>x,SafeZone1[2]>z,SafeZone2[1]<x,SafeZone2[2]<z)
        --print(mine[1],mine[2],' - ',eTeam[1],eTeam[2])
        pcall(
            function()
                if (SafeZone1[1] > x and SafeZone1[2] > z and SafeZone2[1] < x and SafeZone2[2] < z) then
                    --if(mine)
                    if (mine[2] == nil or v.Character.Humanoid.Health == 0) then
                        InSafe[v.name] = true
                    else
                        if (mine[1] == eTeam[1] or v.Character.Humanoid.Health == 0) then
                            InSafe[v.name] = true
                        else
                            InSafe[v.name] = false
                        end
                    end
                else
                    if (v.Character.Humanoid.Health < 1) then
                        InSafe[v.name] = true
                    else
                        InSafe[v.name] = false
                    end
                end
            end
        )
    end
    return InSafe
end
local t_ = ""
local usertarget = false
print("waiting for game to load")
repeat
    wait()
until game:IsLoaded()
print("game laoded")

local function fire(event)
    return event:FireServer()
end
local egg = nil
--game:GetService("ReplicatedStorage").EggEvent
local treasure = nil
--ame:GetService("ReplicatedStorage").TreasureEvent
--local drop=game:GetService("ReplicatedStorage").disableOwnRide
local cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
local function MHBox()
    local cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
    for i, v in pairs(game.Workspace:GetDescendants()) do
        if v:IsA("BasePart") then
            if
                (v.Name:match("Diamond") or v.Name:match("Research") or v.Name:match("Golden") or
                    v.Name:match("Crystal")) and
                    not v.Name:match("overlay") and
                    not v.Name:match("inside") and
                    not v.Name:match("Lava") and
                    not v.Name:match("Mine") and
                    not v.Name:match("Handle") and
                    not v.Name:match("Upgrade") and
                    not v.Name:match("Conv") and
                    not v.Name:match("Hitox") and
                    not v.Name:match("Mesh") and
                    not v.Name:match("Palm") and
                    not v.Name:match("Sphere") and
                    not v.Name:match("Smooth") and
                    not v.Name:match("Grass") and
                    not v.Name:match("Grass") and
                    not v.Name:match("Union") and
                    not v.Name:match("Color") and
                    not v.Name:match("Drop") and
                    not v.Name:match("EGG") and
                    not v.Name:match("Terrain") and
                    not v.Name:match("Rock") and
                    not v.Name:match("Sand") and
                    not v:IsA("Terrain") and
                    not v.Name:match("Part") and
                    not v.Name:match("rock") and
                    not v.Name:match("Wedge") and
                    not v.Name:match("Lights") and
                    not v.Name:match("Tree") and
                    not v.Name:match("Leaf")
             then
                --if v.Name:match("Egg") then
                print("Yes", v.Name)
                wait(0.05)
                cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
                game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.CFrame
                wait(.5)
                game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = cf
            else
                if
                    (not v.Name:match("overlay") and not v.Name:match("inside") and not v.Name:match("Lava") and
                        not v.Name:match("Mine") and
                        not v.Name:match("Handle") and
                        not v.Name:match("Upgrade") and
                        not v.Name:match("Conv") and
                        not v.Name:match("Hitox") and
                        not v.Name:match("Mesh") and
                        not v.Name:match("Palm") and
                        not v.Name:match("Sphere") and
                        not v.Name:match("Smooth") and
                        not v.Name:match("Grass") and
                        not v.Name:match("Grass") and
                        not v.Name:match("Union") and
                        not v.Name:match("Color") and
                        not v.Name:match("Drop") and
                        not v.Name:match("EGG") and
                        not v.Name:match("Terrain") and
                        not v.Name:match("Rock") and
                        not v.Name:match("Sand") and
                        not v:IsA("Terrain") and
                        not v.Name:match("Part") and
                        not v.Name:match("rock") and
                        not v.Name:match("Wedge") and
                        not v.Name:match("Lights") and
                        not v.Name:match("Tree") and
                        not v.Name:match("Leaf"))
                 then
                --print('Not',v.Name)
                end
            end
        end
    end
    print("Done!")
end
local DMGbool = false
local FarmBool = false
local bool = false
local CurrentTarget = ""
local ctime = 0
local ltime = 0
local function farm()
    _G.speed = 0.005
    --ltime=os.clock()*100
    while _G.toggle == true do
        local point = nil
        local dist = nil
        humanoidRoot = character:WaitForChild("HumanoidRootPart")
        for _, coin in pairs(game.Workspace.CoinContainer:GetChildren()) do
            local magnitude = math.abs((coin.Coin.Position - humanoidRoot.Position).Magnitude)
            if (dist == nil) then
                dist = magnitude
            end
            if (magnitude < dist) then
                point = coin.Coin
                dist = magnitude
            end
        end
        if (legitCoin) then
            followPath(point.Position)
        else
            tp(point)
        end
    end
end
local function farm_()
    cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
    _G.speed = 0.05
    while _G.toggle == true do
        for i, v in pairs(game.Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                if not v:IsA("Terrain") then
                    if v.Name:match("Egg") then
                        -- print(v.Name)
                        wait(_G.speed)
                        cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
                        game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.CFrame
                        wait(0)
                        game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = cf
                    --wait(0.001)
                    end
                    if v.Name:match("Tre") then
                        --print(v.Name)
                        wait(_G.speed)
                        cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
                        game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.CFrame
                        wait(0)
                        game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = cf
                    --wait(0.001)
                    end
                end
            end
        end
        cf = mil
    end
end
local function findPlr(name)
    for _, v in pairs(game:GetService("Players"):GetPlayers()) do
        if string.find(v.Name, name) then
            return v
        end
    end
    return nil
end
local damagedplayer = nil
local function damageplayer(player)
    for i, p in pairs(game.Workspace:GetChildren()) do
        if p.Name == player then
            --print("Damaging " .. player)
            hitHumanoid(p:FindFirstChildOfClass("Humanoid"))
        --print("Damaged " .. player)
        end
    end
end

local function aura()
    _G.speed2 = 0.05
    cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
    while _G.toggle2 == true do
        local function death()
            local Zoned = getPos()
            if (usertarget == true) then
                local player = findPlr(t_)
                if (Zoned[t_] == true) then
                    wait()
                    return
                end
                --print(player)
                local function atk()
                    --teleportInFrontOfPlayer(t_)
                    local randomOffsetX = math.random(-15, 15)
                    local randomOffsetY = math.random(-15, 15)
                    local randomOffsetZ = math.random(-15, 15)
                    local newPos =
                        player.Character:WaitForChild("HumanoidRootPart").Position +
                        Vector3.new(randomOffsetX, randomOffsetY, randomOffsetZ)
                    game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame = CFrame.new(newPos)
                    --game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame=player.Character.HumanoidRootPart.CFrame
                    wait(.1)
                    print("Target:", player, player.Character.Humanoid.Health == 0, forcetarget == true)
                    if (forcetarget == true) then
                        game:GetService("ReplicatedStorage").RideEvents.acceptEvent:FireServer(player.Name)
                    end
                    hitHumanoid(player.Character:FindFirstChildOfClass("Humanoid"))
                end
                pcall(atk)
                wait(0)
            else
                --for i,v in pairs(game.Players:GetChildren()) do for i,p in pairs(game.Workspace:GetChildren()) do if p.Name == v.Name and p.Name ~= game.Players.LocalPlayer.Name then print(p.Name,p.Health);game:GetService("ReplicatedStorage").jdskhfsIIIllliiIIIdchgdIiIIIlIlIli:FireServer(p.Humanoid,1) end end end
                local Closest = {}
                local alive = {}
                local npcs = {}
                for i, p in pairs(game.Workspace.NPC:GetChildren()) do
                    local head
                    local Humanoid_

                    for _i, _p in pairs(p:GetDescendants()) do
                        if (_p.Name == "Head") then
                            head = _p
                            break
                        end
                    end
                    for _i, _p in pairs(p:GetDescendants()) do
                        if (_p.Name == "Humanoid") then
                            Humanoid_ = _p
                            break
                        end
                    end

                    pcall(
                        function()
                            table.insert(
                                Closest,
                                {
                                    p,
                                    (head.Position -
                                        game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").Position).magnitude,
                                    p,
                                    {Humanoid_.Health, Humanoid_.MaxHealth}
                                }
                            )
                            npcs[i] = p
                        end
                    )
                end
                for _, player in pairs(game.Players:GetPlayers()) do
                    if not (player.Name == game.Players.LocalPlayer.Character.Name) then
                        for i, p in pairs(game.Workspace:GetChildren()) do
                            if p.Name == player.Name and p.Name ~= game.Players.LocalPlayer.Name then
                                pcall(
                                    function()
                                        table.insert(
                                            Closest,
                                            {
                                                player,
                                                player:DistanceFromCharacter(
                                                    game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").Position
                                                ),
                                                p,
                                                {p.Humanoid.Health, p.Humanoid.MaxHealth},
                                                player.Name
                                            }
                                        )
                                    end
                                )
                            end
                        end
                    end
                end
                table.sort(
                    Closest,
                    function(valueA, valueB)
                        return valueA[2] < valueB[2]
                    end
                )
                for _, player in pairs(Closest) do
                    if ((Closest[1][4][1] / Closest[1][4][2]) ~= 0) then
                        table.insert(alive, {player[1], player[3].Humanoid, player[4]})
                    end
                end
                --for _, npc in pairs(npcs) do if((Closest[1][4][1]/Closest[1][4][2])~=0) then table.insert(alive,{player[1],player[3].Humanoid,player[4]}) end end
                --atk closest player
                --if CurrentTarget~=alive[1][1].name then print('New Target:',alive[1][1].name) end
                CurrentTarget = alive[1][1].name
                for _, player in pairs(alive) do
                    if (not Zoned[player.name]) then
                        --hitHumanoid(player[2])
                        print(findClosestPlayer())
                        local closest = findClosestPlayer()
                        if closest and closest.Character then
                            hitHumanoid(closest.Character:FindFirstChildOfClass("Humanoid"))
                        end
                    end
                end
            end
        end
        if usertarget then
            wait(0)
        end
        if not usertarget then
            wait(_G.speed2)
        end
        pcall(death)
    end
    game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = cf
    -- list events for i,p in pairs(game:GetService("ReplicatedStorage"):GetChildren()) do print(p)end
end
local function dmgloop()
    while DMGbool == true do
        wait(0.05)
        pcall(DMGall)
    end
end
local function toggleFarm()
    _G.toggle = not _G.toggle
    if _G.toggle == true then
        print("Auto exp:ON")
        farm()
    else
        print("Auto exp:OFF")
    end
end
local function toggleAura()
    _G.toggle2 = not _G.toggle2
    if _G.toggle2 == true then
        print("Aura:ON")
        aura()
    else
        print("Aura:OFF")
    end
end
local Venyx =
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
local UI =
    Venyx.new(
    {
        title = "Menu - By Pirator/Lucky - Edit By Doornextguyyhat"
    }
)

local Themes = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255)
}

Revamp.UI.Themes = Themes

local Main =
    UI:addPage(
    {
        title = "Animal Sim",
        icon = 887262219
    }
)
local Miners =
    UI:addPage(
    {
        title = "Miner's Haven",
        icon = 887262219
    }
)
local Legends =
    UI:addPage(
    {
        title = "LoS",
        icon = 887262219
    }
)
local BloxF =
    UI:addPage(
    {
        title = "LoS",
        icon = 887262219
    }
)
local Gameplaydiv =
    Main:addSection(
    {
        title = "Gameplay"
    }
)
local Orbs =
    Legends:addSection(
    {
        title = "Orbs"
    }
)
local Minersdiv =
    Miners:addSection(
    {
        title = "Boxes"
    }
)
local Fruits =
    Main:addSection(
    {
        title = "Scripts/Hubs"
    }
)

local tb = {}
for _, player in pairs(game.Players:GetPlayers()) do
    if not (player.Name == game.Players.LocalPlayer.Character.Name) then
        for i, p in pairs(game.Workspace:GetChildren()) do
            if p.Name == player.Name and p.Name ~= game.Players.LocalPlayer.Name then
                table.insert(tb, player)
            end
        end
    end
end
local lis = nil
local function cb(text)
    --print(text,focusLost)
    t_ = text
    print("Searching " .. text)
    local Player = findPlr(text)
    print("Found " .. tostring(Player))
    local Player = game.Workspace:FindFirstChild(Player.Name)
    damagedplayer = tostring(Player)
    t_ = damagedplayer
    print("Updating list")
    local tb_ = {}
    for _, player in pairs(game.Players:GetPlayers()) do
        if not (player.Name == game.Players.LocalPlayer.Character.Name) then
            for i, p in pairs(game.Workspace:GetChildren()) do
                if p.Name == player.Name and p.Name ~= game.Players.LocalPlayer.Name then
                    table.insert(tb_, player)
                end
            end
        end
    end
    print(self)
    print(lis)
    print(tb_ == tb)
    print(
        Gameplaydiv:updateDropdown(
            lis,
            {
                title = "Set Target Player",
                default = damagedplayer or game.Players.LocalPlayer.Character.Name,
                list = {"testone", "testtwo", "onetweotree"},
                callback = cb
            }
        )
    )
end
local function cb_(text)
    --print(text,focusLost)
    t_ = text
    print("Searching " .. text)
    local Player = findPlr(text)
    print("Found " .. tostring(Player))
    local Player = game.Workspace:FindFirstChild(Player.Name)
    damagedplayer = tostring(Player)
    t_ = damagedplayer
    print("Updating list")
    local tb_ = {}
    for _, player in pairs(game.Players:GetPlayers()) do
        if not (player.Name == game.Players.LocalPlayer.Character.Name) then
            for i, p in pairs(game.Workspace:GetChildren()) do
                if p.Name == player.Name and p.Name ~= game.Players.LocalPlayer.Name then
                    table.insert(tb_, player)
                end
            end
        end
    end
    print(self)
    print(lis)
    print(tb_ == tb)
    Gameplaydiv:updateDropdown(
        lis,
        {
            title = "Set Target Player",
            default = damagedplayer or game.Players.LocalPlayer.Character.Name,
            list = tb_,
            callback = cb
        }
    )
end
lis =
    Gameplaydiv:addDropdown(
    {
        title = "Set Target Player",
        default = game.Players.LocalPlayer.Character.Name,
        list = tb,
        callback = function(text)
            --print(text,focusLost)
            t_ = text
            print("Searching " .. text)
            local Player = findPlr(text)
            print("Found " .. tostring(Player))
            local Player = game.Workspace:FindFirstChild(Player.Name)
            damagedplayer = tostring(Player)
            t_ = damagedplayer
            print("Updating list")
            local tb_ = {}
            for _, player in pairs(game.Players:GetPlayers()) do
                if not (player.Name == game.Players.LocalPlayer.Character.Name) then
                    for i, p in pairs(game.Workspace:GetChildren()) do
                        if p.Name == player.Name and p.Name ~= game.Players.LocalPlayer.Name then
                            table.insert(tb_, player)
                        end
                    end
                end
            end
            print(self)
            print(lis)
            print(tb_ == tb)
            Gameplaydiv:updateDropdown(
                lis,
                {
                    title = "Set Target Player",
                    default = damagedplayer or game.Players.LocalPlayer.Character.Name,
                    list = tb_
                }
            )
            print("list updated")
        end
    }
)
local collecting
Gameplaydiv:addToggle(
    {
        title = "Auto exp farfm",
        toggled = nil,
        callback = function(value)
            player = Players.LocalPlayer
            character = player.Character
            humanoid = character:WaitForChild("Humanoid")
            humanoidRoot = character:WaitForChild("HumanoidRootPart")
            _G.toggle = not value
            toggleFarm()
        end
    }
)

Gameplaydiv:addToggle(
    {
        title = "LegitMode",
        toggled = nil,
        callback = function(value)
            legitCoin = not (not value)
        end
    }
)

local dmga

Gameplaydiv:addToggle(
    {
        title = "Kill aura",
        toggled = nil,
        callback = function(value)
            _G.toggle2 =  not value
            toggleAura()
        end
    }
)
Gameplaydiv:addToggle(
    {
        title = "Auto PVP",
        toggled = nil,
        callback = function(value)
            _G.autoPVP = not not value
            print("_G.autoPVP",_G.autoPVP)
        end
    }
)
Gameplaydiv:addToggle(
    {
        title = "Auto Jump",
        toggled = nil,
        callback = function(value)
            autoJump = not not value
            print("Autojump:", autoJump)
        end
    }
)
Gameplaydiv:addToggle(
    {
        title = "Auto Fight",
        toggled = nil,
        callback = function(value)
            autoFight = not not value
            print("AutoFight:", autoFight)
            while(autoFight)do
            	local target=parsePlayer(findClosestPlayer())
            	wait(0)
            end
        end
    }
)
Gameplaydiv:addToggle(
    {
        title = "Use target",
        toggled = nil,
        callback = function(value)
            usertarget = value
        end
    }
)
Gameplaydiv:addButton(
    {
        title = "Damage Player",
        callback = function()
            damageplayer(damagedplayer)
        end
    }
)
Fruits:addButton(
    {
        title = "Uranium Hub",
        callback = function()
            BloxFruit()
        end
    }
)
Orbs:addButton(
    {
        title = "Get all",
        callback = function()
            cf = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
            for i, v in pairs(game.Workspace.orbFolder.City:GetChildren()) do
                if
                    (not v.Name:match("Union") and not v.Name:match("sea") and not v.Name:match("Cactus") and
                        not (v.name == "Part"))
                 then
                    -- print(v.name)
                    local inner = nil
                    for i, p in pairs(v:GetChildren()) do
                        if (p.Name:match("inner")) then
                            inner = p
                        end
                    end
                    local playerPos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
                    --local ipos=(GetPos(inner))
                    --local d=(playerPos - inner.Position).Magnitude
                    --if(inner.Position.Y<10 and not lastOrb[inner.Position] and (dist==nil or dist>d)) then dist=d;orb=inner end
                    game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = inner.CFrame
                    wait(0)
                end
            end
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = cf
        end
    }
)
local _cb_1 = false
local _cb1 = false
local __cb1 = false
local function destoryAll()
    game.ReplicatedStorage.DestroyAll:InvokeServer()
    wait(1)
end
local function openBox()
    for i, mysteryBox in pairs(game.Players.LocalPlayer.Crates:GetChildren()) do
        game.ReplicatedStorage.MysteryBox:InvokeServer(mysteryBox.Name)
    end
end

Minersdiv:addToggle(
    {
        title = "Collect Boxes",
        toggled = nil,
        callback = function(value)
            _cb1 = value
            local pos = humanoidRoot.CFrame
            while (_cb1) do
                local a, b =
                    pcall(
                    function()
                        return getClosest(Boxes()).CFrame
                    end
                )
                if a then
                    PathfindTo(b)
                    wait(1.2)
                    print("DOne")
                else
                    PathfindTo(pos)
                    wait(1.2)
                end
                wait()
            end
            PathfindTo(pos)
        end
    }
)
Minersdiv:addToggle(
    {
        title = "Auto open Boxes",
        toggled = nil,
        callback = function(value)
            __cb1 = value
            while (__cb1) do
                pcall(openBox)
            end
        end
    }
)

Minersdiv:addToggle(
    {
        title = "Collect Clovers",
        toggled = nil,
        callback = function(value)
            _cb_1 = value
            while (_cb_1) do
                local pos = humanoidRoot.CFrame
                humanoidRoot.CFrame = getClosest(Clovers()).CFrame
                wait(1.2)
                humanoidRoot.CFrame = pos
                wait(1)
                humanoidRoot.CFrame = pos
                --wait(getgenv().duration+getgenv().duration_)
            end
        end
    }
)
Minersdiv:addToggle(
    {
        title = "Legit Pathing?",
        toggled = nil,
        callback = function(value)
            LegitPathing = value
        end
    }
)
local cost1
local cost2
Minersdiv:addTextbox(
    {
        title = "layout 2 cost?",
        default = "10M",
        callback = function(text, focusLost)
            if (focusLost) then
                if conv(text) then
                    cost1 = text
                end
            end
        end
    }
)
Minersdiv:addTextbox(
    {
        title = "layout 3 cost?",
        default = "10qd",
        callback = function(text, focusLost)
            if (focusLost) then
                if conv(text) then
                    cost2 = text
                end
            end
        end
    }
)

Minersdiv:addButton(
    {
        title = "Load AutoRebirth",
        callback = function()
            defineNilLocals()
            local obj = {
                ["Catalyst of Thunder"] = {
                    name = "Draedon's Gauntlet",
                    items = {
                        "True Book of Knowledge",
                        "Tempest Refiner",
                        "Lightningbolt Predictor",
                        "Azure Purifier",
                        "Mystical Thunder",
                        "Tesla Refuter"
                    },
                    Catalyst = "Catalyst of Thunder"
                },
                ["Catalyst of Void"] = {
                    name = "Daestrophe",
                    items = {
                        "True Book of Knowledge",
                        "The Fissure",
                        "The Daegelart",
                        "Overlord's Telamonster",
                        "Eternal Fracture",
                        "Void Drive"
                    },
                    Catalyst = "Catalyst of Void"
                },
                ["Catalyst of Spirits"] = {
                    name = "Delta Phantom",
                    items = {
                        "True Book of Knowledge",
                        "Eternal Limbo",
                        "Brimstone Spires",
                        "Dark Illuminator",
                        "Forbidden Magic",
                        "Anguished Guardian of the Gate"
                    },
                    Catalyst = "Catalyst of Spirits"
                },
                ["Catalyst of Destruction"] = {
                    name = "Pandora's Box",
                    items = {
                        "True Book of Knowledge",
                        "Dreamer's Blight",
                        "Dreamer's Valor",
                        "Dreamer's Nightmare",
                        "Dreamer's Terror",
                        "Devourer of Nightmares"
                    },
                    Catalyst = "Catalyst of Destruction"
                },
                ["Catalyst of the Supreme"] = {
                    name = "Elysium Solemnity",
                    items = {
                        "True Book of Knowledge",
                        "True Overlord Device",
                        "Aethereal Synthesizer",
                        "Final Eclipse Gate",
                        "Crystal Altar",
                        "Champion Infuser"
                    },
                    Catalyst = "Catalyst of the Supreme"
                },
                ["Catalyst of Light"] = {
                    name = "Optic Origin",
                    items = {
                        "True Book of Knowledge",
                        "Morning Star",
                        "Neutron Star",
                        "Catalyzed Star",
                        "Ore Nova",
                        "Void Star"
                    },
                    Catalyst = "Catalyst of Light"
                },
                ["Catalyst of Earth"] = {
                    name = "Havium Mine",
                    items = {
                        "True Book of Knowledge",
                        "Yuttrium Mine",
                        "Symmetryte Mine",
                        "Yuntonium Mine",
                        "Solarium Mine",
                        "Gargantium Mine"
                    },
                    Catalyst = "Catalyst of Earth"
                },
                ["Catalyst of Death"] = {
                    name = "The Death Cap",
                    items = {
                        "True Book of Knowledge",
                        "Dreamer's Blight",
                        "Deadly Spore",
                        "Azure Spore",
                        "Delta Phantom",
                        "Lord of Tenebrous"
                    },
                    Catalyst = "Catalyst of Death"
                },
                ["Catalyst of Fire"] = {
                    name = "Vulcan's Wrath",
                    items = {
                        "True Book of Knowledge",
                        "Igneous Forge",
                        "Searing Heat",
                        "Spirit of Fire",
                        "Firecrystallized System",
                        "Vulcan's Destiny"
                    },
                    Catalyst = "Catalyst of Fire"
                },
                ["Catalyst of Fortune"] = {
                    name = "Midas Blaster",
                    items = {
                        "True Book of Knowledge",
                        "King Gold Mine",
                        "Massive Diamond Drill",
                        "Sage Justice",
                        "Coliseum Catharsis",
                        "Sage King"
                    },
                    Catalyst = "Catalyst of Fortune"
                },
                ["Catalyst of Power"] = {
                    name = "Tyrant's Throne",
                    items = {
                        "True Book of Knowledge",
                        "V-tolite Mine",
                        "Tyrant's Forge",
                        "Mystical Thunder",
                        "Void Drive",
                        "Gargantium Core"
                    },
                    Catalyst = "Catalyst of Power"
                },
                ["Catalyst of Nature"] = {
                    name = "Garden of Gaia",
                    items = {
                        "True Book of Knowledge",
                        "Gaia's Grasp",
                        "Dreamer's Life",
                        "Frozen Peaks",
                        "Ambrosia Garden",
                        "Deadly Spore"
                    },
                    Catalyst = "Catalyst of Nature"
                },
                ["Catalyst of Space"] = {
                    name = "Ore Hypernova",
                    items = {
                        "True Book of Knowledge",
                        "Optic Origin",
                        "Blue Supergiant",
                        "Aurora Borealis",
                        "Stardust Pulsar",
                        "Stellarite Mine"
                    },
                    Catalyst = "Catalyst of Space"
                },
                ["Catalyst of Knowledge"] = {
                    name = "Enchanted Library",
                    items = {
                        "True Book of Knowledge",
                        "Book of Knowledge",
                        "Stardust Illuminator",
                        "Statue of Knowledge",
                        "Ore Indoctrinator",
                        "Ancient Coliseum"
                    },
                    Catalyst = "Catalyst of Knowledge"
                },
                ["Catalyst of Time"] = {
                    name = "The Hourglass",
                    items = {
                        "True Book of Knowledge",
                        "Grandfather Clockwork",
                        "Interstellar Conqueror",
                        "Temporal Enchantment",
                        "Temporal Armageddon",
                        "The Trinity"
                    },
                    Catalyst = "Catalyst of Time"
                },
                ["Catalyst of Blood Magic"] = {
                    name = "Swag City",
                    items = {
                        "True Book of Knowledge",
                        "Draconicglass Mine",
                        "Azure Purifier",
                        "Dreamer's Nightmare",
                        "Funky Town",
                        "Devil's Spore"
                    },
                    Catalyst = "Catalyst of Blood Magic"
                },
                ["Catalyst of Necromancy"] = {
                    name = "Methuselah's Mask",
                    items = {
                        "True Book of Knowledge",
                        "The Death Cap",
                        "Lord of Tenebrous",
                        "Castle Bravo",
                        "Tsar Bomba",
                        "Son of Poison"
                    },
                    Catalyst = "Catalyst of Necromancy"
                },
                ["Catalyst of Magic"] = {
                    name = "Meralin's Sorcery",
                    items = {
                        "True Book of Knowledge",
                        "Forbidden Magic",
                        "Mystical Thunder",
                        "Swag City",
                        "Methuselah's Mask",
                        "Soul Blossom"
                    },
                    Catalyst = "Catalyst of Magic"
                },
                ["Catalyst of Oblivion"] = {
                    name = "The Heart of Void",
                    items = {
                        "True Book of Knowledge",
                        "Daestrophe",
                        "Void Star",
                        "Devourer of Nightmares",
                        "Oblivion Emission",
                        "The Forbidden Tome"
                    },
                    Catalyst = "Catalyst of Oblivion"
                }
            }
            Revamp.Data.Catalysts = obj
            local Fusions = {
                ["Phasecursor Mine"] = {
                    fusion = "Phasecursor Mine",
                    cost = "100k",
                    item = getItem("Phasecursor Mine"),
                    needed = {
                        ["Precursor Mine"] = {item = getItem("Precursor Mine"), count = 6},
                        ["Phase Refiner"] = {item = getItem("Phase Refiner"), count = 3}
                    }
                },
                ["Dragon Cannon"] = {
                    fusion = "Dragon Cannon",
                    cost = "200k",
                    item = getItem("Dragon Cannon"),
                    needed = {
                        ["Railgun Cannon"] = {item = getItem("Railgun Cannon"), count = 5},
                        ["Dragon Blaster"] = {item = getItem("Dragon Blaster"), count = 2}
                    }
                },
                ["Azure Spore"] = {
                    fusion = "Azure Spore",
                    cost = "75k",
                    item = getItem("Azure Spore"),
                    needed = {
                        ["Wild Spore"] = {item = getItem("Wild Spore"), count = 3},
                        ["Azure Refiner"] = {item = getItem("Azure Refiner"), count = 6}
                    }
                },
                ["Catalyzed Star"] = {
                    fusion = "Catalyzed Star",
                    cost = "150k",
                    item = getItem("Catalyzed Star"),
                    needed = {
                        ["The Catalyst"] = {item = getItem("The Catalyst"), count = 10},
                        ["Morning Star"] = {item = getItem("Morning Star"), count = 5}
                    }
                },
                ["Diamond Breech Loader"] = {
                    fusion = "Diamond Breech Loader",
                    cost = "200k",
                    item = getItem("Diamond Breech Loader"),
                    needed = {
                        ["Massive Diamond Mine"] = {item = getItem("Massive Diamond Mine"), count = 10},
                        ["Breech Loader"] = {item = getItem("Breech Loader"), count = 5}
                    }
                },
                ["Eternal Fracture"] = {
                    fusion = "Eternal Fracture",
                    cost = "100k",
                    item = getItem("Eternal Fracture"),
                    needed = {
                        ["Eternal Journey"] = {item = getItem("Eternal Journey"), count = 6},
                        ["The Fracture"] = {item = getItem("The Fracture"), count = 3}
                    }
                },
                ["Quantum Clockwork"] = {
                    fusion = "Quantum Clockwork",
                    cost = "75k",
                    item = getItem("Quantum Clockwork"),
                    needed = {
                        ["Quantum Ore Cleaner"] = {item = getItem("Quantum Ore Cleaner"), count = 10},
                        ["Clockwork"] = {item = getItem("Clockwork"), count = 5}
                    }
                },
                ["Lightningbolt Predictor"] = {
                    fusion = "Lightningbolt Predictor",
                    cost = "75k",
                    item = getItem("Lightningbolt Predictor"),
                    needed = {
                        ["Lightningbolt Refiner"] = {item = getItem("Lightningbolt Refiner"), count = 6},
                        ["Astral Predictor"] = {item = getItem("Astral Predictor"), count = 3}
                    }
                },
                ["Frozen Eclipse"] = {
                    fusion = "Frozen Eclipse",
                    cost = "75k",
                    item = getItem("Frozen Eclipse"),
                    needed = {
                        ["Frozen Justice"] = {item = getItem("Frozen Justice"), count = 3},
                        ["Gate of Eclipse"] = {item = getItem("Gate of Eclipse"), count = 6}
                    }
                },
                ["Sage Justice"] = {
                    fusion = "Sage Justice",
                    cost = "250k",
                    item = getItem("Sage Justice"),
                    needed = {
                        ["Sage Redeemer"] = {item = getItem("Sage Redeemer"), count = 5},
                        ["Blind Justice"] = {item = getItem("Blind Justice"), count = 10}
                    }
                },
                ["Dark Illuminator"] = {
                    fusion = "Dark Illuminator",
                    cost = "200k",
                    item = getItem("Dark Illuminator"),
                    needed = {
                        ["Ore Illuminator"] = {item = getItem("Ore Illuminator"), count = 4},
                        ["Dark Magic"] = {item = getItem("Dark Magic"), count = 8}
                    }
                },
                ["Symcorpium Mine"] = {
                    fusion = "Symcorpium Mine",
                    cost = "250k",
                    item = getItem("Symcorpium Mine"),
                    needed = {
                        ["Scorpium Mine"] = {item = getItem("Scorpium Mine"), count = 10},
                        ["Symmetrium Mine"] = {item = getItem("Symmetrium Mine"), count = 5}
                    }
                },
                ["Ambrosia Garden"] = {
                    fusion = "Ambrosia Garden",
                    cost = "100k",
                    item = getItem("Ambrosia Garden"),
                    needed = {
                        ["Sakura Garden"] = {item = getItem("Sakura Garden"), count = 6},
                        ["Ambrosia Fountain"] = {item = getItem("Ambrosia Fountain"), count = 3}
                    }
                },
                ["Anguished Garden"] = {
                    fusion = "Anguished Garden",
                    cost = "100k",
                    item = getItem("Anguished Garden"),
                    needed = {
                        ["Dreamer's Anguish"] = {item = getItem("Dreamer's Anguish"), count = 5},
                        ["Sakura Garden"] = {item = getItem("Sakura Garden"), count = 10}
                    }
                },
                ["Anguished Guardian of the Gate"] = {
                    fusion = "Anguished Guardian of the Gate",
                    cost = "200k",
                    item = getItem("Anguished Guardian of the Gate"),
                    needed = {
                        ["Dreamer's Anguish"] = {item = getItem("Dreamer's Anguish"), count = 4},
                        ["Guardian of the Gate"] = {item = getItem("Guardian of the Gate"), count = 8}
                    }
                },
                ["Firecrystallized System"] = {
                    fusion = "Firecrystallized System",
                    cost = "75k",
                    item = getItem("Firecrystallized System"),
                    needed = {
                        ["Industrial Firecrystal Mine"] = {item = getItem("Industrial Firecrystal Mine"), count = 4},
                        ["Crystallized System"] = {item = getItem("Crystallized System"), count = 8}
                    }
                },
                ["Illuminator Evaluator"] = {
                    fusion = "Illuminator Evaluator",
                    cost = "75k",
                    item = getItem("Illuminator Evaluator"),
                    needed = {
                        ["Ore Illuminator"] = {item = getItem("Ore Illuminator"), count = 4},
                        ["Flaming Schrodinger"] = {item = getItem("Flaming Schrodinger"), count = 8}
                    }
                },
                ["Nature's Temple"] = {
                    fusion = "Nature's Temple",
                    cost = "150k",
                    item = getItem("Nature's Temple"),
                    needed = {
                        ["Nature's Grip"] = {item = getItem("Nature's Grip"), count = 10},
                        ["Ancient Temple"] = {item = getItem("Ancient Temple"), count = 5}
                    }
                },
                ["The Pizzalyst"] = {
                    fusion = "The Pizzalyst",
                    cost = "75k",
                    item = getItem("The Pizzalyst"),
                    needed = {
                        ["The Catalyst"] = {item = getItem("The Catalyst"), count = 6},
                        ["Pizza Blaster"] = {item = getItem("Pizza Blaster"), count = 3}
                    }
                },
                ["Yuntonium Mine"] = {
                    fusion = "Yuntonium Mine",
                    cost = "150k",
                    item = getItem("Yuntonium Mine"),
                    needed = {
                        ["Newtonium Mine"] = {item = getItem("Newtonium Mine"), count = 6},
                        ["Yunium Mine"] = {item = getItem("Yunium Mine"), count = 3}
                    }
                },
                ["Massive Quantum Diamond Cleaner"] = {
                    fusion = "Massive Quantum Diamond Cleaner",
                    cost = "350k",
                    item = getItem("Massive Quantum Diamond Cleaner"),
                    needed = {
                        ["Quantum Ore Cleaner"] = {item = getItem("Quantum Ore Cleaner"), count = 13},
                        ["Massive Diamond Mine"] = {item = getItem("Massive Diamond Mine"), count = 6}
                    }
                }
            }
            Revamp.Data.Fusions = Fusions
            local Evolved = {
                ["Phase Refiner"] = {
                    cost = "75k",
                    evolved = getItem("Phase Refiner"),
                    reborn = getItem("Phase Conveyor"),
                    r = "Phase Conveyor",
                    count = 10
                },
                ["Dragon Blaster"] = {
                    cost = "150k",
                    evolved = getItem("Dragon Blaster"),
                    reborn = getItem("Blaster"),
                    r = "Blaster",
                    count = 5
                },
                ["Saturated Catalyst"] = {
                    cost = "75k",
                    evolved = getItem("Saturated Catalyst"),
                    reborn = getItem("The Catalyst"),
                    r = "The Catalyst",
                    count = 10
                },
                ["Quantum Ore Polisher"] = {
                    cost = "50k",
                    evolved = getItem("Quantum Ore Polisher"),
                    reborn = getItem("Quantum Ore Cleaner"),
                    r = "Quantum Ore Cleaner",
                    count = 7
                },
                ["Deadly Spore"] = {
                    cost = "100k",
                    evolved = getItem("Deadly Spore"),
                    reborn = getItem("Wild Spore"),
                    r = "Wild Spore",
                    count = 12
                },
                ["Symmetryte Mine"] = {
                    cost = "200k",
                    evolved = getItem("Symmetryte Mine"),
                    reborn = getItem("Symmetrium Mine"),
                    r = "Symmetrium Mine",
                    count = 8
                },
                ["Swift Justice"] = {
                    cost = "75k",
                    evolved = getItem("Swift Justice"),
                    reborn = getItem("Blind Justice"),
                    r = "Blind Justice",
                    count = 7
                },
                ["Sakura Falls"] = {
                    cost = "100k",
                    evolved = getItem("Sakura Falls"),
                    reborn = getItem("Sakura Garden"),
                    r = "Sakura Garden",
                    count = 7
                },
                ["Neutron Star"] = {
                    cost = "100k",
                    evolved = getItem("Neutron Star"),
                    reborn = getItem("Red Giant"),
                    r = "Red Giant",
                    count = 10
                },
                ["Astral Setter"] = {
                    cost = "50k",
                    evolved = getItem("Astral Setter"),
                    reborn = getItem("Astral Predictor"),
                    r = "Astral Predictor",
                    count = 12
                },
                ["Sage King"] = {
                    cost = "50k",
                    evolved = getItem("Sage King"),
                    reborn = getItem("Sage Redeemer"),
                    r = "Sage Redeemer",
                    count = 12
                },
                ["Final Eclipse Gate"] = {
                    cost = "75k",
                    evolved = getItem("Final Eclipse Gate"),
                    reborn = getItem("Gate of Eclipse"),
                    r = "Gate of Eclipse",
                    count = 10
                },
                ["Ambrosia Forest"] = {
                    cost = "50k",
                    evolved = getItem("Ambrosia Forest"),
                    reborn = getItem("Ambrosia Fountain"),
                    r = "Ambrosia Fountain",
                    count = 7
                },
                ["Ancient Coliseum"] = {
                    cost = "50k",
                    evolved = getItem("Ancient Coliseum"),
                    reborn = getItem("Ancient Temple"),
                    r = "Ancient Temple",
                    count = 10
                },
                ["Newtonium Excavator"] = {
                    cost = "150k",
                    evolved = getItem("Newtonium Excavator"),
                    reborn = getItem("Newtonium Mine"),
                    r = "Newtonium Mine",
                    count = 14
                },
                ["Tesla Refuter"] = {
                    cost = "100k",
                    evolved = getItem("Tesla Refuter"),
                    reborn = getItem("Tesla Resetter"),
                    r = "Tesla Resetter",
                    count = 10
                },
                ["Super Schrodinger"] = {
                    cost = "75k",
                    evolved = getItem("Super Schrodinger"),
                    reborn = getItem("Flaming Schrodinger"),
                    r = "Flaming Schrodinger",
                    count = 12
                },
                ["Frozen Peaks"] = {
                    cost = "50k",
                    evolved = getItem("Frozen Peaks"),
                    reborn = getItem("Frozen Justice"),
                    r = "Frozen Justice",
                    count = 9
                },
                ["Forbidden Magic"] = {
                    cost = "75k",
                    evolved = getItem("Forbidden Magic"),
                    reborn = getItem("Dark Magic"),
                    r = "Dark Magic",
                    count = 12
                },
                ["Massive Diamond Drill"] = {
                    cost = "50k",
                    evolved = getItem("Massive Diamond Drill"),
                    reborn = getItem("Massive Diamond Mine"),
                    r = "Massive Diamond Mine",
                    count = 9
                },
                ["Ore Indoctrinator"] = {
                    cost = "666k",
                    evolved = getItem("Ore Indoctrinator"),
                    reborn = getItem("Ore Illuminator"),
                    r = "Ore Illuminator",
                    count = 66
                },
                ["Dreamer's Nightmare"] = {
                    cost = "150k",
                    evolved = getItem("Dreamer's Nightmare"),
                    reborn = getItem("Dreamer's Anguish"),
                    r = "Dreamer's Anguish",
                    count = 7
                },
                ["Dreamer's Terror"] = {
                    cost = "150k",
                    evolved = getItem("Dreamer's Terror"),
                    reborn = getItem("Dreamer's Fright"),
                    r = "Dreamer's Fright",
                    count = 50
                },
                ["Zenith Will"] = {
                    cost = "200k",
                    evolved = getItem("Zenith Will"),
                    reborn = getItem("Righteous Will"),
                    r = "Righteous Will",
                    count = 20
                },
                ["Draconicglass Mine"] = {
                    cost = "150k",
                    evolved = getItem("Draconicglass Mine"),
                    reborn = getItem("Dragonglass Mine"),
                    r = "Dragonglass Mine",
                    count = 15
                },
                ["The Daegelart"] = {
                    cost = "150k",
                    evolved = getItem("The Daegelart"),
                    reborn = getItem("The Abomination"),
                    r = "The Abomination",
                    count = 10
                },
                ["Tsar Bomba"] = {
                    cost = "1M",
                    evolved = getItem("Tsar Bomba"),
                    reborn = getItem("Big Bertha"),
                    r = "Big Bertha",
                    count = 100
                },
                ["Aethereal Synthesizer"] = {
                    cost = "100k",
                    evolved = getItem("Aethereal Synthesizer"),
                    reborn = getItem("Aether Refinery"),
                    r = "Aether Refinery",
                    count = 15
                },
                ["The Fissure"] = {
                    cost = "75k",
                    evolved = getItem("The Fissure"),
                    reborn = getItem("The Fracture"),
                    r = "The Fracture",
                    count = 10
                },
                ["Pizza Bombarder"] = {
                    cost = "75k",
                    evolved = getItem("Pizza Bombarder"),
                    reborn = getItem("Pizza Blaster"),
                    r = "Pizza Blaster",
                    count = 10
                },
                ["Yuttrium Mine"] = {
                    cost = "75k",
                    evolved = getItem("Yuttrium Mine"),
                    reborn = getItem("Yunium Mine"),
                    r = "Yunium Mine",
                    count = 11
                },
                ["Crystallized Engine"] = {
                    cost = "75k",
                    evolved = getItem("Crystallized Engine"),
                    reborn = getItem("Crystallized System"),
                    r = "Crystallized System",
                    count = 8
                },
                ["Eternal Limbo"] = {
                    cost = "100k",
                    evolved = getItem("Eternal Limbo"),
                    reborn = getItem("Eternal Journey"),
                    r = "Eternal Journey",
                    count = 20
                },
                ["Tempest Refiner"] = {
                    cost = "200k",
                    evolved = getItem("Tempest Refiner"),
                    reborn = getItem("Lightningbolt Refiner"),
                    r = "Lightningbolt Refiner",
                    count = 20
                },
                ["Grandfather Clockwork"] = {
                    cost = "100k",
                    evolved = getItem("Grandfather Clockwork"),
                    reborn = getItem("Clockwork"),
                    r = "Clockwork",
                    count = 11
                },
                ["Turbine Chamber"] = {
                    cost = "125k",
                    evolved = getItem("Turbine Chamber"),
                    reborn = getItem("Cooling Chamber"),
                    r = "Cooling Chamber",
                    count = 11
                },
                ["Atomyke Mine"] = {
                    cost = "150k",
                    evolved = getItem("Atomyke Mine"),
                    reborn = getItem("Atomium Mine"),
                    r = "Atomium Mine",
                    count = 15
                },
                ["V-tolite Mine"] = {
                    cost = "150k",
                    evolved = getItem("V-tolite Mine"),
                    reborn = getItem("Pilotite Mine"),
                    r = "Pilotite Mine",
                    count = 7
                },
                ["Dimension Extractor"] = {
                    cost = "250k",
                    evolved = getItem("Dimension Extractor"),
                    reborn = getItem("Breech Loader"),
                    r = "Breech Loader",
                    count = 12
                },
                ["Azure Purifier"] = {
                    cost = "75k",
                    evolved = getItem("Azure Purifier"),
                    reborn = getItem("Azure Refiner"),
                    r = "Azure Refiner",
                    count = 9
                },
                ["Searing Heat"] = {
                    cost = "75k",
                    evolved = getItem("Searing Heat"),
                    reborn = getItem("Scorching Heat"),
                    r = "Scorching Heat",
                    count = 8
                },
                ["Atmospheric Steamwork"] = {
                    cost = "50k",
                    evolved = getItem("Atmospheric Steamwork"),
                    reborn = getItem("Gravitational Gearwork"),
                    r = "Gravitational Gearwork",
                    count = 13
                },
                ["Dreamer's Valor"] = {
                    cost = "100k",
                    evolved = getItem("Dreamer's Valor"),
                    reborn = getItem("Dreamer's Might"),
                    r = "Dreamer's Might",
                    count = 25
                },
                ["Guardian of the Portal"] = {
                    cost = "75k",
                    evolved = getItem("Guardian of the Portal"),
                    reborn = getItem("Guardian of the Gate"),
                    r = "Guardian of the Gate",
                    count = 12
                },
                ["Atlantic Monument"] = {
                    cost = "75k",
                    evolved = getItem("Atlantic Monument"),
                    reborn = getItem("Atlantic Monolith"),
                    r = "Atlantic Monolith",
                    count = 10
                },
                ["Breached Motherboard"] = {
                    cost = "100k",
                    evolved = getItem("Breached Motherboard"),
                    reborn = getItem("Invasive Cyberlord"),
                    r = "Invasive Cyberlord",
                    count = 10
                },
                ["Phase Bombarder"] = {
                    cost = "75k",
                    evolved = getItem("Phase Bombarder"),
                    reborn = getItem("Phase Refiner"),
                    r = "Phase Refiner",
                    count = 11
                },
                ["Gaia's Grasp"] = {
                    cost = "100k",
                    evolved = getItem("Gaia's Grasp"),
                    reborn = getItem("Nature's Grip"),
                    r = "Nature's Grip",
                    count = 20
                },
                ["Mad Monsterous Melter"] = {
                    cost = "300k",
                    evolved = getItem("Mad Monsterous Melter"),
                    reborn = getItem("Big Bad Blaster"),
                    r = "Big Bad Blaster",
                    count = 20
                },
                ["Ore Chainsaw"] = {
                    cost = "300k",
                    evolved = getItem("Ore Chainsaw"),
                    reborn = getItem("Ore Sawmill"),
                    r = "Ore Sawmill",
                    count = 28
                },
                ["Scorponyte Mine"] = {
                    cost = "125k",
                    evolved = getItem("Scorponyte Mine"),
                    reborn = getItem("Scorpium Mine"),
                    r = "Scorpium Mine",
                    count = 17
                },
                ["Temporal Enchantment"] = {
                    cost = "100k",
                    evolved = getItem("Temporal Enchantment"),
                    reborn = getItem("Timeless Enhancement"),
                    r = "Timeless Enhancement",
                    count = 25
                },
                ["Banana Sundae Refiner"] = {
                    cost = "100k",
                    evolved = getItem("Banana Sundae Refiner"),
                    reborn = getItem("Banana Split Upgrader"),
                    r = "Banana Split Upgrader",
                    count = 7
                },
                ["Temporal Armageddon"] = {
                    cost = "600k",
                    evolved = getItem("Temporal Armageddon"),
                    reborn = getItem("Fractured Reality"),
                    r = "Fractured Reality",
                    count = 30
                },
                ["Shard City"] = {
                    cost = "350k",
                    evolved = getItem("Shard City"),
                    reborn = getItem("Shard Park"),
                    r = "Shard Park",
                    count = 15
                },
                ["Green Tea Kettle"] = {
                    cost = "50k",
                    evolved = getItem("Green Tea Kettle"),
                    reborn = getItem("Green Tea Latte"),
                    r = "Green Tea Latte",
                    count = 7
                },
                ["Solar Eruption"] = {
                    cost = "50k",
                    evolved = getItem("Solar Eruption"),
                    reborn = getItem("Solar Flare"),
                    r = "Solar Flare",
                    count = 16
                },
                ["Lunar Bombardment"] = {
                    cost = "50k",
                    evolved = getItem("Lunar Bombardment"),
                    reborn = getItem("Solar Flare"),
                    r = "Solar Flare",
                    count = 16
                },
                ["Nuclear Castle"] = {
                    cost = "500k",
                    evolved = getItem("Nuclear Castle"),
                    reborn = getItem("Nuclear Stronghold"),
                    r = "Nuclear Stronghold",
                    count = 20
                },
                ["Demon Core"] = {
                    cost = "125k",
                    evolved = getItem("Demon Core"),
                    reborn = getItem("Toxic Waste Disposal"),
                    r = "Toxic Waste Disposal",
                    count = 10
                },
                ["Industrial Firegem Quarry"] = {
                    cost = "80k",
                    evolved = getItem("Industrial Firegem Quarry"),
                    reborn = getItem("Industrial Firecrystal Mine"),
                    r = "Industrial Firecrystal Mine",
                    count = 7
                },
                ["Heavenly Flux"] = {
                    cost = "250k",
                    evolved = getItem("Heavenly Flux"),
                    reborn = getItem("Skyliner Flux"),
                    r = "Skyliner Flux",
                    count = 8
                },
                ["Vortex Singularity"] = {
                    cost = "400k",
                    evolved = getItem("Vortex Singularity"),
                    reborn = getItem("Vortex Chamber"),
                    r = "Vortex Chamber",
                    count = 15
                }
            }
            Revamp.Data.Evolved = Evolved
            for catalyst, data in pairs(obj) do
                data.Item = getItem(catalyst)
                print("Added:" .. catalyst)
            end
            for catalyst, data in pairs(obj) do
                data.Item = getItem(catalyst)
                for item, _ in data.items do
                    data[_] = getItem(_)
                end
                print("Added:" .. catalyst)
            end

            hasCat = function(catalystName)
                local catalystData = obj[catalystName]
                if not catalystData then
                    print("Catalyst not found: " .. catalystName)
                    return false
                end

                local missingItems = {}

                for _, itemName in ipairs(catalystData.items) do
                    local item = getItem(itemName)
                    if not HasItem(item.ItemId.Value) then
                        table.insert(missingItems, itemName)
                    end
                end

                if #missingItems == 0 then
                    print("All items required for " .. catalystName .. " are present.")
                    return true
                else
                    print("Missing items for " .. catalystName .. ":")
                    for _, missingItem in ipairs(missingItems) do
                        print("- " .. missingItem)
                        -- Check if the missing item is an evolved item
                        if Evolved[missingItem] then
                            local evolutionData = Evolved[missingItem]
                            local baseItem = evolutionData.reborn
                            local requiredCount = evolutionData.count
                            local currentCount = HasItem(baseItem.ItemId.Value, true)
                            if currentCount >= requiredCount then
                                print("  You can evolve " .. baseItem.Name .. " into " .. missingItem .. ".")
                            else
                                print("  You need " .. (requiredCount - currentCount) .. " more " .. baseItem.Name .. "(s) to evolve into " .. missingItem .. ".")
                            end
                        end
                        -- Check if the missing item is a fusion item
                        if Fusions[missingItem] then
                            local fusionData = Fusions[missingItem]
                            print("  To create " .. missingItem .. ", you need:")
                            for componentName, componentData in pairs(fusionData.needed) do
                                local componentItem = componentData.item
                                local requiredCount = componentData.count
                                local currentCount = HasItem(componentItem.ItemId.Value, true)
                                if currentCount >= requiredCount then
                                    print("    - " .. componentName .. ": You have enough.")
                                else
                                    print("    - " .. componentName .. ": You need " .. (requiredCount - currentCount) .. " more.")
                                end
                            end
                        end
                        -- Check if the missing item is available in the shop
                        if IsShopItem(item.ItemId.Value) then
                            print("  " .. missingItem .. " is available in the shop.")
                        else
                            print("  " .. missingItem .. " is not available in the shop. Check other sources.")
                        end
                    end
                    return false
                end

            end
            Revamp.Inventory.hasCat = hasCat
            local oldPos
            goTo = function()
                TycoonBase = game.Players.LocalPlayer.PlayerTycoon.Value.Base
                if GetDistanceBetweenCFrame(TycoonBase.CFrame, root.CFrame) > 100 then
                    oldPos = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame
                    if finding then
                        pathfindingComplete = true
                    end
                    PathfindTo(TycoonBase.CFrame, 2)
                end
            end
            goBack = function()
                if (oldPos) then
                    PathfindTo(oldPos)
                end
                oldPos = nil
            end
            Revamp.Pathing.goTo = goTo
            Revamp.Pathing.goBack = goBack
            local library =
                loadstring(
                game:HttpGet(
                    "https://raw.githubusercontent.com/TheAbsolutionism/Wally-GUI-Library-V2-Remastered/main/Library%20Code",
                    true
                )
            )() --//Wally UI Lib V2 Remastered by: https://forum.robloxscripts.com/showthread.php?tid=3180
            library.options.underlinecolor = "rainbow" --//makes the underline of each "window" rainbow
            library.options.toggledisplay = "Fill" --//Applies to all toggles, [Fill] OFF = RED, ON = GREEN [CHECK] OFF = BLANK,ON = CHECKMARK
            local mainW = library:CreateWindow("Miner's Haven") --//Name of window
            local Section = mainW:Section("Farm", true)

            --//AntiAFK Credits to: https://v3rmillion.net/showthread.php?tid=772135
            local vu = game:GetService("VirtualUser")
            game:GetService("Players").LocalPlayer.Idled:connect(
                function()
                    vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(1)
                    vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end
            )
            --//AntiAFK Credits to: https://v3rmillion.net/showthread.php?tid=772135

            --//Enables Rebirth Farming
            local reFarm =
                mainW:Toggle(
                "Rebirth Farm",
                {flag = "rebfarm"},
                function()
                    if mainW.flags.rebfarm then
                        loadLayouts()
                        farmRebirth()
                    end
                end
            )

            --//User chooses if they want second layout to be used
            local tFarm =
                mainW:Toggle(
                "Enable Second Layout?",
                {flag = "seclayout"},
                function()
                end
            )
            local tFarm_ =
                mainW:Toggle(
                "Enable Third Layout?",
                {flag = "thirdlayout"},
                function()
                end
            )
            local _tFarm_ =
                mainW:Toggle(
                "Clear after first layout?",
                {flag = "seclayoutclear"},
                function()
                end
            )
            local tFarm_ =
                mainW:Toggle(
                "Clear after second layout?",
                {flag = "thirdlayoutclear"},
                function()
                end
            )
            local RFarm_ =
                mainW:Toggle(
                "Rebirths with layout?",
                {flag = "rebirthWL"},
                function()
                end
            )

            --//Auto Rebirth Toggle
            local autoReb =
                mainW:Toggle(
                "Auto Rebirth",
                {flag = "aReb"},
                function()
                    farmRebirth()
                end
            )

            --//Input time between layouts
            local timeBox =
                mainW:Box(
                "Time first layout",
                {
                    default = 0,
                    type = "number",
                    min = 0,
                    max = 9999, --//You can change this to math.huge if u want. (Currently set to 60 Seconds / 1 Minute)
                    flag = "duration",
                    location = {getgenv()}
                },
                function(new)
                    getgenv().duration = new
                end
            )
            local timeBox_ =
                mainW:Box(
                "Time second layout",
                {
                    default = 0,
                    type = "number",
                    min = 0,
                    max = 9999, --//You can change this to math.huge if u want. (Currently set to 60 Seconds / 1 Minute)
                    flag = "duration2",
                    location = {getgenv()}
                },
                function(new)
                    getgenv().duration2 = new
                end
            )

            --//Select First Layout
            mainW:Dropdown(
                "First Layout",
                {
                    default = "First Layout",
                    location = getgenv(),
                    flag = "layoutone",
                    list = {
                        "Layout1",
                        "Layout2",
                        "Layout3"
                    }
                },
                function()
                    print("Selected: " .. getgenv().layoutone)
                end
            )

            --//Select Second Layout
            mainW:Dropdown(
                "Second Layout",
                {
                    default = "Second Layout",
                    location = getgenv(),
                    flag = "layoutwo",
                    list = {
                        "Layout1",
                        "Layout2",
                        "Layout3"
                    }
                },
                function()
                    print("Selected: " .. getgenv().layoutwo)
                end
            )
            --//Select Third Layout
            mainW:Dropdown(
                "Third Layout",
                {
                    default = "Third Layout",
                    location = getgenv(),
                    flag = "layouthree",
                    list = {
                        "Layout1",
                        "Layout2",
                        "Layout3"
                    }
                },
                function()
                    print("Selected: " .. getgenv().layouthree)
                end
            )

            mainW:Dropdown(
                "Rebrith W Layout",
                {
                    default = "Rebirth Layout",
                    location = getgenv(),
                    flag = "rebirthlayout",
                    list = {
                        "Layout1",
                        "Layout2",
                        "Layout3"
                    }
                },
                function()
                    print("Selected: " .. getgenv().rebirthlayout)
                end
            )

            loadLayouts = function()
                task.spawn(
                    function()
                        goTo()
                        wait(.5)
                        game:GetService("ReplicatedStorage").Layouts:InvokeServer("Load", getgenv().layoutone) --//Loads first layout
                        wait(.1)
                        goBack()
                        --task.wait(getgenv().duration) --//Duration between layouts
                        if mainW.flags.seclayout then --//Checks if "Enable second layout" toggle is true
                            repeat
                                wait(0)
                            until comparCash(cost1)
                            if (mainW.flags.seclayoutclear) then
                                goTo()
                                wait(.5)
                                destroyAll()
                                wait(.1)
                                goBack()
                            end
                            goTo()
                            wait(.2)
                            game:GetService("ReplicatedStorage").Layouts:InvokeServer("Load", getgenv().layoutwo) --//Loads second layout
                            wait(.1)
                            goBack()
                            task.wait(getgenv().duration_)
                            if mainW.flags.thirdlayout then --//Checks if "Enable second layout" toggle is true
                                repeat
                                    wait(0)
                                until comparCash(cost2)
                                if (mainW.flags.thirdlayoutclear) then
                                    goTo()
                                    wait(.5)
                                    destroyAll()
                                    wait(.1)
                                    goBack()
                                end
                                goTo()
                                wait(.2)
                                game:GetService("ReplicatedStorage").Layouts:InvokeServer("Load", getgenv().layouthree) --//Loads third layout
                                wait(.1)
                                goBack()
                            end
                        end
                    end
                )
            end
            Revamp.Farming.loadLayouts = loadLayouts

            --//Auto Rebirth Function
            farmRebirth = function()
                print("Print trying auto?")
                task.spawn(
                    function()
                        print("Auto Going?")
                        while mainW.flags.aReb do
                            local canRebirth =
                                game:GetService("Players").LocalPlayer.PlayerGui.GUI.Money.Value >=
                                MoneyLibary.RebornPrice(game:GetService("Players").LocalPlayer)
                            wait(0)
                            --print("----------------------------")
                            --print(canRebirth)
                            if canRebirth then
                                if mainW.flags.rebirthWl then
                                    print("With Layouth")
                                    goTo()
                                    wait(.2)
                                    game:GetService("ReplicatedStorage").Layouts:InvokeServer(
                                        "Load",
                                        getgenv().rebirthlayout
                                    )
                                    wait(.7)
                                    game:GetService("ReplicatedStorage").Rebirth:InvokeServer(26) --// I dont know what "26" means dont change it.
                                    task.wait()
                                    wait(.1)
                                    goBack()
                                else
                                    print("WithoutLayout")
                                    goTo()
                                    wait(.2)
                                    game:GetService("ReplicatedStorage").Rebirth:InvokeServer(26) --// I dont know what "26" means dont change it.
                                    task.wait()
                                    wait(.1)
                                    goBack()
                                end
                            end
                        end
                    end
                )
            end
            Revamp.Farming.farmRebirth = farmRebirth
            Revamp.Farming.MinerFarm = farmRebirth

            --//Auto Load
            value:GetPropertyChangedSignal("Value"):Connect(
                function()
                    task.wait(0.75)
                    if mainW.flags.rebfarm then
                        loadLayouts()
                    end
                end
            )
            --//Auto Load
        end
    }
)

Gameplaydiv:addTextbox(
    {
        title = "Force Join Pack",
        default = "Case Sensitive",
        callback = function(text, focusLost)
            if (focusLost) then
                for i, v in pairs(game.Workspace.Teams:GetChildren()) do
                    if string.find(text, v.Name) then
                        game:GetService("ReplicatedStorage").acceptedEvent:FireServer(v.Name)
                    end
                end
            end
        end
    }
)

Gameplaydiv:addButton(
    {
        title = "Print All Teams (F9)",
        callback = function()
            for i, v in pairs(game.Workspace.Teams:GetChildren()) do
                print(v.Name)
            end
        end
    }
)

Gameplaydiv:addTextbox(
    {
        title = "Force Player Ride",
        default = "Case Sensitive",
        callback = function(text, focusLost)
            if (focusLost) then
                for i, v in pairs(game.Players:GetChildren()) do
                    if string.find(v.Name, text) then
                        game:GetService("ReplicatedStorage").RideEvents.acceptEvent:FireServer(v.Name)
                    end
                end
            end
        end
    }
)

local Theme =
    UI:addPage(
    {
        title = "Theme",
        icon = 4890363233
    }
)

local Colors =
    Theme:addSection(
    {
        title = "Colors"
    }
)

for theme, color in pairs(Themes) do
    Colors:addColorPicker(
        {
            title = theme,
            default = color,
            callback = function(color3)
                UI:setTheme(
                    {
                        theme = theme,
                        color3 = color3
                    }
                )
            end
        }
    )
end

UI:SelectPage(
    {
        page = UI.pages[1],
        toggle = true
    }
)
--_G.speed=0.05;_G.toggle=true while _G.toggle == true do for i,v in pairs(game.Workspace:GetDescendants()) do if v:IsA("BasePart") and not v:IsA('Terrain') and (v.Name:match("Egg") or v.Name:match("Tre")) then wait(_G.speed);game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.CFrame end end print("done");end
print("Loaded")
local localInfo = {}
local function findDmg(taken)
    if (taken == nil) then
        taken = 0
    end
    for _, v in pairs(game:GetService("Players"):GetPlayers()) do
        local Zoned = getPos()
        if (true) then
            local l = v.leaderstats.Level.value
            local info = {
                lvl = v.leaderstats.Level.value,
                dmg = l * 2,
                hp = (l * 2) * 10,
                player = v
            }
            --game.Players.LocalPlayer
            print("@", v.name, "#", v.leaderstats.Level.value, "$", info.dmg)
            if ((l * 2) == (taken - 10)) then
                print("Found:" .. v.name)
                return info
            end
        end
    end
end

local function isInsideSafeZone(position)
    if not position or not SafeZoneXZ or not SafeZoneXZ.x.min or not SafeZoneXZ.x.max then
        return false
    end
    local x, z = position.X, position.Z
    return x >= SafeZoneXZ.x.min and x <= SafeZoneXZ.x.max and z >= SafeZoneXZ.z.min and z <= SafeZoneXZ.z.max
end

local function engageEnemy(enemy)
    if not enemy or not _G.autoPVP then
        return
    end

    local targetPlayer = enemy.player
    if not targetPlayer then
        return
    end

    local localPlayer = game.Players.LocalPlayer
    local localCharacter = localPlayer.Character
    if not localCharacter then
        return
    end
    local localRootPart = localCharacter:FindFirstChild("HumanoidRootPart")
    if not localRootPart then
        return
    end

    local allowedLevel = increaseByPercentage(localPlayer.leaderstats.Level.value, incDMG_)
    if allowedLevel < enemy.lvl then
        warn(targetPlayer.Name .. " is too strong")
        return
    end

    local targetCharacter = targetPlayer.Character
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetHumanoid or not targetRoot then
        return
    end
    updated_()
    if isInsideSafeZone(targetRoot.Position) then
        print(string.format("[AutoPVP] %s E-Zoned (already safe).", targetPlayer.Name))
        return
    end
    local originalCF = localRootPart.CFrame

    if attacking_ then
        return
    end

    attacking_ = true
    Jump_()
    autoJump = true

    local lastHumanoid = targetHumanoid

    while _G.autoPVP do
        targetCharacter = targetPlayer.Character
        targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
        targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

        if not targetHumanoid or not targetRoot then
            break
        end

        if isInsideSafeZone(targetRoot.Position) then
            print(string.format("[AutoPVP] %s EZ zone", targetPlayer.Name))
            break
        end

        if targetHumanoid ~= lastHumanoid then
            lastHumanoid = targetHumanoid
        end

        hitHumanoid(targetHumanoid)
        humanoid:MoveTo(targetRoot.Position)

        if targetHumanoid.Health <= 0 then
            break
        end

        wait(0.1)
    end

    attacking_ = false
    autoJump = false

    if not _G.autoPVP then
        return
    end

    if LegitPathing then
        moveToTarget(originalCF)
    else
        pcall(function()
            localRootPart.CFrame = originalCF
        end)
    end
end

_G.log6 = true
_G.log5 = false
local function hptp()
    local Humanoid = game.Players.LocalPlayer.Character.Humanoid
    local OldHealth = Humanoid.Health

    Humanoid:GetPropertyChangedSignal("Health"):Connect(
        function()
            local percent = OldHealth / Humanoid.Health
            local percent2 = Humanoid.Health / OldHealth

            if (_G.log6 == false) then
                return
            end
            if (Humanoid.Health < 1) then
                deathPose = game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame
                justDied=true
            end
            pcall(
                function()
                    if Humanoid.Health < OldHealth then
                        --game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame =CFrame.new(newPos)
                        local enemy = findDmg(OldHealth - Humanoid.Health)
                        print("damage taken", OldHealth - Humanoid.Health)
                        engageEnemy(enemy)
                    else
                        print("Healed", Humanoid.Health - OldHealth)
                    end
                end
            )
            OldHealth = Humanoid.Health
        end
    )
end
local Players = game:GetService("Players")
for _, player in pairs(game:GetService("Players"):GetPlayers()) do
end
game.Players.LocalPlayer.CharacterAdded:Connect(
    function(char)
        defineLocals()
        pcall(updated_)
        updated_()
        justDied=false
        if deathPose then
            moveToTarget(deathPose)
            game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart").CFrame = deathPose
        end
        hptp()
    end
)
defineLocals()
pcall(updated_)
updated_()
hptp()
spawn(
function()
    local placeId = game.PlaceId
print(placeId)

local AnimalSim={
    main=5712833750,
    PvP=13399356664
}
Revamp.Data.AnimalSim = AnimalSim
-- List of select player names to protect automaticaly from others
local selectedPlayers = {
    "282475249a7auto","9","Allaboutsuki","DefNotRealMe","Doornextguythat","Little_Puppywolf","ProGammerMove_1","RektBySuki","RektBySukisAlt","Rockyrode112","Rose_altl5","Sakura_Mirai","SimpleDisasters","TheBestAccount_mom","TheFreeAccount_Free1","TheOneMyth","Unicornzzz6109","baby46793","batman_kite","foalsarecut","iwillendUmadaf4","Miner_havennoob","naypolm","naypolm005","naypolm05","naypolm12","naypolm1789","qwertyPCLOL","ll_BANX","xXxnothingxXx274", "dexvilxtails","ninja1098583","J_esusTheCreator","L_ilBoomStick","TheReal_SigmaG","SpongeBobStartFish","HeyNo_ThatsBa","TheFreeAccount_Free1","PeanutNox2180","Tsubakidoki"    -- Add more player names as needed
}
Revamp.Logging.selectedPlayers = selectedPlayers
local localPlayer = game.Players.LocalPlayer
if localPlayer then
    for i, playerName in ipairs(selectedPlayers) do
        if playerName == localPlayer.Name then
            table.remove(selectedPlayers, i)
            break
        end
    end
end

-- Dictionary to store initial health values for selected players
-- Function to log damage taken by selected players
local function LogDamage(player, damageAmount)

    if damageAmount<0 then damageAmount=-damageAmount end
    print(player.Name .. " took " .. damageAmount .. " damage")
    local enemy = findDmg(damageAmount)
    if not enemy then
        return
    end
    print(
        "IncDMG:",
        increaseByPercentage(game.Players.LocalPlayer.leaderstats.Level.value, incDMG_),
        enemy.lvl
    )
    engageEnemy(enemy)
    -- You can add more advanced logging or processing here if needed
end

-- Dictionary to store initial health values for selected players
local initialHealth = {}

-- Function to log events for selected players
local function LogEvent(player, event)
    print(player.Name .. " " .. event)
    -- You can add more advanced logging or processing here if needed
end

-- Function to connect to the player's health changes
local function ConnectHealthChanged(player)
    local function DisconnectHealthChanged()
        repeat wait(0) until player.Character:FindFirstChild("Humanoid");
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            initialHealth[player] = humanoid.Health

            local healthChangedConnection
            print("Connected HP",player)
            healthChangedConnection = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
                local currentHealth = humanoid.Health
                local initialHealthValue = initialHealth[player]
                LogDamage(player,initialHealthValue - currentHealth)
                LogEvent(player, "health changed by " .. (initialHealthValue - currentHealth))
                initialHealth[player] = currentHealth
            end)

            player.Character.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil then
                    print("Disconnected HP",player)
                    healthChangedConnection:Disconnect()
                end
            end)
        end
    end

    player.CharacterAdded:Connect(function()
        LogEvent(player, "character changed")
        DisconnectHealthChanged()
        -- Reconnect the event for the new character
    end)
    DisconnectHealthChanged()
end

-- Check existing players for selected names
for _, playerName in ipairs(selectedPlayers) do
    local existingPlayer = game.Players:FindFirstChild(playerName)
    if existingPlayer then
        LogEvent(existingPlayer, "joined")
        ConnectHealthChanged(existingPlayer)
    end
end

-- Connect to the PlayerAdded event for future players
game.Players.PlayerAdded:Connect(function(player)
    for _, playerName in ipairs(selectedPlayers) do
        if player.Name == playerName then
            LogEvent(player, "joined")
            ConnectHealthChanged(player)
        end
    end
end)
end
)

--[[
    Expose core helpers through the Revamp table so other scripts can opt into specific systems
    without traversing the entire legacy file. These assignments intentionally sit at the bottom
    to ensure every dependency is defined before export.
]]
Revamp.Utilities.teamCheck = teamCheck
Revamp.Utilities.findClosestPlayer = findClosestPlayer
Revamp.Utilities.PredictPlayerPosition = PredictPlayerPosition
Revamp.Utilities.teleportInFrontOfPlayer = teleportInFrontOfPlayer
Revamp.Utilities.increaseByPercentage = increaseByPercentage
Revamp.Utilities.defineNilLocals = defineNilLocals
Revamp.Utilities.waitForChar = waitForChar
Revamp.Utilities.defineLocals = defineLocals
Revamp.Utilities.updateSelectedPlayer = updateSelectedPlayer
Revamp.Utilities.stayNearPlayer = stayNearPlayer
Revamp.Utilities.CombineCFrameAndVector = CombineCFrameAndVector
Revamp.Utilities.conv = conv
Revamp.Utilities.comparCash = comparCash
Revamp.Utilities.updated = updated_
Revamp.Utilities.dist = dist
Revamp.Utilities.waitDoneMove = waitDoneMove
Revamp.Utilities.getClosest = getClosest
Revamp.Utilities.myTeam = myTeam
Revamp.Utilities.getTeams = getTeams
Revamp.Utilities.getPos = getPos
Revamp.Utilities.fire = fire
Revamp.Utilities.findDmg = findDmg
Revamp.Utilities.hptp = hptp
Revamp.Utilities.isInsideSafeZone = isInsideSafeZone

Revamp.Pathing.getPathToPosition = getPathToPosition
Revamp.Pathing.moveToTarget = moveToTarget
Revamp.Pathing.PathfindTo = PathfindTo
Revamp.Pathing.followPath = followPath
Revamp.Pathing.MoveTo = MoveTo
Revamp.Pathing.tp = tp
Revamp.Pathing.goTo = goTo
Revamp.Pathing.goBack = goBack

Revamp.Combat.BloxFruit = BloxFruit
Revamp.Combat.heal = heal
Revamp.Combat.useAllFire = useAllFire
Revamp.Combat.useAllFireFromPosition = useAllFire_
Revamp.Combat.destroyAll = destroyAll
Revamp.Combat.damageplayer = damageplayer
Revamp.Combat.aura = aura
Revamp.Combat.dmgloop = dmgloop
Revamp.Combat.toggleFarm = toggleFarm
Revamp.Combat.toggleAura = toggleAura
Revamp.Combat.findPlr = findPlr
Revamp.Combat.farm = farm
Revamp.Combat.farmPassive = farm_
Revamp.Combat.Jump = Jump_
Revamp.Combat.v2 = v2
Revamp.Combat.engageEnemy = engageEnemy

Revamp.Farming.Clovers = Clovers
Revamp.Farming.Boxes = Boxes
Revamp.Farming.MHBox = MHBox
Revamp.Farming.destoryAll = destoryAll
Revamp.Farming.openBox = openBox
Revamp.Farming.loadLayouts = loadLayouts
Revamp.Farming.farmRebirth = farmRebirth
Revamp.Farming.MinerFarm = farmRebirth

Revamp.Inventory.getItem = getItem
Revamp.Inventory.ItemPlaced = ItemPlaced
Revamp.Inventory.ShopItems = ShopItems
Revamp.Inventory.HasItem = HasItem
Revamp.Inventory.IsShopItem = IsShopItem
Revamp.Inventory.hasCat = hasCat
Revamp.Inventory.GetDistanceBetweenCFrame = GetDistanceBetweenCFrame

Revamp.Logging.LogDamage = LogDamage
Revamp.Logging.LogEvent = LogEvent
Revamp.Logging.ConnectHealthChanged = ConnectHealthChanged
Revamp.Logging.initialHealth = initialHealth

Revamp.Services.Players = Players or game:GetService("Players")
Revamp.Services.RunService = RunService or game:GetService("RunService")
Revamp.Services.PathfindingService = PathfindingService or game:GetService("PathfindingService")
Revamp.Services.UserInputService = userInputService or game:GetService("UserInputService")
Revamp.Services.ReplicatedStorage = game:GetService("ReplicatedStorage")

Revamp.State.incDMG = incDMG_
Revamp.State.justDied = justDied
Revamp.State.autoJump = autoJump
Revamp.State.autoFight = autoFight
Revamp.State.autoSelectTarget = usertarget

getgenv().RevampLua = Revamp

return Revamp
