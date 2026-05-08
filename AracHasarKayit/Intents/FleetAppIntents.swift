import AppIntents
import Foundation

@available(iOS 16.0, *)
struct OpenFleetOperationsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Operations"
    static var description: IntentDescription = "Jump to the Operations hub."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FleetDeepLink.requestOperationsTab()
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenFleetScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scan"
    static var description: IntentDescription = "Jump to the plate scan tab."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FleetDeepLink.requestScanTab()
        }
        return .result()
    }
}

@available(iOS 17.0, *)
struct FleetAppShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFleetOperationsIntent(),
            phrases: [
                "Open operations in \(.applicationName)",
                "Operations in \(.applicationName)"
            ],
            shortTitle: "Operations",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: OpenFleetScanIntent(),
            phrases: [
                "Open scan in \(.applicationName)",
                "Plate scan in \(.applicationName)"
            ],
            shortTitle: "Scan",
            systemImageName: "qrcode.viewfinder"
        )
    }
}
