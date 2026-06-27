import SwiftUI

/// Shared return / check-in mileage + fuel sheet (journal + plate scan entry points).
struct WheelSysReturnCheckinSheet: View {
    let franchiseId: String
    let candidate: WheelSysReturnCandidate
    let entryPoint: WheelSysReturnEntryPoint
    var selectedDate: String = WheelSysJournalService.formatZurichDay(WheelSysJournalService.todayZurich())
    var onJournalReload: (() async -> Void)?
    let onCompleted: (WheelSysReturnSaveResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var preview: WheelSysRentalPreview?
    @State private var loadingPreview = true
    @State private var previewError: String?
    @State private var checkInKmText = ""
    @State private var checkInFuel = 8
    @State private var wheelsysUserId = ""
    @State private var submitting = false
    @State private var saveResult: WheelSysReturnSaveResult?
    @State private var saveError: String?

    private var checkInKm: Int? {
        Int(checkInKmText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var kmValidationError: String? {
        guard let km = checkInKm else {
            return checkInKmText.isEmpty ? nil : "wheelsys_checkin.km_invalid".localized
        }
        if let p = preview, km < p.mileageFrom {
            return String(format: "wheelsys_checkin.km_below_checkout".localized, p.mileageFrom)
        }
        if km <= 0 { return "wheelsys_checkin.km_invalid".localized }
        return nil
    }

    private var checkInUserOptions: [(id: String, name: String)] {
        preview?.checkInUserOptions ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    if loadingPreview {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("ch_ops.loading_detail".localized)
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                    } else if let previewError {
                        Text(previewError)
                            .font(.subheadline)
                            .foregroundStyle(PalantirTheme.critical)
                    } else if let preview {
                        previewCard(preview)
                        entryForm(preview)
                    }
                    if let result = saveResult {
                        resultCard(result)
                    } else if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.critical)
                    }
                }
                .padding(16)
            }
            .background(PalantirTheme.background)
            .navigationTitle("wheelsys.return.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .task { await loadPreview() }
        }
    }

    // MARK: - Sections

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.displayTitle)
                .font(PalantirTheme.heroFont(20).monospaced())
                .foregroundStyle(PalantirTheme.textPrimary)
            infoRow("wheelsys_journal.col_driver".localized, candidate.driverName)
            infoRow("ch_ops.col_plate".localized, candidate.plate)
            if let model = candidate.model, !model.isEmpty {
                infoRow("ch_ops.col_model".localized, model)
            }
            if let km = candidate.checkoutMileage {
                infoRow("wheelsys_checkin.checkout_km".localized, "\(km) km")
            }
            if let fuel = candidate.checkoutFuel {
                infoRow("wheelsys_journal.fuel_out".localized, "\(fuel)/8")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func previewCard(_ p: WheelSysRentalPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("wheelsys_checkin.wheelsys_data".localized)
                .font(.headline)
                .foregroundStyle(PalantirTheme.textPrimary)
            if !p.raNo.isEmpty {
                infoRow("RA", p.raNo)
            }
            if !p.resNo.isEmpty {
                infoRow("RES", p.resNo)
            }
            infoRow("wheelsys_checkin.checkout_km".localized, "\(p.mileageFrom) km")
            infoRow("wheelsys_checkin.current_fuel".localized, "\(p.fuelFrom)/8")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func entryForm(_ p: WheelSysRentalPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("wheelsys.return.update_section".localized)
                .font(.headline)
                .foregroundStyle(PalantirTheme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("wheelsys_checkin.checkin_km".localized, text: $checkInKmText)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(
                        kmValidationError != nil ? PalantirTheme.critical : PalantirTheme.border,
                        lineWidth: 1
                    ))
                if let err = kmValidationError {
                    Text(err).font(.caption).foregroundStyle(PalantirTheme.critical)
                } else if let km = checkInKm, p.mileageFrom > 0 {
                    Text(String(format: "wheelsys_checkin.km_driven_preview".localized, km - p.mileageFrom))
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }

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

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if submitting { ProgressView().tint(.white) }
                    Text("wheelsys.return.save_button".localized)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(PalantirTheme.accent)
            .disabled(submitting || checkInKm == nil || kmValidationError != nil || wheelsysUserId.isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func resultCard(_ result: WheelSysReturnSaveResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? Color.green : PalantirTheme.critical)
                Text(result.success
                     ? "wheelsys_checkin.sync_ok".localized
                     : "wheelsys_checkin.sync_failed".localized)
                    .font(.subheadline.weight(.semibold))
            }
            if !result.message.isEmpty {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.verificationPending ? Color.orange : PalantirTheme.textMuted)
            }
            if let km = result.mileageTo {
                infoRow("wheelsys_checkin.synced_km".localized, "\(km) km")
            }
            if let fuel = result.fuelTo {
                infoRow("wheelsys_checkin.synced_fuel".localized, "\(fuel)/8")
            }
        }
        .padding(14)
        .background(result.success ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    // MARK: - Actions

    private func loadPreview() async {
        loadingPreview = true
        previewError = nil
        defer { loadingPreview = false }
        do {
            let p = try await WheelSysRentalService.loadRentalPreview(
                franchiseId: franchiseId,
                rentalId: candidate.rentalEntityId,
                expectedResNo: candidate.resNo.isEmpty ? nil : candidate.resNo
            )
            preview = p
            if checkInKmText.isEmpty {
                checkInKmText = p.mileageTo > 0 ? String(p.mileageTo) : String(p.mileageFrom)
            }
            if wheelsysUserId.isEmpty {
                wheelsysUserId = WheelSysCookieCache.wheelSysOperatorId ?? p.checkInUserId
            }
            if checkInFuel == 8, p.fuelTo >= 0 {
                checkInFuel = p.fuelTo
            }
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func submit() async {
        guard let km = checkInKm, kmValidationError == nil else { return }
        submitting = true
        saveError = nil
        defer { submitting = false }

        let request = WheelSysReturnUpdateRequest(
            franchiseId: franchiseId,
            rentalEntityId: candidate.rentalEntityId,
            resNo: candidate.resNo,
            plate: candidate.plate,
            checkInMileage: km,
            checkInFuel: checkInFuel,
            checkInUserId: wheelsysUserId.isEmpty ? nil : wheelsysUserId,
            vehicleEntityIdHint: candidate.vehicleEntityId,
            fleetCarId: candidate.vehicleEntityId,
            entryPoint: entryPoint,
            station: candidate.station.isEmpty ? "ZRH" : candidate.station,
            addAutoNotes: true,
            actualCheckInDateTime: WheelSysZurichDateTime.now()
        )

        do {
            let result = try await WheelSysJournalService.submitReturnUpdate(
                franchiseId: franchiseId,
                request: request,
                onJournalReload: onJournalReload
            )
            saveResult = result
            if result.success {
                HapticManager.shared.success()
                WheelSysActivityReporter.record(
                    .precheckin(
                        plate: candidate.plate,
                        rntNo: candidate.raNo,
                        resNo: candidate.resNo,
                        rentalId: candidate.rentalEntityId
                    ),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
                onCompleted(result)
            } else {
                HapticManager.shared.error()
                saveError = result.message
            }
        } catch {
            HapticManager.shared.error()
            saveError = error.localizedDescription
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

/// Picker when plate scan finds multiple active rentals.
struct WheelSysReturnCandidatePickerSheet: View {
    let candidates: [WheelSysReturnCandidate]
    let onSelect: (WheelSysReturnCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    onSelect(candidate)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.displayTitle)
                            .font(.headline.monospaced())
                        Text(candidate.driverName)
                            .font(.subheadline)
                        HStack {
                            Text(candidate.plate)
                            if let model = candidate.model, !model.isEmpty {
                                Text("· \(model)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
            }
            .navigationTitle("wheelsys.return.pick_rental".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
    }
}
