<#
    check-lua.ps1 - syntax gate for this repo's Roblox scripts.

    Roblox runs Luau, not Lua, so the authoritative parser is luau-compile:
        .\check-lua.ps1                     # Luau syntax gate over tracked *.lua
        .\check-lua.ps1 -Lint               # + luacheck (uses .luacheckrc)
        .\check-lua.ps1 -All                # include untracked scratch files
        .\check-lua.ps1 -Path 5712833750.lua, main.lua

    Exit code 0 = every file parsed, 1 = at least one file failed to compile.
    luacheck warnings never fail the gate - only real syntax errors do.

    Requires: scoop install luau   (and optionally: scoop install luacheck)
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$Lint,
    [switch]$All,
    [string]$LuauCompile
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Resolve-LuauCompile {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    $cmd = Get-Command luau-compile -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $guess = Join-Path $env:USERPROFILE 'scoop\apps\luau\current\luau-compile.exe'
    if (Test-Path -LiteralPath $guess) { return $guess }
    throw 'luau-compile not found. Install it with: scoop install luau'
}

$exe = Resolve-LuauCompile -Explicit $LuauCompile

if (-not $Path -or $Path.Count -eq 0) {
    if ($All) {
        $Path = @(Get-ChildItem -Recurse -Filter *.lua -File -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.FullName })
    }
    else {
        # tracked files only - keeps scratch/experimental copies out of the gate
        $Path = @(git ls-files '*.lua')
    }
}

if ($Path.Count -eq 0) {
    Write-Host 'no .lua files to check'
    exit 0
}

$failed = New-Object System.Collections.Generic.List[string]

foreach ($f in $Path) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $out = & $exe --only-parse $f 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $msg = ($out -split "`r?`n" | Where-Object { $_ -match 'SyntaxError' } | Select-Object -First 1)
        Write-Host ("FAIL  {0}" -f $f) -ForegroundColor Red
        if ($msg) { Write-Host ("      {0}" -f $msg.Trim()) }
        $failed.Add($f)
    }
    else {
        Write-Host ("ok    {0}" -f $f) -ForegroundColor DarkGray
    }
}

if ($Lint) {
    Write-Host ''
    Write-Host '--- luacheck ---'
    if (Get-Command luacheck -ErrorAction SilentlyContinue) {
        luacheck --no-color -q .
        Write-Host '(luacheck warnings are informational - they do not fail the gate)'
    }
    else {
        Write-Host 'luacheck not installed (scoop install luacheck) - skipping' -ForegroundColor Yellow
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ("{0} of {1} file(s) FAILED the Luau syntax gate:" -f $failed.Count, $Path.Count) -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Red }
    exit 1
}

Write-Host ("all {0} file(s) parsed cleanly (Luau)" -f $Path.Count) -ForegroundColor Green
exit 0
