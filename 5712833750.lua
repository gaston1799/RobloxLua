--[[
    Animal Simulator - PVP Bot (Minimal Version)
    PlaceID: 5712833750
    Simplified to load via main.lua without initialization errors
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ===== BUILD UI FUNCTION =====
local function buildUI(ui)
    if not ui then
        print("[AnimalSim] ERROR: UI object is nil!")
        return
    end

    print("[AnimalSim] Building game-specific pages...")

    -- Main page
    local mainPage = ui:addPage({title = "Main"})
    local mainSection = mainPage:addSection({title = "Bot Status"})

    mainSection:addLabel({text = "Advanced PVP Bot v2"})
    mainSection:addLabel({text = "Status: Ready"})

    mainSection:addToggle({
        title = "Bot Enabled",
        toggled = false,
        callback = function(val)
            print("[AnimalSim] Bot toggled: " .. tostring(val))
        end,
    })

    -- Combat page
    local combatPage = ui:addPage({title = "Combat"})
    local combatSection = combatPage:addSection({title = "Settings"})

    combatSection:addSlider({
        title = "Hit-to-Kill Ratio",
        min = 0.1,
        max = 2.0,
        default = 1.0,
        rounding = 0.1,
        callback = function(val)
            print("[Combat] Ratio: " .. val)
        end,
    })

    combatSection:addToggle({
        title = "Auto PVP",
        toggled = false,
        callback = function(val)
            print("[Combat] Auto PVP: " .. tostring(val))
        end,
    })

    -- AutoZone page
    local azPage = ui:addPage({title = "AutoZone"})
    local azSection = azPage:addSection({title = "Settings"})

    azSection:addToggle({
        title = "AutoZone Enabled",
        toggled = false,
        callback = function(val)
            print("[AutoZone] Enabled: " .. tostring(val))
        end,
    })

    azSection:addToggle({
        title = "Follow Ally",
        toggled = false,
        callback = function(val)
            print("[AutoZone] Follow Ally: " .. tostring(val))
        end,
    })

    print("[AnimalSim] ✓ UI built successfully!")
    return ui
end

-- Store buildUI globally for main.lua to call
_G.buildAnimalSimUI = buildUI

print("[AnimalSim] Script loaded and ready for UI injection!")
