import Foundation
import Combine

@MainActor
final class WheelSysJournalViewModel: ObservableObject {

    @Published var selectedDay = WheelSysJournalService.todayZurich()
    @Published var stationFilter = "all"
    @Published var checkoutRows: [WheelSysJournalRow] = []
    @Published var returnRows: [WheelSysJournalRow] = []
    @Published var fleetVehicles: [WheelSysFleetVehicle] = []
    @Published var availableVehicles: [WheelSysJournalVehicleAvailability] = []
    @Published var journalSnapshot: WheelSysJournalSnapshot?
    @Published var journalUsesFleetFallback = false
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var rentalDetailsByEntityId: [Int: WheelSysRentalDetail] = [:]
    private var enrichingEntityIds: Set<Int> = []
    @Published var diagnosticsResult: WheelSysRentalDiagnostics?
    @Published var diagnosticsLoading = false
    @Published var highlightGroup: String = ""

    private var enrichmentTask: Task<Void, Never>?
    private let franchiseId: String
    private var onSessionExpired: (() -> Void)?

    var franchiseIdForOps: String { franchiseId }

    init(franchiseId: String, onSessionExpired: (() -> Void)? = nil) {
        self.franchiseId = franchiseId
        self.onSessionExpired = onSessionExpired
    }

    // MARK: Fleet load

    /// Populate journal rows from disk-cached fleet so the picker is usable before the API responds.
    func warmFromLocalFleetCache(station: String = "ZRH") {
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        _ = applyLocalFleetFallbackIfAvailable(station: station)
    }

    func loadJournal(background: Bool = false) async {
        let station = stationFilter == "all" ? "ZRH" : stationFilter
        let selectedDate = WheelSysJournalService.formatZurichDay(selectedDay)
        let showBlockingSpinner = !background && checkoutRows.isEmpty && returnRows.isEmpty
        if showBlockingSpinner {
            loading = true
        }
        errorMessage = nil
        defer {
            if showBlockingSpinner { loading = false }
        }

        let trace = PerfTrace.begin("journal.load", detail: "\(selectedDate) bg=\(background)")

        do {
            let snapshot = try await WheelSysJournalAPIService.loadSnapshot(
                franchiseId: franchiseId,
                selectedDate: selectedDate,
                station: station
            )
            applyJournalSnapshot(snapshot)
            journalUsesFleetFallback = snapshot.source.lowercased().contains("fleet")
            PerfTrace.end(trace, note: "co=\(snapshot.checkOuts.count) ci=\(snapshot.checkIns.count)")
        } catch WheelSysJournalAPIServiceError.notAuthenticated {
            errorMessage = WheelSysJournalAPIServiceError.notAuthenticated.localizedDescription
        } catch {
            let raw = Self.rawErrorMessage(from: error)
            if applyLocalFleetFallbackIfAvailable(station: station) {
                print("[Journal] server snapshot failed — using local fleet fallback raw=\(raw)")
                return
            }
            let message = WheelSysUserFacingError.message(for: error)
            print("[Journal] snapshot API failed: \(message) raw=\(raw)")
            errorMessage = message
            if Self.shouldInvalidateSession(raw: raw) {
                onSessionExpired?()
            }
        }
    }

    /// When the server journal callable fails but WKWebView fleet is already loaded, keep the UI usable.
    private func applyLocalFleetFallbackIfAvailable(station: String) -> Bool {
        guard let fleet = WheelSysVehicleFleetStatusStore.shared.fleet else { return false }
        let built = WheelSysJournalService.buildJournalRows(
            from: fleet,
            selectedDay: selectedDay,
            stationFilter: stationFilter
        )
        guard !built.checkout.isEmpty || !built.returns.isEmpty else { return false }

        journalUsesFleetFallback = true
        errorMessage = nil
        checkoutRows = applyCachedEnrichment(to: built.checkout)
        returnRows = applyCachedEnrichment(to: built.returns)
        fleetVehicles = fleet.vehicles
        availableVehicles = []
        journalSnapshot = nil
        print(
            "[Journal] local fleet fallback station=\(station) " +
            "checkOuts=\(built.checkout.count) returns=\(built.returns.count)"
        )
        return true
    }

    private static func rawErrorMessage(from error: Error) -> String {
        if let op = error as? WheelSysJournalAPIServiceError,
           case .operationFailed(let msg) = op {
            return msg
        }
        return error.localizedDescription
    }

    /// Only invalidate WheelSys login for explicit session/auth failures — never fleet/journal ops errors.
    private static func shouldInvalidateSession(raw: String) -> Bool {
        if WheelSysUserFacingError.isOperationalFailure(raw) { return false }
        return WheelSysUserFacingError.isSessionExpiredRaw(raw)
    }

    private func applyJournalSnapshot(_ snapshot: WheelSysJournalSnapshot) {
        journalSnapshot = snapshot
        availableVehicles = snapshot.availableVehicles.filter { vehicle in
            !vehicle.inUse && !vehicle.onService && !vehicle.hardHold
        }
        fleetVehicles = availableVehicles
            .sorted { $0.plate < $1.plate }
            .map { availability in
                WheelSysFleetVehicle(
                    vehicleId: availability.vehicleEntityId,
                    group: availability.group,
                    plate: availability.plate,
                    model: availability.model,
                    station: availability.station.isEmpty ? snapshot.station : availability.station,
                    mileage: availability.mileage,
                    color: nil,
                    fuelType: availability.fuel.map(String.init) ?? "",
                    status: availability.inUse ? "on_rental" : "available",
                    rawCssClass: "",
                    events: []
                )
            }

        let builtCheckout = WheelSysJournalRowMapper.checkoutRows(from: snapshot)
        let builtReturn = WheelSysJournalRowMapper.returnRows(from: snapshot)
        checkoutRows = applyCachedEnrichment(to: builtCheckout)
        returnRows = applyCachedEnrichment(to: builtReturn)
    }

    func shiftDay(_ delta: Int) {
        if let next = WheelSysJournalService.zurichCalendar.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = WheelSysJournalService.startOfDayZurich(next)
            Task { await loadJournal() }
        }
    }

    func goToToday() {
        selectedDay = WheelSysJournalService.todayZurich()
        Task { await loadJournal() }
    }

    func setSelectedDay(_ day: Date) {
        selectedDay = WheelSysJournalService.startOfDayZurich(day)
        Task { await loadJournal() }
    }

    func setStationFilter(_ filter: String) {
        stationFilter = filter
        Task { await loadJournal() }
    }

    private func applyCachedEnrichment(to rows: [WheelSysJournalRow]) -> [WheelSysJournalRow] {
        rows.map { row in
            var copy = row
            if let detail = rentalDetailsByEntityId[row.rentalEntityId] {
                copy.enrichmentStatus = .loaded
                copy.rentalTitle = detail.title
                copy.rentalNumber = detail.rentalNumber
            } else if enrichingEntityIds.contains(row.rentalEntityId) {
                copy.enrichmentStatus = .loading
            }
            return copy
        }
    }

    // MARK: Display helpers

    func customerName(for row: WheelSysJournalRow) -> String {
        if let detail = rentalDetailsByEntityId[row.rentalEntityId],
           let name = detail.customerName, !name.isEmpty {
            return name
        }
        let fleetName = row.driverNameFromFleet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fleetName.isEmpty { return fleetName }
        return "-"
    }

    func agentBooker(for row: WheelSysJournalRow) -> String {
        guard let detail = rentalDetailsByEntityId[row.rentalEntityId],
              let agent = detail.agentBooker, !agent.isEmpty
        else { return "-" }
        return agent
    }

    func location(for row: WheelSysJournalRow) -> String {
        if let detail = rentalDetailsByEntityId[row.rentalEntityId] {
            switch row.kind {
            case .checkout:
                if let loc = detail.checkoutLocation, !loc.isEmpty { return loc }
            case .return:
                if let loc = detail.checkinLocation, !loc.isEmpty { return loc }
            }
        }
        return row.station.isEmpty ? "ZRH" : row.station
    }

    func vehicleGroup(for row: WheelSysJournalRow) -> String {
        return row.vehicleGroup.isEmpty ? "-" : row.vehicleGroup
    }

    /// Fleet chart group for the checkout vehicle — used to highlight matching journal rows.
    func resolveHighlightGroup(forPlate plate: String) {
        let norm = WheelSysPlateNormalizer.canonical(plate)
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        if let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate),
           !fleetVehicle.group.isEmpty {
            highlightGroup = fleetVehicle.group
            return
        }
        if let match = fleetVehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plate) == norm
        }) {
            highlightGroup = match.group
            return
        }
        if let match = availableVehicles.first(where: { $0.normalizedPlate == norm }) {
            highlightGroup = match.group
        } else {
            highlightGroup = ""
        }
    }

    func rentalNumber(for row: WheelSysJournalRow) -> String? {
        row.rentalNumber ?? rentalDetailsByEntityId[row.rentalEntityId]?.rentalNumber
    }

    // MARK: Lazy enrichment

    /// Bulk enrichment disabled — journal API already includes driver names.
    func scheduleLazyEnrichment() {}

    func enrichIfNeeded(entityId: Int) async {
        if rentalDetailsByEntityId[entityId] != nil { return }
        await enrichRentalDetail(entityId: entityId)
    }

    func enrichRentalDetail(entityId: Int) async {
        guard !enrichingEntityIds.contains(entityId) else { return }
        guard rentalDetailsByEntityId[entityId] == nil else { return }

        enrichingEntityIds.insert(entityId)
        markEnrichmentStatus(entityId: entityId, status: .loading)
        defer { enrichingEntityIds.remove(entityId) }

        do {
            let detail = try await WheelSysJournalService.fetchRentalDetail(entityId: entityId)
            rentalDetailsByEntityId[entityId] = detail
            markEnrichmentStatus(entityId: entityId, status: .loaded, detail: detail)
        } catch WheelSysRentalFetchError.sessionExpired {
            errorMessage = WheelSysRentalFetchError.sessionExpired.localizedDescription
            markEnrichmentStatus(entityId: entityId, status: .failed)
            onSessionExpired?()
        } catch {
            print("[Journal] rental detail fetch failed entityId=\(entityId): \(error.localizedDescription)")
            markEnrichmentStatus(entityId: entityId, status: .failed)
        }
    }

    private func markEnrichmentStatus(
        entityId: Int,
        status: WheelSysJournalEnrichmentStatus,
        detail: WheelSysRentalDetail? = nil
    ) {
        func patch(_ rows: [WheelSysJournalRow]) -> [WheelSysJournalRow] {
            rows.map { row in
                guard row.rentalEntityId == entityId else { return row }
                var copy = row
                copy.enrichmentStatus = status
                if let detail {
                    copy.rentalTitle = detail.title
                    copy.rentalNumber = detail.rentalNumber
                }
                return copy
            }
        }
        checkoutRows = patch(checkoutRows)
        returnRows = patch(returnRows)
    }

    /// Instant journal row plate update after assign / change (background reload follows).
    func applyOptimisticPlateAssignment(bookingEntityId: Int, plate: String) {
        checkoutRows = checkoutRows.map { row in
            guard row.effectiveBookingEntityId == bookingEntityId else { return row }
            return row.withPlateAssignment(plate)
        }
    }

    /// Instant journal row plate clear after remove (background reload follows).
    func applyOptimisticPlateRemoval(bookingEntityId: Int) {
        applyOptimisticPlateAssignment(bookingEntityId: bookingEntityId, plate: "")
    }

    // MARK: Return action

    @Published var syncingReturnEntityIds: Set<Int> = []

    func handleReturnPressed(for row: WheelSysJournalRow, mileageIn: Int?, fuelIn: Int?) async {
        _ = row
        _ = mileageIn
        _ = fuelIn
        errorMessage = "wheelsys.precheckin.inline_footer".localized
        HapticManager.shared.error()
    }

    // MARK: Debug diagnostics

    #if DEBUG
    func runDiagnostics(entityId: Int) async {
        diagnosticsLoading = true
        diagnosticsResult = nil
        defer { diagnosticsLoading = false }

        do {
            diagnosticsResult = try await WheelSysJournalService.fetchRentalDetailDiagnostics(entityId: entityId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}

private extension WheelSysFleetVehicle {
    var plakaSortKey: String { plate }
}
