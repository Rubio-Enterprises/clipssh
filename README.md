# clipssh

Send clipboard screenshots to remote SSH hosts. Perfect for pasting images into terminal tools like Claude Code running over SSH.

## The Problem

When using Claude Code (or similar tools) over SSH, you can't paste images from your local clipboard. The remote terminal has no access to your local display server.

## The Solution

`clipssh` extracts the screenshot from your local clipboard, uploads it to the remote server, and copies the file path to your clipboard. Just paste the path into Claude Code and it auto-attaches the image.

## Install

```bash
# macOS via Homebrew
brew install strubio-ray/tap/clipssh
```

## Usage

```bash
# Take a screenshot to clipboard
# macOS: Cmd+Shift+Ctrl+4 (select area, copies to clipboard)

# Upload to remote host
clipssh user@myserver

# Paste the path into Claude Code on the remote
# The image will auto-attach
```

## Configuration

Configure defaults with `clipssh config`:

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

Environment variables override the config file for per-session use:

```bash
CLIPSSH_HOST=other@host clipssh
CLIPSSH_REMOTE_DIR=/custom/path clipssh
```

**Precedence:** CLI arguments > environment variables > config file > defaults.

## Requirements

**macOS:**
- `pngpaste` - Install with `brew install pngpaste`
- SSH access to remote host

**Linux:**
- `xclip` (X11) or `wl-clipboard` (Wayland)
- SSH access to remote host

## How It Works

1. Extracts PNG image from your local clipboard
2. Uploads to `<remote-dir>/clipboard-<timestamp>.png` on remote host via SSH (default: `/tmp`)
3. Copies the remote path to your clipboard
4. You paste the path into Claude Code, which reads and displays the image

## License

MIT
