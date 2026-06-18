import SwiftUI

/// WheelSys Journal — daily checkout/return from Fleet Chart, enriched via rental.aspx.
///
/// DEPRECATED (WheelSys iOS master plan): the Journal tab was removed from
/// `WheelSysHubView`. This file is intentionally kept in the Xcode target to
/// avoid build churn; it is no longer reachable from the hub. Full removal is a
/// separate follow-up PR.
struct WheelSysJournalView: View {
    var sessionValid: Bool
    var onSessionExpired: () -> Void
    var reloadTrigger: Int = 0

    @StateObject private var journalVM: WheelSysJournalViewModel
    @State private var selectedReturnRow: WheelSysJournalRow?
    @State private var showReturnDetail = false

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    init(
        sessionValid: Bool,
        franchiseId: String,
        onSessionExpired: @escaping () -> Void,
        reloadTrigger: Int = 0
    ) {
        self.sessionValid = sessionValid
        self.onSessionExpired = onSessionExpired
        self.reloadTrigger = reloadTrigger
        _journalVM = StateObject(wrappedValue: WheelSysJournalViewModel(
            franchiseId: franchiseId.uppercased(),
            onSessionExpired: onSessionExpired
        ))
    }

    var body: some View {
        Group {
            if !sessionValid {
                sessionRequiredPlaceholder
            } else if journalVM.loading && journalVM.checkoutRows.isEmpty && journalVM.returnRows.isEmpty {
                ProgressView("ch_ops.loading".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                journalScrollContent
            }
        }
        .task(id: reloadTrigger) {
            guard sessionValid else { return }
            await journalVM.loadJournal()
            journalVM.scheduleLazyEnrichment()
        }
        .onChange(of: journalVM.selectedDay) { _, _ in
            journalVM.scheduleLazyEnrichment()
        }
        .alert("Error".localized, isPresented: Binding(
            get: { journalVM.errorMessage != nil },
            set: { if !$0 { journalVM.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(journalVM.errorMessage ?? "")
        }
        .sheet(isPresented: $showReturnDetail) {
            if let row = selectedReturnRow {
                WheelSysJournalReturnDetailView(
                    row: row,
                    rentalDetail: journalVM.rentalDetailsByEntityId[row.rentalEntityId],
                    isLoadingDetail: journalVM.enrichingEntityIds.contains(row.rentalEntityId),
                    onReturn: { km, fuel in
                        await journalVM.handleReturnPressed(for: row, mileageIn: km, fuelIn: fuel)
                    }
                )
            }
        }
    }

    private var sessionRequiredPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(PalantirTheme.textMuted)
            Text("wheelsys_checkin.session_required".localized)
                .font(.subheadline)
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var journalScrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                journalBanner
                toolbar
                #if DEBUG
                debugDiagnosticsSection
                #endif
                sectionLabel("ch_ops.checkout_section".localized, count: journalVM.checkoutRows.count)
                journalTable(rows: journalVM.checkoutRows, isReturnSection: false)
                sectionLabel("ch_ops.return_section".localized, count: journalVM.returnRows.count)
                journalTable(rows: journalVM.returnRows, isReturnSection: true)
                sectionLabel("ch_ops.fleet_section".localized, count: journalVM.fleetVehicles.count)
                fleetSection
            }
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .refreshable {
            await journalVM.loadJournal()
            journalVM.scheduleLazyEnrichment()
        }
    }

    private var journalBanner: some View {
        Text("ch_ops.journal_banner".localized)
            .font(.system(size: 13, weight: .bold))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(red: 0.427, green: 0.365, blue: 0.988))
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { journalVM.shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                        .background(PalantirTheme.surface)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                DatePicker("", selection: Binding(
                    get: { journalVM.selectedDay },
                    set: { journalVM.setSelectedDay($0) }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

                Button { journalVM.shiftDay(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                        .background(PalantirTheme.surface)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button("ch_ops.today".localized) { journalVM.goToToday() }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(PalantirTheme.surface)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

                Spacer()

                if journalVM.loading {
                    ProgressView().scaleEffect(0.8)
                }

                Picker("Station", selection: Binding(
                    get: { journalVM.stationFilter },
                    set: { journalVM.setStationFilter($0) }
                )) {
                    Text("ch_ops.all_stations".localized).tag("all")
                    Text("ZRH").tag("ZRH")
                }
                .pickerStyle(.menu)
            }
        }
        .padding(14)
        .background(PalantirTheme.surfaceHigh)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    #if DEBUG
    private var debugDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rental diagnostics (debug)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PalantirTheme.textMuted)
            HStack(spacing: 8) {
                debugDiagButton("19525", entityId: 19525)
                debugDiagButton("19584", entityId: 19584)
                debugDiagButton("18781", entityId: 18781)
            }
            if journalVM.diagnosticsLoading {
                ProgressView().scaleEffect(0.7)
            }
            if let diag = journalVM.diagnosticsResult {
                Text("entityId=\(diag.entityId) status=\(diag.status) html=\(diag.htmlLength)")
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textMuted)
                Text("title: \(diag.title)")
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textPrimary)
                if let driverField = diag.inputs.first(where: { $0.idAttr == "rdDriver_text" || $0.name.contains("rdDriver") }) {
                    Text("rdDriver_text: \(driverField.valuePreview)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diag.inputs.prefix(20)) { field in
                            Text("\(field.idAttr) | \(field.name) = \(field.valuePreview)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(12)
        .background(PalantirTheme.surfaceHigh)
    }

    private func debugDiagButton(_ label: String, entityId: Int) -> some View {
        Button(label) {
            Task { await journalVM.runDiagnostics(entityId: entityId) }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
    #endif

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Text("(\(count))")
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer()
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(1.2)
        .textCase(.uppercase)
        .foregroundStyle(PalantirTheme.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PalantirTheme.surfaceHigh)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func journalTable(rows: [WheelSysJournalRow], isReturnSection: Bool) -> some View {
        Group {
            if rows.isEmpty {
                Text(isReturnSection ? "ch_ops.return_empty".localized : "ch_ops.checkout_empty".localized)
                    .font(.subheadline)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        journalHeaderRow
                        ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                            journalDataRow(row, index: offset + 1, isReturnSection: isReturnSection)
                        }
                    }
                    .frame(minWidth: 720, alignment: .leading)
                }
            }
        }
    }

    private var journalHeaderRow: some View {
        HStack(spacing: 8) {
            headerCell("#", width: 24)
            headerCell("ch_ops.col_time".localized, width: 44)
            headerCell("ch_ops.col_date".localized, width: 72)
            headerCell("ch_ops.col_customer".localized, width: 100)
            headerCell("ch_ops.col_group".localized, width: 44)
            headerCell("ch_ops.col_plate".localized, width: 72)
            headerCell("ch_ops.col_location".localized, width: 80)
            headerCell("ch_ops.col_agent".localized, width: 80)
            headerCell("ch_ops.col_model".localized, width: 100)
            headerCell("ID", width: 48)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(PalantirTheme.textMuted)
            .frame(width: width, alignment: .leading)
            .lineLimit(1)
    }

    private func journalDataRow(_ row: WheelSysJournalRow, index: Int, isReturnSection: Bool) -> some View {
        let enriching = journalVM.enrichingEntityIds.contains(row.rentalEntityId)

        return HStack(spacing: 8) {
            dataCell("\(row.rowNumber)", width: 24)
            dataCell(formatTime(row.eventDateTime), width: 44)
            dataCell(formatDate(row.eventDateTime), width: 72)
            dataCell(journalVM.customerName(for: row), width: 100)
            dataCell(journalVM.vehicleGroup(for: row), width: 44)
            dataCell(row.plate, width: 72)
            dataCell(journalVM.location(for: row), width: 80)
            dataCell(journalVM.agentBooker(for: row), width: 80)
            dataCell(row.model, width: 100)
            dataCell(String(row.rentalEntityId), width: 48, debug: true)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color(red: 0.427, green: 0.365, blue: 0.988))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
        .opacity(enriching ? 0.7 : 1)
        .contentShape(Rectangle())
        .onAppear {
            Task { await journalVM.enrichIfNeeded(entityId: row.rentalEntityId) }
        }
        .onTapGesture(count: 2) {
            guard isReturnSection else { return }
            print("[Journal] row double tapped type=return plate=\(row.plate) entityId=\(row.rentalEntityId)")
            print("[Journal] opening VehicleDetailView plate=\(row.plate) entityId=\(row.rentalEntityId)")
            selectedReturnRow = row
            showReturnDetail = true
            Task { await journalVM.enrichIfNeeded(entityId: row.rentalEntityId) }
        }
    }

    private func dataCell(_ text: String, width: CGFloat, debug: Bool = false) -> some View {
        Text(text)
            .font(.system(size: debug ? 10 : 12, weight: debug ? .regular : .semibold))
            .foregroundStyle(debug ? PalantirTheme.textMuted : Color(red: 0.427, green: 0.365, blue: 0.988))
            .frame(width: width, alignment: .leading)
            .lineLimit(2)
    }

    private var fleetSection: some View {
        Group {
            if journalVM.fleetVehicles.isEmpty {
                Text("ch_ops.fleet_empty".localized)
                    .font(.subheadline)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(18)
            } else {
                ForEach(journalVM.fleetVehicles.prefix(40)) { vehicle in
                    HStack {
                        Text(vehicle.plate).frame(width: 80, alignment: .leading)
                        Text(vehicle.group).frame(width: 40, alignment: .leading)
                        Text(vehicle.model).frame(maxWidth: .infinity, alignment: .leading)
                        Text(vehicle.station.isEmpty ? "ZRH" : vehicle.station).frame(width: 40, alignment: .leading)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(PalantirTheme.border).frame(height: 1)
                    }
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }
}

/// Legacy wrapper — same WheelSys journal inside OPS naming.
struct SwitzerlandOpsJournalView: View {
    var body: some View {
        WheelSysJournalView(
            sessionValid: WheelSysCookieCache.isValid,
            franchiseId: FirebaseService.shared.currentFranchiseId,
            onSessionExpired: {}
        )
    }
}
