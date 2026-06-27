import Foundation

/// Persists WheelSys fleet status snapshot per franchise for instant Vehicles filters / km micro text.
/// Full fleet chart still refreshes from network; this avoids blank UI on cold start.
enum WheelSysFleetDiskCache {
    struct VehicleRow: Codable {
        let plateCanonical: String
        let vehicleId: String
        let mileage: Int
        let status: String
        let fuel: Int?
    }

    struct Snapshot: Codable {
        let franchiseId: String
        let savedAt: Date
        let vehicles: [VehicleRow]
    }

    private static let ttl: TimeInterval = 24 * 60 * 60

    private static func fileURL(franchiseId: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WheelSysFleetCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = franchiseId.uppercased().replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }

    static func load(franchiseId: String) -> Snapshot? {
        let fid = franchiseId.uppercased()
        guard let data = try? Data(contentsOf: fileURL(franchiseId: fid)),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.franchiseId.uppercased() == fid,
              Date().timeIntervalSince(snap.savedAt) < ttl
        else { return nil }
        return snap
    }

    static func save(from fleet: WheelSysFleetChartResult, franchiseId: String, fuelByPlate: [String: Int]) {
        let fid = franchiseId.uppercased()
        let rows = fleet.vehicles.map { v -> VehicleRow in
            let key = WheelSysPlateNormalizer.canonical(v.plate)
            return VehicleRow(
                plateCanonical: key,
                vehicleId: v.vehicleId,
                mileage: v.mileage,
                status: v.status.lowercased(),
                fuel: fuelByPlate[key]
            )
        }
        let snap = Snapshot(franchiseId: fid, savedAt: Date(), vehicles: rows)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL(franchiseId: fid), options: .atomic)
    }
}
