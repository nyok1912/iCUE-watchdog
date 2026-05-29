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
