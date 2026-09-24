# RobloxLua loader — what was actually broken, and whether it's fixed

**Verdict: fixed, verified, and live.** The place script the loader downloads now compiles, and the
loader itself has been patched and pushed to branch `lua`. Confirmed over HTTP: the bytes the
executor will fetch are the fixed ones.

Commits on branch `lua`, pushed to `origin/lua` (on top of `7a51e0e5c "Restore v2 loading in main loader"`):

| Commit | Contents |
| --- | --- |
| `cf0e5c408` | The `end` fix, the loader rewrite, `.luacheckrc`, `check-lua.ps1`, `README.md` |
| `eafbd727e` | Configurable download branch (`RAW_BRANCHES`), `report.md`, `tools/`, `from-lua-clone-20260921/` snapshots |
| `552b12248` | `luacheck` config fix (`_G` must be writable) |

---

## 1. What the actual problem was

It looked like one bug. It was two independent faults stacked on top of each other, which is why
"fixing it" kept not working.

### Fault A — one extra `end` (the real breakage)

The tail of `findClosestAlly()` had **seven** consecutive `end`s where only six were needed:

```lua
                            end     -- 28 spaces
                        end         -- 24
                    end             -- 20
                end                 -- 16
            end                     -- 12
        end                         -- 8
    end          <<< this one is extra
                                    (blank)
    return closestAlly
end
```

The run closed `findClosestAlly` itself one line early, so `return closestAlly` ended up *outside*
the function and the function's real `end` had nothing left to close. Both parsers agree:

| Parser | Message |
| --- | --- |
| `luau-compile --only-parse` (authoritative for Roblox) | `5712833750-v2.lua(756,1): SyntaxError: Expected <eof>, got 'end'` |
| `luac` / `lua` 5.5 | `5712833750-v2.lua:756: <eof> expected near 'end'` |

`<eof> expected near 'end'` is Lua for *"the chunk already ended, here's another `end`"*. A
chunk-prefix probe confirmed it mechanically: the longest prefix of the file that forms a **complete
valid chunk** was the `return closestAlly` line — everything up to it parsed as a finished chunk.

**Consequence, and the reason the console was misleading:** the loader did

```lua
return loadstring(script)()
```

When the remote file fails to *compile*, `loadstring` returns `nil` plus the compiler message — and
the trailing `()` then tries to call nil. So the console showed `attempt to call a nil value` while
the actual error (`Expected <eof>, got 'end'`) was thrown away, because the second return value was
never captured. That single line hid the root cause of every failed run.

### Fault B — the fix was on a branch nothing reads

In `https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/<file>`, the `lua` segment is a
**branch name**, not a directory. The loader fetches from **branch `lua`**; local work was happening
on **branch `main`, 2 commits ahead and unpushed**.

- `5712833750-v3.lua` did not exist on branch `lua` at all — verified by real HTTP: `404: Not Found`. The
  current `main` loader built that v3 URL, so it was dead on arrival.
- On `main`, `5712833750-v2.lua` and `5712833750-v3.lua` were **byte-identical**. The commit titled
  "Create v3 with fix - different filename to bypass cache" changed the file name and nothing else.
- `core.autocrlf=true`, so working-tree sizes are inflated by one byte per line versus the committed
  blob. That is why the download was 58,038 bytes while the local file showed 60,454 — they are the
  same revision, and neither matched the file being edited. Comparing those two numbers sends you
  down the wrong path.

### Contributing detail — `v2.lua` was literally the text `404: Not Found`

`v2.lua` in the repo is a **14-byte file whose entire contents are `404: Not Found`**. A fetch of a
missing file was saved as a `.lua` and committed, and `loadstring` was pointed at it.

---

## 2. What was changed

Branch `lua`, commit `cf0e5c408`:

| File | Change |
| --- | --- |
| `5712833750.lua` | Deleted the extra `end` (line 743). 1-line diff; file now compiles. |
| `main.lua` | Rewrote the loader: probes `<placeId>-v2.lua` first and falls back to `<placeId>.lua`; compiles with `loadstring` **before** executing so syntax errors report themselves; detects 404 bodies so they can't be fed to `loadstring`; passes the Venyx UI window to the place script as its argument; keeps supporting the legacy `_G.buildAnimalSimUI` hook; removed the `script` / `httpOk` / `httpErr` globals (they leaked into the executor's global env, and `script` shadows Roblox's built-in). |
| `.luacheckrc` | New. Roblox + executor globals, so luacheck stops reporting every Roblox global as undefined. |
| `check-lua.ps1` | New. Luau syntax gate (`luau-compile --only-parse`) with optional `-Lint`, `-All`, `-Path`. |
| `README.md` | New. Documents that branch `lua` is the live branch, the loader/place-script UI contract, and the pre-push check. |

The loader → place-script contract is now explicit:

```lua
-- main.lua
local chunk, compileErr = loadstring(source)
if not chunk then
    print("[Main Loader] ✗ " .. label .. " COMPILE ERROR: " .. tostring(compileErr))
    return false
end
local ok, result = pcall(chunk, ui)     -- the Venyx UI is handed over here
```

```lua
-- <placeId>-v2.lua
local ui = ...                          -- and creates its pages on it
local page = ui:addPage({title = "Main"})
```

---

## 3. Verification

**Syntax, before → after**

| File | Before | After |
| --- | --- | --- |
| `5712833750.lua` | `expected <eof>, got 'end'` at 746 | ✅ parses (Luau **and** Lua 5.5) |
| `5712833750-v2.lua` | `expected <eof>, got 'end'` at 756 | still broken — **not mine to touch**, see §4 |
| `main.lua` | parsed | ✅ parses |

```
.\check-lua.ps1        ->  ok main.lua / ok 5712833750.lua / FAIL 5712833750-v2.lua (+ the two stubs)
git diff --stat        ->  5712833750.lua | 1 -      <- exactly one deleted line
```

**Live URL check (PBC, after the push)**

```
pbc open https://raw.githubusercontent.com/gaston1799/RobloxLua/lua/5712833750.lua
-> utf8Bytes: 58932        <- exactly the new blob (git ls-tree -l lua: 58932)
-> tail: 737 end / 738 end / 739 end / 740 end / 741 end / 742 end /
         (blank) / 744 return closestAlly / 745 end      <- no stray end
```

No CDN staleness: the served byte count already matches the pushed blob.

**Tooling installed for this loop**

| Tool | Version | Notes |
| --- | --- | --- |
| `luau` / `luau-compile` / `luau-analyze` / `luau-ast` | 0.739 | `scoop install luau`; shim for `luau-compile` added manually (the scoop manifest only shims two of the four binaries) |
| `lua` / `luac` | 5.5.0 | `scoop install lua` |
| `luacheck` | 1.2.0 | `scoop install luacheck` |

---

## 4. What is **not** fixed

- **`5712833750-v2.lua` is still broken** (syntax error at line 756) and is being restored by a
  separate Claude task. I deliberately backed off it: I had applied the same one-line fix, then
  reverted it (`git checkout --`) so that restore starts from its original state. It is **not** in my
  commit. Until that lands, the loader prints a compile error for v2 and falls back to
  `5712833750.lua`, which works — so the game is not blocked.
- **`5712833750-v2-fresh.lua`** (untracked scratch copy) still has the old defect; I restored it to
  its pre-edit state for the same reason. Delete it or fix it, but it isn't fetched by anything.
- **`v2.lua`** (the 14-byte `404: Not Found`) and **`5712833750-v2-restored.lua`** (0 bytes) were left
  in place rather than deleted, because a concurrent agent may own those paths. If they don't:
  `git rm v2.lua 5712833750-v2-restored.lua`.
- **Two luacheck "errors" are false positives** — `5712833750_pvp_intent.lua:221` and
  `5712833750_v2_recovered.lua:4340` report `expected '=' near 'end'` because luacheck parses *Lua*,
  not *Luau*, while `luau-compile` accepts both files. Trust `check-lua.ps1`, not luacheck, for
  syntax on this project.
- The large `*_recovered.lua` files (126–174 KB) are still committed. Untouched.
- **In-game behaviour is unverified.** Syntax and loader logic are verified here; running inside a
  Roblox executor is the one thing I can't test from this machine.

---

## 5. What you should see when you run it

```
[Main Loader] Looking for the place script (v2 first)...
[Main Loader] ✗ 5712833750-v2.lua COMPILE ERROR: ...(756,1): Expected <eof>, got 'end'
[Main Loader] --> -v2 not usable, trying 5712833750.lua
[Main Loader] ✓ 5712833750.lua downloaded (58932 bytes)
[Main Loader] ✓ 5712833750.lua loaded, UI attached
[Main Loader] ✓ Ready!
```

Once the v2 restore is pushed, the first two lines become a `✓` for `5712833750-v2.lua` and the
fallback disappears. `5712833750.lua` builds its pages by itself from `_G.venyx` (which the loader
sets before loading it), so both paths end with pages on the Venyx window.

To test a change without pushing, compare what is actually served — not what is on disk:

```powershell
git show lua:5712833750.lua | Select-String "some string you just added"
```

---

## 6. Preventing a repeat

1. Work on branch `lua` for anything the loader downloads; `git push origin lua` before testing.
2. Run `.\check-lua.ps1` before pushing. It parses with **Luau**, which is what Roblox actually runs.
3. Never trust the file name for cache busting — change the content and push.
4. Remember raw.githubusercontent.com caches for ~5 minutes; if nothing changes, wait before
   re-debugging.
5. The loader now separates **compile errors** from **runtime errors** and detects 404 bodies. If
   something fails, read that message first — it is no longer swallowed.

---

## 7. Follow-up: which branch the loader reads, and where the noise actually is

Measured 2026-09-24, after the fix:

| Branch | Commits | Touching `a/` | Last 24h |
| --- | --- | --- | --- |
| `lua` (what the loader reads) | 20,379 | 20,265 | 4,274 |
| `origin/main` | 591 | 577 | 228 |

The Discord presence bot commits to **both**, but the churn is overwhelmingly on **`lua`** — the
same branch the loader downloads from, and the same one the scripts are edited on. `main` is
~19x quieter, but it cannot serve the loader on its own: it has no `venyx_source.lua`, and its
`5712833750.lua` is a 2,231-byte stub versus 58,932 B on `lua`.

So the source branch is no longer hardcoded. `main.lua` now opens with:

```lua
local RAW_BRANCHES = { "lua", "main" }
```

tried in order with first hit winning, and every download (`venyx_source.lua`,
`<placeId>-v2.lua`, `<placeId>.lua`, `lib/*`) goes through `rawUrl(branch, path)`. Moving the
loader to `main` is now a one-line change — but only after `venyx_source.lua` and the real
place scripts are pushed there too, otherwise it just 404s and falls through to `lua`.

The real fix for the commit noise is to point the bot at its own branch or repository, then
`git rm -r --cached a/` on this one, so script edits and presence data stop sharing a branch.
Until then use `git fetch origin lua` (not a bare `fetch`) and prefer
`git clone --single-branch --branch lua`, so clones don't drag the churn in.
