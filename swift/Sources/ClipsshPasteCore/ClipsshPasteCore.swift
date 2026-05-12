import Foundation

/// Pure (AppKit-free) helpers used by clipssh-paste.
///
/// These are extracted into their own module so they can be unit tested
/// without spinning up an NSPasteboard. Anything that touches the
/// pasteboard, the file system, or process exit lives in the executable
/// target, not here.
public enum ClipsshPasteCore {

    /// File extensions clipssh-paste will accept as image inputs.
    /// Lowercase canonical form; callers should compare against `lowercased()`.
    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp",
    ]

    /// Returns true when `ext` (case-insensitively) is in the supported set.
    /// An empty extension is never considered an image.
    public static func isImageExtension(_ ext: String) -> Bool {
        guard !ext.isEmpty else { return false }
        return supportedExtensions.contains(ext.lowercased())
    }

    /// Strips a matching pair of surrounding single or double quotes.
    /// Finder's "Copy as Pathname" wraps paths in single quotes; we accept
    /// either flavor and leave unquoted strings alone.
    public static func stripSurroundingQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if (s.hasPrefix("'") && s.hasSuffix("'")) ||
           (s.hasPrefix("\"") && s.hasSuffix("\"")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Whether `s` looks like a single-line absolute or tilde-prefixed path.
    /// Multi-line input is rejected — the clipboard may contain prose that
    /// happens to begin with a slash.
    public static func looksLikePath(_ s: String) -> Bool {
        guard !s.contains("\n") else { return false }
        return s.hasPrefix("/") || s.hasPrefix("~")
    }

    /// Normalizes a clipboard text candidate into a (potential) filesystem
    /// path: trims whitespace, strips surrounding quotes, expands `~`.
    /// Returns nil when the input clearly isn't a path.
    public static func normalizeClipboardPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = stripSurroundingQuotes(trimmed)
        guard looksLikePath(unquoted) else { return nil }
        return NSString(string: unquoted).expandingTildeInPath
    }

    /// Builds the "source:..." marker clipssh-paste writes to stderr so the
    /// caller can use the original filename for the remote upload.
    /// Returns nil for unrecognized origins.
    public static func sourceMarker(origin: SourceOrigin, payload: String) -> String {
        switch origin {
        case .file:  return "source:file:\(payload)"
        case .path:  return "source:path:\(payload)"
        case .image: return "source:image"
        }
    }

    public enum SourceOrigin {
        /// Pasteboard contained an NSURL pointing at a file.
        case file
        /// Pasteboard contained plain text resolved to a file path.
        case path
        /// Pasteboard contained raw image bytes.
        case image
    }
}
