import SwiftUI

/// Compact reservation detail — opened from Journal ops list.
struct WheelSysJournalRowDetailView: View {
    let row: WheelSysJournalRow
    let isCheckout: Bool
    let rentalDetail: WheelSysRentalDetail?
    let isLoadingDetail: Bool
    let customerName: String
    let vehicleGroup: String
    let fleetVehicle: WheelSysFleetVehicle?
    let journalMileage: Int?
    let journalFuel: Int?
    let canManageVehicle: Bool
    let onAssign: () -> Void
    let onChange: () -> Void
    let onRemove: () -> Void
    var onStartReturn: (() -> Void)? = nil
    var onStartCheckout: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!
    private static let categoryOptions = ["B", "C", "D", "E", "HC", "N", "Q", "R", "T", "X", "Z"]
    private static let miniCardMinHeight: CGFloat = 118

    @State private var selectedCategory: String = ""
    @State private var bookingAttachments: [WheelSysBookingAttachment] = []
    @State private var attachmentsLoading = false

    private var unassigned: Bool {
        let t = row.plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" || t == "—"
    }

    private var effectiveCategory: String {
        let g = selectedCategory.isEmpty ? vehicleGroup : selectedCategory
        let trimmed = g.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "—" : trimmed
    }

    private var effectiveCustomerName: String {
        let rentalName = rentalDetail?.customerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rentalName.isEmpty { return rentalName }
        let passed = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !passed.isEmpty, passed != "-" { return passed }
        let fleet = row.driverNameFromFleet.trimmingCharacters(in: .whitespacesAndNewlines)
        return fleet.isEmpty ? "—" : fleet
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                compactGrid
                if isCheckout {
                    attachmentsSection
                }
                if isLoadingDetail {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("ch_ops.loading_detail".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                if !isCheckout {
                    returnInlineActions
                } else if canManageVehicle && !unassigned {
                    checkoutStartActions
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(PalantirTheme.background)
            .wheelSysCHOpsChrome()
            .navigationTitle("wheelsys_journal.detail_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .onAppear {
                selectedCategory = vehicleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .task(id: row.effectiveBookingEntityId) {
                guard isCheckout else { return }
                await loadBookingAttachments()
            }
        }
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        infoMiniCard(title: "wheelsys.journal.attachments".localized) {
            if attachmentsLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("ch_ops.loading_detail".localized)
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            } else if bookingAttachments.isEmpty {
                Text("wheelsys.journal.attachments_empty".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bookingAttachments) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(PalantirTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PalantirTheme.textPrimary)
                                    .lineLimit(2)
                                if item.fileSize > 0 {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(PalantirTheme.textMuted)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadBookingAttachments() async {
        attachmentsLoading = true
        defer { attachmentsLoading = false }
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let docNo = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview = try? await WheelSysCheckinService.loadBookingPreview(
            franchiseId: franchiseId,
            entityId: row.effectiveBookingEntityId,
            resNo: docNo.isEmpty ? nil : docNo,
            displayDocNo: docNo.isEmpty ? nil : docNo
        ) else { return }
        bookingAttachments = preview.attachments
    }

    // MARK: - Layout

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(heroDocText)
                    .font(.system(size: 18, weight: .bold).monospaced())
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let secondary = heroSecondaryText {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            miniChip(isCheckout ? "ch_ops.checkout_section".localized : "ch_ops.return_section".localized)
            miniChip(row.station.isEmpty ? "ZRH" : row.station)
        }
        .padding(10)
        .background(
            Rectangle()
                .fill(unassigned ? PalantirTheme.surfaceHigh : Color(red: 0.427, green: 0.365, blue: 0.988).opacity(0.12))
                .overlay(Rectangle().stroke(
                    unassigned ? PalantirTheme.textMuted.opacity(0.35) : Color(red: 0.427, green: 0.365, blue: 0.988).opacity(0.45),
                    lineWidth: 1
                ))
        )
    }

    private var compactGrid: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                vehiclePlateGroupCard
                    .frame(maxWidth: .infinity)
                scheduleMiniCard
                    .frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 8) {
                infoMiniCard(title: "wheelsys_journal.section_customer".localized) {
                    gridValue(effectiveCustomerName)
                    if let agent = rentalDetail?.agentBooker, !agent.isEmpty {
                        gridLabel("wheelsys_journal.agent".localized)
                        gridValue(agent)
                    }
                }
                .frame(maxWidth: .infinity)

                infoMiniCard(title: "wheelsys_journal.section_km_fuel".localized) {
                    if let out = mileageOutText {
                        gridPair("wheelsys_journal.km_out".localized, out)
                    }
                    if let fuel = fuelOutText {
                        gridPair("wheelsys_journal.fuel_out".localized, fuel)
                    }
                    if let `in` = mileageInText {
                        gridPair("wheelsys_journal.km_in".localized, `in`)
                    }
                    if let fuel = fuelInText {
                        gridPair("wheelsys_journal.fuel_in".localized, fuel)
                    }
                    if !hasKmFuelData && !isLoadingDetail {
                        gridValue("—")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            infoMiniCard(title: "wheelsys_journal.section_reservation".localized) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    if !row.confirmationReference.isEmpty {
                        gridPair("wheelsys_assign.conf".localized, row.confirmationReference)
                    }
                    gridPair("wheelsys_assign.booking".localized, "#\(row.effectiveBookingEntityId)")
                    if let rentalNo = row.rentalNumber ?? rentalDetail?.rentalNumber {
                        gridPair("wheelsys_journal.rental_no".localized, rentalNo)
                    }
                    gridPair("wheelsys_journal.entity_id".localized, String(row.rentalEntityId))
                }
            }
        }
    }

    private var vehiclePlateGroupCard: some View {
        infoMiniCard(title: "wheelsys_journal.section_vehicle".localized) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ch_ops.col_plate".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PalantirTheme.textMuted)
                    HStack(spacing: 6) {
                        Text(unassigned ? "—" : row.plate)
                            .font(.system(size: 14, weight: .bold).monospaced())
                            .foregroundStyle(unassigned ? PalantirTheme.textMuted : Color(red: 0.427, green: 0.365, blue: 0.988))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if canManageVehicle && isCheckout && !unassigned {
                            Button {
                                HapticManager.shared.selection()
                                HapticManager.shared.medium()
                                onRemove()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(PalantirTheme.critical)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("wheelsys_assign.remove_title".localized)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ch_ops.col_group".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PalantirTheme.textMuted)
                    if canManageVehicle && isCheckout {
                        Menu {
                            ForEach(Self.categoryOptions, id: \.self) { code in
                                Button(code) {
                                    HapticManager.shared.selection()
                                    selectedCategory = code
                                }
                            }
                            Button("wheelsys_assign.change_title".localized) {
                                HapticManager.shared.selection()
                                onChange()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(effectiveCategory)
                                    .font(.system(size: 14, weight: .bold))
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(PalantirTheme.accent)
                        }
                    } else {
                        Text(effectiveCategory)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(PalantirTheme.textPrimary)
                    }
                }
            }
            if !row.model.isEmpty {
                gridPair("ch_ops.col_model".localized, row.model)
            }
            if canManageVehicle && isCheckout && unassigned {
                palantirAssignVehicleButton
                    .padding(.top, 6)
            }
        }
    }

    private var palantirAssignVehicleButton: some View {
        Button {
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            onAssign()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "car.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("wheelsys_assign.title".localized)
                    .font(PalantirTheme.labelFont(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(PalantirTheme.onAccent)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PalantirTheme.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(PalantirTheme.accent, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("wheelsys_assign.title".localized)
    }

    private var scheduleMiniCard: some View {
        infoMiniCard(title: "wheelsys_journal.section_schedule".localized) {
            if let start = row.eventStart {
                gridPair("wheelsys_journal.checkout_time".localized, formatDateTime(start))
            }
            if let end = row.eventEnd {
                gridPair("wheelsys_journal.checkin_time".localized, formatDateTime(end))
            }
            gridPair("ch_ops.col_time".localized, formatDateTime(row.eventDateTime))
        }
    }

    private var checkoutStartActions: some View {
        Button {
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            onStartCheckout?()
        } label: {
            Label("wheelsys.checkout.start_button".localized, systemImage: "arrow.right.circle.fill")
                .font(PalantirTheme.labelFont(12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(PalantirTheme.onAccent)
                .background(PalantirTheme.accent)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var returnInlineActions: some View {
        Button {
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            onStartReturn?()
        } label: {
            Label("wheelsys.return.start_button".localized, systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(PalantirTheme.accent)
    }

    // MARK: - Helpers

    private var heroDocText: String {
        if !isCheckout, let res = row.linkedResCode?.trimmingCharacters(in: .whitespacesAndNewlines), !res.isEmpty {
            return res
        }
        let main = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !main.isEmpty { return main }
        return "—"
    }

    private var heroSecondaryText: String? {
        let ra = row.rentalNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !isCheckout, !ra.isEmpty, ra.uppercased().hasPrefix("RNT"), heroDocText != ra {
            return "RA: \(ra)"
        }
        return nil
    }

    private var hasKmFuelData: Bool {
        mileageOutText != nil || fuelOutText != nil || mileageInText != nil || fuelInText != nil
    }

    private var mileageOutText: String? {
        if let text = rentalDetail?.mileageOutText ?? rentalDetail?.mileageOutHidden,
           !text.isEmpty, text != "0" { return text }
        if let km = journalMileage, km > 0 { return "\(km)" }
        if let km = fleetVehicle?.mileage, km > 0 { return "\(km)" }
        return nil
    }

    private var fuelOutText: String? {
        if let text = rentalDetail?.fuelOutText ?? rentalDetail?.fuelOutHidden,
           !text.isEmpty, text != "0" { return formatFuel(text) }
        if let fuel = journalFuel, fuel >= 0 { return "\(fuel)/8" }
        return nil
    }

    private var mileageInText: String? {
        if let text = rentalDetail?.mileageInText ?? rentalDetail?.mileageInHidden,
           !text.isEmpty, text != "0" { return text }
        return nil
    }

    private var fuelInText: String? {
        if let text = rentalDetail?.fuelInText ?? rentalDetail?.fuelInHidden,
           !text.isEmpty { return formatFuel(text) }
        return nil
    }

    private func formatFuel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") { return trimmed }
        if let value = Int(trimmed) { return "\(value)/8" }
        return trimmed
    }

    private func infoMiniCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(PalantirTheme.textMuted)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: Self.miniCardMinHeight, alignment: .topLeading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func gridLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(PalantirTheme.textMuted)
    }

    private func gridValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PalantirTheme.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private func gridPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            gridLabel(label)
            gridValue(value)
        }
    }

    private func miniChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PalantirTheme.surfaceHigh)
            .foregroundStyle(PalantirTheme.textMuted)
    }

    private func formatDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.timeZone = Self.zurichTimeZone
        df.dateFormat = "d MMM yyyy HH:mm"
        return df.string(from: date)
    }
}
