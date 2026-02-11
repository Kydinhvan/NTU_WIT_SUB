#!/bin/bash
# Bridge Backend Quick Start Script for macOS/Linux
# Run this from the NTU_WH directory: ./start-backend.sh

echo ""
echo "============================================"
echo "  Bridge Backend Setup"
echo "============================================"
echo ""

# Check if .env exists
if [ ! -f "hackathonerds/.env" ]; then
    echo "[!] .env file not found"
    echo ""
    echo "Creating .env from template..."
    cp hackathonerds/.env.example hackathonerds/.env
    echo ""
    echo "[*] Please edit hackathonerds/.env and add your OPENROUTER_API_KEY"
    echo "[*] Get a free key at: https://openrouter.ai/keys"
    echo ""
    read -p "Press Enter after you've added your API key..."
fi

# Check if venv exists
if [ ! -d ".venv" ]; then
    echo "[*] Creating virtual environment..."
    python3 -m venv .venv
    if [ $? -ne 0 ]; then
        echo "[!] Failed to create virtual environment"
        echo "[!] Make sure Python 3.10+ is installed"
        exit 1
    fi
fi

# Activate venv
echo "[*] Activating virtual environment..."
source .venv/bin/activate

# Install dependencies
echo "[*] Installing Python dependencies..."
pip install -r hackathonerds/requirements.txt
if [ $? -ne 0 ]; then
    echo "[!] Failed to install dependencies"
    exit 1
fi

echo ""
echo "============================================"
echo "  Starting Backend Server"
echo "============================================"
echo ""
echo "Backend will run on http://localhost:8000"
echo "Press Ctrl+C to stop the server"
echo ""

cd hackathonerds
uvicorn api:app --host 0.0.0.0 --port 8000 --reload
