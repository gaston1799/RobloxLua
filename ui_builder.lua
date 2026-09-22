--[[
    New Animal Sim UI Builder
    Structure: Combat | PVP Bot | AutoZone | Hit-to-Kill | Misc
]]

local function buildUI(venyx)
    if not venyx then
        error("[AnimalSim] Venyx UI library required")
    end

    local ui = venyx.new({title = "Animal Sim PVP"})
    local mainPage = ui:addPage({title = "Main"})

    -- ===== COMBAT SECTION =====
    local combatSection = mainPage:addSection({title = "Combat"})

    local function collectPlayerNames()
        local names = {}
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player ~= game:GetService("Players").LocalPlayer then
                table.insert(names, player.Name)
            end
        end
        table.sort(names)
        return names
    end

    local targetDropdown = combatSection:addDropdown({
        title = "Set Target Player",
        list = collectPlayerNames(),
        callback = function(playerName)
            if playerName then
                local Players = game:GetService("Players")
                AnimalSim.State.selectedPlayer = Players:FindFirstChild(playerName)
            end
        end,
    })

    combatSection:addToggle({
        title = "Auto PVP",
        toggled = AnimalSim.State.autoPVP,
        callback = function(val)
            if setAutoPVP then setAutoPVP(val) end
        end,
    })

    combatSection:addToggle({
        title = "Auto Eat",
        toggled = false,
        callback = function(val)
            if val then
                if startAutoEat then startAutoEat() end
            else
                if stopAutoEat then stopAutoEat() end
            end
        end,
    })

    combatSection:addToggle({
        title = "Auto Fireball (Engaged)",
        toggled = false,
        callback = function(val)
            if val then
                if startAutoFireball then startAutoFireball() end
            else
                if stopAutoFireball then stopAutoFireball() end
            end
        end,
    })

    combatSection:addButton({
        title = "Damage Player",
        callback = function()
            if damageplayer then
                damageplayer(AnimalSim.State.selectedPlayer and AnimalSim.State.selectedPlayer.Name)
            end
        end,
    })

    -- ===== PVP BOT SECTION =====
    local pvpBotSection = mainPage:addSection({title = "PVP Bot"})

    pvpBotSection:addToggle({
        title = "Enable PVP Bot",
        toggled = false,
        callback = function(val)
            if _G.PVPBot then
                if val then _G.PVPBot.start() else _G.PVPBot.stop() end
            end
        end,
    })

    pvpBotSection:addToggle({
        title = "Auto Sprint",
        toggled = false,
        callback = function(val)
            if _G.PVPBot then _G.PVPBot.setAutoSprint(val) end
        end,
    })

    pvpBotSection:addToggle({
        title = "Auto Re-engage",
        toggled = false,
        callback = function(val)
            if _G.PVPBot then _G.PVPBot.setAutoReengage(val) end
        end,
    })

    local botTargetDropdown = pvpBotSection:addDropdown({
        title = "PVP Bot Target",
        list = collectPlayerNames(),
        callback = function(playerName)
            if playerName and _G.PVPBot then
                local player = game:GetService("Players"):FindFirstChild(playerName)
                if player then _G.PVPBot.setTarget(player) end
            end
        end,
    })

    -- ===== AUTOZONE SECTION =====
    local autozoneSection = mainPage:addSection({title = "AutoZone"})

    autozoneSection:addToggle({
        title = "Auto Zone (kills all outside safe)",
        toggled = AnimalSim.State.autoZone,
        callback = function(val)
            if setAutoZone then setAutoZone(val) end
        end,
    })

    autozoneSection:addToggle({
        title = "Follow Ally",
        toggled = AnimalSim.State.followAlly,
        callback = function(val)
            AnimalSim.State.followAlly = val
        end,
    })

    autozoneSection:addSlider({
        title = "Ally Follow Min Dist",
        min = 0,
        max = 500,
        default = AnimalSim.Modules.Combat.AutoZoneConfig.followAllyMinDistance or 3,
        precision = 0,
        callback = function(val)
            if AnimalSim.Modules.Combat.AutoZoneConfig then
                AnimalSim.Modules.Combat.AutoZoneConfig.followAllyMinDistance = tonumber(val) or 3
            end
        end,
    })

    autozoneSection:addSlider({
        title = "Ally Target Range",
        min = 0,
        max = 500,
        default = AnimalSim.Modules.Combat.AutoZoneConfig.followAllyTargetRange or 20,
        precision = 0,
        callback = function(val)
            if AnimalSim.Modules.Combat.AutoZoneConfig then
                AnimalSim.Modules.Combat.AutoZoneConfig.followAllyTargetRange = tonumber(val) or 20
            end
        end,
    })

    autozoneSection:addToggle({
        title = "Auto Zone Fakeouts",
        toggled = AnimalSim.State.autoZoneFakeouts,
        callback = function(val)
            AnimalSim.State.autoZoneFakeouts = val
        end,
    })

    -- ===== HIT-TO-KILL SECTION =====
    local ratioSection = mainPage:addSection({title = "Hit-to-Kill Ratio"})

    ratioSection:addSlider({
        title = "Damage Multiplier",
        min = 0.1,
        max = 2,
        default = 1,
        precision = 1,
        callback = function(val)
            -- Stores multiplier for damage calculations
            _G.DamageMultiplier = tonumber(val) or 1
        end,
    })

    ratioSection:addButton({
        title = "Show Damage Info",
        callback = function()
            print("[Hit-to-Kill] Run damage_ratio_probe for live calculations")
        end,
    })

    -- ===== MISC SECTION =====
    local miscSection = mainPage:addSection({title = "Misc"})

    miscSection:addToggle({
        title = "Remember Walkspeed",
        toggled = AnimalSim.State.rememberWalkspeed,
        callback = function(val)
            AnimalSim.State.rememberWalkspeed = val
        end,
    })

    miscSection:addToggle({
        title = "Movement Visualizer",
        toggled = AnimalSim.State.visualizerEnabled,
        callback = function(val)
            if setVisualizerEnabled then setVisualizerEnabled(val) end
        end,
    })

    miscSection:addToggle({
        title = "Use Target",
        toggled = AnimalSim.State.followTarget,
        callback = function(val)
            if setFollowTargetEnabled then setFollowTargetEnabled(val) end
        end,
    })

    miscSection:addButton({
        title = "Load AW Script",
        callback = function()
            if loadAwScript then loadAwScript() end
        end,
    })

    -- Store UI reference
    AnimalSim.UI.instances.library = venyx
    AnimalSim.UI.instances.ui = ui

    return venyx, ui
end

-- Export
return buildUI
