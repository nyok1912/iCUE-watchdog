@echo off
:: iCUE Watchdog - Manual Restore
::
:: Checks the iCUE log and restarts iCUE if IPC has failed.
::
:: Options:
::   (none)           Silent: only restarts on failure
::   --force          Skip log check, always restart
::   --quiet          Suppress all console output

set "SysPath=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" set "SysPath=%SystemRoot%\Sysnative"
set "ps=%SysPath%\WindowsPowerShell\v1.0\powershell.exe"

set re1=
set _force=
set _quiet=

for %%A in (%*) do (
    if /i "%%A"=="re1"      set re1=1
    if /i "%%A"=="--force"  set _force=1
    if /i "%%A"=="--quiet"  set _quiet=1
)

:: Ensure 64-bit process on 64-bit Windows
if exist "%SystemRoot%\Sysnative\cmd.exe" if not defined re1 (
    start /wait "%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %* re1"
    exit /b
)

set ICUE_FORCE=
set ICUE_QUIET=
if defined _force  set ICUE_FORCE=1
if defined _quiet  set ICUE_QUIET=1

"%ps%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
pause
