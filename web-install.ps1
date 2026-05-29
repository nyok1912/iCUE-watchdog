# web-install.ps1 - iCUE Watchdog launcher
#
# Usage (PowerShell, no admin required):
#   irm https://raw.githubusercontent.com/nyok1912/iCUE-watchdog/main/web-install.ps1 | iex
#
# Downloads the latest iCUE-Watchdog.cmd from GitHub Releases and opens the
# interactive menu. UAC elevation is requested automatically when needed.

$ErrorActionPreference = 'Stop'

$url  = 'https://github.com/nyok1912/iCUE-watchdog/releases/latest/download/iCUE-Watchdog.cmd'
$dest = "$env:TEMP\iCUE-Watchdog.cmd"

Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
& cmd.exe /c "`"$dest`""
