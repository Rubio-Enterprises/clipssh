import Foundation

/// AppKit-free helpers; safe to import from any target.
public enum ClipsshPasteCore {

    /// File extensions accepted as image inputs. Lowercase canonical form.
    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp",
    ]

    public static func isImageExtension(_ ext: String) -> Bool {
        guard !ext.isEmpty else { return false }
        return supportedExtensions.contains(ext.lowercased())
    }

    /// Strips a matching pair of surrounding single or double quotes.
    /// Finder's "Copy as Pathname" wraps paths in single quotes.
    public static func stripSurroundingQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if (s.hasPrefix("'") && s.hasSuffix("'")) ||
           (s.hasPrefix("\"") && s.hasSuffix("\"")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Single-line strings starting with `/` or `~`. Multi-line input is
    /// rejected so prose pasted from a document doesn't masquerade as a path.
    public static func looksLikePath(_ s: String) -> Bool {
        guard !s.contains("\n") else { return false }
        return s.hasPrefix("/") || s.hasPrefix("~")
    }

    /// Trim, unquote, and expand `~`. Returns nil for non-path input.
    public static func normalizeClipboardPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = stripSurroundingQuotes(trimmed)
        guard looksLikePath(unquoted) else { return nil }
        return NSString(string: unquoted).expandingTildeInPath
    }

    /// The "source:..." marker clipssh-paste writes to stderr so the bash
    /// caller can derive the remote filename from the original source.
    /// This contract is mirrored in `clipssh`'s `compute_remote_filename`.
    public enum Source {
        case file(String)
        case path(String)
        case image
    }

    public static func sourceMarker(_ source: Source) -> String {
        switch source {
        case .file(let path):  return "source:file:\(path)"
        case .path(let path):  return "source:path:\(path)"
        case .image:           return "source:image"
        }
    }
}
