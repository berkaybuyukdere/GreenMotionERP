import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var localization: LocalizationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var offlineMode = OfflineModeManager.shared
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
    
    private func scheduleDailySummary() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let returns = viewModel.iadeIslemleri.filter { $0.createdAt >= today && $0.createdAt < tomorrow }.count
        let checkouts = viewModel.exitIslemleri.filter { $0.createdAt >= today && $0.createdAt < tomorrow }.count
        let damages = viewModel.allHasarKayitlariForReporting.filter { $0.tarih >= today && $0.tarih < tomorrow }.count
        NotificationManager.shared.scheduleDailySummaryNotification(
            returnsCount: returns,
            checkoutsCount: checkouts,
            damageCount: damages
        )
    }

    private var activeCountry: Country {
        if let profile = authManager.userProfile, profile.isCrossFranchisePlatformOperator {
            return UserDefaults.standard.selectedCountry
        }
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

                if offlineMode.pendingChanges > 0 {
                    HStack(spacing: 8) {
                        if offlineMode.isOnline, offlineMode.isSyncing {
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                        if offlineMode.isOnline {
                            Text(String(format: "Uploading %d saved item(s) from this device…".localized, offlineMode.pendingChanges))
                        } else {
                            Text(String(format: "%d item(s) will upload when you are back online.".localized, offlineMode.pendingChanges))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                }
                
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

                OperationsHubView()
                    .tabItem {
                        Label("Operations".localized, systemImage: "calendar.badge.clock")
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
                    let tabNames = ["Dashboard", "Vehicles", "Scan", "Operations", "Report"]
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
        .inAppNotificationBanner()
        .toastView() // Errors, warnings, offline-only messages (success uses in-app banner)
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

            // Schedule daily summary notification
            scheduleDailySummary()

            OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
        }
        .onChange(of: offlineMode.isOnline) { _, isOnline in
            if isOnline {
                OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
            }
        }
        .onChange(of: viewModel.iadeIslemleri.count) { _, _ in scheduleDailySummary() }
        .onChange(of: viewModel.exitIslemleri.count) { _, _ in scheduleDailySummary() }
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
