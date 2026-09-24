# RobloxLua

Loader + per-place scripts for a Roblox script executor.

## The one rule that matters: branch `lua` is the live branch

`main.lua` downloads its scripts from raw.githubusercontent.com, and in those URLs the
`lua` segment is a **branch name**, not a directory:

```
https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/<file>
                                          ^^^
                                          branch "lua"
```

So a change only reaches the game once it is committed **and pushed to branch `lua`**.
Editing files on `main` (or on any other branch) changes nothing in game. This has
already caused a "I fixed it and it still fails" loop: the fixed file was on `main`,
while the executor kept fetching the old copy from `lua`.

- Do work that the loader downloads on branch `lua`.
- `git push origin lua` after every change you want to test in game.
- raw.githubusercontent.com caches for ~5 minutes. If a change doesn't appear, wait,
  or point the loader at a new file name.
- Sanity-check what is actually served, not what you have locally:
  `git show lua:5712833750-v2.lua | Select-String "some string"`.

## Files

| File | Purpose |
| --- | --- |
| `main.lua` | Loader: loads the Venyx UI library, builds the base pages, then loads the place script and hands it the UI. |
| `venyx_source.lua` | Venyx UI library. This root copy is the one the loader fetches. |
| `<placeId>-v2.lua` | Preferred place script. Loaded with the Venyx UI passed as its argument. |
| `<placeId>.lua` | Fallback place script for that PlaceID. |
| `lib/` | Support modules (`prefixes`, second Venyx copy, etc.). |
| `check-lua.ps1` | Syntax gate (see below). |
| `.luacheckrc` | Globals list so luacheck doesn't report every Roblox global as undefined. |

## Contract between the loader and a place script

`main.lua` builds the Venyx window and passes it in:

```lua
-- main.lua
local chunk = loadstring(source)
chunk(ui)              -- <placeId>-v2.lua receives it as its argument

-- <placeId>-v2.lua
local ui = ...         -- and creates its own pages on it
local page = ui:addPage({title = "Main"})
```

Rules:

- The place script **creates pages on the window it is given**. It must not create a
  second window (`venyx.new`) of its own.
- Legacy scripts may instead register `_G.buildAnimalSimUI`; the loader detects that and
  calls it with the same ui. Don't do both or the pages get built twice.
- The loader probes `<placeId>-v2.lua` first and falls back to `<placeId>.lua`, then
  falls back to the built-in Debug Tools + Misc pages.

## Error reporting

The loader compiles before executing, so a broken remote script reports its real
compiler message:

```
[Main Loader] ✗ 5712833750-v2.lua COMPILE ERROR: ...(756,1): Expected <eof>, got 'end'
```

Previously the code did `loadstring(source)()` in one expression. When the remote file
had a syntax error, `loadstring` returned `nil` and the trailing `()` tried to call nil,
so the console showed `attempt to call a nil value` and hid the actual cause. Likewise,
a GitHub 404 returns the body `404: Not Found` instead of raising, which is how a file
named `v2.lua` containing exactly that text ended up committed. The loader now detects
both cases explicitly.

## Checking before you push

```powershell
.\check-lua.ps1              # Luau syntax gate over tracked *.lua
.\check-lua.ps1 -Lint        # + luacheck
.\check-lua.ps1 -All         # include untracked scratch files
```

`luau-compile --only-parse` is the authoritative parser for Roblox code, because Roblox
runs **Luau**, not Lua. Plain `lua`/`luac` (Lua 5.1-5.5) parse most of these files but
reject Luau-only syntax (`+=`, type annotations, `continue`, interpolated strings).
