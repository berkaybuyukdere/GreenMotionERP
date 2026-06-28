import Foundation

/// Matches checkout / return / damage rows to a fleet vehicle the same way the web UI does:
/// primary `aracId`, fallback normalized plate when legacy rows used a different vehicle UUID.
enum VehicleOperationMatching {
    static func normalizedPlateKey(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    }

    static func matchesVehicle(aracId: UUID, plate: String, vehicle: Arac) -> Bool {
        if aracId == vehicle.id { return true }
        let op = normalizedPlateKey(plate)
        let vehicleKey = vehicle.canonicalPlateKey
        guard !op.isEmpty, !vehicleKey.isEmpty else { return false }
        return op == vehicleKey
    }

    static func iadeBelongsToVehicle(_ iade: IadeIslemi, vehicle: Arac) -> Bool {
        matchesVehicle(aracId: iade.aracId, plate: iade.aracPlaka, vehicle: vehicle)
    }

    static func exitBelongsToVehicle(_ exit: ExitIslemi, vehicle: Arac) -> Bool {
        matchesVehicle(aracId: exit.aracId, plate: exit.aracPlaka, vehicle: vehicle)
    }

    static func hasarBelongsToVehicle(_ hasar: HasarKaydi, vehicle: Arac) -> Bool {
        matchesVehicle(aracId: hasar.aracId, plate: hasar.aracPlaka, vehicle: vehicle)
    }

    private static func checkoutRecency(_ exit: ExitIslemi) -> Date {
        max(exit.createdAt, exit.exitTarihi)
    }

    /// Precomputed fleet-ops lifecycle sets for Vehicles filters/badges (O(exits + returns), not O(N·M)).
    struct FleetOpsLifecycleIndex: Sendable {
        let parkedVehicleIds: Set<UUID>
        let openCompletedOutboundVehicleIds: Set<UUID>
        let inProgressCheckoutVehicleIds: Set<UUID>
        let openCheckoutVehicleIds: Set<UUID>

        static let empty = FleetOpsLifecycleIndex(
            parkedVehicleIds: [],
            openCompletedOutboundVehicleIds: [],
            inProgressCheckoutVehicleIds: [],
            openCheckoutVehicleIds: []
        )

        static func build(
            vehicles: [Arac],
            exits: [ExitIslemi],
            returns: [IadeIslemi]
        ) -> FleetOpsLifecycleIndex {
            guard !vehicles.isEmpty else { return .empty }

            let vehicleIds = Set(vehicles.map(\.id))
            var plateToVehicleId: [String: UUID] = [:]
            plateToVehicleId.reserveCapacity(vehicles.count)
            for vehicle in vehicles {
                let key = normalizedPlateKey(vehicle.plaka)
                if !key.isEmpty { plateToVehicleId[key] = vehicle.id }
            }

            func resolveVehicleId(aracId: UUID, plate: String) -> UUID? {
                if vehicleIds.contains(aracId) { return aracId }
                let key = normalizedPlateKey(plate)
                guard !key.isEmpty else { return nil }
                return plateToVehicleId[key]
            }

            var exitsByVehicle: [UUID: [ExitIslemi]] = [:]
            exitsByVehicle.reserveCapacity(vehicles.count)
            var inProgressIds: Set<UUID> = []
            var openCheckoutIds: Set<UUID> = []

            for exit in exits where !exit.isDeleted {
                guard let vehicleId = resolveVehicleId(aracId: exit.aracId, plate: exit.aracPlaka) else {
                    continue
                }
                exitsByVehicle[vehicleId, default: []].append(exit)
                switch exit.status {
                case .inProgress:
                    inProgressIds.insert(vehicleId)
                    openCheckoutIds.insert(vehicleId)
                case .parked:
                    openCheckoutIds.insert(vehicleId)
                default:
                    break
                }
            }

            var lastReturnByVehicle: [UUID: Date] = [:]
            for ret in returns where !ret.isDeleted && ret.status == .completed {
                guard let vehicleId = resolveVehicleId(aracId: ret.aracId, plate: ret.aracPlaka) else {
                    continue
                }
                let recency = max(ret.createdAt, ret.iadeTarihi)
                if let existing = lastReturnByVehicle[vehicleId] {
                    if recency > existing { lastReturnByVehicle[vehicleId] = recency }
                } else {
                    lastReturnByVehicle[vehicleId] = recency
                }
            }

            var parkedIds: Set<UUID> = []
            var openCompletedIds: Set<UUID> = []
            parkedIds.reserveCapacity(32)
            openCompletedIds.reserveCapacity(64)

            for vehicle in vehicles {
                let vehicleExits = exitsByVehicle[vehicle.id] ?? []
                guard !vehicleExits.isEmpty else { continue }
                let cutoff = lastReturnByVehicle[vehicle.id]

                var latest: ExitIslemi?
                var latestRecency = Date.distantPast
                for exit in vehicleExits {
                    guard exit.status == .completed || exit.status == .parked || exit.status == .inProgress else {
                        continue
                    }
                    let recency = checkoutRecency(exit)
                    if let cutoff, recency <= cutoff { continue }
                    if recency > latestRecency || (recency == latestRecency && (latest?.createdAt ?? .distantPast) < exit.createdAt) {
                        latest = exit
                        latestRecency = recency
                    }
                }

                guard let latest else { continue }
                switch latest.status {
                case .parked:
                    parkedIds.insert(vehicle.id)
                case .completed:
                    openCompletedIds.insert(vehicle.id)
                case .inProgress:
                    break
                }
            }

            return FleetOpsLifecycleIndex(
                parkedVehicleIds: parkedIds,
                openCompletedOutboundVehicleIds: openCompletedIds,
                inProgressCheckoutVehicleIds: inProgressIds,
                openCheckoutVehicleIds: openCheckoutIds
            )
        }
    }

    static func activeParkedVehicleIds(
        vehicles: [Arac],
        exits: [ExitIslemi],
        returns: [IadeIslemi]
    ) -> Set<UUID> {
        FleetOpsLifecycleIndex.build(vehicles: vehicles, exits: exits, returns: returns).parkedVehicleIds
    }

    static func openCompletedOutboundVehicleIds(
        vehicles: [Arac],
        exits: [ExitIslemi],
        returns: [IadeIslemi]
    ) -> Set<UUID> {
        FleetOpsLifecycleIndex.build(vehicles: vehicles, exits: exits, returns: returns).openCompletedOutboundVehicleIds
    }

    /// Latest open outbound checkout (completed, parked, or in-progress) after the last return.
    static func latestOpenOutbound(
        for vehicle: Arac,
        exits: [ExitIslemi],
        returns: [IadeIslemi]
    ) -> ExitIslemi? {
        let cutoff = returns
            .filter { iadeBelongsToVehicle($0, vehicle: vehicle) && $0.status == .completed }
            .map { max($0.createdAt, $0.iadeTarihi) }
            .max()
        let candidates = exits.filter { exit in
            guard exitBelongsToVehicle(exit, vehicle: vehicle), !exit.isDeleted else { return false }
            guard exit.status == .completed || exit.status == .parked || exit.status == .inProgress else {
                return false
            }
            guard let cutoff else { return true }
            return checkoutRecency(exit) > cutoff
        }
        return candidates.max { a, b in
            let ra = checkoutRecency(a)
            let rb = checkoutRecency(b)
            if ra != rb { return ra < rb }
            return a.createdAt < b.createdAt
        }
    }
}
