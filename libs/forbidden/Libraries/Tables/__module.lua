--[[
From prooheckcp_robloxstatemachine@1.1.7
    Deep copy of the object
]]
TablesLibrary = {}

TablesLibrary.DeepCopy = function <T>(object)
    local newObject = {} -- Clone metaData (@rman501, good that it does this.)

    for index: string, value: any in object do
        if typeof(value) == "table" then
            newObject[index] = TablesLibrary.DeepCopy(value)
            continue
        end

        newObject[index] = value
    end

	return setmetatable(newObject, getmetatable(object))
end

TablesLibrary.DeepCopyPaste = function(Overwriter, Target)
    for index, value in Overwriter do
        if typeof(value) == "table" then
            if typeof(Target[index]) ~= "table" then
				Target[index] = {}
			end
            TablesLibrary.DeepCopyPaste(value, Target[index])
        else
            Target[index] = value
        end
    end

    setmetatable(Target, getmetatable(Overwriter))
end

-- recoded to be "safer" from some random guys "insight"
-- no idea why, but i understand it was related to too many metatable levels
function TablesLibrary.LockKeyInTable(tbl, keyToLock)
    local mt = getmetatable(tbl) or {}
    local originalIndex = mt.__index

    mt.__index = function(t, key)
        if key == keyToLock then
            error(`Attempt to read locked key: {key}`)
        elseif type(originalIndex) == "function" then
            return originalIndex(t, key)
        elseif type(originalIndex) == "table" then
            return originalIndex[key]
        end
    end

    mt.__newindex = function(t, key, value)
        if key == keyToLock then
            error(`Attempt to modify locked key: {key}`)
        else
            rawset(t, key, value)
        end
    end

    setmetatable(tbl, mt)
end


TablesLibrary.RemoveMetatable = function <T>(Target)
    -- Remove the lock on a key in the table
    setmetatable(Target, nil)
end


return TablesLibrary