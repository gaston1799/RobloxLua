--[[
    Placeholder module for PlaceId 98927955463992.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_THEME = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255),
}

local PlaceholderPlace = {
    PlaceId = 98927955463992,
    Services = {
        ReplicatedStorage = ReplicatedStorage,
    },
    State = {
        version = 1.00,
    },
    Modules = {
        Utilities = {},
        Gameplay = {},
    },
    UI = {
        instances = {},
        defaults = {
            theme = DEFAULT_THEME,
        },
    },
}

local function nameHasZombie(value)
    return string.find(string.lower(value), "zombie", 1, true) ~= nil
end

local function hasZombieName(instance)
    local current = instance
    while current do
        if nameHasZombie(current.Name) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function splitPath(path)
    local segments = {}
    for part in string.gmatch(path, "[^%.]+") do
        segments[#segments + 1] = part
    end
    return segments
end

local function commonPathPrefix(paths)
    if #paths == 0 then
        return nil
    end

    local prefix = splitPath(paths[1])
    for i = 2, #paths do
        local segments = splitPath(paths[i])
        local nextPrefix = {}
        local limit = math.min(#prefix, #segments)
        for j = 1, limit do
            if prefix[j] ~= segments[j] then
                break
            end
            nextPrefix[#nextPrefix + 1] = prefix[j]
        end
        prefix = nextPrefix
        if #prefix == 0 then
            break
        end
    end

    return table.concat(prefix, ".")
end

local function ancestorChain(instance)
    local chain = {}
    local current = instance
    while current do
        table.insert(chain, 1, current)
        current = current.Parent
    end
    return chain
end

local function commonAncestor(instances)
    if #instances == 0 then
        return nil
    end

    local common = ancestorChain(instances[1])
    for i = 2, #instances do
        local chain = ancestorChain(instances[i])
        local nextCommon = {}
        local limit = math.min(#common, #chain)
        for j = 1, limit do
            if common[j] ~= chain[j] then
                break
            end
            nextCommon[#nextCommon + 1] = common[j]
        end
        common = nextCommon
        if #common == 0 then
            break
        end
    end

    return common[#common]
end

local function scanZombieHumanoids()
    local matches = {}
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Humanoid") and hasZombieName(instance) then
            matches[#matches + 1] = instance
        end
    end
    return matches
end

local function logZombieHumanoids()
    local matches = scanZombieHumanoids()
    if #matches == 0 then
        warn("[ZombieScan] No humanoids found with 'zombie' in the name.")
        return
    end

    local parentPaths = {}
    local parentInstances = {}
    for index, humanoid in ipairs(matches) do
        local parent = humanoid.Parent
        local path = parent and parent:GetFullName() or humanoid:GetFullName()
        parentPaths[#parentPaths + 1] = path
        parentInstances[#parentInstances + 1] = parent or humanoid
        print(("[ZombieScan] %d) %s (Humanoid: %s)"):format(index, path, humanoid:GetFullName()))
    end

    local commonPath = commonPathPrefix(parentPaths)
    if commonPath and commonPath ~= "" then
        print(("[ZombieScan] Common folder path: %s"):format(commonPath))
    else
        print("[ZombieScan] Common folder path: <none>")
    end

    local ancestor = commonAncestor(parentInstances)
    if ancestor then
        print(("[ZombieScan] Common ancestor instance: %s"):format(ancestor:GetFullName()))
    end
end

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/libRebound/Venyx.lua"))()
    local ui = venyx.new({ title = "Revamp - Placeholder" })

    local placeholderPage = ui:addPage({ title = "Menu" })
    local section = placeholderPage:addSection({ title = "Zombie Scan" })
    section:addButton({
        title = "Scan Zombies",
        callback = logZombieHumanoids,
    })

    PlaceholderPlace.UI.instances.library = venyx
    PlaceholderPlace.UI.instances.ui = ui
    return venyx, ui
end

function PlaceholderPlace.init()
    if game.PlaceId ~= PlaceholderPlace.PlaceId then
        return
    end

    local venyx, ui = buildUI()
    logZombieHumanoids()
    if venyx and ui then
        return {
            library = venyx,
            ui = ui,
            defaultTheme = DEFAULT_THEME,
            defaultPageIndex = 1,
            module = PlaceholderPlace,
        }
    end
end

return PlaceholderPlace
