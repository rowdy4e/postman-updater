#!/bin/bash

# Postman Updater - Install Script
# Usage: ./install.sh

set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Postman Updater - Installer ==="

[[ "$EUID" -eq 0 ]] && { echo "Do not run as root. This installs to user directories."; exit 1; }

echo "[1/2] Creating directories..."
mkdir -p "$INSTALL_DIR" "$HOME/.local/opt" "$HOME/.local/share/applications" "$HOME/.local/share/postman-updater"
echo "      ✓ ~/.local directories ready"

echo "[2/2] Installing script..."
cp "$SCRIPT_DIR/update-postman.sh" "$INSTALL_DIR/update-postman"
chmod +x "$INSTALL_DIR/update-postman"
echo "      ✓ Installed to $INSTALL_DIR/update-postman"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "⚠  ~/.local/bin is not in your PATH. Add this to your ~/.bashrc or ~/.profile:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! No sudo required."
echo ""
echo "Usage:"
echo "  update-postman                    # auto-update (or fresh install)"
echo "  update-postman --force            # force reinstall"
echo "  update-postman --version 11.20.0  # install specific version"
echo "  update-postman --uninstall        # remove Postman"
