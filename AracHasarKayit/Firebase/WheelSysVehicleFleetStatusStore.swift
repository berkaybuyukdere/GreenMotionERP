import Foundation
import Combine
import FirebaseFirestore
import UIKit

/// Palantir-style fleet ops badge for Vehicles list / detail (CH WheelSys).
enum WheelSysFleetOpsBadgeKind: Equatable {
    case ntr
    case rental
    case available

    var labelKey: String {
        switch self {
        case .ntr: return "wheelsys_fleet.badge_ntr"
        case .rental: return "wheelsys_fleet.badge_rental"
        case .available: return "wheelsys_fleet.badge_available"
        }
    }
}

struct WheelSysFleetOpsBadge: Equatable {
    let kind: WheelSysFleetOpsBadgeKind
}

/// Caches WheelSys fleet chart status per plate for Vehicles page filters (CH).
@MainActor
final class WheelSysVehicleFleetStatusStore: ObservableObject {
    static let shared = WheelSysVehicleFleetStatusStore()

    @Published private(set) var fleet: WheelSysFleetChartResult?
    @Published private(set) var loading = false
    @Published private(set) var lastError: String?
    @Published private(set) var filterCounts: [VehicleFleetOpsFilter: Int] = [:]
    @Published private(set) var filterVehicleIds: [VehicleFleetOpsFilter: Set<UUID>] = [:]

    private var statusByPlate: [String: String] = [:]
    private var fuelByPlate: [String: Int] = [:]
    private var mileageByPlate: [String: Int] = [:]
    private var loadTask: Task<Void, Never>?
    private var lastLoadedAt: Date?

    private static let cacheTTL: TimeInterval = 20 * 60

    private var pendingRefreshTask: Task<Void, Never>?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .wheelSysFleetStatusDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isWheelSysSessionActive else { return }
                self.scheduleDebouncedRefresh(force: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .wheelSysNTRDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isWheelSysSessionActive else { return }
                self.scheduleDebouncedRefresh(force: true)
            }
        }
    }

    private var isWheelSysSessionActive: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: nil
        )
    }

    private func scheduleDebouncedRefresh(force: Bool) {
        guard isWheelSysSessionActive else {
            clearInMemoryIfNonCHSession()
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await loadOnce(force: force)
        }
    }

    func refreshIfNeeded() async {
        guard isWheelSysSessionActive else {
            clearInMemoryIfNonCHSession()
            return
        }
        bootstrapFromDiskIfNeeded()
        await loadOnce(force: false)
    }

    func refresh(force: Bool) async {
        guard isWheelSysSessionActive else {
            clearInMemoryIfNonCHSession()
            return
        }
        if force { bootstrapFromDiskIfNeeded() }
        await loadOnce(force: force)
    }

    /// Warm status/km/fuel from on-disk snapshot (instant filters before network).
    func bootstrapFromDiskIfNeeded() {
        guard isWheelSysSessionActive else {
            clearInMemoryIfNonCHSession()
            return
        }
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        guard !franchiseId.isEmpty else { return }
        guard fleet == nil, statusByPlate.isEmpty else { return }
        if let snap = WheelSysFleetDiskCache.load(franchiseId: franchiseId) {
            applyDiskSnapshot(snap)
        }
    }

    func applyDiskSnapshot(_ snap: WheelSysFleetDiskCache.Snapshot) {
        var statusMap: [String: String] = [:]
        var mileageMap: [String: Int] = [:]
        var fuelMap: [String: Int] = [:]
        for row in snap.vehicles {
            guard !row.plateCanonical.isEmpty else { continue }
            statusMap[row.plateCanonical] = row.status
            if row.mileage > 0 { mileageMap[row.plateCanonical] = row.mileage }
            if let fuel = row.fuel { fuelMap[row.plateCanonical] = fuel }
        }
        statusByPlate = statusMap
        mileageByPlate = mileageMap
        fuelByPlate = fuelMap
        lastLoadedAt = snap.savedAt
    }

    /// Recompute filter chip counts and precomputed vehicle ID sets (no network).
    func updateFilterCounts(
        araclar: [Arac],
        parkedVehicleIds: Set<UUID>,
        openCheckoutVehicleIds: Set<UUID> = [],
        inProgressCheckoutVehicleIds: Set<UUID> = []
    ) {
        var counts: [VehicleFleetOpsFilter: Int] = [:]
        var idsByFilter: [VehicleFleetOpsFilter: Set<UUID>] = [:]
        for filter in VehicleFleetOpsFilter.allCases {
            let matchedIds = araclar.compactMap { arac -> UUID? in
                matches(
                    filter: filter,
                    arac: arac,
                    parkedVehicleIds: parkedVehicleIds,
                    openCheckoutVehicleIds: openCheckoutVehicleIds,
                    inProgressCheckoutVehicleIds: inProgressCheckoutVehicleIds
                ) ? arac.id : nil
            }
            counts[filter] = matchedIds.count
            idsByFilter[filter] = Set(matchedIds)
        }
        filterCounts = counts
        filterVehicleIds = idsByFilter
    }

    /// Fast filter using precomputed ID sets from `updateFilterCounts`.
    func filteredAraclar(
        from araclar: [Arac],
        filter: VehicleFleetOpsFilter,
        parkedVehicleIds: Set<UUID>,
        openCheckoutVehicleIds: Set<UUID> = [],
        inProgressCheckoutVehicleIds: Set<UUID> = []
    ) -> [Arac] {
        guard filter != .all else { return araclar }
        if let ids = filterVehicleIds[filter] {
            return araclar.filter { ids.contains($0.id) }
        }
        return araclar.filter {
            matches(
                filter: filter,
                arac: $0,
                parkedVehicleIds: parkedVehicleIds,
                openCheckoutVehicleIds: openCheckoutVehicleIds,
                inProgressCheckoutVehicleIds: inProgressCheckoutVehicleIds
            )
        }
    }

    private func clearInMemoryIfNonCHSession() {
        guard !isWheelSysSessionActive else { return }
        loadTask?.cancel()
        pendingRefreshTask?.cancel()
        fleet = nil
        statusByPlate = [:]
        fuelByPlate = [:]
        mileageByPlate = [:]
        filterCounts = [:]
        filterVehicleIds = [:]
        lastLoadedAt = nil
        lastError = nil
        loading = false
        loadTask = nil
        pendingRefreshTask = nil
    }

    private func loadOnce(force: Bool) async {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        guard isWheelSysSessionActive else {
            clearInMemoryIfNonCHSession()
            return
        }
        guard WheelSysCookieCache.isValid else { return }
        guard force || UIApplication.shared.applicationState == .active else { return }

        if !force,
           fleet != nil,
           let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < Self.cacheTTL {
            return
        }

        if loading, !force {
            await loadTask?.value
            return
        }

        if let existing = loadTask, !force {
            await existing.value
            return
        }

        loading = true
        lastError = nil

        let task = Task(priority: .utility) {
            defer {
                Task { @MainActor in
                    self.loading = false
                    self.loadTask = nil
                }
            }
            do {
                let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
                async let chartTask = WheelSysCheckinService.loadFleetChart(franchiseId: franchiseId)
                async let fuelTask = Self.loadVehicleMasterFuelMapOffMain(franchiseId: franchiseId)
                let chart = try await chartTask
                let fuelMap = await fuelTask
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.applyFleet(chart, fuelByPlate: fuelMap)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.lastError = WheelSysUserFacingError.message(for: error)
                }
            }
        }

        loadTask = task
        await task.value
    }

    private func applyFleet(_ chart: WheelSysFleetChartResult, fuelByPlate: [String: Int] = [:]) {
        fleet = chart
        lastLoadedAt = Date()
        lastError = nil
        self.fuelByPlate = fuelByPlate

        var map: [String: String] = [:]
        var mileageMap: [String: Int] = [:]
        for vehicle in chart.vehicles {
            let key = WheelSysPlateNormalizer.canonical(vehicle.plate)
            guard !key.isEmpty else { continue }
            map[key] = vehicle.status.lowercased()
            if vehicle.mileage > 0 { mileageMap[key] = vehicle.mileage }
        }
        statusByPlate = map
        mileageByPlate = mileageMap

        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        if !franchiseId.isEmpty {
            WheelSysFleetDiskCache.save(from: chart, franchiseId: franchiseId, fuelByPlate: fuelByPlate)
        }
    }

    func status(for arac: Arac) -> String? {
        let key = WheelSysPlateNormalizer.canonical(arac.plaka)
        guard !key.isEmpty else { return nil }
        if let cached = statusByPlate[key] { return cached }
        guard let fleet else { return nil }
        return fleet.vehicles.first {
            WheelSysPlateNormalizer.canonical($0.plate) == key
        }?.status.lowercased()
    }

    /// Human-readable fleet status (not raw css token).
    func displayStatusLabel(for arac: Arac) -> String {
        guard let raw = status(for: arac)?.lowercased(), !raw.isEmpty else {
            return "—"
        }
        return Self.localizedFleetStatusLabel(raw)
    }

    static func localizedFleetStatusLabel(_ status: String) -> String {
        let s = status.lowercased()
        switch s {
        case "available": return "wheelsys_fleet.status_available".localized
        case "on_rental", "rental", "on rental", "onrental": return "wheelsys_fleet.status_on_rental".localized
        case "non_revenue": return "wheelsys_fleet.status_non_revenue".localized
        case "booking": return "wheelsys_fleet.status_booking".localized
        case "insurance": return "wheelsys_fleet.status_insurance".localized
        default:
            if s.contains("rent") { return "wheelsys_fleet.status_on_rental".localized }
            if s.contains("avail") { return "wheelsys_fleet.status_available".localized }
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    func fleetVehicle(for arac: Arac) -> WheelSysFleetVehicle? {
        fleetVehicle(forPlate: arac.plaka)
    }

    func fleetVehicle(forPlate plate: String) -> WheelSysFleetVehicle? {
        guard let fleet else { return nil }
        let key = WheelSysPlateNormalizer.canonical(plate)
        return fleet.vehicles.first { WheelSysPlateNormalizer.canonical($0.plate) == key }
    }

    /// Driver name from fleet chart for the active rental entity (authoritative for CH return).
    func fleetDriverName(forRentalEntityId rentalId: Int, plate: String? = nil) -> String? {
        guard rentalId > 0, let fleet else { return nil }
        if let event = fleet.allEvents.first(where: { $0.rentalEntityId == rentalId }) {
            let name = event.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let plate {
            let key = WheelSysPlateNormalizer.canonical(plate)
            if let vehicle = fleet.vehicles.first(where: { WheelSysPlateNormalizer.canonical($0.plate) == key }) {
                if let event = vehicle.events.first(where: { $0.rentalEntityId == rentalId }) {
                    let name = event.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { return name }
                }
            }
        }
        return nil
    }

    /// Compact km + fuel line for Vehicles list rows (CH fleet ops).
    func fleetMicroSummary(for arac: Arac) -> String? {
        let plateKey = WheelSysPlateNormalizer.canonical(arac.plaka)
        var parts: [String] = []
        // `mileageByPlate` is built from the same chart/disk source as `fleetVehicle`, so
        // prefer the O(1) dict lookup and only fall back to the O(F) linear scan on a miss.
        // This avoids an O(N·F) plate scan when building row metadata for the whole fleet.
        if let km = mileageByPlate[plateKey], km > 0 {
            parts.append("\(km) km")
        } else if let vehicle = fleetVehicle(for: arac), vehicle.mileage > 0 {
            parts.append("\(vehicle.mileage) km")
        }
        if let fuel = fuelByPlate[plateKey], fuel >= 0 {
            parts.append("\(fuel)/8")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func fleetFuelEighths(for arac: Arac) -> Int? {
        let plateKey = WheelSysPlateNormalizer.canonical(arac.plaka)
        guard let fuel = fuelByPlate[plateKey], fuel >= 0 else { return nil }
        return fuel
    }

    func fleetMileage(for arac: Arac) -> Int? {
        if let vehicle = fleetVehicle(for: arac), vehicle.mileage > 0 {
            return vehicle.mileage
        }
        let plateKey = WheelSysPlateNormalizer.canonical(arac.plaka)
        if let km = mileageByPlate[plateKey], km > 0 { return km }
        return nil
    }

    private static func loadVehicleMasterFuelMapOffMain(franchiseId: String) async -> [String: Int] {
        do {
            let snap = try await Firestore.firestore()
                .collection("franchises").document(franchiseId)
                .collection("wheelsysScratch").document("vehicleMasterCache")
                .getDocument()
            guard let vehicles = snap.data()?["vehicles"] as? [[String: Any]] else { return [:] }
            var map: [String: Int] = [:]
            for row in vehicles {
                let plateRaw = (row["normalizedPlate"] as? String) ?? (row["plateNo"] as? String) ?? ""
                let key = WheelSysPlateNormalizer.canonical(plateRaw)
                guard !key.isEmpty else { continue }
                if let fuel = row["fuel"] as? Int {
                    map[key] = fuel
                } else if let fuel = row["fuel"] as? Double {
                    map[key] = Int(fuel)
                }
            }
            return map
        } catch {
            return [:]
        }
    }

    /// Fleet-chart status string indicates the vehicle is currently on an active rental.
    static func isFleetOnRentalStatus(_ status: String?) -> Bool {
        let s = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return false }
        if s.contains("closed") { return false }
        if s == "non_revenue" || s.contains("non_revenue") { return false }
        if s == "available" || s.contains("avail") { return false }
        if s == "on_rental" || s == "on rental" || s == "onrental" || s == "on_rent" {
            return true
        }
        return s.contains("on_rental") || s.contains("on rental")
    }

    private static func isOpenRentalFleetEvent(_ event: WheelSysFleetEvent) -> Bool {
        let type = event.type.lowercased()
        guard type == "rental" || type.contains("rental") else { return false }
        let st = event.status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if st == "closed" || st.contains("closed") { return false }
        if st == "active" || st == "running" || st.contains("on_rent") { return true }
        return st.isEmpty
    }

    /// True when fleet chart has a running rental event (not closed history).
    func hasActiveRentalEvent(for arac: Arac) -> Bool {
        guard let vehicle = fleetVehicle(for: arac) else { return false }
        return vehicle.events.contains { Self.isOpenRentalFleetEvent($0) }
    }

    /// True when WheelSys fleet chart shows an active rental for this vehicle.
    func isVehicleOnRental(_ arac: Arac) -> Bool {
        isVehicleOnRental(forPlate: arac.plaka)
    }

    func isVehicleOnRental(forPlate plate: String) -> Bool {
        let key = WheelSysPlateNormalizer.canonical(plate)
        guard !key.isEmpty, let fleet else {
            return Self.isFleetOnRentalStatus(status(forPlate: plate))
        }
        if let vehicle = fleet.vehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plate) == key
        }) {
            if vehicle.events.contains(where: { Self.isOpenRentalFleetEvent($0) }) {
                return true
            }
            return Self.isFleetOnRentalStatus(vehicle.status.lowercased())
        }
        return Self.isFleetOnRentalStatus(status(forPlate: plate))
    }

    private func status(forPlate plate: String) -> String? {
        let key = WheelSysPlateNormalizer.canonical(plate)
        guard !key.isEmpty else { return nil }
        if let cached = statusByPlate[key] { return cached }
        guard let fleet else { return nil }
        return fleet.vehicles.first {
            WheelSysPlateNormalizer.canonical($0.plate) == key
        }?.status.lowercased()
    }

    /// Open/running rental event for detail banner (ignores closed history).
    func activeRentalEvent(for arac: Arac) -> WheelSysFleetEvent? {
        guard let vehicle = fleetVehicle(for: arac) else { return nil }
        return vehicle.events.first { Self.isOpenRentalFleetEvent($0) }
    }

    /// Most recent closed rental event — shown when vehicle is not currently on rent.
    func lastClosedRentalEvent(for arac: Arac) -> WheelSysFleetEvent? {
        guard let vehicle = fleetVehicle(for: arac) else { return nil }
        return vehicle.events
            .filter {
                let type = $0.type.lowercased()
                guard type == "rental" || type.contains("rental") else { return false }
                let st = $0.status.lowercased()
                return st == "closed" || st.contains("closed")
            }
            .sorted { $0.end > $1.end }
            .first
    }

    /// Fleet chart shows a running (not closed) non-revenue block.
    private static func isOpenNonRevenueFleetStatus(_ status: String?) -> Bool {
        let s = status?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return false }
        if s.contains("closed") { return false }
        return s == "non_revenue" || s == "non_revenue_running"
    }

    func isFleetNonRevenue(_ arac: Arac) -> Bool {
        if Self.isOpenNonRevenueFleetStatus(status(for: arac)) { return true }
        return activeNonRevenueEvent(for: arac) != nil
    }

    /// Fleet chart / daily view on-rental signal for a vehicle.
    func isOnRental(_ arac: Arac) -> Bool {
        hasActiveRentalEvent(for: arac) || isVehicleOnRental(arac)
    }

    /// Open/running NTR event only — closed historical NTR rows are ignored.
    func activeNonRevenueEvent(for arac: Arac) -> WheelSysFleetEvent? {
        guard let vehicle = fleetVehicle(for: arac) else { return nil }
        return vehicle.events.first { event in
            Self.isOpenNonRevenueEvent(event)
        }
    }

    private static func isOpenNonRevenueEvent(_ event: WheelSysFleetEvent) -> Bool {
        let type = event.type.lowercased()
        guard type == "non_revenue" || type.contains("non_revenue") else { return false }
        let st = event.status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if st == "closed" || st.contains("closed") { return false }
        if st == "active" || st == "running" || st.contains("running") { return true }
        // Fleet chart sometimes omits status on the currently running NTR bar.
        return st.isEmpty
    }

    func activeNonRevenueEntityId(for arac: Arac) -> Int? {
        guard let event = activeNonRevenueEvent(for: arac) else { return nil }
        let digits = event.recordId.filter { $0.isNumber }
        guard !digits.isEmpty, let id = Int(digits) else { return nil }
        return id
    }

    /// Open booking/checkout slot on fleet chart — blocks new NTR even when status shows available.
    func activeBookingEvent(for arac: Arac) -> WheelSysFleetEvent? {
        guard let vehicle = fleetVehicle(for: arac) else { return nil }
        return vehicle.events.first { event in
            let type = event.type.lowercased()
            let st = event.status.lowercased()
            guard type == "booking" else { return false }
            return st != "closed" && !st.contains("closed")
        }
    }

    /// NTR / RENTAL / AVAILABLE badge for list rows and vehicle detail (CH ops).
    func fleetOpsBadge(for arac: Arac, hasActiveCheckout: Bool = false) -> WheelSysFleetOpsBadge {
        if arac.wheelsysNtrStatus == WheelSysNTRStatus.active.rawValue || isFleetNonRevenue(arac) {
            return WheelSysFleetOpsBadge(kind: .ntr)
        }
        if hasActiveCheckout || isVehicleOnRental(arac) {
            return WheelSysFleetOpsBadge(kind: .rental)
        }
        return WheelSysFleetOpsBadge(kind: .available)
    }

    func matches(
        filter: VehicleFleetOpsFilter,
        arac: Arac,
        parkedVehicleIds: Set<UUID>,
        openCheckoutVehicleIds: Set<UUID> = [],
        inProgressCheckoutVehicleIds: Set<UUID> = []
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .parking:
            return parkedVehicleIds.contains(arac.id)
        case .ntr:
            if arac.wheelsysNtrStatus == WheelSysNTRStatus.active.rawValue { return true }
            return isFleetNonRevenue(arac)
        case .available:
            if isVehicleOnRental(arac) { return false }
            if parkedVehicleIds.contains(arac.id) { return true }
            if inProgressCheckoutVehicleIds.contains(arac.id) { return false }
            let s = (status(for: arac) ?? "").lowercased()
            if s == "available" { return true }
            // Unassigned / unknown fleet status — treat as available when not on rental.
            return s.isEmpty
        case .rental:
            if openCheckoutVehicleIds.contains(arac.id) { return true }
            return isVehicleOnRental(arac)
        }
    }
}
