#!/bin/bash

# Postman Updater - Install Script
# Usage: sudo ./install.sh

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURRENT_USER="${SUDO_USER:-$(whoami)}"

echo "=== Postman Updater - Installer ==="

[[ "$EUID" -ne 0 ]] && { echo "Run with sudo: sudo ./install.sh"; exit 1; }

echo "[1/3] Installing script..."
cp "$SCRIPT_DIR/update-postman.sh" "$INSTALL_DIR/update-postman"
chmod +x "$INSTALL_DIR/update-postman"
echo "      ✓ Installed to $INSTALL_DIR/update-postman"

echo "[2/3] Configuring passwordless sudo for user: $CURRENT_USER..."
cat > /etc/sudoers.d/postman-updater << EOF
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman /opt/Postman.backup-*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman.backup-* /opt/Postman
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/tar -xzf * -C /opt/
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/ln -sf /opt/Postman/Postman /usr/bin/postman
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Postman.backup-*
EOF
chmod 440 /etc/sudoers.d/postman-updater
echo "      ✓ Sudoers configured"

echo "[3/3] Done!"
echo ""
echo "Usage:"
echo "  update-postman                    # auto-update (or fresh install)"
echo "  update-postman --force            # force reinstall"
echo "  update-postman --version 11.20.0  # specific version"
