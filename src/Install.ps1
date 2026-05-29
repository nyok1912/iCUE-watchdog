# iCUE Watchdog - Install
# Auto-elevates if not running as administrator.
#
# Usages:
#   - Standalone: .\Install.ps1
#   - From AIO CMD bundle: automatically called (elevation handled by CMD)
#
# When called from the AIO CMD bundle, $env:_batf points to the CMD file.
# The Restore module is extracted from the bundle's :icue_restore: section.
# When called standalone, Restore.ps1 is read from $PSScriptRoot.

param(
    [switch]$AcceptDefaults   # Skip interactive prompts and use defaults (Silent, no Force)
)

$TargetDir    = "$env:LOCALAPPDATA\iCUE-Watchdog"
$TargetScript = "$TargetDir\Restore.ps1"
$TaskName     = 'iCUE-Watchdog'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# When called from the CMD bundle, elevation is already guaranteed by the CMD preamble.
# When called standalone, auto-elevate via UAC if needed.
if (-not $env:_batf) {
    if (-not $isAdmin) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($AcceptDefaults) { $argList += ' -AcceptDefaults' }
        Start-Process powershell -Verb RunAs -Wait -ArgumentList $argList
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
Write-Host 'iCUE Watchdog - Install' -ForegroundColor Cyan

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
Write-Host '[+] Creating install directory...' -ForegroundColor Cyan
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory $TargetDir -Force | Out-Null
}

# Locate the Restore module:
#   1. Extract :icue_restore: section from the running CMD bundle ($env:_batf)
#   2. Fallback: read Restore.ps1 from the same folder as this script (dev mode)
$cmdFile = $env:_batf
if ($cmdFile -and (Test-Path $cmdFile) -and $cmdFile -match '\.cmd$') {
    Write-Host '[+] Extracting Restore module from CMD bundle...' -ForegroundColor Cyan
    $restoreCode = ([IO.File]::ReadAllText($cmdFile) -split '(?m)^:icue_restore\:.*')[1].Trim()
} elseif ($PSScriptRoot -and (Test-Path "$PSScriptRoot\Restore.ps1")) {
    Write-Host '[+] Reading Restore.ps1 from src/ folder...' -ForegroundColor Cyan
    $restoreCode = [IO.File]::ReadAllText("$PSScriptRoot\Restore.ps1")
} else {
    Write-Host 'ERROR: Cannot locate Restore module. Run from iCUE-Watchdog.cmd or the src\ folder.' -ForegroundColor Red
    exit 1
}

[IO.File]::WriteAllText($TargetScript, $restoreCode, [Text.Encoding]::UTF8)
Write-Host "[+] Saved: $TargetScript" -ForegroundColor Cyan

if ($AcceptDefaults) {
    $modeIdx  = 0   # Silent (default)
    $forceIdx = 0   # No force (default)
} else {
    $modeChoices = [System.Management.Automation.Host.ChoiceDescription[]] @(
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Silent', 'Task runs in the background with no visible window (-Quiet)'),
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Normal', 'Task opens a console window when it runs')
    )
    $modeIdx  = $Host.UI.PromptForChoice('', '  Scheduled task mode:', $modeChoices, 0)

    $forceChoices = [System.Management.Automation.Host.ChoiceDescription[]] @(
        (New-Object System.Management.Automation.Host.ChoiceDescription '&No',  'Only restarts iCUE when an IPC failure is detected in the log'),
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Always restarts iCUE when the task fires, without checking the log (-Force)')
    )
    $forceIdx = $Host.UI.PromptForChoice('', '  Force mode (always restart)?:', $forceChoices, 0)
}

if ($modeIdx -eq 1) {
    $windowArg = '-WindowStyle Normal'
    $taskArgs  = ''
} else {
    $windowArg = '-WindowStyle Hidden'
    $taskArgs  = '-Quiet'
}
if ($forceIdx -eq 1) { $taskArgs = "$taskArgs -Force".TrimStart() }
Write-Host ''

# Build Task XML
# The Subscription element holds the event query as an XML-escaped string.
$sub = '&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;'

$xml = (@(
    '<?xml version="1.0" encoding="UTF-16"?>',
    '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">',
    '  <RegistrationInfo>',
    '    <Author>Corsair Community</Author>',
    '    <Description>Auto-restarts iCUE when IPC fails after unlock or resume from sleep.</Description>',
    "    <URI>$TaskName</URI>",
    '  </RegistrationInfo>',
    '  <Triggers>',
    '    <SessionStateChangeTrigger>',
    '      <Enabled>true</Enabled>',
    '      <StateChange>SessionUnlock</StateChange>',
    '    </SessionStateChangeTrigger>',
    '    <EventTrigger>',
    '      <Enabled>true</Enabled>',
    "      <Subscription>$sub</Subscription>",
    '    </EventTrigger>',
    '  </Triggers>',
    '  <Principals>',
    '    <Principal id="Author">',
    '      <LogonType>InteractiveToken</LogonType>',
    '      <RunLevel>LeastPrivilege</RunLevel>',
    '    </Principal>',
    '  </Principals>',
    '  <Settings>',
    '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>',
    '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>',
    '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>',
    '    <AllowHardTerminate>true</AllowHardTerminate>',
    '    <StartWhenAvailable>true</StartWhenAvailable>',
    '    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>',
    '    <IdleSettings>',
    '      <StopOnIdleEnd>true</StopOnIdleEnd>',
    '      <RestartOnIdle>false</RestartOnIdle>',
    '    </IdleSettings>',
    '    <AllowStartOnDemand>true</AllowStartOnDemand>',
    '    <Enabled>true</Enabled>',
    '    <Hidden>false</Hidden>',
    '    <RunOnlyIfIdle>false</RunOnlyIfIdle>',
    '    <WakeToRun>false</WakeToRun>',
    '    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>',
    '    <Priority>7</Priority>',
    '  </Settings>',
    '  <Actions Context="Author">',
    '    <Exec>',
    '      <Command>powershell.exe</Command>',
    "      <Arguments>$windowArg -ExecutionPolicy Bypass -NoProfile -File `"$TargetScript`" $taskArgs</Arguments>".TrimEnd(),
    '    </Exec>',
    '  </Actions>',
    '</Task>'
) -join "`r`n")

Write-Host "[+] Registering scheduled task '$TaskName'..." -ForegroundColor Cyan
Register-ScheduledTask -Xml $xml -TaskName $TaskName -Force | Out-Null

Write-Host ''
Write-Host 'Install complete!' -ForegroundColor Green
$modeDesc  = if ($modeIdx -eq 1) { 'normal mode (visible window)' } else { 'silent mode (-Quiet)' }
$forceDesc = if ($forceIdx -eq 1) { ' + forced (-Force)' } else { '' }
Write-Host "Task '$TaskName' installed in $modeDesc$forceDesc."
Write-Host ''
