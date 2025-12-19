--[[
    Boba Stand Game split.
    Placeholder module for PlaceId 136723874788185.
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

local BobaStand = {
    PlaceId = 136723874788185,
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

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/libRebound/Venyx.lua"))()
    local ui = venyx.new({ title = "Revamp - Boba Stand" })

    local bobaPage = ui:addPage({ title = "Boba" })
    local placeholder = bobaPage:addSection({ title = "Placeholder" })
    placeholder:addButton({
        title = ("Random Button %d"):format(math.random(1, 9999)),
        callback = function()
            print("[BobaStand] Placeholder button clicked")
        end,
    })

    BobaStand.UI.instances.library = venyx
    BobaStand.UI.instances.ui = ui
    return venyx, ui
end

function BobaStand.init()
    if game.PlaceId ~= BobaStand.PlaceId then
        return
    end

    local venyx, ui = buildUI()
    if venyx and ui then
        return {
            library = venyx,
            ui = ui,
            defaultTheme = DEFAULT_THEME,
            defaultPageIndex = 1,
            module = BobaStand,
        }
    end
end

return BobaStand

