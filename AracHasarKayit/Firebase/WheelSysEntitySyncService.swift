import Foundation

struct WheelSysEntitySyncResult: Equatable {
    var matched = 0
    var unmatched = 0
    var ambiguous = 0
    var written = 0
    var categoriesUpdated = 0
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

    private static var clientWritesDisabled = false

    @MainActor
    static func sync(
        fleet: WheelSysFleetChartResult,
        araclar: [Arac],
        service: FirebaseService = .shared
    ) async -> WheelSysEntitySyncResult {
        guard !clientWritesDisabled else { return WheelSysEntitySyncResult() }
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
            if clientWritesDisabled { break }
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
                await syncFleetCategoryIfNeeded(
                    arac: arac,
                    fleetGroup: vehicle.group,
                    service: service,
                    cid: cid,
                    result: &result
                )
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
            "done matched=\(result.matched) unmatched=\(result.unmatched) ambiguous=\(result.ambiguous) " +
            "written=\(result.written) categories=\(result.categoriesUpdated)",
            cid: cid
        )
        return result
    }

    @MainActor
    private static func syncFleetCategoryIfNeeded(
        arac: Arac,
        fleetGroup: String,
        service: FirebaseService,
        cid: String,
        result: inout WheelSysEntitySyncResult
    ) async {
        let normalizedFleetGroup = fleetGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetGroup.isEmpty else { return }
        let appCategory = arac.kategori.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appCategory.uppercased() != normalizedFleetGroup.uppercased() else { return }

        let didWrite = await withCheckedContinuation { continuation in
            service.mergeWheelSysEntityFields(
                aracId: arac.id,
                vehicleId: nil,
                rentalEntityId: nil,
                plateCanonical: nil,
                syncStatus: nil,
                fleetGroup: normalizedFleetGroup
            ) { error in
                if let error {
                    if Self.isPermissionDenied(error) {
                        clientWritesDisabled = true
                        WheelSysDebug.error(
                            "EntitySync",
                            "Firestore permission denied — disabling client entity sync for this session",
                            cid: cid
                        )
                    } else {
                        WheelSysDebug.error(
                            "EntitySync",
                            "category write failed plate=\(arac.plaka): \(error.localizedDescription)",
                            cid: cid
                        )
                    }
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
        if didWrite { result.categoriesUpdated += 1 }
    }

    private static func resolveRentalEntityId(_ vehicle: WheelSysFleetVehicle) -> Int? {
        WheelSysCheckinService.resolveRentalEntityId(from: vehicle)
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
                    if Self.isPermissionDenied(error) {
                        clientWritesDisabled = true
                        WheelSysDebug.error(
                            "EntitySync",
                            "Firestore permission denied — disabling client entity sync for this session",
                            cid: cid
                        )
                    } else {
                        WheelSysDebug.error("EntitySync", "write failed plate=\(arac.plaka): \(error.localizedDescription)", cid: cid)
                    }
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }
}

private extension WheelSysEntitySyncService {
    static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain.contains("Firestore") || ns.domain == "FIRFirestoreErrorDomain")
            && ns.code == 7
    }
}
