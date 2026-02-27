#!/bin/bash

# Postman Linux Updater - Quick Install
# Usage: curl -fsSL <raw-url>/install.sh | bash

set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/$(git config user.name 2>/dev/null || echo 'USER')/postman-updater/main/update-postman.sh"
INSTALL_PATH="/usr/local/bin/update-postman"
SUDOERS_PATH="/etc/sudoers.d/postman-updater"

echo "=== Postman Linux Updater - Installer ==="

# Download script
echo "[1/3] Downloading update-postman.sh..."
sudo curl -fsSL -o "$INSTALL_PATH" "$SCRIPT_URL"
sudo chmod +x "$INSTALL_PATH"
echo "      Installed to $INSTALL_PATH"

# Configure sudoers
echo "[2/3] Configuring passwordless sudo..."
CURRENT_USER=$(whoami)
sudo tee "$SUDOERS_PATH" > /dev/null << EOF
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman /opt/Postman.backup-*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman.backup-* /opt/Postman
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/tar -xzf * -C /opt/
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/ln -sf /opt/Postman/Postman /usr/bin/postman
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Postman.backup-*
EOF
sudo chmod 440 "$SUDOERS_PATH"
echo "      Sudoers configured for user: $CURRENT_USER"

# Done
echo "[3/3] Done!"
echo ""
echo "Usage:"
echo "  update-postman                    # auto-update"
echo "  update-postman --force            # force reinstall"
echo "  update-postman --version 11.20.0  # specific version"
echo ""
echo "Optional: Add to startup scripts:"
echo '  (sleep 60 && update-postman) &'
