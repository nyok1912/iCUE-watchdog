:: =========================
:: Autoelevar a administrador
:: =========================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

wmic process where "name like '%icue%' or name like '%corsair%'" call terminate