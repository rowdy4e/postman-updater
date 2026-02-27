# Postman Linux Updater

Automatic updater for [Postman](https://www.postman.com/) on Linux. Keeps your installation up to date with zero effort — just add it to your startup scripts.

## Features

- **Automatic update detection** — uses HTTP ETag headers to check for new versions without downloading anything
- **Specific version install** — install any Postman version by number
- **Desktop notifications** — shows system notifications for update status
- **Safe updates** — backs up current installation before updating, with automatic rollback on failure
- **Internet check** — verifies connectivity with retry logic before attempting download
- **Startup-friendly** — designed to run silently at boot with a delay
- **Logging** — all actions logged to `~/.postman-updater.log`

## Requirements

- Linux x64
- `curl`, `tar`, `ping`
- `notify-send` (usually pre-installed on GNOME/KDE/Cinnamon desktops)
- `sudo` access to `/opt/Postman`

## Installation

### 1. Install the script

```bash
sudo cp update-postman.sh /usr/local/bin/update-postman
sudo chmod +x /usr/local/bin/update-postman
```

### 2. Configure passwordless sudo (optional, recommended for automation)

Create `/etc/sudoers.d/postman-updater`:

```bash
sudo visudo -f /etc/sudoers.d/postman-updater
```

Add the following (replace `your_username` with your actual username):

```
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman /opt/Postman.backup-*
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman.backup-* /opt/Postman
your_username ALL=(ALL) NOPASSWD: /bin/tar -xzf * -C /opt/
your_username ALL=(ALL) NOPASSWD: /bin/ln -sf /opt/Postman/Postman /usr/bin/postman
your_username ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Postman.backup-*
```

### 3. Add to startup (optional)

Add to your startup scripts or `.bashrc`/`.profile`:

```bash
# Update Postman 60 seconds after login
(sleep 60 && update-postman) &
```

Or create a desktop autostart entry at `~/.config/autostart/postman-updater.desktop`:

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
# Check for updates and install if available
update-postman

# Force reinstall latest version
update-postman --force

# Install a specific version
update-postman --version 11.20.0

# Combine flags
update-postman --force --version 11.72.9
```

### Options

| Option | Description |
|---|---|
| *(no options)* | Check for updates using ETag comparison, install if new version available |
| `--force` | Skip ETag check and reinstall (useful if installation is corrupted) |
| `--version X.Y.Z` | Install a specific Postman version (implies `--force`) |

## How it works

1. **Internet check** — pings `1.1.1.1` or curls `dl.pstmn.io` (3 retries with backoff)
2. **ETag comparison** — fetches HTTP headers from `dl.pstmn.io` and compares the ETag with the stored value in `~/.postman-updater.etag`
3. **Download** — downloads the latest (or specified) `.tar.gz` from Postman's CDN
4. **Backup** — moves current `/opt/Postman` to `/opt/Postman.backup-YYYYMMDD-HHMMSS`
5. **Install** — extracts the archive to `/opt/` and creates symlink at `/usr/bin/postman`
6. **Cleanup** — removes old backups (keeps 1), saves new ETag
7. **Notify** — sends desktop notification with the result

## Files

| Path | Description |
|---|---|
| `/usr/local/bin/update-postman` | The updater script |
| `~/.postman-updater.log` | Log file |
| `~/.postman-updater.etag` | Stored ETag for update detection |
| `/opt/Postman` | Postman installation directory |
| `/opt/Postman.backup-*` | Backup of previous installation |

## Uninstall

```bash
sudo rm /usr/local/bin/update-postman
sudo rm /etc/sudoers.d/postman-updater
rm ~/.postman-updater.log ~/.postman-updater.etag
```

## License

MIT
