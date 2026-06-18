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
    @ObservedObject private var customerEmailSend = CustomerEmailSendCoordinator.shared
    @State private var demoBannerDismissed = false
    
    private func refreshFleetWidgetSnapshot() {
        FleetWidgetSnapshotWriter.publish(
            iadeIslemleri: viewModel.iadeIslemleri,
            exitIslemleri: viewModel.exitIslemleri,
            damageRecords: viewModel.allHasarKayitlariForReporting,
            operationsTabAvailable: operationsEnabledForCurrentFranchise
        )
    }

    private func applyPendingDeepLinkIfNeeded() {
        if isGaragePortalSession {
            seciliTab = min(seciliTab, 1)
            return
        }
        guard let tab = FleetDeepLink.consumePendingTab(router: tabRouter) else { return }
        if tab >= 0, tab <= tabRouter.maxTab {
            seciliTab = tab
        }
    }

    private var activeCountry: Country {
        SessionCountryResolver.activeCountry(userProfile: authManager.userProfile)
    }

    private var operationsEnabledForCurrentFranchise: Bool {
        FranchiseCapabilityMatrix.operationsEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var isGaragePortalSession: Bool {
        authManager.userProfile?.role == .garage
    }

    private var tabRouter: MainTabRouter {
        MainTabRouter.current(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: activeCountry.countryCode
        )
    }

    private var showsCHAdminPanelTab: Bool { tabRouter.showsCHPanel }
    private var showsCHOpsTab: Bool { tabRouter.showsCHOps }
    private var showsShuttleMapTab: Bool { tabRouter.showsShuttleMap }
    
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
                
                Group {
                    if isGaragePortalSession {
                        TabView(selection: $seciliTab) {
                            GaragePortalHubView()
                                .environmentObject(viewModel)
                                .environmentObject(authManager)
                                .tabItem {
                                    Label("garage_portal.nav_title".localized, systemImage: "square.grid.2x2.fill")
                                }
                                .tag(0)

                            SettingsView()
                                .environmentObject(authManager)
                                .environmentObject(localization)
                                .tabItem {
                                    Label("Settings".localized, systemImage: "gearshape.fill")
                                }
                                .tag(1)
                        }
                    } else {
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
                                .tag(tabRouter.scan)

                            if let shuttleTag = tabRouter.shuttleMap {
                                ShuttleMapView()
                                    .tabItem {
                                        Label("shuttle_map.tab".localized, systemImage: "map.fill")
                                    }
                                    .tag(shuttleTag)
                            }

                            if let opsTag = tabRouter.operations {
                                OperationsHubView()
                                    .tabItem {
                                        Label("Operations".localized, systemImage: "calendar.badge.clock")
                                    }
                                    .tag(opsTag)
                            }

                            if let chOpsTag = tabRouter.chOps {
                                WheelSysHubView()
                                    .tabItem {
                                        Label("wheelsys.tab".localized, systemImage: "point.3.connected.trianglepath.dotted")
                                    }
                                    .tag(chOpsTag)
                            }

                            RaporView()
                                .tabItem {
                                    Label("Report".localized, systemImage: "doc.text.fill")
                                }
                                .tag(tabRouter.report)

                            if let panelTag = tabRouter.chPanel {
                                SwitzerlandAdminPanelView()
                                    .tabItem {
                                        Label("ch_panel.tab".localized, systemImage: "gauge.with.dots.needle.67percent")
                                    }
                                    .tag(panelTag)
                            }
                        }
                    }
                }
            .accentColor(.blue)
            .onOpenURL { url in
                FleetDeepLink.handleOpenURL(url, operationsEnabled: operationsEnabledForCurrentFranchise)
                applyPendingDeepLinkIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: FleetDeepLink.pendingNotification)) { _ in
                applyPendingDeepLinkIfNeeded()
            }
            .onChange(of: authManager.userProfile?.role) { _, role in
                if isGaragePortalSession {
                    seciliTab = min(seciliTab, 1)
                }
                if role == .shuttle {
                    ShuttleLocationSharingService.shared.requestLocationPermissionAtLoginIfNeeded(isShuttleRole: true)
                }
            }
            .onChange(of: seciliTab) { oldTab, newTab in
                    func tabLabel(_ tag: Int) -> String {
                        if isGaragePortalSession {
                            switch tag {
                            case 0: return "GarageVehicles"
                            default: return "Unknown"
                            }
                        }
                        let r = tabRouter
                        if tag == r.dashboard { return "Dashboard" }
                        if tag == r.vehicles { return "Vehicles" }
                        if tag == r.scan { return "Scan" }
                        if tag == r.shuttleMap { return "ShuttleMap" }
                        if tag == r.operations { return "Operations" }
                        if tag == r.chOps { return "CHOps" }
                        if tag == r.report { return "Report" }
                        if tag == r.chPanel { return "CHPanel" }
                        return "Unknown"
                    }
                    let fromTab = tabLabel(oldTab)
                    let toTab = tabLabel(newTab)
                    
                    AnalyticsManager.shared.trackTabSwitch(
                        fromTab: fromTab,
                        toTab: toTab,
                        tabIndex: newTab
                    )
                    
                    // Clear badges when tabs are visited
                    switch newTab {
                    case 0: // Dashboard (or garage vehicles-only tab)
                        if !isGaragePortalSession, !dashboardBadgeCleared && viewModel.damagedCarsCount > 0 {
                            dashboardBadgeCleared = true
                        }
                        if isGaragePortalSession, !vehiclesBadgeCleared && viewModel.damagedCarsCount > 0 {
                            vehiclesBadgeCleared = true
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
        .toastView()
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
                if userProfile.role == .shuttle {
                    ShuttleLocationSharingService.shared.requestLocationPermissionAtLoginIfNeeded(isShuttleRole: true)
                }
            }

            refreshFleetWidgetSnapshot()
            applyPendingDeepLinkIfNeeded()

            OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
            NotificationManager.shared.ensureProminentDeliveryOnLaunch()
        }
        .onChange(of: offlineMode.isOnline) { _, isOnline in
            if isOnline {
                OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
                NotificationManager.shared.ensureProminentDeliveryOnLaunch()
                applyPendingDeepLinkIfNeeded()
                refreshFleetWidgetSnapshot()
                if authManager.isAuthenticated {
                    LiveActivityTracker.shared.recordAppForeground(userProfile: authManager.userProfile)
                }
            case .background:
                if customerEmailSend.isActive {
                    customerEmailSend.hideOverlayContinueInBackground()
                }
                ShuttleLocationSharingService.shared.handleAppBackgrounded()
                if authManager.isAuthenticated {
                    LiveActivityTracker.shared.recordAppBackground(userProfile: authManager.userProfile)
                }
            case .inactive:
                if customerEmailSend.isActive {
                    customerEmailSend.hideOverlayContinueInBackground()
                }
                ShuttleLocationSharingService.shared.handleAppBackgrounded()
                if authManager.isAuthenticated {
                    LiveActivityTracker.shared.recordAppInactive(userProfile: authManager.userProfile)
                }
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.iadeIslemleri.count) { _, _ in
            refreshFleetWidgetSnapshot()
        }
        .onChange(of: viewModel.exitIslemleri.count) { _, _ in
            refreshFleetWidgetSnapshot()
        }
        .onChange(of: viewModel.allHasarKayitlariForReporting.count) { _, _ in
            refreshFleetWidgetSnapshot()
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
                .environmentObject(authManager)
        }
        // iPad'de de iPhone benzeri tek-kolonu zorlamak için
        // tüm alt görünümlere "compact" yatay size class yayıyoruz.
        // (Sidebar davranışını engeller; NavigationView'lar stack gibi çalışır.)
        .environment(\.horizontalSizeClass, .compact)
        .id(localization.currentLanguage)
    }
}
