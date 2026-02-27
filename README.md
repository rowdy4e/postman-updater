# Postman Linux Updater

Automatic updater for [Postman](https://www.postman.com/) on Linux. Keeps your installation up to date — just add it to your startup scripts. Also works as a fresh installer if Postman isn't installed yet.

## Features

- **Automatic update detection** — uses HTTP ETag headers to check for new versions without downloading
- **Fresh install support** — installs Postman from scratch if not present
- **Specific version install** — install any Postman version by number
- **Desktop notifications** — system notifications for update status
- **Safe updates** — backs up current installation, automatic rollback on failure
- **Internet check** — verifies connectivity with retry logic
- **Startup-friendly** — designed to run silently at boot
- **Logging** — all actions logged to `~/.postman-updater.log`

## Requirements

- Linux x64
- `curl`, `tar`, `ping`
- `notify-send` (pre-installed on GNOME/KDE/Cinnamon)
- `sudo` access

## Installation

```bash
git clone https://github.com/YOUR_USER/postman-updater.git
cd postman-updater
sudo ./install.sh
```

### Manual install

```bash
sudo cp update-postman.sh /usr/local/bin/update-postman
sudo chmod +x /usr/local/bin/update-postman
```

### Passwordless sudo (recommended for automation)

```bash
sudo visudo -f /etc/sudoers.d/postman-updater
```

```
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman /opt/Postman.backup-*
your_username ALL=(ALL) NOPASSWD: /bin/mv /opt/Postman.backup-* /opt/Postman
your_username ALL=(ALL) NOPASSWD: /bin/tar -xzf * -C /opt/
your_username ALL=(ALL) NOPASSWD: /bin/ln -sf /opt/Postman/Postman /usr/bin/postman
your_username ALL=(ALL) NOPASSWD: /bin/rm -rf /opt/Postman.backup-*
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
```

| Option | Description |
|---|---|
| *(none)* | Check ETag, install if new version available |
| `--force` | Skip check and reinstall |
| `--version X.Y.Z` | Install specific version (implies `--force`) |

## How it works

1. **Internet check** — pings `1.1.1.1` or curls `dl.pstmn.io` (3 retries with backoff)
2. **ETag comparison** — compares HTTP ETag from server with stored value in `~/.postman-updater.etag`
3. **Download** — downloads `.tar.gz` from Postman CDN
4. **Backup** — moves `/opt/Postman` to `/opt/Postman.backup-YYYYMMDD-HHMMSS`
5. **Install** — extracts to `/opt/`, creates symlink at `/usr/bin/postman`
6. **Cleanup** — removes old backups (keeps 1), saves new ETag
7. **Notify** — desktop notification with result

## Files

| Path | Description |
|---|---|
| `/usr/local/bin/update-postman` | Updater script |
| `~/.postman-updater.log` | Log file |
| `~/.postman-updater.etag` | Stored ETag |
| `/opt/Postman` | Installation directory |

## Uninstall

```bash
sudo rm /usr/local/bin/update-postman /etc/sudoers.d/postman-updater
rm ~/.postman-updater.log ~/.postman-updater.etag
```

## License

MIT
