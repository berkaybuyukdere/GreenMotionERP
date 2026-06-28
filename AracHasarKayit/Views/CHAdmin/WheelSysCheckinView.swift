import SwiftUI

/// WheelSys check-in mileage & fuel sync — replaces OPS journal tab for CH.
///
/// Firebase save and WheelSys sync are tracked separately.
/// A "Firebase saved" log does NOT mean WheelSys was updated.
struct WheelSysCheckinView: View {
    /// When embedded in `WheelSysHubView`, session UI is owned by the hub.
    var embedInHub: Bool = false
    var hubSessionValid: Bool = true

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: Search
    @State private var resQuery = ""
    @State private var searchResults: [WheelSysRentalSearchHit] = []
    @State private var selectedHit: WheelSysRentalSearchHit?
    @State private var entityIdInput = ""

    // MARK: Preview
    @State private var preview: WheelSysRentalPreview?
    @State private var checkInKmText = ""
    @State private var checkInFuel = 8
    @State private var wheelsysUserId = ""
    @State private var checkInUserOptions: [(id: String, name: String)] = []

    // MARK: Status
    @State private var searching = false
    @State private var loadingPreview = false
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var wheelsysSyncResult: WheelSysCheckinResult?

    // MARK: Session
    @State private var showLoginSheet = false
    @State private var loginSaving = false
    @State private var sessionValid = false
    @State private var checkingSession = false
    @State private var sessionSuccessNote: String?

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    private var resolvedEntityId: String {
        let fromHit = selectedHit?.entityId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromHit.isEmpty { return fromHit }
        return entityIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var checkInKm: Int? { Int(checkInKmText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var effectiveSessionValid: Bool {
        embedInHub ? hubSessionValid : sessionValid
    }

    private var kmValidationError: String? {
        guard let km = checkInKm else {
            return checkInKmText.isEmpty ? nil : "wheelsys_checkin.km_invalid".localized
        }
        if let p = preview, km <= p.mileageFrom {
            return String(format: "wheelsys_checkin.km_below_checkout".localized, p.mileageFrom)
        }
        return nil
    }

    var body: some View {
        Group {
            if embedInHub {
                checkinScrollContent
            } else {
                NavigationStack {
                    checkinScrollContent
                        .navigationTitle("wheelsys_checkin.title".localized)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
            }
        }
        .wheelSysCHOpsChrome()
        .alert("Error".localized, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: embedInHub ? .constant(false) : $showLoginSheet) {
            WheelSysLoginSheet(
                isSaving: loginSaving,
                onSessionCaptured: { cookie in
                    Task { await saveCapturedSession(cookie) }
                },
                onCancel: { showLoginSheet = false }
            )
        }
        .task {
            guard !embedInHub else { return }
            await refreshSessionStatus()
        }
    }

    private var checkinScrollContent: some View {
        WheelSysPalantirFormScroll {
            if !embedInHub { sessionBanner }
            if effectiveSessionValid {
                searchSection
                if selectedHit != nil || !entityIdInput.isEmpty {
                    selectionSection
                }
                if let p = preview {
                    previewSection(p)
                }
            }
            if let result = wheelsysSyncResult {
                resultSection(result)
            }
        }
    }

    // MARK: Session Banner

    private var sessionBanner: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.session.menu_title".localized,
            icon: "globe"
        ) {
            WheelSysPalantirStatusStrip(
                icon: sessionValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                message: sessionValid
                    ? "wheelsys_checkin.session_connected".localized
                    : "wheelsys_checkin.session_required".localized,
                tint: sessionValid ? PalantirTheme.success : PalantirTheme.warning,
                showsSpinner: checkingSession
            )
            if !sessionValid && !checkingSession {
                Text("wheelsys_checkin.session_required_hint".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if let note = sessionSuccessNote {
                WheelSysPalantirStatusStrip(
                    icon: "checkmark.circle",
                    message: note,
                    tint: PalantirTheme.success
                )
            }
            WheelSysPalantirSecondaryButton(
                title: sessionValid
                    ? "wheelsys_checkin.relogin".localized
                    : "wheelsys_checkin.login_button".localized,
                icon: "globe"
            ) {
                sessionSuccessNote = nil
                showLoginSheet = true
            }
        }
    }

    // MARK: Search

    private var searchSection: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_checkin.search_label".localized,
            icon: "magnifyingglass"
        ) {
            HStack(spacing: 8) {
                PalantirReportSearchField(
                    placeholder: "RES-16745",
                    text: $resQuery
                )
                Button {
                    HapticManager.shared.medium()
                    Task { await runSearch() }
                } label: {
                    Group {
                        if searching {
                            ProgressView().tint(PalantirTheme.accent)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(searching || resQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(searching || resQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }

            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { hit in
                        Button {
                            HapticManager.shared.selection()
                            selectHit(hit)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.displayTitle)
                                        .font(PalantirTheme.dataFont(13))
                                        .foregroundStyle(PalantirTheme.textPrimary)
                                    if !hit.plate.isEmpty {
                                        Text(hit.plate)
                                            .font(PalantirTheme.dataFont(11))
                                            .foregroundStyle(PalantirTheme.textMuted)
                                    }
                                    if !hit.customer.isEmpty {
                                        Text(hit.customer)
                                            .font(PalantirTheme.bodyFont(12))
                                            .foregroundStyle(PalantirTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(11)
                        }
                        .buttonStyle(.plain)
                        .background(selectedHit?.id == hit.id ? PalantirTheme.surfaceHigh : PalantirTheme.background.opacity(0.55))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(PalantirTheme.border).frame(height: 1)
                        }
                    }
                }
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
        }
    }

    // MARK: Selection / Entity ID

    private var selectionSection: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_checkin.rental_id".localized,
            icon: "number"
        ) {
            if selectedHit?.hasEntityId == true, let e = selectedHit?.entityId {
                HStack(spacing: 8) {
                    Text("#\(e)")
                        .font(PalantirTheme.dataFont(15))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    PalantirOpsBadge(text: "OK".localized, tone: .success)
                    Spacer(minLength: 0)
                }
            } else {
                WheelSysPalantirStatusStrip(
                    icon: "exclamationmark.triangle",
                    message: "wheelsys_checkin.entity_id_hint".localized,
                    tint: PalantirTheme.warning
                )
                WheelSysPalantirTextInput(
                    label: "wheelsys_checkin.rental_id".localized,
                    text: $entityIdInput,
                    placeholder: "wheelsys_checkin.entity_id_placeholder".localized,
                    keyboard: .numberPad
                )
            }

            WheelSysPalantirPrimaryButton(
                title: "wheelsys_checkin.load_preview".localized,
                icon: "doc.text.magnifyingglass",
                isLoading: loadingPreview,
                disabled: loadingPreview || resolvedEntityId.isEmpty
            ) {
                Task { await loadPreview() }
            }
        }
    }

    // MARK: Preview + Update

    @ViewBuilder
    private func previewSection(_ p: WheelSysRentalPreview) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_checkin.wheelsys_data".localized,
            icon: "car.fill"
        ) {
            if !p.resNo.isEmpty {
                HStack(spacing: 8) {
                    PalantirOpsBadge(text: p.resNo, tone: .accent)
                    if !p.raNo.isEmpty {
                        Text(p.raNo)
                            .font(PalantirTheme.dataFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    if !p.plate.isEmpty {
                        Text(p.plate)
                            .font(PalantirTheme.dataFont(13))
                            .foregroundStyle(PalantirTheme.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
            }

            WheelSysPalantirDataRow(
                label: "wheelsys_checkin.checkout_km".localized,
                value: "\(p.mileageFrom) km"
            )
            WheelSysPalantirDataRow(
                label: "wheelsys_checkin.current_checkin_km".localized,
                value: p.mileageTo > 0 ? "\(p.mileageTo) km" : "—"
            )
            WheelSysPalantirDataRow(
                label: "wheelsys_checkin.current_fuel".localized,
                value: "\(p.fuelTo)/8"
            )

            WheelSysPalantirInsetDivider()

            WheelSysPalantirTextInput(
                label: "wheelsys_checkin.checkin_km".localized,
                text: $checkInKmText,
                placeholder: "wheelsys_checkin.checkin_km".localized,
                keyboard: .numberPad
            )
            if let err = kmValidationError {
                WheelSysPalantirStatusStrip(
                    icon: "exclamationmark.triangle",
                    message: err,
                    tint: PalantirTheme.critical
                )
            } else if let km = checkInKm, p.mileageFrom > 0 {
                WheelSysPalantirStatusStrip(
                    icon: "road.lanes",
                    message: String(format: "wheelsys_checkin.km_driven_preview".localized, km - p.mileageFrom),
                    tint: PalantirTheme.accent
                )
            }

            WheelSysPalantirFuelSlider(
                label: "wheelsys_checkin.checkin_fuel".localized,
                eighths: $checkInFuel,
                tint: PalantirTheme.accent
            )

            if !checkInUserOptions.isEmpty {
                WheelSysPalantirField(label: "wheelsys_checkin.checkin_user".localized) {
                    Picker("", selection: $wheelsysUserId) {
                        Text("wheelsys_checkin.select_user".localized).tag("")
                        ForEach(checkInUserOptions, id: \.id) { opt in
                            Text(opt.name).tag(opt.id)
                        }
                    }
                    .labelsHidden()
                    .font(PalantirTheme.bodyFont(14))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PalantirTheme.background.opacity(0.55))
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
            } else {
                WheelSysPalantirTextInput(
                    label: "wheelsys_checkin.checkin_user_id".localized,
                    text: $wheelsysUserId,
                    keyboard: .numberPad
                )
            }

            if wheelsysUserId.isEmpty {
                WheelSysPalantirStatusStrip(
                    icon: "person.crop.circle.badge.exclamationmark",
                    message: "wheelsys_checkin.user_required".localized,
                    tint: PalantirTheme.warning
                )
            }

            WheelSysPalantirPrimaryButton(
                title: "wheelsys_checkin.sync_button".localized,
                icon: "arrow.triangle.2.circlepath",
                isLoading: submitting,
                disabled: submitting || checkInKm == nil || kmValidationError != nil || wheelsysUserId.isEmpty
            ) {
                Task { await submitUpdate() }
            }
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(_ result: WheelSysCheckinResult) -> some View {
        WheelSysPalantirSectionCard(
            title: result.success
                ? "wheelsys_checkin.sync_ok".localized
                : "wheelsys_checkin.sync_failed".localized,
            icon: result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
        ) {
            WheelSysPalantirStatusStrip(
                icon: result.success ? "checkmark.circle" : "xmark.circle",
                message: result.success
                    ? "wheelsys_checkin.sync_ok".localized
                    : "wheelsys_checkin.sync_failed".localized,
                tint: result.success ? PalantirTheme.success : PalantirTheme.critical
            )

            if result.success {
                if let km = result.mileageTo {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_checkin.synced_km".localized,
                        value: "\(km) km"
                    )
                }
                if let driven = result.milesDriven {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_checkin.synced_driven".localized,
                        value: "\(driven) km"
                    )
                }
                if let fuel = result.fuelTo {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_checkin.synced_fuel".localized,
                        value: "\(fuel)/8"
                    )
                }
                if let verified = result.verifiedMileageTo {
                    let match = verified == result.mileageTo
                    WheelSysPalantirStatusStrip(
                        icon: match ? "checkmark.seal" : "exclamationmark.triangle",
                        message: match
                            ? "wheelsys_checkin.verified_ok".localized
                            : String(format: "wheelsys_checkin.verified_mismatch".localized, verified),
                        tint: match ? PalantirTheme.success : PalantirTheme.warning
                    )
                }
            } else if !result.message.isEmpty {
                Text(result.message)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.critical)
            }

            Text("wheelsys_checkin.firebase_separate_note".localized)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
        }
    }

    // MARK: Actions

    private func selectHit(_ hit: WheelSysRentalSearchHit) {
        selectedHit = hit
        entityIdInput = hit.entityId ?? ""
        preview = nil
        wheelsysSyncResult = nil
        if let km = hit.km, checkInKmText.isEmpty {
            checkInKmText = String(km)
        }
        if hit.hasEntityId {
            Task { await loadPreview() }
        }
    }

    @MainActor
    private func refreshSessionStatus() async {
        checkingSession = true
        defer { checkingSession = false }
        do {
            let status = try await WheelSysCheckinService.sessionStatus(franchiseId: franchiseId)
            sessionValid = status.isValid
            if !status.isValid { showLoginSheet = true }
        } catch {
            sessionValid = false
        }
    }

    @MainActor
    private func saveCapturedSession(_ cookie: String) async {
        loginSaving = true
        defer { loginSaving = false }
        do {
            try await WheelSysCheckinService.saveSessionCookie(
                franchiseId: franchiseId,
                sessionCookie: cookie
            )
            showLoginSheet = false
            sessionValid = true
            sessionSuccessNote = "wheelsys_checkin.session_saved".localized
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { sessionSuccessNote = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func runSearch() async {
        searching = true
        defer { searching = false }
        do {
            searchResults = try await WheelSysCheckinService.searchByRes(
                franchiseId: franchiseId,
                resQuery: resQuery
            )
            if searchResults.isEmpty { errorMessage = "wheelsys_checkin.no_results".localized }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadPreview() async {
        loadingPreview = true
        defer { loadingPreview = false }
        wheelsysSyncResult = nil
        do {
            let expectedRes = selectedHit?.resNo ?? resQuery
            let p = try await WheelSysCheckinService.loadPreview(
                franchiseId: franchiseId,
                entityId: resolvedEntityId,
                expectedResNo: expectedRes
            )
            preview = p
            checkInUserOptions = p.checkInUserOptions
            if checkInKmText.isEmpty {
                checkInKmText = p.mileageTo > 0 ? String(p.mileageTo) : String(p.mileageFrom)
            }
            checkInFuel = p.fuelTo > 0 ? p.fuelTo : 8
            if wheelsysUserId.isEmpty {
                wheelsysUserId = WheelSysCookieCache.wheelSysOperatorId ?? p.checkInUserId
            }
            if wheelsysUserId.isEmpty, let first = p.checkInUserOptions.first {
                wheelsysUserId = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submitUpdate() async {
        guard let km = checkInKm, let p = preview else { return }
        guard kmValidationError == nil else { return }
        submitting = true
        defer { submitting = false }
        wheelsysSyncResult = nil
        do {
            // NOTE: This call only updates WheelSys. If you also need to save to Firebase,
            // that must be a separate operation (exitIslemleri / iadeIslemleri save).
            let result = try await WheelSysCheckinService.submitCheckinUpdate(
                franchiseId: franchiseId,
                entityId: resolvedEntityId,
                resNo: p.resNo.isEmpty ? (selectedHit?.resNo ?? resQuery) : p.resNo,
                plate: p.plate.isEmpty ? (selectedHit?.plate ?? "") : p.plate,
                checkInMileage: km,
                checkInFuel: checkInFuel,
                checkInUserId: wheelsysUserId.isEmpty ? nil : wheelsysUserId
            )
            wheelsysSyncResult = result
            if result.success {
                WheelSysActivityReporter.record(
                    .checkinSync(
                        plate: p.plate.isEmpty ? (selectedHit?.plate ?? "") : p.plate,
                        resNo: p.resNo.isEmpty ? (selectedHit?.resNo ?? resQuery) : p.resNo,
                        km: km
                    ),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
                preview = nil
                selectedHit = nil
            } else {
                errorMessage = result.message.isEmpty
                    ? "wheelsys_checkin.sync_failed".localized
                    : result.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
