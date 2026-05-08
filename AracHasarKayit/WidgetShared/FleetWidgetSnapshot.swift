import Foundation

/// App group used by the main app and the Fleet widget extension (must match entitlements).
enum FleetWidgetAppGroup {
    static let suiteName = "group.com.greenmotionapp.fleetwidget"
    static let snapshotKey = "fleetWidgetSnapshot.v1"
}

/// JSON-serializable summary written by the app and read by the widget.
struct FleetWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    /// Returns (iade) created today (calendar day, device timezone).
    var returnsTodayCount: Int
    var checkoutsTodayCount: Int
    /// Hasar records dated today (reporting set).
    var damagesTodayCount: Int
    /// Pending returns heuristic: not completed same-day pipeline (optional; 0 if unknown).
    var pendingReturnsCount: Int
    var operationsTabAvailable: Bool

    static let empty = FleetWidgetSnapshot(
        updatedAt: Date(),
        returnsTodayCount: 0,
        checkoutsTodayCount: 0,
        damagesTodayCount: 0,
        pendingReturnsCount: 0,
        operationsTabAvailable: false
    )

    static func loadFromSharedDefaults() -> FleetWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: FleetWidgetAppGroup.suiteName)?.data(forKey: FleetWidgetAppGroup.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FleetWidgetSnapshot.self, from: data)
    }

    func saveToSharedDefaults() {
        guard let enc = try? JSONEncoder().encode(self) else { return }
        let ud = UserDefaults(suiteName: FleetWidgetAppGroup.suiteName)
        ud?.set(enc, forKey: FleetWidgetAppGroup.snapshotKey)
    }
}
