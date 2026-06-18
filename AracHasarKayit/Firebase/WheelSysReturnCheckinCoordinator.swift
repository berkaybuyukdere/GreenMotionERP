import Foundation

/// Drives the WheelSys check-in embedded in the return (iade) flow: resolves the
/// rental entityId, loads a read-only km/fuel preview, and pushes the check-in to
/// WheelSys during return completion. The return can always be completed in
/// Firebase even if WheelSys sync fails (ops flexibility).
@MainActor
final class WheelSysReturnCheckinCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingPreview
        case ready
        case noEntity
        case failed(String)
    }

    enum CompletionSyncPhase: Equatable {
        case idle
        case savingRental
        case savingVehicle
        case savingNotes
        case done
        case warning(String)
    }

    @Published var phase: Phase = .idle
    @Published var preview: WheelSysRentalPreview?
    @Published var entityId: String?
    @Published var resolvedResNo: String = ""
    @Published var completionSyncPhase: CompletionSyncPhase = .idle
    @Published var lastResult: WheelSysCheckinResult?

    private var franchiseId = ""
    private var plate = ""
    private var fleetCarId: String?

    var completionMicrocopy: String {
        switch completionSyncPhase {
        case .idle:
            return "wheelsys.return.syncing_micro".localized
        case .savingRental:
            return "wheelsys.return.sync.saving_rental".localized
        case .savingVehicle:
            return "wheelsys.return.sync.saving_vehicle".localized
        case .savingNotes:
            return "wheelsys.return.sync.saving_notes".localized
        case .done:
            return "wheelsys.return.success".localized
        case .warning(let msg):
            return msg.isEmpty ? "wheelsys.return.failed".localized : msg
        }
    }

    // MARK: Resolve + preview

    /// Resolve entityId then load the read-only preview. Order:
    /// search by RES → fleet lookup by plate → stored `wheelsysRentalEntityId`.
    func resolveAndLoadPreview(arac: Arac, resNo: String, franchiseId: String) async {
        guard phase == .idle || phase == .noEntity else { return }
        self.franchiseId = franchiseId.uppercased()
        self.plate = arac.plaka
        self.fleetCarId = arac.wheelsysVehicleId
        let cid = WheelSysDebug.newCorrelationId()
        resolvedResNo = resNo.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .loadingPreview
        WheelSysDebug.log("ReturnCheckin", "resolve plate=\(plate) res=\(resolvedResNo)", cid: cid)

        do {
            let resolved = try await resolveEntityId(arac: arac, resNo: resolvedResNo, cid: cid)
            guard let resolved, !resolved.isEmpty else {
                phase = .noEntity
                WheelSysDebug.log("ReturnCheckin", "no entityId resolved", cid: cid)
                return
            }
            entityId = resolved
            let preview = try await WheelSysCheckinService.loadPreview(
                franchiseId: franchiseId,
                entityId: resolved,
                expectedResNo: resolvedResNo.isEmpty ? nil : resolvedResNo
            )
            self.preview = preview
            phase = .ready
            WheelSysDebug.log(
                "ReturnCheckin",
                "preview ready entityId=\(resolved) kmTo=\(preview.mileageTo) fuelTo=\(preview.fuelTo)",
                cid: cid
            )
        } catch {
            phase = .failed(error.localizedDescription)
            WheelSysDebug.error("ReturnCheckin", "preview failed: \(error.localizedDescription)", cid: cid)
        }
    }

    /// Reload preview after a note is saved (keeps notes list current).
    func reloadPreview() async {
        guard let entityId, !franchiseId.isEmpty else { return }
        do {
            let preview = try await WheelSysCheckinService.loadPreview(
                franchiseId: franchiseId,
                entityId: entityId,
                expectedResNo: resolvedResNo.isEmpty ? nil : resolvedResNo
            )
            self.preview = preview
            if case .failed = phase {
                phase = .ready
            }
        } catch {
            WheelSysDebug.error("ReturnCheckin", "preview reload failed: \(error.localizedDescription)")
        }
    }

    private func resolveEntityId(arac: Arac, resNo: String, cid: String) async throws -> String? {
        if !resNo.isEmpty {
            let hits = try await WheelSysCheckinService.searchByRes(franchiseId: franchiseId, resQuery: resNo)
            if let hit = hits.first(where: { $0.hasEntityId }), let id = hit.entityId {
                WheelSysDebug.log("ReturnCheckin", "entityId from RES search=\(id)", cid: cid)
                return id
            }
        }

        if let fleet = try? await WheelSysCheckinService.loadFleetChart(franchiseId: franchiseId),
           let fleetId = WheelSysCheckinService.findRentalEntityId(in: fleet, for: plate) {
            fleetCarId = fleet.vehicles.first(where: {
                WheelSysPlateNormalizer.canonical($0.plate) ==
                WheelSysPlateNormalizer.canonical(plate)
            })?.vehicleId ?? fleetCarId
            WheelSysDebug.log("ReturnCheckin", "entityId from fleet plate=\(fleetId)", cid: cid)
            return String(fleetId)
        }

        if let stored = arac.wheelsysRentalEntityId {
            WheelSysDebug.log("ReturnCheckin", "entityId from arac fallback=\(stored)", cid: cid)
            return String(stored)
        }

        return nil
    }

    /// Re-resolve rental entityId from RES immediately before sync (fleet can drift).
    private func reResolveEntityFromRes(cid: String) async -> String? {
        guard !resolvedResNo.isEmpty else { return entityId }
        do {
            let hits = try await WheelSysCheckinService.searchByRes(
                franchiseId: franchiseId,
                resQuery: resolvedResNo
            )
            if let hit = hits.first(where: { $0.hasEntityId }), let id = hit.entityId {
                WheelSysDebug.log("ReturnCheckin", "complete-sync re-resolved entityId=\(id)", cid: cid)
                return id
            }
        } catch {
            WheelSysDebug.error(
                "ReturnCheckin",
                "complete-sync RES re-resolve failed: \(error.localizedDescription)",
                cid: cid
            )
        }
        return entityId
    }

    // MARK: Completion sync

    /// Called from the return completion overlay — syncs km/fuel to WheelSys.
    /// Non-blocking: returns `false` on failure but callers should still complete the return.
    @discardableResult
    func submitCheckinOnComplete(
        km: Int,
        fuel: Int,
        firestoreDocId: String?,
        userNote: String?
    ) async -> Bool {
        let cid = WheelSysDebug.newCorrelationId()
        completionSyncPhase = .savingRental

        if let refreshedId = await reResolveEntityFromRes(cid: cid) {
            entityId = refreshedId
        }
        guard let entityId else { return false }

        // Preview optional at completion — fetch inline when missing but entityId is known.
        var activePreview = preview
        if activePreview == nil {
            do {
                activePreview = try await WheelSysCheckinService.loadPreview(
                    franchiseId: franchiseId,
                    entityId: entityId,
                    expectedResNo: resolvedResNo.isEmpty ? nil : resolvedResNo
                )
                preview = activePreview
            } catch {
                WheelSysDebug.error(
                    "ReturnCheckin",
                    "inline preview fetch failed (continuing): \(error.localizedDescription)",
                    cid: cid
                )
            }
        }

        WheelSysDebug.log("ReturnCheckin", "complete-sync entityId=\(entityId) km=\(km) fuel=\(fuel)", cid: cid)

        let checkInUserId = activePreview?.checkInUserId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedUserNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingNote = (trimmedUserNote?.isEmpty == false) ? trimmedUserNote : nil

        let vehicleEntityHint = activePreview?.vehicleEntityId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resNoForSync = activePreview?.resNo.isEmpty == false ?
            activePreview!.resNo : resolvedResNo
        let plateForSync = activePreview?.plate.isEmpty == false ?
            activePreview!.plate : plate

        do {
            let result = try await WheelSysCheckinService.submitCheckinUpdate(
                franchiseId: franchiseId,
                entityId: entityId,
                resNo: resNoForSync,
                plate: plateForSync,
                checkInMileage: km,
                checkInFuel: fuel,
                checkInUserId: checkInUserId.isEmpty ? nil : checkInUserId,
                firestoreCollection: firestoreDocId == nil ? nil : "iadeIslemleri",
                firestoreDocId: firestoreDocId,
                addAutoNotes: true,
                rentalNoteText: pendingNote,
                vehicleEntityIdHint: vehicleEntityHint.isEmpty ? nil : vehicleEntityHint,
                fleetCarId: fleetCarId
            )
            lastResult = result

            if result.vehicleMasterSynced {
                completionSyncPhase = .savingVehicle
            } else if result.vehicleEntityId != nil {
                completionSyncPhase = .warning("wheelsys.return.vehicle_master_failed".localized)
                WheelSysDebug.error(
                    "ReturnCheckin",
                    "vehicle master not synced entity=\(result.vehicleEntityId ?? "")",
                    cid: cid
                )
                return false
            }

            if pendingNote != nil {
                completionSyncPhase = .savingNotes
            }

            if result.success {
                completionSyncPhase = .done
                WheelSysDebug.log(
                    "ReturnCheckin",
                    "complete-sync success verifiedKm=\(result.verifiedMileageTo.map(String.init) ?? "nil")",
                    cid: cid
                )
                return true
            } else {
                let msg = result.message.isEmpty ? "wheelsys.return.failed".localized : result.message
                completionSyncPhase = .warning(msg)
                WheelSysDebug.error("ReturnCheckin", "complete-sync reported failure: \(result.message)", cid: cid)
                return false
            }
        } catch {
            completionSyncPhase = .warning(error.localizedDescription)
            WheelSysDebug.error("ReturnCheckin", "complete-sync failed: \(error.localizedDescription)", cid: cid)
            return false
        }
    }

    func beginCompletionSync() {
        completionSyncPhase = .savingRental
    }

    func resetCompletionSync() {
        completionSyncPhase = .idle
    }

    func reset() {
        phase = .idle
        completionSyncPhase = .idle
    }
}
