import SwiftCrossUI
#if os(macOS)
import AppKit
import AppKitBackend
#endif

/// Per-platform window chrome.
///
/// The two desktops disagree about where a window title belongs, and following
/// each one is what keeps the app from looking transplanted:
///
///   * macOS — the modern idiom is a transparent, full-size-content title bar
///     with the traffic lights floating over the app's own header. The native
///     title is hidden and drawn by us, so there is no separated grey strip.
///   * GNOME — the header bar *is* the native idiom, and it already shows the
///     title. We leave it alone and draw only our actions, so nothing is
///     duplicated.
enum WindowChrome {
    /// Whether the header row should render the window title itself.
    /// True only where we've hidden the system's own.
    static var drawsOwnTitle: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Space reserved at the leading edge for the traffic lights, which sit on
    /// top of our content once the title bar goes full-size.
    static var trafficLightInset: Int {
        #if os(macOS)
        return 62
        #else
        return 0
        #endif
    }
}

extension View {
    /// Applies the unified title bar on macOS; a no-op elsewhere.
    func unifiedTitleBar() -> some View {
        #if os(macOS)
        return overlay { NSWindowConfigurator() }
        #else
        return self
        #endif
    }
}

#if os(macOS)
/// Reaches the underlying `NSWindow` to apply chrome settings SwiftCrossUI
/// exposes no API for. Zero-sized and non-interactive — it exists only for the
/// side effect.
private struct NSWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ConfiguringView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> ViewSize {
        // Take up no space, so the overlay can't affect the layout of the
        // window it is configuring.
        .zero
    }
}

/// Applies the configuration once the view has actually been placed in a
/// window. `viewDidMoveToWindow` is the earliest reliable point — at
/// `makeNSView` time there is no window to configure yet.
private final class ConfiguringView: NSView {
    private var configured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !configured, let window else { return }
        configured = true

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        // The title still exists for Mission Control and the Window menu; it
        // is only hidden from the title bar, where we draw it ourselves.
        window.titleVisibility = .hidden

        // Without this a control adopts first-responder status at launch and
        // renders a focus ring — the blue rectangle around the refresh button.
        window.makeFirstResponder(nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
