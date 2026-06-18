import SwiftUI

/// Rich reservation detail — opened on double-tap from Journal ops list.
struct WheelSysJournalRowDetailView: View {
    let row: WheelSysJournalRow
    let isCheckout: Bool
    let rentalDetail: WheelSysRentalDetail?
    let isLoadingDetail: Bool
    let customerName: String
    let vehicleGroup: String
    let canManageVehicle: Bool
    let onAssign: () -> Void
    let onChange: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!

    private var unassigned: Bool {
        let t = row.plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" || t == "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroHeader
                    reservationSection
                    vehicleSection
                    scheduleSection
                    kmFuelSection
                    customerSection
                    if canManageVehicle && isCheckout {
                        actionsSection
                    }
                }
                .padding(16)
            }
            .background(PalantirTheme.background)
            .navigationTitle("wheelsys_journal.detail_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resCodeText)
                        .font(PalantirTheme.heroFont(22).monospaced())
                        .foregroundStyle(PalantirTheme.textPrimary)
                    if !row.displayDocNo.isEmpty, row.displayDocNo != resCodeText {
                        Text(row.displayDocNo)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                miniChip(isCheckout ? "ch_ops.checkout_section".localized : "ch_ops.return_section".localized)
                miniChip(row.station.isEmpty ? "ZRH" : row.station)
                if !vehicleGroup.isEmpty, vehicleGroup != "-" {
                    miniChip(vehicleGroup)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(unassigned ? Color.orange.opacity(0.12) : PalantirTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            unassigned ? Color.orange.opacity(0.45) : PalantirTheme.border,
                            lineWidth: 1
                        )
                )
        )
    }

    private var statusBadge: some View {
        Group {
            if unassigned {
                Text("wheelsys_journal.unassigned".localized)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.22))
                    .foregroundStyle(Color.orange)
            } else {
                Text(row.plate)
                    .font(.system(size: 12, weight: .bold).monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PalantirTheme.success.opacity(0.15))
                    .foregroundStyle(PalantirTheme.success)
            }
        }
    }

    private var reservationSection: some View {
        detailCard(title: "wheelsys_journal.section_reservation".localized) {
            infoRow("wheelsys_assign.res_code".localized, resCodeText)
            if !row.displayDocNo.isEmpty {
                infoRow("wheelsys_assign.conf".localized, row.displayDocNo)
            }
            infoRow("wheelsys_assign.booking".localized, "#\(row.effectiveBookingEntityId)")
            if let rentalNo = row.rentalNumber ?? rentalDetail?.rentalNumber {
                infoRow("wheelsys_journal.rental_no".localized, rentalNo)
            }
            if let resDate = rentalDetail?.reservationDateText {
                infoRow("wheelsys_journal.reservation_date".localized, resDate)
            }
        }
    }

    private var vehicleSection: some View {
        detailCard(title: "wheelsys_journal.section_vehicle".localized) {
            infoRow("ch_ops.col_plate".localized, unassigned ? "—" : row.plate)
            infoRow("ch_ops.col_model".localized, row.model.isEmpty ? "—" : row.model)
            infoRow("ch_ops.col_group".localized, vehicleGroup.isEmpty ? "—" : vehicleGroup)
            if !row.resourceId.isEmpty {
                infoRow("wheelsys_journal.resource_id".localized, row.resourceId)
            }
            infoRow("wheelsys_journal.entity_id".localized, String(row.rentalEntityId))
        }
    }

    private var scheduleSection: some View {
        detailCard(title: "wheelsys_journal.section_schedule".localized) {
            if let start = row.eventStart {
                infoRow("wheelsys_journal.checkout_time".localized, formatDateTime(start))
            }
            if let end = row.eventEnd {
                infoRow("wheelsys_journal.checkin_time".localized, formatDateTime(end))
            }
            infoRow(
                isCheckout ? "ch_ops.col_time".localized : "ch_ops.col_time".localized,
                formatDateTime(row.eventDateTime)
            )
            if let checkoutLoc = rentalDetail?.checkoutLocation, !checkoutLoc.isEmpty {
                infoRow("wheelsys_journal.checkout_location".localized, checkoutLoc)
            }
            if let checkinLoc = rentalDetail?.checkinLocation, !checkinLoc.isEmpty {
                infoRow("wheelsys_journal.checkin_location".localized, checkinLoc)
            }
        }
    }

    @ViewBuilder
    private var kmFuelSection: some View {
        if isLoadingDetail {
            HStack(spacing: 8) {
                ProgressView()
                Text("ch_ops.loading_detail".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        } else if rentalDetail != nil || hasKmFuelData {
            detailCard(title: "wheelsys_journal.section_km_fuel".localized) {
                if let out = mileageOutText {
                    infoRow("wheelsys_journal.km_out".localized, out)
                }
                if let fuel = fuelOutText {
                    infoRow("wheelsys_journal.fuel_out".localized, fuel)
                }
                if let `in` = mileageInText {
                    infoRow("wheelsys_journal.km_in".localized, `in`)
                }
                if let fuel = fuelInText {
                    infoRow("wheelsys_journal.fuel_in".localized, fuel)
                }
            }
        }
    }

    private var customerSection: some View {
        detailCard(title: "wheelsys_journal.section_customer".localized) {
            infoRow("wheelsys_journal.col_driver".localized, customerName.isEmpty ? "—" : customerName)
            if let agent = rentalDetail?.agentBooker, !agent.isEmpty {
                infoRow("wheelsys_journal.agent".localized, agent)
            }
            if let title = rentalDetail?.title, !title.isEmpty {
                infoRow("wheelsys_journal.rental_title".localized, title)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            if unassigned {
                actionButton(
                    title: "wheelsys_assign.title".localized,
                    icon: "car.fill",
                    tint: PalantirTheme.accent,
                    action: onAssign
                )
            } else {
                actionButton(
                    title: "wheelsys_assign.change_title".localized,
                    icon: "arrow.triangle.2.circlepath",
                    tint: PalantirTheme.accent,
                    action: onChange
                )
                actionButton(
                    title: "wheelsys_assign.remove_title".localized,
                    icon: "minus.circle.fill",
                    tint: PalantirTheme.critical,
                    action: onRemove
                )
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var resCodeText: String {
        let code = row.resCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? "—" : code
    }

    private var hasKmFuelData: Bool {
        mileageOutText != nil || fuelOutText != nil || mileageInText != nil || fuelInText != nil
    }

    private var mileageOutText: String? {
        rentalDetail?.mileageOutText ?? rentalDetail?.mileageOutHidden
    }

    private var fuelOutText: String? {
        rentalDetail?.fuelOutText ?? rentalDetail?.fuelOutHidden
    }

    private var mileageInText: String? {
        rentalDetail?.mileageInText ?? rentalDetail?.mileageInHidden
    }

    private var fuelInText: String? {
        rentalDetail?.fuelInText ?? rentalDetail?.fuelInHidden
    }

    private func detailCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(PalantirTheme.textMuted)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func miniChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PalantirTheme.surfaceHigh)
            .foregroundStyle(PalantirTheme.textMuted)
    }

    private func actionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.medium()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private func formatDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = Self.zurichTimeZone
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
