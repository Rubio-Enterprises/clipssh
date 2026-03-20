# Expanded Clipboard Input Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `pngpaste` with a custom Swift CLI tool (`clipssh-paste`) that handles raw image data, Finder file references, and text file paths from the macOS clipboard.

**Architecture:** A single-file Swift CLI (`clipssh-paste`) uses `NSPasteboard` to detect clipboard content type, extract/convert image data to PNG, and output it to stdout with a structured `source:` line on stderr. The main `clipssh` bash script is updated to call this tool instead of `pngpaste`, parse the source line for filename logic, and relay errors.

**Tech Stack:** Swift (compiled with `swiftc`), AppKit (`NSPasteboard`, `NSImage`, `NSBitmapImageRep`), Bash

**Spec:** `docs/superpowers/specs/2026-03-20-clipboard-input-methods-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `swift/ClipsshPaste.swift` | Swift CLI: clipboard detection, image extraction, PNG conversion, stdout/stderr output |
| Create | `swift/Makefile` | Build target for compiling `clipssh-paste` |
| Modify | `clipssh` (lines 154-190) | Replace `pngpaste` with `clipssh-paste`, add stderr capture, filename logic |
| Modify | `clipssh` (lines 196-202) | Update upload section for dynamic filenames |
| Delete | `install.sh` | No longer needed; Homebrew is sole distribution |
| Modify | `README.md` | Update requirements, usage, and how-it-works sections |

---

### Task 1: Create the Swift CLI — Argument Parsing and Empty Clipboard

**Files:**
- Create: `swift/ClipsshPaste.swift`

This task sets up the Swift file with `--help`, `--version`, argument parsing, and the empty-clipboard detection path.

- [ ] **Step 1: Create `swift/ClipsshPaste.swift` with argument parsing and empty clipboard check**

```swift
import AppKit
import Foundation

let version = "1.0.0"

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func exitWithError(_ message: String, code: Int32 = 1) -> Never {
    printError(message)
    exit(code)
}

// Argument parsing
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    Usage: clipssh-paste

    Extract image from macOS clipboard and write PNG data to stdout.

    Detection order:
      1. Raw image data (screenshot to clipboard)
      2. File reference (Finder right-click → Copy)
      3. Text file path (Finder right-click → Copy Path)

    Output:
      stdout: PNG image data
      stderr: source line (last line) indicating detection method

    Exit codes:
      0  Success
      1  No usable image found
      2  File found but not a supported image type

    Options:
      -h, --help     Show this help
      -v, --version  Show version
    """)
    exit(0)
}

if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print("clipssh-paste \(version)")
    exit(0)
}

let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"])

let pasteboard = NSPasteboard.general

// Check if pasteboard has any content at all
if pasteboard.pasteboardItems == nil || pasteboard.pasteboardItems?.isEmpty == true {
    exitWithError("No content found in clipboard")
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /vm-clipssh && swiftc -O -o clipssh-paste swift/ClipsshPaste.swift 2>&1`

Note: This will only compile on macOS (requires AppKit). On Linux, verify the file is syntactically correct by checking it exists and has the expected structure. The actual compilation and testing must happen on a macOS machine.

- [ ] **Step 3: Commit**

```bash
git add swift/ClipsshPaste.swift
git commit -m "feat: scaffold clipssh-paste with argument parsing and empty clipboard check"
```

---

### Task 2: Raw Image Data Detection

**Files:**
- Modify: `swift/ClipsshPaste.swift`

Add the first detection path: raw image data from the pasteboard (`public.png`, `public.tiff`).

- [ ] **Step 1: Add raw image data detection after the empty clipboard check**

Append to `swift/ClipsshPaste.swift`, before any exit:

```swift
// --- Detection 1: Raw image data ---
func tryRawImageData() -> Bool {
    // Check for PNG data first, then TIFF (macOS screenshots are often TIFF internally)
    let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
    ]

    for type in imageTypes {
        if let data = pasteboard.data(forType: type) {
            guard let imageRep = NSBitmapImageRep(data: data),
                  let pngData = imageRep.representation(using: .png, properties: [:]) else {
                continue
            }
            FileHandle.standardOutput.write(pngData)
            printError("source:image")
            exit(0)
        }
    }
    return false
}

let _ = tryRawImageData()
```

- [ ] **Step 2: Commit**

```bash
git add swift/ClipsshPaste.swift
git commit -m "feat: add raw image data detection to clipssh-paste"
```

---

### Task 3: File Reference Detection

**Files:**
- Modify: `swift/ClipsshPaste.swift`

Add the second detection path: file references from Finder Copy (`public.file-url`).

- [ ] **Step 1: Add helper function to validate image extension and convert file to PNG**

Insert after `tryRawImageData()` function:

```swift
func isImageExtension(_ ext: String) -> Bool {
    return supportedExtensions.contains(ext.lowercased())
}

func fileToStdoutPNG(path: String, sourcePrefix: String) -> Never {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url) else {
        exitWithError("Failed to convert image to PNG")
    }
    guard let tiffData = image.tiffRepresentation,
          let imageRep = NSBitmapImageRep(data: tiffData),
          let pngData = imageRep.representation(using: .png, properties: [:]) else {
        exitWithError("Failed to convert image to PNG")
    }
    FileHandle.standardOutput.write(pngData)
    printError("\(sourcePrefix)\(path)")
    exit(0)
}
```

- [ ] **Step 2: Add file reference detection**

Insert after the helpers:

```swift
// --- Detection 2: File references ---
func tryFileReference() -> Bool {
    // Prefer modern public.file-url, fall back to legacy NSFilenamesPboardType
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
       let fileURL = urls.first {
        let path = fileURL.path
        let resolvedPath = (try? URL(fileURLWithPath: path).resolvingSymlinksInPath().path) ?? path
        let ext = URL(fileURLWithPath: resolvedPath).pathExtension

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            exitWithError("File not found: \(resolvedPath)")
        }

        guard isImageExtension(ext) else {
            exitWithError("Copied file is not a supported image type: \(resolvedPath)", code: 2)
        }

        fileToStdoutPNG(path: resolvedPath, sourcePrefix: "source:file:")
    }
    return false
}

let _ = tryFileReference()
```

- [ ] **Step 3: Commit**

```bash
git add swift/ClipsshPaste.swift
git commit -m "feat: add file reference detection to clipssh-paste"
```

---

### Task 4: Text File Path Detection

**Files:**
- Modify: `swift/ClipsshPaste.swift`

Add the third detection path: text file path from clipboard.

- [ ] **Step 1: Add text path detection**

Insert after `tryFileReference()`:

```swift
// --- Detection 3: Text file path ---
func tryTextPath() -> Bool {
    guard let text = pasteboard.string(forType: .string) else {
        return false
    }

    // Must be a single line
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains("\n") else {
        return false
    }

    // Must start with / or ~
    guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else {
        return false
    }

    // Expand ~ to home directory
    let expanded = NSString(string: trimmed).expandingTildeInPath
    let ext = URL(fileURLWithPath: expanded).pathExtension

    guard isImageExtension(ext) else {
        if !ext.isEmpty {
            exitWithError("Path is not a supported image type: \(expanded)", code: 2)
        }
        return false
    }

    guard FileManager.default.fileExists(atPath: expanded) else {
        exitWithError("File not found: \(expanded)")
    }

    fileToStdoutPNG(path: expanded, sourcePrefix: "source:path:")
}

let _ = tryTextPath()
```

- [ ] **Step 2: Add final fallback — no match found**

Append at the end of the file:

```swift
// --- No match ---
exitWithError("No content found in clipboard")
```

- [ ] **Step 3: Commit**

```bash
git add swift/ClipsshPaste.swift
git commit -m "feat: add text file path detection to clipssh-paste"
```

---

### Task 5: Create Makefile

**Files:**
- Create: `swift/Makefile`

- [ ] **Step 1: Create `swift/Makefile`**

```makefile
.PHONY: build clean

BUILD_DIR ?= ../build

build: $(BUILD_DIR)/clipssh-paste

$(BUILD_DIR)/clipssh-paste: ClipsshPaste.swift
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $@ $<

clean:
	rm -rf $(BUILD_DIR)
```

- [ ] **Step 2: Commit**

```bash
git add swift/Makefile
git commit -m "build: add Makefile for clipssh-paste"
```

---

### Task 6: Update `clipssh` Script — macOS Clipboard Extraction

**Files:**
- Modify: `clipssh` (lines 154-190)

Replace the `pngpaste` dependency check and clipboard extraction with `clipssh-paste`.

- [ ] **Step 1: Replace the macOS dependency check (lines 155-159)**

Replace:
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v pngpaste &> /dev/null; then
        error "pngpaste not found. Install with: brew install pngpaste"
    fi
    PASTE_CMD="pngpaste"
```

With:
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v clipssh-paste &> /dev/null; then
        error "clipssh-paste not found. Install with: brew install strubio-ray/tap/clipssh"
    fi
```

- [ ] **Step 2: Replace the macOS clipboard extraction block (lines 176-190)**

Replace:
```bash
# Extract image from clipboard
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! pngpaste "$TEMP_FILE" 2>/dev/null; then
        error "No image in clipboard. Take a screenshot first (Cmd+Shift+Ctrl+4)"
    fi
else
    if ! $PASTE_CMD > "$TEMP_FILE" 2>/dev/null; then
        error "No image in clipboard. Take a screenshot first"
    fi
fi

# Verify file has content
if [[ ! -s "$TEMP_FILE" ]]; then
    error "Clipboard image is empty"
fi
```

With:
```bash
# Extract image from clipboard
if [[ "$OSTYPE" == "darwin"* ]]; then
    STDERR_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE $STDERR_FILE" EXIT
    clipssh-paste > "$TEMP_FILE" 2>"$STDERR_FILE"
    EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        error "$(tail -1 "$STDERR_FILE")"
    fi

    SOURCE_LINE=$(tail -1 "$STDERR_FILE")
    rm -f "$STDERR_FILE"
else
    if ! $PASTE_CMD > "$TEMP_FILE" 2>/dev/null; then
        error "No image in clipboard. Take a screenshot first"
    fi
fi

# Verify file has content
if [[ ! -s "$TEMP_FILE" ]]; then
    error "Clipboard image is empty"
fi
```

- [ ] **Step 3: Verify trap cleanup**

The original trap on line 174 (`trap "rm -f $TEMP_FILE" EXIT`) is overridden in the macOS branch to also clean `$STDERR_FILE`. Verify the trap override covers both files. The Linux path still uses the original trap (no `$STDERR_FILE` there).

- [ ] **Step 4: Commit**

```bash
git add clipssh
git commit -m "feat: replace pngpaste with clipssh-paste for macOS clipboard extraction"
```

---

### Task 7: Update `clipssh` Script — Dynamic Filename Logic

**Files:**
- Modify: `clipssh` (lines 192-202)

Update the upload section to use dynamic filenames based on the source line.

- [ ] **Step 1: Add filename resolution logic after clipboard extraction**

Insert after the "Verify file has content" block and before the "Generate remote path" section:

```bash
# Determine remote filename
TIMESTAMP=$(date +%s)
if [[ "$OSTYPE" == "darwin"* ]]; then
    case "$SOURCE_LINE" in
        source:file:*|source:path:*)
            ORIGINAL_PATH="${SOURCE_LINE#source:file:}"
            ORIGINAL_PATH="${ORIGINAL_PATH#source:path:}"
            ORIGINAL_NAME=$(basename "$ORIGINAL_PATH")
            ORIGINAL_BASE="${ORIGINAL_NAME%.*}"
            REMOTE_FILENAME="${ORIGINAL_BASE}-${TIMESTAMP}.png"
            ;;
        *)
            REMOTE_FILENAME="clipboard-${TIMESTAMP}.png"
            ;;
    esac
else
    REMOTE_FILENAME="clipboard-${TIMESTAMP}.png"
fi
```

- [ ] **Step 2: Update the SSH upload block to use `$REMOTE_FILENAME`**

Replace:
```bash
# Generate remote path (env var > config file > default)
REMOTE_DIR="${CLIPSSH_REMOTE_DIR:-$(config_get remote_dir)}"
REMOTE_DIR="${REMOTE_DIR:-/tmp}"
TIMESTAMP=$(date +%s)

# Upload via SSH (~ is expanded by the remote shell using eval echo)
REMOTE_PATH=$(cat "$TEMP_FILE" | ssh "$HOST" "
    DIR=\$(eval echo \"$REMOTE_DIR\")
    PATH_FULL=\"\$DIR/clipboard-${TIMESTAMP}.png\"
    mkdir -p \"\$DIR\" && cat > \"\$PATH_FULL\" && echo \"\$PATH_FULL\"
" 2>/dev/null) || true
```

With:
```bash
# Generate remote path (env var > config file > default)
REMOTE_DIR="${CLIPSSH_REMOTE_DIR:-$(config_get remote_dir)}"
REMOTE_DIR="${REMOTE_DIR:-/tmp}"

# Upload via SSH (~ is expanded by the remote shell using eval echo)
REMOTE_PATH=$(cat "$TEMP_FILE" | ssh "$HOST" "
    DIR=\$(eval echo \"$REMOTE_DIR\")
    PATH_FULL=\"\$DIR/${REMOTE_FILENAME}\"
    mkdir -p \"\$DIR\" && cat > \"\$PATH_FULL\" && echo \"\$PATH_FULL\"
" 2>/dev/null) || true
```

- [ ] **Step 3: Commit**

```bash
git add clipssh
git commit -m "feat: use original filename with timestamp for file/path clipboard sources"
```

---

### Task 8: Remove `install.sh`

**Files:**
- Delete: `install.sh`

- [ ] **Step 1: Remove install.sh**

```bash
git rm install.sh
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove install.sh, Homebrew is sole distribution method"
```

---

### Task 9: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README.md**

Replace the full contents of `README.md` with:

```markdown
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

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for expanded clipboard input methods"
```

---

### Task 10: Add `.gitignore` for build artifacts

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add `build/` to `.gitignore`**

Append to `.gitignore`:

```
build/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add build directory to gitignore"
```

---

### Follow-up (out of scope)

- Update the Homebrew formula in the separate tap repository to compile `clipssh-paste` from Swift source, remove the `pngpaste` dependency, and install both binaries.
