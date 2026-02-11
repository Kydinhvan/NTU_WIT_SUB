#!/bin/bash
# Bridge Frontend Quick Start Script for macOS/Linux
# Run this from the NTU_WH directory: ./start-frontend.sh

echo ""
echo "============================================"
echo "  Bridge Frontend (Flutter Web)"
echo "============================================"
echo ""

# Check Flutter installation
if ! command -v flutter &> /dev/null; then
    echo "[!] Flutter not found in PATH"
    echo "[!] Please install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

cd bridge

# Get Flutter dependencies
echo "[*] Installing Flutter dependencies..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "[!] Failed to get Flutter dependencies"
    exit 1
fi

echo ""
echo "============================================"
echo "  Starting Flutter Web App"
echo "============================================"
echo ""
echo "[*] Make sure the backend is running on http://localhost:8000"
echo "[*] App will open in Chrome automatically"
echo "[*] Press 'r' to hot reload, 'R' to hot restart, 'q' to quit"
echo ""

flutter run -d chrome
