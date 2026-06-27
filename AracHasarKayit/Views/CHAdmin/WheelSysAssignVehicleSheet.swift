import SwiftUI
import FirebaseAuth
import FirebaseFunctions

/// Modal sheet: loads booking.aspx context via WKWebView, searches available fleet,
/// then performs the real BTSAVE POST directly from the authenticated WebView.
/// Supports assign, change, and remove modes.
struct WheelSysAssignVehicleSheet: View {
    let bookingEntityId: Int
    let carGroup: String
    let dateFrom: Date
    let dateTo: Date
    let station: String
    /// RES code pre-filled from the journal / daily-view row (e.g. "RES-17694").
    var resNo: String?
    /// Agent/external confirmation code pre-filled from the row (e.g. "JIG(A)-…").
    var confirmationNo: String?
    /// Operation mode — assign (default), change, or remove.
    var mode: WheelSysVehicleUpdateMode = .assign
    /// Currently assigned plate (for change/remove UI).
    var currentPlate: String? = nil
    /// Driver / customer display name from journal or booking page.
    var customerName: String? = nil
    /// When opened from vehicle checkout journal — pre-select this plate in the picker.
    var preselectedPlate: String? = nil
    var preselectedVehicleId: Int? = nil
    var onAssigned: ((WheelSysAssignableVehicle?, String?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var allVehicles: [WheelSysAssignableVehicle] = []
    @State private var selectedCategory: String = ""
    @State private var phase: AssignPhase = .loadingPage
    @State private var assigning = false
    @State private var selectedVehicle: WheelSysAssignableVehicle?
    @State private var showRemoveConfirm = false
    @State private var errorMessage: String?
    /// Context extracted from the live booking.aspx DOM — authoritative source.
    @State private var bookingPageContext: WheelSysBookingPageContext?
    /// WKWebView-based fetcher; kept alive for the BTSAVE call.
    @State private var fetcher: WheelSysBookingPageFetcher?
    @State private var correlationId = WheelSysDebug.newCorrelationId()
    /// Guard: context is currently being loaded.
    @State private var isLoadingContext = false
    /// Guard: context already successfully loaded (prevent double-load).
    @State private var didLoadContext = false
    /// Guard against duplicate confirm taps.
    @State private var isAssigning = false
    @State private var showVehiclePicker = false
    @State private var previewCustomerEmail: String?

    private enum AssignPhase {
        /// Booking.aspx loading in WebView + vehicle list loading.
        case loadingPage
        /// Both loaded — user can pick a vehicle.
        case vehiclesReady
    }

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WheelSysPalantirFormSpacing.section) {
                    bookingSummaryCard
                    if mode == .remove {
                        removeSection
                    } else {
                        categorySection
                        vehicleSelectionSection
                    }
                }
                .padding(.horizontal, WheelSysPalantirFormSpacing.hPadding)
                .padding(.vertical, WheelSysPalantirFormSpacing.vPadding)
            }
            .background(PalantirTheme.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                        .disabled(assigning)
                }
            }
            .wheelSysCHOpsChrome()
            .task { await bootstrapAssignmentFlow() }
            .onDisappear { fetcher?.cleanup() }
            .alert("Error".localized, isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) {}
                Button("wheelsys_assign.retry_context".localized) {
                    Task { await bootstrapAssignmentFlow() }
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("wheelsys_assign.remove_confirm_title".localized, isPresented: $showRemoveConfirm) {
                Button("Cancel".localized, role: .cancel) {}
                Button("wheelsys_assign.remove_action".localized, role: .destructive) {
                    guard !isAssigning else { return }
                    Task { await confirmVehicleUpdate() }
                }
                .disabled(isAssigning)
            } message: {
                Text(String(
                    format: "wheelsys_assign.remove_confirm_body".localized,
                    effectiveCurrentPlate,
                    bookingEntityId
                ))
            }
            .overlay {
                if showVehiclePicker {
                    WheelSysAssignVehiclePickerOverlay(
                        title: "wheelsys_assign.picker_title".localized,
                        categoryCode: selectedCategory,
                        vehicles: pickerVehicles,
                        isLoading: phase == .loadingPage && allVehicles.isEmpty,
                        onSelect: { vehicle in
                            showVehiclePicker = false
                            selectedVehicle = vehicle
                            Task { await confirmVehicleUpdate() }
                        },
                        onDismiss: { showVehiclePicker = false }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .overlay {
                if assigning {
                    PalantirOpsBlockingOverlay(
                        title: "wheelsys.checkout.syncing_micro".localized,
                        microcopy: mode == .assign
                            ? "wheelsys_assign.assigning_micro".localized
                            : "wheelsys_assign.syncing_micro".localized
                    )
                }
            }
        }
    }

    private enum WheelSysPalantirFormSpacing {
        static let section: CGFloat = 13
        static let hPadding: CGFloat = 13
        static let vPadding: CGFloat = 11
    }

    // MARK: - Booking summary (checkout-style)

    private var bookingSummaryCard: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_assign.booking_section".localized,
            icon: "doc.text.fill",
            footer: effectiveConfirmationNo
        ) {
            WheelSysPalantirOpsHeader(
                title: effectiveResCode,
                subtitle: effectiveDriverName ?? customerName,
                badge: selectedCategory.isEmpty ? effectiveChargeGroup : selectedCategory
            )
            WheelSysPalantirMetricsBar(items: bookingMetricItems, compact: true)
            if let email = effectiveCustomerEmail {
                WheelSysPalantirStatusStrip(
                    icon: "envelope.fill",
                    message: email,
                    tint: PalantirTheme.accent
                )
            } else if phase == .vehiclesReady {
                WheelSysPalantirStatusStrip(
                    icon: "exclamationmark.triangle.fill",
                    message: "wheelsys_assign.email_missing_hint".localized,
                    tint: PalantirTheme.warning
                )
            }
            if showCategoryMismatchWarning {
                WheelSysPalantirStatusStrip(
                    icon: "arrow.left.arrow.right.circle.fill",
                    message: String(
                        format: "wheelsys.checkout.category_auto_override".localized,
                        categoryAutoOverrideVehicleGroup,
                        categoryAutoOverrideReservationGroup
                    ),
                    tint: PalantirTheme.accent
                )
            }
        }
    }

    private var bookingMetricItems: [(icon: String, label: String, value: String, tint: Color)] {
        var items: [(icon: String, label: String, value: String, tint: Color)] = [
            (
                icon: "number",
                label: "wheelsys_assign.booking".localized,
                value: "#\(bookingEntityId)",
                tint: PalantirTheme.accent
            ),
            (
                icon: "mappin.circle.fill",
                label: "wheelsys_journal.station".localized,
                value: station,
                tint: PalantirTheme.accent
            ),
            (
                icon: "calendar",
                label: "wheelsys_assign.period".localized,
                value: periodText,
                tint: PalantirTheme.accent
            )
        ]
        if !effectiveChargeGroup.isEmpty, effectiveChargeGroup != "—" {
            items.insert(
                (
                    icon: "square.grid.2x2",
                    label: "wheelsys_assign.booked_group".localized,
                    value: effectiveChargeGroup,
                    tint: PalantirTheme.accent
                ),
                at: 0
            )
        }
        if mode != .assign, !effectiveCurrentPlate.isEmpty, effectiveCurrentPlate != "—" {
            items.append(
                (
                    icon: "car.fill",
                    label: "wheelsys_assign.current_vehicle".localized,
                    value: effectiveCurrentPlate,
                    tint: PalantirTheme.warning
                )
            )
        }
        return items
    }

    private var effectiveCustomerEmail: String? {
        previewCustomerEmail?.trimmed.nonEmpty
    }

    // MARK: - Category

    private var categorySection: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_assign.category_section".localized,
            icon: "square.grid.2x2"
        ) {
            if availableCategories.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.85)
                    Text("wheelsys_assign.category_loading".localized)
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories, id: \.self) { category in
                            Button {
                                HapticManager.shared.selection()
                                selectedCategory = category
                            } label: {
                                Text(category)
                                    .font(.system(size: 12, weight: .bold).monospaced())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(
                                        selectedCategory == category
                                            ? PalantirTheme.onAccent
                                            : PalantirTheme.textPrimary
                                    )
                                    .background(
                                        selectedCategory == category
                                            ? PalantirTheme.accent
                                            : PalantirTheme.surfaceHigh
                                    )
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(
                                                selectedCategory == category
                                                    ? PalantirTheme.accent
                                                    : PalantirTheme.border,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text(String(
                format: "wheelsys_assign.available_count".localized,
                sameCategoryVehicleCount
            ))
            .font(PalantirTheme.labelFont(10))
            .foregroundStyle(PalantirTheme.textMuted)
        }
    }

    private var availableCategories: [String] {
        var set = Set<String>()
        for vehicle in allVehicles {
            for code in vehicle.categoryCodes where !code.isEmpty {
                set.insert(code)
            }
        }
        var sorted = set.sorted()
        let current = WheelSysCategoryNormalizer.normalize(selectedCategory)
        if !current.isEmpty, !sorted.contains(current) {
            sorted.insert(current, at: 0)
        }
        return sorted
    }

    private var eligibleVehicles: [WheelSysAssignableVehicle] {
        let stationNorm = WheelSysCategoryNormalizer.normalize(station)
        return allVehicles.filter { vehicle in
            guard !vehicle.plateNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard vehicle.active, !vehicle.inUse, !vehicle.hardHold, !vehicle.onService else { return false }
            let vehicleStation = WheelSysCategoryNormalizer.normalize(vehicle.station)
            if !vehicleStation.isEmpty, vehicleStation != stationNorm { return false }
            return true
        }
    }

    private var pickerVehicles: [WheelSysAssignableVehicle] {
        eligibleVehicles
    }

    private var sameCategoryVehicleCount: Int {
        let categoryNorm = WheelSysCategoryNormalizer.normalize(selectedCategory)
        guard !categoryNorm.isEmpty else { return eligibleVehicles.count }
        return eligibleVehicles.filter { $0.matchesCategory(categoryNorm) }.count
    }

    private var filteredVehicles: [WheelSysAssignableVehicle] {
        let categoryNorm = WheelSysCategoryNormalizer.normalize(selectedCategory)
        guard !categoryNorm.isEmpty else { return [] }
        return eligibleVehicles.filter { $0.matchesCategory(categoryNorm) }
    }

    private var effectiveChargeGroup: String {
        if let charge = bookingPageContext?.chargeGroup?.trimmed, !charge.isEmpty { return charge }
        if let res = bookingPageContext?.reservationGroup?.trimmed, !res.isEmpty { return res }
        let prefilled = carGroup.trimmed
        return prefilled.isEmpty || prefilled == "-" ? "—" : prefilled
    }

    private var showCategoryMismatchWarning: Bool {
        categoryAutoOverrideInfo != nil
    }

    private var categoryAutoOverrideInfo: (vehicle: String, reservation: String)? {
        guard mode == .assign else { return nil }
        let reservation = WheelSysCategoryNormalizer.normalize(effectiveChargeGroup == "—" ? nil : effectiveChargeGroup)
        guard !reservation.isEmpty else { return nil }
        if let vehicle = selectedVehicle {
            let vehicleGroup = WheelSysCategoryNormalizer.normalize(vehicle.categoryCodes.first)
            guard !vehicleGroup.isEmpty, vehicleGroup != reservation else { return nil }
            return (vehicleGroup, reservation)
        }
        if let plate = preselectedPlate?.trimmingCharacters(in: .whitespacesAndNewlines), !plate.isEmpty,
           let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate) {
            let vehicleGroup = WheelSysCategoryNormalizer.normalize(fleetVehicle.group)
            guard !vehicleGroup.isEmpty, vehicleGroup != reservation else { return nil }
            return (vehicleGroup, reservation)
        }
        return nil
    }

    private var categoryAutoOverrideVehicleGroup: String {
        categoryAutoOverrideInfo?.vehicle ?? ""
    }

    private var categoryAutoOverrideReservationGroup: String {
        categoryAutoOverrideInfo?.reservation ?? ""
    }

    // MARK: - Vehicle selection (single page)

    @ViewBuilder
    private var vehicleSelectionSection: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys_assign.vehicles_section".localized,
            icon: "car.side.fill"
        ) {
            if phase == .loadingPage && allVehicles.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("wheelsys_assign.loading_page".localized)
                            .font(PalantirTheme.bodyFont(12))
                        Text("wheelsys_assign.loading_page_detail".localized)
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if eligibleVehicles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "car.slash")
                        .font(.title2)
                        .foregroundStyle(PalantirTheme.textMuted)
                    Text("wheelsys_assign.empty".localized)
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                        .multilineTextAlignment(.center)
                    WheelSysPalantirSecondaryButton(
                        title: "wheelsys_assign.retry_context".localized,
                        icon: "arrow.clockwise"
                    ) {
                        Task { await bootstrapAssignmentFlow() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                if let selected = selectedVehicle {
                    selectedVehicleCard(selected)
                }
                WheelSysPalantirPrimaryButton(
                    title: selectedVehicle == nil
                        ? "wheelsys_assign.open_picker".localized
                        : "wheelsys_assign.change_vehicle".localized,
                    icon: "magnifyingglass",
                    disabled: assigning || isAssigning || selectedCategory.isEmpty
                ) {
                    HapticManager.shared.selection()
                    showVehiclePicker = true
                }
                if mode == .assign {
                    Text("wheelsys_assign.picker_flow_hint".localized)
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func selectedVehicleCard(_ vehicle: WheelSysAssignableVehicle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vehicle.plateNo)
                    .font(PalantirTheme.heroFont(16).monospaced())
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer(minLength: 0)
                if vehicle.readyToGo {
                    PalantirOpsBadge(text: "wheelsys_assign.ready_to_go".localized, tone: .success)
                }
            }
            HStack(spacing: 12) {
                Text(vehicle.modelName.isEmpty ? vehicle.carGroup : vehicle.modelName)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                Text("\(vehicle.mileage) km · \(vehicle.fuel)/8")
                    .font(PalantirTheme.dataFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.accent.opacity(0.08))
        .overlay(Rectangle().stroke(PalantirTheme.accent.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Remove

    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("wheelsys_assign.remove_warning".localized)
                    .font(.subheadline)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Image(systemName: "car.fill")
                        .foregroundStyle(PalantirTheme.warning)
                    Text(effectiveCurrentPlate)
                        .font(PalantirTheme.heroFont(16).monospaced())
                        .foregroundStyle(PalantirTheme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PalantirTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(PalantirTheme.border, lineWidth: 1)
                )
            }
            .palantirCard()

            Button {
                showRemoveConfirm = true
            } label: {
                Label("wheelsys_assign.remove_action".localized, systemImage: "minus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(PalantirTheme.critical)
            .disabled(assigning || isAssigning || effectiveCurrentPlate.isEmpty)
        }
    }

    // MARK: - Computed titles

    private var navigationTitle: String {
        switch mode {
        case .assign: return "wheelsys_assign.title".localized
        case .change: return "wheelsys_assign.change_title".localized
        case .remove: return "wheelsys_assign.remove_title".localized
        }
    }

    private var effectiveCurrentPlate: String {
        if let ctxPlate = bookingPageContext?.currentPlate?.trimmed, !ctxPlate.isEmpty {
            return ctxPlate
        }
        if let prefilled = currentPlate?.trimmed, !prefilled.isEmpty {
            return prefilled
        }
        return "—"
    }

    // MARK: - Computed display values

    /// RES number: always displayDocNo from booking page; fallback to pre-filled resNo.
    private var effectiveResCode: String {
        // 1. Authoritative: from live booking page DOM
        if let ctx = bookingPageContext,
           let docNo = ctx.displayDocNo?.trimmed, !docNo.isEmpty {
            return docNo
        }
        // 2. Pre-filled RES code from row (must look like RES-XXXXX)
        if let prefilled = resNo?.trimmed,
           !prefilled.isEmpty,
           WheelSysResCode.isReservationCode(prefilled) {
            return prefilled
        }
        // 3. Pre-filled as-is
        if let prefilled = resNo?.trimmed, !prefilled.isEmpty {
            return prefilled
        }
        return "—"
    }

    /// IRN: from booking page context.
    private var effectiveIrn: String? {
        bookingPageContext?.irn?.trimmed
    }

    /// Confirmation number: always confirmationNo, never shown as RES.
    private var effectiveConfirmationNo: String? {
        // 1. From live booking page DOM
        if let ctxConf = bookingPageContext?.confirmationNo?.trimmed, !ctxConf.isEmpty {
            return ctxConf
        }
        // 2. Pre-filled from row parameter
        if let prefConf = confirmationNo?.trimmed, !prefConf.isEmpty {
            return prefConf
        }
        return nil
    }

    private var effectiveDriverName: String? {
        bookingPageContext?.driverName?.trimmed.nonEmpty ?? customerName?.trimmed.nonEmpty
    }

    private var periodText: String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "Europe/Zurich")
        df.dateStyle = .short
        df.timeStyle = .short
        return "\(df.string(from: dateFrom)) → \(df.string(from: dateTo))"
    }

    // MARK: - Actions

    @MainActor
    private func bootstrapAssignmentFlow() async {
        phase = .loadingPage
        allVehicles = []
        selectedCategory = ""
        bookingPageContext = nil
        errorMessage = nil
        didLoadContext = false

        let newFetcher = WheelSysBookingPageFetcher(bookingEntityId: bookingEntityId)
        fetcher?.cleanup()
        fetcher = newFetcher

        WheelSysDebug.log("Assign", "start mode=\(mode.rawValue) bookingEntityId=\(bookingEntityId)", cid: correlationId)
        print("[WheelSys][Assign] start mode=\(mode.rawValue) bookingEntityId=\(bookingEntityId)")

        // Load booking page context + vehicles in parallel (skip vehicles for remove-only)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadBookingPageContext(using: newFetcher) }
            group.addTask { await loadCustomerPreview() }
            if mode != .remove {
                group.addTask { await loadVehicles() }
            }
        }

        phase = .vehiclesReady
        if selectedCategory.isEmpty, let ctx = bookingPageContext {
            applyDefaultCategory(from: ctx)
        } else if selectedCategory.isEmpty {
            let fallback = WheelSysCategoryNormalizer.normalize(carGroup.nilIfDash)
            if !fallback.isEmpty { selectedCategory = fallback }
        }

        applyPreselectedVehicleIfNeeded()
        applyReservationCategoryForPreselectedVehicle()
        if mode == .assign, !selectedCategory.isEmpty, !eligibleVehicles.isEmpty,
           preselectedPlate == nil, preselectedVehicleId == nil {
            showVehiclePicker = true
        }
    }

    /// When assigning a known vehicle to a reservation in another group, use the reservation category.
    @MainActor
    private func applyReservationCategoryForPreselectedVehicle() {
        guard mode == .assign else { return }
        let reservation = WheelSysCategoryNormalizer.normalize(effectiveChargeGroup == "—" ? nil : effectiveChargeGroup)
        guard !reservation.isEmpty else { return }
        let hasPreselected = (preselectedVehicleId ?? 0) > 0
            || !(preselectedPlate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasPreselected else { return }
        selectedCategory = reservation
    }

    @MainActor
    private func applyPreselectedVehicleIfNeeded() {
        guard selectedVehicle == nil else { return }
        if let vid = preselectedVehicleId, vid > 0,
           let match = allVehicles.first(where: { $0.id == vid }) {
            selectedVehicle = match
            if selectedCategory.isEmpty, let cat = match.categoryCodes.first {
                selectedCategory = cat
            }
            return
        }
        let plate = preselectedPlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !plate.isEmpty else { return }
        let norm = WheelSysPlateNormalizer.canonical(plate)
        guard let match = allVehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plateNo) == norm
        }) else { return }
        selectedVehicle = match
        if selectedCategory.isEmpty, let cat = match.categoryCodes.first {
            selectedCategory = cat
        }
    }

    @MainActor
    private func loadCustomerPreview() async {
        guard previewCustomerEmail == nil else { return }
        let res = (resNo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview = try? await WheelSysCheckinService.loadPreview(
            franchiseId: franchiseId,
            entityId: String(bookingEntityId),
            expectedResNo: res.isEmpty ? nil : res
        ) else { return }
        let email = preview.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            previewCustomerEmail = email
        }
    }

    @MainActor
    private func loadBookingPageContext(using f: WheelSysBookingPageFetcher) async {
        guard !isLoadingContext, !didLoadContext else {
            print("[WheelSys][Assign] context load skipped (isLoading=\(isLoadingContext) didLoad=\(didLoadContext))")
            return
        }
        isLoadingContext = true
        defer { isLoadingContext = false }

        do {
            let ctx = try await f.loadAndExtractContext()
            self.bookingPageContext = ctx
            self.didLoadContext = true
            applyDefaultCategory(from: ctx)
            // Authoritative values from live booking.aspx DOM
            print("[WheelSys][Assign] context patched "
                + "bookingEntityId=\(bookingEntityId) "
                + "RES=\(ctx.displayDocNo ?? "nil") "
                + "IRN=\(ctx.irn ?? "nil") "
                + "Conf=\(ctx.confirmationNo ?? "nil") "
                + "Voucher=\(ctx.voucherNo ?? "nil")")
            print("[WheelSys][Mapping] "
                + "id=\(bookingEntityId) "
                + "displayDocNo=\(ctx.displayDocNo ?? "nil") "
                + "confirmationNo=\(ctx.confirmationNo ?? "nil") "
                + "irn=\(ctx.irn ?? "nil") "
                + "voucher=\(ctx.voucherNo ?? "nil")")
        } catch {
            let desc = error.localizedDescription
            WheelSysDebug.error("Assign", "booking page context failed: \(desc)", cid: correlationId)
            // Show as non-fatal warning; user can still see vehicle list and retry
            if !(error is WheelSysBookingFetchError) || {
                if case .cacheKeyMissing = error as! WheelSysBookingFetchError { return true }
                return false
            }() {
                errorMessage = desc
            }
        }
    }

    private func applyDefaultCategory(from ctx: WheelSysBookingPageContext) {
        guard selectedCategory.isEmpty else { return }
        let candidates: [String?] = [
            ctx.operationalGroup,
            carGroup.nilIfDash,
            ctx.chargeGroup,
            ctx.reservationGroup,
        ]
        for candidate in candidates {
            let normalized = WheelSysCategoryNormalizer.normalize(candidate)
            if !normalized.isEmpty {
                selectedCategory = normalized
                print("[WheelSys][Assign] defaultCategory=\(normalized) "
                    + "operational=\(ctx.operationalGroup ?? "nil") "
                    + "charge=\(ctx.chargeGroup ?? "nil")")
                return
            }
        }
    }

    @MainActor
    private func loadVehicles() async {
        do {
            let loaded = try await WheelSysCheckinService.searchAvailableVehicles(
                franchiseId: franchiseId,
                bookingEntityId: bookingEntityId,
                station: station,
                dateFrom: isoDateTime(dateFrom),
                dateTo: isoDateTime(dateTo),
                carGroup: nil,
                resNo: resNo?.trimmed,
                displayDocNo: nil,
                entireFleet: true
            )
            allVehicles = loaded
            WheelSysDebug.log("Assign", "vehicles loaded=\(allVehicles.count)", cid: correlationId)
        } catch {
            WheelSysDebug.error("Assign", "load vehicles: \(WheelSysCheckinService.describeCallableError(error))", cid: correlationId)
            if allVehicles.isEmpty {
                errorMessage = "wheelsys_assign.error_load_vehicles".localized
                    + " " + WheelSysCheckinService.describeCallableError(error)
            }
        }
    }

    @MainActor
    private func confirmVehicleUpdate() async {
        guard !isAssigning else {
            print("[WheelSys][Assign] ignored duplicate confirm tap cid=\(correlationId)")
            return
        }
        if mode != .remove {
            guard selectedVehicle != nil else { return }
        }
        guard let f = fetcher else {
            errorMessage = "Booking page fetcher not ready. Please retry."
            return
        }

        isAssigning = true
        assigning = true
        defer {
            isAssigning = false
            assigning = false
        }

        let oldPlate = effectiveCurrentPlate == "—" ? nil : effectiveCurrentPlate

        do {
            // Always reload fresh booking page context before save
            WheelSysDebug.log("Assign", "reloading fresh context before \(mode.rawValue)", cid: correlationId)
            let ctx = try await f.loadAndExtractContext()
            bookingPageContext = ctx
            didLoadContext = true

            switch mode {
            case .assign, .change:
                guard let vehicle = selectedVehicle else { return }
                let oldOperational = ctx.operationalGroup ?? carGroup
                let charge = ctx.chargeGroup ?? effectiveChargeGroup
                let usageReq = Int(ctx.usageType ?? "1") ?? 1

                print("[WheelSys][Assign] mode=\(mode.rawValue) rentalId=\(bookingEntityId) "
                    + "RES=\(effectiveResCode) IRN=\(ctx.irn ?? "nil") "
                    + "oldOperational=\(oldOperational) selectedOperational=\(selectedCategory) "
                    + "chargeGroup=\(charge) oldPlate=\(oldPlate ?? "nil") "
                    + "newPlate=\(vehicle.plateNo) newVehicleId=\(vehicle.id)")

                let canUse = try await f.checkCanUseCar(
                    plate: vehicle.plateNo,
                    vehicleId: vehicle.id,
                    dateFrom: utcIsoDateTime(dateFrom),
                    dateTo: utcIsoDateTime(dateTo),
                    usageReq: usageReq
                )
                print("[WheelSys][Assign] canUseCar IsUsable=\(canUse.isUsable ?? false) "
                    + "CarGroup=\(canUse.carGroup ?? "nil")")

                guard canUse.isUsable == true else {
                    let msg = canUse.warningMessage ?? "wheelsys_assign.canusecar_blocked".localized
                    throw WheelSysBookingFetchError.saveFailed(msg)
                }

                let modelName = canUse.carInfo?.modelName?.trimmed.nonEmpty
                    ?? vehicle.modelName.trimmed.nonEmpty
                    ?? ""
                let modelId = canUse.carInfo?.modelTableId ?? vehicle.modelId
                let operationalGroup = WheelSysCategoryNormalizer.normalize(selectedCategory)

                let payload = WheelSysVehicleAssignPayload(
                    plate: vehicle.plateNo,
                    vehicleId: vehicle.id,
                    operationalGroup: operationalGroup,
                    modelName: modelName,
                    modelId: modelId > 0 ? modelId : vehicle.modelId
                )

                let saveResult: WheelSysAssignSaveResult
                if mode == .assign {
                    saveResult = try await f.performAssign(
                        plate: vehicle.plateNo,
                        vehicleId: vehicle.id,
                        payload: payload
                    )
                } else {
                    saveResult = try await f.performChange(
                        plate: vehicle.plateNo,
                        vehicleId: vehicle.id,
                        oldPlate: oldPlate,
                        payload: payload
                    )
                }

                print("[WheelSys][Assign] save success keyValue=\(saveResult.keyValue.map(String.init) ?? "nil") "
                    + "refresh pending")

                allVehicles.removeAll { $0.id == vehicle.id }
                attemptFirestoreSync(plate: vehicle.plateNo, carId: vehicle.id)
                finishSuccess(plate: vehicle.plateNo)

            case .remove:
                print("[WheelSys][Assign] mode=remove bookingEntityId=\(bookingEntityId) "
                    + "oldPlate=\(oldPlate ?? "nil")")
                _ = try await f.performRemove(oldPlate: oldPlate)
                finishSuccess(plate: nil, removed: true)
            }
        } catch {
            let desc = error.localizedDescription
            WheelSysDebug.error("Assign", "\(mode.rawValue) failed: \(desc)", cid: correlationId)
            if mode == .remove {
                errorMessage = "wheelsys_assign.remove_not_allowed".localized
            } else {
                errorMessage = desc
            }
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func finishSuccess(plate: String?, removed: Bool = false) {
        HapticManager.shared.success()
        if removed {
            print("[WheelSys][Assign] remove success bookingEntityId=\(bookingEntityId)")
            WheelSysDebug.log("Assign", "remove success bookingEntityId=\(bookingEntityId)", cid: correlationId)
            WheelSysActivityReporter.record(
                .vehicleRemoved(resNo: resNo),
                viewModel: viewModel,
                userProfile: authManager.userProfile
            )
        } else if let plate {
            print("[WheelSys][Assign] save success bookingEntityId=\(bookingEntityId) plate=\(plate)")
            WheelSysDebug.log("Assign", "save success bookingEntityId=\(bookingEntityId) plate=\(plate)", cid: correlationId)
            let operation: WheelSysActivityReporter.Operation = mode == .change
                ? .vehicleChanged(plate: plate, resNo: resNo)
                : .vehicleAssigned(plate: plate, resNo: resNo)
            WheelSysActivityReporter.record(
                operation,
                viewModel: viewModel,
                userProfile: authManager.userProfile
            )
        }
        let assignedVehicle = mode == .remove ? nil : selectedVehicle
        let email = previewCustomerEmail
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onAssigned?(assignedVehicle, email)
        }
    }

    /// Non-blocking Firestore sync — Wheelsys success is already confirmed.
    private func attemptFirestoreSync(plate: String, carId: Int) {
        Task {
            do {
                // Lightweight Firestore record update (if needed in future)
                _ = plate; _ = carId
            } catch {
                // Non-blocking warning — Wheelsys save already succeeded
                print("[WheelSys][Assign][Warning] Firestore sync failed (non-blocking): \(error.localizedDescription)")
                WheelSysDebug.log("Assign", "Wheelsys assignment succeeded, but local Firestore sync failed: \(error.localizedDescription)", cid: correlationId)
            }
        }
    }

    private func utcIsoDateTime(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.string(from: date)
    }

    private func isoDateTime(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.timeZone = TimeZone(identifier: "Europe/Zurich")
        df.formatOptions = [.withInternetDateTime]
        return df.string(from: date)
    }
}

// MARK: - Models

struct WheelSysAssignableVehicle: Identifiable, Hashable {
    let id: Int
    let plateNo: String
    let carGroup: String
    let grpcode: String
    let cargroup: String
    let modelName: String
    let modelId: Int
    let mileage: Int
    let fuel: Int
    let station: String
    let lastCheckin: String
    let readyToGo: Bool
    let active: Bool
    let inUse: Bool
    let hardHold: Bool
    let onService: Bool

    var categoryCodes: [String] {
        [grpcode, cargroup, carGroup]
            .map { WheelSysCategoryNormalizer.normalize($0) }
            .filter { !$0.isEmpty }
    }

    func matchesCategory(_ category: String) -> Bool {
        let target = WheelSysCategoryNormalizer.normalize(category)
        guard !target.isEmpty else { return false }
        return categoryCodes.contains(target)
    }
}

// MARK: - String helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
    var nilIfDash: String? {
        let t = trimmed
        if t.isEmpty || t == "-" { return nil }
        return t
    }
    var nilIfEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
}

// MARK: - Service bridge (callable wrappers used by this sheet)

extension WheelSysCheckinService {

    static func searchAvailableVehicles(
        franchiseId: String,
        bookingEntityId: Int,
        station: String,
        dateFrom: String,
        dateTo: String,
        carGroup: String?,
        resNo: String? = nil,
        displayDocNo: String? = nil,
        entireFleet: Bool = false
    ) async throws -> [WheelSysAssignableVehicle] {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysCheckinServiceError.notAuthenticated
        }
        let functions = Functions.functions(region: "europe-west6")
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "bookingEntityId": bookingEntityId,
            "rentalId": bookingEntityId,
            "station": station.uppercased(),
            "dateFrom": dateFrom,
            "dateTo": dateTo,
        ]
        if let group = carGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty {
            payload["carGroup"] = group
        }
        if let resNo = resNo?.trimmingCharacters(in: .whitespacesAndNewlines), !resNo.isEmpty {
            payload["resNo"] = resNo
        }
        if let displayDocNo = displayDocNo?.trimmingCharacters(in: .whitespacesAndNewlines), !displayDocNo.isEmpty {
            payload["displayDocNo"] = displayDocNo
        }
        if entireFleet {
            payload["entireFleet"] = true
        }

        do {
            let result = try await functions.httpsCallable("wheelsysSearchAvailableVehicles").call(payload)
            guard let data = result.data as? [String: Any] else { return [] }
            let rows = data["vehicles"] as? [[String: Any]] ?? []
            return rows.compactMap { parseAssignableVehicle($0) }
        } catch {
            throw WheelSysCheckinServiceError.operationFailed(describeCallableError(error))
        }
    }

    private static func parseAssignableVehicle(_ row: [String: Any]) -> WheelSysAssignableVehicle? {
        func string(_ value: Any?) -> String {
            guard let value else { return "" }
            return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func int(_ value: Any?) -> Int? {
            if let n = value as? Int { return n }
            if let n = value as? NSNumber { return n.intValue }
            if let s = value as? String { return Int(s) }
            return nil
        }
        func bool(_ value: Any?, default defaultValue: Bool = true) -> Bool {
            if let b = value as? Bool { return b }
            if let n = value as? NSNumber { return n.boolValue }
            return defaultValue
        }
        let id = int(row["id"]) ?? int(row["Id"])
        guard let id, id > 0 else { return nil }
        let grp = string(row["grpcode"])
        let cargo = string(row["cargroup"])
        let group = string(row["carGroup"])
        return WheelSysAssignableVehicle(
            id: id,
            plateNo: string(row["plateNo"]),
            carGroup: group.isEmpty ? cargo : group,
            grpcode: grp.isEmpty ? group : grp,
            cargroup: cargo.isEmpty ? group : cargo,
            modelName: string(row["modelName"]),
            modelId: int(row["modelId"]) ?? 0,
            mileage: int(row["mileage"]) ?? 0,
            fuel: int(row["fuel"]) ?? 0,
            station: string(row["station"]),
            lastCheckin: string(row["lastCheckin"]),
            readyToGo: row["readyToGo"] as? Bool ?? false,
            active: bool(row["active"], default: true),
            inUse: bool(row["inuse"], default: false),
            hardHold: bool(row["hardhold"], default: false),
            onService: bool(row["onService"], default: false)
        )
    }
}
