@echo off
REM L4D2 Roblox Horror Game - Windows Setup Script

echo ========================================
echo L4D2 Horror Game Development Setup
echo ========================================
echo.

REM Check if Rokit is installed
where rokit >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [1/4] Installing Rokit...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/rojo-rbx/rokit/releases/latest/download/rokit-windows-x86_64.zip' -OutFile 'rokit.zip'"
    powershell -Command "Expand-Archive -Path 'rokit.zip' -DestinationPath 'rokit-temp' -Force"
    rokit-temp\rokit.exe self-install
    del rokit.zip
    rmdir /s /q rokit-temp
    echo Rokit installed. Please restart your terminal and run this script again.
    pause
    exit /b
)

echo [1/4] Rokit found, installing tools...
rokit install

echo.
echo [2/4] Installing Wally packages...
wally install

echo.
echo [3/4] Creating Packages folders if needed...
if not exist "Packages" mkdir Packages
if not exist "ServerPackages" mkdir ServerPackages

echo.
echo [4/4] Setup complete!
echo.
echo ========================================
echo Next Steps:
echo ========================================
echo 1. Open Roblox Studio
echo 2. Install Rojo plugin from Creator Hub
echo 3. Run 'rojo serve' in this directory
echo 4. Connect via Rojo plugin in Studio
echo.
echo Development Commands:
echo   rojo serve      - Start file sync
echo   wally install   - Update packages
echo   selene src/     - Lint code
echo   stylua src/     - Format code
echo ========================================
pause
