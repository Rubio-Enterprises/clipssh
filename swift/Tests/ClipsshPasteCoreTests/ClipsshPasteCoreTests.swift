import XCTest
@testable import ClipsshPasteCore

final class ClipsshPasteCoreTests: XCTestCase {

    // MARK: - isImageExtension

    func testIsImageExtension_acceptsCanonicalLowercase() {
        for ext in ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"] {
            XCTAssertTrue(ClipsshPasteCore.isImageExtension(ext), "\(ext) should be accepted")
        }
    }

    func testIsImageExtension_caseInsensitive() {
        XCTAssertTrue(ClipsshPasteCore.isImageExtension("PNG"))
        XCTAssertTrue(ClipsshPasteCore.isImageExtension("Jpeg"))
        XCTAssertTrue(ClipsshPasteCore.isImageExtension("WEBP"))
    }

    func testIsImageExtension_rejectsUnsupported() {
        for ext in ["txt", "pdf", "heic", "mp4", "doc"] {
            XCTAssertFalse(ClipsshPasteCore.isImageExtension(ext), "\(ext) should be rejected")
        }
    }

    func testIsImageExtension_rejectsEmpty() {
        XCTAssertFalse(ClipsshPasteCore.isImageExtension(""))
    }

    // MARK: - stripSurroundingQuotes

    func testStripSurroundingQuotes_removesMatchingSingleQuotes() {
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("'/tmp/x.png'"), "/tmp/x.png")
    }

    func testStripSurroundingQuotes_removesMatchingDoubleQuotes() {
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("\"/tmp/x.png\""), "/tmp/x.png")
    }

    func testStripSurroundingQuotes_leavesUnquotedAlone() {
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("/tmp/x.png"), "/tmp/x.png")
    }

    func testStripSurroundingQuotes_doesNotStripMismatchedQuotes() {
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("'/tmp/x.png\""), "'/tmp/x.png\"")
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("\"/tmp/x.png'"), "\"/tmp/x.png'")
    }

    func testStripSurroundingQuotes_handlesShortStrings() {
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes(""), "")
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("'"), "'")
        // Two-character matched quotes collapse to empty.
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("''"), "")
        XCTAssertEqual(ClipsshPasteCore.stripSurroundingQuotes("\"\""), "")
    }

    // MARK: - looksLikePath

    func testLooksLikePath_acceptsAbsolutePaths() {
        XCTAssertTrue(ClipsshPasteCore.looksLikePath("/tmp/x.png"))
        XCTAssertTrue(ClipsshPasteCore.looksLikePath("/"))
    }

    func testLooksLikePath_acceptsTildePaths() {
        XCTAssertTrue(ClipsshPasteCore.looksLikePath("~/Pictures/x.png"))
        XCTAssertTrue(ClipsshPasteCore.looksLikePath("~"))
    }

    func testLooksLikePath_rejectsRelativeAndUnrelated() {
        XCTAssertFalse(ClipsshPasteCore.looksLikePath("relative/path.png"))
        XCTAssertFalse(ClipsshPasteCore.looksLikePath("hello world"))
        XCTAssertFalse(ClipsshPasteCore.looksLikePath(""))
    }

    func testLooksLikePath_rejectsMultilineInput() {
        XCTAssertFalse(ClipsshPasteCore.looksLikePath("/tmp/x.png\n/tmp/y.png"))
    }

    // MARK: - normalizeClipboardPath

    func testNormalizeClipboardPath_trimsWhitespace() {
        XCTAssertEqual(ClipsshPasteCore.normalizeClipboardPath("  /tmp/x.png  \n"), "/tmp/x.png")
    }

    func testNormalizeClipboardPath_stripsQuotes() {
        XCTAssertEqual(ClipsshPasteCore.normalizeClipboardPath("'/tmp/x.png'"), "/tmp/x.png")
        XCTAssertEqual(ClipsshPasteCore.normalizeClipboardPath("\"/tmp/x.png\""), "/tmp/x.png")
    }

    func testNormalizeClipboardPath_expandsTilde() {
        let result = ClipsshPasteCore.normalizeClipboardPath("~/photo.png")
        // The exact expansion depends on $HOME but it must not start with ~ anymore.
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.hasPrefix("~"))
        XCTAssertTrue(result!.hasSuffix("/photo.png"))
    }

    func testNormalizeClipboardPath_returnsNilForNonPaths() {
        XCTAssertNil(ClipsshPasteCore.normalizeClipboardPath("just some prose"))
        XCTAssertNil(ClipsshPasteCore.normalizeClipboardPath(""))
        XCTAssertNil(ClipsshPasteCore.normalizeClipboardPath("relative.png"))
    }

    func testNormalizeClipboardPath_returnsNilForMultilineEvenIfFirstLineLooksValid() {
        XCTAssertNil(ClipsshPasteCore.normalizeClipboardPath("/tmp/x.png\nextra"))
    }

    // MARK: - sourceMarker

    func testSourceMarker_fileIncludesPath() {
        XCTAssertEqual(
            ClipsshPasteCore.sourceMarker(origin: .file, payload: "/tmp/x.png"),
            "source:file:/tmp/x.png"
        )
    }

    func testSourceMarker_pathIncludesPath() {
        XCTAssertEqual(
            ClipsshPasteCore.sourceMarker(origin: .path, payload: "/tmp/y.png"),
            "source:path:/tmp/y.png"
        )
    }

    func testSourceMarker_imageIgnoresPayload() {
        XCTAssertEqual(
            ClipsshPasteCore.sourceMarker(origin: .image, payload: "anything"),
            "source:image"
        )
        XCTAssertEqual(
            ClipsshPasteCore.sourceMarker(origin: .image, payload: ""),
            "source:image"
        )
    }
}
