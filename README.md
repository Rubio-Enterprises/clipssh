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

### Supported Clipboard Sources (macOS)

- **Screenshot to clipboard** — `Cmd+Shift+Ctrl+4` (select area)
- **Copy file in Finder** — right-click an image file → Copy
- **Copy file path** — right-click an image file → Copy Path

All three methods are detected automatically.

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
