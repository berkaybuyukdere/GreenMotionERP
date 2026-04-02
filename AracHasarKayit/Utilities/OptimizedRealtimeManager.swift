import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Optimized real-time updates manager with debouncing and batching
/// Reduces unnecessary network calls and UI updates
class OptimizedRealtimeManager: ObservableObject {
    static let shared = OptimizedRealtimeManager()
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    private var debounceTimers: [String: Timer] = [:]
    private let lock = NSLock()
    
    // Debounce delay (milliseconds)
    private let debounceDelay: TimeInterval = 0.3
    
    // Batch update queue
    private var pendingUpdates: [String: [Any]] = [:]
    
    // Use FirebaseService.shared for all collection access (handles demo routing + franchise filtering)
    private func getCollectionReference(_ baseName: String) -> CollectionReference {
        return FirebaseService.shared.getCollectionReference(baseName)
    }
    
    private init() {
        print("✅ OptimizedRealtimeManager initialized")
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Araclar (Vehicles) Listener
    
    func observeAraclar(completion: @escaping ([Arac]) -> Void) {
        let listenerKey = "araclar"
        
        // Remove existing listener if any
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getFilteredQuery("araclar")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Araclar listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                // Debounce updates to prevent rapid successive calls
                self.debounceUpdate(for: listenerKey) {
                    // Return all vehicles (including soft-deleted); callers decide what to filter.
                    let araclar = documents.compactMap { doc -> Arac? in
                        try? doc.data(as: Arac.self)
                    }

                    print("✅ Araclar updated: \(araclar.count) items (all, incl. soft-deleted)")
                    completion(araclar)
                }
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - İade İşlemleri Listener
    
    func observeIadeIslemleri(completion: @escaping ([IadeIslemi]) -> Void) {
        let listenerKey = "iadeIslemleri"
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getFilteredQuery("iadeIslemleri")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ İade listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                self.debounceUpdate(for: listenerKey) {
                    let iadeler = documents.compactMap { doc -> IadeIslemi? in
                        try? doc.data(as: IadeIslemi.self)
                    }
                    
                    print("✅ İade işlemleri updated: \(iadeler.count) items")
                    completion(iadeler)
                }
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - Office Operations Listener
    
    func observeOfficeOperations(completion: @escaping ([OfficeOperation]) -> Void) {
        let listenerKey = "officeOperations"
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getFilteredQuery("office_operations")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Office operations listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                self.debounceUpdate(for: listenerKey) {
                    do {
                        let operations = try documents.compactMap { doc -> OfficeOperation? in
                            let data = try JSONSerialization.data(withJSONObject: doc.data())
                            return try JSONDecoder().decode(OfficeOperation.self, from: data)
                        }
                        
                        print("✅ Office operations updated: \(operations.count) items")
                        completion(operations)
                    } catch {
                        print("❌ Office operations decode error: \(error)")
                        completion([])
                    }
                }
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - Activities Listener (with limit)
    
    func observeActivities(limit: Int = 100, completion: @escaping ([Activity]) -> Void) {
        let listenerKey = "activities"
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getFilteredQuery("activities")
            .order(by: "tarih", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Activities listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                self.debounceUpdate(for: listenerKey) {
                    let activities = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    print("✅ Activities updated: \(activities.count) items")
                    completion(activities)
                }
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - Servis Firmaları Listener
    
    func observeServisFirmalari(completion: @escaping ([ServisFirma]) -> Void) {
        let listenerKey = "servisFirmalari"
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getFilteredQuery("servisFirmalari")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Servis firmaları listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                self.debounceUpdate(for: listenerKey) {
                    let firmalar = documents.compactMap { doc -> ServisFirma? in
                        try? doc.data(as: ServisFirma.self)
                    }
                    
                    print("✅ Servis firmaları updated: \(firmalar.count) items")
                    completion(firmalar)
                }
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - Specific Vehicle Listener
    
    func observeVehicle(id: UUID, completion: @escaping (Arac?) -> Void) {
        let listenerKey = "vehicle_\(id.uuidString)"
        removeListener(for: listenerKey)
        
        let listener = FirebaseService.shared.getCollectionReference("araclar")
            .document(id.uuidString)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Vehicle listener error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let document = snapshot else {
                    completion(nil)
                    return
                }
                
                let arac = try? document.data(as: Arac.self)
                completion(arac)
            }
        
        storeListener(listener, for: listenerKey)
    }
    
    // MARK: - Listener Management
    
    func removeListener(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel debounce timer
        debounceTimers[key]?.invalidate()
        debounceTimers.removeValue(forKey: key)
        
        // Remove Firestore listener
        listeners[key]?.remove()
        listeners.removeValue(forKey: key)
        
        print("🗑️ Listener removed: \(key)")
    }
    
    func removeAllListeners() {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel all timers
        debounceTimers.values.forEach { $0.invalidate() }
        debounceTimers.removeAll()
        
        // Remove all listeners
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        
        print("🗑️ All listeners removed")
    }
    
    func pauseAllListeners() {
        removeAllListeners()
        print("⏸️ All listeners paused")
    }
    
    func getActiveListenersCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return listeners.count
    }
    
    // MARK: - Private Methods
    
    private func storeListener(_ listener: ListenerRegistration, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        listeners[key] = listener
    }
    
    private func debounceUpdate(for key: String, action: @escaping () -> Void) {
        lock.lock()
        
        // Cancel existing timer
        debounceTimers[key]?.invalidate()
        
        // Create new timer
        let timer = Timer.scheduledTimer(
            withTimeInterval: debounceDelay,
            repeats: false
        ) { _ in
            DispatchQueue.main.async {
                action()
            }
        }
        
        debounceTimers[key] = timer
        lock.unlock()
    }
}

// MARK: - Batch Operations Support

extension OptimizedRealtimeManager {
    /// Batch write operations for better performance
    func batchWrite(operations: [(collection: String, documentId: String, data: [String: Any])], completion: @escaping (Error?) -> Void) {
        let batch = db.batch()
        
        for operation in operations {
            let docRef = FirebaseService.shared.getCollectionReference(operation.collection).document(operation.documentId)
            batch.setData(operation.data, forDocument: docRef)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ Batch write failed: \(error.localizedDescription)")
            } else {
                print("✅ Batch write successful: \(operations.count) operations")
            }
            completion(error)
        }
    }
    
    /// Batch delete operations
    func batchDelete(references: [(collection: String, documentId: String)], completion: @escaping (Error?) -> Void) {
        let batch = db.batch()
        
        for reference in references {
            let docRef = FirebaseService.shared.getCollectionReference(reference.collection).document(reference.documentId)
            batch.deleteDocument(docRef)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ Batch delete failed: \(error.localizedDescription)")
            } else {
                print("✅ Batch delete successful: \(references.count) operations")
            }
            completion(error)
        }
    }
}

// MARK: - Connection State Monitor (Firestore)

extension OptimizedRealtimeManager {
    /// Monitor Firestore connection state
    /// Note: Firestore doesn't have a direct connection state API like Realtime Database
    /// This is a simplified version that checks if listeners are active
    func isConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !listeners.isEmpty
    }
    
    /// Get connection info
    func getConnectionInfo() -> String {
        let count = getActiveListenersCount()
        return count > 0 ? "🟢 Connected (\(count) listeners)" : "🔴 No active listeners"
    }
}

