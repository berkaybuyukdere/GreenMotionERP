import Foundation
import FirebaseFirestore
import Network

/// Offline mode manager with sync capabilities
class OfflineModeManager: ObservableObject {
    static let shared = OfflineModeManager()
    
    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var pendingChanges = 0
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "OfflineModeMonitor")
    
    private init() {
        setupFirestoreOffline()
        setupNetworkMonitoring()
    }
    
    private func setupFirestoreOffline() {
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = 100 * 1024 * 1024 // 100MB cache
        Firestore.firestore().settings = settings
        
        print("✅ Offline persistence enabled (100MB cache)")
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                print(path.status == .satisfied ? "🟢 ONLINE" : "🔴 OFFLINE")
                
                if path.status == .satisfied {
                    self?.syncPendingChanges()
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    private func syncPendingChanges() {
        isSyncing = true
        
        // Firestore automatically syncs pending writes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isSyncing = false
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

