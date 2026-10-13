--[[
    ui_probe.lua - dump the layout of a Roblox ScreenGui so a script can be written against it.

    Built for the Animal Simulator pets window, from this Explorer path:
        Players/<you>/PlayerGui/AnimalsGUI/windowFrame/bodyFrame/body2Frame/Animals/<pet slots>

    Run it in the executor WHILE THE GUI IS OPEN. A hidden ScreenGui still reports a tree, but
    AbsolutePosition/AbsoluteSize are only meaningful once it is actually on screen.

    What it prints (and copies to the clipboard, so it can be pasted back instead of screenshotted):
      1. TREE      - every node, indented: Name (Class), Size, Position, Absolute pixel box,
                     ZIndex, Visible, Text / ImageId, attributes and value objects.
      2. CLICK     - the centre pixel of every GuiButton/GuiObject under the container named in
         TARGETS     CONFIG.container, i.e. the coordinates an intent-server click needs.

    Tune CONFIG. Nothing else needs editing.
]]

local CONFIG = {
    target = "AnimalsGUI",   -- ScreenGui to probe. "*" = every ScreenGui in PlayerGui.
    container = "Animals",   -- node whose children become CLICK TARGETS. "" = skip that section.
    maxDepth = 8,            -- how deep to recurse
    maxNodes = 600,          -- hard cap so the console cannot be flooded
    includeInvisible = true, -- false = only Visible = true nodes
    copyToClipboard = true,  -- setclipboard() the whole dump when the executor exposes it
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local lines = {}
local nodeCount = 0
local function push(text)
    lines[#lines + 1] = text
    print(text)
end

-- "0.30,12 0.40,0" is hard to read at a glance, so show scale+offset for both axes explicitly.
local function fmtUdims(udim2)
    return string.format("%.2f,%d %.2f,%d",
        udim2.X.Scale, udim2.X.Offset, udim2.Y.Scale, udim2.Y.Offset)
end

local function absBox(obj)
    if not obj:IsA("GuiObject") then return nil end
    local ok, pos = pcall(function() return obj.AbsolutePosition end)
    local ok2, size = pcall(function() return obj.AbsoluteSize end)
    if ok and ok2 and pos and size then return pos, size end
    return nil
end

local function describe(obj)
    local parts = { obj.Name .. " (" .. obj.ClassName .. ")" }

    if obj:IsA("GuiObject") then
        local ok, size = pcall(function() return obj.Size end)
        if ok and size then
            parts[#parts + 1] = "size=" .. fmtUdims(size)
        end
        local ok2, pos = pcall(function() return obj.Position end)
        if ok2 and pos then
            parts[#parts + 1] = "pos=" .. fmtUdims(pos)
        end
        local absPos, absSize = absBox(obj)
        if absPos and absSize then
            parts[#parts + 1] = string.format("abs=%d,%d %dx%d",
                math.floor(absPos.X), math.floor(absPos.Y),
                math.floor(absSize.X), math.floor(absSize.Y))
        end
        local ok3, z = pcall(function() return obj.ZIndex end)
        local ok4, visible = pcall(function() return obj.Visible end)
        if ok3 and z then parts[#parts + 1] = "z=" .. tostring(z) end
        if ok4 then parts[#parts + 1] = "vis=" .. tostring(visible) end
    end

    -- Text-bearing properties: this GUI labels each pet slot with text or an image.
    for _, prop in ipairs({ "Text", "Image", "TextScaled" }) do
        local ok, value = pcall(function() return obj[prop] end)
        if ok and value ~= nil and value ~= "" then
            local shown = tostring(value)
            if #shown > 80 then shown = shown:sub(1, 77) .. "..." end
            parts[#parts + 1] = prop .. "=" .. shown
        end
    end

    -- Attributes and ValueBase children: how a pet slot usually carries its real data.
    local okAttrs, attrs = pcall(function() return obj:GetAttributes() end)
    if okAttrs and attrs then
        for name, value in pairs(attrs) do
            parts[#parts + 1] = "attr." .. tostring(name) .. "=" .. tostring(value)
        end
    end
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("ValueBase") then
            local ok, value = pcall(function() return child.Value end)
            if ok then
                parts[#parts + 1] = child.Name .. "=" .. tostring(value)
            end
        end
    end

    parts[#parts + 1] = "children=" .. tostring(#obj:GetChildren())
    return table.concat(parts, " | ")
end

local function walk(obj, depth)
    if nodeCount >= CONFIG.maxNodes then return end
    if depth > CONFIG.maxDepth then return end

    if not CONFIG.includeInvisible and obj:IsA("GuiObject") then
        local ok, visible = pcall(function() return obj.Visible end)
        if ok and not visible then return end
    end

    nodeCount = nodeCount + 1
    push(string.rep("  ", depth) .. describe(obj))

    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("GuiObject") or child:IsA("LayerCollector") or child:IsA("Folder") then
            walk(child, depth + 1)
        end
    end
end

-- ===== run =====

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
if not playerGui then
    print("[UI Probe] PlayerGui never appeared - is this running in the game client?")
    return
end

local targets = {}
if CONFIG.target == "*" then
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("LayerCollector") then table.insert(targets, gui) end
    end
else
    local gui = playerGui:FindFirstChild(CONFIG.target) or playerGui:WaitForChild(CONFIG.target, 10)
    if not gui then
        print("[UI Probe] '" .. CONFIG.target .. "' is not in PlayerGui. Open the window in game first.")
        print("[UI Probe] ScreenGuis present right now:")
        for _, gui in ipairs(playerGui:GetChildren()) do
            if gui:IsA("LayerCollector") then print("   - " .. gui.Name .. " (" .. gui.ClassName .. ")") end
        end
        print("[UI Probe] Set CONFIG.target to one of those (or \"*\") and run it again.")
        return
    end
    targets = { gui }
end

push("===== UI PROBE =====")
push("place=" .. tostring(game.PlaceId) .. " player=" .. LocalPlayer.Name .. " time=" .. os.date("%H:%M:%S"))

for _, gui in ipairs(targets) do
    push("")
    push("--- " .. describe(gui))
    for _, child in ipairs(gui:GetChildren()) do
        walk(child, 1)
    end
end

-- CLICK TARGETS: centre pixels, which is what an intent-server mouse click needs.
if CONFIG.container ~= "" then
    local container = nil
    local function findContainer(obj)
        if container then return end
        if obj.Name == CONFIG.container then container = obj return end
        for _, child in ipairs(obj:GetChildren()) do
            if not container then findContainer(child) end
        end
    end
    for _, gui in ipairs(targets) do findContainer(gui) end

    push("")
    if container then
        push("--- CLICK TARGETS under " .. container:GetFullName())
        for index, child in ipairs(container:GetChildren()) do
            local pos, size = absBox(child)
            if pos and size and size.X > 0 and size.Y > 0 then
                push(string.format("  [%d] %s (%s) centre=%d,%d  box=%d,%d %dx%d",
                    index, child.Name, child.ClassName,
                    math.floor(pos.X + size.X / 2), math.floor(pos.Y + size.Y / 2),
                    math.floor(pos.X), math.floor(pos.Y),
                    math.floor(size.X), math.floor(size.Y)))
            else
                push(string.format("  [%d] %s (%s) - no absolute box (hidden or not rendered)",
                    index, child.Name, child.ClassName))
            end
        end
    else
        push("--- CLICK TARGETS: no node named '" .. CONFIG.container .. "' was found under " .. CONFIG.target)
    end
end

push("")
push("===== END (" .. nodeCount .. " nodes) =====")
push("NOTE: abs/centre values are in Roblox viewport pixels, origin top-left of the viewport.")

if CONFIG.copyToClipboard and type(setclipboard) == "function" then
    local ok = pcall(function() setclipboard(table.concat(lines, "\n")) end)
    print(ok and "[UI Probe] full dump copied to the clipboard - paste it back instead of screenshotting"
        or "[UI Probe] setclipboard failed; copy the console output by hand")
end
