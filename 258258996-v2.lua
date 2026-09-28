--[[
    Miner's Haven automation module (v2 rewrite).

    Key changes vs the legacy 258258996.lua:
      * ForbiddenV2 is the ONLY movement backend. The hand-rolled
        moveTo/waypoint/slope/stuck stack is deleted.
      * A single Scheduler owns movement. Box/clover/open-box collection are
        "jobs"; auto-rebirth is a high-priority interrupt serviced at safe
        checkpoints. No two things ever pathfind at once, which removes the
        race that made the old pause->rebirth->resume handoff buggy.
      * Every subsystem lives inside its own function scope, so the main chunk
        stays far under Luau's 200-local limit.

    PlaceId 258258996.
]]

--#region Services & environment ------------------------------------------------
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local ENV = (getgenv and getgenv()) or _G
--#endregion

--#region Config & state --------------------------------------------------------
local DEFAULT_THEME = {
    Background    = Color3.fromRGB(24, 24, 24),
    Glow          = Color3.fromRGB(0, 0, 0),
    Accent        = Color3.fromRGB(10, 10, 10),
    LightContrast = Color3.fromRGB(20, 20, 20),
    DarkContrast  = Color3.fromRGB(14, 14, 14),
    TextColor     = Color3.fromRGB(255, 255, 255),
}

-- ForbiddenV2 now lives in this repo at libs/forbidden (branch 'lua'), so the base is the
-- repo root and the tree is addressed as libs/forbidden/**. entry.lua normalises a base that
-- points at the tree dir itself, so either form works.
local FORBIDDEN_REPO       = ENV.__FORBIDDEN_REPO or "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua"
local FORBIDDEN_BASE_URL   = FORBIDDEN_REPO
local FORBIDDEN_ENTRY_PATH = "/libs/forbidden/entry.lua"

local AUTO_REBIRTH_DATA_URL = "https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/autoRebirthData.lua"
local PREFIX_TABLE_URL      = "https://raw.githubusercontent.com/gaston1799/HostedFiles/refs/heads/main/table.lua"
local REBIRTH_UI_TAIL       = "PlayerGui.Rebirth.Frame.Rebirth_Content.Content.Rebirth.Frame.Bottom.Reborn"

local BASE_ON_TOP_RADIUS = 24 -- studs; "close enough to base" for rebirth/layout work

local MinersHaven = {
    PlaceId = 258258996,
    Data = {
        Settings = {
            returnHomeOnIdle = true,
        },
        LayoutAutomation = {
            layout2Enabled   = false,
            layout3Enabled   = false,
            layout2Cost      = "10M",
            layout3Cost      = "10qd",
            layout2Withdraw  = false,
            layout3Withdraw  = false,
            rebirthWithLayout = false,
            rebirthLayout    = "Layout1",
            rebirthWithdraw  = false,
            teleportToTycoon = true, -- kept for config parity; ForbiddenV2 walks, never teleports
            layoutSelections = { first = "Layout1", second = "Layout2", third = "Layout3" },
        },
    },
    State = {
        collectBoxes       = false,
        collectClovers     = false,
        autoOpenBoxes      = false,
        autoRebirth        = false,
        rebirthFarm        = false,
        onBase             = false,
        currentTask        = "Idle",
        taskDetail         = "",
        lastRebirthProgress = 0,
    },
    Modules = { Farming = {}, Utilities = {} },
    UI = { instances = {}, defaults = { theme = DEFAULT_THEME } },
}

local Settings = MinersHaven.Data.Settings
local State    = MinersHaven.State
--#endregion

--#region Task status -----------------------------------------------------------
local function setTaskState(task, detail)
    State.currentTask = task or "Idle"
    State.taskDetail  = detail or ""
end
--#endregion

--#region Character helpers -----------------------------------------------------
local Char = {}

function Char.get()
    return LocalPlayer.Character
end

function Char.humanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

function Char.root()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

function Char.isReady()
    local hum = Char.humanoid()
    local root = Char.root()
    return hum ~= nil and hum.Health > 0 and root ~= nil and root.Parent ~= nil
end

function Char.waitReady(timeout)
    local deadline = os.clock() + (timeout or 5)
    while not Char.isReady() and os.clock() < deadline do
        task.wait(0.1)
    end
    return Char.isReady()
end
--#endregion

--#region Currency parsing ------------------------------------------------------
local Currency = {}
do
    local prefixScale = { [""] = 1 }
    local sortedPrefixes = {}

    local function loadPrefixTable()
        local ok, chunk = pcall(function()
            return loadstring(game:HttpGet(PREFIX_TABLE_URL))
        end)
        if not ok or type(chunk) ~= "function" then
            warn("[MinersHaven] prefix table fetch failed:", tostring(chunk))
            return false
        end
        local ok2, result = pcall(chunk)
        if not ok2 or type(result) ~= "table" then
            warn("[MinersHaven] prefix table decode failed:", tostring(result))
            return false
        end
        for _, entry in ipairs(result) do
            local prefix = entry.prefix or ""
            local number = entry.number or 1
            prefixScale[prefix:lower()] = number
            if prefix ~= "" then
                table.insert(sortedPrefixes, { prefix = prefix, number = number })
            end
        end
        table.sort(sortedPrefixes, function(a, b) return #a.prefix > #b.prefix end)
        return true
    end

    -- B6: a silent failure here makes every suffixed price parse as 0, which would make every
    -- affordability check pass. Never fail quietly; retry once.
    if not loadPrefixTable() then
        task.spawn(function()
            task.wait(10)
            if loadPrefixTable() then
                warn("[MinersHaven] prefix table loaded on retry")
            else
                warn("[MinersHaven] prefix table still unavailable - cash parsing is unreliable")
            end
        end)
    end

    function Currency.parse(value)
        if type(value) == "number" then return value end
        if not value then return 0 end
        local normalized = tostring(value):gsub("[%$,]", "")
        local base, suffix = normalized, ""
        for _, entry in ipairs(sortedPrefixes) do
            local prefix = entry.prefix
            if prefix ~= "" and #base >= #prefix then
                local candidate = base:sub(-#prefix)
                if candidate:lower() == prefix:lower() then
                    suffix = candidate
                    base = base:sub(1, -#prefix - 1)
                    break
                end
            end
        end
        base = (base and base:match("^%s*(.-)%s*$")) or ""
        if base == "" then return 0 end
        local amount = tonumber(base)
        if not amount then return 0 end
        local multiplier = (suffix ~= "" and (prefixScale[suffix:lower()] or 1)) or 1
        return amount * multiplier
    end
end

local function getInstanceFromTail(tail)
    local current = LocalPlayer
    if not current then return nil end
    for part in tail:gmatch("[^%.]+") do
        current = current:FindFirstChild(part)
        if not current then return nil end
    end
    return current
end
--#endregion

--#region Movement (ForbiddenV2) ------------------------------------------------
-- The single movement authority. Nothing else may drive the character.
local Movement = {}
do
    local AI            -- ForbiddenV2 API, lazily loaded
    local anchor        -- reusable pathfinding target part for raw positions
    local loadError
    local retryAt = 0   -- B3: a transient failure must not disable movement for the session
    local RETRY_DELAY = 10

    local function ensureAI()
        if AI then return AI end
        if loadError and os.clock() < retryAt then return nil end
        ENV.__FORBIDDEN_BASE_URL = FORBIDDEN_BASE_URL
        _G.__FORBIDDEN_BASE_URL  = FORBIDDEN_BASE_URL
        local ok, api = pcall(function()
            return loadstring(game:HttpGet(FORBIDDEN_BASE_URL .. FORBIDDEN_ENTRY_PATH))()
        end)
        if not ok or type(api) ~= "table" or type(api.SmartPathfind) ~= "function" then
            loadError = tostring(api)
            retryAt = os.clock() + RETRY_DELAY
            warn("[MinersHaven] Failed to load ForbiddenV2 (retrying in " .. RETRY_DELAY .. "s):", loadError)
            return nil
        end
        loadError = nil
        AI = api
        return AI
    end

    local function ensureAnchor()
        if anchor and anchor.Parent then return anchor end
        local part = Instance.new("Part")
        part.Name         = "MHPathAnchor"
        part.Anchored     = true
        part.CanCollide   = false
        part.CanTouch     = false
        part.CanQuery     = false
        part.Transparency = 1
        part.Size         = Vector3.new(1, 1, 1)
        part.Archivable   = false     -- B13: never saved with the place
        part.Parent       = workspace
        anchor = part
        return part
    end

    -- Apply a baseline config once per character (no tracking for static targets).
    -- B5: keyed on the character instance, because a respawn creates a new one and
    -- ForbiddenV2's config is per-NPC.
    local configuredChar
    function Movement.configure(trackingEnabled, force)
        local api = ensureAI()
        local char = Char.get()
        if not api or not char then return end
        if configuredChar == char and not force then return end
        local ok, config = pcall(api.GetConfig, char)
        if not ok or not config then return end
        configuredChar = char
        pcall(function()
            config:RestoreDefaults()
            config.Debugging.Enabled     = false
            config.Visualization.Enabled = false
            config.Tracking.Enabled      = trackingEnabled == true
            config:ApplyNow()
        end)
    end

    function Movement.isAvailable()
        return ensureAI() ~= nil
    end

    -- Walk to a raw world position. Yields until the goal is reached or aborted.
    -- Returns true if it believes it arrived.
    function Movement.goTo(position)
        local api = ensureAI()
        if not api or not Char.isReady() then return false end
        local part = ensureAnchor()
        part.Position = position
        local ok = pcall(api.SmartPathfind, Char.get(), part, true)
        if not ok then return false end
        local root = Char.root()
        if not root then return false end
        return (root.Position - position).Magnitude <= 8
    end

    -- Walk to an Instance target (BasePart/Model/Player). Yields.
    function Movement.goToInstance(target)
        local api = ensureAI()
        if not api or not Char.isReady() or not target then return false end
        return pcall(api.SmartPathfind, Char.get(), target, true)
    end

    -- Cancel any in-progress path immediately. Safe to call when idle.
    function Movement.cancel()
        local api = AI
        local char = Char.get()
        if api and char then
            pcall(api.Stop, char, false)
        end
    end
end
--#endregion

--#region Boxes ----------------------------------------------------------------
local Box = {}
do
    local includePatterns = { "Box", "Gift", "Crate" }
    local excludePatterns = { "overlay", "inside", "Lava", "Mine", "Handle", "Upgrade", "Conv", "Mesh", "Terrain" }
    local boxesFolder = workspace:FindFirstChild("Boxes")

    -- box key (Model or Part) -> os.clock() time collected
    local collected = {}

    function Box.resetTracking()
        collected = {}
    end

    function Box.container()
        if boxesFolder and boxesFolder.Parent then return boxesFolder end
        local ok, folder = pcall(function() return workspace:WaitForChild("Boxes", 2) end)
        if ok and folder then boxesFolder = folder; return folder end
        return nil
    end

    local function basePartOf(part)
        if not part then return nil end
        if part:IsA("Model") then return part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart") end
        if part:IsA("BasePart") then return part end
        return nil
    end
    Box.basePartOf = basePartOf

    local function keyOf(part)
        if part.Parent and part.Parent:IsA("Model") then return part.Parent end
        return part
    end

    local function isNameBox(part)
        if not part or not part:IsA("BasePart") then return false end
        for _, inc in ipairs(includePatterns) do
            if part.Name:match(inc) then
                for _, exc in ipairs(excludePatterns) do
                    if part.Name:match(exc) then return false end
                end
                return true
            end
        end
        return false
    end

    function Box.pruneCollected()
        local now = os.clock()
        for box, ts in pairs(collected) do
            if not box or not box.Parent or ts + 30 < now then
                collected[box] = nil
            end
        end
    end

    -- Return the nearest un-collected box (as {part, key, base}) to the given position.
    function Box.nearest(fromPos)
        local best, bestDist
        local container = Box.container()
        local function consider(child)
            local base = basePartOf(child)
            if not base then return end
            local key = keyOf(child)
            if collected[key] then return end
            local d = (base.Position - fromPos).Magnitude
            if not bestDist or d < bestDist then
                bestDist = d
                best = { part = child, key = key, base = base }
            end
        end
        if container then
            for _, child in ipairs(container:GetChildren()) do consider(child) end
        else
            for _, desc in ipairs(workspace:GetDescendants()) do
                if isNameBox(desc) then consider(desc) end
            end
        end
        return best
    end

    function Box.markCollected(key)
        collected[key] = os.clock()
    end
end
--#endregion

--#region Tycoon base ----------------------------------------------------------
local Base = {}
do
    local lastReturnHome = 0

    local function tycoon()
        local value = LocalPlayer:FindFirstChild("PlayerTycoon")
        if not value then
            local ok, v = pcall(function() return LocalPlayer:WaitForChild("PlayerTycoon", 3) end)
            if ok then value = v end
        end
        return value and value.Value or nil
    end

    function Base.part()
        local base = tycoon()
        if not base then return nil end
        local surface = base:FindFirstChild("Base")
        if not surface then
            local ok, v = pcall(function() return base:WaitForChild("Base", 3) end)
            if ok then surface = v end
        end
        surface = surface or base.PrimaryPart or base:FindFirstChildWhichIsA("BasePart")
        if surface and surface:IsA("Model") then
            surface = surface.PrimaryPart or surface:FindFirstChildWhichIsA("BasePart")
        end
        return surface
    end

    -- Walk onto the base. Yields. Returns true if within range afterward.
    function Base.goTo()
        local part = Base.part()
        if not part or not part:IsA("BasePart") then return false end
        Movement.goTo(part.Position)
        local root = Char.root()
        return root ~= nil and (root.Position - part.Position).Magnitude <= BASE_ON_TOP_RADIUS
    end

    function Base.isOn()
        local part = Base.part()
        local root = Char.root()
        if not part or not root then return false end
        return (root.Position - part.Position).Magnitude <= BASE_ON_TOP_RADIUS
    end

    function Base.returnIfIdle()
        if not Settings.returnHomeOnIdle then return end
        local now = os.clock()
        if now - lastReturnHome < 2 then return end
        if Base.goTo() then lastReturnHome = now end
    end
end
--#endregion

--#region Rebirth & layouts ----------------------------------------------------
local Rebirth = {}
do
    local LayoutsService = ReplicatedStorage:FindFirstChild("Layouts")

    local function getCash()
        local stats = LocalPlayer:FindFirstChild("leaderstats")
        local cashStat = stats and stats:FindFirstChild("Cash")
        if not cashStat then return 0 end
        return Currency.parse(cashStat.Value)
    end
    Rebirth.getCash = getCash

    function Rebirth.getPrice()
        local ui = getInstanceFromTail(REBIRTH_UI_TAIL)
        if not ui then return nil end
        if not (ui:IsA("TextLabel") or ui:IsA("TextButton")) then
            ui = ui:FindFirstChildWhichIsA("TextLabel") or ui:FindFirstChildWhichIsA("TextButton")
            if not ui then return nil end
        end
        local fullText = ui.Text or ""
        local valueStr = fullText:match(":%s*(.+)$") or fullText
        return Currency.parse(valueStr)
    end

    function Rebirth.progress()
        local price = Rebirth.getPrice()
        if not price or price <= 0 then return 0 end
        return math.clamp(getCash() / price, 0, 1)
    end

    local function destroyAll()
        pcall(function() ReplicatedStorage.DestroyAll:InvokeServer() end)
        task.wait(0.7)
    end

    -- Walk to base, then load a layout via the server. Yields.
    function Rebirth.loadLayout(layoutName)
        if not layoutName or layoutName == "" then return false end
        LayoutsService = LayoutsService or ReplicatedStorage:FindFirstChild("Layouts")
        if not LayoutsService then
            warn("[MinersHaven] Layout service unavailable.")
            return false
        end
        if not Base.isOn() then Base.goTo() end
        local ok = pcall(function() LayoutsService:InvokeServer("Load", layoutName) end)
        if not ok then warn("[MinersHaven] Failed to load layout:", layoutName) end
        return ok
    end

    -- Poll cash until we can afford `cost`, or auto-rebirth turns off.
    local function waitForCash(cost)
        local required = Currency.parse(cost)
        if required <= 0 then return true end
        while State.rebirthFarm and getCash() < required do
            task.wait(0.25)
        end
        return State.rebirthFarm
    end

    -- Load the configured layout sequence (1, then optional 2/3 gated on cash). Yields.
    function Rebirth.runLayoutSequence()
        if not State.rebirthFarm then return end
        local cfg = MinersHaven.Data.LayoutAutomation
        setTaskState("Layouts", "First layout")
        Rebirth.loadLayout(cfg.layoutSelections.first or "Layout1")

        if cfg.layout2Enabled and State.rebirthFarm then
            if not waitForCash(cfg.layout2Cost) then setTaskState("Idle", ""); return end
            if cfg.layout2Withdraw then destroyAll() end
            setTaskState("Layouts", "Second layout")
            Rebirth.loadLayout(cfg.layoutSelections.second or "Layout2")
        end
        if cfg.layout3Enabled and State.rebirthFarm then
            if not waitForCash(cfg.layout3Cost) then setTaskState("Idle", ""); return end
            if cfg.layout3Withdraw then destroyAll() end
            setTaskState("Layouts", "Third layout")
            Rebirth.loadLayout(cfg.layoutSelections.third or "Layout3")
        end
        setTaskState("Idle", "")
    end

    -- Invoke the actual rebirth. Yields briefly.
    function Rebirth.invoke()
        pcall(function() ReplicatedStorage.Rebirth:InvokeServer() end)
        task.wait(0.5)
    end

    -- Optional pre-rebirth layout (rebirthWithLayout).
    function Rebirth.prepareLayout()
        local cfg = MinersHaven.Data.LayoutAutomation
        if not cfg.rebirthWithLayout or not cfg.rebirthLayout or cfg.rebirthLayout == "" then
            return true
        end
        if cfg.rebirthWithdraw then destroyAll() end
        return Rebirth.loadLayout(cfg.rebirthLayout)
    end
end
--#endregion

--#region Farming jobs ---------------------------------------------------------
-- These do exactly one movement unit and return, so the Scheduler can re-check
-- the rebirth interrupt between every target (safe checkpoint).
local BoxFarm, CloverFarm = {}, {}

function BoxFarm.collectOne()
    if not State.collectBoxes or not Char.isReady() then return false end
    Box.pruneCollected()
    local root = Char.root()
    if not root then return false end

    local target = Box.nearest(root.Position)
    if not target then
        setTaskState("BoxFarm", "No boxes")
        return false
    end

    setTaskState("BoxFarm", "Collecting box")
    local base = target.base or Box.basePartOf(target.part)
    if base and base:IsA("BasePart") then
        Movement.goTo(base.Position)
    end
    Box.markCollected(target.key)
    return true
end

function CloverFarm.collectOne()
    if not State.collectClovers or not Char.isReady() then return false end
    local clovers = workspace:FindFirstChild("Clovers")
    if not clovers then return false end
    local root = Char.root()
    if not root then return false end

    local best, bestDist
    for _, child in ipairs(clovers:GetChildren()) do
        local part = Box.basePartOf(child)
        if part then
            local d = (part.Position - root.Position).Magnitude
            if not bestDist or d < bestDist then bestDist = d; best = part end
        end
    end
    if not best then return false end

    setTaskState("BoxFarm", "Collecting clover")
    Movement.goTo(best.Position)
    return true
end
--#endregion

--#region Scheduler (single movement owner) ------------------------------------
local Scheduler = {}
do
    local running = false
    local openBoxesRunning = false
    local generation = 0        -- B2: bumped on every start/stop so a stale loop exits
    local preferClovers = false -- B7: round-robin the farming order

    local REBIRTH_COOLDOWN = 5   -- B4: settle time after an attempt
    local lastRebirthAttempt = 0

    local function rebirthReady()
        -- B1: "Rebirth Farm" is a superset of "Auto Rebirth" (it adds the layout sequence
        -- after the rebirth), so either flag may service the interrupt. Previously the
        -- Rebirth Farm toggle alone was a silent no-op.
        if not (State.autoRebirth or State.rebirthFarm) then return false end
        if os.clock() - lastRebirthAttempt < REBIRTH_COOLDOWN then return false end
        local price = Rebirth.getPrice()
        if not price or price <= 0 then return false end
        return Rebirth.getCash() >= price
    end

    -- Called only at a safe checkpoint (movement idle, between targets).
    local function serviceRebirth()
        local wasBoxes   = State.collectBoxes
        local wasClovers = State.collectClovers

        lastRebirthAttempt = os.clock()
        Movement.cancel()          -- B9: never start a rebirth on top of a live path

        setTaskState("Rebirth", "Going to base")
        Base.goTo()

        setTaskState("Rebirth", "Invoking")
        Rebirth.invoke()

        -- B4: let the character respawn before anything else touches movement.
        if not Char.waitReady(8) then return end
        Box.resetTracking()

        if State.rebirthFarm then
            setTaskState("Rebirth", "Layouts")
            Rebirth.runLayoutSequence()
        end

        -- Resume marker only affects HUD text; farming flags were never cleared,
        -- so the loop naturally continues collecting on the next cycle.
        if wasBoxes or wasClovers then
            setTaskState("BoxFarm", "Resuming")
        else
            setTaskState("Rebirth", "Watching cash")
        end
    end

    local function loop(myGen)
        while running and myGen == generation do
            Movement.configure(false)   -- B5: cheap no-op unless the character changed
            if not Char.waitReady(2) then
                Box.resetTracking()
                task.wait(0.3)
                continue
            end

            -- Keep the rebirth progress HUD fresh whenever auto-rebirth is on.
            if State.autoRebirth then
                State.lastRebirthProgress = Rebirth.progress()
            end

            -- 1) Rebirth interrupt: top priority, serviced between targets.
            if rebirthReady() then
                serviceRebirth()
                continue
            end

            -- 2) Farming (one target per cycle). B7: the order alternates, otherwise a
            -- steady supply of boxes starves clover collection entirely.
            local didWork = false
            preferClovers = not preferClovers
            if preferClovers then
                if State.collectClovers then didWork = CloverFarm.collectOne() end
                if not didWork and State.collectBoxes then didWork = BoxFarm.collectOne() end
            else
                if State.collectBoxes then didWork = BoxFarm.collectOne() end
                if not didWork and State.collectClovers then didWork = CloverFarm.collectOne() end
            end

            if not didWork then
                if (State.collectBoxes or State.collectClovers) then
                    Base.returnIfIdle()
                end
                task.wait(0.3)
            end
        end
        Movement.cancel()
    end

    -- Auto-open-boxes never touches movement, so it runs independently.
    local function openBoxesLoop()
        local seen = {}
        local warned = false
        while State.autoOpenBoxes do
            local remote = ReplicatedStorage:FindFirstChild("MysteryBox")
            local crates = LocalPlayer:FindFirstChild("Crates")
            if not remote and not warned then
                warned = true
                warn("[MinersHaven] ReplicatedStorage.MysteryBox not found; auto-open does nothing")
            end
            if remote and crates then
                for _, crate in ipairs(crates:GetChildren()) do
                    -- B8: invoke each crate exactly once; the old loop re-invoked every crate
                    -- twice a second.
                    if not seen[crate] then
                        local ok = pcall(function() remote:InvokeServer(crate.Name) end)
                        if ok then seen[crate] = true end
                        task.wait(0.05)
                    end
                end
            end
            task.wait(0.5)
        end
        openBoxesRunning = false
    end

    -- Should the movement loop be running?
    local function wantActive()
        return State.collectBoxes or State.collectClovers or State.autoRebirth or State.rebirthFarm
    end

    function Scheduler.refresh()
        if wantActive() and not running then
            running = true
            generation = generation + 1
            Movement.configure(false)
            task.spawn(loop, generation)
        elseif not wantActive() and running then
            running = false
            generation = generation + 1   -- B2: strands the old loop at its next check
            Movement.cancel()
        end
        if State.autoOpenBoxes and not openBoxesRunning then
            openBoxesRunning = true
            task.spawn(openBoxesLoop)
        end
    end

    function Scheduler.stopAll()
        State.collectBoxes   = false
        State.collectClovers = false
        State.autoOpenBoxes  = false
        State.autoRebirth    = false
        State.rebirthFarm    = false
        running = false
        generation = generation + 1   -- B2: strands the old loop at its next check
        Movement.cancel()
        State.onBase = false          -- B10: don't leave stale HUD state behind
        State.lastRebirthProgress = 0
        setTaskState("Idle", "")
    end
end
--#endregion

--#region Public farming API ---------------------------------------------------
local Farming = MinersHaven.Modules.Farming

function Farming.collectBoxes(value)
    State.collectBoxes = value and true or false
    if value then Box.resetTracking(); setTaskState("BoxFarm", "Collecting boxes") end
    task.spawn(Scheduler.refresh)   -- B12: UI callbacks may run off the game thread
end

function Farming.collectClovers(value)
    State.collectClovers = value and true or false
    if value then setTaskState("BoxFarm", "Collecting clovers") end
    task.spawn(Scheduler.refresh)
end

function Farming.autoOpenBoxes(value)
    State.autoOpenBoxes = value and true or false
    task.spawn(Scheduler.refresh)
end

function Farming.autoRebirth(value)
    State.autoRebirth = value and true or false
    if value then setTaskState("Rebirth", "Watching cash") end
    task.spawn(Scheduler.refresh)
end

function Farming.rebirthFarm(value)
    State.rebirthFarm = value and true or false
    task.spawn(Scheduler.refresh)
end

function Farming.stopAll()
    task.spawn(Scheduler.stopAll)
end
--#endregion

-- T5: the two actions the UI buttons need. Base/Movement/Scheduler are file-locals,
-- so they have to be exposed deliberately.
function MinersHaven.returnHome()
    task.spawn(function()
        Movement.cancel()
        setTaskState("Idle", "Returning to tycoon")
        Base.goTo()
    end)
end

function MinersHaven.stopAll()
    Farming.stopAll()
end

--#region UI (Venyx window passed in by the loader) -----------------------------
local UI = MinersHaven.UI
do
    local controls = {}

    -- T3: layout names for the dropdowns. Tries the repo branches, then falls back to the
    -- three layouts the config already references.
    local function loadLayoutCatalog()
        for _, branch in ipairs({ "lua", "main" }) do
            local ok, result = pcall(function()
                return loadstring(game:HttpGet(
                    ("https://raw.githubusercontent.com/gaston1799/RobloxLua/%s/autoRebirthData.lua"):format(branch)))()
            end)
            if ok and type(result) == "table" then
                local seen = {}
                for key, value in pairs(result) do
                    if type(key) == "string" then seen[key] = true end
                    if type(value) == "string" then seen[value] = true end
                end
                local names = {}
                for name in pairs(seen) do table.insert(names, name) end
                if #names > 0 then
                    table.sort(names)
                    return names
                end
            end
        end
        warn("[MinersHaven] layout catalog unavailable; using Layout1/2/3")
        return { "Layout1", "Layout2", "Layout3" }
    end

    -- The loader's Venyx toggle object has no public :Set(); it keeps its state in `.toggled`
    -- and refreshes through `Update`. Set both, guarded, and never re-fire the callback.
    local function setToggle(control, value)
        if type(control) ~= "table" then return end
        control.toggled = value
        if type(control.Update) == "function" then
            pcall(control.Update, control)
        end
    end

    function UI.build(ui)
        if UI.window then return UI.window end   -- idempotent: entry point + legacy hook both call this
        UI.window = ui
        local cfg = MinersHaven.Data.LayoutAutomation
        local layouts = loadLayoutCatalog()

        local page = ui:addPage({ title = "Miner's Haven" })

        -- Boxes --------------------------------------------------------------
        local boxes = page:addSection({ title = "Boxes" })
        controls.collectBoxes = boxes:addToggle({ title = "Collect Boxes",   callback = function(v) Farming.collectBoxes(v) end })
        controls.openBoxes    = boxes:addToggle({ title = "Auto open Boxes", callback = function(v) Farming.autoOpenBoxes(v) end })
        controls.clovers      = boxes:addToggle({ title = "Collect Clovers", callback = function(v) Farming.collectClovers(v) end })
        boxes:addToggle({ title = "Return home when idle", callback = function(v) Settings.returnHomeOnIdle = v end })

        -- Auto Rebirth -------------------------------------------------------
        local rebirth = page:addSection({ title = "Auto Rebirth" })
        controls.rebirthFarm = rebirth:addToggle({ title = "Rebirth Farm", callback = function(v) Farming.rebirthFarm(v) end })
        controls.autoRebirth = rebirth:addToggle({ title = "Auto Rebirth", callback = function(v) Farming.autoRebirth(v) end })

        rebirth:addDropdown({ title = "First layout",  values = layouts, default = cfg.layoutSelections.first,  callback = function(v) cfg.layoutSelections.first  = v end })
        rebirth:addDropdown({ title = "Second layout", values = layouts, default = cfg.layoutSelections.second, callback = function(v) cfg.layoutSelections.second = v end })
        rebirth:addDropdown({ title = "Third layout",  values = layouts, default = cfg.layoutSelections.third,  callback = function(v) cfg.layoutSelections.third  = v end })

        rebirth:addToggle({ title = "Load Layout 2", callback = function(v) cfg.layout2Enabled = v end })
        rebirth:addTextbox({ title = "Layout 2 cost", default = cfg.layout2Cost, callback = function(v) cfg.layout2Cost = v end })
        rebirth:addToggle({ title = "Withdraw before Layout 2", callback = function(v) cfg.layout2Withdraw = v end })
        rebirth:addToggle({ title = "Load Layout 3", callback = function(v) cfg.layout3Enabled = v end })
        rebirth:addTextbox({ title = "Layout 3 cost", default = cfg.layout3Cost, callback = function(v) cfg.layout3Cost = v end })
        rebirth:addToggle({ title = "Withdraw before Layout 3", callback = function(v) cfg.layout3Withdraw = v end })
        rebirth:addToggle({ title = "Rebirth with layout", callback = function(v) cfg.rebirthWithLayout = v end })
        rebirth:addDropdown({ title = "Rebirth layout", values = layouts, default = cfg.rebirthLayout, callback = function(v) cfg.rebirthLayout = v end })
        rebirth:addToggle({ title = "Withdraw before rebirth layout", callback = function(v) cfg.rebirthWithdraw = v end })

        -- Utilities ----------------------------------------------------------
        local utils = page:addSection({ title = "Utilities" })
        utils:addButton({ title = "Return to Tycoon", callback = function() MinersHaven.returnHome() end })
        utils:addButton({
            title = "Stop all automation",
            callback = function()
                MinersHaven.stopAll()
                for _, control in pairs(controls) do
                    if control ~= nil then setToggle(control, false) end
                end
            end,
        })

        -- T4: status surface. This Venyx build has no addLabel (verified: its only text
        -- primitives are the titles of toggles/buttons/textboxes), so fall back to a button
        -- that prints the state. MinersHaven.State stays readable for scripted checks either way.
        local function statusText()
            local detail = State.taskDetail or ""
            return ("%s%s"):format(State.currentTask or "Idle",
                (detail ~= "" and (" - " .. detail) or ""))
        end
        if type(utils.addLabel) == "function" then
            controls.status = utils:addLabel({ title = "Status: idle" })
            task.spawn(function()
                local last
                while true do
                    local text = "Status: " .. statusText()
                    if text ~= last then
                        last = text
                        pcall(function() controls.status:Set(text) end)
                    end
                    task.wait(0.5)
                end
            end)
        else
            utils:addButton({
                title = "Show status (console)",
                callback = function() print("[MinersHaven] status: " .. statusText()) end,
            })
        end

        print("[MinersHaven] UI attached")
        return ui
    end
end
--#endregion

--#region Init -----------------------------------------------------------------
function MinersHaven.init()
    if game.PlaceId ~= MinersHaven.PlaceId then
        warn("[MinersHaven] init called on wrong place:", game.PlaceId)
        return
    end
    -- T1: the loader calls chunk(ui), so the Venyx window arrives as init's argument
    -- (or via _G.venyx when an older loader is in use).
    ui = ui or _G.venyx
    if type(ui) == "table" and type(ui.addPage) == "function" then
        local okBuild, buildErr = pcall(UI.build, ui)
        if not okBuild then warn("[MinersHaven] UI build failed:", buildErr) end
    else
        UI.headless = true
        warn("[MinersHaven] no Venyx UI passed - running headless (API only)")
    end

    -- Preload ForbiddenV2 so the first pathfind isn't a cold HttpGet stall.
    task.spawn(function()
        if not Movement.isAvailable() then
            warn("[MinersHaven] ForbiddenV2 movement unavailable; automation will not move.")
        end
    end)
    setTaskState("Idle", "")
    return MinersHaven
end
--#endregion

--#region Entry -----------------------------------------------------------------
-- main.lua compiles this file and calls chunk(ui): the first vararg is the Venyx window.
-- The same builder is registered as the loader's legacy hook, but idempotently: the loader
-- calls that hook after chunk(ui) whenever it finds it, so a naive registration would build
-- the page twice.
_G.buildAnimalSimUI = function(passed)
    if UI.window then return UI.window end
    return UI.build(passed)
end

local passedUI = ...
local okInit, initErr = pcall(MinersHaven.init, passedUI)
if not okInit then
    warn("[MinersHaven] init failed:", initErr)
end

return MinersHaven
--#endregion
