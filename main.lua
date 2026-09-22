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
    
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    end)
    
    if ok then
        venyx = result
        print("[Main Loader] ✓ Venyx loaded from remote")
        return venyx
    end
    
    print("[Main Loader] ✗ Remote failed, trying local fallback...")
    print("[Main Loader] ✗ No local Venyx available")
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

-- Store Venyx in global for game scripts
_G.venyx = venyx
print("[Main Loader] ✓ Venyx stored in _G.venyx")

-- Load game script based on PlaceID
local placeId = game.PlaceId
local success = loadGameScript(placeId)

if not success then
    print("[Main Loader] ✗ No script available for PlaceID " .. placeId)
end

print("[Main Loader] Done!")
