import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var seciliTab = 0
    @State private var launchScreenGoster = true
    
    var body: some View {
        ZStack {
            TabView(selection: $seciliTab) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(0)
                
                AracListesiView()
                    .tabItem {
                        Label("Vehicles", systemImage: "car.fill")
                    }
                    .tag(1)
                
                ScannerView()
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
