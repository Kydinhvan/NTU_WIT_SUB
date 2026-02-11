@echo off
REM Bridge Backend Quick Start Script for Windows
REM Run this from the NTU_WH directory

echo.
echo ============================================
echo   Bridge Backend Setup
echo ============================================
echo.

REM Check if .env exists
if not exist "hackathonerds\.env" (
    echo [!] .env file not found
    echo.
    echo Creating .env from template...
    copy hackathonerds\.env.example hackathonerds\.env
    echo.
    echo [*] Please edit hackathonerds\.env and add your OPENROUTER_API_KEY
    echo [*] Get a free key at: https://openrouter.ai/keys
    echo.
    pause
)

REM Check if venv exists
if not exist ".venv\Scripts\activate.bat" (
    echo [*] Creating virtual environment...
    python -m venv .venv
    if errorlevel 1 (
        echo [!] Failed to create virtual environment
        echo [!] Make sure Python 3.10+ is installed
        pause
        exit /b 1
    )
)

REM Activate venv
echo [*] Activating virtual environment...
call .venv\Scripts\activate.bat

REM Install dependencies
echo [*] Installing Python dependencies...
pip install -r hackathonerds\requirements.txt
if errorlevel 1 (
    echo [!] Failed to install dependencies
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Starting Backend Server
echo ============================================
echo.
echo Backend will run on http://localhost:8000
echo Press Ctrl+C to stop the server
echo.

cd hackathonerds
uvicorn api:app --host 0.0.0.0 --port 8000 --reload
