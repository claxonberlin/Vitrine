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
    private var lastSweep = Date.distantPast

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !configured, let window else { return }
        configured = true

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        // The title still exists for Mission Control and the Window menu; it
        // is only hidden from the title bar, where we draw it ourselves.
        window.titleVisibility = .hidden

        // An empty toolbar in compact style is what makes the traffic lights
        // line up with our header. AppKit only vertically centres them when a
        // toolbar gives the title bar its taller layout; without one they stay
        // pinned near the top of a 28pt bar and sit noticeably high against a
        // 38pt header row.
        window.toolbar = NSToolbar(identifier: "app.vitrine.chrome")
        window.toolbarStyle = .unifiedCompact

        clearButtonFocus(in: window)
        // The initial first responder is assigned after this runs, so clearing
        // once here isn't enough.
        DispatchQueue.main.async { clearButtonFocus(in: window) }
        // Buttons created later — every catalogue row arrives after the fetch
        // — need the same treatment, so sweep as the window updates.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        // Selector-based rather than closure-based: the observer is removed
        // automatically when this view is deallocated, and the callback lands
        // on NSView's main-actor isolation without a Sendable dance.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        clearButtonFocus(in: window)
    }

    /// didUpdate fires on every event-loop pass that touches the window, so
    /// the sweep is throttled; the view tree is small enough that twice a
    /// second is imperceptible.
    @objc private func windowDidUpdate(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSweep) > 0.5 else { return }
        lastSweep = now
        clearButtonFocus(in: window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Suppresses the blue focus ring on buttons.
///
/// Clearing the first responder alone wasn't enough: AppKit hands focus back
/// the moment a button is *clicked*, and the ring then persists — which is why
/// the "+" stayed lit after opening the file dialog. Setting `focusRingType`
/// to none on the controls themselves removes the artifact at the source.
///
/// Text fields are left alone so the settings sheet still shows where typing
/// goes. Keyboard focus itself is untouched: only the ring is suppressed, so
/// tabbing between controls still works.
@MainActor
private func clearButtonFocus(in window: NSWindow) {
    // focusRingType is declared on NSView, not NSControl, and the ring is
    // drawn by whichever view in the chain claims it — restricting the sweep
    // to NSControl left the ring on the button's wrapper.
    func sweep(_ view: NSView) {
        if !(view is NSTextField) && !(view is NSTextView) {
            view.focusRingType = .none
        }
        view.subviews.forEach(sweep)
    }
    if let content = window.contentView { sweep(content) }

    if let focused = window.firstResponder as? NSControl, !(focused is NSTextField) {
        window.makeFirstResponder(nil)
    }
}
#endif
