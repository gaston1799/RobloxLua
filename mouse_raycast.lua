--[[
    Mouse Raycast Viewer - Shows what mouse is pointing at
    Press P to toggle on/off
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local mouse = LocalPlayer:GetMouse()
local camera = workspace.CurrentCamera

local enabled = true
local raycastPart = nil

print("\n[Mouse Raycast] Loaded - Press P to toggle")
print("[Mouse Raycast] Shows object name and distance under mouse cursor\n")

-- Create visual indicator
local function createRayVisualizer()
    if raycastPart then raycastPart:Destroy() end

    raycastPart = Instance.new("Part")
    raycastPart.Name = "MouseRaycastPoint"
    raycastPart.Shape = Enum.PartType.Ball
    raycastPart.Size = Vector3.new(0.5, 0.5, 0.5)
    raycastPart.Color = Color3.fromRGB(255, 255, 0)
    raycastPart.Material = Enum.Material.Neon
    raycastPart.CanCollide = false
    raycastPart.TopSurface = Enum.SurfaceType.Smooth
    raycastPart.BottomSurface = Enum.SurfaceType.Smooth
    raycastPart.Parent = workspace
end

createRayVisualizer()

-- Toggle on/off
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.P then
        enabled = not enabled
        if enabled then
            print("[Mouse Raycast] Enabled")
            createRayVisualizer()
        else
            print("[Mouse Raycast] Disabled")
            if raycastPart then
                raycastPart:Destroy()
                raycastPart = nil
            end
        end
    end
end)

-- Raycast update loop
RunService.RenderStepped:Connect(function()
    if not enabled or not raycastPart then return end

    -- Create ray from camera through mouse position
    local mouseX = mouse.X
    local mouseY = mouse.Y
    local viewportSize = camera.ViewportSize

    -- Normalize mouse position to screen coordinates
    local unitRay = camera:ScreenPointToRay(mouseX, mouseY)

    -- Raycast parameters
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}

    -- Perform raycast
    local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

    if rayResult then
        local hitPart = rayResult.Instance
        local hitPosition = rayResult.Position
        local distance = (hitPosition - camera.CFrame.Position).Magnitude

        -- Move indicator to hit point
        raycastPart.Position = hitPosition

        -- Get full path
        local path = hitPart.Name
        local current = hitPart.Parent
        while current and current ~= workspace do
            path = current.Name .. " > " .. path
            current = current.Parent
        end

        -- Print under mouse (updates constantly, check console)
        if tick() % 0.5 < 0.016 then  -- Print every ~0.5s
            print(string.format("[Hit] %s | Distance: %.1f studs", path, distance))
        end
    else
        -- Nothing hit, move indicator away
        raycastPart.Position = camera.CFrame.Position + unitRay.Direction * 1000
    end
end)

print("[Instructions]")
print("  - Press P to toggle raycast on/off")
print("  - Yellow ball shows what mouse is pointing at")
print("  - Console shows: object path and distance")
print("  - Move mouse around to see different objects\n")
