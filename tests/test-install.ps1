# tests/test-install.ps1
# Tests the install flow: deploys Restore.ps1 and registers the scheduled task.
# REQUIRES administrator privileges. Skipped automatically if not admin.
#
# Exit code: 0 = all pass, 1 = any fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root      = (Resolve-Path "$PSScriptRoot\..").Path
$installPs = "$root\src\Install.ps1"

$TaskName     = 'iCUE-Watchdog'
$TargetDir    = "$env:LOCALAPPDATA\iCUE-Watchdog"
$TargetScript = "$TargetDir\Restore.ps1"

$pass = 0; $fail = 0
function Assert([string]$desc, [bool]$cond) {
    if ($cond) { Write-Host "  [PASS] $desc" -ForegroundColor Green; $script:pass++ }
    else        { Write-Host "  [FAIL] $desc" -ForegroundColor Red;   $script:fail++ }
}

Write-Host ""
Write-Host "=== TEST: Install ===" -ForegroundColor Cyan

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $isAdmin) {
    Write-Host "  [SKIP] Requires administrator privileges - rerun test.ps1 as admin to include this test." -ForegroundColor Yellow
    exit 0
}

# --- Setup: ensure clean slate ---
Write-Host ""
Write-Host "  [Setup] Removing any previous install..." -ForegroundColor DarkGray
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force }

# --- Pre-conditions ---
Write-Host ""
Write-Host "  [Pre-conditions]" -ForegroundColor Yellow
Assert "Pre: target dir does not exist"   (-not (Test-Path $TargetDir))
Assert "Pre: task does not exist"         ($null -eq (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue))

# --- Run install ---
Write-Host ""
Write-Host "  [Action] Running Install.ps1..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File $installPs -AcceptDefaults

# --- Post-conditions ---
Write-Host ""
Write-Host "  [Post-conditions]" -ForegroundColor Yellow
Assert "Post: target dir created"         (Test-Path $TargetDir)
Assert "Post: Restore.ps1 deployed"       (Test-Path $TargetScript)

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Assert "Post: scheduled task registered"  ($null -ne $task)

if ($task) {
    $sessionTrigger = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskSessionStateChangeTrigger' }
    $eventTrigger   = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskEventTrigger' }
    Assert "Task: SessionUnlock trigger present"          ($null -ne $sessionTrigger)
    Assert "Task: EventTrigger (power resume) present"   ($null -ne $eventTrigger)
    Assert "Task: action runs powershell.exe"             ($task.Actions[0].Execute -match 'powershell')
    Assert "Task: action references Restore.ps1"          ($task.Actions[0].Arguments -match 'Restore\.ps1')
    Assert "Task: action points to target dir"            ($task.Actions[0].Arguments -match [regex]::Escape($TargetDir))
    Assert "Task: hidden window style"                    ($task.Actions[0].Arguments -match '-WindowStyle\s+Hidden')
}

# Validate deployed script is valid PowerShell
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($TargetScript, [ref]$null, [ref]$errs)
Assert "Deployed Restore.ps1: no parse errors"                ($errs.Count -eq 0)

$deployed = Get-Content $TargetScript -Raw
Assert "Deployed Restore.ps1: contains log parsing logic"     ($deployed -match 'Entering working state')
Assert "Deployed Restore.ps1: contains iCUE restart logic"    ($deployed -match 'iCUE Launcher')

# ==========================================================================
Write-Host ""
$clr = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "TEST-INSTALL: $pass passed, $fail failed" -ForegroundColor $clr
exit ([int]($fail -gt 0))
