# tests/test-uninstall.ps1
# Tests the uninstall flow: removes the scheduled task and deployed files.
# Ensures a clean install exists first, then validates full cleanup.
# REQUIRES administrator privileges. Skipped automatically if not admin.
#
# Exit code: 0 = all pass, 1 = any fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root      = (Resolve-Path "$PSScriptRoot\..").Path
$installPs   = "$root\src\Install.ps1"
$uninstallPs = "$root\src\Uninstall.ps1"

$TaskName  = 'iCUE-Watchdog'
$TargetDir = "$env:LOCALAPPDATA\iCUE-Watchdog"

$pass = 0; $fail = 0
function Assert([string]$desc, [bool]$cond) {
    if ($cond) { Write-Host "  [PASS] $desc" -ForegroundColor Green; $script:pass++ }
    else        { Write-Host "  [FAIL] $desc" -ForegroundColor Red;   $script:fail++ }
}

Write-Host ""
Write-Host "=== TEST: Uninstall ===" -ForegroundColor Cyan

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $isAdmin) {
    Write-Host "  [SKIP] Requires administrator privileges - rerun test.ps1 as admin to include this test." -ForegroundColor Yellow
    exit 0
}

# --- Setup: ensure installed state ---
Write-Host ""
Write-Host "  [Setup] Ensuring installed state..." -ForegroundColor DarkGray
$taskExists = $null -ne (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
$dirExists  = Test-Path $TargetDir
if (-not $taskExists -or -not $dirExists) {
    Write-Host "  [Setup] Running Install.ps1 to create baseline..." -ForegroundColor DarkGray
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installPs -AcceptDefaults
}

# --- Pre-conditions ---
Write-Host ""
Write-Host "  [Pre-conditions]" -ForegroundColor Yellow
Assert "Pre: target dir exists before uninstall"  (Test-Path $TargetDir)
Assert "Pre: task exists before uninstall"         ($null -ne (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue))

# --- Run uninstall ---
Write-Host ""
Write-Host "  [Action] Running Uninstall.ps1..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallPs

# --- Post-conditions ---
Write-Host ""
Write-Host "  [Post-conditions]" -ForegroundColor Yellow
Assert "Post: target dir removed"   (-not (Test-Path $TargetDir))
Assert "Post: task removed"          ($null -eq (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue))

# ==========================================================================
Write-Host ""
$clr = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "TEST-UNINSTALL: $pass passed, $fail failed" -ForegroundColor $clr
exit ([int]($fail -gt 0))
