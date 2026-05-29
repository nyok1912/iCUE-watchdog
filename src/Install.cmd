@echo off
:: iCUE Watchdog - Install
::
:: Registers the iCUE Watchdog Scheduled Task.
:: Requires administrator privileges (will auto-elevate).

set "SysPath=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" set "SysPath=%SystemRoot%\Sysnative"
set "ps=%SysPath%\WindowsPowerShell\v1.0\powershell.exe"

:: Auto-elevate if not running as administrator
powershell -NoProfile -Command "if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')){Start-Process '%~f0' -Verb RunAs;exit 1}"
if %errorlevel% neq 0 exit /b

"%ps%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
pause
