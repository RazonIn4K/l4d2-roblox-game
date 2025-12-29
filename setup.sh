#!/bin/bash
# L4D2 Roblox Horror Game - Unix Setup Script

set -e

echo "========================================"
echo "L4D2 Horror Game Development Setup"
echo "========================================"
echo

# Check if Rokit is installed
if ! command -v rokit &> /dev/null; then
    echo "[1/4] Installing Rokit..."
    curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
    echo "Rokit installed. Please restart your terminal and run this script again."
    exit 0
fi

echo "[1/4] Rokit found, installing tools..."
rokit install

echo
echo "[2/4] Installing Wally packages..."
wally install

echo
echo "[3/4] Creating Packages folders if needed..."
mkdir -p Packages
mkdir -p ServerPackages

echo
echo "[4/4] Setup complete!"
echo
echo "========================================"
echo "Next Steps:"
echo "========================================"
echo "1. Open Roblox Studio"
echo "2. Install Rojo plugin from Creator Hub"
echo "3. Run 'rojo serve' in this directory"
echo "4. Connect via Rojo plugin in Studio"
echo
echo "Development Commands:"
echo "  rojo serve      - Start file sync"
echo "  wally install   - Update packages"
echo "  selene src/     - Lint code"
echo "  stylua src/     - Format code"
echo "========================================"
