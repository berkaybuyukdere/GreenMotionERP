import Foundation

/// Centralized rental.aspx return / check-in operations (no UI).
enum WheelSysRentalService {

    static func loadRentalPreview(
        franchiseId: String,
        rentalId: Int,
        expectedResNo: String? = nil
    ) async throws -> WheelSysRentalPreview {
        try await WheelSysCheckinService.loadPreview(
            franchiseId: franchiseId,
            entityId: String(rentalId),
            expectedResNo: expectedResNo
        )
    }

    /// Update check-in mileage and fuel via rental.aspx BTSAVE (full form preserved server-side).
    static func updateReturnMileageAndFuel(
        _ request: WheelSysReturnUpdateRequest
    ) async throws -> WheelSysReturnSaveResult {
        guard request.checkInMileage > 0 else {
            throw WheelSysCheckinServiceError.operationFailed(
                "Check-in mileage must be greater than zero.".localized
            )
        }
        guard (0...8).contains(request.checkInFuel) else {
            throw WheelSysCheckinServiceError.operationFailed(
                "Fuel must be between 0 and 8.".localized
            )
        }

        let result = try await WheelSysCheckinService.submitCheckinUpdate(
            franchiseId: request.franchiseId,
            entityId: String(request.rentalEntityId),
            resNo: request.resNo,
            plate: request.plate,
            checkInMileage: request.checkInMileage,
            checkInFuel: request.checkInFuel,
            checkInUserId: request.checkInUserId,
            addAutoNotes: request.addAutoNotes,
            vehicleEntityIdHint: request.vehicleEntityIdHint,
            fleetCarId: request.fleetCarId,
            entryPoint: request.entryPoint.rawValue,
            skipVehicleMasterSync: true,
            verifyDailyViewAvailable: true,
            station: request.station,
            actualCheckInDateTime: request.actualCheckInDateTime
        )

        return WheelSysReturnSaveResult(
            success: result.success,
            message: result.message,
            mileageFrom: result.mileageFrom,
            mileageTo: result.mileageTo,
            milesDriven: result.milesDriven,
            fuelTo: result.fuelTo,
            verifiedMileageTo: result.verifiedMileageTo,
            vehicleEntityId: result.vehicleEntityId,
            dailyViewAvailableVerified: result.dailyViewAvailableVerified,
            verificationPending: result.verificationPending,
            verificationAttempts: result.verificationAttempts,
            entryPoint: request.entryPoint
        )
    }
}
