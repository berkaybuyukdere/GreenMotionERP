import SwiftUI

struct ScannerView: View {
    @State private var isActive = false
    @Binding var selectedTab: Int
    @Binding var navigateToVehicleId: UUID?
    
    var body: some View {
        NavigationView {
            PlakaScannerView(
                isActive: $isActive,
                selectedTab: $selectedTab,
                navigateToVehicleId: $navigateToVehicleId
            )
            .navigationTitle("Plate Scanner")
            .onAppear {
                                isActive = true
            }
            .onDisappear {
                                isActive = false
            }
        }
    }
}
