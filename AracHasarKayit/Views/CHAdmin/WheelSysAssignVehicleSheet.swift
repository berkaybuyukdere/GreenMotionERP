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
    var onAssigned: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var vehicles: [WheelSysAssignableVehicle] = []
    @State private var phase: AssignPhase = .loadingPage
    @State private var assigning = false
    @State private var selectedVehicle: WheelSysAssignableVehicle?
    @State private var showConfirm = false
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
                VStack(alignment: .leading, spacing: 14) {
                    bookingHeaderCard
                    if mode == .remove {
                        removeSection
                    } else {
                        vehiclesSection
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
            .alert(confirmAlertTitle, isPresented: $showConfirm) {
                Button("Cancel".localized, role: .cancel) {}
                Button(confirmActionTitle) {
                    guard !isAssigning else { return }
                    Task { await confirmVehicleUpdate() }
                }
                .disabled(isAssigning)
            } message: {
                if let vehicle = selectedVehicle {
                    Text(String(
                        format: confirmBodyFormat,
                        vehicle.plateNo,
                        bookingEntityId
                    ))
                }
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
                if assigning {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(.white)
                            Text("wheelsys.checkout.syncing_micro".localized)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var bookingHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Primary: RES number — always displayDocNo, never confirmationNo
            VStack(alignment: .leading, spacing: 4) {
                Text("wheelsys_assign.res_code".localized)
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .textCase(.uppercase)
                Text(effectiveResCode)
                    .font(PalantirTheme.heroFont(18).monospaced())
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(2)
            }

            Rectangle().fill(PalantirTheme.border).frame(height: 1)

            // IRN — from booking page context
            if let irn = effectiveIrn {
                detailRow("wheelsys_assign.irn".localized, irn)
            }

            // Confirmation number — separate, never in RES field
            if let conf = effectiveConfirmationNo {
                detailRow("wheelsys_assign.conf".localized, conf)
            }

            detailRow("wheelsys_assign.booking".localized, "#\(bookingEntityId)")

            if !carGroup.isEmpty, carGroup != "-" {
                detailRow("ch_ops.col_group".localized, carGroup)
            }
            detailRow("wheelsys_journal.station".localized, station)
            detailRow("wheelsys_assign.period".localized, periodText)

            // Driver from booking page context (authoritative) or pre-fill
            if let driver = effectiveDriverName, !driver.isEmpty {
                detailRow("wheelsys_journal.col_driver".localized, driver)
            }

            // Current vehicle (change/remove modes)
            if mode != .assign, !effectiveCurrentPlate.isEmpty {
                detailRow("wheelsys_assign.current_vehicle".localized, effectiveCurrentPlate)
            }

            // Voucher if available
            if let voucher = bookingPageContext?.voucherNo {
                detailRow("wheelsys_assign.voucher".localized, voucher)
            }

#if DEBUG
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
            Text("wheelsys_assign.debug_title".localized)
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .textCase(.uppercase)
            detailRow("wheelsys_assign.debug_cid".localized, correlationId)
            if let ctx = bookingPageContext {
                detailRow("wheelsys_assign.debug_cachekey".localized, String(ctx.cacheKey.prefix(8)))
                detailRow("wheelsys_assign.debug_source".localized, "booking.aspx/webview")
            }
#endif
        }
        .palantirCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(PalantirTheme.bodyFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Vehicles

    @ViewBuilder
    private var vehiclesSection: some View {
        HStack {
            Text("wheelsys_assign.vehicles_section".localized)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .textCase(.uppercase)
            Spacer()
            if phase == .loadingPage {
                ProgressView().scaleEffect(0.75)
            }
        }

        if phase == .loadingPage && vehicles.isEmpty {
            VStack(spacing: 10) {
                ProgressView("wheelsys_assign.loading_page".localized)
                Text("wheelsys_assign.loading_page_detail".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if vehicles.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
                ForEach(vehicles) { vehicle in
                    vehicleCard(vehicle)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.largeTitle)
                .foregroundStyle(PalantirTheme.textMuted)
            Text("wheelsys_assign.empty".localized)
                .font(.subheadline)
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)
            Button("wheelsys_assign.retry_context".localized) {
                Task { await bootstrapAssignmentFlow() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .palantirCard()
    }

    private func vehicleCard(_ vehicle: WheelSysAssignableVehicle) -> some View {
        Button {
            selectedVehicle = vehicle
            showConfirm = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.plateNo)
                            .font(PalantirTheme.heroFont(15).monospaced())
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text("ID: \(vehicle.id)")
                            .font(PalantirTheme.dataFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    Spacer()
                    if vehicle.readyToGo {
                        Text("wheelsys_assign.ready_to_go".localized)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(PalantirTheme.success.opacity(0.15))
                            .foregroundStyle(PalantirTheme.success)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                }

                HStack(spacing: 12) {
                    metaChip(vehicle.carGroup)
                    if !vehicle.modelName.isEmpty {
                        metaChip(vehicle.modelName)
                    }
                }

                HStack(spacing: 12) {
                    metaChip(String(format: "wheelsys_daily.col_mileage".localized + ": %d", vehicle.mileage))
                    metaChip(String(format: "wheelsys_journal.col_fuel".localized + ": %d", vehicle.fuel))
                }

                if !vehicle.lastCheckin.isEmpty {
                    Text(String(format: "wheelsys_daily.col_last_checkin".localized + ": %@", vehicle.lastCheckin))
                        .font(.caption2)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(PalantirTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(PalantirTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(assigning || isAssigning)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(PalantirTheme.dataFont(11))
            .foregroundStyle(PalantirTheme.textPrimary)
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

    private var confirmAlertTitle: String {
        switch mode {
        case .assign: return "wheelsys_assign.confirm_title".localized
        case .change: return "wheelsys_assign.change_confirm_title".localized
        case .remove: return "wheelsys_assign.remove_confirm_title".localized
        }
    }

    private var confirmActionTitle: String {
        switch mode {
        case .assign: return "wheelsys_assign.confirm_action".localized
        case .change: return "wheelsys_assign.change_action".localized
        case .remove: return "wheelsys_assign.remove_action".localized
        }
    }

    private var confirmBodyFormat: String {
        switch mode {
        case .assign: return "wheelsys_assign.confirm_body".localized
        case .change: return "wheelsys_assign.change_confirm_body".localized
        case .remove: return "wheelsys_assign.remove_confirm_body".localized
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
        bookingPageContext?.driverName?.trimmed
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
        vehicles = []
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
            if mode != .remove {
                group.addTask { await loadVehicles() }
            }
        }

        phase = .vehiclesReady
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

    @MainActor
    private func loadVehicles() async {
        do {
            let loaded = try await WheelSysCheckinService.searchAvailableVehicles(
                franchiseId: franchiseId,
                bookingEntityId: bookingEntityId,
                station: station,
                dateFrom: isoDateTime(dateFrom),
                dateTo: isoDateTime(dateTo),
                carGroup: carGroup.nilIfDash,
                resNo: resNo?.trimmed,
                displayDocNo: nil
            )
            vehicles = filterVehiclesByCarGroup(loaded)
            WheelSysDebug.log("Assign", "vehicles loaded=\(vehicles.count)", cid: correlationId)
        } catch {
            WheelSysDebug.error("Assign", "load vehicles: \(WheelSysCheckinService.describeCallableError(error))", cid: correlationId)
            if vehicles.isEmpty {
                errorMessage = "wheelsys_assign.error_load_vehicles".localized
                    + " " + WheelSysCheckinService.describeCallableError(error)
            }
        }
    }

    private func filterVehiclesByCarGroup(_ loaded: [WheelSysAssignableVehicle]) -> [WheelSysAssignableVehicle] {
        guard let targetGroup = carGroup.nilIfDash?.uppercased(), !targetGroup.isEmpty else { return loaded }
        return loaded.filter { $0.carGroup.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetGroup }
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
            case .assign:
                guard let vehicle = selectedVehicle else { return }
                print("[WheelSys][Assign] mode=assign bookingEntityId=\(bookingEntityId) "
                    + "selectedPlate=\(vehicle.plateNo) selectedVehicleId=\(vehicle.id)")
                _ = try await f.performAssign(plate: vehicle.plateNo, vehicleId: vehicle.id)
                attemptFirestoreSync(plate: vehicle.plateNo, carId: vehicle.id)
                finishSuccess(plate: vehicle.plateNo)

            case .change:
                guard let vehicle = selectedVehicle else { return }
                print("[WheelSys][Assign] mode=change bookingEntityId=\(bookingEntityId) "
                    + "oldPlate=\(oldPlate ?? "nil") newPlate=\(vehicle.plateNo) newVehicleId=\(vehicle.id)")
                _ = try await f.performChange(
                    plate: vehicle.plateNo,
                    vehicleId: vehicle.id,
                    oldPlate: oldPlate
                )
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
        } else if let plate {
            print("[WheelSys][Assign] save success bookingEntityId=\(bookingEntityId) plate=\(plate)")
            WheelSysDebug.log("Assign", "save success bookingEntityId=\(bookingEntityId) plate=\(plate)", cid: correlationId)
        }
        onAssigned?()
        dismiss()
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
    let modelName: String
    let mileage: Int
    let fuel: Int
    let lastCheckin: String
    let readyToGo: Bool
}

// MARK: - String helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
        displayDocNo: String? = nil
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
        let id = int(row["id"]) ?? int(row["Id"])
        guard let id, id > 0 else { return nil }
        return WheelSysAssignableVehicle(
            id: id,
            plateNo: string(row["plateNo"]),
            carGroup: string(row["carGroup"]),
            modelName: string(row["modelName"]),
            mileage: int(row["mileage"]) ?? 0,
            fuel: int(row["fuel"]) ?? 0,
            lastCheckin: string(row["lastCheckin"]),
            readyToGo: row["readyToGo"] as? Bool ?? false
        )
    }
}
