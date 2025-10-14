--[[
    Legend of Speed Automation Template
    Place ID: 3101667897

    This template mirrors the Legend of Speed specific structure that should
    be extracted from `CodeToBeBrokenDown.lua`. Use it to port orb farming,
    race automation, and XP helpers into a dedicated file.
]]

local LegendOfSpeed = {
    PlaceId = 3101667897,
    Services = {},
    Data = {
        OrbSpawns = {},
        Races = {}
    },
    State = {
        autoOrbs = false,
        autoRace = false,
        autoRebirth = false
    },
    UI = {
        Pages = {}
    },
    Modules = {
        Utilities = {},
        Pathing = {},
        Farming = {},
        Combat = {},
        Logging = {}
    }
}

--[[
    Section: Service References & Core Locals
    TODO: Copy the Roblox services and local variables used for orb farming
    (player, humanoidRootPart, orbFolder references, etc.).
]]

--[[
    Section: Utility Helpers
    TODO: Implement shared helpers that Legend of Speed requires, such as:
      * Player/character retrieval wrappers
      * Teleport helpers for moving between orb spawns
      * Timer utilities for race countdowns
]]

LegendOfSpeed.Modules.Utilities.todos = {
    "Orb folder discovery and caching",
    "Player/character safety checks",
    "Race timer utilities"
}

--[[
    Section: Pathing Module
    TODO: Provide movement helpers for quickly travelling between orbs and
    race checkpoints.
]]

LegendOfSpeed.Modules.Pathing.todos = {
    "Teleport/move routines for orb collection",
    "Checkpoint navigation for races"
}

--[[
    Section: Farming Module
    TODO: Port the orb farming logic (looping through Workspace.orbFolder
    descendants) and any XP/rebirth helpers tied to Legend of Speed.
]]

LegendOfSpeed.Modules.Farming.todos = {
    "Orb collection loop (Workspace.orbFolder.City:GetChildren())",
    "XP/rebirth automation stubs"
}

--[[
    Section: Combat Module
    NOTE: Legend of Speed does not rely on combat logic; leave empty unless
    future features require it.
]]

LegendOfSpeed.Modules.Combat.todos = {
    "Not applicable for current Legend of Speed features"
}

--[[
    Section: Logging Module
    TODO: Add logging if telemetry or debugging is required for races.
]]

LegendOfSpeed.Modules.Logging.todos = {
    "Add race/XP logging if desired"
}

--[[
    Section: UI Layout (Venyx Library)
    TODO: Build the Legend of Speed specific UI sections.
]]

LegendOfSpeed.UI.Pages.LegendOfSpeed = {
    title = "LoS",
    sections = {
        Orbs = {
            buttons = {
                "Get all"
            }
        }
    },
    notes = {
        "Button should iterate Workspace.orbFolder.City like the unified script",
        "Add additional sections for race/XP automation as needed"
    }
}

--[[
    Optional Shared Pages
    TODO: Include Theme/Colors or other shared pages if they remain part of
    the Legend of Speed experience after splitting.
]]

LegendOfSpeed.UI.Pages.Theme = {
    title = "Theme",
    sections = {
        Colors = {
            colorPickers = {
                "Background",
                "Glow",
                "Accent",
                "LightContrast",
                "DarkContrast",
                "TextColor"
            }
        }
    }
}

--[[
    Initialization Stub
    TODO: Gate execution by PlaceId, initialise services, bind UI, and start
    orb/race automation according to toggles.
]]

function LegendOfSpeed.init()
    error("Legend of Speed template stub - implement init() during split")
end

return LegendOfSpeed
