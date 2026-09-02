// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitrine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/stackotter/swift-cross-ui", from: "0.9.0")
    ],
    targets: [
        // Everything that isn't UI: catalogue, downloads, install bookkeeping,
        // and the per-OS integration layer. Builds on macOS and Linux alike.
        .target(name: "VitrineKit"),

        // The SwiftCrossUI front end — one source of truth for both platforms.
        // DefaultBackend resolves to AppKit on macOS and GTK 4 on Linux.
        .executableTarget(
            name: "Vitrine",
            dependencies: [
                "VitrineKit",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                // Only for the NSWindow escape hatch in WindowChrome.swift:
                // SwiftCrossUI exposes no window-chrome API, and the unified
                // title bar is what makes the app look at home on macOS.
                .product(name: "AppKitBackend", package: "swift-cross-ui",
                         condition: .when(platforms: [.macOS]))
            ],
            linkerSettings: [
                // Embeds Info.plist into __TEXT,__info_plist so `swift run` on
                // macOS launches as a real GUI app. Swift Bundler supplies the
                // plist for shipped .app bundles; Linux has no equivalent.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),

        .testTarget(name: "VitrineKitTests", dependencies: ["VitrineKit"])
    ]
)
