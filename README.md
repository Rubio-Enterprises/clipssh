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

### Interactive capture mode (macOS)

```bash
clipssh --capture
```

Shows a region-select crosshair, captures the selected area, and uploads it — no need to screenshot to the clipboard first. Press `Esc` to cancel.

Best used via a global hotkey. See [Hotkey setup with skhd.zig](#hotkey-setup-with-skhdzig) below.

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

## Hotkey setup with skhd.zig

The most frictionless way to use `clipssh --capture` is to bind it to a global hotkey, so you never have to touch a terminal. The recommended hotkey daemon is [`skhd.zig`](https://github.com/jackielii/skhd.zig), the actively-maintained Zig rewrite of the original `skhd`.

### 1. Install skhd.zig

```bash
brew install jackielii/tap/skhd-zig
```

### 2. Configure your hotkeys

Create or edit `~/.config/skhd/skhdrc` and add:

```
# clipssh: fused screenshot + upload
cmd + shift - 5 : /opt/homebrew/bin/clipssh --capture

# clipssh: upload whatever's on the clipboard (retry / non-screenshot sources)
cmd + shift - u : /opt/homebrew/bin/clipssh
```

**Important: use the absolute path to clipssh** in your `skhdrc`, not just `clipssh`. skhd runs as a launchd agent and its `PATH` may not include Homebrew directories. Check your actual path with:

```bash
which clipssh
```

- Apple Silicon (M1/M2/M3/M4): usually `/opt/homebrew/bin/clipssh`
- Intel: usually `/usr/local/bin/clipssh`

### 3. Start skhd as a launchd service

```bash
skhd --install-service
skhd --start-service
```

skhd now starts at login and watches your config file — edits to `skhdrc` take effect immediately without a restart.

### 4. Grant permissions

skhd needs **two separate macOS permission grants** the first time you use it with `clipssh --capture`:

**a) Accessibility (required by skhd to listen for global hotkeys)**

On first run, skhd will prompt you. Grant it in System Settings → Privacy & Security → Accessibility.

**b) Screen Recording (required by `screencapture` to capture pixels)**

This one is trickier. The permission prompt may name `screencapture`, your shell (`zsh` or `bash`), or sometimes not appear at all, depending on your macOS version. The most reliable way to settle it is:

1. **Before binding the hotkey, run `clipssh --capture` once from a terminal.** This gives macOS a clean attribution chain via Terminal.app and usually produces a proper permission prompt.
2. If a prompt appears, click "Allow".
3. If no prompt appears and the command fails with "Screen Recording permission is required", follow the manual-add instructions printed on stderr.

**Manual-add procedure** (for the Screen Recording permission):

1. Open System Settings → Privacy & Security → **Screen & System Audio Recording**
2. Click the **+** button
3. Press **Cmd+Shift+G** in the file picker
4. Type `/usr/sbin/screencapture` and press Enter
5. Click **Add**
6. You may also need to repeat the process for your shell (run `echo $SHELL` to find its path)

After permission is granted, `clipssh --capture` is ready to use via the hotkey.

### Changing the hotkey

Just edit `~/.config/skhd/skhdrc` and save. skhd reloads automatically. Pick any combination that doesn't conflict with an existing macOS shortcut.

### Advanced: taking over `Cmd+Shift+Ctrl+4`

If (like the clipssh author) you only take screenshots for remote SSH sessions, you can disable the built-in macOS shortcut and bind clipssh to it instead:

1. System Settings → Keyboard → Keyboard Shortcuts → Screenshots
2. Uncheck "Copy picture of selected area to the clipboard" (or reassign it)
3. In `skhdrc`:

```
cmd + shift + ctrl - 4 : /opt/homebrew/bin/clipssh --capture
cmd + shift - u        : /opt/homebrew/bin/clipssh
```

### Troubleshooting

**"All my uploads are black or blank images"** — Screen Recording permission is silently denied. `screencapture` is writing a zero-content image without prompting. Delete the preflight marker and re-run:

```bash
rm ~/.config/clipssh/.preflight-ok
clipssh --capture
```

The preflight check should fail and print actionable instructions. Follow the manual-add procedure above.

**"Nothing happens when I press the hotkey"** — Either skhd isn't running, or it lacks Accessibility permission. Check:

```bash
skhd --start-service        # ensure the launchd agent is running
# Then check System Settings → Privacy & Security → Accessibility
```

**"I see a permission prompt every week or two"** — This is a macOS 15 (Sequoia) feature, not a clipssh behavior. Apple added periodic reminders for Screen Recording consent. Just click "Allow" when it appears.

**"It doesn't work in fullscreen games / video players"** — Certain fullscreen apps intercept or hide the `screencapture` crosshair overlay. This is a macOS limitation, not a clipssh bug. Workaround: temporarily exit fullscreen before capturing.

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

## License

MIT
