import Foundation

extension Notification.Name {
    static let wheelSysReturnPreviewUpdated = Notification.Name("wheelSysReturnPreviewUpdated")
}

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

    static let previewLoadTimeout: TimeInterval = 15

    @Published var phase: Phase = .idle
    @Published var preview: WheelSysRentalPreview?
    @Published var entityId: String?
    @Published var resolvedResNo: String = ""
    @Published var completionSyncPhase: CompletionSyncPhase = .idle
    @Published var lastResult: WheelSysCheckinResult?

    private var franchiseId = ""
    private var plate = ""
    private var fleetCarId: String?
    private var prefillFallback: WheelSysReturnOperationPrefill?
    private var lockedRentalAfterPrecheckin: WheelSysLockedRentalContext?

    var isPrecheckinLocked: Bool { lockedRentalAfterPrecheckin != nil }

    /// Lock rental identity after successful pre-check-in. Final check-in must not re-resolve via RES.
    func lockRentalAfterPrecheckin(_ context: WheelSysLockedRentalContext) {
        lockedRentalAfterPrecheckin = context
        entityId = String(context.rentalId)
        if let vid = context.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines), !vid.isEmpty {
            fleetCarId = vid
        }
        if !context.plate.isEmpty {
            plate = context.plate
        }
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnCheckin",
            "locked rentalId=\(context.rentalId) vehicleId=\(context.vehicleId ?? "nil") plate=\(context.plate) — RES search disabled"
        )
    }

    private func previewExpectedResNo() -> String? {
        nil
    }

    private func previewLockEntityId() -> Bool {
        lockedRentalAfterPrecheckin != nil
            || (prefillFallback?.rentalEntityId ?? 0) > 0
            || !(entityId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func effectiveEntityIdForSync(cid: String) async -> String? {
        if let locked = lockedRentalAfterPrecheckin {
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "ReturnCheckin",
                "using locked rentalId=\(locked.rentalId) vehicleId=\(locked.vehicleId ?? "nil"), skipping searchByRes",
                cid: cid
            )
            return String(locked.rentalId)
        }
        return await reResolveEntityFromRes(cid: cid)
    }

    private func publishPreviewUpdate() {
        NotificationCenter.default.post(name: .wheelSysReturnPreviewUpdated, object: nil)
    }

    private func assignPreview(_ loaded: WheelSysRentalPreview?) {
        preview = loaded
        publishPreviewUpdate()
    }

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

    // MARK: - Fallback preview

    static func buildFallbackPreview(
        from prefill: WheelSysReturnOperationPrefill,
        entityId: String,
        fleetVehicle: WheelSysFleetVehicle? = nil
    ) -> WheelSysRentalPreview {
        let checkoutKm = prefill.checkoutMileage ?? fleetVehicle?.mileage ?? 0
        let checkoutFuel = prefill.checkoutFuel ?? 0
        let checkinKm = WheelSysReturnMileageFuel.effectiveCheckinMileage(prefill.checkinMileageHint) ?? 0
        let checkinFuel = WheelSysReturnMileageFuel.effectiveCheckinFuel(
            prefill.checkinFuelHint,
            checkout: checkoutFuel
        ) ?? checkoutFuel
        let vehicleId = prefill.vehicleEntityId
            ?? fleetVehicle?.vehicleId
            ?? ""

        return WheelSysRentalPreview(
            entityId: entityId,
            vehicleEntityId: vehicleId,
            resNo: prefill.resNo,
            raNo: prefill.raNo ?? "",
            plate: fleetVehicle?.plate ?? "",
            mileageFrom: checkoutKm,
            mileageTo: checkinKm,
            fuelFrom: checkoutFuel,
            fuelTo: checkinFuel,
            checkoutMileageText: checkoutKm > 0 ? "\(checkoutKm)" : "",
            checkinMileageText: checkinKm > 0 ? "\(checkinKm)" : "",
            vehicleMasterMileage: fleetVehicle?.mileage,
            vehicleMasterFuel: nil,
            milesDriven: max(0, checkinKm - checkoutKm),
            checkInUserId: "",
            checkInUserOptions: [],
            dateFrom: "",
            timeFrom: "",
            dateTo: "",
            timeTo: "",
            insurance: nil,
            rentalNotes: [],
            vehicleNotes: [],
            customerName: prefill.driverName,
            customerEmail: prefill.customerEmail ?? ""
        )
    }

    private func applyPrefillFallbackIfNeeded(
        entityId: String,
        prefill: WheelSysReturnOperationPrefill?,
        fleetVehicle: WheelSysFleetVehicle?
    ) {
        guard let prefill else { return }
        prefillFallback = prefill
        if preview == nil {
            assignPreview(Self.buildFallbackPreview(
                from: prefill,
                entityId: entityId,
                fleetVehicle: fleetVehicle
            ))
        }
    }

    private func fleetVehicleForPlate(_ plate: String) -> WheelSysFleetVehicle? {
        WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate)
    }

    // MARK: - Prefill bootstrap (instant UI, no spinner)

    /// Apply journal/vehicle prefill synchronously so notes & sync UI render immediately.
    func prepareFromPrefill(_ prefill: WheelSysReturnOperationPrefill, arac: Arac) {
        franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        plate = arac.plaka
        fleetCarId = prefill.vehicleEntityId ?? arac.wheelsysVehicleId
        resolvedResNo = prefill.resNo.trimmingCharacters(in: .whitespacesAndNewlines)
        prefillFallback = prefill

        if prefill.rentalEntityId > 0 {
            entityId = String(prefill.rentalEntityId)
        }

        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnCheckin",
            "prefill bootstrap plate=\(plate) res=\(resolvedResNo) entityId=\(entityId ?? "nil") rentalId=\(prefill.rentalEntityId)"
        )

        let fleetVehicle = fleetVehicleForPlate(arac.plaka)
        if preview == nil, let entityId, !entityId.isEmpty {
            assignPreview(Self.buildFallbackPreview(
                from: prefill,
                entityId: entityId,
                fleetVehicle: fleetVehicle
            ))
        } else if preview == nil, prefill.rentalEntityId > 0 {
            assignPreview(Self.buildFallbackPreview(
                from: prefill,
                entityId: String(prefill.rentalEntityId),
                fleetVehicle: fleetVehicle
            ))
        }
    }

    // MARK: - Preview loading

    /// Load preview when rental entityId is already known (journal / plate scan / vehicle detail).
    func loadPreviewWithKnownEntity(
        franchiseId: String,
        entityId: String,
        resNo: String,
        arac: Arac,
        fleetCarId: String? = nil,
        prefill: WheelSysReturnOperationPrefill? = nil
    ) async {
        let cid = WheelSysDebug.newCorrelationId()
        self.franchiseId = franchiseId.uppercased()
        self.plate = arac.plaka
        self.fleetCarId = fleetCarId ?? arac.wheelsysVehicleId
        resolvedResNo = resNo.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entityId = entityId
        phase = .loadingPreview
        prefillFallback = prefill
        WheelSysDebug.logCH(
            franchiseId: self.franchiseId,
            "ReturnCheckin",
            "loadPreview known entityId=\(entityId) plate=\(plate) res=\(resolvedResNo)",
            cid: cid
        )

        let fleetVehicle = fleetVehicleForPlate(arac.plaka)
        applyPrefillFallbackIfNeeded(entityId: entityId, prefill: prefill, fleetVehicle: fleetVehicle)

        do {
            let loaded = try await Self.loadPreviewResilient(
                franchiseId: franchiseId,
                entityId: entityId,
                expectedResNo: nil,
                lockEntityId: true
            )
            assignPreview(loaded)
            if loaded.resNo.isEmpty == false {
                resolvedResNo = loaded.resNo
            }
            phase = .ready
            WheelSysDebug.logCH(
                franchiseId: self.franchiseId,
                "ReturnCheckin",
                "preview ready kmTo=\(loaded.mileageTo) fuelTo=\(loaded.fuelTo) res=\(loaded.resNo)",
                cid: cid
            )
        } catch {
            if preview == nil, let prefill {
                assignPreview(Self.buildFallbackPreview(
                    from: prefill,
                    entityId: entityId,
                    fleetVehicle: fleetVehicle
                ))
                WheelSysDebug.warnCH(
                    franchiseId: self.franchiseId,
                    "ReturnCheckin",
                    "preview failed — using prefill fallback",
                    cid: cid
                )
            }
            if preview != nil {
                phase = .ready
                WheelSysDebug.warnCH(
                    franchiseId: self.franchiseId,
                    "ReturnCheckin",
                    "preview degraded (fallback data): \(error.localizedDescription)",
                    cid: cid
                )
            } else {
                phase = .failed(WheelSysUserFacingError.message(for: error))
                WheelSysDebug.errorCH(
                    franchiseId: self.franchiseId,
                    "ReturnCheckin",
                    "loadPreview failed: \(error.localizedDescription)",
                    cid: cid
                )
            }
        }
    }

    // MARK: Resolve + preview

    /// Resolve entityId then load the read-only preview. Order:
    /// search by RES → fleet lookup by plate → stored `wheelsysRentalEntityId`.
    func resolveAndLoadPreview(
        arac: Arac,
        resNo: String,
        franchiseId: String,
        prefill: WheelSysReturnOperationPrefill? = nil
    ) async {
        if case .failed = phase { reset() }
        guard phase == .idle || phase == .noEntity || phase == .loadingPreview else { return }
        self.franchiseId = franchiseId.uppercased()
        self.plate = arac.plaka
        self.fleetCarId = arac.wheelsysVehicleId
        let cid = WheelSysDebug.newCorrelationId()
        resolvedResNo = resNo.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .loadingPreview
        prefillFallback = prefill
        WheelSysDebug.log("ReturnCheckin", "resolve plate=\(plate) res=\(resolvedResNo)", cid: cid)

        if let prefill, prefill.rentalEntityId > 0 {
            WheelSysDebug.log(
                "ReturnCheckin",
                "using journal/stored rentalId=\(prefill.rentalEntityId) — skip RES resolve",
                cid: cid
            )
            await loadPreviewWithKnownEntity(
                franchiseId: franchiseId,
                entityId: String(prefill.rentalEntityId),
                resNo: prefill.resNo,
                arac: arac,
                fleetCarId: prefill.vehicleEntityId ?? arac.wheelsysVehicleId,
                prefill: prefill
            )
            return
        }

        do {
            let resolved = try await resolveEntityId(arac: arac, resNo: resolvedResNo, cid: cid)
            guard let resolved, !resolved.isEmpty else {
                if let prefill, prefill.rentalEntityId > 0 {
                    WheelSysDebug.log(
                        "ReturnCheckin",
                        "RES resolve empty — falling back to prefill rentalId=\(prefill.rentalEntityId)",
                        cid: cid
                    )
                    await loadPreviewWithKnownEntity(
                        franchiseId: franchiseId,
                        entityId: String(prefill.rentalEntityId),
                        resNo: resolvedResNo.isEmpty ? prefill.resNo : resolvedResNo,
                        arac: arac,
                        fleetCarId: prefill.vehicleEntityId,
                        prefill: prefill
                    )
                    return
                }
                phase = .noEntity
                WheelSysDebug.log("ReturnCheckin", "no entityId resolved", cid: cid)
                return
            }
            entityId = resolved
            applyPrefillFallbackIfNeeded(
                entityId: resolved,
                prefill: prefill,
                fleetVehicle: fleetVehicleForPlate(arac.plaka)
            )
            let loaded = try await Self.loadPreviewResilient(
                franchiseId: franchiseId,
                entityId: resolved,
                expectedResNo: nil,
                lockEntityId: true
            )
            assignPreview(loaded)
            if loaded.resNo.isEmpty == false {
                resolvedResNo = loaded.resNo
            }
            phase = .ready
            WheelSysDebug.log(
                "ReturnCheckin",
                "preview ready entityId=\(resolved) kmTo=\(loaded.mileageTo) fuelTo=\(loaded.fuelTo)",
                cid: cid
            )
        } catch {
            if let entityId, preview == nil, let prefill {
                assignPreview(Self.buildFallbackPreview(
                    from: prefill,
                    entityId: entityId,
                    fleetVehicle: fleetVehicleForPlate(arac.plaka)
                ))
            }
            if preview != nil {
                phase = .ready
                WheelSysDebug.warn(
                    "ReturnCheckin",
                    "preview degraded after RES resolve: \(error.localizedDescription)",
                    cid: cid
                )
            } else {
                phase = .failed(WheelSysUserFacingError.message(for: error))
                WheelSysDebug.error("ReturnCheckin", "preview failed: \(error.localizedDescription)", cid: cid)
            }
        }
    }

    private static func isTransientPreviewError(_ error: Error) -> Bool {
        WheelSysUserFacingError.isTransientServiceError(error.localizedDescription)
    }

    private static func loadPreviewResilient(
        franchiseId: String,
        entityId: String,
        expectedResNo: String?,
        lockEntityId: Bool = false,
        timeout: TimeInterval = previewLoadTimeout
    ) async throws -> WheelSysRentalPreview {
        let fid = franchiseId.uppercased()
        await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: fid)
        _ = await WheelSysVehicleDamageService.syncClientCookieToServerIfNeeded(franchiseId: fid)

        do {
            return try await loadPreviewWithTimeout(
                franchiseId: franchiseId,
                entityId: entityId,
                expectedResNo: expectedResNo,
                lockEntityId: lockEntityId,
                timeout: timeout
            )
        } catch {
            guard isTransientPreviewError(error) else { throw error }
            WheelSysDebug.warnCH(
                franchiseId: fid,
                "ReturnCheckin",
                "transient preview error — retrying once: \(error.localizedDescription)"
            )
            try await Task.sleep(nanoseconds: 800_000_000)
            await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: fid)
            _ = await WheelSysVehicleDamageService.syncClientCookieToServerIfNeeded(franchiseId: fid)
            return try await loadPreviewWithTimeout(
                franchiseId: franchiseId,
                entityId: entityId,
                expectedResNo: expectedResNo,
                lockEntityId: lockEntityId,
                timeout: timeout
            )
        }
    }

    private static func loadPreviewWithTimeout(
        franchiseId: String,
        entityId: String,
        expectedResNo: String?,
        lockEntityId: Bool = false,
        timeout: TimeInterval = previewLoadTimeout
    ) async throws -> WheelSysRentalPreview {
        try await withThrowingTaskGroup(of: WheelSysRentalPreview.self) { group in
            group.addTask {
                try await WheelSysCheckinService.loadPreview(
                    franchiseId: franchiseId,
                    entityId: entityId,
                    expectedResNo: expectedResNo,
                    lockEntityId: lockEntityId
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw WheelSysCheckinServiceError.operationFailed(
                    "wheelsys.return.preview_timeout".localized
                )
            }
            guard let result = try await group.next() else {
                throw WheelSysCheckinServiceError.operationFailed(
                    "wheelsys.return.preview_timeout".localized
                )
            }
            group.cancelAll()
            return result
        }
    }

    /// Reload preview after a note is saved (keeps notes list current).
    func reloadPreview() async {
        guard let entityId, !franchiseId.isEmpty else { return }
        let cid = WheelSysDebug.newCorrelationId()
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnCheckin",
            "reloadPreview entityId=\(entityId)",
            cid: cid
        )
        do {
            let loaded = try await Self.loadPreviewResilient(
                franchiseId: franchiseId,
                entityId: entityId,
                expectedResNo: previewExpectedResNo(),
                lockEntityId: previewLockEntityId()
            )
            assignPreview(loaded)
            if case .failed = phase {
                phase = .ready
            }
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "ReturnCheckin",
                "reloadPreview ok notes rental=\(loaded.rentalNotes.count) vehicle=\(loaded.vehicleNotes.count)",
                cid: cid
            )
        } catch {
            WheelSysDebug.errorCH(
                franchiseId: franchiseId,
                "ReturnCheckin",
                "preview reload failed: \(error.localizedDescription)",
                cid: cid
            )
        }
    }

    private func resolveEntityId(arac: Arac, resNo: String, cid: String) async throws -> String? {
        let resolved = await WheelSysCheckinService.resolveRentalEntityIdForVehicle(
            arac: arac,
            resNo: resNo,
            franchiseId: franchiseId
        )
        if let vid = resolved.vehicleId, !vid.isEmpty {
            fleetCarId = vid
        }
        if let id = resolved.entityId {
            WheelSysDebug.log("ReturnCheckin", "entityId resolved=\(id)", cid: cid)
            return id
        }
        WheelSysDebug.log("ReturnCheckin", "entityId not resolved plate=\(plate) res=\(resNo)", cid: cid)
        return nil
    }

    /// Re-resolve rental entityId from RES immediately before sync (fleet can drift).
    /// Skipped when pre-check-in locked the rental — RES search can return a booking entity.
    private func reResolveEntityFromRes(cid: String) async -> String? {
        if let locked = lockedRentalAfterPrecheckin {
            WheelSysDebug.log(
                "ReturnCheckin",
                "skipping searchByRes — locked rentalId=\(locked.rentalId)",
                cid: cid
            )
            return String(locked.rentalId)
        }
        if let prefill = prefillFallback, prefill.rentalEntityId > 0 {
            WheelSysDebug.log(
                "ReturnCheckin",
                "skipping searchByRes — known rentalId=\(prefill.rentalEntityId)",
                cid: cid
            )
            return String(prefill.rentalEntityId)
        }
        guard !resolvedResNo.isEmpty else { return entityId }
        do {
            let hits = try await WheelSysCheckinService.searchByRes(
                franchiseId: franchiseId,
                resQuery: resolvedResNo
            )
            if let id = await WheelSysCheckinService.pickBestRentalEntityIdFromResHits(
                franchiseId: franchiseId,
                hits: hits,
                expectedResNo: resolvedResNo,
                currentEntityId: entityId,
                cid: cid
            ) {
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
        userNote: String?,
        actualReturnDateTime: Date? = nil
    ) async -> Bool {
        let cid = WheelSysDebug.newCorrelationId()
        completionSyncPhase = .savingRental

        if let refreshedId = await effectiveEntityIdForSync(cid: cid) {
            entityId = refreshedId
        }
        guard let entityId else { return false }

        // Preview optional at completion — fetch inline when missing but entityId is known.
        var activePreview = preview
        if activePreview == nil {
            do {
                activePreview = try await Self.loadPreviewWithTimeout(
                    franchiseId: franchiseId,
                    entityId: entityId,
                    expectedResNo: previewExpectedResNo(),
                    lockEntityId: previewLockEntityId()
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

        let checkInUserId = WheelSysCheckinService.resolvedCheckInUserId(from: activePreview) ?? ""
        let trimmedUserNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingNote = (trimmedUserNote?.isEmpty == false) ? trimmedUserNote : nil

        let vehicleEntityHint = {
            let fromPreview = activePreview?.vehicleEntityId
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromPreview.isEmpty { return fromPreview }
            return lockedRentalAfterPrecheckin?.vehicleId?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()
        let resNoForSync = activePreview?.resNo.isEmpty == false ?
            activePreview!.resNo : resolvedResNo
        let plateForSync = activePreview?.plate.isEmpty == false ?
            activePreview!.plate : plate

        let actualReturn = actualReturnDateTime ?? WheelSysZurichDateTime.now()
        if let preview = activePreview {
            do {
                try WheelSysZurichDateTime.validateReturnNotBeforeCheckout(
                    checkoutDate: preview.dateFrom,
                    checkoutTime: preview.timeFrom,
                    plannedDate: preview.dateTo,
                    plannedTime: preview.timeTo,
                    actual: actualReturn
                )
            } catch {
                WheelSysDebug.error(
                    "ReturnCheckin",
                    "date validation blocked: \(error.localizedDescription)",
                    cid: cid
                )
                completionSyncPhase = .warning(WheelSysUserFacingError.message(for: error))
                return false
            }
        }

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
                fleetCarId: fleetCarId,
                actualCheckInDateTime: actualReturn,
                correlationId: cid
            )
            lastResult = result

            if pendingNote != nil {
                completionSyncPhase = .savingNotes
                WheelSysDebug.logCH(
                    franchiseId: franchiseId,
                    "ReturnCheckin",
                    "complete-sync notes phase rentalNoteLen=\(pendingNote?.count ?? 0)",
                    cid: cid
                )
            }

            if result.verificationPending {
                let msg = result.message.isEmpty ?
                    "wheelsys.return.verification_pending".localized : result.message
                completionSyncPhase = .warning(msg)
                WheelSysDebug.logCH(
                    franchiseId: franchiseId,
                    "ReturnCheckin",
                    "complete-sync saved; daily view verify pending",
                    cid: cid
                )
                return true
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
                WheelSysSessionPromptCenter.notifyIfSessionMessage(msg)
                completionSyncPhase = .warning(msg)
                WheelSysDebug.error("ReturnCheckin", "complete-sync reported failure: \(result.message)", cid: cid)
                return false
            }
        } catch {
            let msg = WheelSysUserFacingError.message(for: error)
            WheelSysSessionPromptCenter.notifyIfSessionMessage(msg)
            completionSyncPhase = .warning(msg)
            WheelSysDebug.error("ReturnCheckin", "complete-sync failed: \(error.localizedDescription)", cid: cid)
            return false
        }
    }

    func beginCompletionSync() {
        completionSyncPhase = .savingRental
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnCheckin",
            "beginCompletionSync entityId=\(entityId ?? "nil")"
        )
    }

    func resetCompletionSync() {
        completionSyncPhase = .idle
    }

    func reset() {
        phase = .idle
        completionSyncPhase = .idle
        preview = nil
        entityId = nil
        prefillFallback = nil
        lastResult = nil
        lockedRentalAfterPrecheckin = nil
    }
}
