# Postman Linux Updater

Automatic updater for [Postman](https://www.postman.com/) on Linux. Keeps your installation up to date — just add it to your startup scripts. Also works as a fresh installer if Postman isn't installed yet.

**No sudo required** — everything installs to `~/.local/`.

## Features

- **No root privileges needed** — installs to user-local directories
- **Automatic update detection** — uses HTTP ETag headers to check for new versions without downloading
- **Fresh install support** — installs Postman from scratch if not present
- **Specific version install** — install any Postman version by number
- **Skip versions** — ignore specific versions via `--ignore` or the `ignored_versions` config file
- **Uninstall** — clean removal with `--uninstall`
- **Desktop notifications** — system notifications for update status
- **Safe updates** — backs up current installation, automatic rollback on failure
- **Internet check** — verifies connectivity with retry logic
- **Startup-friendly** — designed to run silently at boot
- **Logging** — all actions logged to `~/.local/share/postman-updater/updater.log`

## Requirements

- Linux x64
- `curl`, `tar`, `ping`
- `notify-send` (pre-installed on GNOME/KDE/Cinnamon)
- `~/.local/bin` in your `PATH` (default on most modern distros)

## Installation

```bash
git clone https://github.com/YOUR_USER/postman-updater.git
cd postman-updater
./install.sh
```

### Manual install

```bash
mkdir -p ~/.local/bin
cp update-postman.sh ~/.local/bin/update-postman
chmod +x ~/.local/bin/update-postman
```

### Add to startup (optional)

```bash
(sleep 60 && update-postman) &
```

Or `~/.config/autostart/postman-updater.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Postman Updater
Exec=bash -c "sleep 60 && update-postman"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
```

## Usage

```bash
update-postman                    # auto-update to latest
update-postman --force            # force reinstall latest
update-postman --version 11.20.0  # install specific version
update-postman --ignore 11.20.0   # add version to ignore list
update-postman --quiet            # skip "up to date" notification
update-postman --uninstall        # remove Postman
```

| Option | Description |
|---|---|
| *(none)* | Check ETag, install if new version available |
| `--force` | Skip check and reinstall |
| `--version X.Y.Z` | Install specific version (implies `--force`) |
| `--ignore X.Y.Z` | Add version to ignore list and exit |
| `--unignore X.Y.Z` | Remove version from ignore list and exit |
| `--list-ignored` | Show all ignored versions and exit |
| `--quiet` | Skip "up to date" notification (updates/errors still notify) |
| `--uninstall` | Remove Postman and all related files |

### Ignoring versions

To skip a specific version (e.g. wait for the next one):

```bash
update-postman --ignore 11.20.0
```

You can also edit the ignore list directly — one version per line:

```bash
nano ~/.local/share/postman-updater/ignored_versions
```

When a new version is detected and downloaded but found to be ignored, the ETag is saved so the archive isn't re-downloaded on subsequent runs. Using `--version X.Y.Z` always installs regardless of the ignore list.

## How it works

1. **Internet check** — pings `1.1.1.1` or curls `dl.pstmn.io` (3 retries with backoff)
2. **ETag comparison** — compares HTTP ETag from server with stored value
3. **Download** — downloads `.tar.gz` from Postman CDN
4. **Backup** — moves current installation to `~/.local/opt/Postman.backup-YYYYMMDD-HHMMSS`
5. **Install** — extracts to `~/.local/opt/Postman`, creates symlink at `~/.local/bin/postman`
6. **Desktop entry** — creates `~/.local/share/applications/postman.desktop`
7. **Cleanup** — removes old backups (keeps 1), saves new ETag
8. **Notify** — desktop notification with result

## Files

| Path | Description |
|---|---|
| `~/.local/bin/update-postman` | Updater script |
| `~/.local/bin/postman` | Symlink to Postman binary |
| `~/.local/opt/Postman/` | Installation directory |
| `~/.local/share/applications/postman.desktop` | Desktop entry |
| `~/.local/share/postman-updater/updater.log` | Log file |
| `~/.local/share/postman-updater/etag` | Stored ETag |
| `~/.local/share/postman-updater/ignored_versions` | Ignored versions (one per line) |

## Uninstall

```bash
update-postman --uninstall
rm ~/.local/bin/update-postman
```

## License

MIT
