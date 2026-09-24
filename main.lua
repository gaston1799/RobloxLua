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

-- Fetch a remote script. Returns the source, or nil + a printed reason.
-- A GitHub 404 does NOT raise an error - it comes back as the body "404: Not Found" -
-- so that has to be detected explicitly or it reaches loadstring as bogus source.
local function fetchRemote(url, label)
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        print("[Main Loader] ✗ " .. label .. " HttpGet failed: " .. tostring(result))
        return nil
    end

    local body = result
    if type(body) ~= "string" or #body == 0 then
        print("[Main Loader] ✗ " .. label .. " is empty")
        return nil
    end

    if body:sub(1, 3) == "404" or body:sub(1, 1) == "<" then
        print("[Main Loader] ✗ " .. label .. " not found on branch 'lua' (remote replied: " .. body:sub(1, 32) .. ")")
        return nil
    end

    print("[Main Loader] ✓ " .. label .. " downloaded (" .. #body .. " bytes)")
    return body
end

-- Load one place script and hand it the Venyx UI window. The script receives the UI as
-- its first argument, so inside <placeId>-v2.lua it is read with:  local ui = ...
local function runGameScript(placeId, suffix, ui)
    local label = tostring(placeId) .. suffix
    local url = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/" .. label

    local source = fetchRemote(url, label)
    if not source then return false end

    -- Compile BEFORE executing: if the remote file has a syntax error, this reports the
    -- real compiler message. Calling loadstring(source)() straight away would instead
    -- try to call nil and show "attempt to call a nil value", hiding the actual cause.
    local chunk, compileErr = loadstring(source)
    if not chunk then
        print("[Main Loader] ✗ " .. label .. " COMPILE ERROR: " .. tostring(compileErr))
        return false
    end

    _G.buildAnimalSimUI = nil   -- drop any hook left over from an earlier run
    local ok, result = pcall(chunk, ui)
    if not ok then
        print("[Main Loader] ✗ " .. label .. " RUNTIME ERROR: " .. tostring(result))
        return false
    end

    -- Legacy contract: a script may register a builder instead of using its argument.
    if type(_G.buildAnimalSimUI) == "function" then
        print("[Main Loader] --> script registered buildAnimalSimUI, calling it with the Venyx UI")
        local ok2, err2 = pcall(_G.buildAnimalSimUI, ui)
        if not ok2 then
            print("[Main Loader] ✗ buildAnimalSimUI failed: " .. tostring(err2))
            return false
        end
    end

    print("[Main Loader] ✓ " .. label .. " loaded, UI attached")
    return true
end

-- Preferred script is <placeId>-v2.lua; <placeId>.lua is the fallback.
local function loadGameScript(placeId, ui)
    print("[Main Loader] Detected PlaceID: " .. placeId)
    print("[Main Loader] Looking for the place script (v2 first)...")

    if runGameScript(placeId, "-v2.lua", ui) then return true end
    print("[Main Loader] --> -v2 not usable, trying " .. placeId .. ".lua")

    if runGameScript(placeId, ".lua", ui) then return true end

    print("[Main Loader] ✗ No usable game script for PlaceID " .. placeId)
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
    success = loadGameScript(placeId, ui)
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
