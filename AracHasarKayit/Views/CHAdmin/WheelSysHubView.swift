import SwiftUI

private enum WheelSysHubSegment: String, CaseIterable, Identifiable {
    case journal
    case dailyView

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .journal: return "wheelsys.hub.journal"
        case .dailyView: return "wheelsys.hub.daily_view"
        }
    }
}

/// WheelSys CH ops — journal and daily view for check-outs, pre-check-ins, cancellations.
struct WheelSysHubView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject private var session: WheelSysSessionCoordinator

    @State private var segment: WheelSysHubSegment = .journal

    var body: some View {
        NavigationStack {
            Group {
                if session.checkingSession && !session.sessionValid {
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
            .task {
                guard FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
                    serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
                    userProfile: nil
                ) else { return }
                guard !session.sessionValid else { return }
                await session.refreshSessionStatus()
            }
        }
    }

    // MARK: Connected

    private var connectedContent: some View {
        VStack(spacing: 0) {
            hubSegmentPicker
            Group {
                switch segment {
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
                        hubMode: true,
                        onSessionExpired: { session.markExpired() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: session.reloadToken) {
            let franchiseId = FirebaseService.shared.currentFranchiseId
            guard FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
                serviceFranchiseId: franchiseId,
                userProfile: nil
            ) else { return }
            await viewModel.bootstrapWheelSysFleetLinks(franchiseId: franchiseId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let note = session.sessionSuccessNote, !note.isEmpty {
                        Text(note)
                    }
                    Button {
                        HapticManager.shared.selection()
                        Task { await session.refreshSessionStatus(force: true) }
                    } label: {
                        Label("wheelsys.session.refresh".localized, systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        HapticManager.shared.medium()
                        session.clearCachedSessionCookie()
                    } label: {
                        Label("wheelsys.session.clear_cookie".localized, systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        HapticManager.shared.medium()
                        session.signOut()
                    } label: {
                        Label("wheelsys.session.sign_out_relogin".localized, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: session.sessionValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(session.sessionValid ? Color.green : Color.orange)
                        .accessibilityLabel("wheelsys.session.menu_title".localized)
                }
            }
        }
    }

    private var hubSegmentPicker: some View {
        HStack(spacing: 8) {
            ForEach(WheelSysHubSegment.allCases) { item in
                let selected = segment == item
                Button {
                    HapticManager.shared.selection()
                    segment = item
                } label: {
                    Text(item.titleKey.localized)
                        .font(PalantirTheme.labelFont(12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? PalantirTheme.accent : PalantirTheme.surfaceHigh)
                        .foregroundStyle(selected ? PalantirTheme.onAccent : PalantirTheme.textPrimary)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
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
            .onAppear {
                WheelSysSessionPromptCenter.snoozePrompts(for: 300)
            }

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
