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
    Usage: clipssh-paste              (read mode)
           clipssh-paste --put-file <path>  (write mode)

    Read mode: Extract image from macOS clipboard and write PNG data to stdout.
    Write mode: Read a PNG file from disk and place it on the clipboard as image data.

    Detection order (read mode only):
      1. File reference (Finder right-click → Copy)
      2. Raw image data (screenshot to clipboard)
      3. Text file path (Finder right-click → Copy Path)

    Output:
      stdout: PNG image data
      stderr: source line (last line) indicating detection method

    Exit codes:
      0  Success
      1  Error (read mode: no usable image found; write mode: file unreadable,
         not a valid image, or pasteboard write failed)
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

// --- Mode: --put-file <path> ---
// Write a PNG file from disk onto the pasteboard as image data.
// Used by `clipssh --capture` on upload failure to restore the retry contract:
// the captured PNG is placed back on the clipboard so the bare-clipssh hotkey
// can re-attempt the upload without re-capturing.
if let putFileIdx = CommandLine.arguments.firstIndex(of: "--put-file") {
    let pathArgIdx = CommandLine.arguments.index(after: putFileIdx)
    guard pathArgIdx < CommandLine.arguments.endIndex else {
        exitWithError("--put-file requires a path argument")
    }
    let path = CommandLine.arguments[pathArgIdx]

    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        exitWithError("Failed to read file: \(path)")
    }

    // Decode to validate the file is a real image (reject truncated/corrupt PNGs
    // and non-image files before touching the pasteboard) and to produce the
    // TIFF representation the pasteboard also requires.
    guard let bitmapRep = NSBitmapImageRep(data: data) else {
        exitWithError("Failed to decode image from file: \(path)")
    }
    guard let tiffData = bitmapRep.representation(using: .tiff, properties: [:]) else {
        exitWithError("Failed to convert image to TIFF")
    }

    // Write both PNG and TIFF representations so consumers can pick whichever
    // they prefer. The PNG bytes are written as-is (the file on disk is already
    // a valid PNG from screencapture).
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.declareTypes([.png, .tiff], owner: nil)
    guard pb.setData(data, forType: .png) else {
        exitWithError("Failed to write PNG data to pasteboard")
    }
    guard pb.setData(tiffData, forType: .tiff) else {
        exitWithError("Failed to write TIFF data to pasteboard")
    }

    exit(0)
}

let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"])

let pasteboard = NSPasteboard.general

// Check if pasteboard has any content at all
let items = pasteboard.pasteboardItems
if items == nil || items?.isEmpty == true {
    exitWithError("No content found in clipboard")
}

func isImageExtension(_ ext: String) -> Bool {
    return supportedExtensions.contains(ext.lowercased())
}

func writePNGToStdout(_ pngData: Data, source: String) -> Never {
    FileHandle.standardOutput.write(pngData)
    printError(source)
    exit(0)
}

func convertToPNG(_ data: Data) -> Data? {
    guard let imageRep = NSBitmapImageRep(data: data),
          let pngData = imageRep.representation(using: .png, properties: [:]) else {
        return nil
    }
    return pngData
}

func fileToStdoutPNG(path: String, sourcePrefix: String) -> Never {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        exitWithError("Failed to read image file: \(path)")
    }
    guard let pngData = convertToPNG(data) else {
        exitWithError("Failed to convert image to PNG")
    }
    writePNGToStdout(pngData, source: "\(sourcePrefix)\(path)")
}

// --- Detection 1: File references ---
func tryFileReference() {
    // Prefer modern public.file-url, fall back to legacy NSFilenamesPboardType
    // Checked before raw image data because Finder Copy puts both a file reference
    // AND the file's icon as image data on the clipboard — we want the actual file.
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
       let fileURL = urls.first {
        let resolved = fileURL.resolvingSymlinksInPath()
        let resolvedPath = resolved.path
        let ext = resolved.pathExtension

        guard isImageExtension(ext) else {
            exitWithError("Copied file is not a supported image type: \(resolvedPath)", code: 2)
        }

        fileToStdoutPNG(path: resolvedPath, sourcePrefix: "source:file:")
    }
}

tryFileReference()

// --- Detection 2: Raw image data ---
func tryRawImageData() {
    // Check for PNG data first, then TIFF (macOS screenshots are often TIFF internally)
    let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
    ]

    for type in imageTypes {
        if let data = pasteboard.data(forType: type) {
            if type == .png {
                // PNG data can be written directly without re-encoding
                writePNGToStdout(data, source: "source:image")
            }
            guard let pngData = convertToPNG(data) else {
                continue
            }
            writePNGToStdout(pngData, source: "source:image")
        }
    }
}

tryRawImageData()

// --- Detection 3: Text file path ---
func tryTextPath() {
    guard let text = pasteboard.string(forType: .string) else {
        return
    }

    // Must be a single line
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains("\n") else {
        return
    }

    // Strip surrounding quotes (Finder's "Copy as Pathname" wraps paths in single quotes)
    if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) ||
       (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
        trimmed = String(trimmed.dropFirst().dropLast())
    }

    // Must start with / or ~
    guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else {
        return
    }

    // Expand ~ to home directory
    let expanded = NSString(string: trimmed).expandingTildeInPath
    let ext = URL(fileURLWithPath: expanded).pathExtension

    guard isImageExtension(ext) else {
        if !ext.isEmpty {
            exitWithError("Path is not a supported image type: \(expanded)", code: 2)
        }
        return
    }

    fileToStdoutPNG(path: expanded, sourcePrefix: "source:path:")
}

tryTextPath()

// --- No match ---
exitWithError("No content found in clipboard")
