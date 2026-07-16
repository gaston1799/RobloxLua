-- Animal Simulator title/health probe. Read-only: it only inspects and prints live state.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local TITLE_BONUSES = {
    ["executioner"] = 25000,
    ["destroyer"] = 50000,
    ["supreme reaper"] = 100000,
    ["notorious gladiator"] = 250000,
    ["legend"] = 500000,
    ["god"] = 1000000,
}

local VALUE_CLASSES = {
    BoolValue = true,
    IntValue = true,
    NumberValue = true,
    StringValue = true,
}

local lastSnapshots = {}

local function normalize(text)
    return tostring(text or ""):lower():gsub("[%c%p]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function detectTitle(text)
    local normalized = normalize(text)
    for title, bonus in pairs(TITLE_BONUSES) do
        if normalized:find(title, 1, true) then
            return title, bonus
        end
    end
end

local function readAttributes(instance)
    local result = {}
    if not instance then return result end
    for name, value in pairs(instance:GetAttributes()) do
        local key = name:lower()
        if key:find("title", 1, true) or key:find("health", 1, true) or key:find("hp", 1, true) then
            result[name] = tostring(value)
        end
    end
    return result
end

local function readValues(root)
    local result = {}
    if not root then return result end
    for _, descendant in ipairs(root:GetDescendants()) do
        if VALUE_CLASSES[descendant.ClassName] then
            local key = descendant.Name:lower()
            if key:find("title", 1, true) or key:find("health", 1, true) or key:find("hp", 1, true) then
                result[descendant:GetFullName()] = tostring(descendant.Value)
            end
        end
    end
    return result
end

local function readHeadGui(head)
    local result = {}
    local detectedTitle, detectedBonus
    if not head then return result end

    for _, descendant in ipairs(head:GetDescendants()) do
        local value
        if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
            value = descendant.Text
        elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
            value = descendant.Image
        end

        if value and value ~= "" then
            result[descendant:GetFullName()] = value
            local title, bonus = detectTitle(value)
            if title then
                detectedTitle, detectedBonus = title, bonus
            end
        end
    end

    return result, detectedTitle, detectedBonus
end

local function snapshot(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local head = character and character:FindFirstChild("Head")
    local headGui, title, titleBonus = readHeadGui(head)

    return {
        player = player.Name,
        displayName = player.DisplayName,
        title = title or "UNKNOWN",
        configuredTitleBonus = titleBonus or 0,
        health = humanoid and humanoid.Health or nil,
        maxHealth = humanoid and humanoid.MaxHealth or nil,
        playerAttributes = readAttributes(player),
        characterAttributes = readAttributes(character),
        relevantValues = readValues(player),
        headGui = headGui,
    }
end

local function scan()
    for _, player in ipairs(Players:GetPlayers()) do
        local data = snapshot(player)
        local encoded = HttpService:JSONEncode(data)
        if lastSnapshots[player] ~= encoded then
            lastSnapshots[player] = encoded
            print(("[TitleProbe] %s"):format(encoded))
        end
    end

    for player in pairs(lastSnapshots) do
        if player.Parent ~= Players then
            lastSnapshots[player] = nil
        end
    end
end

local environment = (getgenv and getgenv()) or _G
environment.STOP_ANIMAL_TITLE_PROBE = false

print("[TitleProbe] Started. Set getgenv().STOP_ANIMAL_TITLE_PROBE = true to stop.")
while not environment.STOP_ANIMAL_TITLE_PROBE do
    scan()
    task.wait(1)
end
print("[TitleProbe] Stopped.")
