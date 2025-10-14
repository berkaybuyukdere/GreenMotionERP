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
                        Label("AraÃ§lar", systemImage: "car.fill")
                    }
                    .tag(1)
                
                ScannerView()
                    .tabItem {
                        Label("Tarama", systemImage: "qrcode.viewfinder")
                    }
                    .tag(2)
                
                ServisView()
                    .tabItem {
                        Label("Servis", systemImage: "wrench.and.screwdriver.fill")
                    }
                    .tag(3)
                
                RaporView()
                    .tabItem {
                        Label("Rapor", systemImage: "doc.text.fill")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
            
            if launchScreenGoster {
                LaunchScreenView(gosteriliyor: $launchScreenGoster)
                    .transition(.opacity)
            }
        }
    }
}
