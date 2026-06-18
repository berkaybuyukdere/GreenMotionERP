import SwiftUI

/// WheelSys area with a shared session: Fleet Chart, Availability, Journal, and Daily View.
struct WheelSysHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case fleet
        case availability
        case journal
        case dailyView

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fleet: return "wheelsys_hub.tab_fleet".localized
            case .availability: return "wheelsys_hub.tab_availability".localized
            case .journal: return "wheelsys_hub.tab_journal".localized
            case .dailyView: return "wheelsys_hub.tab_daily_view".localized
            }
        }
    }

    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var session = WheelSysSessionCoordinator()
    @State private var selectedTab: Tab = .fleet

    var body: some View {
        NavigationStack {
            Group {
                if session.checkingSession {
                    checkingPlaceholder
                } else if session.sessionValid {
                    connectedContent
                } else {
                    inlineLoginContent
                }
            }
            .background(PalantirTheme.background)
            .navigationTitle("wheelsys.tab".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error".localized, isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(session.errorMessage ?? "")
            }
            .task { await session.refreshSessionStatus() }
        }
    }

    // MARK: Connected (tabs)

    private var connectedContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch selectedTab {
                case .fleet:
                    WheelSysFleetChartView(
                        sessionValid: session.sessionValid,
                        fleetChartAccessValid: session.fleetChartValid,
                        reloadTrigger: session.reloadToken,
                        onSessionExpired: { session.markExpired() }
                    )
                case .availability:
                    WheelSysAvailabilityView(
                        sessionValid: session.sessionValid,
                        reloadTrigger: session.reloadToken,
                        onSessionExpired: { session.markExpired() }
                    )
                case .journal:
                    WheelSysJournalOpsView(
                        sessionValid: session.sessionValid,
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        reloadTrigger: session.reloadToken,
                        onSessionExpired: { session.markExpired() }
                    )
                case .dailyView:
                    WheelSysDailyViewScreen(
                        sessionValid: session.sessionValid,
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        reloadTrigger: session.reloadToken,
                        onSessionExpired: { session.markExpired() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.green)
            }
        }
    }

    // MARK: Placeholders

    private var checkingPlaceholder: some View {
        PalantirOpsLoadingOverlay(
            title: "wheelsys.fleet.loading.connecting_title".localized,
            microcopy: "wheelsys.fleet.loading.connecting_micro".localized,
            step: 1,
            floating: false
        )
    }

    // MARK: Inline login (once — no sheet, no button after success)

    private var inlineLoginContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("wheelsys_checkin.session_required".localized, systemImage: "globe")
                    .font(.headline)
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text("wheelsys_checkin.session_required_hint".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PalantirTheme.surface)

            ZStack {
                WheelSysLoginWebView { cookie in
                    Task { await session.saveCapturedSession(cookie) }
                }
                .ignoresSafeArea(edges: .bottom)

                if session.loginSaving {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("wheelsys_checkin.session_saving".localized)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
