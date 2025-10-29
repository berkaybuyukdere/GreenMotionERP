import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var seciliTab = 0
    @State private var launchScreenGoster = true
    @State private var navigateToVehicleId: UUID?
    
    // Badge states - tracks whether badges have been cleared
    @State private var dashboardBadgeCleared = false
    @State private var vehiclesBadgeCleared = false
    @State private var reportBadgeCleared = false
    
    var body: some View {
        ZStack {
            TabView(selection: $seciliTab) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(0)
                
                AracListesiView(navigateToVehicleId: $navigateToVehicleId)
                    .tabItem {
                        Label("Vehicles", systemImage: "car.fill")
                    }
                    .tag(1)
                
                ScannerView(selectedTab: $seciliTab, navigateToVehicleId: $navigateToVehicleId)
                    .tabItem {
                        Label("Scan", systemImage: "qrcode.viewfinder")
                    }
                    .tag(2)
                
                ShuttleMapView()
                    .tabItem {
                        Label("Shuttle", systemImage: "bus.fill")
                    }
                    .tag(3)
                
                RaporView()
                    .tabItem {
                        Label("Report", systemImage: "doc.text.fill")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
            .onChange(of: seciliTab) { oldTab, newTab in
                // Clear badges when tabs are visited
                switch newTab {
                case 0: // Dashboard
                    if !dashboardBadgeCleared && viewModel.damagedCarsCount > 0 {
                        dashboardBadgeCleared = true
                    }
                case 1: // Vehicles
                    if !vehiclesBadgeCleared && viewModel.damagedCarsCount > 0 {
                        vehiclesBadgeCleared = true
                    }
                case 4: // Report
                    if !reportBadgeCleared && viewModel.aktifServisSayisi > 0 {
                        reportBadgeCleared = true
                    }
                default:
                    break
                }
            }
            
            if launchScreenGoster {
                LaunchScreenView(gosteriliyor: $launchScreenGoster)
                    .transition(.opacity)
            }
        }
        .toastView() // Toast notification support
        // iPad'de de iPhone benzeri tek-kolonu zorlamak için
        // tüm alt görünümlere "compact" yatay size class yayıyoruz.
        // (Sidebar davranışını engeller; NavigationView'lar stack gibi çalışır.)
        .environment(\.horizontalSizeClass, .compact)
    }
}
