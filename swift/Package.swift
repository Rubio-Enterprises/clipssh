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
        .target(
            name: "ClipsshPasteCore",
            path: "Sources/ClipsshPasteCore"
        ),
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
