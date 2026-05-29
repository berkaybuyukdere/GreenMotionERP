import SwiftUI
import UIKit

/// Global Palantir Foundry preview toggle (Settings → Palantir Mode).
final class PalantirModeManager: ObservableObject {
    static let shared = PalantirModeManager()

    @AppStorage("palantirModeEnabled") var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            applyUIKitChrome(enabled: isEnabled)
            objectWillChange.send()
        }
    }

    private init() {
        applyUIKitChrome(enabled: isEnabled)
    }

    func applyUIKitChrome(enabled: Bool) {
        if enabled {
            PalantirUIKitAppearance.apply()
        } else {
            PalantirUIKitAppearance.reset()
        }
    }
}

// MARK: - Environment

private struct PalantirModeEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var palantirModeEnabled: Bool {
        get { self[PalantirModeEnabledKey.self] }
        set { self[PalantirModeEnabledKey.self] = newValue }
    }
}

// MARK: - UIKit chrome (lists, nav bars, tab bar)

enum PalantirUIKitAppearance {
    private static let navBg = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
    private static let canvasBg = UIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1)
    private static let surfaceBg = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
    private static let border = UIColor(red: 0.19, green: 0.21, blue: 0.24, alpha: 1)
    private static let accent = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1)
    private static let text = UIColor(red: 0.79, green: 0.82, blue: 0.85, alpha: 1)

    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = navBg
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        nav.shadowColor = border
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = navBg
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)

        UITableView.appearance().backgroundColor = canvasBg
        UITableViewCell.appearance().backgroundColor = surfaceBg
        UICollectionView.appearance().backgroundColor = canvasBg

        UISearchBar.appearance().barTintColor = navBg
        UISearchBar.appearance().backgroundColor = navBg
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).backgroundColor = surfaceBg

        UISegmentedControl.appearance().selectedSegmentTintColor = accent.withAlphaComponent(0.35)
    }

    static func reset() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = nil

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = nil
        UITabBar.appearance().unselectedItemTintColor = nil

        UITableView.appearance().backgroundColor = nil
        UITableViewCell.appearance().backgroundColor = nil
        UICollectionView.appearance().backgroundColor = nil

        UISearchBar.appearance().barTintColor = nil
        UISearchBar.appearance().backgroundColor = nil
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).backgroundColor = nil

        UISegmentedControl.appearance().selectedSegmentTintColor = nil
    }
}
