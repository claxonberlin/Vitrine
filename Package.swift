// swift-tools-version: 6.0
import PackageDescription

// One core, two native front ends.
//
// `VitrineKit` is the whole app minus its pixels: catalogue, downloads,
// install bookkeeping, the view model, and the per-OS integration layer. It
// imports nothing but Foundation and builds identically on macOS and Fedora.
//
// The front end is chosen here rather than with `#if os(...)` inside the
// sources, because the two use different UI frameworks entirely: SwiftUI on
// macOS, Adwaita for Swift (GTK 4 / libadwaita) on Linux. A package manifest
// is compiled and run on the host, so these branches decide what a build on
// *this* machine even sees — which is what keeps a macOS build free of any
// dependency at all, and a Fedora build free of AppKit.
//
// Both branches produce an executable called `Vitrine` from the same
// `VitrineKit`, so `swift build`, `swift run` and `bundle.sh` are unchanged
// between platforms.

#if os(Linux)
let uiPath = "Sources/VitrineLinux"
let uiDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/AparokshaUI/adwaita-swift", from: "0.2.6")
]
let uiTargetDependencies: [Target.Dependency] = [
    "VitrineKit",
    .product(name: "Adwaita", package: "adwaita-swift")
]
let uiResources: [Resource] = []
// Adwaita builds in Swift 5 language mode; matching it here keeps its
// non-Sendable widget types usable from our views.
let uiSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let uiLinkerSettings: [LinkerSetting] = []
#else
let uiPath = "Sources/VitrineMac"
let uiDependencies: [Package.Dependency] = []
let uiTargetDependencies: [Target.Dependency] = ["VitrineKit"]
// The icons ship as SVG and are tinted at draw time: AppKit reads SVG into a
// vector image rep, so there is no rasterisation step and one file covers
// light, dark and on-accent.
let uiResources: [Resource] = [.copy("Resources/Icons")]
let uiSwiftSettings: [SwiftSetting] = []
let uiLinkerSettings: [LinkerSetting] = [
    // Embeds Info.plist into __TEXT,__info_plist so `swift run` launches as a
    // real GUI app. `bundle.sh` supplies the same plist to the .app wrapper.
    .unsafeFlags([
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", "Resources/Info.plist"
    ])
]
#endif

let package = Package(
    name: "Vitrine",
    platforms: [.macOS(.v15)],
    dependencies: uiDependencies,
    targets: [
        // The splash paintings ship with the app rather than being scraped
        // on demand: `./splashes.sh` fills the folder, so an install already
        // has every released series' artwork and the daily's standing one.
        .target(name: "VitrineKit", resources: [.copy("Resources/Splashes")]),

        .executableTarget(
            name: "Vitrine",
            dependencies: uiTargetDependencies,
            path: uiPath,
            resources: uiResources,
            swiftSettings: uiSwiftSettings,
            linkerSettings: uiLinkerSettings
        ),

        .testTarget(name: "VitrineKitTests", dependencies: ["VitrineKit"])
    ]
)
