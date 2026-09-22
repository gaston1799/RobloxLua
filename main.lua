--[[
    Revamp Main Loader
    - Loads shared libs (Venyx, Prefixes)
    - Loads game-specific script by PlaceID
    - Passes libs to game script init()
]]

print("[Loader] Starting...")

-- Get lib loaders (don't call them yet - let game scripts decide)
local loadVenyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/lib/venyx.lua"))()
local loadPrefixes = loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/lib/prefixes.lua"))()
print("[Loader] ✓ Loaded lib loaders")

local placeID = game.PlaceId
local MODULE_BASE_URL = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua"

local function tryLoadPlaceModule(moduleName)
    local url = ("%s/%s.lua"):format(MODULE_BASE_URL, moduleName)
    print(("[Loader] Trying %s.lua for PlaceID %s"):format(moduleName, placeID))

    local fetched, response = pcall(game.HttpGet, game, url)
    if not fetched then
        print(("[Loader] ✗ Request failed: %s"):format(tostring(response)))
        return false, response
    end
    if type(response) ~= "string" or response:match("^%s*$") then
        print(("[Loader] ✗ Empty response"))
        return false, "empty"
    end

    local chunk, compileErr = loadstring(response, ("=%s.lua"):format(moduleName))
    if not chunk then
        print(("[Loader] ✗ Compile error: %s"):format(tostring(compileErr)))
        return false, compileErr
    end

    local ok, moduleTable = pcall(chunk)
    if not ok then
        print(("[Loader] ✗ Load error: %s"):format(tostring(moduleTable)))
        return false, moduleTable
    end

    if type(moduleTable) ~= "table" or type(moduleTable.init) ~= "function" then
        print(("[Loader] ✗ Missing init() function"):format())
        return false, "no init"
    end

    print(("[Loader] ✓ Loaded %s.lua"):format(moduleName))
    return true, moduleTable
end

local baseName = tostring(placeID)
local v2Name = baseName .. "-v2"

-- Try v2 first
local success, gameScript = tryLoadPlaceModule(v2Name)
if not success then
    -- Fallback to base name
    success, gameScript = tryLoadPlaceModule(baseName)
end

if success then
    print("[Loader] Initializing game script...")
    gameScript.init(loadVenyx, loadPrefixes)
    print("[Loader] ✓ Done!")
else
    warn("[Loader] Failed to load game script for PlaceID", placeID)
end
