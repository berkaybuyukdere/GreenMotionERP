import SwiftUI

/// Scan tab index in `ContentView` `TabView` (Dashboard=0, Vehicles=1, Scan=2, …).
enum AppTabIndex {
    static let scan = 2
}

struct ScannerView: View {
    @Binding var selectedTab: Int
    @Binding var navigateToVehicleId: UUID?

    private var scanTabSelected: Bool {
        selectedTab == AppTabIndex.scan
    }

    var body: some View {
        PlakaScannerView(
            isActive: Binding(
                get: { scanTabSelected },
                set: { _ in }
            ),
            selectedTab: $selectedTab,
            navigateToVehicleId: $navigateToVehicleId
        )
    }
}
