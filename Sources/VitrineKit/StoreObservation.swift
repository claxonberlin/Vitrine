import Foundation

extension BuildStore {

    /// Calls `handler` after any observable property changes.
    ///
    /// This is the store's whole contract with a UI layer, and it is the same
    /// on both platforms: SwiftUI turns it into an invalidation, Adwaita into
    /// a bumped revision counter. Nothing here knows which.
    ///
    /// The returned token keeps the subscription alive; cancel it, or let it
    /// go out of scope, to stop.
    @discardableResult
    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken()
        observers.append(Observer(token: token, handler: handler))
        return token
    }

    /// Fired by the `didSet` on every published property. Cancelled
    /// subscriptions are swept here rather than on cancellation, so a token
    /// deinit never has to reach back into the store.
    func notify() {
        observers.removeAll { $0.token == nil || $0.token?.isCancelled == true }
        for observer in observers { observer.handler() }
    }
}

/// One subscription. The token is held weakly: when the front end lets go of
/// it, the subscription lapses instead of retaining a dead view's closure.
@MainActor
struct Observer {
    weak var token: ObservationToken?
    let handler: @MainActor () -> Void
}

/// Keeps an `observeChanges` subscription alive. Storing it in the presenting
/// window is enough; releasing it ends the subscription.
public final class ObservationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }

    init() {}
}
