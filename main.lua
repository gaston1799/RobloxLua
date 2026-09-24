--[[
    Main Loader - Universal Game Script Loader
    Loads Venyx UI once, passes to game-specific scripts
]]

print("[Main Loader] ========================================")
print("[Main Loader] Starting Gaston1799 Bot Loader...")
print("[Main Loader] ========================================")

print("[Main Loader] [1/5] Waiting for game to load...")
if not game:IsLoaded() then
    game.Loaded:Wait()
end
print("[Main Loader] [1/5] ✓ Game loaded!")

print("[Main Loader] [2/5] Getting game services...")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    print("[Main Loader] [2/5] ✗ ERROR: LocalPlayer not found!")
    return
end
print("[Main Loader] [2/5] ✓ LocalPlayer ready!")

-- ===== VENYX UI LOADER =====

local venyx
local function loadVenyx()
    if venyx then return venyx end

    print("[Main Loader] [3/5] Loading Venyx UI library...")
    print("[Main Loader]      Trying: venyx_source.lua (local)...")

    -- Try local first (with SetOptions support)
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/venyx_source.lua"))()
    end)

    if ok then
        venyx = result
        print("[Main Loader] [3/5] ✓ Venyx loaded from local!")
        return venyx
    end

    print("[Main Loader]      ✗ Local failed, trying remote...")
    print("[Main Loader]      Trying: Stefanuk12/Venyx-UI-Library...")

    ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    end)

    if ok then
        venyx = result
        print("[Main Loader] [3/5] ✓ Venyx loaded from remote!")
        return venyx
    end

    print("[Main Loader] [3/5] ✗ ERROR: Venyx load failed!")
    return nil
end

-- ===== PREFIXES LOADER =====

local prefixes = {}
local function loadPrefixes()
    if #prefixes > 0 then return prefixes end
    
    print("[Main Loader] Loading prefixes...")
    
    local ok, result = pcall(function()
        local json = game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/lib/prefixes.json")
        return game:GetService("HttpService"):JSONDecode(json)
    end)
    
    if ok and result then
        prefixes = result
        print("[Main Loader] ✓ Prefixes loaded (" .. #prefixes .. " entries)")
        return prefixes
    end
    
    print("[Main Loader] ✗ Prefixes unavailable, using empty table")
    prefixes = {}
    return prefixes
end

-- ===== FALLBACK UI BUILDER (Game Script Provides Main, Combat, AutoZone) =====

local function buildGameUI(ui)
    print("[Game UI] ⚠ Fallback: Game script should provide Main/Combat/AutoZone pages")
    -- Don't create duplicate pages - v2 will create Main, Combat, AutoZone
end

-- ===== MAIN EXECUTION =====

print("[Main Loader] Waiting for game to load...")
if not game:IsLoaded() then
    game.Loaded:Wait()
end

print("[Main Loader] Game loaded!")

-- Load Venyx
venyx = loadVenyx()
if not venyx then
    error("[Main Loader] CRITICAL: Venyx failed to load")
end

print("[Main Loader] ✓ Venyx loaded")

-- ===== BUILD BASE UI (Debugging + Misc) =====

local function buildBaseUI(ui)
    print("[Main Loader] Building base UI...")

    -- Debugging Tools page
    local debugPage = ui:addPage({title = "Debug Tools"})
    local debugSection = debugPage:addSection({title = "Utilities"})

    debugSection:addButton({
        title = "Dex Explorer",
        callback = function()
            print("[Debug] Loading Dex Explorer...")
            loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/master/dex.lua"))()
        end,
    })

    debugSection:addButton({
        title = "Infinite Yield",
        callback = function()
            print("[Debug] Loading Infinite Yield...")
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end,
    })

    debugSection:addButton({
        title = "Script Executor",
        callback = function()
            print("[Debug] Use Dex or IY to execute scripts")
        end,
    })

    -- Misc page
    local miscPage = ui:addPage({title = "Misc"})
    local miscSection = miscPage:addSection({title = "General"})

    miscSection:addButton({
        title = "Clear Chat",
        callback = function()
            print("[Misc] Chat cleared (manually)")
        end,
    })

    print("[Main Loader] ✓ Base UI built")
    return ui
end

-- Create base UI window with branding
local ui = venyx.new({title = "Gaston1799 Bot"})

-- Build and store UI
buildBaseUI(ui)
_G.venyx = ui
print("[Main Loader] ✓ UI stored in _G.venyx")

-- Load game script from lua branch
print("[Main Loader] [4/5] Loading game-specific script...")
local placeId = game.PlaceId
print("[Main Loader]      PlaceID: " .. placeId)

local gameScriptUrl = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/" .. placeId .. "-v2.lua"
print("[Main Loader]      URL: " .. gameScriptUrl)
print("[Main Loader]      Downloading...")

local ok, err = pcall(function()
    local script = game:HttpGet(gameScriptUrl)
    if script and #script > 0 then
        print("[Main Loader]      ✓ Downloaded! (" .. #script .. " bytes)")
        print("[Main Loader]      Executing game script...")
        loadstring(script)()
        print("[Main Loader] [4/5] ✓ Game script executed!")
    else
        print("[Main Loader]      ✗ Script empty!")
    end
end)

if not ok then
    print("[Main Loader] [4/5] ✗ Game script failed: " .. tostring(err))
    print("[Main Loader]      Using fallback UI...")
    buildGameUI(ui)
else
    print("[Main Loader] [4/5] ✓ Game script loaded successfully!")
end

print("[Main Loader] [5/5] ========================================")
print("[Main Loader] [5/5] ✓ Bot Ready!")
print("[Main Loader] [5/5] ========================================")
