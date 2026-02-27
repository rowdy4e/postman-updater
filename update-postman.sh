#!/bin/bash

# Postman Auto-Updater Script
# Usage: update-postman [--force] [--version X.Y.Z] [--uninstall]

set -euo pipefail

DATA_DIR="$HOME/.local/share/postman-updater"
POSTMAN_DIR="$HOME/.local/opt/Postman"
BIN_LINK="$HOME/.local/bin/postman"
DESKTOP_FILE="$HOME/.local/share/applications/postman.desktop"

LOG_FILE="$DATA_DIR/updater.log"
ETAG_FILE="$DATA_DIR/etag"
POSTMAN_PKG="$POSTMAN_DIR/app/resources/app/package.json"

BASE_URL="https://dl.pstmn.io/download"
DOWNLOAD_URL="$BASE_URL/latest/linux_64"
TMP_DIR="/tmp/postman-update-$$"

# --- Logging & notifications ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

notify() {
    local urgency="$1" summary="$2" body="$3"
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
        notify-send -u "$urgency" -i postman -a "Postman Updater" "$summary" "$body" 2>/dev/null || true
}

die() {
    log "ERROR: $*"
    notify "critical" "Postman Update Failed" "$*"
    exit 1
}

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Helpers ---

ensure_dirs() {
    mkdir -p "$DATA_DIR" "$HOME/.local/opt" "$HOME/.local/bin" "$HOME/.local/share/applications"
}

get_current_version() {
    if [[ -f "$POSTMAN_PKG" ]]; then
        grep -m1 '"version"' "$POSTMAN_PKG" | sed 's/.*": "\(.*\)".*/\1/'
    else
        echo "0.0.0"
    fi
}

get_remote_etag() {
    curl -sI --connect-timeout 10 --max-time 15 "$DOWNLOAD_URL" 2>/dev/null \
        | grep -i '^etag:' | tr -d '\r' | awk '{print $2}'
}

get_stored_etag() {
    [[ -f "$ETAG_FILE" ]] && cat "$ETAG_FILE" || echo ""
}

needs_update() {
    local remote_etag stored_etag
    remote_etag=$(get_remote_etag)

    if [[ -z "$remote_etag" ]]; then
        log "Could not fetch remote ETag"
        return 1
    fi

    stored_etag=$(get_stored_etag)
    log "Remote ETag: $remote_etag | Stored ETag: ${stored_etag:-none}"

    [[ "$remote_etag" != "$stored_etag" ]]
}

save_etag() {
    get_remote_etag > "$ETAG_FILE"
}

check_internet() {
    log "Checking internet connectivity..."
    local retries=3
    for ((i=1; i<=retries; i++)); do
        if ping -c1 -W3 1.1.1.1 &>/dev/null || curl -sf --connect-timeout 5 --max-time 10 "https://dl.pstmn.io" &>/dev/null; then
            log "Internet connection OK"
            return 0
        fi
        log "Attempt $i/$retries failed, waiting ${i}s..."
        sleep "$i"
    done
    die "No internet connection after $retries attempts"
}

download_postman() {
    mkdir -p "$TMP_DIR"
    local archive="$TMP_DIR/postman.tar.gz"

    log "Downloading Postman..."
    if ! curl -L --silent --show-error --connect-timeout 15 --max-time 300 -o "$archive" "$DOWNLOAD_URL"; then
        die "Download failed"
    fi

    [[ -s "$archive" ]] || die "Downloaded file is empty"
    log "Download OK ($(du -h "$archive" | cut -f1))"
    echo "$archive"
}

install_postman() {
    local archive="$1"
    local backup="${POSTMAN_DIR}.backup-$(date +%Y%m%d-%H%M%S)"

    log "Installing Postman..."

    # Backup
    if [[ -d "$POSTMAN_DIR" ]]; then
        mv "$POSTMAN_DIR" "$backup" || die "Backup failed"
    fi

    # Extract (tar extracts "Postman/" folder)
    if ! tar -xzf "$archive" -C "$HOME/.local/opt/"; then
        log "Extract failed, rolling back..."
        [[ -d "$backup" ]] && mv "$backup" "$POSTMAN_DIR"
        die "Extraction failed"
    fi

    # Symlink binary
    ln -sf "$POSTMAN_DIR/Postman" "$BIN_LINK"

    # Desktop entry
    cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=Postman
Comment=API Development Environment
Exec=$POSTMAN_DIR/Postman %U
Terminal=false
Type=Application
Icon=$POSTMAN_DIR/app/resources/app/assets/icon.png
StartupWMClass=postman
Categories=Development;
DESKTOP

    # Cleanup old backups (keep 1)
    ls -dt ${POSTMAN_DIR}.backup-* 2>/dev/null | tail -n +2 | xargs -r rm -rf || true

    log "Installation OK"
}

uninstall_postman() {
    log "=== Uninstalling Postman ==="

    rm -rf "$POSTMAN_DIR" ${POSTMAN_DIR}.backup-*
    rm -f "$BIN_LINK" "$DESKTOP_FILE" "$ETAG_FILE"

    log "Postman uninstalled"
    notify "normal" "Postman Uninstalled" "Postman has been removed from this system"
}

# --- Main ---

main() {
    ensure_dirs
    log "=== Postman Auto-Updater ==="
    [[ "$EUID" -eq 0 ]] && die "Do not run as root"

    local force=false target_version=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)     force=true; log "Force mode" ;;
            --version)   target_version="$2"; shift ;;
            --uninstall) uninstall_postman; exit 0 ;;
            *)           die "Unknown option: $1\nUsage: update-postman [--force] [--version X.Y.Z] [--uninstall]" ;;
        esac
        shift
    done

    # Override download URL for specific version
    if [[ -n "$target_version" ]]; then
        DOWNLOAD_URL="$BASE_URL/version/$target_version/linux_64"
        force=true
        log "Target version: $target_version ($DOWNLOAD_URL)"
    fi

    check_internet

    local current_version
    current_version=$(get_current_version)
    log "Installed: $current_version"

    # Check if update is needed
    if ! $force; then
        if ! needs_update; then
            log "Already up to date (ETag match)"
            notify "low" "Postman Up to Date" "Version $current_version — no update available"
            exit 0
        fi
        log "New version detected"
        notify "normal" "Updating Postman" "Current version: $current_version — downloading update..."
    else
        if [[ -n "$target_version" ]]; then
            notify "normal" "Updating Postman" "Installing version $target_version (current: $current_version)..."
        else
            notify "normal" "Updating Postman" "Force reinstalling (current: $current_version)..."
        fi
    fi

    # Download & install
    local archive
    archive=$(download_postman)
    install_postman "$archive"

    # Store ETag for next run
    save_etag

    # Verify
    local new_version
    new_version=$(get_current_version)
    log "=== Done: $current_version → $new_version ==="
    notify "normal" "Postman Updated" "$current_version → $new_version"
}

main "$@"
