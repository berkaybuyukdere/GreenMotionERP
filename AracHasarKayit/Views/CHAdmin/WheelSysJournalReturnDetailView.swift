import SwiftUI

/// Return row detail — opened on double-tap; pre-check-in guidance only.
struct WheelSysJournalReturnDetailView: View {
    let row: WheelSysJournalRow
    let rentalDetail: WheelSysRentalDetail?
    let isLoadingDetail: Bool
    let onReturn: (Int?, Int?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mileageInText = ""
    @State private var fuelInValue = 8
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    if isLoadingDetail {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("ch_ops.loading_detail".localized)
                                .font(.subheadline)
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                    }
                    if let detail = rentalDetail {
                        rentalDetailSection(detail)
                    }
                    returnFormSection
                }
                .padding(16)
            }
            .background(PalantirTheme.background)
            .navigationTitle("ch_ops.return_detail".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .onAppear { prefillFromDetail() }
            .onChange(of: rentalDetail?.mileageInText) { _, _ in prefillFromDetail() }
        }
    }

    private func prefillFromDetail() {
        guard let detail = rentalDetail else { return }
        if mileageInText.isEmpty {
            mileageInText = detail.mileageInText ?? detail.mileageInHidden ?? ""
        }
        if fuelInValue == 8, let fuel = detail.fuelInText ?? detail.fuelInHidden, let parsed = Int(fuel) {
            fuelInValue = parsed
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledRow("ch_ops.col_plate".localized, row.plate)
            labeledRow("ch_ops.col_model".localized, row.model)
            labeledRow("Station", row.station)
            labeledRow("Resource ID", row.resourceId)
            labeledRow("Rental entityId", String(row.rentalEntityId))
            labeledRow("ch_ops.col_time".localized, formatDateTime(row.eventDateTime))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func rentalDetailSection(_ detail: WheelSysRentalDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rental detail")
                .font(.headline)
                .foregroundStyle(PalantirTheme.textPrimary)
            if let title = detail.title {
                labeledRow("Title", title)
            }
            labeledRow("ch_ops.col_customer".localized, detail.customerName ?? "-")
            if let rentalNo = detail.rentalNumber {
                labeledRow("Rental", rentalNo)
            }
            if let resDate = detail.reservationDateText {
                labeledRow("Reservation", resDate)
            }
            if let out = detail.mileageOutText ?? detail.mileageOutHidden {
                labeledRow("Km out", out)
            }
            if let fuel = detail.fuelOutText ?? detail.fuelOutHidden {
                labeledRow("Fuel out", fuel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private var returnFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ch_ops.return_update".localized)
                .font(.headline)
                .foregroundStyle(PalantirTheme.textPrimary)

            TextField("Km in", text: $mileageInText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("wheelsys_checkin.checkin_fuel".localized)
                    Spacer()
                    Text("\(fuelInValue)/8").monospacedDigit().fontWeight(.semibold)
                }
                Slider(value: Binding(
                    get: { Double(fuelInValue) },
                    set: { fuelInValue = min(8, max(0, Int($0.rounded()))) }
                ), in: 0...8, step: 1)
            }

            WheelSysPalantirStatusStrip(
                icon: "info.circle",
                message: "wheelsys.precheckin.inline_footer".localized,
                tint: PalantirTheme.textMuted
            )

            WheelSysPalantirPrimaryButton(
                title: "wheelsys.precheckin.submit_button".localized,
                icon: "checkmark.seal.fill",
                isLoading: submitting,
                disabled: submitting || Int(mileageInText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil
            ) {
                HapticManager.shared.medium()
                Task {
                    submitting = true
                    defer { submitting = false }
                    let km = Int(mileageInText.trimmingCharacters(in: .whitespacesAndNewlines))
                    await onReturn(km, fuelInValue)
                    if km != nil, km! > 0 {
                        HapticManager.shared.success()
                        ToastManager.shared.show(
                            "wheelsys.precheckin.submit_success".localized,
                            type: .success
                        )
                        dismiss()
                    } else {
                        HapticManager.shared.error()
                        ToastManager.shared.show(
                            "wheelsys_checkin.km_invalid".localized,
                            type: .error
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
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

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: date)
    }
}
