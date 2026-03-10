import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var localization: LocalizationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var seciliTab = 0
    @State private var launchScreenGoster = true
    @State private var navigateToVehicleId: UUID?
    @State private var showOnboarding = false
    
    // Badge states - tracks whether badges have been cleared
    @State private var dashboardBadgeCleared = false
    @State private var vehiclesBadgeCleared = false
    @State private var reportBadgeCleared = false
    
    // Demo banner state
    @StateObject private var demoStatusManager = DemoStatusManager()
    @State private var demoBannerDismissed = false
    
    private var activeCountry: Country {
        if let profile = authManager.userProfile {
            if let byFranchise = CountryManager.country(byId: profile.franchiseId) {
                return byFranchise
            }
            if let byCode = CountryManager.country(byCode: profile.countryCode) {
                return byCode
            }
        }
        return UserDefaults.standard.selectedCountry
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Demo Banner - shown at top if user is demo
                if demoStatusManager.isDemo && !demoBannerDismissed, let days = demoStatusManager.daysRemaining {
                    DemoBannerView(daysRemaining: days) {
                        demoBannerDismissed = true
                    }
                }
                
                HStack(spacing: 6) {
                    Text(activeCountry.flag)
                        .font(.system(size: 12))
                    Text(activeCountry.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                TabView(selection: $seciliTab) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard".localized, systemImage: "chart.bar.fill")
                    }
                    .tag(0)
                
                AracListesiView(navigateToVehicleId: $navigateToVehicleId)
                    .tabItem {
                        Label("Vehicles".localized, systemImage: "car.fill")
                    }
                    .tag(1)
                
                ScannerView(selectedTab: $seciliTab, navigateToVehicleId: $navigateToVehicleId)
                    .tabItem {
                        Label("Scan".localized, systemImage: "qrcode.viewfinder")
                    }
                    .tag(2)
                
                AnalyticsDashboardView()
                    .tabItem {
                        Label("Journal".localized, systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(3)
                
                RaporView()
                    .tabItem {
                        Label("Report".localized, systemImage: "doc.text.fill")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
            .onChange(of: seciliTab) { oldTab, newTab in
                    // Track tab switch
                    let tabNames = ["Dashboard", "Vehicles", "Scan", "Journal", "Report"]
                    let fromTab = oldTab < tabNames.count ? tabNames[oldTab] : "Unknown"
                    let toTab = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
                    
                    AnalyticsManager.shared.trackTabSwitch(
                        fromTab: fromTab,
                        toTab: toTab,
                        tabIndex: newTab
                    )
                    
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
            } // End of VStack
            
            if launchScreenGoster {
                LaunchScreenView(gosteriliyor: $launchScreenGoster)
                    .transition(.opacity)
            }
        }
        .toastView() // Toast notification support
        .tutorialOverlay() // Tutorial overlay support
        .onAppear {
            // Check if onboarding is needed
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showOnboarding = true
                }
            }
            
            // Update demo status from user profile
            if let userProfile = authManager.userProfile {
                demoStatusManager.updateStatus(isDemo: userProfile.effectiveIsTrialUser, expiresAt: userProfile.effectiveTrialEndsAt)
            }
        }
        .onChange(of: authManager.userProfile?.isDemoAccount) { _, newValue in
            // Update demo banner when profile loads (may happen after onAppear)
            if let userProfile = authManager.userProfile {
                demoStatusManager.updateStatus(isDemo: userProfile.effectiveIsTrialUser, expiresAt: userProfile.effectiveTrialEndsAt)
            }
        }
        .onChange(of: authManager.userProfile?.isTrialUser) { _, _ in
            if let userProfile = authManager.userProfile {
                demoStatusManager.updateStatus(isDemo: userProfile.effectiveIsTrialUser, expiresAt: userProfile.effectiveTrialEndsAt)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        // iPad'de de iPhone benzeri tek-kolonu zorlamak için
        // tüm alt görünümlere "compact" yatay size class yayıyoruz.
        // (Sidebar davranışını engeller; NavigationView'lar stack gibi çalışır.)
        .environment(\.horizontalSizeClass, .compact)
        .id(localization.currentLanguage)
    }
}
