@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Tests failed with exit code %ERRORLEVEL%.
    pause
    exit /b %ERRORLEVEL%
)
echo.
echo All tests passed.
pause
