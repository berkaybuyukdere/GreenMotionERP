import Foundation

/// Assigns the current vehicle to a WheelSys booking during checkout completion.
@MainActor
final class WheelSysCheckoutAssignmentCoordinator: ObservableObject {
    enum CompletionSyncPhase: Equatable {
        case idle
        case validating
        case calculating
        case saving
        case done
        case warning(String)
    }

    @Published var completionSyncPhase: CompletionSyncPhase = .idle
    @Published var bookingEntityId: Int?
    @Published var lastMessage: String = ""

    var completionMicrocopy: String {
        switch completionSyncPhase {
        case .idle:
            return "wheelsys.checkout.syncing_micro".localized
        case .validating:
            return "wheelsys.checkout.sync.validating".localized
        case .calculating:
            return "wheelsys.checkout.sync.calculating".localized
        case .saving:
            return "wheelsys.checkout.sync.saving".localized
        case .done:
            return "wheelsys.checkout.success".localized
        case .warning(let msg):
            return msg.isEmpty ? "wheelsys.checkout.failed".localized : msg
        }
    }

    func beginCompletionSync() {
        completionSyncPhase = .validating
    }

    func resetCompletionSync() {
        completionSyncPhase = .idle
    }

    func bindBooking(entityId: Int) {
        bookingEntityId = entityId
    }

    /// Non-blocking: returns false on failure; checkout may still complete in Firebase.
    @discardableResult
    func submitAssignmentOnComplete(
        arac: Arac,
        franchiseId: String,
        km: Int,
        fuel: Int,
        resNo: String,
        firestoreDocId: String?
    ) async -> Bool {
        guard let bookingEntityId else {
            WheelSysDebug.log("CheckoutAssign", "skipped — no bookingEntityId bound")
            return false
        }
        let cid = WheelSysDebug.newCorrelationId()
        completionSyncPhase = .validating
        WheelSysDebug.log(
            "CheckoutAssign",
            "complete-sync start entityId=\(bookingEntityId) plate=\(arac.plaka) km=\(km) fuel=\(fuel) res=\(resNo) firestoreDoc=\(firestoreDocId ?? "nil")",
            cid: cid
        )

        do {
            completionSyncPhase = .calculating
            WheelSysDebug.log("CheckoutAssign", "resolving vehicleId for plate=\(arac.plaka)", cid: cid)
            let carId = try await resolveVehicleId(arac: arac, franchiseId: franchiseId, cid: cid)
            completionSyncPhase = .saving
            WheelSysDebug.log(
                "CheckoutAssign",
                "assignVehicleToBooking carId=\(carId) booking=\(bookingEntityId)",
                cid: cid
            )
            let result = try await WheelSysCheckinService.assignVehicleToBooking(
                franchiseId: franchiseId,
                bookingEntityId: bookingEntityId,
                carId: carId,
                plateNo: arac.plaka,
                carGroup: nil,
                checkOutMileage: km,
                checkOutFuel: fuel,
                resNo: resNo,
                correlationId: cid,
                firestoreCollection: firestoreDocId == nil ? nil : "exitIslemleri",
                firestoreDocId: firestoreDocId
            )
            lastMessage = result.message
            if result.success {
                completionSyncPhase = .done
                WheelSysDebug.log(
                    "CheckoutAssign",
                    "success booking=\(bookingEntityId) carId=\(result.carId.map(String.init) ?? "nil") plate=\(result.plateNo ?? arac.plaka)",
                    cid: cid
                )
            } else {
                completionSyncPhase = .warning(result.message)
                WheelSysDebug.error(
                    "CheckoutAssign",
                    "reported failure: \(result.message)",
                    cid: cid
                )
            }
            return result.success
        } catch {
            completionSyncPhase = .warning(error.localizedDescription)
            WheelSysDebug.error("CheckoutAssign", "failed: \(error.localizedDescription)", cid: cid)
            return false
        }
    }

    private func resolveVehicleId(arac: Arac, franchiseId: String, cid: String) async throws -> Int {
        if let stored = arac.wheelsysVehicleId, let id = Int(stored), id > 0 {
            WheelSysDebug.log("CheckoutAssign", "vehicleId from arac.wheelsysVehicleId=\(id)", cid: cid)
            return id
        }
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        if let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)
            ?? WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka),
           let id = Int(fleetVehicle.vehicleId), id > 0 {
            WheelSysDebug.log(
                "CheckoutAssign",
                "vehicleId from fleet store=\(id) plate=\(arac.plakaFormatli)",
                cid: cid
            )
            return id
        }
        WheelSysDebug.log("CheckoutAssign", "vehicleId not stored — loading fleet chart", cid: cid)
        let fleet = try await WheelSysCheckinService.loadFleetChart(franchiseId: franchiseId)
        let norm = WheelSysPlateNormalizer.canonical(arac.plaka)
        if let vehicle = fleet.vehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plate) == norm
        }), let id = Int(vehicle.vehicleId), id > 0 {
            WheelSysDebug.log(
                "CheckoutAssign",
                "vehicleId from fleet plate match=\(id) fleetVehicles=\(fleet.vehiclesCount)",
                cid: cid
            )
            return id
        }
        WheelSysDebug.error(
            "CheckoutAssign",
            "vehicleId not found plate=\(arac.plakaFormatli) fleetVehicles=\(fleet.vehiclesCount)",
            cid: cid
        )
        throw WheelSysCheckinServiceError.operationFailed(
            "WheelSys vehicle id not found for plate \(arac.plakaFormatli).".localized
        )
    }
}
