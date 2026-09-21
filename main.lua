-- Main Branch Loader
-- Pulls the improved PVP bot from lua branch

local botUrl = "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/main.lua"

print("[Loader] Loading bot from lua branch...")
loadstring(game:HttpGet(botUrl))()
