import Foundation
import FirebaseAuth

/// Forces explicit country + franchise selection after each app store update.
enum AppSessionGate {
    private static let lastBuildKey = "appLastLaunchedBuildIdentity"
    private static let requiresFreshLoginKey = "requiresFreshLoginSelection"

    static var requiresFreshLoginSelection: Bool {
        get { UserDefaults.standard.bool(forKey: requiresFreshLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: requiresFreshLoginKey) }
    }

    /// Call once during app launch (after `FirebaseApp.configure()`).
    static func enforceFreshLoginIfAppUpdated() {
        let current = currentBuildIdentity()
        let previous = UserDefaults.standard.string(forKey: lastBuildKey)
        UserDefaults.standard.set(current, forKey: lastBuildKey)

        guard let previous, previous != current else { return }

        requiresFreshLoginSelection = true
        clearLoginBranchPreferences()
        try? Auth.auth().signOut()
        LogManager.shared.info("App updated (\(previous) → \(current)): fresh login required")
    }

    static func markFreshLoginCompleted() {
        requiresFreshLoginSelection = false
    }

    static func clearLoginBranchPreferences() {
        UserDefaults.standard.loginSelectedFranchiseId = nil
        UserDefaults.standard.removeObject(forKey: "loginSelectedFranchiseId")
        for code in ["CH", "DE", "TR", "UK", "AT", "FR"] {
            UserDefaults.standard.removeObject(forKey: "loginSelectedFranchiseId_\(code)")
        }
        UserDefaults.standard.removeObject(forKey: "selectedCountryId")
    }

    private static func currentBuildIdentity() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version)(\(build))"
    }
}
