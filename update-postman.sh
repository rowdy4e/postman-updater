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
IGNORED_VERSIONS_FILE="$DATA_DIR/ignored_versions"
VERSION_HISTORY_FILE="$DATA_DIR/version_history"
POSTMAN_PKG="$POSTMAN_DIR/app/resources/app/package.json"

BASE_URL="https://dl.pstmn.io/download"
DOWNLOAD_URL="$BASE_URL/latest/linux_64"
CHANGELOG_URL="https://dl.pstmn.io/changelog?channel=stable&platform=linux&arch=64"
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
        grep -oP '"version"\s*:\s*"\K[^"]+' "$POSTMAN_PKG" | head -1
    else
        echo "0.0.0"
    fi
}

is_version_ignored() {
    local ver="$1"
    [[ -f "$IGNORED_VERSIONS_FILE" ]] && grep -qxF "$ver" "$IGNORED_VERSIONS_FILE"
}

record_version() {
    local ver="$1"
    [[ -z "$ver" || "$ver" == "0.0.0" ]] && return
    local tmp
    tmp=$(mktemp)
    { echo "$ver"; grep -vxF "$ver" "$VERSION_HISTORY_FILE" 2>/dev/null || true; } | head -20 > "$tmp"
    mv "$tmp" "$VERSION_HISTORY_FILE"
}

# --- TUI multi-select (arrow keys + space to toggle) ---

tui_multiselect() {
    local prompt="$1" prechecked="$2"
    shift 2
    local -a items=("$@")
    local count=${#items[@]}
    [[ $count -eq 0 ]] && return 1

    local cursor=0
    local -a checked=()
    for ((i=0; i<count; i++)); do checked+=("0"); done
    for idx in $prechecked; do
        (( idx >= 0 && idx < count )) && checked[$idx]=1
    done

    local max_vis
    max_vis=$(( $(tput lines 2>/dev/tty || echo 20) - 6 ))
    (( max_vis > count )) && max_vis=$count
    (( max_vis < 3 )) && max_vis=3
    local offset=0

    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)
    trap 'printf "\e[?25h" >/dev/tty 2>/dev/null; stty "'"$saved_tty"'" </dev/tty 2>/dev/null; exit 130' INT
    printf '\e[?25l' >/dev/tty

    # Reserve space, move back up, save position
    local total=$((max_vis + 4))
    for ((i=0; i<total; i++)); do printf '\n' >/dev/tty; done
    printf '\e[%dA' "$total" >/dev/tty
    printf '\e7' >/dev/tty

    _tui_draw() {
        printf '\e8\e[J' >/dev/tty
        printf '  \e[1;36m%s\e[0m\n\n' "$prompt" >/dev/tty

        (( cursor < offset )) && offset=$cursor
        (( cursor >= offset + max_vis )) && offset=$((cursor - max_vis + 1))

        for ((i=offset; i < offset + max_vis && i < count; i++)); do
            local mark="\e[90m◻\e[0m" pfx="  " style=""
            (( checked[i] )) && mark="\e[32m◼\e[0m"
            if (( i == cursor )); then
                pfx="\e[32m❯\e[0m" style="\e[1m"
            fi
            printf '  %b %b %b%b\e[0m\n' "$pfx" "$mark" "$style" "${items[$i]}" >/dev/tty
        done

        printf '\n  \e[90m↑↓ navigate · space select · enter confirm · q cancel\e[0m' >/dev/tty
    }

    _tui_draw

    while true; do
        local key
        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\e')
                local seq
                IFS= read -rsn2 -t 0.1 seq </dev/tty
                case "$seq" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < count - 1 )) && (( cursor++ )) ;;
                esac
                _tui_draw
                ;;
            ' ')
                checked[$cursor]=$(( 1 - checked[cursor] ))
                _tui_draw
                ;;
            ''|$'\r')
                break
                ;;
            q)
                printf '\e[?25h' >/dev/tty
                stty "$saved_tty" </dev/tty 2>/dev/null
                trap - INT
                printf '\n\n  \e[33mCancelled\e[0m\n' >/dev/tty
                return 1
                ;;
        esac
    done

    printf '\e[?25h' >/dev/tty
    stty "$saved_tty" </dev/tty 2>/dev/null
    trap - INT
    printf '\n\n' >/dev/tty

    local any=false
    for ((i=0; i<count; i++)); do
        if (( checked[i] )); then
            echo "${items[$i]}"
            any=true
        fi
    done

    if ! $any; then
        return 2
    fi
}

tui_singleselect() {
    local prompt="$1"
    shift
    local -a items=("$@")
    local count=${#items[@]}
    [[ $count -eq 0 ]] && return 1

    local cursor=0
    local max_vis
    max_vis=$(( $(tput lines 2>/dev/tty || echo 20) - 6 ))
    (( max_vis > count )) && max_vis=$count
    (( max_vis < 3 )) && max_vis=3
    local offset=0

    local saved_tty
    saved_tty=$(stty -g </dev/tty 2>/dev/null)
    trap 'printf "\e[?25h" >/dev/tty 2>/dev/null; stty "'"$saved_tty"'" </dev/tty 2>/dev/null; exit 130' INT
    printf '\e[?25l' >/dev/tty

    local total=$((max_vis + 4))
    for ((i=0; i<total; i++)); do printf '\n' >/dev/tty; done
    printf '\e[%dA' "$total" >/dev/tty
    printf '\e7' >/dev/tty

    _tui_s_draw() {
        printf '\e8\e[J' >/dev/tty
        printf '  \e[1;36m%s\e[0m\n\n' "$prompt" >/dev/tty

        (( cursor < offset )) && offset=$cursor
        (( cursor >= offset + max_vis )) && offset=$((cursor - max_vis + 1))

        for ((i=offset; i < offset + max_vis && i < count; i++)); do
            if (( i == cursor )); then
                printf '  \e[32m❯\e[0m \e[1m%b\e[0m\n' "${items[$i]}" >/dev/tty
            else
                printf '    %b\n' "${items[$i]}" >/dev/tty
            fi
        done

        printf '\n  \e[90m↑↓ navigate · enter select · q cancel\e[0m' >/dev/tty
    }

    _tui_s_draw

    while true; do
        local key
        IFS= read -rsn1 key </dev/tty
        case "$key" in
            $'\e')
                local seq
                IFS= read -rsn2 -t 0.1 seq </dev/tty
                case "$seq" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < count - 1 )) && (( cursor++ )) ;;
                esac
                _tui_s_draw
                ;;
            ''|$'\r')
                break
                ;;
            q)
                printf '\e[?25h' >/dev/tty
                stty "$saved_tty" </dev/tty 2>/dev/null
                trap - INT
                printf '\n\n  \e[33mCancelled\e[0m\n' >/dev/tty
                return 1
                ;;
        esac
    done

    printf '\e[?25h' >/dev/tty
    stty "$saved_tty" </dev/tty 2>/dev/null
    trap - INT
    printf '\n\n' >/dev/tty

    echo "${items[$cursor]}"
}

# --- Interactive ignore/unignore/version ---

interactive_ignore() {
    echo "Fetching available versions..."
    local versions=()

    local changelog
    changelog=$(curl -sL --connect-timeout 10 --max-time 15 "$CHANGELOG_URL" 2>/dev/null)
    if [[ -n "$changelog" ]]; then
        mapfile -t versions < <(echo "$changelog" | grep -oP '"name"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -20)
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        echo "Could not fetch version list. Try: update-postman --ignore X.Y.Z"
        return 1
    fi

    # Build labels & pre-check already-ignored
    local labels=() prechecked="" was_ignored=()
    for ((i=0; i<${#versions[@]}; i++)); do
        if grep -qxF "${versions[$i]}" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
            labels+=("${versions[$i]}  \e[90m(ignored)\e[0m")
            prechecked+="$i "
            was_ignored+=("${versions[$i]}")
        else
            labels+=("${versions[$i]}")
        fi
    done

    local selected rc=0
    selected=$(tui_multiselect "Select versions to ignore (uncheck to unignore):" "$prechecked" "${labels[@]}") || rc=$?
    [[ $rc -eq 1 ]] && return 0

    # Parse selected versions into an array
    local -a selected_arr=()
    if [[ -n "$selected" ]]; then
        while IFS= read -r item; do
            selected_arr+=("${item%%  *}")
        done <<< "$selected"
    fi

    local changes=0

    # Add newly checked versions
    for ver in "${selected_arr[@]}"; do
        if ! grep -qxF "$ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
            echo "$ver" >> "$IGNORED_VERSIONS_FILE"
            printf '  \e[32m✓\e[0m %s added to ignore list\n' "$ver"
            changes=$((changes + 1))
        fi
    done

    # Remove unchecked versions that were previously ignored
    for ver in "${was_ignored[@]}"; do
        local still_checked=false
        for s in "${selected_arr[@]}"; do
            [[ "$s" == "$ver" ]] && { still_checked=true; break; }
        done
        if ! $still_checked; then
            sed -i "/^$(sed 's/[.[\*^$]/\\&/g' <<< "$ver")$/d" "$IGNORED_VERSIONS_FILE"
            printf '  \e[32m✓\e[0m %s removed from ignore list\n' "$ver"
            changes=$((changes + 1))
        fi
    done

    if [[ $changes -eq 0 ]]; then
        echo "  No changes"
    fi
}

interactive_unignore() {
    if [[ ! -f "$IGNORED_VERSIONS_FILE" ]] || [[ ! -s "$IGNORED_VERSIONS_FILE" ]]; then
        echo "No ignored versions"
        return 0
    fi

    local versions=()
    mapfile -t versions < "$IGNORED_VERSIONS_FILE"

    local selected
    selected=$(tui_multiselect "Which versions do you want to unignore?" "" "${versions[@]}") || return 0

    while IFS= read -r ver; do
        sed -i "/^$(sed 's/[.[\*^$]/\\&/g' <<< "$ver")$/d" "$IGNORED_VERSIONS_FILE"
        printf '  \e[32m✓\e[0m %s removed from ignore list\n' "$ver"
    done <<< "$selected"
}

interactive_version() {
    echo "Fetching available versions..." >&2
    local versions=()

    local changelog
    changelog=$(curl -sL --connect-timeout 10 --max-time 15 "$CHANGELOG_URL" 2>/dev/null)
    if [[ -n "$changelog" ]]; then
        mapfile -t versions < <(echo "$changelog" | grep -oP '"name"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -20)
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        echo "Could not fetch version list. Try: update-postman --version X.Y.Z" >&2
        return 1
    fi

    # Mark installed version
    local installed
    installed=$(get_current_version)
    local labels=()
    for v in "${versions[@]}"; do
        if [[ "$v" == "$installed" ]]; then
            labels+=("$v  \e[90m(installed)\e[0m")
        else
            labels+=("$v")
        fi
    done

    local selected
    selected=$(tui_singleselect "Which version do you want to install?" "${labels[@]}") || return 1
    echo "${selected%%  *}"
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

    local force=false target_version="" quiet=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)     force=true; log "Force mode" ;;
            --version)
                if [[ -n "${2:-}" ]]; then
                    target_version="$2"; shift
                else
                    target_version=$(interactive_version) || exit 0
                fi
                ;;
            --quiet)     quiet=true ;;
            --uninstall) uninstall_postman; exit 0 ;;
            --list-ignored)
                if [[ ! -f "$IGNORED_VERSIONS_FILE" ]] || [[ ! -s "$IGNORED_VERSIONS_FILE" ]]; then
                    echo "No ignored versions"
                else
                    echo "Ignored versions:"
                    cat "$IGNORED_VERSIONS_FILE"
                fi
                exit 0
                ;;
            --ignore)
                if [[ -n "${2:-}" ]]; then
                    local ignore_ver="$2"
                    shift
                    if grep -qxF "$ignore_ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
                        echo "Version $ignore_ver is already in ignore list"
                    else
                        echo "$ignore_ver" >> "$IGNORED_VERSIONS_FILE"
                        echo "Version $ignore_ver added to ignore list"
                    fi
                else
                    interactive_ignore
                fi
                exit 0
                ;;
            --unignore)
                if [[ -n "${2:-}" ]]; then
                    local unignore_ver="$2"
                    shift
                    if grep -qxF "$unignore_ver" "$IGNORED_VERSIONS_FILE" 2>/dev/null; then
                        sed -i "/^$(sed 's/[.[\*^$]/\\&/g' <<< "$unignore_ver")$/d" "$IGNORED_VERSIONS_FILE"
                        echo "Version $unignore_ver removed from ignore list"
                    else
                        echo "Version $unignore_ver is not in ignore list"
                    fi
                else
                    interactive_unignore
                fi
                exit 0
                ;;
            *)           die "Unknown option: $1\nUsage: update-postman [--force] [--version X.Y.Z] [--quiet] [--uninstall] [--ignore X.Y.Z] [--unignore X.Y.Z] [--list-ignored]" ;;
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
    record_version "$current_version"

    # Fetch latest version from changelog API (before downloading)
    local latest_version=""
    if [[ -z "$target_version" ]]; then
        local changelog_json
        changelog_json=$(curl -sL --connect-timeout 10 --max-time 15 "$CHANGELOG_URL" 2>/dev/null)
        if [[ -n "$changelog_json" ]]; then
            latest_version=$(echo "$changelog_json" | grep -oP '"name"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            [[ -n "$latest_version" ]] && record_version "$latest_version"
            log "Latest available: ${latest_version:-unknown}"
        fi
        # Use version-specific URL when we know the latest version
        if [[ -n "$latest_version" ]]; then
            DOWNLOAD_URL="$BASE_URL/version/$latest_version/linux_64"
        fi
    fi

    # Skip ignored versions before downloading (unless --version was explicitly specified)
    if [[ -z "$target_version" && -n "$latest_version" ]] && is_version_ignored "$latest_version"; then
        log "Version $latest_version is in ignore list, skipping"
        $quiet || notify "low" "Postman Update Skipped" "Version $latest_version is ignored — edit ~/.local/share/postman-updater/ignored_versions to change this"
        exit 0
    fi

    # Check if update is needed
    if ! $force; then
        if [[ -n "$latest_version" && "$current_version" == "$latest_version" ]]; then
            log "Already up to date (version match: $current_version)"
            $quiet || notify "low" "Postman Up to Date" "Version $current_version — no update available"
            exit 0
        fi
        if [[ -z "$latest_version" ]] && ! needs_update; then
            log "Already up to date (ETag match)"
            $quiet || notify "low" "Postman Up to Date" "Version $current_version — no update available"
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
