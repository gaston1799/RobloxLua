-- chunk-probe.lua : find the latest prefix of a file that forms a COMPLETE Lua chunk.
-- If the largest such prefix is well before EOF, the file has a stray/extra 'end'
-- (Lua stops at it with "<eof> expected near 'end'"), i.e. structure closes early.
local path = ...
if not path then print("usage: lua chunk-probe.lua <file>") os.exit(2) end

local lines = {}
for line in io.lines(path) do lines[#lines + 1] = line end
local n = #lines
print("file  : " .. path)
print("lines : " .. n)

local full = table.concat(lines, "\n")
local ok, err = load(full, "@" .. path)
print("full  : " .. (ok and "PARSES OK" or tostring(err)))

local successes = {}
for i = 1, n do
  if load(table.concat(lines, "\n", 1, i)) then successes[#successes + 1] = i end
end

print("complete-chunk prefixes found: " .. #successes)
if #successes > 0 then
  local last = successes[#successes]
  local s = #successes - 5
  if s < 1 then s = 1 end
  local out = {}
  for k = s, #successes do out[#out + 1] = tostring(successes[k]) end
  print("last few complete prefixes: " .. table.concat(out, ", "))
  print("LAST complete prefix ends at line " .. last)
  local function show(i)
    if i >= 1 and i <= n then
      print(string.format("  %5d| %s", i, lines[i]))
    end
  end
  show(last - 2); show(last - 1); show(last); show(last + 1); show(last + 2)
end
