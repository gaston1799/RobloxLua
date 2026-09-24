local placeID = game.PlaceId
local MODULE_BASE_URL = "https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/lua"

local function tryLoadPlaceModule(moduleName)
    local url = ("%s/%s.lua"):format(MODULE_BASE_URL, moduleName)
    print(("[Loader] Trying %s.lua"):format(moduleName))

    local fetched, response = pcall(game.HttpGet, game, url)
    if not fetched then
        return false
    end
    if type(response) ~= "string" or response:match("^%s*$") then
        return false
    end

    local chunk = loadstring(response, ("=%s.lua"):format(moduleName))
    if not chunk then
        return false
    end

    print(("[Loader] ✓ Loaded %s.lua"):format(moduleName))
    chunk()
    return true
end

local baseName = tostring(placeID)
local v2Name = baseName .. "-v2"

-- Try game-specific v2 first
if tryLoadPlaceModule(v2Name) then
    return
end

-- Try game-specific fallback
if tryLoadPlaceModule(baseName) then
    return
end

-- Load v2 as default
print("[Loader] Loading v2.lua as default")
tryLoadPlaceModule("v2")
