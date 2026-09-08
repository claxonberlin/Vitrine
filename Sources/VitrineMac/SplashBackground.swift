import SwiftUI
import AppKit
import VitrineKit

/// The splash artwork of the newest Blender release, filling the window
/// behind everything else.
///
/// The paintings are commissioned art and vary wildly — 5.2 is a near-black
/// close-up of a lynx, others are bright and busy — shown sharp and at full
/// colour, the way the artist made it. The rows in front carry their own
/// glass material to stay legible over it, and the title wears its own
/// glass pill (`TitlePillBackground` in ContentView.swift) for the same
/// reason — the artwork itself is a persistent backdrop behind the whole
/// library, not scrolling content, so it can't dissolve into the toolbar
/// the way rows do: `scrollEdgeEffectStyle` only ever reaches a view that's
/// actually attached to the scroll view as content, and this one has to
/// stay put behind every row all the way down the list, not scroll away
/// with them.
///
/// Filling a window with a painting means cropping it, and the crop the app
/// picks is rarely the one you'd pick. Option-dragging pans the painting
/// inside its crop, and where you leave it is where it is next launch.
/// Option, because a plain drag has to keep meaning what it already means:
/// scrolling the list.
struct SplashBackground: View {
    @StateObject private var model = SplashArtworkModel()
    @EnvironmentObject private var bridge: StoreBridge

    var body: some View {
        SplashArtworkFill(artwork: model.artwork, pan: model.pan)
            .ignoresSafeArea()
            // Decoration only: VoiceOver has no use for it, and it must never
            // take a click meant for the list on top.
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .animation(.smooth(duration: 0.5), value: model.artwork != nil)
            .task(id: bridge.store.splashArtwork) { model.load(from: bridge.store.splashArtwork) }
            .background(WindowConfigurator { model.pan.watch($0) })
            .onDisappear { model.pan.stopWatching() }
    }
}

/// Owns the one decoded copy of the splash artwork and its pan tracker.
@MainActor
final class SplashArtworkModel: ObservableObject {
    @Published private(set) var artwork: NSImage?
    let pan = SplashPan()

    /// Reloads only when the file actually changes, so decoding happens once
    /// per release rather than once per render. Call from a `.task(id:)`
    /// keyed to the store's current splash-artwork URL.
    func load(from url: URL?) {
        artwork = url.flatMap { NSImage(contentsOf: $0) }
    }
}

/// Draws the splash artwork, cropped and offset by `pan`, filling whatever
/// frame it's given.
struct SplashArtworkFill: View {
    let artwork: NSImage?
    @ObservedObject var pan: SplashPan

    var body: some View {
        GeometryReader { geometry in
            let travel: CGSize = artwork
                .map { SplashPan.travel(for: $0.size, in: geometry.size) } ?? .zero

            ZStack {
                // Painted first so the window is never briefly transparent,
                // and so a machine that has never reached blender.org still
                // gets an ordinary window.
                Color(nsColor: .windowBackgroundColor)

                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .offset(x: pan.x * travel.width, y: pan.y * travel.height)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            // The drag handler works in points, so it needs this view's own
            // measured size, not the image's.
            .onChange(of: travel, initial: true) { pan.travel = travel }
        }
    }
}

/// Where the splash artwork sits inside its crop, and the option-drag that
/// moves it.
///
/// The drag is caught with an AppKit event monitor rather than a SwiftUI
/// gesture. The artwork is the bottom layer of the window and the library's
/// scroll view covers the rest of it, so a gesture attached to the artwork
/// never sees a mouse event — the scroll view takes them all first. A monitor
/// sits ahead of the whole responder chain and hands back every event it
/// isn't interested in, which is all of them unless Option is down.
@MainActor
final class SplashPan: ObservableObject {
    /// The crop's position as a fraction of how far it can travel on each
    /// axis: -1 is hard against one edge, 0 centred, 1 against the other.
    /// A fraction rather than points, so the painting keeps its framing when
    /// the window is resized.
    @Published private(set) var x: Double
    @Published private(set) var y: Double

    /// How far the crop can move, in points. Set by the view, which is where
    /// the window size and the artwork size meet.
    var travel: CGSize = .zero

    private weak var window: NSWindow?
    private var monitor: Any?
    /// Non-nil while an option-drag is running: where it began, in window
    /// coordinates, and the framing it started from.
    private var drag: (start: NSPoint, from: CGSize)?

    private static let xKey = "splashPanX"
    private static let yKey = "splashPanY"

    init() {
        x = UserDefaults.standard.double(forKey: Self.xKey)
        y = UserDefaults.standard.double(forKey: Self.yKey)
    }

    /// How far the crop can move on each axis before it runs off the edge of
    /// the painting: half of whatever `scaledToFill` spills over the frame.
    static func travel(for image: CGSize, in frame: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0,
              frame.width > 0, frame.height > 0 else { return .zero }
        let scale = max(frame.width / image.width, frame.height / image.height)
        return CGSize(width: max(0, (image.width * scale - frame.width) / 2),
                      height: max(0, (image.height * scale - frame.height) / 2))
    }

    // MARK: - The drag

    func watch(_ window: NSWindow) {
        self.window = window
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            // A local monitor is only ever called on the main thread. The
            // answer crosses back as a Bool because `NSEvent` isn't Sendable.
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// True when the event belongs to a pan and the rest of the app should
    /// never see it.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard event.modifierFlags.contains(.option),
                  let window, event.window === window,
                  // Below the title bar: the traffic lights and the toolbar
                  // are AppKit's, and it has its own uses for Option there.
                  let content = window.contentView,
                  content.bounds.contains(content.convert(event.locationInWindow, from: nil))
            else { return false }
            drag = (event.locationInWindow, CGSize(width: x, height: y))
            return true

        case .leftMouseDragged:
            guard let drag else { return false }
            // Window coordinates count upwards, the image's offset downwards.
            move(by: CGSize(width: event.locationInWindow.x - drag.start.x,
                            height: drag.start.y - event.locationInWindow.y),
                 from: drag.from)
            return true

        case .leftMouseUp:
            guard drag != nil else { return false }
            drag = nil
            return true

        default:
            return false
        }
    }

    /// Every event of a drag is measured from where that drag began and saved
    /// as it goes, so a drag that never reports its end still leaves the
    /// painting where you put it.
    private func move(by translation: CGSize, from origin: CGSize) {
        if travel.width > 0 {
            x = clamp(origin.width * travel.width + translation.width, to: travel.width)
                / travel.width
            UserDefaults.standard.set(x, forKey: Self.xKey)
        }
        if travel.height > 0 {
            y = clamp(origin.height * travel.height + translation.height, to: travel.height)
                / travel.height
            UserDefaults.standard.set(y, forKey: Self.yKey)
        }
    }

    private func clamp(_ value: CGFloat, to limit: CGFloat) -> CGFloat {
        min(limit, max(-limit, value))
    }
}
