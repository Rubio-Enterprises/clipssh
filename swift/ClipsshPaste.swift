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
      1. File reference (Finder right-click → Copy)
      2. Raw image data (screenshot to clipboard)
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
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains("\n") else {
        return
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
