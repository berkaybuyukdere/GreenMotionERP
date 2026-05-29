import Foundation

/// Deep links from widgets / App Intents → main `TabView` selection via `UserDefaults`.
enum FleetDeepLink {
    private static let tabKey = "fleetDeepLinkPendingTab"
    private static let semanticKey = "fleetDeepLinkPendingSemantic"
    private static let hasPendingKey = "fleetDeepLinkHasPending"
    private static let notification = Notification.Name("FleetDeepLinkPendingTab")

    enum Semantic: String {
        case operations
        case scan
        case shuttleMap
    }

    static func requestTab(_ tab: Int) {
        UserDefaults.standard.set(true, forKey: hasPendingKey)
        UserDefaults.standard.set(tab, forKey: tabKey)
        UserDefaults.standard.removeObject(forKey: semanticKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func requestSemantic(_ semantic: Semantic) {
        UserDefaults.standard.set(true, forKey: hasPendingKey)
        UserDefaults.standard.set(semantic.rawValue, forKey: semanticKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func requestOperationsTab() {
        requestSemantic(.operations)
    }

    static func requestScanTab() {
        requestSemantic(.scan)
    }

    static func consumePendingTab(router: MainTabRouter) -> Int? {
        guard UserDefaults.standard.bool(forKey: hasPendingKey) else { return nil }
        UserDefaults.standard.set(false, forKey: hasPendingKey)

        if let semantic = UserDefaults.standard.string(forKey: semanticKey), !semantic.isEmpty {
            UserDefaults.standard.removeObject(forKey: semanticKey)
            switch Semantic(rawValue: semantic) {
            case .operations: return router.operations
            case .scan: return router.scan
            case .shuttleMap: return router.shuttleMap
            case .none: break
            }
        }

        let legacy = UserDefaults.standard.integer(forKey: tabKey)
        UserDefaults.standard.removeObject(forKey: tabKey)
        // Legacy index 3 = Operations when present
        if legacy == 3 { return router.operations ?? legacy }
        return legacy
    }

    static var pendingNotification: Notification.Name { notification }

    static func handleOpenURL(_ url: URL, operationsEnabled: Bool) {
        guard url.scheme?.lowercased() == "erpxtm" else { return }
        switch url.host?.lowercased() {
        case "operations":
            if operationsEnabled { requestOperationsTab() }
        case "returns":
            if operationsEnabled { requestOperationsTab() }
        case "scan":
            requestScanTab()
        default:
            break
        }
    }
}
