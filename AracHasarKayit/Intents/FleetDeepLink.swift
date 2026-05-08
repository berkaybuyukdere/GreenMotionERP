import Foundation

/// Deep links from widgets / App Intents → main `TabView` selection via `UserDefaults`.
enum FleetDeepLink {
    private static let tabKey = "fleetDeepLinkPendingTab"
    private static let hasPendingKey = "fleetDeepLinkHasPending"
    private static let notification = Notification.Name("FleetDeepLinkPendingTab")

    /// Tab indices match `ContentView` (`Operations` = 3 when enabled).
    static func requestTab(_ tab: Int) {
        UserDefaults.standard.set(true, forKey: hasPendingKey)
        UserDefaults.standard.set(tab, forKey: tabKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func requestOperationsTab() {
        requestTab(3)
    }

    static func requestScanTab() {
        requestTab(2)
    }

    static func consumePendingTab() -> Int? {
        guard UserDefaults.standard.bool(forKey: hasPendingKey) else { return nil }
        UserDefaults.standard.set(false, forKey: hasPendingKey)
        return UserDefaults.standard.integer(forKey: tabKey)
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
