import Foundation

/// Serializes traffic-contract Firestore writes from the UI (double taps, overlapping sheets).
actor TrafficContractSaveActor {
    static let shared = TrafficContractSaveActor()

    private var last: Task<Void, Never>?

    func enqueueMain(_ block: @MainActor @escaping () -> Void) async {
        let previous = last
        let work = Task {
            await previous?.value
            await MainActor.run { block() }
        }
        last = Task {
            await work.value
        }
        await work.value
    }
}
