import SwiftUI
import Charts

/// Switzerland-only admin Panel: operational charts + Jarvis intelligence hub.
struct SwitzerlandAdminPanelView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var localization: LocalizationManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject private var liveFeed = LiveActivityFeedService.shared

    @State private var period: CHPanelPeriod = .weekly
    @State private var showJarvis = false
    @State private var jarvisFleetContext: JarvisFleetDataContext?
    @State private var isPreparingJarvis = false
    @State private var selectedBucket: CHPanelTimeBucket?
    @State private var damageChartSelection: String?
    @State private var revenueChartSelection: String?

    @State private var showCosmosCamera = false

    @State private var analyticsSnapshot: CHPanelAnalyticsSnapshot?
    @State private var chDamagesCache: [HasarKaydi] = []
    @State private var chOfficeCache: [OfficeOperation] = []
    @State private var chTrafficCache: [TrafficAccidentContract] = []

    private let topRowHeight: CGFloat = 300
    private let topRowCompactJarvisMinHeight: CGFloat = 200
    private let topRowCompactLiveMinHeight: CGFloat = 360

    private var usesSideBySideColumns: Bool {
        horizontalSizeClass == .regular
    }

    private var isAdmin: Bool {
        authManager.userProfile?.canAccessFranchiseAdminPanel == true
    }

    private var jarvisEnabled: Bool {
        GroqInsightsService.isEnabledForSwitzerland(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: localization.currentLanguage.rawValue.uppercased() == "DE" ? "DE" : "CH"
        )
    }

    private var snapshot: CHPanelAnalyticsSnapshot {
        analyticsSnapshot
            ?? CHPanelAnalyticsEngine.buildSnapshot(
                period: period,
                damages: chDamagesCache,
                officeOperations: chOfficeCache,
                trafficContracts: chTrafficCache,
                auditLogs: []
            )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isAdmin {
                    panelContent
                } else {
                    accessDenied
                }
            }
            .navigationTitle("ch_panel.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showJarvis) {
                jarvisSheetContent
            }
            .sheet(item: $selectedBucket) { bucket in
                CHPanelBucketDetailSheet(bucket: bucket, period: period)
            }
            .sheet(isPresented: $showCosmosCamera) {
                CosmosVisionCameraView()
                    .environmentObject(viewModel)
            }
            .task { refreshPanelData() }
            .onAppear {
                liveFeed.retainListening()
            }
            .onDisappear {
                liveFeed.releaseListening()
            }
            .onChange(of: period) { _, _ in
                damageChartSelection = nil
                revenueChartSelection = nil
                selectedBucket = nil
                rebuildAnalyticsSnapshot()
            }
        }
    }

    @ViewBuilder
    private var jarvisSheetContent: some View {
        if let jarvisFleetContext {
            CHPanelJarvisSheet(
                fleetContext: jarvisFleetContext,
                languageCode: localization.currentLanguage.rawValue,
                jarvisEnabled: jarvisEnabled
            )
        } else {
            ZStack {
                PalantirTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(PalantirTheme.accent)
                    Text("ch_panel.jarvis_preparing".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            .presentationDetents([.large])
        }
    }

    private var panelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topOperationsRow
                CHPanelCosmosCameraCard {
                    showCosmosCamera = true
                }
                periodPicker
                kpiRow
                damageChartSection
                revenueChartSection
                officeDetailSection
            }
            .padding()
        }
        .background(PalantirTheme.background)
        .refreshable {
            refreshPanelData()
        }
    }

    private var topOperationsRow: some View {
        Group {
            if usesSideBySideColumns {
                HStack(alignment: .top, spacing: 12) {
                    jarvisLauncherCard
                        .frame(maxWidth: .infinity)
                        .frame(height: topRowHeight)
                    CHPanelLiveTrackingCard()
                        .frame(maxWidth: .infinity)
                        .frame(height: topRowHeight)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    jarvisLauncherCard
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: topRowCompactJarvisMinHeight)
                    CHPanelLiveTrackingCard()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: topRowCompactLiveMinHeight)
                }
            }
        }
    }

    private var jarvisLauncherCard: some View {
        CHPanelJarvisLauncherCard(jarvisEnabled: jarvisEnabled) {
            openJarvis()
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(CHPanelPeriod.allCases) { p in
                Text(p.titleKey.localized).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpiCard(
                title: "ch_panel.kpi_revenue".localized,
                value: AppCurrency.amountWithCode(snapshot.totalRevenue),
                icon: "banknote.fill",
                color: PalantirTheme.success
            )
            kpiCard(
                title: "ch_panel.kpi_damages".localized,
                value: "\(snapshot.totalDamages)",
                icon: "car.side.front.open.fill",
                color: PalantirTheme.warning
            )
            kpiCard(
                title: "ch_panel.kpi_live".localized,
                value: "\(liveFeed.eventsLast15Minutes)",
                icon: "dot.radiowaves.left.and.right",
                color: PalantirTheme.accent
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(PalantirTheme.dataFont(usesSideBySideColumns ? 15 : 14))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(title.uppercased())
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: usesSideBySideColumns ? 0 : 88, alignment: .leading)
        .palantirCard()
    }

    private var damageChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ch_panel.chart_damages".localized.uppercased())
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
                Spacer()
                Text("ch_panel.chart_revenue".localized.uppercased())
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.success)
            }
            Chart(snapshot.buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.label),
                    y: .value("Count", bucket.damageCount)
                )
                .foregroundStyle(
                    damageChartSelection == bucket.label
                        ? PalantirTheme.warning
                        : PalantirTheme.warning.opacity(0.55)
                )
            }
            .frame(height: 200)
            .chartXSelection(value: $damageChartSelection)
            .onChange(of: damageChartSelection) { _, label in
                guard let label,
                      let bucket = snapshot.buckets.first(where: { $0.label == label }) else { return }
                selectedBucket = bucket
            }
        }
        .palantirCard()
    }

    private var revenueChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_panel.chart_revenue".localized.uppercased())
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
            Chart(snapshot.buckets) { bucket in
                LineMark(
                    x: .value("Period", bucket.label),
                    y: .value("Revenue", bucket.officeRevenue)
                )
                .foregroundStyle(PalantirTheme.success)
                AreaMark(
                    x: .value("Period", bucket.label),
                    y: .value("Revenue", bucket.officeRevenue)
                )
                .foregroundStyle(PalantirTheme.success.opacity(0.15))
                PointMark(
                    x: .value("Period", bucket.label),
                    y: .value("Revenue", bucket.officeRevenue)
                )
                .symbolSize(revenueChartSelection == bucket.label ? 120 : 50)
                .annotation(position: .top) {
                    if revenueChartSelection == bucket.label || bucket.officeRevenue > 0 {
                        Text(AppCurrency.amountWithCode(bucket.officeRevenue))
                            .font(PalantirTheme.dataFont(8))
                            .foregroundStyle(PalantirTheme.success)
                    }
                }
            }
            .frame(height: 200)
            .chartXSelection(value: $revenueChartSelection)
            .onChange(of: revenueChartSelection) { _, label in
                guard let label,
                      let bucket = snapshot.buckets.first(where: { $0.label == label }) else { return }
                selectedBucket = bucket
            }
        }
        .palantirCard()
    }

    private var officeDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_panel.office_detail".localized.uppercased())
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
            ForEach(snapshot.officeBreakdown) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(officeTypeLabel(row.type))
                            .font(PalantirTheme.bodyFont(13))
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text(String(format: "ch_panel.ops_count".localized, row.count))
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    Spacer()
                    Text(AppCurrency.amountWithCode(row.totalAmount))
                        .font(PalantirTheme.dataFont(13))
                        .foregroundStyle(PalantirTheme.success)
                }
                .padding(.vertical, 6)
                if row.id != snapshot.officeBreakdown.last?.id {
                    Divider().overlay(PalantirTheme.border)
                }
            }
        }
        .palantirCard()
    }

    private var accessDenied: some View {
        ContentUnavailableView(
            "ch_panel.access_denied".localized,
            systemImage: "lock.fill",
            description: Text("ch_panel.access_denied_hint".localized)
        )
    }

    private func refreshPanelData() {
        chDamagesCache = viewModel.allHasarKayitlariForReporting.filter {
            FranchiseCapabilityMatrix.isSwitzerland(franchiseId: $0.franchiseId)
        }
        chOfficeCache = viewModel.officeOperations.filter {
            FranchiseCapabilityMatrix.isSwitzerland(franchiseId: $0.franchiseId)
        }
        chTrafficCache = viewModel.trafficAccidentContracts.filter {
            FranchiseCapabilityMatrix.isSwitzerland(franchiseId: $0.franchiseId)
        }
        rebuildAnalyticsSnapshot()
    }

    private func rebuildAnalyticsSnapshot() {
        analyticsSnapshot = CHPanelAnalyticsEngine.buildSnapshot(
            period: period,
            damages: chDamagesCache,
            officeOperations: chOfficeCache,
            trafficContracts: chTrafficCache,
            auditLogs: []
        )
    }

    private func openJarvis() {
        guard jarvisEnabled, !isPreparingJarvis else { return }
        jarvisFleetContext = nil
        showJarvis = true
        isPreparingJarvis = true

        Task { @MainActor in
            jarvisFleetContext = JarvisFleetDataContext.build(viewModel: viewModel, auditLogs: [])
            isPreparingJarvis = false
        }
    }

    private func officeTypeLabel(_ raw: String) -> String {
        if raw == "traffic_accident" {
            return "ch_panel.traffic_revenue".localized
        }
        if let t = OfficeOperationType(rawValue: raw) {
            return t.hubTitleLocalized
        }
        return raw.localized
    }
}
