@echo off
:: ============================================================================
::
::   iCUE Watchdog - Uninstall
::   https://github.com/nyok1912/iCUE-watchdog
::
::   Removes the iCUE Watchdog Scheduled Task and all installed files.
::   Requires administrator privileges (will auto-elevate).
::
:: ============================================================================

setlocal EnableExtensions
setlocal DisableDelayedExpansion

set "SysPath=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" set "SysPath=%SystemRoot%\Sysnative"

set "ps=%SysPath%\WindowsPowerShell\v1.0\powershell.exe"
set "psc=%ps% -NoProfile -ExecutionPolicy Bypass -Command"
set "_batf=%~f0"
set "_batp=%_batf:'=''%"

:: Auto-elevate if not running as administrator
powershell -NoProfile -Command "if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')){Start-Process '%~f0' -Verb RunAs;exit 1}"
if %errorlevel% neq 0 exit /b
setlocal EnableDelayedExpansion
%psc% "$f=[IO.File]::ReadAllText('!_batp!') -split ':icue_uninstall\:.*'; . ([scriptblock]::Create($f[1]))"
endlocal
pause
exit /b

:: ============================================================================
::  PowerShell section - CMD never reaches here
:: ============================================================================
exit /b


:icue_uninstall:
# iCUE Watchdog - Uninstall
# Auto-elevates if not running as administrator.
#
# Usages:
#   - Standalone: .\Uninstall.ps1
#   - From AIO CMD bundle: automatically called (elevation handled by CMD)
#
# When called from the AIO CMD bundle, $env:_batf is set by the CMD preamble.
# The admin check is skipped in that case (CMD already ensured elevation).

$TargetDir = "$env:LOCALAPPDATA\iCUE-Watchdog"
$TaskName  = 'iCUE-Watchdog'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# When called from the CMD bundle, elevation is already guaranteed by the CMD preamble.
# When called standalone, auto-elevate via UAC if needed.
if (-not $env:_batf) {
    if (-not $isAdmin) {
        Start-Process powershell -Verb RunAs -Wait `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit $LASTEXITCODE
    }
}

$iCUEProc   = Get-Process -Name 'iCUE' -ErrorAction SilentlyContinue | Select-Object -First 1
$procUser   = if ($iCUEProc) {
    $w = Get-WmiObject Win32_Process -Filter "ProcessId=$($iCUEProc.Id)" -ErrorAction SilentlyContinue
    if ($w) { $w.GetOwner().User } else { '?' }
} else { $null }
$startupLog = @(
    Get-ChildItem 'C:\ProgramData\Corsair\Logs\CUE5\*.log'           -ErrorAction SilentlyContinue
    Get-ChildItem "$env:LOCALAPPDATA\Corsair\Logs\CUE5\*.log"         -ErrorAction SilentlyContinue
) | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host ''
Write-Host 'iCUE Watchdog - Uninstall' -ForegroundColor Cyan

Write-Host '  Elevated : ' -NoNewline -ForegroundColor DarkGray
if ($isAdmin) { Write-Host 'Yes' -ForegroundColor Green  }
else          { Write-Host 'No'  -ForegroundColor Yellow }

Write-Host '  iCUE     : ' -NoNewline -ForegroundColor DarkGray
if ($iCUEProc) { Write-Host "Running  PID $($iCUEProc.Id)  ($procUser)" -ForegroundColor Green }
else           { Write-Host 'Not running'                                -ForegroundColor Red   }

Write-Host '  Log      : ' -NoNewline -ForegroundColor DarkGray
if ($startupLog) { Write-Host $startupLog.FullName -ForegroundColor Gray   }
else             { Write-Host '(none found)'       -ForegroundColor Yellow }

Write-Host ''
Write-Host "[x] Removing scheduled task '$TaskName'..." -ForegroundColor Red
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "[x] Removing installed files from: $TargetDir" -ForegroundColor Red
if (Test-Path $TargetDir) {
    Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Uninstall complete!' -ForegroundColor Green
Write-Host ''
:icue_uninstall: