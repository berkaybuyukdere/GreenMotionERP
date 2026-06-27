import SwiftUI

/// CH checkout entry: journal checkout list with date navigation and category highlight.
struct WheelSysCheckoutJournalPickerView: View {
    let arac: Arac
    var onSelect: (WheelSysCheckoutPrefill) -> Void
    var onCancel: () -> Void

    @StateObject private var journalVM: WheelSysJournalViewModel
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectingEntityId: Int?
    @State private var selectionError: String?
    @State private var categoryOverrideBanner: (vehicleGroup: String, reservationGroup: String)?
    @State private var assignContext: WheelSysAssignBookingContext?
    @State private var pendingAssignRow: WheelSysJournalRow?
    @State private var pendingCarGroupOverride: String?
    @State private var pendingBookingPreview: WheelSysBookingPreview?

    private static let palantirPurple = Color(red: 0.427, green: 0.365, blue: 0.988)
    private static let unassignedRowFill = PalantirTheme.surfaceHigh
    private static let assignedRowFill = palantirPurple.opacity(0.14)
    private static let mutedRowFill = PalantirTheme.surfaceHigh

    private var checkoutPlateNorm: String {
        WheelSysPlateNormalizer.canonical(arac.plaka)
    }

    private var vehicleCategoryCode: String {
        journalVM.highlightGroup.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// When the journal has at least one checkout in the vehicle's category, use gray/purple styling.
    private var usesCategoryHighlightPalette: Bool {
        guard !vehicleCategoryCode.isEmpty else { return false }
        return journalVM.checkoutRows.contains { rowCategory(for: $0) == vehicleCategoryCode }
    }

    /// Today's checkout row already tied to this plate (vehicle assigned, customer not picked up).
    private var preAssignedCheckoutRow: WheelSysJournalRow? {
        journalVM.checkoutRows.first { row in
            let plate = row.plate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plate.isEmpty, !row.isUnassigned else { return false }
            return WheelSysPlateNormalizer.canonical(plate) == checkoutPlateNorm
        }
    }

    private var vehicleIsPreAssignedToBooking: Bool {
        guard preAssignedCheckoutRow != nil else { return false }
        let fleetStatus = WheelSysVehicleFleetStatusStore.shared
            .fleetVehicle(for: arac)?
            .status
            .lowercased() ?? "available"
        return fleetStatus == "available"
    }

    init(
        arac: Arac,
        onSelect: @escaping (WheelSysCheckoutPrefill) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.arac = arac
        self.onSelect = onSelect
        self.onCancel = onCancel
        _journalVM = StateObject(wrappedValue: WheelSysJournalViewModel(
            franchiseId: FirebaseService.shared.currentFranchiseId.uppercased()
        ))
    }

    var body: some View {
        NavigationView {
            Group {
                if journalVM.loading && journalVM.checkoutRows.isEmpty {
                    PalantirOpsLoadingOverlay(
                        title: "wheelsys.checkout.journal_loading".localized,
                        microcopy: PalantirOpsPhase.fetching.microcopy,
                        step: PalantirOpsPhase.fetching.step,
                        floating: false
                    )
                } else {
                    journalContent
                }
            }
            .wheelSysCHOpsChrome()
            .navigationTitle("wheelsys.checkout.journal_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { onCancel() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await journalVM.loadJournal() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(journalVM.loading)
                }
            }
            .task {
                journalVM.goToToday()
                journalVM.resolveHighlightGroup(forPlate: arac.plaka)
                journalVM.warmFromLocalFleetCache()
                await journalVM.loadJournal(background: !journalVM.checkoutRows.isEmpty)
                journalVM.resolveHighlightGroup(forPlate: arac.plaka)
            }
            .onChange(of: journalVM.selectedDay) { _, _ in
                Task { await journalVM.loadJournal() }
            }
            .alert("Error".localized, isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(selectionError ?? "")
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
                    mode: .assign,
                    customerName: context.customerName,
                    preselectedPlate: arac.plakaFormatli,
                    preselectedVehicleId: Int(arac.wheelsysVehicleId ?? "")
                ) { _, email in
                    guard let row = pendingAssignRow else { return }
                    let override = pendingCarGroupOverride
                    let preview = pendingBookingPreview
                    pendingAssignRow = nil
                    pendingCarGroupOverride = nil
                    pendingBookingPreview = nil
                    Task {
                        await journalVM.loadJournal()
                        deliverPrefill(
                            from: row,
                            carGroupOverride: override,
                            bookingPreview: preview,
                            customerEmail: email
                        )
                    }
                }
            }
        }
    }

    private var journalContent: some View {
        VStack(spacing: 0) {
            if !journalVM.checkoutRows.isEmpty || !journalVM.returnRows.isEmpty {
                WheelSysPalantirMetricsBar(items: [
                    (
                        icon: "arrow.up.right.circle.fill",
                        label: "ch_ops.checkout_section".localized,
                        value: "\(journalVM.checkoutRows.count)",
                        tint: PalantirTheme.accent
                    ),
                    (
                        icon: "car.side.fill",
                        label: "wheelsys_daily.tab_available".localized,
                        value: "\(journalVM.availableVehicles.count)",
                        tint: Self.palantirPurple
                    )
                ], compact: true)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            dateToolbar
            if let override = categoryOverrideBanner {
                categoryOverrideInfoBanner(vehicleGroup: override.vehicleGroup, reservationGroup: override.reservationGroup)
            } else if vehicleIsPreAssignedToBooking, let assigned = preAssignedCheckoutRow {
                preAssignedBanner(assigned)
            } else if !journalVM.highlightGroup.isEmpty {
                highlightBanner
            }
            columnHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    if journalVM.checkoutRows.isEmpty {
                        Text("ch_ops.checkout_empty".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                            .padding(16)
                    } else {
                        ForEach(journalVM.checkoutRows) { row in
                            journalRow(row)
                        }
                    }
                }
            }
        }
        .background(PalantirTheme.background)
    }

    private var dateToolbar: some View {
        HStack(spacing: 10) {
            WheelSysJournalDateNavButton(systemName: "chevron.left.circle.fill") {
                journalVM.shiftDay(-1)
            }

            DatePicker("", selection: Binding(
                get: { journalVM.selectedDay },
                set: { journalVM.setSelectedDay($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity)

            WheelSysJournalDateNavButton(systemName: "chevron.right.circle.fill") {
                journalVM.shiftDay(1)
            }

            Button {
                HapticManager.shared.selection()
                journalVM.goToToday()
            } label: {
                Text("ch_ops.today".localized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(PalantirTheme.surface)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if journalVM.loading {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PalantirTheme.surfaceHigh)
    }

    private func categoryOverrideInfoBanner(vehicleGroup: String, reservationGroup: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .foregroundStyle(PalantirTheme.accent)
            Text(String(
                format: "wheelsys.checkout.category_auto_override".localized,
                vehicleGroup,
                reservationGroup
            ))
            .font(.caption)
            .foregroundStyle(PalantirTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PalantirTheme.accent.opacity(0.12))
    }

    private var highlightBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .foregroundStyle(Self.palantirPurple)
            Text(String(format: "wheelsys.checkout.group_hint".localized, journalVM.highlightGroup, arac.plakaFormatli))
                .font(.caption)
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Self.palantirPurple.opacity(0.12))
    }

    private func preAssignedBanner(_ row: WheelSysJournalRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Self.palantirPurple)
            Text(String(
                format: "wheelsys.checkout.assigned_hint".localized,
                row.mainDocNo.isEmpty ? "—" : row.mainDocNo,
                arac.plakaFormatli
            ))
            .font(.caption)
            .foregroundStyle(PalantirTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Self.palantirPurple.opacity(0.12))
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            headerCell("wheelsys_journal.col_res".localized, width: 72)
            headerCell("ch_ops.col_plate".localized, width: 72)
            headerCell("ch_ops.col_group".localized, width: 40)
            headerCell("wheelsys_journal.col_driver".localized, width: 100)
            headerCell("ch_ops.col_time".localized, width: 44)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
    }

    private func journalRow(_ row: WheelSysJournalRow) -> some View {
        let highlighted = rowShouldHighlight(row)
        let isSelecting = selectingEntityId == row.effectiveBookingEntityId
        let resText = row.mainDocNo.isEmpty ? "—" : row.mainDocNo
        let muted = usesCategoryHighlightPalette && !highlighted && !vehicleIsPreAssignedToBooking

        return HStack(spacing: 6) {
            Text(resText)
                .font(.caption.weight(.bold))
                .frame(width: 72, alignment: .leading)
                .lineLimit(2)
                .foregroundStyle(muted ? PalantirTheme.textMuted : PalantirTheme.textPrimary)
            Text(row.plate.isEmpty ? "—" : row.plate)
                .font(.caption.weight(.semibold).monospaced())
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(muted ? PalantirTheme.textMuted : PalantirTheme.textPrimary)
            Text(journalVM.vehicleGroup(for: row))
                .font(.caption)
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(highlighted ? Self.palantirPurple : (muted ? PalantirTheme.textMuted : PalantirTheme.textPrimary))
            Text(journalVM.customerName(for: row))
                .font(.caption)
                .frame(width: 100, alignment: .leading)
                .lineLimit(2)
                .foregroundStyle(muted ? PalantirTheme.textMuted : PalantirTheme.textPrimary)
            Text(formatTime(row.eventDateTime))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(muted ? PalantirTheme.textMuted : PalantirTheme.textPrimary)
            if isSelecting {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground(for: row, highlighted: highlighted))
        .overlay(alignment: .leading) {
            let unassigned = row.isUnassigned || row.plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if highlighted {
                Rectangle()
                    .fill(Self.palantirPurple)
                    .frame(width: 3)
            } else if !usesCategoryHighlightPalette && !vehicleIsPreAssignedToBooking {
                Rectangle()
                    .fill(unassigned ? PalantirTheme.textMuted.opacity(0.45) : Self.palantirPurple)
                    .frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.selection()
            Task { await handleCheckoutRowSelected(row) }
        }
    }

    private func rowCategory(for row: WheelSysJournalRow) -> String {
        journalVM.vehicleGroup(for: row).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func rowMatchesHighlight(_ row: WheelSysJournalRow) -> Bool {
        guard !vehicleCategoryCode.isEmpty else { return false }
        return rowCategory(for: row) == vehicleCategoryCode
    }

    private func rowHasCategoryMismatch(_ row: WheelSysJournalRow) -> Bool {
        guard !vehicleCategoryCode.isEmpty else { return false }
        let reservationGroup = rowCategory(for: row)
        guard !reservationGroup.isEmpty, reservationGroup != "-" else { return false }
        return reservationGroup != vehicleCategoryCode
    }

    private func rowShouldHighlight(_ row: WheelSysJournalRow) -> Bool {
        if vehicleIsPreAssignedToBooking, let assigned = preAssignedCheckoutRow {
            return row.effectiveBookingEntityId == assigned.effectiveBookingEntityId
        }
        return rowMatchesHighlight(row)
    }

    private func rowBackground(for row: WheelSysJournalRow, highlighted: Bool) -> Color {
        if highlighted { return Self.palantirPurple.opacity(0.16) }
        if vehicleIsPreAssignedToBooking { return Self.mutedRowFill }
        if usesCategoryHighlightPalette { return Self.mutedRowFill }
        let unassigned = row.isUnassigned || row.plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return unassigned ? Self.unassignedRowFill : Self.assignedRowFill
    }

    @MainActor
    private func handleCheckoutRowSelected(_ row: WheelSysJournalRow) async {
        let reservationGroup = rowCategory(for: row)
        if rowHasCategoryMismatch(row) {
            categoryOverrideBanner = (vehicleGroup: vehicleCategoryCode, reservationGroup: reservationGroup)
        } else {
            categoryOverrideBanner = nil
        }
        let override = rowHasCategoryMismatch(row) ? reservationGroup : nil
        await beginAssign(from: row, carGroupOverride: override)
    }

    @MainActor
    private func beginAssign(from row: WheelSysJournalRow, carGroupOverride: String?) async {
        selectingEntityId = row.effectiveBookingEntityId
        defer { selectingEntityId = nil }

        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        var resNo = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if resNo.isEmpty {
            resNo = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var bookingPreview: WheelSysBookingPreview?
        if !WheelSysResCode.isReservationCode(resNo) {
            bookingPreview = try? await WheelSysCheckinService.loadBookingPreview(
                franchiseId: franchiseId,
                entityId: row.effectiveBookingEntityId,
                resNo: resNo,
                displayDocNo: row.displayDocNo
            )
            if let previewRes = bookingPreview?.resNo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                resNo = previewRes
            } else if !WheelSysResCode.isReservationCode(resNo) {
                selectionError = WheelSysUserFacingError.message(
                    for: WheelSysCheckinServiceError.operationFailed(
                        "Reservation code could not be resolved.".localized
                    )
                )
                HapticManager.shared.error()
                return
            }
        }

        let assignGroup = carGroupOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? journalVM.vehicleGroup(for: row)

        let needsAssign = row.isUnassigned
            || row.plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || WheelSysPlateNormalizer.canonical(row.plate) != checkoutPlateNorm
            || carGroupOverride != nil

        if needsAssign {
            await silentAssignCurrentVehicle(
                from: row,
                carGroupOverride: carGroupOverride,
                bookingPreview: bookingPreview
            )
            return
        }

        deliverPrefill(
            from: row,
            carGroupOverride: carGroupOverride,
            bookingPreview: bookingPreview,
            customerEmail: nil
        )
        HapticManager.shared.success()
    }

    @MainActor
    private func deliverPrefill(
        from row: WheelSysJournalRow,
        carGroupOverride: String?,
        bookingPreview: WheelSysBookingPreview?,
        customerEmail: String?
    ) {
        var resNo = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if resNo.isEmpty {
            resNo = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let previewRes = bookingPreview?.resNo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            resNo = previewRes
        }
        let assignGroup = carGroupOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? journalVM.vehicleGroup(for: row)
        let journalCustomer = journalVM.customerName(for: row)
        let customer = bookingPreview?.driverName
            ?? (journalCustomer == "-" ? nil : journalCustomer)
        let email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let prefill = WheelSysCheckoutPrefillResolver.enrichCheckoutPrefill(
            WheelSysCheckoutPrefill(
                bookingEntityId: row.effectiveBookingEntityId,
                resNo: resNo,
                customerName: customer,
                customerEmail: email,
                confirmationNo: bookingPreview?.confirmationNo,
                vehicleGroup: assignGroup,
                eventDateTime: row.eventDateTime,
                plannedReturnDate: row.eventEnd ?? row.eventStart,
                assignedPlate: arac.plakaFormatli,
                isUnassigned: false,
                insurance: bookingPreview?.insurance,
                rentalDays: bookingPreview?.rentalDays,
                checkoutMileage: fleetMileageForCurrentVehicle(),
                irn: bookingPreview?.irn
            ),
            booking: bookingPreview,
            fleetMileage: fleetMileageForCurrentVehicle()
        )
        onSelect(prefill)
    }

    private func fleetMileageForCurrentVehicle() -> Int? {
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        let mileage = (
            WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac) ??
            WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka)
        )?.mileage
        guard let mileage, mileage > 0 else { return nil }
        return mileage
    }

    @MainActor
    private func silentAssignCurrentVehicle(
        from row: WheelSysJournalRow,
        carGroupOverride: String?,
        bookingPreview: WheelSysBookingPreview?
    ) async {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let assignGroup = carGroupOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? journalVM.vehicleGroup(for: row)

        var resNo = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if resNo.isEmpty {
            resNo = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let previewRes = bookingPreview?.resNo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            resNo = previewRes
        }
        if let normalized = WheelSysResCode.normalizedReservationCode(resNo) {
            resNo = normalized
        }

        let dateFrom = row.eventStart ?? row.eventDateTime ?? Date()
        let dateTo = row.eventEnd ?? Calendar.current.date(byAdding: .day, value: 1, to: dateFrom) ?? dateFrom
        let station = row.station.isEmpty ? "ZRH" : row.station

        let fetcher = WheelSysBookingPageFetcher(bookingEntityId: row.effectiveBookingEntityId)
        defer { fetcher.cleanup() }

        do {
            HapticManager.shared.medium()
            async let ctxTask = fetcher.loadAndExtractContext()
            async let vehicleTask = resolveAssignableVehicle(
                bookingEntityId: row.effectiveBookingEntityId,
                franchiseId: franchiseId,
                station: station,
                dateFrom: dateFrom,
                dateTo: dateTo,
                assignGroup: assignGroup,
                resNo: resNo,
                displayDocNo: row.displayDocNo
            )
            let ctx = try await ctxTask
            let vehicle = try await vehicleTask

            let usageReq = Int(ctx.usageType ?? "1") ?? 1
            let canUse = try await fetcher.checkCanUseCar(
                plate: vehicle.plateNo,
                vehicleId: vehicle.id,
                dateFrom: checkoutUtcIso(dateFrom),
                dateTo: checkoutUtcIso(dateTo),
                usageReq: usageReq
            )
            guard canUse.isUsable == true else {
                selectionError = canUse.warningMessage ?? "wheelsys_assign.canusecar_blocked".localized
                HapticManager.shared.error()
                return
            }

            let operationalGroup = WheelSysCategoryNormalizer.normalize(
                assignGroup.isEmpty ? (ctx.operationalGroup ?? vehicle.carGroup) : assignGroup
            )
            let modelName = canUse.carInfo?.modelName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? vehicle.modelName
            let modelId = canUse.carInfo?.modelTableId ?? vehicle.modelId
            let payload = WheelSysVehicleAssignPayload(
                plate: vehicle.plateNo,
                vehicleId: vehicle.id,
                operationalGroup: operationalGroup,
                modelName: modelName,
                modelId: modelId > 0 ? modelId : vehicle.modelId
            )

            _ = try await fetcher.performAssign(
                plate: vehicle.plateNo,
                vehicleId: vehicle.id,
                payload: payload
            )

            HapticManager.shared.success()
            WheelSysActivityReporter.record(
                .vehicleAssigned(plate: vehicle.plateNo, resNo: resNo.nilIfEmpty),
                viewModel: viewModel,
                userProfile: authManager.userProfile
            )
            Task { await journalVM.loadJournal(background: true) }
            deliverPrefill(
                from: row,
                carGroupOverride: carGroupOverride,
                bookingPreview: bookingPreview,
                customerEmail: bookingPreview?.customerEmail
            )
        } catch {
            selectionError = WheelSysUserFacingError.message(for: error)
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func resolveAssignableVehicle(
        bookingEntityId: Int,
        franchiseId: String,
        station: String,
        dateFrom: Date,
        dateTo: Date,
        assignGroup: String,
        resNo: String,
        displayDocNo: String
    ) async throws -> WheelSysAssignableVehicle {
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        let plateNorm = checkoutPlateNorm

        if let synthetic = syntheticAssignableVehicle(
            assignGroup: assignGroup,
            station: station
        ) {
            return synthetic
        }

        let vehicles = try await WheelSysCheckinService.searchAvailableVehicles(
            franchiseId: franchiseId,
            bookingEntityId: bookingEntityId,
            station: station,
            dateFrom: checkoutLocalIso(dateFrom),
            dateTo: checkoutLocalIso(dateTo),
            carGroup: nil,
            resNo: resNo,
            displayDocNo: displayDocNo,
            entireFleet: true
        )
        if let match = vehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plateNo) == plateNorm
        }) {
            return match
        }

        throw WheelSysCheckinServiceError.operationFailed(
            String(format: "WheelSys vehicle id not found for plate %@.".localized, arac.plakaFormatli)
        )
    }

    @MainActor
    private func syntheticAssignableVehicle(
        assignGroup: String,
        station: String
    ) -> WheelSysAssignableVehicle? {
        let mileage = fleetMileageForCurrentVehicle() ?? 0
        let group = assignGroup.trimmingCharacters(in: .whitespacesAndNewlines)

        if let stored = arac.wheelsysVehicleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let vid = Int(stored), vid > 0 {
            return WheelSysAssignableVehicle(
                id: vid,
                plateNo: arac.plaka,
                carGroup: group,
                grpcode: group,
                cargroup: group,
                modelName: "",
                modelId: 0,
                mileage: mileage,
                fuel: 8,
                station: station,
                lastCheckin: "",
                readyToGo: true,
                active: true,
                inUse: false,
                hardHold: false,
                onService: false
            )
        }

        if let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)
            ?? WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka),
           let vid = Int(fleetVehicle.vehicleId), vid > 0 {
            return WheelSysAssignableVehicle(
                id: vid,
                plateNo: arac.plaka,
                carGroup: group.isEmpty ? fleetVehicle.group : group,
                grpcode: group.isEmpty ? fleetVehicle.group : group,
                cargroup: group.isEmpty ? fleetVehicle.group : group,
                modelName: fleetVehicle.model,
                modelId: 0,
                mileage: fleetVehicle.mileage > 0 ? fleetVehicle.mileage : mileage,
                fuel: 8,
                station: station,
                lastCheckin: "",
                readyToGo: true,
                active: true,
                inUse: false,
                hardHold: false,
                onService: false
            )
        }

        return nil
    }

    private func checkoutLocalIso(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.timeZone = TimeZone(identifier: "Europe/Zurich")
        df.formatOptions = [.withInternetDateTime]
        return df.string(from: date)
    }

    private func checkoutUtcIso(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.string(from: date)
    }

    private func buildAssignContext(
        from row: WheelSysJournalRow,
        carGroup: String,
        bookingPreview: WheelSysBookingPreview?
    ) -> WheelSysAssignBookingContext {
        let dateFrom = row.eventStart ?? row.eventDateTime
        let dateTo = row.eventEnd ?? Calendar.current.date(byAdding: .day, value: 1, to: dateFrom) ?? dateFrom
        var trimmedRes = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRes.isEmpty {
            trimmedRes = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let previewRes = bookingPreview?.resNo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            trimmedRes = previewRes
        }
        let res = WheelSysResCode.normalizedReservationCode(trimmedRes) ?? (trimmedRes.isEmpty ? nil : trimmedRes)
        let agentConf = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let journalCustomer = journalVM.customerName(for: row)
        let customerName: String? = {
            let name = (bookingPreview?.driverName ?? journalCustomer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || name == "-" ? nil : name
        }()
        return WheelSysAssignBookingContext(
            bookingEntityId: row.effectiveBookingEntityId,
            carGroup: carGroup,
            dateFrom: dateFrom,
            dateTo: dateTo,
            station: row.station.isEmpty ? "ZRH" : row.station,
            resNo: res,
            confirmationNo: agentConf.isEmpty ? bookingPreview?.confirmationNo : agentConf,
            mode: .assign,
            customerName: customerName
        )
    }

    @MainActor
    private func completeAssign(from row: WheelSysJournalRow, carGroupOverride: String?) async {
        await beginAssign(from: row, carGroupOverride: carGroupOverride)
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
