import Foundation

/// Pushes a small JSON snapshot to the App Group for the home screen widget.
enum FleetWidgetSnapshotWriter {
    static func publish(
        iadeIslemleri: [IadeIslemi],
        exitIslemleri: [ExitIslemi],
        damageRecords: [HasarKaydi],
        operationsTabAvailable: Bool
    ) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }

        let returnsToday = iadeIslemleri.filter { !$0.isDeleted && $0.createdAt >= today && $0.createdAt < tomorrow }.count
        let checkoutsToday = exitIslemleri.filter { $0.createdAt >= today && $0.createdAt < tomorrow }.count
        let damagesToday = damageRecords.filter { $0.tarih >= today && $0.tarih < tomorrow }.count

        let pendingReturns = iadeIslemleri.filter { !$0.isDeleted && $0.status == .inProgress }.count

        let snap = FleetWidgetSnapshot(
            updatedAt: Date(),
            returnsTodayCount: returnsToday,
            checkoutsTodayCount: checkoutsToday,
            damagesTodayCount: damagesToday,
            pendingReturnsCount: pendingReturns,
            operationsTabAvailable: operationsTabAvailable
        )
        snap.saveToSharedDefaults()
    }
}
