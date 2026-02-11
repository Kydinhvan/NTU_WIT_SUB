@echo off
REM Bridge Frontend Quick Start Script for Windows
REM Run this from the NTU_WH directory

echo.
echo ============================================
echo   Bridge Frontend (Flutter Web)
echo ============================================
echo.

REM Check Flutter installation
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [!] Flutter not found in PATH
    echo [!] Please install Flutter from: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

cd bridge

REM Get Flutter dependencies
echo [*] Installing Flutter dependencies...
flutter pub get
if errorlevel 1 (
    echo [!] Failed to get Flutter dependencies
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Starting Flutter Web App
echo ============================================
echo.
echo [*] Make sure the backend is running on http://localhost:8000
echo [*] App will open in Chrome automatically
echo [*] Press 'r' to hot reload, 'R' to hot restart, 'q' to quit
echo.

flutter run -d chrome
