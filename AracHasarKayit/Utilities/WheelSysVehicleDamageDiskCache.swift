import Foundation

/// Persists last WheelSys vehicle damage history per plate for instant UI on vehicle detail / checkout / return.
enum WheelSysVehicleDamageDiskCache {
    private static let ttl: TimeInterval = 6 * 60 * 60

    private static func fileURL(franchiseId: String, plateCanonical: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WheelSysDamageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fid = franchiseId.uppercased().replacingOccurrences(of: "/", with: "_")
        let plate = plateCanonical.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(fid)_\(plate).json")
    }

    static func load(franchiseId: String, plate: String) -> WheelSysVehicleDamageHistoryResponse? {
        let fid = franchiseId.uppercased()
        let key = WheelSysPlateNormalizer.canonical(plate)
        guard !fid.isEmpty, !key.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: fileURL(franchiseId: fid, plateCanonical: key)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.franchiseId.uppercased() == fid,
              envelope.plateCanonical == key,
              Date().timeIntervalSince(envelope.savedAt) < ttl
        else { return nil }
        return envelope.response
    }

    static func save(_ response: WheelSysVehicleDamageHistoryResponse, franchiseId: String, plate: String) {
        let fid = franchiseId.uppercased()
        let key = WheelSysPlateNormalizer.canonical(plate)
        guard !fid.isEmpty, !key.isEmpty else { return }
        let envelope = Envelope(
            franchiseId: fid,
            plateCanonical: key,
            savedAt: Date(),
            response: response
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: fileURL(franchiseId: fid, plateCanonical: key), options: .atomic)
    }

    private struct Envelope: Codable {
        let franchiseId: String
        let plateCanonical: String
        let savedAt: Date
        let response: WheelSysVehicleDamageHistoryResponse
    }
}

extension WheelSysVehicleDamageHistoryResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case vehicleId, resolvedVehicleEntityId, damages, damageCount, syncedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vehicleId = try c.decode(Int.self, forKey: .vehicleId)
        resolvedVehicleEntityId = try c.decode(String.self, forKey: .resolvedVehicleEntityId)
        damages = try c.decode([WheelSysVehicleDamageRecord].self, forKey: .damages)
        damageCount = try c.decode(Int.self, forKey: .damageCount)
        syncedAt = try c.decode(String.self, forKey: .syncedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(resolvedVehicleEntityId, forKey: .resolvedVehicleEntityId)
        try c.encode(damages, forKey: .damages)
        try c.encode(damageCount, forKey: .damageCount)
        try c.encode(syncedAt, forKey: .syncedAt)
    }
}
