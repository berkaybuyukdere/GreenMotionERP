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
    @Published var enrichingEntityIds: Set<Int> = []
    @Published var diagnosticsResult: WheelSysRentalDiagnostics?
    @Published var diagnosticsLoading = false
    @Published var highlightGroup: String = ""

    private var fleetCache: WheelSysFleetChartResult?
    private var enrichmentTask: Task<Void, Never>?
    private let franchiseId: String
    private var onSessionExpired: (() -> Void)?

    init(franchiseId: String, onSessionExpired: (() -> Void)? = nil) {
        self.franchiseId = franchiseId
        self.onSessionExpired = onSessionExpired
    }

    // MARK: Fleet load

    func loadJournal() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        let station = stationFilter == "all" ? "ZRH" : stationFilter
        let selectedDate = WheelSysJournalService.formatZurichDay(selectedDay)

        print("[Journal] snapshot fetch started date=\(selectedDate) station=\(station)")

        do {
            let snapshot = try await WheelSysJournalAPIService.loadSnapshot(
                franchiseId: franchiseId,
                selectedDate: selectedDate,
                station: station
            )
            applyJournalSnapshot(snapshot)
            journalUsesFleetFallback = false
            print("[Journal] snapshot API checkOuts=\(snapshot.checkOuts.count) checkIns=\(snapshot.checkIns.count)")
            return
        } catch {
            print("[Journal] snapshot API failed, falling back to fleet chart: \(error.localizedDescription)")
        }

        print("[Journal] Fleet Chart fetch started")

        do {
            let fleet = try await WheelSysCheckinService.loadFleetChart(
                franchiseId: franchiseId,
                station: station
            )
            fleetCache = fleet
            fleetVehicles = fleet.vehicles.sorted { $0.plate < $1.plakaSortKey }
            journalSnapshot = nil
            availableVehicles = []
            journalUsesFleetFallback = true
            print("[Journal] Fleet Chart status=200")
            print("[Journal] allEventsCount=\(fleet.eventsCount)")
            print("[Journal] rentalEventsCount=\(fleet.rentalEventsCount)")
            rebuildRows()
        } catch WheelSysFleetFetchError.sessionExpired {
            errorMessage = WheelSysFleetFetchError.sessionExpired.localizedDescription
            onSessionExpired?()
        } catch WheelSysRentalFetchError.sessionExpired {
            errorMessage = WheelSysRentalFetchError.sessionExpired.localizedDescription
            onSessionExpired?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyJournalSnapshot(_ snapshot: WheelSysJournalSnapshot) {
        journalSnapshot = snapshot
        availableVehicles = snapshot.availableVehicles
        fleetCache = nil
        fleetVehicles = snapshot.availableVehicles
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

    private func rebuildRows() {
        guard let fleet = fleetCache else {
            checkoutRows = []
            returnRows = []
            return
        }
        let built = WheelSysJournalService.buildJournalRows(
            from: fleet,
            selectedDay: selectedDay,
            stationFilter: stationFilter
        )
        checkoutRows = applyCachedEnrichment(to: built.checkout)
        returnRows = applyCachedEnrichment(to: built.returns)
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

    // MARK: Return action

    func handleReturnPressed(for row: WheelSysJournalRow, mileageIn: Int?, fuelIn: String?) async {
        print("[Journal] return pressed entityId=\(row.rentalEntityId)")
        await enrichIfNeeded(entityId: row.rentalEntityId)

        guard let km = mileageIn, km > 0 else {
            print("[Journal] WheelSys return update failed entityId=\(row.rentalEntityId) error=missing km")
            return
        }

        do {
            try await WheelSysJournalService.submitReturnUpdate(
                entityId: row.rentalEntityId,
                mileageIn: km,
                fuelIn: fuelIn ?? ""
            )
        } catch {
            print("[Journal] WheelSys return update failed entityId=\(row.rentalEntityId) error=\(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
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
