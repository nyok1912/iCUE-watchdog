# test.ps1 - iCUE-Watchdog test suite runner
#
# Usage:
#   .\test.ps1                  # run all tests (admin tests skipped if not elevated)
#   .\test.ps1 -SkipBuild       # skip the build step (use existing build/ output)
#
# Tests that require admin (install/uninstall) are automatically skipped when
# not running as administrator. Run PowerShell as admin to include them.

param(
    [switch]$SkipBuild   # Skip running build.ps1 before tests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root     = $PSScriptRoot
$testsDir = "$root\tests"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   iCUE-Watchdog Test Suite" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
if ($isAdmin) {
    Write-Host "   Elevation : YES (all tests will run)" -ForegroundColor Green
} else {
    Write-Host "   Elevation : NO  (install/uninstall tests skipped)" -ForegroundColor Yellow
}
Write-Host "==========================================" -ForegroundColor Cyan

# --- Build step: regenerate CMD files from src/ ---
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "  [Build] Running build.ps1..." -ForegroundColor DarkGray
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\build.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] build.ps1 failed (exit $LASTEXITCODE). Aborting tests." -ForegroundColor Red
        exit 1
    }
}

# --- Test definitions ---
$tests = @(
    @{ File = 'test-restore.ps1';   RequiresAdmin = $false; Description = 'Restore logic + all execution modes' },
    @{ File = 'test-install.ps1';   RequiresAdmin = $true;  Description = 'Install: deploys files + registers task' },
    @{ File = 'test-uninstall.ps1'; RequiresAdmin = $true;  Description = 'Uninstall: removes files + task' }
)

# --- Run tests ---
$results = [ordered]@{}

foreach ($t in $tests) {
    $testPath = "$testsDir\$($t.File)"
    Write-Host ""

    if (-not (Test-Path $testPath)) {
        Write-Host "  [SKIP] $($t.File) (file not found)" -ForegroundColor Yellow
        $results[$t.File] = 'SKIP'
        continue
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $testPath
    $results[$t.File] = $LASTEXITCODE
}

# --- Summary ---
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$failed = 0
foreach ($name in $results.Keys) {
    $r = $results[$name]
    if ($r -eq 'SKIP') {
        Write-Host "  [SKIP] $name" -ForegroundColor Yellow
    } elseif ($r -eq 0) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $name" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "  All tests passed!" -ForegroundColor Green
} else {
    Write-Host "  $failed test file(s) FAILED." -ForegroundColor Red
}
Write-Host ""
exit $failed
