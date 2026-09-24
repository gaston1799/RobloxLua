# from-lua-clone-20260921

**Reference snapshots, not live files.** Nothing here is downloaded by the loader — it only
ever requests `<placeId>[-v2].lua`, `venyx_source.lua` and `lib/*` from the branches listed
in `RAW_BRANCHES` in `main.lua`.

These files were copied out of a separate, stale clone of this repo
(`C:\Users\Naquan\C?UsersNaquanRobloxLua-lua`, branch `lua` @ `22a07ee`, last touched
2026-09-21) that held older revisions of the Animal Sim scripts. Kept as recovery material
for the `5712833750-v2.lua` restore.

| File | Size | Why it is here |
| --- | --- | --- |
| `5712833750.lua` | 147,245 B | The fullest version of that script in any checkout — 2.5x the current one (58,932 B). Best source for pulling lost functionality back out. It parses clean as Luau. |
| `main.lua` | 1,088 B | The minimal loader from that snapshot, for comparison with the current one. Also parses clean. |

A third file from that snapshot is deliberately **not** committed. Its entire 14-byte
content was:

```
404: Not Found
```

That is a saved GitHub 404 response, committed as `5712833750-v2.lua` (and `v2.lua`) — the
concrete evidence for how v2 was lost. It is quoted here instead, because committing a
`.lua` file whose contents are a 404 body is what caused this mess, and it would fail the
`check-lua.ps1` gate. The original still exists on disk if needed.

Do not copy these over the repo root. See `../report.md` for the full write-up.
