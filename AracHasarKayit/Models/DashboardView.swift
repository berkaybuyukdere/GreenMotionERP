import SwiftUI
import Charts

// Wrapper for OfficeOperationDetailView to use in NavigationLink
struct OfficeOperationDetailViewWrapper: View {
    let operation: OfficeOperation
    @EnvironmentObject var viewModel: AracViewModel
    
    var body: some View {
        OfficeOperationDetailView(operation: operation)
            .environmentObject(viewModel)
    }
}

struct DashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var localization: LocalizationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var navigateToVehicleId: UUID?
    @State private var isRefreshingActivities = false
    @State private var showAnnouncementsHub = false
    @State private var announcementsInitialSegment = 0
    @ObservedObject private var announcementStore = AnnouncementStore.shared
    @ObservedObject private var fleetStatusStore = WheelSysVehicleFleetStatusStore.shared
    
    /// Admin panel: franchise `admin` or platform elevated operators.
    private var isAdminUser: Bool {
        authManager.userProfile?.canAccessFranchiseAdminPanel == true
    }

    private var activeCountry: Country {
        SessionCountryResolver.activeCountry(userProfile: authManager.userProfile)
    }

    private var isSwitzerlandContext: Bool {
        Self.resolveSwitzerlandContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: activeCountry.countryCode
        )
    }

    private var isWheelSysCHDashboard: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private static func resolveSwitzerlandContext(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        let serviceId = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if serviceId.hasPrefix("CH") { return true }
        if let profile = userProfile {
            let pid = profile.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if pid.hasPrefix("CH") { return true }
            let cc = profile.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if cc == "CH" { return true }
        }
        return fallbackCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CH"
    }

    private var parkedVehiclesCount: Int {
        viewModel.exitIslemleri.filter { $0.status == .parked }.count
    }

    private var parkedVehiclesSparkline: [Double] {
        let current = Double(parkedVehiclesCount)
        return [max(0, current - 2), max(0, current - 1), current, current, current + 0.2, current, current]
    }

    private var announcementsEnabled: Bool {
        FranchiseCapabilityMatrix.announcementsEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: activeCountry.countryCode
        )
    }

    /// Show U-Save mark beside flag when franchise branding is U-Save (e.g. Sabiha).
    private var franchiseLineShowsUSaveLogo: Bool {
        let fid = FirebaseService.shared.currentFranchiseId.uppercased()
        let name = viewModel.franchiseName.lowercased()
        if name.contains("u-save") || name.contains("usave") { return true }
        if fid.contains("SABIHA") || fid.contains("SAW") { return true }
        return false
    }

    private var dashboardFranchiseSubtitle: String {
        let raw = viewModel.franchiseName.isEmpty ? activeCountry.name : viewModel.franchiseName
        guard franchiseLineShowsUSaveLogo else { return raw }
        var s = raw
        for token in ["U-Save ", "USave ", "u-save ", "usave "] {
            s = s.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }

    private var greetingHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if let profile = authManager.userProfile {
                    if isWheelSysCHDashboard {
                        Text(String(format: "Hello, %@".localized, profile.displayName))
                            .font(PalantirTheme.heroFont(18))
                            .foregroundStyle(PalantirTheme.textPrimary)
                    } else {
                        Text(String(format: "Hello, %@".localized, profile.displayName))
                            .font(.title3.weight(.bold))
                            .foregroundColor(.primary)
                    }
                }
                HStack(spacing: 6) {
                    Text(activeCountry.flag)
                        .font(.system(size: 14))
                    if franchiseLineShowsUSaveLogo {
                        USaveMiniLogoView(size: CGSize(width: 72, height: 26))
                    }
                    Text(dashboardFranchiseSubtitle)
                        .font(isWheelSysCHDashboard ? PalantirTheme.bodyFont(13) : .subheadline)
                        .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textMuted : .secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var topStatisticsGrid: some View {
        if isWheelSysCHDashboard {
            chPalantirStatisticsGrid
        } else {
            legacyStatisticsGrid
        }
    }

    private var legacyStatisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            NavigationLink(destination: DamageReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                DashboardKartWithMetric(
                    baslik: "Today's Damage Reports".localized,
                    deger: "\(viewModel.todayDamageReportsCount)",
                    ikon: "exclamationmark.triangle.fill",
                    renk: .orange,
                    metric: viewModel.damageReportsChangeMetric,
                    sparkData: viewModel.damageSparkline
                )
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    AnalyticsManager.shared.trackButtonTap(
                        action: "view_damage_reports",
                        screen: "dashboard",
                        buttonLabel: "Today's Damage Reports"
                    )
                }
            )

            NavigationLink(destination: ExitReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                DashboardKart(
                    baslik: "Today's Check Outs".localized,
                    deger: "\(viewModel.todayExitCount)",
                    ikon: "arrow.right.circle.fill",
                    renk: .blue,
                    sparkData: viewModel.exitSparkline
                )
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    AnalyticsManager.shared.trackButtonTap(
                        action: "view_exit_reports",
                        screen: "dashboard",
                        buttonLabel: "Check Out Count"
                    )
                }
            )

            NavigationLink(destination: ReturnReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                DashboardKart(
                    baslik: "Today's Returns".localized,
                    deger: "\(viewModel.todayReturnsCount)",
                    ikon: "arrow.uturn.backward.circle.fill",
                    renk: .purple,
                    sparkData: viewModel.returnSparkline
                )
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    AnalyticsManager.shared.trackButtonTap(
                        action: "view_return_reports",
                        screen: "dashboard",
                        buttonLabel: "Today's Returns"
                    )
                }
            )

            NavigationLink(destination: ParkedCheckoutsListView()
                .environmentObject(viewModel)
                .environmentObject(authManager)
            ) {
                DashboardKart(
                    baslik: "Parked Vehicles".localized,
                    deger: "\(parkedVehiclesCount)",
                    ikon: "car.circle.fill",
                    renk: .pink,
                    sparkData: parkedVehiclesSparkline
                )
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    AnalyticsManager.shared.trackButtonTap(
                        action: "view_parked_vehicles",
                        screen: "dashboard",
                        buttonLabel: "Parked Vehicles"
                    )
                }
            )
        }
        .padding(.horizontal)
    }

    private var chPalantirStatisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
            NavigationLink(destination: DamageReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                chPalantirStatTile(
                    title: "Today's Damage Reports".localized,
                    value: "\(viewModel.todayDamageReportsCount)",
                    icon: "exclamationmark.triangle.fill",
                    tint: PalantirTheme.warning,
                    delta: viewModel.damageReportsChangeMetric,
                    sparkData: viewModel.damageSparkline
                )
            }
            .buttonStyle(.plain)
            NavigationLink(destination: ExitReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                chPalantirStatTile(
                    title: "Today's Check Outs".localized,
                    value: "\(viewModel.todayExitCount)",
                    icon: "arrow.right.circle.fill",
                    tint: PalantirTheme.accent,
                    delta: viewModel.exitCountChangeMetric,
                    sparkData: viewModel.exitSparkline
                )
            }
            .buttonStyle(.plain)
            NavigationLink(destination: ReturnReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                chPalantirStatTile(
                    title: "Today's Returns".localized,
                    value: "\(viewModel.todayReturnsCount)",
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: PalantirTheme.success,
                    delta: viewModel.returnCountChangeMetric,
                    sparkData: viewModel.returnSparkline
                )
            }
            .buttonStyle(.plain)
            NavigationLink(destination: ParkedCheckoutsListView().environmentObject(viewModel).environmentObject(authManager)) {
                chPalantirStatTile(
                    title: "Parked Vehicles".localized,
                    value: "\(parkedVehiclesCount)",
                    icon: "car.circle.fill",
                    tint: PalantirTheme.purple,
                    delta: "",
                    sparkData: parkedVehiclesSparkline
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func chPalantirStatTile(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        delta: String = "",
        sparkData: [Double] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if !delta.isEmpty, delta != "0" {
                    Text(delta)
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(delta.hasPrefix("+") ? PalantirTheme.success : (delta.hasPrefix("-") ? PalantirTheme.critical : PalantirTheme.textMuted))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PalantirTheme.surfaceHigh)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
            }
            if sparkData.count > 1 {
                SparklineChart(data: sparkData, color: tint)
                    .frame(height: 44)
            }
            Text(value)
                .font(PalantirTheme.heroFont(28))
                .foregroundStyle(PalantirTheme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private var dashboardCommunicationsRow: some View {
        HStack(spacing: 12) {
            Button {
                announcementsInitialSegment = 0
                showAnnouncementsHub = true
                announcementStore.startListening()
            } label: {
                dashboardCommButton(
                    title: "Announcements".localized,
                    icon: "megaphone.fill",
                    color: .purple
                )
            }
            .buttonStyle(.plain)

            Button {
                announcementsInitialSegment = 1
                showAnnouncementsHub = true
                announcementStore.startListening()
            } label: {
                dashboardCommButton(
                    title: "announcements.tab.chat".localized,
                    icon: "message.fill",
                    color: MessagesTheme.iosBlue
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func dashboardCommButton(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.accent : color)
            Text(title)
                .font(isWheelSysCHDashboard ? PalantirTheme.labelFont(12) : .subheadline.weight(.semibold))
                .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textPrimary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(isWheelSysCHDashboard ? PalantirTheme.surface : Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
            if isWheelSysCHDashboard {
                Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isWheelSysCHDashboard ? 0 : 16, style: .continuous))
    }

    @ViewBuilder
    private var dashboardFleetCategoriesSection: some View {
        if isWheelSysCHDashboard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vehicles".localized)
                    .font(PalantirTheme.labelFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .textCase(.uppercase)
                    .padding(.horizontal)

                HStack(spacing: 6) {
                    ForEach([VehicleFleetOpsFilter.ntr, .available, .rental, .parking]) { filter in
                        dashboardFleetCategoryChip(filter)
                    }
                }
                .padding(.horizontal)
            }
            .task(id: viewModel.araclar.count) {
                await refreshDashboardFleetCounts()
            }
        }
    }

    private func dashboardFleetCategoryChip(_ filter: VehicleFleetOpsFilter) -> some View {
        let count = fleetStatusStore.filterCounts[filter] ?? 0
        let accent: Color = {
            switch filter {
            case .ntr: return PalantirTheme.warning
            case .available: return PalantirTheme.success
            case .rental: return Color(red: 0.427, green: 0.365, blue: 0.988)
            case .parking: return Color.pink
            default: return PalantirTheme.accent
            }
        }()
        return Button {
            HapticManager.shared.selection()
            FleetDeepLink.requestVehiclesTab(fleetFilter: filter)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: filter.iconName)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 11, height: 11)
                    Text(filter.titleKey.localized)
                        .font(PalantirTheme.labelFont(9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                Text("\(count)")
                    .font(PalantirTheme.dataFont(11))
                    .monospacedDigit()
                    .frame(minWidth: 20)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(accent)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshDashboardFleetCounts() async {
        await fleetStatusStore.refreshIfNeeded()
        let parked = Set(
            viewModel.exitIslemleri
                .filter { $0.status == .parked && !$0.isDeleted }
                .map(\.aracId)
        )
        let inProgress = Set(
            viewModel.exitIslemleri
                .filter { $0.status == .inProgress && !$0.isDeleted }
                .map(\.aracId)
        )
        let openCheckout = parked.union(inProgress)
        fleetStatusStore.updateFilterCounts(
            araclar: viewModel.araclar,
            parkedVehicleIds: parked,
            openCheckoutVehicleIds: openCheckout,
            inProgressCheckoutVehicleIds: inProgress
        )
    }

    var body: some View {
        NavigationView {
            dashboardScrollView
                .navigationTitle("Dashboard".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { dashboardSettingsToolbar }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(authManager)
                        .environmentObject(localization)
                }
                .fullScreenCover(isPresented: $showAnnouncementsHub) {
                    AnnouncementsHubView(initialSegment: announcementsInitialSegment)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
                .background { dashboardHiddenNavigationLinks }
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: isWheelSysCHDashboard))
    }

    @ToolbarContentBuilder
    private var dashboardSettingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.accent : .blue)
            }
        }
    }

    private var dashboardScrollView: some View {
        ScrollView {
            Color.clear
                .onAppear {
                    AnalyticsManager.shared.trackScreenView("Dashboard", screenClass: "DashboardView")
                }
                .onDisappear {
                    AnalyticsManager.shared.trackScreenExit("Dashboard")
                }
            dashboardMainContent
                .padding(.vertical)
        }
    }

    private var dashboardMainContent: some View {
        VStack(spacing: 20) {
            greetingHeader
            topStatisticsGrid
            dashboardFleetCategoriesSection
            if announcementsEnabled {
                dashboardCommunicationsRow
            }
            dashboardRecentActivitiesSection
            if isAdminUser {
                NavigationLink(destination: AdminPanelView()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)) {
                    AdminPanelCard()
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
            if viewModel.araclar.isEmpty {
                dashboardEmptyState
            }
        }
    }

    private var dashboardRecentActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activities".localized)
                    .font(isWheelSysCHDashboard ? PalantirTheme.labelFont(12) : .headline)
                    .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textPrimary : .primary)
                Spacer()
                Button {
                    guard !isRefreshingActivities else { return }
                    isRefreshingActivities = true
                    viewModel.activitiesYukle {
                        isRefreshingActivities = false
                    }
                } label: {
                    Group {
                        if isRefreshingActivities {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.accent : .blue)
                        }
                    }
                    .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                NavigationLink(destination: ActivityView().environmentObject(authManager)) {
                    Text("View All".localized)
                        .font(.caption)
                        .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.accent : .blue)
                }
            }
            .padding(.horizontal)

            if viewModel.activities.isEmpty {
                Text("No activities yet. Tap refresh to load from the server.".localized)
                    .font(.subheadline)
                    .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textMuted : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(isWheelSysCHDashboard ? PalantirTheme.surface : Color.gray.opacity(0.05))
                    .overlay {
                        if isWheelSysCHDashboard {
                            Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                        }
                    }
                    .cornerRadius(isWheelSysCHDashboard ? 0 : 16)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.activities.prefix(8))) { activity in
                        Button {
                            navigateToActivity(activity)
                        } label: {
                            ModernActivityRow(activity: activity)
                        }
                        .buttonStyle(PlainButtonStyle())
                        if activity.id != viewModel.activities.prefix(8).last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(isWheelSysCHDashboard ? PalantirTheme.surface : Color.gray.opacity(0.05))
                .overlay {
                    if isWheelSysCHDashboard {
                        Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                    }
                }
                .cornerRadius(isWheelSysCHDashboard ? 0 : 16)
                .padding(.horizontal)
            }
        }
    }

    private var dashboardEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 80))
                .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textMuted : Color.gray.opacity(0.5))
            Text("No Data Yet".localized)
                .font(.title2)
                .fontWeight(.bold)
            Text("Start adding vehicles and your data will appear here".localized)
                .font(.subheadline)
                .foregroundStyle(isWheelSysCHDashboard ? PalantirTheme.textMuted : .secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var dashboardHiddenNavigationLinks: some View {
        NavigationLink(
            destination: selectedArac.map { AracDetayView(arac: $0) },
            isActive: $navigateToVehicleDetail,
            label: { EmptyView() }
        )
        if let operation = selectedOfficeOperation {
            NavigationLink(
                destination: OfficeOperationDetailViewWrapper(operation: operation)
                    .environmentObject(viewModel),
                isActive: $navigateToOfficeOperation,
                label: { EmptyView() }
            )
        }
    }
    
    // MARK: - Navigation Helper
    @State private var selectedOfficeOperation: OfficeOperation?
    @State private var navigateToOfficeOperation = false
    
    private func navigateToActivity(_ activity: Activity) {
        // Check if it's an office operation
        if activity.tip == .officeOperation, let operationId = activity.officeOperationId {
            if let operation = viewModel.officeOperations.first(where: { $0.id == operationId }) {
                selectedOfficeOperation = operation
                navigateToOfficeOperation = true
                return
            }
        }
        
        // Otherwise, find the related vehicle
        if let plate = activity.aracPlaka {
            if let arac = viewModel.araclar.first(where: { $0.plaka == plate || $0.plakaFormatli == plate }) {
                selectedArac = arac
                navigateToVehicleDetail = true
            }
        }
    }
}

// MARK: - Modern Category Card
struct ModernKategoriKart: View {
    let kategori: String
    let aracSayisi: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Spacer()
            }
            
            Text(kategori)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
            
            HStack(spacing: 4) {
                Text("\(aracSayisi)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("araç".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 100, height: 110)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Modern Activity Row
struct ModernActivityRow: View {
    let activity: Activity
    @Environment(\.palantirModeEnabled) private var palantirMode
    
    var body: some View {
        HStack(spacing: 14) {
            if palantirMode {
                PalantirOpsIconTile(systemName: activity.tip.icon, tint: activity.tip.color, size: 44)
            } else {
                ZStack {
                    Circle()
                        .fill(activity.tip.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: activity.tip.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(activity.tip.color)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.tip.englishDisplayName)
                        .font(palantirMode ? PalantirTheme.labelFont(12) : .subheadline)
                        .fontWeight(palantirMode ? nil : .semibold)
                        .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : Color.primary)
                    
                    if let kullaniciAdi = activity.kullaniciAdi?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !kullaniciAdi.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                        Text(kullaniciAdi)
                            .font(palantirMode ? PalantirTheme.dataFont(10) : .caption)
                            .foregroundStyle(palantirMode ? PalantirTheme.accent : Color.blue)
                    } else if let kullaniciEmail = activity.kullaniciEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !kullaniciEmail.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                        Text(kullaniciEmail.components(separatedBy: "@").first ?? kullaniciEmail)
                            .font(palantirMode ? PalantirTheme.dataFont(10) : .caption)
                            .foregroundStyle(palantirMode ? PalantirTheme.accent : Color.blue)
                    }
                }
                
                Text(activity.localizedDescription)
                    .font(palantirMode ? PalantirTheme.bodyFont(11) : .caption)
                    .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                    .lineLimit(2)

                if palantirMode, let plaka = activity.aracPlaka {
                    PalantirOpsBadge(text: plaka, tone: .accent)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatRelativeTime(activity.tarih))
                    .font(palantirMode ? PalantirTheme.dataFont(10) : .caption2)
                    .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(palantirMode ? PalantirTheme.textMuted.opacity(0.6) : Color.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "Just now".localized
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(format: "%d min ago".localized, minutes)
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return String(format: "%d hours ago".localized, hours)
        } else {
            let days = Int(seconds / 86400)
            if days == 1 {
                return "Yesterday".localized
            } else if days < 7 {
                return String(format: "%d days ago".localized, days)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
}

// MARK: - Mini Sparkline Chart (iOS Stocks style)
struct SparklineChart: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = normalised(in: geo.size)
            ZStack {
                // Fill gradient under the line
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        p.addLine(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Line
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalised(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let minV = data.min() ?? 0
        let maxV = data.max() ?? 1
        let span = maxV - minV == 0 ? 1.0 : maxV - minV
        return data.enumerated().map { idx, v in
            let x = CGFloat(idx) / CGFloat(data.count - 1) * size.width
            let y = size.height - CGFloat((v - minV) / span) * size.height * 0.85 - size.height * 0.08
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Dashboard Card
struct DashboardKart: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    var sparkData: [Double] = []
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2)
                    .foregroundColor(renk)
                Spacer()
            }

            if sparkData.count > 1 {
                SparklineChart(data: sparkData, color: renk)
                    .frame(height: 36)
            }
            
            Text(deger)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.primary)
            
            Text(baslik)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeSurface(cornerRadius: 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Dashboard Card with Metric
struct DashboardKartWithMetric: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    let metric: String
    var sparkData: [Double] = []
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2)
                    .foregroundColor(renk)
                Spacer()
                if !metric.isEmpty && metric != "0" {
                    Text(metric)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(metric.hasPrefix("+") ? .green : metric.hasPrefix("-") ? .red : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((metric.hasPrefix("+") ? Color.green : metric.hasPrefix("-") ? Color.red : Color.gray).opacity(0.1))
                        .cornerRadius(8)
                }
            }

            if sparkData.count > 1 {
                SparklineChart(data: sparkData, color: renk)
                    .frame(height: 36)
            }
            
            Text(deger)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.primary)
            
            Text(baslik)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeSurface(cornerRadius: 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Service Status Bar
struct ServisDurumBar: View {
    let baslik: String
    let sayi: Int
    let toplam: Int
    let renk: Color
    
    var yuzde: Double {
        toplam > 0 ? Double(sayi) / Double(toplam) : 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(baslik)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(sayi)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(renk)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(renk)
                        .frame(width: geometry.size.width * yuzde, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Admin Panel Card
struct AdminPanelCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Panel".localized)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Firebase Connection Tests".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                )
        )
        .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
