# Expanded Clipboard Input Methods

## Problem

clipssh currently only handles raw image data from the clipboard (via `pngpaste`), which works for `Cmd+Shift+Ctrl+4` screenshots. Two other common macOS clipboard operations fail:

1. **Right-click → Copy** on a file in Finder: puts a file reference on the clipboard, not raw image data. `pngpaste` doesn't find image data and errors.
2. **Right-click → Copy Path** in Finder: puts a text string on the clipboard. `pngpaste` fails silently or produces invalid output, resulting in a corrupted upload.

## Solution

Replace `pngpaste` with a custom Swift CLI tool (`clipssh-paste`) that uses `NSPasteboard` directly to detect and handle all three clipboard content types.

## Swift CLI Helper: `clipssh-paste`

A single-file Swift command-line tool that queries `NSPasteboard` and outputs image data to stdout.

### Detection Order

1. **Raw image data** — `public.png`, `public.tiff` pasteboard types → convert to PNG, write to stdout
2. **File references** — `NSFilenamesPboardType` / `public.file-url` → validate it's an image file, read from disk, write to stdout
3. **Text file path** — clipboard text that is a valid image file path → validate file exists and is an image, read from disk, write to stdout
4. **No match** — exit with code 1 and descriptive error to stderr

### Output Contract

- **stdout:** Raw PNG bytes (always PNG, converts other formats)
- **stderr:** Human-readable status/error messages, plus a `source:` line for the calling script
- **Exit code 0:** Success, stdout has image data
- **Exit code 1:** No usable image found
- **Exit code 2:** File found but not a valid image type

### Supported Image Extensions

`.png`, `.jpg`, `.jpeg`, `.gif`, `.tiff`, `.bmp`, `.webp`

### Stderr Source Line

The last line of stderr indicates which method was used:

- `source:image` — raw image data from clipboard
- `source:file:/path/to/original.png` — file reference from Finder Copy
- `source:path:/path/to/original.png` — text file path from Copy Path

### Error Cases

| Scenario | Exit Code | Stderr Message |
|----------|-----------|----------------|
| Raw image found | 0 | `source:image` |
| File reference found, valid image | 0 | `source:file:/path/to/file.png` |
| Text path found, valid image | 0 | `source:path:/path/to/file.png` |
| Clipboard is empty | 1 | `No content found in clipboard` |
| File reference, not an image | 2 | `Copied file is not a supported image type: /path/to/file.txt` |
| Text path, not an image | 2 | `Path is not a supported image type: /path/to/file.txt` |
| Text path, file doesn't exist | 1 | `File not found: /path/to/file.png` |
| File reference, file doesn't exist | 1 | `File not found: /path/to/file.png` |
| Image conversion to PNG fails | 1 | `Failed to convert image to PNG` |

## Integration with `clipssh` Script

### macOS Clipboard Extraction

Replace current `pngpaste` logic:

```bash
# Old
pngpaste "$TEMP_FILE"

# New
clipssh-paste > "$TEMP_FILE"
```

### Filename Logic

Parse the `source:` line from stderr:

- `source:image` → `clipboard-{timestamp}.png` (current behavior)
- `source:file:/path/to/Original Name.png` or `source:path:...` → `Original Name-{timestamp}.png`

### Error Messages

No more hardcoded "Take a screenshot first (Cmd+Shift+Ctrl+4)". The Swift helper provides specific errors that are passed through to the user via the existing `error()` function.

### Linux Unchanged

`xclip`/`wl-paste` logic remains as-is. This is a macOS-only enhancement.

### Dependency Check

Replace `command -v pngpaste` with `command -v clipssh-paste` and update the install guidance message.

## Build & Distribution

### Project Structure

```
clipssh/
├── clipssh                  # Main bash script (existing)
├── swift/
│   ├── ClipsshPaste.swift   # Single-file Swift CLI
│   └── Makefile             # Build target
└── ...
```

### Build

- Single Swift file compiled with `swiftc` — no Swift Package Manager needed
- Makefile target: `swiftc -O -o clipssh-paste swift/ClipsshPaste.swift`
- Pre-compiled universal binary (arm64 + x86_64 via `lipo`) in Homebrew bottle

### Homebrew Formula

- Remove `pngpaste` dependency
- Include `clipssh-paste` binary alongside `clipssh` script
- Both installed to the Homebrew bin path

### Removed

`install.sh` is removed. Homebrew is the sole distribution method.
