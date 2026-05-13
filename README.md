# clipssh

Send clipboard images to remote SSH hosts. Perfect for pasting images into terminal tools like Claude Code running over SSH.

## The Problem

When using Claude Code (or similar tools) over SSH, you can't paste images from your local clipboard. The remote terminal has no access to your local display server.

## The Solution

`clipssh` extracts the image from your local clipboard, uploads it to the remote server, and copies the file path to your clipboard. Just paste the path into Claude Code and it auto-attaches the image.

## Install

```bash
# macOS via Homebrew
brew install strubio-ray/tap/clipssh
```

## Usage

```bash
# Upload a clipboard image to the remote host
clipssh user@myserver

# Paste the path into Claude Code on the remote
# The image will auto-attach
```

### Common flags

```bash
clipssh -p 2222 -i ~/.ssh/id_ed25519 user@server   # SSH options passed through
clipssh -f ~/Desktop/diagram.png user@server       # upload a specific file
clipssh -r ~/uploads user@server                   # one-shot remote dir override
clipssh --print-only user@server                   # print path; leave clipboard alone
clipssh --watch user@server                        # watch clipboard, upload on change
```

### Supported clipboard sources

| Source                                                  | macOS | Linux |
| ------------------------------------------------------- | :---: | :---: |
| Screenshot to clipboard (`Cmd+Shift+Ctrl+4` / `Print`)  |  yes  |  yes  |
| Copy file in Finder / Nautilus / Dolphin                |  yes  |  yes  |
| Copy file path as plain text                            |  yes  |  yes  |

All sources are detected automatically.

### Watch mode

`clipssh --watch` polls the clipboard at a configurable interval (default 2s)
and uploads any new image as soon as it appears — take a screenshot and the
remote path is already on your clipboard. Override the interval with
`--interval SECONDS`. Ctrl-C to stop.

## Configuration

First-time setup is interactive:

```bash
clipssh setup
```

Or configure directly:

```bash
# Set default host
clipssh config set host user@myserver

# Set custom remote directory (default: /tmp)
clipssh config set remote_dir ~/.vibetunnel/control/uploads

# Now just run:
clipssh

# View current settings
clipssh config list
```

Settings are stored in `~/.config/clipssh/config`.

> **Note on `/tmp`**: the default remote directory is `/tmp`, which some
> distros clear on reboot or periodically (e.g. `systemd-tmpfiles`). For
> images you want to keep, configure a durable directory:
> `clipssh config set remote_dir ~/.cache/clipssh`.

Environment variables override the config file for per-session use:

```bash
CLIPSSH_HOST=other@host clipssh
CLIPSSH_REMOTE_DIR=/custom/path clipssh
```

**Precedence:** CLI arguments > environment variables > config file > defaults.

## Hotkey integration

`clipssh` becomes much faster to use with a global hotkey — take a screenshot,
press a key, and the path is on your clipboard ready to paste.

**macOS (Raycast):** create a Script Command pointing at `clipssh --watch`,
or bind a Quicklink that runs `clipssh user@server`.

**macOS (Alfred):** add a Workflow → Hotkey Trigger → Run Script:
`/opt/homebrew/bin/clipssh user@server`.

**macOS (skhd):** in `~/.config/skhd/skhdrc`:

```text
cmd + shift + ctrl - v : /opt/homebrew/bin/clipssh user@server
```

**Linux (sxhkd / GNOME / KDE):** bind a key to `clipssh user@server`.

## Requirements

**macOS:**
- SSH access to remote host
- `clipssh-paste` (bundled with `brew install strubio-ray/tap/clipssh`)

**Linux:**
- `xclip` (X11) or `wl-clipboard` (Wayland)
- SSH access to remote host

## How It Works

1. Detects clipboard content: raw image data, copied file reference, or copied file path
2. Extracts and converts to PNG
3. Uploads to `<remote-dir>/<filename>.png` on remote host via SSH
4. Copies the remote path to your clipboard
5. You paste the path into Claude Code, which reads and displays the image

## Development

```bash
task setup   # installs Task, bats, shellcheck, jq, kcov (Linux + macOS)
task check   # exact pipeline CI runs: lint + tests + 80% coverage floor
```

See [tests/README.md](tests/README.md) for the layout of the test suite.

## License

MIT
