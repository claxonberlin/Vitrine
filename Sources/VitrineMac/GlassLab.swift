#if DEBUG
import SwiftUI
import AppKit
import VitrineKit

/// A specimen sheet for the glass treatments a button can wear, laid over the
/// same painting a daily card wears — a backdrop that runs from near-black to
/// near-white across its width, which is exactly the case that makes a glass
/// control disagree with itself.
///
/// Debug builds only, and reachable only from the Developer menu: this is a
/// place to look at materials side by side and decide, not a feature. macOS
/// 26 only, since half of what it draws doesn't exist below that.
///
/// Every specimen draws the same glyph at the same size, so the only thing
/// varying down the sheet is the treatment named beside it. Each is repeated
/// across the width, so one row shows what that treatment does over black
/// sky, over the lit rim, and over everything between.
@available(macOS 26.0, *)
struct GlassLab: View {
    @State private var tintOpacity: Double = Theme.cardGlassOpacity
    @State private var tint: Color = Theme.catalogueAccent
    @State private var scheme: ColorScheme = .light
    @State private var backdropKind: Backdrop = .painting

    /// What the specimens stand on. Black is the case that breaks things: the
    /// darker the backdrop, the harder a vibrant label is pushed towards
    /// white, whatever colour it was given.
    private enum Backdrop: String, CaseIterable, Identifiable {
        case painting, black, window
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// How many copies of a specimen straddle the picture.
    private static let repeats = 5

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            sheet
        }
        .frame(minWidth: 720, minHeight: 560)
        .preferredColorScheme(scheme)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Appearance", selection: $scheme) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            ColorPicker("Tint", selection: $tint, supportsOpacity: false)
                .frame(width: 90)

            HStack(spacing: 6) {
                Text("Tint opacity")
                Slider(value: $tintOpacity, in: 0...1)
                    .frame(width: 140)
                Text(String(format: "%.2f", tintOpacity))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            Picker("Backdrop", selection: $backdropKind) {
                ForEach(Backdrop.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sheet

    private var sheet: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(specimens) { specimen in
                    SpecimenRow(specimen: specimen, repeats: Self.repeats)
                }
            }
            .padding(.vertical, 14)
        }
        .background(backdrop)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch backdropKind {
        case .black: Color.black
        case .window: Theme.windowBackground
        case .painting: painting
        }
    }

    @ViewBuilder
    private var painting: some View {
        if let url = SplashLibrary.dailyArtwork,
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
                .ignoresSafeArea()
        } else {
            Theme.windowBackground
        }
    }

    // MARK: - The specimens themselves

    private var specimens: [Specimen] {
        [
            Specimen(name: ".buttonStyle(.glass)") {
                AnyView(Button {} label: { LabGlyph() }.buttonStyle(.glass))
            },
            Specimen(name: ".glass + foregroundStyle(ink)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.glass)
                    .foregroundStyle(Color(nsColor: .labelColor)))
            },
            Specimen(name: ".glass + foregroundStyle(.black)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.glass)
                    .foregroundStyle(.black))
            },
            Specimen(name: ".glass + .tint(tint)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.glass)
                    .tint(tint))
            },
            Specimen(name: ".glassProminent + .tint(tint)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.glassProminent)
                    .tint(tint))
            },
            Specimen(name: ".glassProminent + white glyph") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .foregroundStyle(.white))
            },
            Specimen(name: ".plain + glassEffect(.regular)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .padding(8)
                    .glassEffect(.regular, in: .circle))
            },
            Specimen(name: ".plain + glassEffect(.regular.tint(opacity))") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .padding(8)
                    .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: "…tinted, with a white glyph") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(8)
                    .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: "…tinted, with an ink glyph") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .padding(8)
                    .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: ".regular.tint(.white.opacity(opacity))") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .padding(8)
                    .glassEffect(.regular.tint(.white.opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: ".regular.interactive()") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .padding(8)
                    .glassEffect(.regular.interactive(), in: .circle))
            },
            // What the library row's "···" wears today: the glass pinned
            // light by a tint, with a vibrant glyph on top. The two disagree
            // over a dark card — the tint holds the disc light while the
            // glyph resolves against the picture and goes white.
            Specimen(name: "row menu today: tint(control, 0.8) + .secondary") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .glassEffect(.regular.tint(Color(nsColor: .controlBackgroundColor)
                        .opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: "…same, glyph pinned to ink") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(8)
                    .glassEffect(.regular.tint(Color(nsColor: .controlBackgroundColor)
                        .opacity(tintOpacity)), in: .circle))
            },
            // The pin that follows the appearance without following the
            // picture: `labelColor` is dark in light appearance and light in
            // dark, which is exactly how `controlBackgroundColor` moves, so
            // the disc and the glyph can no longer disagree.
            Specimen(name: "…same, glyph pinned to labelColor") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .padding(8)
                    .glassEffect(.regular.tint(Color(nsColor: .controlBackgroundColor)
                        .opacity(tintOpacity)), in: .circle))
            },
            Specimen(name: "…same, glyph pinned to secondaryLabelColor") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(8)
                    .glassEffect(.regular.tint(Color(nsColor: .controlBackgroundColor)
                        .opacity(tintOpacity)), in: .circle))
            },
            // What the row menu wears now: both ends stated, neither
            // semantic, so nothing in the pair can be re-resolved against
            // the picture.
            Specimen(name: "stated fill + stated glyph") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.cardButtonGlyph(scheme))
                    .padding(8)
                    .glassEffect(.regular.tint(Theme.cardButtonFill(scheme).opacity(tintOpacity)),
                                 in: .circle))
            },
            // The library row's control is a `Menu`, not a `Button`. Same
            // modifiers, same colours — if this one drifts where the plain
            // button above holds, the menu's own chrome is what re-resolves
            // the colours.
            Specimen(name: "Menu, stated fill + stated glyph") {
                AnyView(Menu {
                    Button("Nothing") {}
                } label: {
                    LabGlyph()
                        .foregroundStyle(Theme.cardButtonGlyph(scheme))
                        .frame(width: Theme.Metrics.actionHeight,
                               height: Theme.Metrics.actionHeight)
                }
                .menuStyle(.button)
                .buttonStyle(.disc(hoverInk: Hover.onSurface))
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.tint(Theme.cardButtonFill(scheme).opacity(tintOpacity)),
                             in: .circle))
            },
            // Two ways out of the blend, if a stated colour isn't enough:
            // ask for normal compositing, or draw the glyph over the glass
            // instead of inside it.
            Specimen(name: "…stated, + blendMode(.normal)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.cardButtonGlyph(scheme))
                    .blendMode(.normal)
                    .padding(8)
                    .glassEffect(.regular.tint(Theme.cardButtonFill(scheme).opacity(tintOpacity)),
                                 in: .circle))
            },
            Specimen(name: "…glyph drawn over the glass, not in it") {
                AnyView(Button {} label: {
                    Color.clear
                        .frame(width: Theme.Metrics.actionHeight - Theme.Metrics.glassCirclePadding,
                               height: Theme.Metrics.actionHeight - Theme.Metrics.glassCirclePadding)
                }
                    .buttonStyle(.plain)
                    .padding(8)
                    .glassEffect(.regular.tint(Theme.cardButtonFill(scheme).opacity(tintOpacity)),
                                 in: .circle)
                    .overlay {
                        LabGlyph()
                            .foregroundStyle(Theme.cardButtonGlyph(scheme))
                            .allowsHitTesting(false)
                    })
            },
            Specimen(name: "untinted .regular + .secondary") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .glassEffect(.regular, in: .circle))
            },
            Specimen(name: "flat fill (no glass at all)") {
                AnyView(Button {} label: { LabGlyph() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(tint.opacity(0.88))))
            }
        ]
    }
}

/// One treatment, named and drawn.
private struct Specimen: Identifiable {
    let name: String
    let make: () -> AnyView

    var id: String { name }
}

/// A specimen repeated across the picture, with its name on a plate at the
/// leading edge — the plate is deliberately opaque, so the caption stays
/// readable whatever the glass beside it is doing.
private struct SpecimenRow: View {
    let specimen: Specimen
    let repeats: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(specimen.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.65)))
                .frame(width: 220, alignment: .leading)
                .padding(.leading, 12)

            ForEach(0..<repeats, id: \.self) { _ in
                Spacer(minLength: 8)
                specimen.make()
            }
            Spacer(minLength: 8)
        }
        .frame(height: 48)
    }
}

/// The glyph every specimen carries: the app's own "···", at the size a row
/// draws it, so the sheet is measuring the real thing.
private struct LabGlyph: View {
    var body: some View {
        IconView(icon: .more, size: Theme.Metrics.actionIconSize)
            .frame(width: Theme.Metrics.actionHeight - Theme.Metrics.glassCirclePadding,
                   height: Theme.Metrics.actionHeight - Theme.Metrics.glassCirclePadding)
    }
}
#endif
