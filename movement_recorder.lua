--[[
    Movement Recorder
    Records position, rotation, velocity over a time period
    F1 = Start recording
    F2 = Stop & export to clipboard
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

local RecorderState = {
    recording = false,
    startTime = 0,
    duration = 30, -- seconds
    frames = {},
}

local function recordFrame()
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    if not root or not humanoid then return end

    local pos = root.Position
    local rot = root.Rotation
    local vel = root.AssemblyLinearVelocity

    table.insert(RecorderState.frames, {
        time = tick() - RecorderState.startTime,
        pos = {x = pos.X, y = pos.Y, z = pos.Z},
        rot = {x = rot.X, y = rot.Y, z = rot.Z},
        vel = {x = vel.X, y = vel.Y, z = vel.Z},
    })
end

local function startRecording()
    if RecorderState.recording then return end

    RecorderState.recording = true
    RecorderState.startTime = tick()
    RecorderState.frames = {}

    print("[Movement Recorder] Recording started...")

    -- Record every frame
    local connection
    connection = game:GetService("RunService").RenderStepped:Connect(function()
        if not RecorderState.recording then
            connection:Disconnect()
            return
        end

        if tick() - RecorderState.startTime > RecorderState.duration then
            stopRecording()
            return
        end

        recordFrame()
    end)

    -- Auto-stop after duration
    task.delay(RecorderState.duration, function()
        if RecorderState.recording then
            stopRecording()
        end
    end)
end

local function stopRecording()
    if not RecorderState.recording then return end

    RecorderState.recording = false
    print(string.format("[Movement Recorder] Stopped. Recorded %d frames", #RecorderState.frames))
    exportData()
end

local function exportData()
    if #RecorderState.frames == 0 then
        print("[Movement Recorder] No data to export")
        return
    end

    -- Format as JSON for easy parsing
    local json = "{\n"
    json = json .. "  \"frames\": " .. #RecorderState.frames .. ",\n"
    json = json .. "  \"duration\": " .. RecorderState.duration .. ",\n"
    json = json .. "  \"data\": [\n"

    for i, frame in ipairs(RecorderState.frames) do
        json = json .. string.format(
            "    {\"t\": %.3f, \"px\": %.2f, \"py\": %.2f, \"pz\": %.2f, \"rx\": %.2f, \"ry\": %.2f, \"rz\": %.2f, \"vx\": %.2f, \"vy\": %.2f, \"vz\": %.2f}",
            frame.time,
            frame.pos.x, frame.pos.y, frame.pos.z,
            frame.rot.x, frame.rot.y, frame.rot.z,
            frame.vel.x, frame.vel.y, frame.vel.z
        )

        if i < #RecorderState.frames then
            json = json .. ",\n"
        else
            json = json .. "\n"
        end
    end

    json = json .. "  ]\n}\n"

    -- Print to console (user can copy from there)
    print("\n[Movement Recorder] DATA EXPORT:\n" .. json)

    -- Also try to copy to clipboard via intent server
    local ok, err = pcall(function()
        game:HttpPost("http://127.0.0.1:3636/clipboard", json, Enum.HttpContentType.ApplicationJson)
    end)

    if ok then
        print("[Movement Recorder] ✓ Copied to clipboard via intent server")
    else
        print("[Movement Recorder] ℹ Copy from console above (intent server unavailable)")
    end

    -- Save to _G for easy access
    _G.LastRecording = {
        frames = RecorderState.frames,
        json = json,
        frameCount = #RecorderState.frames,
        duration = RecorderState.duration,
    }

    print("[Movement Recorder] Data saved to _G.LastRecording")
end

-- Keyboard shortcuts
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F1 then
        startRecording()
    elseif input.KeyCode == Enum.KeyCode.F2 then
        stopRecording()
    end
end)

print([[
[Movement Recorder] Ready!

Controls:
  F1 = Start recording (30 seconds)
  F2 = Stop & export to clipboard

The recording captures:
  - Position (x, y, z)
  - Rotation (x, y, z)
  - Velocity (x, y, z)

Data will be exported as JSON to:
  1. Console (copy manually)
  2. Clipboard (if intent server available)
  3. _G.LastRecording (access via script)

Keyboard shortcuts will run until you load a different script.
]])
