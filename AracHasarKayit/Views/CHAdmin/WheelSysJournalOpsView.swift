import SwiftUI

/// Operational journal — check-outs and check-ins for the selected Zurich day.
struct WheelSysJournalOpsView: View {
    let sessionValid: Bool
    var reloadTrigger: Int = 0
    var onSessionExpired: (() -> Void)?

    @EnvironmentObject private var authManager: AuthenticationManager
    @StateObject private var journalVM: WheelSysJournalViewModel
    @State private var searchText = ""
    @State private var assignContext: WheelSysAssignBookingContext?
    @State private var detailRow: WheelSysJournalDetailContext?
    @State private var mobileSegment: MobileJournalSegment = .checkout

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!
    private static let rowMinHeight: CGFloat = 44
    /// Soft vibrant orange for unassigned vehicle rows.
    private static let unassignedRowFill = Color.orange.opacity(0.22)
    private static let unassignedRowBorder = Color.orange.opacity(0.5)

    private var canManageVehicle: Bool {
        authManager.userProfile?.canPerformWheelSysVehicleOps == true
    }

    private enum MobileJournalSegment: String, CaseIterable {
        case checkout
        case `return`
    }

    init(
        sessionValid: Bool,
        franchiseId: String,
        reloadTrigger: Int = 0,
        onSessionExpired: (() -> Void)? = nil
    ) {
        self.sessionValid = sessionValid
        self.reloadTrigger = reloadTrigger
        self.onSessionExpired = onSessionExpired
        _journalVM = StateObject(wrappedValue: WheelSysJournalViewModel(
            franchiseId: franchiseId.uppercased(),
            onSessionExpired: onSessionExpired
        ))
    }

    private var filteredCheckouts: [WheelSysJournalRow] {
        filterRows(journalVM.checkoutRows)
    }

    private var filteredReturns: [WheelSysJournalRow] {
        filterRows(journalVM.returnRows)
    }

    var body: some View {
        Group {
            if !sessionValid {
                sessionRequiredPlaceholder
            } else if journalVM.loading && journalVM.checkoutRows.isEmpty && journalVM.returnRows.isEmpty {
                ProgressView("wheelsys_journal.loading".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                journalContent
            }
        }
        .task(id: reloadTrigger) {
            guard sessionValid else { return }
            journalVM.stationFilter = "ZRH"
            await journalVM.loadJournal()
        }
        .alert("Error".localized, isPresented: Binding(
            get: { journalVM.errorMessage != nil },
            set: { if !$0 { journalVM.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(journalVM.errorMessage ?? "")
        }
        .sheet(item: $assignContext) { context in
            WheelSysAssignVehicleSheet(
                bookingEntityId: context.bookingEntityId,
                carGroup: context.carGroup,
                dateFrom: context.dateFrom,
                dateTo: context.dateTo,
                station: context.station,
                resNo: context.resNo,
                confirmationNo: context.confirmationNo,
                mode: context.mode,
                currentPlate: context.currentPlate
            ) {
                Task { await journalVM.loadJournal() }
            }
        }
        .sheet(item: $detailRow) { ctx in
            WheelSysJournalRowDetailView(
                row: ctx.row,
                isCheckout: ctx.isCheckout,
                rentalDetail: journalVM.rentalDetailsByEntityId[ctx.row.rentalEntityId],
                isLoadingDetail: journalVM.enrichingEntityIds.contains(ctx.row.rentalEntityId),
                customerName: journalVM.customerName(for: ctx.row),
                vehicleGroup: journalVM.vehicleGroup(for: ctx.row),
                canManageVehicle: canManageVehicle,
                onAssign: {
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .assign)
                    }
                },
                onChange: {
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .change)
                    }
                },
                onRemove: {
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .remove)
                    }
                }
            )
            .onAppear {
                Task { await journalVM.enrichIfNeeded(entityId: ctx.row.rentalEntityId) }
            }
        }
    }

    // MARK: Content

    private var journalContent: some View {
        VStack(spacing: 0) {
            toolbar
            if horizontalSizeClass != .regular {
                segmentToggle
            }
            searchBar
            if horizontalSizeClass == .regular {
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 8) {
                        journalColumn(
                            title: "ch_ops.checkout_section".localized,
                            count: filteredCheckouts.count,
                            rows: filteredCheckouts,
                            isCheckout: true,
                            width: geo.size.width * 0.52
                        )
                        journalColumn(
                            title: "ch_ops.return_section".localized,
                            count: filteredReturns.count,
                            rows: filteredReturns,
                            isCheckout: false,
                            width: geo.size.width * 0.48 - 8
                        )
                    }
                }
            } else {
                let isCheckout = mobileSegment == .checkout
                let rows = isCheckout ? filteredCheckouts : filteredReturns
                journalColumn(
                    title: isCheckout
                        ? "ch_ops.checkout_section".localized
                        : "ch_ops.return_section".localized,
                    count: rows.count,
                    rows: rows,
                    isCheckout: isCheckout,
                    width: nil
                )
            }
        }
        .background(PalantirTheme.background)
    }

    private var segmentToggle: some View {
        HStack(spacing: 0) {
            segmentButton(
                title: "ch_ops.checkout_section".localized,
                count: filteredCheckouts.count,
                selected: mobileSegment == .checkout
            ) {
                mobileSegment = .checkout
            }
            segmentButton(
                title: "ch_ops.return_section".localized,
                count: filteredReturns.count,
                selected: mobileSegment == .return
            ) {
                mobileSegment = .return
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func segmentButton(
        title: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("(\(count))")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? PalantirTheme.textPrimary : PalantirTheme.textMuted)
            .background(selected ? PalantirTheme.surface : PalantirTheme.surfaceHigh)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button { journalVM.shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(journalVM.loading)

            Spacer()

            HStack(spacing: 8) {
                Text(formattedSelectedDay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                if journalVM.loading {
                    ProgressView().scaleEffect(0.75)
                }
            }

            Spacer()

            Button { journalVM.shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(journalVM.loading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(PalantirTheme.surfaceHigh)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("wheelsys_journal.search_placeholder".localized, text: $searchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func journalColumn(
        title: String,
        count: Int,
        rows: [WheelSysJournalRow],
        isCheckout: Bool,
        width: CGFloat?
    ) -> some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                HStack {
                    Text(title)
                    Text("(\(count))")
                    Spacer()
                }
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(PalantirTheme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PalantirTheme.surfaceHigh)
            }

            columnHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(isCheckout ? "ch_ops.checkout_empty".localized : "ch_ops.return_empty".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                            .padding(16)
                            .frame(minHeight: Self.rowMinHeight)
                    } else {
                        ForEach(rows) { row in
                            journalRow(row, isCheckout: isCheckout)
                        }
                    }
                }
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : width)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: horizontalSizeClass == .regular ? 1 : 0))
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            headerCell("wheelsys_journal.col_res".localized, width: 72)
            headerCell("ch_ops.col_plate".localized, width: 72)
            headerCell("ch_ops.col_group".localized, width: 40)
            headerCell("wheelsys_journal.col_driver".localized, width: 88)
            headerCell("wheelsys_journal.col_fuel".localized, width: 32)
            headerCell("ch_ops.col_time".localized, width: 44)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Self.rowMinHeight)
        .padding(.horizontal, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(PalantirTheme.textMuted)
            .frame(width: width, alignment: .leading)
            .lineLimit(1)
    }

    private func journalRow(_ row: WheelSysJournalRow, isCheckout: Bool) -> some View {
        let plateText = row.plate.isEmpty ? "—" : row.plate
        let unassigned = rowShowsUnassigned(row)

        return HStack(spacing: 6) {
            dataCell(resCodeText(for: row), width: 72, bold: true)
            dataCell(plateText, width: 72, bold: true)
            dataCell(journalVM.vehicleGroup(for: row), width: 40, bold: false)
            dataCell(journalVM.customerName(for: row), width: 88, bold: false)
            dataCell(fuelText(for: row), width: 32, bold: false)
            dataCell(formatTime(row.eventDateTime), width: 44, bold: false)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Self.rowMinHeight)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            unassigned
                ? Self.unassignedRowFill
                : Color.clear
        )
        .overlay(alignment: .leading) {
            if unassigned {
                Rectangle()
                    .fill(Self.unassignedRowBorder)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
        .onTapGesture(count: 2) {
            HapticManager.shared.light()
            detailRow = WheelSysJournalDetailContext(row: row, isCheckout: isCheckout)
            Task { await journalVM.enrichIfNeeded(entityId: row.rentalEntityId) }
        }
    }

    private func dataCell(_ text: String, width: CGFloat, bold: Bool) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.bold) : .caption.weight(.semibold))
            .foregroundStyle(PalantirTheme.textPrimary)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 32)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
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

    // MARK: Helpers

    private var formattedSelectedDay: String {
        let df = DateFormatter()
        df.timeZone = Self.zurichTimeZone
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: journalVM.selectedDay)
    }

    private func filterRows(_ rows: [WheelSysJournalRow]) -> [WheelSysJournalRow] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            let res = resCodeText(for: row).lowercased()
            let plate = row.plate.lowercased()
            let driver = journalVM.customerName(for: row).lowercased()
            return res.contains(q) || plate.contains(q) || driver.contains(q)
        }
    }

    private func resCodeText(for row: WheelSysJournalRow) -> String {
        let code = row.resCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? "—" : code
    }

    private func rowShowsUnassigned(_ row: WheelSysJournalRow) -> Bool {
        isPlateUnassigned(row.plate)
    }

    private func isPlateUnassigned(_ plate: String) -> Bool {
        let t = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" || t == "—"
    }

    private func fuelText(for row: WheelSysJournalRow) -> String {
        if let detail = journalVM.rentalDetailsByEntityId[row.rentalEntityId] {
            switch row.kind {
            case .checkout:
                if let fuel = detail.fuelOutText ?? detail.fuelOutHidden, !fuel.isEmpty { return fuel }
            case .return:
                if let fuel = detail.fuelInText ?? detail.fuelInHidden, !fuel.isEmpty { return fuel }
            }
        }
        return "—"
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = Self.zurichTimeZone
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func assignContext(
        for row: WheelSysJournalRow,
        mode: WheelSysVehicleUpdateMode
    ) -> WheelSysAssignBookingContext {
        let from = row.eventStart ?? row.eventDateTime
        let to = row.eventEnd ?? Calendar.current.date(byAdding: .day, value: 1, to: from) ?? from
        let trimmedRes = row.resCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let res = WheelSysResCode.normalizedReservationCode(trimmedRes) ?? (trimmedRes.isEmpty ? nil : trimmedRes)
        let agentConf = row.displayDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = row.plate.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPlate = isPlateUnassigned(plate) ? nil : plate
        return WheelSysAssignBookingContext(
            bookingEntityId: row.effectiveBookingEntityId,
            carGroup: journalVM.vehicleGroup(for: row),
            dateFrom: from,
            dateTo: to,
            station: row.station.isEmpty ? "ZRH" : row.station,
            resNo: res,
            confirmationNo: agentConf.isEmpty ? nil : agentConf,
            mode: mode,
            currentPlate: currentPlate
        )
    }
}

// MARK: - Context types

struct WheelSysJournalDetailContext: Identifiable, Hashable {
    let row: WheelSysJournalRow
    let isCheckout: Bool
    var id: String { row.id }
}

struct WheelSysAssignBookingContext: Identifiable, Hashable {
    let bookingEntityId: Int
    let carGroup: String
    let dateFrom: Date
    let dateTo: Date
    let station: String
    /// RES code, e.g. "RES-17694".
    let resNo: String?
    /// Agent/external confirmation number, e.g. "JIG(A)-6813462-67939".
    let confirmationNo: String?
    var mode: WheelSysVehicleUpdateMode = .assign
    var currentPlate: String? = nil

    var id: String { "\(bookingEntityId)-\(mode.rawValue)" }
}
