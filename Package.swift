// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Openfy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Openfy", targets: ["Openfy"]),
    ],
    targets: [
        // Library scanning, tag parsing, artwork, filtering. No UI, fully unit-tested.
        .target(name: "OpenfyCore", path: "Sources/OpenfyCore"),
        // The macOS app: SwiftUI interface + CoreAudio playback engine.
        .executableTarget(
            name: "Openfy",
            dependencies: ["OpenfyCore"],
            path: "Sources/Openfy",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer"),
            ]
        ),
        .testTarget(name: "OpenfyCoreTests", dependencies: ["OpenfyCore"], path: "Tests/OpenfyCoreTests"),
    ]
)
