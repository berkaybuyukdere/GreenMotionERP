import Foundation
import FirebaseFirestore
import Network

/// Network reachability + hooks for Firestore pending writes and offline media upload queue.
final class OfflineModeManager: ObservableObject {
    static let shared = OfflineModeManager()

    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var pendingChanges = 0

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "OfflineModeMonitor")

    private init() {
        setupNetworkMonitoring()
    }

    func syncPendingMediaJobCount(_ count: Int) {
        pendingChanges = count
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self?.syncPendingChanges()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func syncPendingChanges() {
        isSyncing = true
        OfflineMediaSyncCoordinator.shared.processQueueIfNeeded()
        Firestore.firestore().waitForPendingWrites { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSyncing = false
            }
        }
    }

    func clearCache() {
        Firestore.firestore().clearPersistence { error in
            if let error = error {
                print("❌ Failed to clear cache: \(error.localizedDescription)")
            } else {
                print("✅ Cache cleared")
            }
        }
    }
}
