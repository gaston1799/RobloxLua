--[[
    Venyx UI Library Loader
    Loads the Venyx UI framework from GitHub
]]

return function()
    local success, venyx = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/libRebound/Venyx.lua"))()
    end)

    if not success then
        error("[Venyx] Failed to load Venyx UI: " .. tostring(venyx))
    end

    return venyx
end
