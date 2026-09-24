--[[
    Main Loader - Universal Game Script Loader
    Loads Venyx UI once, passes to game-specific scripts
    Tries <placeid>-v2.lua first, then <placeid>.lua fallback
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("[Main Loader] Starting...")

-- ===== VENYX UI LOADER =====

local venyx
local function loadVenyx()
    if venyx then return venyx end

    print("[Main Loader] Loading Venyx UI...")

    -- Try local first (with SetOptions support)
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/venyx_source.lua"))()
    end)

    if ok then
        venyx = result
        print("[Main Loader] ✓ Venyx loaded from local (with SetOptions)")
        return venyx
    end

    print("[Main Loader] ✗ Local failed, trying remote...")

    ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    end)

    if ok then
        venyx = result
        print("[Main Loader] ✓ Venyx loaded from remote (fallback)")
        return venyx
    end

    print("[Main Loader] ✗ No Venyx available")
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

-- ===== GAME SCRIPT LOADER =====

local function loadGameScript(placeId)
    print("[Main Loader] Detected PlaceID: " .. placeId)
    
    -- Try v2 first
    local v2Url = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/" .. placeId .. "-v2.lua"
    print("[Main Loader] Trying " .. placeId .. "-v2.lua...")
    
    local ok, result = pcall(function()
        local script = game:HttpGet(v2Url)
        return loadstring(script)()
    end)
    
    if ok then
        print("[Main Loader] ✓ Loaded " .. placeId .. "-v2.lua")
        return true
    end
    
    print("[Main Loader] v2 not found, trying " .. placeId .. ".lua...")
    
    -- Fallback to base script
    local baseUrl = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/" .. placeId .. ".lua"
    ok, result = pcall(function()
        local script = game:HttpGet(baseUrl)
        return loadstring(script)()
    end)
    
    if ok then
        print("[Main Loader] ✓ Loaded " .. placeId .. ".lua")
        return true
    end
    
    print("[Main Loader] ✗ Neither script found")
    return false
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

-- Load game script based on PlaceID
print("[Main Loader] Loading game-specific script...")
local placeId = game.PlaceId
print("[Main Loader] PlaceID: " .. placeId)

local success = false
local ok, err = pcall(function()
    success = loadGameScript(placeId)
end)

if not ok then
    print("[Main Loader] ERROR loading game script: " .. tostring(err))
elseif not success then
    print("[Main Loader] ✗ No game script for PlaceID " .. placeId)
    print("[Main Loader] Only Debug Tools + Misc available")
else
    print("[Main Loader] ✓ Game script loaded successfully")
end

print("[Main Loader] ✓ Ready!")
