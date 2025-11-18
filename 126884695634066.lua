--[[
    Grow a Garden (PlaceId 126884695634066)
    Minimal loader with quick buttons to pull up the default GAG menu and Speed Hub X.
]]

local DEFAULT_THEME = {
    Background = Color3.fromRGB(24, 24, 24),
    Glow = Color3.fromRGB(0, 0, 0),
    Accent = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast = Color3.fromRGB(14, 14, 14),
    TextColor = Color3.fromRGB(255, 255, 255),
}

local HUB_URL = "https://raw.githubusercontent.com/AhmadV99/Speed-Hub-X/main/Speed%20Hub%20X.lua"

local GrowAGarden = {
    PlaceId = 126884695634066,
    UI = {
        instances = {},
        defaults = {
            theme = DEFAULT_THEME,
        },
    },
}

local function runHub(label)
    local ok, err = pcall(function()
        loadstring(game:HttpGet(HUB_URL, true))()
    end)
    if not ok then
        warn(("[GrowAGarden] Failed to load %s: %s"):format(label, tostring(err)))
    end
end

local function buildUI()
    local venyx = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua"))()
    local ui = venyx.new({title = "Revamp - Grow a Garden"})

    local mainPage = ui:addPage({title = "GAG Hubs"})
    local loaderSection = mainPage:addSection({title = "Loaders"})

    loaderSection:addButton({
        title = "Default GAG Menu",
        callback = function()
            runHub("Default GAG Menu")
        end,
    })

    loaderSection:addButton({
        title = "Speed Hub X",
        callback = function()
            runHub("Speed Hub X")
        end,
    })

    GrowAGarden.UI.instances.library = venyx
    GrowAGarden.UI.instances.ui = ui

    return venyx, ui
end

function GrowAGarden.init()
    if game.PlaceId ~= GrowAGarden.PlaceId then
        return
    end

    local venyx, ui = buildUI()

    if venyx and ui then
        return {
            library = venyx,
            ui = ui,
            defaultTheme = DEFAULT_THEME,
            defaultPageIndex = 1,
            module = GrowAGarden,
        }
    end
end

return GrowAGarden
