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
