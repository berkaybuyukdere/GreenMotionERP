import SwiftUI

/// Operational journal — check-outs and check-ins for the selected Zurich day.
struct WheelSysJournalOpsView: View {
    let sessionValid: Bool
    var reloadTrigger: Int = 0
    var onSessionExpired: (() -> Void)?

    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var viewModel: AracViewModel
    @StateObject private var journalVM: WheelSysJournalViewModel
    @State private var searchText = ""
    @State private var assignContext: WheelSysAssignBookingContext?
    @State private var detailRow: WheelSysJournalDetailContext?
    @State private var iadeReturnContext: WheelSysIadeReturnContext?
    @State private var checkoutExitContext: WheelSysCheckoutExitContext?
    @State private var pendingCheckoutRow: WheelSysJournalRow?
    @State private var mobileSegment: MobileJournalSegment = .checkout
    @State private var checkoutPresentations: [JournalRowPresentation] = []
    @State private var returnPresentations: [JournalRowPresentation] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var presentationRefreshTask: Task<Void, Never>?

    private struct JournalRowPresentation: Identifiable, Equatable {
        let id: String
        let row: WheelSysJournalRow
        let resText: String
        let plateText: String
        let group: String
        let driver: String
        let fuel: String
        let time: String
        let unassigned: Bool
        let matchesGroup: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.resText == rhs.resText
                && lhs.plateText == rhs.plateText
                && lhs.group == rhs.group
                && lhs.driver == rhs.driver
                && lhs.fuel == rhs.fuel
                && lhs.time == rhs.time
                && lhs.unassigned == rhs.unassigned
                && lhs.matchesGroup == rhs.matchesGroup
        }
    }

    private struct JournalColumnHeaderRow: View {
        let isCheckout: Bool

        var body: some View {
            HStack(spacing: 8) {
                JournalHeaderCell(title: "wheelsys_journal.col_res".localized, width: 60)
                JournalHeaderCell(title: "ch_ops.col_plate".localized, width: 92)
                JournalHeaderCell(title: "ch_ops.col_group".localized, width: 36)
                JournalHeaderCell(title: "wheelsys_journal.col_driver".localized, width: 88)
                JournalHeaderCell(title: "wheelsys_journal.col_fuel".localized, width: 28)
                JournalHeaderCell(title: "ch_ops.col_time".localized, width: 40)
                Spacer(minLength: 0)
            }
            .frame(minHeight: WheelSysJournalOpsView.rowMinHeight)
            .padding(.horizontal, 10)
            .background(PalantirTheme.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PalantirTheme.border).frame(height: 1)
            }
        }
    }

    private struct JournalHeaderCell: View {
        let title: String
        let width: CGFloat

        var body: some View {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: width, alignment: .leading)
                .lineLimit(1)
        }
    }

    private struct JournalRowCellView: View, Equatable {
        let item: JournalRowPresentation
        let isCheckout: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.item == rhs.item && lhs.isCheckout == rhs.isCheckout
        }

        var body: some View {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(item.unassigned ? WheelSysJournalOpsView.unassignedRowBorder : WheelSysJournalOpsView.assignedRowBorder)
                    .frame(width: 3)
                HStack(spacing: 8) {
                    JournalDataCell(text: item.resText, width: 60, bold: true, singleLine: true)
                    JournalDataCell(text: item.plateText, width: 92, bold: true, singleLine: true)
                    JournalDataCell(text: item.group, width: 36, bold: false, singleLine: false)
                    JournalDataCell(text: item.driver, width: 88, bold: false, singleLine: false)
                    JournalDataCell(text: item.fuel, width: 28, bold: false, singleLine: false)
                    JournalDataCell(text: item.time, width: 40, bold: false, singleLine: false)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
            .frame(minHeight: WheelSysJournalOpsView.rowMinHeight)
            .background(rowBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PalantirTheme.border).frame(height: 1)
            }
        }

        private var rowBackground: Color {
            if item.matchesGroup { return WheelSysJournalOpsView.palantirPurple.opacity(0.22) }
            if item.unassigned { return WheelSysJournalOpsView.unassignedRowFill }
            return WheelSysJournalOpsView.assignedRowFill
        }
    }

    private struct JournalDataCell: View {
        let text: String
        let width: CGFloat
        let bold: Bool
        let singleLine: Bool

        var body: some View {
            Text(text)
                .font(bold ? .caption.weight(.bold) : .caption)
                .foregroundStyle(PalantirTheme.textPrimary)
                .frame(width: width, alignment: .leading)
                .lineLimit(singleLine ? 1 : 2)
                .minimumScaleFactor(singleLine ? 0.75 : 1)
        }
    }

    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!
    private static let zurichTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = zurichTimeZone
        df.dateFormat = "HH:mm"
        return df
    }()
    private static let zurichDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = zurichTimeZone
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let rowMinHeight: CGFloat = 38
    private static let palantirPurple = Color(red: 0.427, green: 0.365, blue: 0.988)
    /// Vehicle not yet assigned — neutral gray.
    private static let unassignedRowFill = PalantirTheme.surfaceHigh
    private static let unassignedRowBorder = PalantirTheme.textMuted.opacity(0.45)
    /// Vehicle assigned on booking — Palantir purple.
    private static let assignedRowFill = palantirPurple.opacity(0.14)
    private static let assignedRowBorder = palantirPurple

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

    @MainActor
    private func schedulePresentationRefresh() {
        presentationRefreshTask?.cancel()
        presentationRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            refreshRowPresentations()
        }
    }

    @MainActor
    private func refreshRowPresentations() {
        checkoutPresentations = buildPresentations(from: journalVM.checkoutRows)
        returnPresentations = buildPresentations(from: journalVM.returnRows)
    }

    @MainActor
    private func scheduleSearchRefresh() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            refreshRowPresentations()
        }
    }

    private func buildPresentations(from rows: [WheelSysJournalRow]) -> [JournalRowPresentation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let highlight = journalVM.highlightGroup
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let fuelByEntityId = buildFuelLookupMap()
        return rows.compactMap { row in
            if !q.isEmpty {
                let doc = mainDocText(for: row).lowercased()
                let conf = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let res = row.linkedResCode?.lowercased() ?? row.resCode.lowercased()
                let plate = row.plate.lowercased()
                let driver = journalVM.customerName(for: row).lowercased()
                let matches = doc.contains(q) || conf.contains(q) || res.contains(q)
                    || plate.contains(q) || driver.contains(q)
                if !matches { return nil }
            }
            let group = row.vehicleGroup.isEmpty ? "-" : row.vehicleGroup
            let matchesGroup = !highlight.isEmpty && group.uppercased() == highlight
            let fleetName = row.driverNameFromFleet.trimmingCharacters(in: .whitespacesAndNewlines)
            let driver = fleetName.isEmpty ? "-" : fleetName
            return JournalRowPresentation(
                id: row.id,
                row: row,
                resText: mainDocText(for: row),
                plateText: row.plate.isEmpty ? "—" : row.plate,
                group: group,
                driver: driver,
                fuel: fuelText(for: row, fuelByEntityId: fuelByEntityId),
                time: formatTime(row.eventDateTime),
                unassigned: rowShowsUnassigned(row),
                matchesGroup: matchesGroup
            )
        }
    }

    private func buildFuelLookupMap() -> [String: String] {
        guard let snapshot = journalVM.journalSnapshot else { return [:] }
        var map: [String: String] = [:]
        for checkout in snapshot.checkOuts {
            guard let fuel = checkout.fuel else { continue }
            let text = "\(fuel)"
            map["co:\(checkout.rentalEntityId)"] = text
            if let bookingId = checkout.bookingEntityId {
                map["co:\(bookingId)"] = text
            }
        }
        for checkin in snapshot.checkIns {
            guard let fuel = checkin.fuel else { continue }
            map["ci:\(checkin.rentalEntityId)"] = "\(fuel)"
        }
        return map
    }

    private var checkoutSheetOpen: Bool { checkoutExitContext != nil }

    var body: some View {
        Group {
            if !sessionValid {
                sessionRequiredPlaceholder
            } else if journalVM.loading && journalVM.checkoutRows.isEmpty && journalVM.returnRows.isEmpty && !checkoutSheetOpen {
                PalantirOpsLoadingOverlay(
                    title: "wheelsys_journal.loading".localized,
                    microcopy: PalantirOpsPhase.fetching.microcopy,
                    step: PalantirOpsPhase.fetching.step,
                    floating: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                journalContent
            }
        }
        .wheelSysCHOpsChrome()
        .task(id: reloadTrigger) {
            guard sessionValid, !checkoutSheetOpen else { return }
            journalVM.stationFilter = "ZRH"
            journalVM.warmFromLocalFleetCache()
            await journalVM.loadJournal(background: !journalVM.checkoutRows.isEmpty && !journalVM.returnRows.isEmpty)
            refreshRowPresentations()
        }
        .onChange(of: journalVM.checkoutRows) { _, _ in schedulePresentationRefresh() }
        .onChange(of: journalVM.returnRows) { _, _ in schedulePresentationRefresh() }
        .onChange(of: journalVM.highlightGroup) { _, _ in schedulePresentationRefresh() }
        .onChange(of: searchText) { _, _ in scheduleSearchRefresh() }
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
                currentPlate: context.currentPlate,
                customerName: context.customerName
            ) { vehicle, email in
                let row = pendingCheckoutRow
                let assignMode = context.mode
                let bookingId = context.bookingEntityId
                pendingCheckoutRow = nil

                switch assignMode {
                case .assign:
                    guard let row, let vehicle else { return }
                    journalVM.applyOptimisticPlateAssignment(
                        bookingEntityId: bookingId,
                        plate: vehicle.plateNo
                    )
                    refreshRowPresentations()
                    Task {
                        await openCheckoutAfterAssign(
                            for: row,
                            assignedPlate: vehicle.plateNo,
                            customerEmail: email
                        )
                        Task(priority: .utility) {
                            await journalVM.loadJournal(background: true)
                            await MainActor.run { refreshRowPresentations() }
                        }
                    }
                case .change:
                    guard let vehicle else { return }
                    journalVM.applyOptimisticPlateAssignment(
                        bookingEntityId: bookingId,
                        plate: vehicle.plateNo
                    )
                    refreshRowPresentations()
                    Task(priority: .utility) {
                        await journalVM.loadJournal(background: true)
                        await MainActor.run { refreshRowPresentations() }
                    }
                case .remove:
                    journalVM.applyOptimisticPlateRemoval(bookingEntityId: bookingId)
                    refreshRowPresentations()
                    Task(priority: .utility) {
                        await journalVM.loadJournal(background: true)
                        await MainActor.run { refreshRowPresentations() }
                    }
                }
            }
        }
        .sheet(item: $detailRow) { ctx in
            WheelSysJournalRowDetailView(
                row: ctx.row,
                isCheckout: ctx.isCheckout,
                rentalDetail: journalVM.rentalDetailsByEntityId[ctx.row.rentalEntityId],
                isLoadingDetail: isEnrichingDetail(entityId: ctx.row.rentalEntityId),
                customerName: journalVM.customerName(for: ctx.row),
                vehicleGroup: journalVM.vehicleGroup(for: ctx.row),
                fleetVehicle: fleetVehicleForJournalRow(ctx.row),
                journalMileage: journalMileageForRow(ctx.row),
                journalFuel: journalFuelForRow(ctx.row),
                canManageVehicle: canManageVehicle,
                onAssign: {
                    pendingCheckoutRow = ctx.row
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .assign)
                    }
                },
                onChange: {
                    pendingCheckoutRow = ctx.row
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .change)
                    }
                },
                onRemove: {
                    pendingCheckoutRow = nil
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        assignContext = assignContext(for: ctx.row, mode: .remove)
                    }
                },
                onStartReturn: {
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        openReturnOperation(for: ctx.row)
                    }
                },
                onStartCheckout: {
                    detailRow = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        Task { await openCheckoutOperation(for: ctx.row, assignedPlate: ctx.row.plate) }
                    }
                }
            )
            .onAppear {
                Task { await journalVM.enrichIfNeeded(entityId: ctx.row.rentalEntityId) }
            }
        }
        .sheet(item: $iadeReturnContext) { context in
            NavigationStack {
                IadeIslemView(
                    arac: context.arac,
                    wheelSysReturnPrefill: context.prefill
                ) { _ in
                    Task { await journalVM.loadJournal() }
                }
                .environmentObject(viewModel)
                .environmentObject(authManager)
            }
            .wheelSysCHOpsChrome()
        }
        .sheet(item: $checkoutExitContext) { context in
            let parkedExit = context.resumeParkedExitId.flatMap { exitId in
                viewModel.exitIslemleri.first { $0.id == exitId && $0.status == .parked && !$0.isDeleted }
            }
            NavigationStack {
                ExitIslemView(
                    arac: context.arac,
                    existingExit: parkedExit,
                    wheelSysCheckoutPrefill: context.prefill,
                    unparkOnWheelSysJournalResume: parkedExit != nil
                ) { _ in
                    Task { await journalVM.loadJournal() }
                }
                .environmentObject(viewModel)
                .environmentObject(authManager)
            }
            .wheelSysCHOpsChrome()
        }
    }

    // MARK: Content

    private var journalContent: some View {
        VStack(spacing: 0) {
            journalSummaryHeader
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
                            count: checkoutPresentations.count,
                            presentations: checkoutPresentations,
                            isCheckout: true,
                            width: geo.size.width * 0.52
                        )
                        journalColumn(
                            title: "ch_ops.return_section".localized,
                            count: returnPresentations.count,
                            presentations: returnPresentations,
                            isCheckout: false,
                            width: geo.size.width * 0.48 - 8
                        )
                    }
                }
            } else {
                let isCheckout = mobileSegment == .checkout
                let presentations = isCheckout ? checkoutPresentations : returnPresentations
                journalColumn(
                    title: isCheckout
                        ? "ch_ops.checkout_section".localized
                        : "ch_ops.return_section".localized,
                    count: presentations.count,
                    presentations: presentations,
                    isCheckout: isCheckout,
                    width: nil
                )
            }
        }
        .background(PalantirTheme.background)
    }

    private var journalSummaryHeader: some View {
        VStack(spacing: 4) {
            if journalVM.journalUsesFleetFallback {
                WheelSysPalantirStatusStrip(
                    icon: "exclamationmark.triangle.fill",
                    message: "wheelsys_journal.fleet_fallback_hint".localized,
                    tint: PalantirTheme.warning
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            journalMetricsBar
                .padding(.horizontal, 12)
                .padding(.top, journalVM.journalUsesFleetFallback ? 4 : 8)
                .padding(.bottom, 2)
        }
    }

    private var journalMetricsBar: some View {
        WheelSysPalantirMetricsBar(items: [
            (
                icon: "arrow.up.right.circle.fill",
                label: "ch_ops.checkout_section".localized,
                value: "\(checkoutPresentations.count)",
                tint: PalantirTheme.accent
            ),
            (
                icon: "arrow.down.left.circle.fill",
                label: "ch_ops.return_section".localized,
                value: "\(returnPresentations.count)",
                tint: Self.palantirPurple.opacity(0.85)
            ),
            (
                icon: "car.side.fill",
                label: "wheelsys_daily.tab_available".localized,
                value: "\(journalVM.availableVehicles.count)",
                tint: Self.palantirPurple
            ),
            (
                icon: "mappin.circle.fill",
                label: "wheelsys_journal.station".localized,
                value: journalVM.stationFilter == "all" ? "ZRH" : journalVM.stationFilter,
                tint: PalantirTheme.textMuted
            )
        ], compact: true)
    }

    private var segmentToggle: some View {
        HStack(spacing: 0) {
            segmentButton(
                title: "ch_ops.checkout_section".localized,
                count: checkoutPresentations.count,
                selected: mobileSegment == .checkout
            ) {
                mobileSegment = .checkout
            }
            segmentButton(
                title: "ch_ops.return_section".localized,
                count: returnPresentations.count,
                selected: mobileSegment == .return
            ) {
                mobileSegment = .return
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func segmentButton(
        title: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
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
            .foregroundStyle(selected ? .white : PalantirTheme.textMuted)
            .background(selected ? Self.palantirPurple : PalantirTheme.surfaceHigh)
            .overlay(Rectangle().stroke(selected ? Self.palantirPurple : PalantirTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            WheelSysJournalDateNavButton(
                systemName: "chevron.left.circle.fill",
                disabled: journalVM.loading
            ) {
                journalVM.shiftDay(-1)
            }

            VStack(spacing: 2) {
                Text(formattedSelectedDay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if journalVM.loading {
                    ProgressView().scaleEffect(0.65)
                }
            }
            .frame(maxWidth: .infinity)

            WheelSysJournalDateNavButton(
                systemName: "chevron.right.circle.fill",
                disabled: journalVM.loading
            ) {
                journalVM.shiftDay(1)
            }

            Button {
                HapticManager.shared.selection()
                journalVM.goToToday()
            } label: {
                Text("ch_ops.today".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PalantirTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(PalantirTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(journalVM.loading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
        .padding(.vertical, 8)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func journalColumn(
        title: String,
        count: Int,
        presentations: [JournalRowPresentation],
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

            JournalColumnHeaderRow(isCheckout: isCheckout)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if presentations.isEmpty {
                        Text(isCheckout ? "ch_ops.checkout_empty".localized : "ch_ops.return_empty".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                            .padding(16)
                            .frame(minHeight: Self.rowMinHeight)
                    } else {
                        ForEach(presentations) { item in
                            Button {
                                handleJournalRowTap(item, isCheckout: isCheckout)
                            } label: {
                                JournalRowCellView(item: item, isCheckout: isCheckout)
                                    .equatable()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : width)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: horizontalSizeClass == .regular ? 1 : 0))
    }

    @MainActor
    private func handleJournalRowTap(_ item: JournalRowPresentation, isCheckout: Bool) {
        let row = item.row
        HapticManager.shared.selection()
        if isCheckout {
            if item.unassigned && canManageVehicle {
                pendingCheckoutRow = row
                assignContext = assignContext(for: row, mode: .assign)
            } else {
                detailRow = WheelSysJournalDetailContext(row: row, isCheckout: true)
                Task { await journalVM.enrichIfNeeded(entityId: row.rentalEntityId) }
            }
        } else {
            openReturnOperation(for: row)
        }
    }

    /// After journal assign — resume parked checkout when the assigned vehicle was last parked.
    @MainActor
    private func openCheckoutAfterAssign(
        for row: WheelSysJournalRow,
        assignedPlate: String?,
        customerEmail: String? = nil
    ) async {
        await openCheckoutOperation(
            for: row,
            assignedPlate: assignedPlate,
            customerEmail: customerEmail,
            preferParkedResume: true
        )
    }

    @MainActor
    private func openCheckoutOperation(
        for row: WheelSysJournalRow,
        assignedPlate: String?,
        customerEmail: String? = nil,
        preferParkedResume: Bool = false
    ) async {
        let plate = (assignedPlate ?? row.plate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plate.isEmpty, plate != "—", plate != "-" else {
            journalVM.errorMessage = "wheelsys.checkout.unassigned".localized
            return
        }
        guard let arac = viewModel.findAracByPlate(plate) ?? viewModel.aracBulPlaka(plaka: plate) else {
            journalVM.errorMessage = String(
                format: "wheelsys.return.vehicle_not_in_fleet".localized,
                plate
            )
            return
        }
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let prefill = await WheelSysCheckoutPrefillResolver.resolveForJournalRow(
            row: row,
            franchiseId: franchiseId,
            assignedPlate: arac.plakaFormatli,
            customerEmail: customerEmail,
            customerNameHint: journalVM.customerName(for: row)
        )
        let parkedId = preferParkedResume ? latestParkedCheckout(for: arac)?.id : nil
        checkoutExitContext = WheelSysCheckoutExitContext(
            arac: arac,
            prefill: prefill,
            resumeParkedExitId: parkedId
        )
    }

    private func latestParkedCheckout(for arac: Arac) -> ExitIslemi? {
        viewModel.exitIslemleri
            .filter { $0.aracId == arac.id && $0.status == .parked && !$0.isDeleted }
            .max { checkoutRecency($0) < checkoutRecency($1) }
    }

    private func checkoutRecency(_ exit: ExitIslemi) -> Date {
        max(exit.createdAt, exit.exitTarihi)
    }

    @MainActor
    private func openReturnOperation(for row: WheelSysJournalRow) {
        guard let prefill = WheelSysJournalService.buildReturnPrefill(
            from: row,
            snapshot: journalVM.journalSnapshot
        ) else {
            journalVM.errorMessage = "wheelsys.return.candidate_missing".localized
            return
        }
        guard let arac = viewModel.aracBulPlaka(plaka: row.plate) else {
            journalVM.errorMessage = String(
                format: "wheelsys.return.vehicle_not_in_fleet".localized,
                row.plate
            )
            return
        }
        iadeReturnContext = WheelSysIadeReturnContext(arac: arac, prefill: prefill)
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
        Self.zurichDayFormatter.string(from: journalVM.selectedDay)
    }

    private func isEnrichingDetail(entityId: Int) -> Bool {
        journalVM.checkoutRows.contains { $0.rentalEntityId == entityId && $0.enrichmentStatus == .loading }
            || journalVM.returnRows.contains { $0.rentalEntityId == entityId && $0.enrichmentStatus == .loading }
    }

    private func mainDocText(for row: WheelSysJournalRow) -> String {
        let code = resColumnText(for: row).trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? "—" : code
    }

    /// RES column — always prefer RES- code over agent confirmation / entity id.
    private func resColumnText(for row: WheelSysJournalRow) -> String {
        let candidates = [
            row.linkedResCode,
            row.resCode,
            WheelSysResCode.isReservationCode(row.mainDocNo) ? row.mainDocNo : nil,
            row.mainDocNo
        ]
        for raw in candidates {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }
            if WheelSysResCode.isReservationCode(trimmed) {
                return WheelSysResCode.normalizedReservationCode(trimmed) ?? trimmed
            }
        }
        return row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mainDocCell(for row: WheelSysJournalRow, isCheckout: Bool, width: CGFloat) -> some View {
        let main = mainDocText(for: row)
        let conf = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let showConfOnly = !isCheckout && main == "—" && !conf.isEmpty
        let raDoc = row.rentalNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showRaSecondary = !isCheckout
            && !raDoc.isEmpty
            && raDoc.uppercased().hasPrefix("RNT")
            && main != "—"
            && main != raDoc

        return VStack(alignment: .leading, spacing: 1) {
            Text(main)
                .font(.caption.weight(.bold))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if showRaSecondary {
                Text("RA: \(raDoc)")
                    .font(.system(size: 8))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if showConfOnly {
                Text("Conf: \(conf)")
                    .font(.system(size: 8))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func resCodeText(for row: WheelSysJournalRow) -> String {
        mainDocText(for: row)
    }

    private func fleetVehicleForJournalRow(_ row: WheelSysJournalRow) -> WheelSysFleetVehicle? {
        let norm = WheelSysPlateNormalizer.canonical(row.plate)
        guard !norm.isEmpty else { return nil }
        return journalVM.fleetVehicles.first {
            WheelSysPlateNormalizer.canonical($0.plate) == norm
        }
    }

    private func journalMileageForRow(_ row: WheelSysJournalRow) -> Int? {
        guard let snapshot = journalVM.journalSnapshot else { return nil }
        switch row.kind {
        case .checkout:
            return nil
        case .return:
            return snapshot.checkIns.first(where: {
                $0.rentalEntityId == row.rentalEntityId
            })?.mileage
        }
    }

    private func journalFuelForRow(_ row: WheelSysJournalRow) -> Int? {
        guard let snapshot = journalVM.journalSnapshot else { return nil }
        switch row.kind {
        case .checkout:
            return snapshot.checkOuts.first(where: {
                $0.rentalEntityId == row.rentalEntityId || $0.bookingEntityId == row.rentalEntityId
            })?.fuel
        case .return:
            return snapshot.checkIns.first(where: {
                $0.rentalEntityId == row.rentalEntityId
            })?.fuel
        }
    }

    private func rowShowsUnassigned(_ row: WheelSysJournalRow) -> Bool {
        isPlateUnassigned(row.plate)
    }

    private func isPlateUnassigned(_ plate: String) -> Bool {
        let t = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" || t == "—"
    }

    private func fuelText(for row: WheelSysJournalRow, fuelByEntityId: [String: String]) -> String {
        let prefix = row.kind == .checkout ? "co:" : "ci:"
        if let cached = fuelByEntityId["\(prefix)\(row.rentalEntityId)"] {
            return cached
        }
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
        Self.zurichTimeFormatter.string(from: date)
    }

    private func assignContext(
        for row: WheelSysJournalRow,
        mode: WheelSysVehicleUpdateMode
    ) -> WheelSysAssignBookingContext {
        let from = row.eventStart ?? row.eventDateTime
        let to = row.eventEnd ?? Calendar.current.date(byAdding: .day, value: 1, to: from) ?? from
        let trimmedRes = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        let res = WheelSysResCode.normalizedReservationCode(trimmedRes) ?? (trimmedRes.isEmpty ? nil : trimmedRes)
        let agentConf = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines)
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
            currentPlate: currentPlate,
            customerName: {
                let name = journalVM.customerName(for: row).trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty || name == "-" ? nil : name
            }()
        )
    }
}

// MARK: - Context types

struct WheelSysCheckoutExitContext: Identifiable, Hashable {
    let arac: Arac
    let prefill: WheelSysCheckoutPrefill
    var resumeParkedExitId: UUID?
    var id: UUID { arac.id }
}

struct WheelSysJournalDetailContext: Identifiable, Hashable {
    let row: WheelSysJournalRow
    let isCheckout: Bool
    var id: String { row.id }
}

struct WheelSysReturnCheckinContext: Identifiable, Hashable {
    let candidate: WheelSysReturnCandidate
    let entryPoint: WheelSysReturnEntryPoint
    var id: String { "\(candidate.id)-\(entryPoint.rawValue)" }
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
    var customerName: String? = nil

    var id: String { "\(bookingEntityId)-\(mode.rawValue)" }
}
