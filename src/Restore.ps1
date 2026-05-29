# iCUE Watchdog - Restore Module
# Reads the latest iCUE log and restarts iCUE if IPC communication has failed.
#
# Usages:
#   - Scheduled task (silent):  powershell.exe -WindowStyle Hidden -File Restore.ps1 -Quiet
#   - Manual / interactive:     .\Restore.ps1 [-Force]
#   - From CMD wrapper:         `. ([scriptblock]::Create($code)) [-Force]`

param (
    [switch]$Force,   # Skip log check and always restart iCUE
    [switch]$Quiet    # Suppress all console output
)

# Honour env vars set by the CMD wrapper
if ($env:ICUE_FORCE -eq '1') { $Force = $true }
if ($env:ICUE_QUIET -eq '1') { $Quiet = $true }

function Log([string]$msg, [string]$color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

function Get-iCUELogFiles {
    @(
        Get-ChildItem "$LogDirPD\*.log" -ErrorAction SilentlyContinue
        Get-ChildItem "$LogDirLA\*.log" -ErrorAction SilentlyContinue
    )
}

$LogDirPD = 'C:\ProgramData\Corsair\Logs\CUE5'
$LogDirLA = "$env:LOCALAPPDATA\Corsair\Logs\CUE5"
$iCUEExe  = 'C:\Program Files\Corsair\Corsair iCUE5 Software\iCUE Launcher.exe'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    (New-Object -ComObject WScript.Shell).Popup(
        "iCUE Watchdog must not run as administrator.`nLaunch Restore.ps1 from a normal (non-elevated) terminal.",
        0, 'iCUE Watchdog', 0x10) | Out-Null
    exit 2
}

Log ''
Log 'iCUE Watchdog' 'Cyan'

if (-not $Quiet) {
    $iCUEProc = Get-Process -Name 'iCUE' -ErrorAction SilentlyContinue | Select-Object -First 1
    $procUser = if ($iCUEProc) {
        $w = Get-WmiObject Win32_Process -Filter "ProcessId=$($iCUEProc.Id)" -ErrorAction SilentlyContinue
        if ($w) { $w.GetOwner().User } else { '?' }
    } else { $null }
    $startupLog = Get-iCUELogFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

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
}

# Give the system time to settle after unlock / resume from sleep
if (-not $Force) {
    Log '  Waiting 3 seconds for system to settle...'
    Start-Sleep -Seconds 3
}

$isFailed = [bool]$Force

if ($Force) {
    Log '  Mode: forced restart (skipping log check)' 'Yellow'
}

if (-not $isFailed) {
    Log '  Checking iCUE log...'
    $latest = Get-iCUELogFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latest) {
        Log "  Log: $($latest.Name)"
        $lines     = Get-Content $latest.FullName -Tail 200 2>$null
        $lastEnter = -1
        $lastLeave = -1

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'Entering working state|StartEnumeration finished') {
                $lastEnter = $i
            }
            if ($lines[$i] -match 'Leaving working state|ConnectionLost|StopEnumeration finished|Disable all enumerators') {
                $lastLeave = $i
            }
        }

        if ($lastLeave -gt $lastEnter) { $isFailed = $true }
    } else {
        Log '  No log files found.' 'Yellow'
    }
}

$restartRequested = $false
if (-not $isFailed -and -not $Quiet) {
    $choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
        (New-Object System.Management.Automation.Host.ChoiceDescription '&No',  'Exit without restarting'),
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Force restart iCUE now')
    )
    $answer = $Host.UI.PromptForChoice('', '  Status: IPC OK. Force restart anyway?', $choices, 0)
    if ($answer -eq 1) { $isFailed = $true; $restartRequested = $true }
}

if ($isFailed) {
    if (-not $Force -and -not $restartRequested) {
        Log '  Status: IPC failure detected - restarting iCUE...' 'Red'
    }

    Log '  Stopping iCUE...'
    Get-Process -Name 'iCUE' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    if (Get-Process -Name 'iCUE' -ErrorAction SilentlyContinue) {
        # iCUE may be running elevated — request admin just for the kill, then continue non-elevated
        Log '  Process still running, requesting admin to stop it...' 'Yellow'
        Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden `
            -ArgumentList '-NoProfile -Command "Get-Process -Name iCUE -EA 0 | Stop-Process -Force -EA 0"'
        Start-Sleep -Seconds 3
    }

    if (Get-Process -Name 'iCUE' -ErrorAction SilentlyContinue) {
        Log '  Warning: could not stop iCUE.' 'Yellow'
    } elseif (Test-Path $iCUEExe) {
        Log '  Starting iCUE...'
        # Snapshot existing logs + line counts so we can distinguish new content after restart
        $knownLogs  = Get-iCUELogFiles | Select-Object -ExpandProperty FullName
        $resumeFile = Get-iCUELogFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $resumeLine = if ($resumeFile) {
                          @(Get-Content $resumeFile.FullName -ErrorAction SilentlyContinue).Count
                      } else { 0 }
        (New-Object -ComObject Shell.Application).ShellExecute(
            $iCUEExe, '--autorun', (Split-Path $iCUEExe), 'open', 1)

        if (-not $Quiet) {
            Write-Host '  Detecting devices:' -ForegroundColor Gray
            $startTime  = Get-Date
            $timeout    = 30
            $ready      = $false
            $currentLog = $null
            $lastLine   = 0

            while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
                Start-Sleep -Milliseconds 50

                # Locate the active log: new file OR existing file that iCUE appended to
                if (-not $currentLog) {
                    $newFile = Get-iCUELogFiles |
                               Where-Object { $_.FullName -notin $knownLogs } |
                               Sort-Object LastWriteTime -Descending |
                               Select-Object -First 1
                    if ($newFile) {
                        $currentLog = $newFile.FullName
                        $lastLine   = 0
                    } elseif ($resumeFile) {
                        $count = @(Get-Content $resumeFile.FullName -ErrorAction SilentlyContinue).Count
                        if ($count -gt $resumeLine) {
                            $currentLog = $resumeFile.FullName
                            $lastLine   = $resumeLine
                        }
                    }
                }

                if ($currentLog) {
                    $allLines = @(Get-Content $currentLog -ErrorAction SilentlyContinue)
                    if ($allLines.Count -gt $lastLine) {
                        $newLines = $allLines[$lastLine..($allLines.Count - 1)]
                        $lastLine = $allLines.Count
                        foreach ($line in $newLines) {
                            if ($line -match 'cue\.devices\.set: (.+?) \(') {
                                Write-Host "    + $($Matches[1])" -ForegroundColor Cyan
                            }
                            if ($line -match 'Devices ready received from service|Enumeration finished, all devices initialized') {
                                $ready = $true; break
                            }
                        }
                        if ($ready) { break }
                    }
                }
            }
            if (-not $ready) {
                Log '  Warning: timed out waiting for iCUE to detect devices.' 'Yellow'
            }
        }
    }
    Log '  Done.' 'Green'
    Log ''
    exit 1   # restart was triggered
}

Log '  Status: IPC OK - no restart needed.' 'Green'
Log ''
exit 0   # no restart needed
