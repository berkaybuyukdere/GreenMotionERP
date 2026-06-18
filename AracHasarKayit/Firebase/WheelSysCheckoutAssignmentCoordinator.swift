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
        guard let bookingEntityId else { return false }
        let cid = WheelSysDebug.newCorrelationId()
        completionSyncPhase = .validating
        WheelSysDebug.log(
            "CheckoutAssign",
            "entityId=\(bookingEntityId) plate=\(arac.plaka) km=\(km)",
            cid: cid
        )

        do {
            completionSyncPhase = .calculating
            let carId = try await resolveVehicleId(arac: arac, franchiseId: franchiseId)
            completionSyncPhase = .saving
            let result = try await WheelSysCheckinService.assignVehicleToBooking(
                franchiseId: franchiseId,
                bookingEntityId: bookingEntityId,
                carId: carId,
                plateNo: arac.plaka,
                carGroup: nil,
                checkOutMileage: km,
                checkOutFuel: fuel,
                resNo: resNo,
                firestoreCollection: firestoreDocId == nil ? nil : "exitIslemleri",
                firestoreDocId: firestoreDocId
            )
            lastMessage = result.message
            completionSyncPhase = .done
            WheelSysDebug.log("CheckoutAssign", "success booking=\(bookingEntityId)", cid: cid)
            return result.success
        } catch {
            completionSyncPhase = .warning(error.localizedDescription)
            WheelSysDebug.error("CheckoutAssign", "failed: \(error.localizedDescription)", cid: cid)
            return false
        }
    }

    private func resolveVehicleId(arac: Arac, franchiseId: String) async throws -> Int {
        if let stored = arac.wheelsysVehicleId, let id = Int(stored), id > 0 {
            return id
        }
        let fleet = try await WheelSysCheckinService.loadFleetChart(franchiseId: franchiseId)
        let norm = WheelSysPlateNormalizer.canonical(arac.plaka)
        if let vehicle = fleet.vehicles.first(where: {
            WheelSysPlateNormalizer.canonical($0.plate) == norm
        }), let id = Int(vehicle.vehicleId), id > 0 {
            return id
        }
        throw WheelSysCheckinServiceError.operationFailed(
            "WheelSys vehicle id not found for plate \(arac.plakaFormatli).".localized
        )
    }
}
