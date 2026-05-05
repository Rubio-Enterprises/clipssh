# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`clipssh` extracts an image from the local clipboard, uploads it to a remote SSH host, and copies the resulting remote path to the clipboard — primarily so images can be pasted into Claude Code running over SSH (which auto-attaches files from paths).

Distributed via Homebrew tap `Rubio-Enterprises/homebrew-tap`.

## Architecture

Two components that work together:

1. **`clipssh`** (bash script at repo root) — the user-facing CLI. Handles argument parsing, XDG config (`~/.config/clipssh/config`), clipboard-source detection dispatch, SSH upload, and clipboard writeback. Precedence for settings: CLI args > env vars (`CLIPSSH_HOST`, `CLIPSSH_REMOTE_DIR`) > config file > defaults.

2. **`clipssh-paste`** (`swift/ClipsshPaste.swift`) — macOS-only helper binary. Reads `NSPasteboard` and writes PNG bytes to stdout plus a "source line" to stderr. The bash script parses the last stderr line to learn how the image was obtained, which drives the remote filename:
   - `source:file:<path>` — Finder "Copy" (file reference on pasteboard)
   - `source:image` — raw image data (e.g. `Cmd+Shift+Ctrl+4` screenshot)
   - `source:path:<path>` — text path (Finder "Copy as Pathname")

   Detection order matters: file reference is checked **before** raw image data because Finder's Copy places both the file URL and the file's icon on the pasteboard simultaneously — we want the file, not the icon.

3. **Linux path** — uses `xclip` or `wl-paste` directly from the bash script; no Swift helper involved. Linux only supports raw image data, so remote files are always named `clipboard-<timestamp>.png`.

### Remote upload mechanism

The script pipes the PNG to `ssh "$HOST" "..."` and uses `eval echo` on the remote side to expand `~` in `REMOTE_DIR` before `mkdir -p` and `cat >`. The remote script echoes back the resolved absolute path, which is captured into `REMOTE_PATH` and copied to the local clipboard.

### Version injection

`VERSION="%%VERSION%%"` in the bash script is a placeholder replaced by the Homebrew formula at install time. Don't treat it as a literal version string.

## Build / Run

```bash
# Build the macOS helper (outputs to ../build/clipssh-paste by default)
cd swift && make

# Override output directory
make build BUILD_DIR=/some/path

# Clean
cd swift && make clean
```

The bash script `clipssh` is not "built" — it's installed directly. For local testing, run it in place:

```bash
PATH="$PWD/build:$PATH" ./clipssh user@host
```

There is no test suite and no lint configuration in this repo.

## Release Flow

Tagging `v*` triggers `.github/workflows/bump-homebrew.yml`, which uses `mislav/bump-homebrew-formula-action` to update `Rubio-Enterprises/homebrew-tap`'s `clipssh` formula with the new tarball URL. The Homebrew formula is responsible for substituting `%%VERSION%%` in the installed script and compiling `swift/ClipsshPaste.swift` as `clipssh-paste`.

## Conventions

- The two clipboard-image-extraction paths (macOS via `clipssh-paste`, Linux via `xclip`/`wl-paste`) must stay behavior-compatible: both produce a PNG on stdout and signal failure via non-zero exit. Keep the `$OSTYPE` branches in `clipssh` symmetric.
- When adding a new clipboard source on macOS, extend `ClipsshPaste.swift` with a new `try*()` function called in priority order, and emit a new `source:<kind>:...` line. Then add a matching `case` in the `SOURCE_LINE` switch in `clipssh` if the remote filename should differ.
- Error messages go through the `error()` / `exitWithError()` helpers so they land on stderr and set a non-zero exit.
