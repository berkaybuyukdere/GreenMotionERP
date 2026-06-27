import Foundation

/// High-level WheelSys NTR orchestration — create/close + Firestore persistence.
enum WheelSysNTRService {

    @MainActor
    static func createNTR(
        arac: Arac,
        request: WheelSysNTRCreateRequest,
        appUserName: String? = nil,
        localNotes: String? = nil,
        service: FirebaseService = .shared
    ) async -> Result<WheelSysNTRCreateResult, Error> {
        let fetcher = WheelSysNTRWebViewFetcher()
        defer { fetcher.cleanup() }

        do {
            let result = try await fetcher.createNonRevenueTicket(request)
            let history = WheelSysNTRHistoryEntry.opened(
                entityId: result.entityId,
                docNo: result.docNo,
                type: request.type,
                wheelsysUser: result.loggedInUser,
                appUserName: appUserName,
                km: request.vehicle.mileage,
                fuel: request.vehicle.fuelEighths,
                notes: localNotes
            )
            let record = WheelSysNTRLocalRecord(
                wheelsysNtrEntityId: result.entityId,
                wheelsysNtrDocNo: result.docNo,
                wheelsysNtrStatus: .active,
                wheelsysNtrSyncStatus: .success,
                wheelsysVehicleId: request.vehicle.wheelsysVehicleId,
                plateNo: request.vehicle.plateNo,
                createdByWheelsysUserId: result.loggedInUser.id,
                createdByWheelsysUserName: result.loggedInUser.name,
                startedAt: request.startDateTime,
                startKm: request.vehicle.mileage,
                startFuel: request.vehicle.fuelEighths,
                lastSyncError: nil,
                historyEntry: history
            )
            await persistNTRRecord(aracId: arac.id, record: record, service: service)
            broadcastChange()
            return .success(result)
        } catch {
            let detail = (error as? WheelSysNTRFetchError)?.errorDescription ?? error.localizedDescription
            LogManager.shared.error("[WheelSys][NTR][Create] failed: \(detail)", error: error)
            let failRecord = WheelSysNTRLocalRecord(
                wheelsysNtrSyncStatus: .failed,
                wheelsysVehicleId: request.vehicle.wheelsysVehicleId,
                plateNo: request.vehicle.plateNo,
                lastSyncError: error.localizedDescription
            )
            await persistNTRRecord(aracId: arac.id, record: failRecord, service: service)
            return .failure(error)
        }
    }

    @MainActor
    static func closeNTR(
        arac: Arac,
        request: WheelSysNTRCloseRequest,
        appUserName: String? = nil,
        localNotes: String? = nil,
        service: FirebaseService = .shared
    ) async -> Result<WheelSysNTRCloseResult, Error> {
        let fetcher = WheelSysNTRWebViewFetcher()
        defer { fetcher.cleanup() }

        do {
            let result = try await fetcher.closeNonRevenueTicket(request)
            let history = WheelSysNTRHistoryEntry.closed(
                entityId: request.ntrEntityId,
                docNo: arac.wheelsysNtrDocNo,
                wheelsysUser: result.loggedInUser,
                appUserName: appUserName,
                km: request.closeKm,
                fuel: request.closeFuelEighths,
                milesTravelled: result.milesTravelled,
                fuelUsed: result.fuelUsed,
                notes: localNotes
            )
            let record = WheelSysNTRLocalRecord(
                wheelsysNtrEntityId: request.ntrEntityId,
                wheelsysNtrStatus: .closed,
                wheelsysNtrSyncStatus: .success,
                closedByWheelsysUserId: result.loggedInUser.id,
                closedByWheelsysUserName: result.loggedInUser.name,
                closedAt: result.closeDateTime,
                closeKm: request.closeKm,
                closeFuel: request.closeFuelEighths,
                milesTravelled: result.milesTravelled,
                fuelUsed: result.fuelUsed,
                lastSyncError: nil,
                historyEntry: history,
                clearActiveState: true
            )
            await persistNTRRecord(aracId: arac.id, record: record, service: service)
            broadcastChange()
            return .success(result)
        } catch {
            let detail = (error as? WheelSysNTRFetchError)?.errorDescription ?? error.localizedDescription
            LogManager.shared.error("[WheelSys][NTR][Close] failed: \(detail)", error: error)
            let failRecord = WheelSysNTRLocalRecord(
                wheelsysNtrEntityId: request.ntrEntityId,
                wheelsysNtrSyncStatus: .pendingRetry,
                lastSyncError: error.localizedDescription
            )
            await persistNTRRecord(aracId: arac.id, record: failRecord, service: service)
            return .failure(error)
        }
    }

    /// Pre-flight checks before opening a new NTR on WheelSys.
    @MainActor
    static func createBlockReason(
        arac: Arac,
        fleetStore: WheelSysVehicleFleetStatusStore = .shared,
        hasOpenOutboundCheckout: Bool,
        openCheckoutResNo: String? = nil,
        hasOpenReturn: Bool
    ) -> WheelSysNTRCreateBlockReason? {
        let context = resolveContext(arac: arac, fleetStore: fleetStore)
        if context.isCloseMode {
            return .activeNTR(docNo: arac.wheelsysNtrDocNo)
        }
        if hasOpenReturn {
            return .openReturn
        }
        if hasOpenOutboundCheckout {
            return .openCheckout(resNo: openCheckoutResNo)
        }
        if fleetStore.isVehicleOnRental(arac) {
            let rentalId = fleetStore.fleetVehicle(for: arac)
                .flatMap { WheelSysCheckinService.resolveRentalEntityId(from: $0) }
            let hint = rentalId.map { "RNT-\($0)" }
            return .onRental(resHint: hint)
        }
        if let booking = fleetStore.activeBookingEvent(for: arac) {
            return .assignedBooking(docNo: booking.recordId)
        }
        if fleetStore.activeNonRevenueEvent(for: arac) != nil {
            return .activeNTR(docNo: fleetStore.activeNonRevenueEvent(for: arac)?.recordId)
        }
        return nil
    }

    /// Merge fleet-chart active NTR into Firestore when the app missed the open sync.
    @MainActor
    static func syncActiveNTRFromFleetIfNeeded(
        arac: Arac,
        fleetStore: WheelSysVehicleFleetStatusStore = .shared,
        service: FirebaseService = .shared
    ) async {
        guard arac.wheelsysNtrStatus != WheelSysNTRStatus.active.rawValue,
              let entityId = fleetStore.activeNonRevenueEntityId(for: arac),
              entityId > 0 else { return }

        if arac.wheelsysNtrStatus == WheelSysNTRStatus.closed.rawValue,
           arac.wheelsysNtrEntityId == entityId {
            return
        }
        if arac.wheelsysNtrHistory.contains(where: { $0.entityId == entityId && $0.action == .closed }) {
            return
        }

        let event = fleetStore.activeNonRevenueEvent(for: arac)
        let record = WheelSysNTRLocalRecord(
            wheelsysNtrEntityId: entityId,
            wheelsysNtrDocNo: event?.recordId,
            wheelsysNtrStatus: .active,
            wheelsysNtrSyncStatus: .success,
            plateNo: arac.plakaFormatli
        )
        await persistNTRRecord(aracId: arac.id, record: record, service: service)
        broadcastChange()
    }

    @MainActor
    static func resolveContext(
        arac: Arac,
        fleetStore: WheelSysVehicleFleetStatusStore = .shared
    ) -> WheelSysNTRResolvedContext {
        if arac.wheelsysNtrStatus == WheelSysNTRStatus.active.rawValue,
           let id = arac.wheelsysNtrEntityId, id > 0 {
            return WheelSysNTRResolvedContext(isCloseMode: true, entityId: id, entitySource: "firestore")
        }
        if let fleetId = fleetStore.activeNonRevenueEntityId(for: arac), fleetId > 0 {
            return WheelSysNTRResolvedContext(isCloseMode: true, entityId: fleetId, entitySource: "fleet")
        }
        return .create
    }

    static func buildVehiclePayload(
        arac: Arac,
        fleetVehicle: WheelSysFleetVehicle?
    ) -> WheelSysNTRVehiclePayload? {
        let plate = arac.plakaFormatli.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleId = (arac.wheelsysVehicleId ?? fleetVehicle?.vehicleId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plate.isEmpty, !vehicleId.isEmpty else { return nil }

        let mileage = fleetVehicle?.mileage ?? arac.lastCheckIn?.km ?? 0
        let fuel = arac.lastCheckIn?.fuelEighths ?? 8
        let group = fleetVehicle?.group ?? arac.kategori
        let model = fleetVehicle?.model ?? arac.model

        return WheelSysNTRVehiclePayload(
            plateNo: plate,
            wheelsysVehicleId: vehicleId,
            carGroup: group,
            modelName: model,
            modelId: nil,
            mileage: mileage,
            fuelEighths: fuel
        )
    }

    static func defaultCreateRequest(
        vehicle: WheelSysNTRVehiclePayload,
        type: WheelSysNTRType,
        station: String = "ZRH"
    ) -> WheelSysNTRCreateRequest {
        let now = WheelSysZurichDateTime.now()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WheelSysZurichDateTime.timeZone
        let plannedEnd = cal.date(byAdding: .day, value: 7, to: now) ?? now
        return WheelSysNTRCreateRequest(
            vehicle: vehicle,
            type: type,
            station: station,
            startDateTime: now,
            plannedEndDateTime: plannedEnd
        )
    }

    @MainActor
    private static func persistNTRRecord(
        aracId: UUID,
        record: WheelSysNTRLocalRecord,
        service: FirebaseService
    ) async {
        await withCheckedContinuation { cont in
            service.mergeWheelSysNTRFields(aracId: aracId, record: record) { error in
                if let error {
                    LogManager.shared.error("[WheelSys][NTR] Firestore merge failed", error: error)
                }
                cont.resume()
            }
        }
    }

    private static func broadcastChange() {
        NotificationCenter.default.post(name: .wheelSysNTRDidChange, object: nil)
        NotificationCenter.default.post(name: .wheelSysFleetStatusDidRefresh, object: nil)
    }
}
