# tools

Helpers used to diagnose the 2026-09-24 loader breakage. None of them are part of the
loader — they are run from a terminal.

| Tool | Use it when |
| --- | --- |
| `chunk-probe.lua` | A script fails to parse and you need to know *where* the structure closes early. Reports the longest prefix that forms a complete chunk; if that is well before EOF, there is a stray/extra block terminator. |
| `fix-stray-end.js` | Repairing the specific `findClosestAlly` defect (a run of 7 `end`s where 6 are needed). Dry-run by default, `--apply` to write, and it aborts unless the pattern matches exactly — it will not guess. |
| `pbc-raw-probe.js` | Checking what a raw.githubusercontent.com URL is *actually* serving (byte length, line count, line numbers, 404 detection) via `pbc tab eval active --file` instead of dumping a 60 KB page into a transcript. |

## Usage

```powershell
# where does this file's structure end?
lua .\tools\chunk-probe.lua .\5712833750-v2.lua

# repair the known defect, dry run first
node .\tools\fix-stray-end.js .\5712833750-v2.lua
node .\tools\fix-stray-end.js .\5712833750-v2.lua --apply

# what is the live URL serving?
pbc open "https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/5712833750.lua"
pbc tab eval active --file .\tools\pbc-raw-probe.js
pbc sac
```

For a plain syntax verdict, prefer `.\check-lua.ps1` (Luau) — these tools are for when you
need to know *why*, or what the network is really returning.
