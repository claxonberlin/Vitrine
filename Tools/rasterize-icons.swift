#!/usr/bin/env swift
// Rasterises Resources/Icons/*.svg into Sources/Vitrine/Resources/Icons/*.png.
//
// SwiftCrossUI's Image loads png/jpeg/webp only — there is no SVG path — so the
// icons have to be baked. The SVGs remain the source of truth; re-run this
// after changing one:
//
//     swift Tools/rasterize-icons.swift
//
// Two tints are emitted per icon because SwiftCrossUI cannot recolour an image
// at render time: "-onlight" carries dark ink for light mode, "-ondark" light
// ink for dark mode, and the view picks by \.colorScheme.
import AppKit
import Foundation

let renderSize = 72  // 4x the 18pt display size, so it downsamples cleanly

struct Tint {
    let suffix: String
    let color: NSColor
}

let neutralTints = [
    Tint(suffix: "onlight", color: NSColor(white: 0.24, alpha: 1)),
    Tint(suffix: "ondark", color: NSColor(white: 0.88, alpha: 1))
]

let accentTint = Tint(suffix: "onaccent", color: .white)

/// Icons that only ever sit on a filled accent button need white ink and
/// nothing else; emitting the neutral pair for them would be dead weight.
let accentOnly: Set<String> = ["download"]
/// Icons that appear both plain and on an accent fill — the page toggle shows
/// its selected half filled — so they need all three tints.
let accentAlso: Set<String> = ["apps", "book-open"]

func tints(for name: String) -> [Tint] {
    if accentOnly.contains(name) { return [accentTint] }
    return accentAlso.contains(name) ? neutralTints + [accentTint] : neutralTints
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDir = root.appendingPathComponent("Resources/Icons")
let outputDir = root.appendingPathComponent("Sources/Vitrine/Resources/Icons")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func rasterize(_ svg: URL, tint: Tint) throws -> Data {
    guard let source = NSImage(contentsOf: svg) else {
        throw NSError(domain: "rasterize", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot read \(svg.lastPathComponent)"])
    }
    // Drawing into an explicitly sized bitmap rep rather than lockFocus keeps
    // the output pixel dimensions independent of the display's scale factor.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: renderSize, pixelsHigh: renderSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        throw NSError(domain: "rasterize", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: 0, y: 0, width: renderSize, height: renderSize)
    source.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
    // sourceAtop paints the tint only where the strokes already have alpha,
    // recolouring the artwork without filling the background.
    tint.color.set()
    box.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "rasterize", code: 3)
    }
    return data
}

let svgs = try FileManager.default
    .contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

for svg in svgs {
    let name = svg.deletingPathExtension().lastPathComponent
    for tint in tints(for: name) {
        let data = try rasterize(svg, tint: tint)
        let out = outputDir.appendingPathComponent("\(name)-\(tint.suffix).png")
        try data.write(to: out)
        print("  \(out.lastPathComponent)  \(data.count) bytes")
    }
}
print("rasterised \(svgs.count) icons at \(renderSize)px")
