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
        if let p = preview, km < p.mileageFrom {
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
        .background(PalantirTheme.background)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(16)
        }
    }

    // MARK: Session Banner

    private var sessionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if checkingSession {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: sessionValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(sessionValid ? Color.green : Color.orange)
                }
                Text(sessionValid
                     ? "wheelsys_checkin.session_connected".localized
                     : "wheelsys_checkin.session_required".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer()
            }
            if !sessionValid && !checkingSession {
                Text("wheelsys_checkin.session_required_hint".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if let note = sessionSuccessNote {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(note)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            Button {
                sessionSuccessNote = nil
                showLoginSheet = true
            } label: {
                Label(
                    sessionValid
                    ? "wheelsys_checkin.relogin".localized
                    : "wheelsys_checkin.login_button".localized,
                    systemImage: "globe"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.427, green: 0.365, blue: 0.988))
        }
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    // MARK: Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("wheelsys_checkin.search_label".localized)

            HStack(spacing: 8) {
                TextField("RES-16745", text: $resQuery)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(PalantirTheme.surface)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

                Button {
                    Task { await runSearch() }
                } label: {
                    Group {
                        if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .background(PalantirTheme.surfaceHigh)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                .disabled(searching || resQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { hit in
                        Button { selectHit(hit) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PalantirTheme.textPrimary)
                                    if !hit.plate.isEmpty { captionText(hit.plate) }
                                    if !hit.customer.isEmpty { captionText(hit.customer) }
                                }
                                Spacer()
                            }
                            .padding(12)
                        }
                        .buttonStyle(.plain)
                        .background(selectedHit?.id == hit.id ? PalantirTheme.surfaceHigh : PalantirTheme.surface)
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
        VStack(alignment: .leading, spacing: 10) {
            label("wheelsys_checkin.rental_id".localized)

            if selectedHit?.hasEntityId == true, let e = selectedHit?.entityId {
                HStack {
                    Text("#\(e)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PalantirTheme.textPrimary)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                }
            } else {
                Text("wheelsys_checkin.entity_id_hint".localized)
                    .font(.caption)
                    .foregroundStyle(Color.orange)

                TextField("wheelsys_checkin.entity_id_placeholder".localized, text: $entityIdInput)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(PalantirTheme.surface)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }

            Button {
                Task { await loadPreview() }
            } label: {
                HStack {
                    if loadingPreview { ProgressView().padding(.trailing, 4) }
                    Text("wheelsys_checkin.load_preview".localized)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.427, green: 0.365, blue: 0.988))
            .disabled(loadingPreview || resolvedEntityId.isEmpty)
        }
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    // MARK: Preview + Update

    @ViewBuilder
    private func previewSection(_ p: WheelSysRentalPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            label("wheelsys_checkin.wheelsys_data".localized)

            // Identity validation: warn if plate/RES mismatch
            if !p.resNo.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(p.resNo + (p.raNo.isEmpty ? "" : " · \(p.raNo)"))
                        .font(.subheadline.weight(.semibold))
                    if !p.plate.isEmpty { Text("·").foregroundStyle(PalantirTheme.textMuted); Text(p.plate).font(.subheadline) }
                }
                .foregroundStyle(PalantirTheme.textPrimary)
            }

            Group {
                row("wheelsys_checkin.checkout_km".localized,    "\(p.mileageFrom) km")
                row("wheelsys_checkin.current_checkin_km".localized, p.mileageTo > 0 ? "\(p.mileageTo) km" : "—")
                row("wheelsys_checkin.current_fuel".localized,   "\(p.fuelTo)/8")
            }

            Divider()
            label("wheelsys_checkin.update_fields".localized)

            // Mileage input
            VStack(alignment: .leading, spacing: 4) {
                TextField("wheelsys_checkin.checkin_km".localized, text: $checkInKmText)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(
                        kmValidationError != nil ? Color.red : PalantirTheme.border,
                        lineWidth: 1
                    ))
                if let err = kmValidationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else if let km = checkInKm, p.mileageFrom > 0 {
                    captionText(String(format: "wheelsys_checkin.km_driven_preview".localized, km - p.mileageFrom))
                }
            }

            // Fuel slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("wheelsys_checkin.checkin_fuel".localized)
                    Spacer()
                    Text("\(checkInFuel)/8").monospacedDigit().fontWeight(.semibold)
                }
                .font(.subheadline)
                Slider(value: Binding(
                    get: { Double(checkInFuel) },
                    set: { checkInFuel = min(8, max(0, Int($0.rounded()))) }
                ), in: 0...8, step: 1)
                .accentColor(Color(red: 0.427, green: 0.365, blue: 0.988))
            }

            if !checkInUserOptions.isEmpty {
                Picker("wheelsys_checkin.checkin_user".localized, selection: $wheelsysUserId) {
                    Text("wheelsys_checkin.select_user".localized).tag("")
                    ForEach(checkInUserOptions, id: \.id) { opt in
                        Text(opt.name).tag(opt.id)
                    }
                }
                .pickerStyle(.menu)
            } else {
                TextField("wheelsys_checkin.checkin_user_id".localized, text: $wheelsysUserId)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }

            if wheelsysUserId.isEmpty {
                Text("wheelsys_checkin.user_required".localized)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // NOTE: "WheelSys sync" is separate from Firebase save.
            // This button only submits to WheelSys — it does not touch Vehicle Sentinel Firebase records.
            Button {
                Task { await submitUpdate() }
            } label: {
                HStack {
                    if submitting { ProgressView().padding(.trailing, 4) }
                    Text("wheelsys_checkin.sync_button".localized)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.427, green: 0.365, blue: 0.988))
            .disabled(submitting || checkInKm == nil || kmValidationError != nil || wheelsysUserId.isEmpty)
        }
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(_ result: WheelSysCheckinResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? Color.green : Color.red)
                Text(result.success
                     ? "wheelsys_checkin.sync_ok".localized
                     : "wheelsys_checkin.sync_failed".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result.success ? Color.green : Color.red)
            }

            if result.success {
                if let km = result.mileageTo { row("wheelsys_checkin.synced_km".localized, "\(km) km") }
                if let driven = result.milesDriven { row("wheelsys_checkin.synced_driven".localized, "\(driven) km") }
                if let fuel = result.fuelTo { row("wheelsys_checkin.synced_fuel".localized, "\(fuel)/8") }
                if let verified = result.verifiedMileageTo {
                    let match = verified == result.mileageTo
                    HStack(spacing: 4) {
                        Image(systemName: match ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(match ? Color.green : Color.orange)
                        Text(match
                             ? "wheelsys_checkin.verified_ok".localized
                             : String(format: "wheelsys_checkin.verified_mismatch".localized, verified))
                            .font(.caption)
                            .foregroundStyle(match ? Color.green : Color.orange)
                    }
                }
            } else if !result.message.isEmpty {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Remind that Firebase save is a separate operation.
            Text("wheelsys_checkin.firebase_separate_note".localized)
                .font(.caption2)
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .padding(14)
        .background(result.success
                    ? Color.green.opacity(0.06)
                    : Color.red.opacity(0.06))
        .overlay(Rectangle().stroke(
            result.success ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
            lineWidth: 1
        ))
    }

    // MARK: Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PalantirTheme.textMuted)
            .textCase(.uppercase)
    }

    private func captionText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(PalantirTheme.textMuted)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(PalantirTheme.textMuted)
            Spacer()
            Text(value.isEmpty ? "—" : value).fontWeight(.medium)
        }
        .font(.subheadline)
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
                wheelsysUserId = p.checkInUserId
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
