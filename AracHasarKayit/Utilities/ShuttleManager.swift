import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Manages shuttle operations and daily sessions
class ShuttleManager: ObservableObject {
    static let shared = ShuttleManager()
    
    // MARK: - Published Properties
    @Published var currentSession: ShuttleSession?
    @Published var todayEntries: [ShuttleEntry] = []
    @Published var allSessions: [ShuttleSession] = []
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var sessionListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?
    
    // Use FirebaseService.shared for all collection access (handles demo routing + franchise filtering)
    private func getCollectionReference(_ baseName: String) -> CollectionReference {
        return FirebaseService.shared.getCollectionReference(baseName)
    }
    
    private func getFilteredQuery(_ baseName: String) -> Query {
        return FirebaseService.shared.getFilteredQuery(baseName)
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize session on app start
        initializeSession()
    }
    
    // MARK: - Session Initialization
    
    func initializeSession() {
        guard let user = Auth.auth().currentUser else { return }
        
        print("🔄 Initializing shuttle session for user: \(user.uid)")
        
        getFilteredQuery("shuttleSessions")
            .whereField("driverUID", isEqualTo: user.uid)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error loading active session: \(error)")
                    return
                }
                
                guard let doc = snapshot?.documents.first else {
                    print("ℹ️ No active session found")
                    return
                }
                
                do {
                    let session = try doc.data(as: ShuttleSession.self)
                    print("✅ Active session loaded: \(session.id ?? "unknown")")
                    
                    DispatchQueue.main.async {
                        self.currentSession = session
                        // Listen to entries
                        self.listenToTodayEntries()
                    }
                } catch {
                    print("❌ Error parsing session: \(error)")
                }
            }
    }
    
    
    // MARK: - Session Management
    
    func startDailySession() {
        // Check if current user is authenticated
        guard let user = Auth.auth().currentUser else {
            ToastManager.shared.show("❌ User not authenticated", type: .error)
            return
        }
        
        let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Driver"
        
        let session = ShuttleSession(
            date: Date(),
            driverName: driverName,
            driverUID: user.uid,
            entries: [],
            totalCustomers: 0,
            isActive: true,
            startTime: Date(),
            franchiseId: FirebaseService.shared.currentFranchiseId
        )
        
        let ref = getCollectionReference("shuttleSessions").document()
        var updatedSession = session
        updatedSession.id = ref.documentID
        
        try? ref.setData(from: session) { error in
            if let error = error {
                print("❌ Error creating shuttle session: \(error)")
                ToastManager.shared.show("❌ Error starting session: \(error.localizedDescription)", type: .error)
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.currentSession = updatedSession
            }
            
            
            // Update presence to online
            UserPresenceManager.shared.setOnline()
            
            self.listenToTodayEntries()
            
            // Send notification
            NotificationManager.shared.sendShuttleStartNotification(driverName: driverName)
            
            // Post notification for UI update
            NotificationCenter.default.post(name: NSNotification.Name("ShuttleSessionUpdated"), object: nil)
            
            print("✅ Shuttle session started: \(ref.documentID)")
        }
    }
    
    func endDailySession() async throws {
        guard var session = currentSession else { return }
        
        session.isActive = false
        session.endTime = Date()
        session.franchiseId = FirebaseService.shared.currentFranchiseId
        
        try getCollectionReference("shuttleSessions")
            .document(session.id ?? "")
            .setData(from: session)
        
        // Update presence to offline
        UserPresenceManager.shared.setOffline()
        
        // Send notification with total customers
        let driverName = session.driverName
        let totalCustomers = session.totalCustomers
        NotificationManager.shared.sendShuttleEndNotification(driverName: driverName, totalCustomers: totalCustomers)
        
        await MainActor.run {
            self.currentSession = nil
        }
        
        print("✅ Shuttle session ended")
    }
    
    // MARK: - Customer Entry
    
    func addCustomerEntry(customerCount: Int, entryType: ShuttleEntryType) async throws {
        guard let user = Auth.auth().currentUser,
              let session = currentSession else {
            throw NSError(domain: "ShuttleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
        }
        
        let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Driver"
        
        var entry = ShuttleEntry(
            customerCount: customerCount,
            entryType: entryType,
            timestamp: Date(),
            driverName: driverName,
            driverUID: user.uid,
            sessionId: session.id ?? ""
        )
        entry.franchiseId = FirebaseService.shared.currentFranchiseId
        
        // CRITICAL FIX: Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add entry to shuttleEntries collection
        let entryRef = getCollectionReference("shuttleEntries").document()
        try batch.setData(from: entry, forDocument: entryRef)
        
        // 2. Update session with new entry and increment total customers
        let sessionRef = getCollectionReference("shuttleSessions").document(session.id ?? "")
        
        // Convert entry to Firestore format
        let entryData: [String: Any] = [
            "customerCount": entry.customerCount,
            "entryType": entry.entryType.rawValue,
            "timestamp": Timestamp(date: entry.timestamp),
            "driverName": entry.driverName,
            "driverUID": entry.driverUID,
            "sessionId": entry.sessionId
        ]
        
        batch.updateData([
            "entries": FieldValue.arrayUnion([entryData]),
            "totalCustomers": FieldValue.increment(Int64(customerCount))
        ], forDocument: sessionRef)
        
        // Commit the batch transaction
        try await batch.commit()
        
        // Update current session locally
        DispatchQueue.main.async {
            var updatedEntries = self.currentSession?.entries ?? []
            updatedEntries.append(entry)
            self.currentSession?.entries = updatedEntries
            self.currentSession?.totalCustomers += customerCount
        }
        
        // Send notification
        NotificationManager.shared.sendShuttleCustomerNotification(driverName: driverName, customerCount: customerCount)
        
        // Log activity
        logActivity(entry: entry)
        
        print("✅ Customer entry added atomically: \(customerCount) customers")
    }
    
    // MARK: - Listeners
    
    func listenToTodayEntries() {
        guard let session = currentSession else { return }
        
        // Use entries from current session directly
        todayEntries = session.entries.sorted { $0.timestamp > $1.timestamp }
        
        // WORKAROUND: Use only session entries to avoid Firebase index requirement
        print("✅ Today entries loaded: \(todayEntries.count)")
    }
    
    func stopListening() {
        entriesListener?.remove()
    }
    
    // MARK: - Activity Logging
    
    private func logActivity(entry: ShuttleEntry) {
        var activity = Activity(
            tip: .shuttlePickup,
            aciklama: "Shuttle pickup: \(entry.customerCount) customers",
            tarih: entry.timestamp,
            aracPlaka: nil,
            kullaniciAdi: entry.driverName
        )
        activity.franchiseId = FirebaseService.shared.currentFranchiseId
        
        try? getCollectionReference("activities").addDocument(from: activity) { error in
            if let error = error {
                print("❌ Error logging activity: \(error)")
            }
        }
    }
    
    // MARK: - Report Generation
    
    func generateDailyReport(for session: ShuttleSession) async throws -> DailyShuttleReport {
        // Fetch all entries for this session
        let snapshot = try await getFilteredQuery("shuttleEntries")
            .whereField("sessionId", isEqualTo: session.id ?? "")
            .order(by: "timestamp")
            .getDocuments()
        
        let entries = snapshot.documents.compactMap { doc in
            try? doc.data(as: ShuttleEntry.self)
        }
        
        let report = DailyShuttleReport(
            date: session.date,
            driverName: session.driverName,
            totalCustomers: session.totalCustomers,
            totalTrips: entries.count,
            entries: entries,
            startTime: session.startTime,
            endTime: session.endTime ?? Date()
        )
        
        return report
    }
    
    // MARK: - Reset (for user change)
    
    func reset() {
        print("🔄 Resetting ShuttleManager data...")
        
        // Clear all published properties
        currentSession = nil
        todayEntries = []
        allSessions = []
        
        // Remove all listeners
        sessionListener?.remove()
        sessionListener = nil
        entriesListener?.remove()
        entriesListener = nil
        
        print("✅ ShuttleManager data reset complete")
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopListening()
    }
}

