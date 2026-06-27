import Foundation

/// Post-save refresh and client-side DailyView Available verification.
enum WheelSysReturnSyncManager {

    private static var refreshTasks: [String: Task<WheelSysReturnVerificationResult, Never>] = [:]

    static func refreshAfterReturnSave(
        franchiseId: String,
        selectedDate: String,
        station: String = "ZRH",
        rentalId: Int,
        vehicleId: String?,
        plate: String,
        expectedMileage: Int,
        expectedFuel: Int,
        onJournalReload: (() async -> Void)? = nil
    ) async -> WheelSysReturnVerificationResult {
        guard FranchiseCapabilityMatrix.wheelSysEnabledForActiveFranchise(franchiseId) else {
            return WheelSysReturnVerificationResult(
                verified: false, attempts: 0, mileage: nil, fuel: nil, pending: true
            )
        }

        let key = "return-\(rentalId)-\(expectedMileage)-\(expectedFuel)"
        if let existing = refreshTasks[key] {
            return await existing.value
        }

        let task = Task {
            defer { refreshTasks[key] = nil }

            if let onJournalReload {
                await onJournalReload()
            }

            var last = WheelSysReturnVerificationResult(
                verified: false, attempts: 0, mileage: nil, fuel: nil, pending: true
            )
            let backoffMs: [UInt64] = [400, 700, 900, 1200, 1500]

            for (index, delay) in backoffMs.enumerated() {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }

                do {
                    let verify = try await WheelSysDailyViewService.verifyVehicleAvailableMileage(
                        franchiseId: franchiseId,
                        selectedDate: selectedDate,
                        station: station,
                        vehicleEntityId: vehicleId,
                        plate: plate,
                        expectedMileage: expectedMileage,
                        expectedFuel: expectedFuel
                    )
                    last = WheelSysReturnVerificationResult(
                        verified: verify.verified,
                        attempts: index + 1,
                        mileage: verify.mileage,
                        fuel: verify.fuel,
                        pending: !verify.verified
                    )
                    if verify.verified { return last }
                } catch {
                    WheelSysDebug.error(
                        "ReturnSync",
                        "daily view verify attempt \(index + 1) failed: \(error.localizedDescription)"
                    )
                }
            }

            return last
        }

        refreshTasks[key] = task
        return await task.value
    }
}
