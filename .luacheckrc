-- .luacheckrc - luacheck configuration for Roblox / Luau place scripts
--
--   luacheck .            (from the repo root)
--   .\check-lua.ps1 -Lint (same thing, with a Luau syntax gate in front)
--
-- luau-compile --only-parse is the *authoritative* parser for Roblox code; luacheck
-- adds the static checks on top (unused vars, accidental globals, shadowing).

std = "lua51"            -- Roblox Luau is a 5.1 derivative
max_line_length = 200    -- these scripts routinely exceed the 120 default
unused_args = false      -- UI callbacks often declare params they don't use

-- Globals provided by the Roblox script environment, plus the executor environment
-- the loader runs inside. Anything not listed here is reported as an undefined global
-- (that's what turns "W113 accessing undefined variable 'game'" noise into signal).
read_globals = {
    -- Roblox data model / services
    "game", "workspace", "script", "plugin", "shared", "_ENV",
    "Enum", "Instance", "settings", "UserSettings", "version", "typeof", "warn",
    -- Roblox datatypes
    "UDim", "UDim2", "Vector2", "Vector3", "Vector2int16", "Vector3int16", "CFrame",
    "Color3", "ColorSequence", "ColorSequenceKeypoint", "BrickColor", "Ray",
    "Region3", "Region3int16", "NumberRange", "NumberSequence",
    "NumberSequenceKeypoint", "Rect", "TweenInfo", "PhysicalProperties", "Axes",
    "Faces", "Random", "DateTime", "Font", "PathWaypoint", "OverlapParams",
    "RaycastParams", "CatalogSearchParams", "DockWidgetPluginGuiInfo",
    -- scheduling / misc stdlib
    "task", "wait", "delay", "spawn", "tick", "time", "elapsedTime", "printidentity",
    "utf8", "debug", "coroutine", "bit32", "buffer", "vector", "os", "table", "string",
    -- executor environment (delete what your executor does not provide)
    "loadstring", "getgenv", "getrenv", "getgc", "getreg", "getsenv",
    "getrawmetatable", "setreadonly", "isreadonly", "checkcaller", "newcclosure",
    "hookfunction", "hookmetamethod", "getnamecallmethod", "setnamecallmethod",
    "getconnections", "firesignal", "firetouchinterest", "fireclickdetector",
    "getloadedmodules", "getscripts", "getnilinstances", "getinstances",
    "cloneref", "compareinstances", "gethui", "protectgui", "sethiddenproperty",
    "gethiddenproperty", "setsimulationradius", "getcustomasset", "getcallbackvalue",
    "queue_on_teleport", "setfpscap", "getfpscap", "isrbxactive", "setclipboard",
    "identifyexecutor", "getexecutorname", "request", "http_request",
    "mousemoverel", "mousemoveabs", "mouse1click", "mouse2click", "keypress",
    "keyrelease", "iskeydown", "getthreadidentity", "setthreadidentity",
    "readfile", "writefile", "appendfile", "listfiles", "isfile", "makefolder",
    "delfile", "delfolder", "loadfile", "dofile",
}

-- The place scripts and loader legitimately set these.
-- _G must be listed here (and NOT in read_globals, which would make its fields read-only):
-- the loader stores the Venyx window in _G.venyx, and place scripts register
-- _G.buildAnimalSimUI / _G.AdvancedPVPBot / _G.DamageMultiplier.
write_globals = {
    "_G", "_G.venyx", "_G.buildAnimalSimUI", "_G.AdvancedPVPBot", "_G.DamageMultiplier",
}
