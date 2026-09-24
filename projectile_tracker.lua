--[[
    Projectile Tracker - Measures Fireball & Lightning Ball Behavior
    Records: distance, duration, speed, trajectory for aiming calculations
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("\n" .. string.rep("=", 70))
print("PROJECTILE TRACKER - Record Fireball/Lightning Ball Trajectories")
print(string.rep("=", 70) .. "\n")

local projectiles = {}
local maxDistance = 0
local totalDuration = 0
local projectileCount = 0

-- Create detector for new projectiles
local function setupProjectileDetector()
    -- Monitor workspace for new fireballs/lightning balls
    local lastCheck = {}

    game:GetService("RunService").Heartbeat:Connect(function()
        -- Check for NewFireball
        for _, fireball in ipairs(workspace:FindFirstChild("Workspace") and workspace:GetChildren() or {}) do
            if (fireball.Name == "NewFireball" or fireball.Name == "NewLightningball") and fireball:IsA("Part") then
                if not lastCheck[fireball] then
                    lastCheck[fireball] = {
                        startTime = tick(),
                        startPos = fireball.Position,
                        lastPos = fireball.Position,
                        projectileName = fireball.Name,
                        positions = {fireball.Position},
                        times = {0}
                    }
                    print("\n[Detected] " .. fireball.Name .. " spawned at " ..
                          string.format("(%.1f, %.1f, %.1f)", fireball.Position.X, fireball.Position.Y, fireball.Position.Z))
                else
                    -- Track movement
                    local data = lastCheck[fireball]
                    local elapsed = tick() - data.startTime
                    local currentPos = fireball.Position
                    local dist = (currentPos - data.startPos).Magnitude

                    table.insert(data.positions, currentPos)
                    table.insert(data.times, elapsed)

                    maxDistance = math.max(maxDistance, dist)
                end
            end
        end

        -- Check for dead projectiles (disappeared)
        for fireball, data in pairs(lastCheck) do
            if not fireball.Parent then
                local elapsed = tick() - data.startTime
                local totalDist = (data.lastPos - data.startPos).Magnitude
                local speed = totalDist / math.max(elapsed, 0.01)

                projectileCount = projectileCount + 1
                totalDuration = totalDuration + elapsed

                print("[Projectile End] " .. data.projectileName)
                print("  Duration: " .. string.format("%.2f", elapsed) .. "s")
                print("  Distance: " .. string.format("%.1f", totalDist) .. " studs")
                print("  Speed: " .. string.format("%.1f", speed) .. " studs/s")
                print("  Start: " .. string.format("(%.1f, %.1f, %.1f)", data.startPos.X, data.startPos.Y, data.startPos.Z))
                print("  End: " .. string.format("(%.1f, %.1f, %.1f)", data.lastPos.X, data.lastPos.Y, data.lastPos.Z))

                table.insert(projectiles, {
                    name = data.projectileName,
                    duration = elapsed,
                    distance = totalDist,
                    speed = speed,
                    startPos = data.startPos,
                    endPos = data.lastPos,
                    positions = data.positions,
                    times = data.times
                })

                lastCheck[fireball] = nil
            else
                lastCheck[fireball].lastPos = fireball.Position
            end
        end
    end)
end

setupProjectileDetector()

print("[Ready] Fire fireballs and lightning balls to record data")
print("[Tracking] All projectiles will be logged with distance/duration")
print("[Stats] Summary will update as projectiles disappear\n")

-- Print summary every 5 seconds
task.spawn(function()
    while true do
        task.wait(5)
        if projectileCount > 0 then
            print("\n" .. string.rep("=", 70))
            print("PROJECTILE STATISTICS (" .. projectileCount .. " projectiles tracked)")
            print(string.rep("=", 70))
            print("Average Duration: " .. string.format("%.2f", totalDuration / projectileCount) .. "s")
            print("Max Distance: " .. string.format("%.1f", maxDistance) .. " studs")

            -- Analyze by type
            local fireballData = {}
            local lightningData = {}
            for _, proj in ipairs(projectiles) do
                if proj.name == "NewFireball" then
                    table.insert(fireballData, proj)
                else
                    table.insert(lightningData, proj)
                end
            end

            if #fireballData > 0 then
                local avgDist = 0
                local avgSpeed = 0
                for _, proj in ipairs(fireballData) do
                    avgDist = avgDist + proj.distance
                    avgSpeed = avgSpeed + proj.speed
                end
                avgDist = avgDist / #fireballData
                avgSpeed = avgSpeed / #fireballData
                print("\nFireballs (" .. #fireballData .. "):")
                print("  Avg Distance: " .. string.format("%.1f", avgDist) .. " studs")
                print("  Avg Speed: " .. string.format("%.1f", avgSpeed) .. " studs/s")
            end

            if #lightningData > 0 then
                local avgDist = 0
                local avgSpeed = 0
                for _, proj in ipairs(lightningData) do
                    avgDist = avgDist + proj.distance
                    avgSpeed = avgSpeed + proj.speed
                end
                avgDist = avgDist / #lightningData
                avgSpeed = avgSpeed / #lightningData
                print("\nLightning Balls (" .. #lightningData .. "):")
                print("  Avg Distance: " .. string.format("%.1f", avgDist) .. " studs")
                print("  Avg Speed: " .. string.format("%.1f", avgSpeed) .. " studs/s")
            end

            print(string.rep("=", 70) .. "\n")
        end
    end
end)

print("[Tip] Keep this running while testing projectiles")
print("[Tip] Data will be used for fireball aiming calculations\n")
