# tests/test-restore.ps1
# Tests all restore execution modes.
# Does NOT require admin. Does NOT permanently modify the system.
#
# Exit code: 0 = all pass, 1 = any fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root      = (Resolve-Path "$PSScriptRoot\..").Path
$restorePs = "$root\src\Restore.ps1"

$pass = 0; $fail = 0
function Assert([string]$desc, [bool]$cond) {
    if ($cond) { Write-Host "  [PASS] $desc" -ForegroundColor Green; $script:pass++ }
    else        { Write-Host "  [FAIL] $desc" -ForegroundColor Red;   $script:fail++ }
}

Write-Host ""
Write-Host "=== TEST: Restore ===" -ForegroundColor Cyan

# ==========================================================================
# UNIT: Log parsing logic (inline, zero side effects)
# ==========================================================================
Write-Host ""
Write-Host "  [Unit] Log parsing logic" -ForegroundColor Yellow

function Test-LogFailed([string[]]$lines) {
    $lastEnter = -1; $lastLeave = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Entering working state|StartEnumeration finished') { $lastEnter = $i }
        if ($lines[$i] -match 'Leaving working state|ConnectionLost|StopEnumeration finished|Disable all enumerators') { $lastLeave = $i }
    }
    return $lastLeave -gt $lastEnter
}

Assert "Empty log          -> isFailed=false" (-not (Test-LogFailed @()))
Assert "No keywords        -> isFailed=false" (-not (Test-LogFailed @('Some log line', 'Another line')))
Assert "Leave then Enter   -> isFailed=false" (-not (Test-LogFailed @('Leaving working state', 'Entering working state')))
Assert "Enter then Leave   -> isFailed=true"  (      Test-LogFailed  @('Entering working state', 'Leaving working state'))
Assert "ConnectionLost     -> isFailed=true"  (      Test-LogFailed  @('Entering working state', 'ConnectionLost'))
Assert "StopEnumeration    -> isFailed=true"  (      Test-LogFailed  @('StartEnumeration finished', 'StopEnumeration finished'))
Assert "Disable enumerators-> isFailed=true"  (      Test-LogFailed  @('Entering working state', 'Disable all enumerators'))
Assert "Multi-cycle: last good -> isFailed=false" (-not (Test-LogFailed @(
    'Entering working state', 'Leaving working state',
    'Entering working state', 'StartEnumeration finished')))
Assert "Multi-cycle: last fail -> isFailed=true" (Test-LogFailed @(
    'Leaving working state',
    'Entering working state', 'StartEnumeration finished',
    'Leaving working state'))

# ==========================================================================
# INTEGRATION: Run src/Restore.ps1 with a mocked LOCALAPPDATA.
# Exit 0 = no restart needed. Exit 1 = restart was triggered.
#
# Fast tests use -Force (no initial 10s sleep).
# Slow tests omit -Force and exercise the real 10s production sleep (~30s total).
# Popup tests verify the WScript dialog appears AND auto-closes via elapsed time:
#   the popup has a 10s timeout, so the script takes >=10s extra when it fires.
# ==========================================================================
Write-Host ""
Write-Host "  [Integration] Restore.ps1 execution modes" -ForegroundColor Yellow

$tmpData = "$env:TEMP\icue-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$logDir  = "$tmpData\Corsair\Logs\CUE5"
New-Item -ItemType Directory -Force $logDir | Out-Null

function Invoke-Restore([string[]]$logLines, [switch]$Force, [switch]$NoLog) {
    Get-ChildItem $logDir -ErrorAction SilentlyContinue | Remove-Item -Force
    if (-not $NoLog) { $logLines | Set-Content "$logDir\test.log" -Encoding UTF8 }
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $restorePs)
    if ($Force) { $psArgs += '-Force' }
    & powershell @psArgs | Out-Null
    return $LASTEXITCODE
}

$origAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $tmpData

try {
    # --- Fast tests: use -Force (no initial 10s sleep) ---

    # Mode 1: --force -> always restart (exit 1)
    $ec = Invoke-Restore -NoLog -Force
    Assert "Mode --force: exit 1 (restart triggered)"                   ($ec -eq 1)

    # Mode 2: ICUE_FORCE=1 env var (CMD wrapper path), good log -> restart (exit 1)
    $env:ICUE_FORCE = '1'
    $ec = Invoke-Restore -logLines @('Entering working state', 'StartEnumeration finished')
    Assert "Mode ICUE_FORCE=1 env var: exit 1 (force via env)"          ($ec -eq 1)
    $env:ICUE_FORCE = $null

    # --- Slow tests: no -Force, real 3s startup sleep per test (~9s total) ---
    Write-Host "    -> next 3 tests include the 3s startup sleep..." -ForegroundColor DarkGray

    # Mode 5: silent, no log files -> no restart (exit 0)
    $ec = Invoke-Restore -NoLog
    Assert "Mode silent, no log files: exit 0 (no restart)"              ($ec -eq 0)

    # Mode 6: silent, good log (lastEnter > lastLeave) -> no restart (exit 0)
    $ec = Invoke-Restore -logLines @('Leaving working state', 'Entering working state', 'StartEnumeration finished')
    Assert "Mode silent, good log: exit 0 (no restart)"                  ($ec -eq 0)

    # Mode 7: silent, failed log (lastLeave > lastEnter) -> restart (exit 1)
    $ec = Invoke-Restore -logLines @('Entering working state', 'StartEnumeration finished', 'Leaving working state')
    Assert "Mode silent, failed log: exit 1 (restart triggered)"         ($ec -eq 1)

} finally {
    $env:LOCALAPPDATA = $origAppData
    $env:ICUE_FORCE   = $null
    Remove-Item $tmpData -Recurse -Force -ErrorAction SilentlyContinue
}

# ==========================================================================
# STATIC: Restore.cmd argument parsing (inspect generated CMD content)
# ==========================================================================
Write-Host ""
Write-Host "  [Static] Restore.cmd arg parsing" -ForegroundColor Yellow

$restoreCmd = "$root\build\Separate-Files-Version\Restore.cmd"
if (Test-Path $restoreCmd) {
    $cmd = Get-Content $restoreCmd -Raw
    Assert "Restore.cmd: parses --force arg"            ($cmd -match '(?i)--force')
    Assert "Restore.cmd: sets ICUE_FORCE=1"             ($cmd -match 'ICUE_FORCE=1')
    Assert "Restore.cmd: embeds :icue_restore: section" ($cmd -match '(?m)^:icue_restore\:')
} else {
    Write-Host "  [SKIP] build\Separate-Files-Version\Restore.cmd not found - run build.ps1 first" -ForegroundColor Yellow
}

# ==========================================================================
Write-Host ""
$clr = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "TEST-RESTORE: $pass passed, $fail failed" -ForegroundColor $clr
exit ([int]($fail -gt 0))
