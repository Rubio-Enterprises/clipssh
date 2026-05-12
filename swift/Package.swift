// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "clipssh-paste",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .executable(name: "clipssh-paste", targets: ["clipssh-paste"]),
        .library(name: "ClipsshPasteCore", targets: ["ClipsshPasteCore"]),
    ],
    targets: [
        // Pure (AppKit-free) helpers. Lives here so it can be unit tested
        // without spinning up an NSPasteboard.
        .target(
            name: "ClipsshPasteCore",
            path: "Sources/ClipsshPasteCore"
        ),
        // The macOS executable — wires up NSPasteboard and stdout/stderr.
        .executableTarget(
            name: "clipssh-paste",
            dependencies: ["ClipsshPasteCore"],
            path: "Sources/clipssh-paste"
        ),
        .testTarget(
            name: "ClipsshPasteCoreTests",
            dependencies: ["ClipsshPasteCore"],
            path: "Tests/ClipsshPasteCoreTests"
        ),
    ]
)
