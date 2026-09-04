import SwiftUI
import AppKit
import VitrineKit

/// The splash artwork of the newest Blender release, filling the window
/// behind everything else.
///
/// A scrim sits over it. The paintings are commissioned art and vary wildly —
/// 5.2 is a near-black close-up of a lynx, others are bright and busy — so
/// nothing readable can be laid straight onto one. The scrim is the window's
/// own background colour at partial opacity, which pulls every painting
/// towards whatever the current appearance calls neutral: lighter in light
/// mode, darker in dark. Unlike a material it doesn't blur, so the picture
/// stays a picture.
struct SplashBackground: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    @State private var artwork: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Painted first so the window is never briefly transparent,
                // and so a machine that has never reached blender.org still
                // gets an ordinary window.
                Color(nsColor: .windowBackgroundColor)

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        // Softened, then scrimmed. Just enough blur to take
                        // the edge off fur, foliage and lettering so they
                        // stop competing with the list — the painting is
                        // still the painting, which is the point of putting
                        // it there. `opaque` samples the edge pixels rather
                        // than transparency, which would otherwise fade the
                        // picture out into a grey border.
                        .blur(radius: 6, opaque: true)
                        .clipped()
                        .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.45))
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        // Decoration only: VoiceOver has no use for it, and it must never
        // take a click meant for the list on top.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.5), value: artwork != nil)
        // Reloads only when the file actually changes, so decoding happens
        // once per release rather than once per render.
        .task(id: store.splashArtwork) {
            artwork = store.splashArtwork.flatMap { NSImage(contentsOf: $0) }
        }
    }
}
