# web-install.ps1 - iCUE Watchdog web installer
#
# Usage (PowerShell, no admin required):
#   irm https://raw.githubusercontent.com/nyok1912/iCUE-watchdog/main/web-install.ps1 | iex
#
# Downloads the latest iCUE-Watchdog.cmd from GitHub Releases and runs --install.
# The installer will request UAC elevation automatically if needed.

$ErrorActionPreference = 'Stop'

$url  = 'https://github.com/nyok1912/iCUE-watchdog/releases/latest/download/iCUE-Watchdog.cmd'
$dest = "$env:TEMP\iCUE-Watchdog.cmd"

Write-Host ''
Write-Host 'iCUE Watchdog - Web Installer' -ForegroundColor Cyan
Write-Host "  Source : $url" -ForegroundColor DarkGray
Write-Host "  Target : $dest" -ForegroundColor DarkGray
Write-Host ''

Write-Host '  Downloading...' -ForegroundColor DarkGray
Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
Write-Host '  Done.' -ForegroundColor Green

Write-Host '  Launching installer (UAC prompt may appear)...' -ForegroundColor DarkGray
& cmd.exe /c "`"$dest`" --install"
