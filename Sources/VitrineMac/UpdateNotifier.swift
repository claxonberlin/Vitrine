import AppKit
import UserNotifications
import VitrineKit

/// Posts a notification when a build in the library has an update — once per
/// update, so the hourly refresh doesn't repeat itself.
///
/// Alphas are left out: a daily alpha has a new build every day, and a
/// notification that arrives daily is one people learn to ignore. Their cards
/// still offer the update.
///
/// Checked each time a catalogue fetch finishes, whoever started it — the
/// menu bar's hourly timer or the window opening. The system holds a
/// notification back while the app is frontmost, which is right here: the
/// window is already showing the same update on its card.
@MainActor
final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateNotifier()

    /// Supplied by the app as it starts, like `MenuBarItem.store`.
    var store: BuildStore? {
        didSet { observe() }
    }

    private var token: ObservationToken?
    private var wasFetching = false

    private static let category = "update"
    nonisolated private static let updateAction = "update"
    nonisolated private static let buildKey = "build"
    nonisolated private static let targetKey = "target"

    /// Every update already announced, as "installed id|remote id". Kept
    /// across launches so a relaunch doesn't announce them all again.
    private static let announcedKey = "AnnouncedUpdates"
    private var announced: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.announcedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.announcedKey) }
    }

    /// Called before launch finishes, so a click on a notification that
    /// started the app is delivered here too.
    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let update = UNNotificationAction(identifier: Self.updateAction,
                                          title: NSLocalizedString("Update", comment: ""))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [update],
                                   intentIdentifiers: [])
        ])
    }

    private func observe() {
        token = store?.observeChanges { [weak self] in self?.storeChanged() }
    }

    /// Acts on the moment a fetch ends, not on every change the store makes.
    private func storeChanged() {
        guard let store else { return }
        let fetching = store.isFetching
        defer { wasFetching = fetching }
        if wasFetching && !fetching { announceUpdates(in: store) }
    }

    private func announceUpdates(in store: BuildStore) {
        let fresh = store.installed.compactMap { build -> (InstalledBuild, RemoteBuild)? in
            guard build.riskId != "alpha",
                  !store.isUpdating(build),
                  let target = store.updateAvailable(for: build),
                  target.riskId != "alpha",
                  !announced.contains(Self.key(build, target))
            else { return nil }
            return (build, target)
        }
        guard !fresh.isEmpty else { return }
        announced.formUnion(fresh.map { Self.key($0.0, $0.1) })

        Task {
            let center = UNUserNotificationCenter.current()
            // Asked the first time there is something to say, rather than at
            // launch, so the question arrives with its reason.
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            else { return }
            for (build, target) in fresh {
                try? await center.add(Self.request(for: build, to: target))
            }
        }
    }

    private static func key(_ build: InstalledBuild, _ target: RemoteBuild) -> String {
        "\(build.id.uuidString)|\(target.id)"
    }

    private static func request(for build: InstalledBuild,
                                to target: RemoteBuild) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(format: NSLocalizedString("Blender %@ is available", comment: ""),
                               target.version)
        // A daily's update is often the same version, built again.
        content.body = target.version == build.version
            ? NSLocalizedString("A newer daily build is ready.", comment: "")
            : String(format: NSLocalizedString("Update from %@.", comment: ""), build.version)
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = [buildKey: build.id.uuidString, targetKey: target.id]
        return UNNotificationRequest(identifier: key(build, target), content: content,
                                     trigger: nil)
    }

    // MARK: - Responses

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let buildID = (info[Self.buildKey] as? String).flatMap(UUID.init(uuidString:))
        let targetID = info[Self.targetKey] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            if action == Self.updateAction, let buildID, let targetID {
                update(buildID, to: targetID)
            } else if action == UNNotificationDefaultActionIdentifier {
                MainWindow.shared.show()
            }
        }
    }

    /// Only if that update is still the one on offer: the catalogue may
    /// have moved on, or the build been updated from the window, since the
    /// notification went out.
    private func update(_ buildID: UUID, to targetID: String) {
        guard let store,
              let build = store.installed.first(where: { $0.id == buildID }),
              let target = store.updateAvailable(for: build),
              target.id == targetID
        else {
            MainWindow.shared.show()
            return
        }
        store.updateInstall(from: build, to: target)
    }
}
