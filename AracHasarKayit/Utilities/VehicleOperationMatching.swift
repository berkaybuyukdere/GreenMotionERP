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
}
