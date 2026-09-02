// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vitrine",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vitrine",
            path: "Sources/Vitrine",
            linkerSettings: [
                // Embed Info.plist into the Mach-O __TEXT,__info_plist section.
                // Lets the bare binary (Xcode Run, `swift run`) launch as a real
                // app — proper menu bar, dock entry, window behavior — without
                // needing the .app bundle wrapper. The custom icon still
                // requires bundle.sh, since LaunchServices only loads .icns
                // from a Resources/ folder next to the binary.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "VitrineTests",
            dependencies: ["Vitrine"]
        )
    ]
)
