import Foundation

struct WheelSysEntitySyncResult: Equatable {
    var matched = 0
    var unmatched = 0
    var ambiguous = 0
    var written = 0
}

/// Links Firebase `araclar` to WheelSys fleet vehicles by canonical plate and
/// stores the resolved `wheelsysVehicleId` / `wheelsysRentalEntityId` per vehicle.
///
/// Rules:
/// 1. `canonical(arac.plaka) == canonical(fleet.plate)`
/// 2. Active rental event (`type==rental && status==active`) → `rentalEntityId`,
///    otherwise the most recent rental event with an entity id.
/// 3. Ambiguous: one canonical plate maps to multiple fleet vehicles → status
///    only, never write an entity id.
/// 4. Unmatched: vehicle exists in Firebase but not in fleet → status only.
///
/// Writes are partial merges (never overwrites other fields) and are skipped when
/// nothing changed, so a fleet reload does not churn Firestore.
enum WheelSysEntitySyncService {

    @MainActor
    static func sync(
        fleet: WheelSysFleetChartResult,
        araclar: [Arac],
        service: FirebaseService = .shared
    ) async -> WheelSysEntitySyncResult {
        let cid = WheelSysDebug.newCorrelationId()

        // canonical plate -> fleet vehicles (detect ambiguity)
        var plateMap: [String: [WheelSysFleetVehicle]] = [:]
        for vehicle in fleet.vehicles {
            let key = WheelSysPlateNormalizer.canonical(vehicle.plate)
            guard !key.isEmpty else { continue }
            plateMap[key, default: []].append(vehicle)
        }
        WheelSysDebug.log("EntitySync", "fleet plates=\(plateMap.count) araclar=\(araclar.count)", cid: cid)

        var result = WheelSysEntitySyncResult()

        for arac in araclar {
            let key = WheelSysPlateNormalizer.canonical(arac.plaka)
            guard !key.isEmpty else { continue }
            let matches = plateMap[key] ?? []

            let status: String
            var vehicleId: String?
            var rentalEntityId: Int?

            switch matches.count {
            case 0:
                status = "unmatched"
                result.unmatched += 1
            case 1:
                status = "matched"
                let vehicle = matches[0]
                vehicleId = vehicle.vehicleId
                rentalEntityId = resolveRentalEntityId(vehicle)
                result.matched += 1
            default:
                status = "ambiguous"
                result.ambiguous += 1
                WheelSysDebug.log("EntitySync", "ambiguous plate=\(key) candidates=\(matches.count)", cid: cid)
            }

            // Skip write when nothing changed (avoid Firestore churn on reloads).
            let unchanged = arac.wheelsysEntitySyncStatus == status
                && arac.wheelsysVehicleId == vehicleId
                && arac.wheelsysRentalEntityId == rentalEntityId
                && (status != "matched" || arac.wheelsysPlateCanonical == key)
            if unchanged { continue }

            let didWrite = await write(
                arac: arac,
                vehicleId: vehicleId,
                rentalEntityId: rentalEntityId,
                plateCanonical: status == "matched" ? key : arac.wheelsysPlateCanonical,
                status: status,
                service: service,
                cid: cid
            )
            if didWrite { result.written += 1 }
        }

        WheelSysDebug.log(
            "EntitySync",
            "done matched=\(result.matched) unmatched=\(result.unmatched) ambiguous=\(result.ambiguous) written=\(result.written)",
            cid: cid
        )
        return result
    }

    private static func resolveRentalEntityId(_ vehicle: WheelSysFleetVehicle) -> Int? {
        let active = vehicle.events.first {
            $0.type == "rental" && $0.status == "active" && $0.rentalEntityId != nil
        }
        let any = vehicle.events.last { $0.type == "rental" && $0.rentalEntityId != nil }
        return (active ?? any)?.rentalEntityId
    }

    @MainActor
    private static func write(
        arac: Arac,
        vehicleId: String?,
        rentalEntityId: Int?,
        plateCanonical: String?,
        status: String,
        service: FirebaseService,
        cid: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            service.mergeWheelSysEntityFields(
                aracId: arac.id,
                vehicleId: vehicleId,
                rentalEntityId: rentalEntityId,
                plateCanonical: plateCanonical,
                syncStatus: status
            ) { error in
                if let error {
                    WheelSysDebug.error("EntitySync", "write failed plate=\(arac.plaka): \(error.localizedDescription)", cid: cid)
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
