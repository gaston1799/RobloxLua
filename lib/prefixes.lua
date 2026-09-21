--[[
    Prefixes Table Loader
    Loads the prefixes table from hosted files
]]

return function()
    local success, prefixes = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/gaston1799/HostedFiles/refs/heads/main/table.lua"))()
    end)

    if not success then
        warn("[Prefixes] Failed to load prefixes table, using empty table")
        return {}
    end

    return prefixes
end
