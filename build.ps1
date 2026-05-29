# build.ps1 - Assembles distributable CMD files from src/ modules
#
# Output:
#   build\Separate-Files-Version\  (self-contained .cmd files, no .ps1 needed)
#   build\All-In-One-Version\iCUE-Watchdog.cmd  (all PS embedded in a single CMD)
#
# Develop and test in src/. Run build.ps1 to generate distributable output.
# CMD files are saved without BOM (plain ASCII/UTF-8 compatible).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root   = $PSScriptRoot
$src    = "$root\src"
$sepDir = "$root\build\Separate-Files-Version"
$aioDir = "$root\build\All-In-One-Version"

New-Item -ItemType Directory -Path $sepDir, $aioDir -Force | Out-Null
Get-ChildItem $sepDir -File | Remove-Item -Force   # clean stale output
Get-ChildItem $aioDir -File | Remove-Item -Force   # clean stale output

# Encoding: no BOM - cmd.exe doesn't handle UTF-8 BOM well
$enc = New-Object System.Text.UTF8Encoding($false)

function Write-Cmd ($path, $content) {
    [IO.File]::WriteAllText($path, $content, $enc)
    Write-Host "[+] Written: $path" -ForegroundColor Green
}

# ============================================================
#  Read PS modules
# ============================================================
$restorePs   = [IO.File]::ReadAllText("$src\Restore.ps1").TrimEnd()
$installPs   = [IO.File]::ReadAllText("$src\Install.ps1").TrimEnd()
$uninstallPs = [IO.File]::ReadAllText("$src\Uninstall.ps1").TrimEnd()

# ---- Shared CMD preambles ----
$preambleNoElev = @'
setlocal EnableExtensions
setlocal DisableDelayedExpansion

set "SysPath=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" set "SysPath=%SystemRoot%\Sysnative"

set "ps=%SysPath%\WindowsPowerShell\v1.0\powershell.exe"
set "psc=%ps% -NoProfile -ExecutionPolicy Bypass -Command"
set re1=
set "_batf=%~f0"
set "_batp=%_batf:'=''%"

for %%A in (%*) do (
    if /i "%%A"=="re1" set re1=1
)

if exist "%SystemRoot%\Sysnative\cmd.exe" if not defined re1 (
    start /wait "%SystemRoot%\Sysnative\cmd.exe" /c ""%_batf%" %* re1"
    exit /b
)
'@

$preambleElev = @'
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
'@

# ============================================================
#  Separate-Files-Version\ — self-contained .cmd files only
# ============================================================
$restoreCmd = @"
@echo off
:: ============================================================================
::
::   iCUE Watchdog - Manual Restore
::   https://github.com/nyok1912/iCUE-watchdog
::
::   Checks the iCUE log and restarts iCUE if IPC has failed. No admin required.
::
::   Options:
::     (none)          silent: only restarts if log shows failure
::     --force         skip log check and always restart
::     --quiet         suppress all console output
::
:: ============================================================================

$preambleNoElev
set _force=
set _quiet=

for %%A in (%*) do (
    if /i "%%A"=="re1"      set re1=1
    if /i "%%A"=="--force"  set _force=1
    if /i "%%A"=="--quiet"  set _quiet=1
)

setlocal EnableDelayedExpansion
set ICUE_FORCE=
set ICUE_QUIET=
if defined _force  set ICUE_FORCE=1
if defined _quiet  set ICUE_QUIET=1
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split '\n:icue_restore\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
pause
exit /b

:: ============================================================================
::  PowerShell section - CMD never reaches here
:: ============================================================================
exit /b


:icue_restore:
$restorePs
:icue_restore:
"@

Write-Cmd "$sepDir\Restore.cmd" $restoreCmd

$installCmd = @"
@echo off
:: ============================================================================
::
::   iCUE Watchdog - Install
::   https://github.com/nyok1912/iCUE-watchdog
::
::   Registers the iCUE Watchdog Scheduled Task.
::   Requires administrator privileges (will auto-elevate).
::
:: ============================================================================

$preambleElev
setlocal EnableDelayedExpansion
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split ':icue_install\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
pause
exit /b

:: ============================================================================
::  PowerShell sections - CMD never reaches here
:: ============================================================================
exit /b


:icue_install:
$installPs
:icue_install:


:icue_restore:
$restorePs
:icue_restore:
"@

Write-Cmd "$sepDir\Install.cmd" $installCmd

$uninstallCmd = @"
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

$preambleElev
setlocal EnableDelayedExpansion
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split ':icue_uninstall\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
pause
exit /b

:: ============================================================================
::  PowerShell section - CMD never reaches here
:: ============================================================================
exit /b


:icue_uninstall:
$uninstallPs
:icue_uninstall:
"@

Write-Cmd "$sepDir\Uninstall.cmd" $uninstallCmd

# ============================================================
#  All-In-One-Version\iCUE-Watchdog.cmd
# ============================================================
$aioCmd = @"
@echo off
:: ============================================================================
::
::   iCUE Watchdog - All-In-One
::   https://github.com/nyok1912/iCUE-watchdog
::
::   Generated by build.ps1 - do not edit directly, edit src/ modules instead.
::
:: ============================================================================

@set "_ver=1.0"
@echo off

$preambleNoElev
:: Parse command-line arguments
set _mode=menu
set _force=

for %%A in (%*) do (
    if /i "%%A"=="--install"   set _mode=install
    if /i "%%A"=="--uninstall" set _mode=uninstall
    if /i "%%A"=="--restore"   set _mode=restore
    if /i "%%A"=="--help"      set _mode=help
    if /i "%%A"=="--force"     set _force=1
)

if not "%_mode%"=="menu" goto :run_%_mode%

:menu
cls
title  iCUE Watchdog %_ver%
echo.
echo   ==========================================
echo         iCUE Watchdog  v%_ver%
echo   ==========================================
echo.
echo    [1] Install   (register Scheduled Task)
echo    [2] Restore   (force restart)
echo    [3] Uninstall (remove task and files)
echo    [0] Exit
echo.
choice /C:1230 /N /M "   Choose: "
set _erl=%errorlevel%
if %_erl%==4 exit /b
if %_erl%==3 goto :do_uninstall
if %_erl%==2 (set _force=1& goto :do_restore)
if %_erl%==1 goto :do_install
goto :menu

:run_install
:do_install
setlocal EnableDelayedExpansion
net session >nul 2>&1
if %errorlevel% equ 0 goto :install_run
%psc% "Start-Process cmd.exe -Verb RunAs -Wait -ArgumentList ('/c', [string]::Concat([char]34, '!_batf!', [char]34), '--install')"
endlocal
if "%_mode%"=="install" exit /b
goto :menu
:install_run
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split ':icue_install\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
if "%_mode%"=="install" (pause & exit /b)
pause
goto :menu

:run_uninstall
:do_uninstall
setlocal EnableDelayedExpansion
net session >nul 2>&1
if %errorlevel% equ 0 goto :uninstall_run
%psc% "Start-Process cmd.exe -Verb RunAs -Wait -ArgumentList ('/c', [string]::Concat([char]34, '!_batf!', [char]34), '--uninstall')"
endlocal
if "%_mode%"=="uninstall" exit /b
goto :menu
:uninstall_run
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split ':icue_uninstall\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
if "%_mode%"=="uninstall" (pause & exit /b)
pause
goto :menu

:run_restore
:do_restore
setlocal EnableDelayedExpansion
set ICUE_FORCE=
if defined _force set ICUE_FORCE=1
%psc% "`$f=[IO.File]::ReadAllText('!_batp!') -split '\n:icue_restore\:.*'; . ([scriptblock]::Create(`$f[1]))"
endlocal
if "%_mode%"=="restore" exit /b
pause
goto :menu

:run_help
cls
echo.
echo   iCUE Watchdog v%_ver%
echo.
echo   Web  : irm [ScriptUrl] ^| iex
echo   Local: iCUE-Watchdog.cmd [options]
echo.
echo     --install    Register Scheduled Task (runs on unlock + resume)
echo     --uninstall  Remove Scheduled Task and installed files
echo     --restore    Check iCUE log and restart if IPC has failed
echo     --force      Force restart (skip log check)
echo     --help       Show this message
echo.
exit /b

:: ============================================================================
::  PowerShell sections - CMD never reaches here
:: ============================================================================
exit /b


:icue_install:
$installPs
:icue_install:


:icue_uninstall:
$uninstallPs
:icue_uninstall:


:icue_restore:
$restorePs
:icue_restore:
"@

Write-Cmd "$aioDir\iCUE-Watchdog.cmd" $aioCmd

Write-Host ''
Write-Host 'Build complete!' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Separate-Files-Version\  (self-contained .cmd files)'
Write-Host '    Install.cmd    - Install scheduled task'
Write-Host '    Uninstall.cmd  - Remove scheduled task + files'
Write-Host '    Restore.cmd    - Manual restore (force-restart or log-based)'
Write-Host ''
Write-Host '  All-In-One-Version\'
Write-Host '    iCUE-Watchdog.cmd - Interactive menu (all actions, self-contained)'
Write-Host ''
