# 🧠 Agents.md — RobloxLua Split Project

### 🧹 Overview

This document defines responsibilities and workflow for breaking down the unified `CodeToBeBrokenDown.lua` script into smaller, game-specific Lua files. This ensures each file stays under Roblox's 200 local variable limit while maintaining modularity and readability.

---

## ⚙️ Loader Logic (`main.lua`)

```lua
local placeID = game.PlaceId
local url = ("https://raw.githubusercontent.com/gaston1799/RobloxLua/refs/heads/main/%s.lua"):format(placeID)

local success, response = pcall(function()
	return game:HttpGet(url)
end)

print(("[Loader] Loading script for placeID: %s - Success: %s"):format(placeID, tostring(success)))

if success and response and response ~= "" then
	loadstring(response)()
else
	warn("[Loader] Failed to load script for placeID:", placeID)
end
```

✅ Dynamically loads the correct Lua script based on the current game.
✅ Uses `pcall` for safe HTTP calls.
✅ Logs the success or failure of loading.

---

## 🧩 Breakdown Targets

| Game                | Place ID     | Output File      | Description                                                          |
| ------------------- | ------------ | ---------------- | -------------------------------------------------------------------- |
| 🐾 Animal Simulator | `5712833750` | `5712833750.lua` | Handles character logic, menu UI, and gameplay automation.           |
| ⛏️ Miner’s Haven    | `258258996`  | `258258996.lua`  | Handles placement utilities, mining automation, and inventory logic. |
| ⚡ Legend of Speed   | `3101667897` | `3101667897.lua` | Handles race timing, XP automation, and UI overlays.                 |

Each file will include only relevant logic for that game. Shared functions will be duplicated as needed.

---

## 🦜 Task Breakdown by Agent

### 🦝 Agent 1 — Splitter

* Parse `CodeToBeBrokenDown.lua`.
* Identify and extract game-specific logic blocks.
* Create three scripts: `5712833750.lua`, `258258996.lua`, `3101667897.lua`.
* Retain shared utilities as necessary.

### ⚒️ Agent 2 — Cleaner

* Reformat and reindent each Lua file.
* Remove redundant locals or globals.
* Ensure no script exceeds ~180 locals.
* Test each script standalone with `loadstring()`.

### 📦 Agent 3 — Loader Integrator

* Ensure the `main.lua` correctly references all split scripts.
* Verify URLs and filenames match exactly.
* Confirm all `HttpGet` calls succeed.

### 🤮 Agent 4 — QA Tester

* Load each target game in Roblox Studio.
* Verify expected features appear.
* Confirm no cross-contamination between game-specific UIs.
* Monitor performance and memory footprint.

---

## 🛠️ Output Structure

```
/RobloxLua/
│
├── main.lua
├── CodeToBeBrokenDown.lua      # Original unified script
├── 5712833750.lua              # Animal Simulator
├── 258258996.lua               # Miner’s Haven
├── 3101667897.lua              # Legend of Speed
└── agents.md                   # This file
```

---

## ✅ Success Criteria

* Each script executes independently under the 200-local limit.
* Shared utilities are safely duplicated.
* `main.lua` loader functions correctly for all `PlaceId`s.
* Scripts validated in live and studio tests.

---

## 📊 Next Step: Template Generation

The next step is generating three base template files (`5712833750.lua`, `258258996.lua`, and `3101667897.lua`) with section headers and placeholders for each menu tab or module from `CodeToBeBrokenDown.lua`.
