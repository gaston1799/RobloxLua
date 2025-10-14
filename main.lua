local placeID = game.PlaceId
local url = ("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/%s.lua"):format(placeID)

local success, response = pcall(function()
	return game:HttpGet(url)
end)
-- log placeID and whether loading was successful
print(("[Loader] Loading script for placeID: %s - Success: %s"):format(placeID, tostring(success)))
if success and response and response ~= "" then
	loadstring(response)()
else
	warn("[Loader] Failed to load script for placeID:", placeID)
end
