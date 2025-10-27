import Foundation
import FirebaseFirestore
import FirebaseAuth

/// User presence status
enum PresenceStatus: String, Codable {
    case online = "Online"
    case offline = "Offline"
    case away = "Away"
    
    var color: String {
        switch self {
        case .online: return "green"
        case .offline: return "gray"
        case .away: return "orange"
        }
    }
}

/// User presence model
struct UserPresence: Identifiable, Codable {
    let id: String  // User ID
    var displayName: String
    var email: String
    var status: PresenceStatus
    var lastSeen: Date
    var isOnline: Bool {
        // Only consider online if status is online AND last seen within 5 minutes
        if status == .online {
            let timeSinceLastSeen = Date().timeIntervalSince(lastSeen)
            return timeSinceLastSeen <= 300 // 5 minutes
        }
        return false
    }
    
    var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
}

/// Manages user presence in the app
class UserPresenceManager: ObservableObject {
    static let shared = UserPresenceManager()
    
    @Published var onlineUsers: [UserPresence] = []
    @Published var offlineUsers: [UserPresence] = []
    @Published var onlineUserCount: Int = 0
    @Published var offlineUserCount: Int = 0
    @Published var isMonitoring = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var updateTimer: Timer?
    private var lastActivityTime = Date()
    
    private init() {
        setupAppStateObservers()
    }
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Listen to all user presence
        listener = db.collection("userPresence")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("âŒ Error monitoring presence: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                var allPresences: [UserPresence] = []
                
                for doc in documents {
                    do {
                        let presence = try doc.data(as: UserPresence.self)
                        allPresences.append(presence)
                    } catch {
                        print("❌ Error decoding presence: \(error)")
                    }
                }
                
                // Separate online and offline users based on actual activity
                let now = Date()
                let onlineUsers = allPresences.filter { presence in
                    // Only consider truly online if status is online AND last seen within 5 minutes
                    if presence.status == .online {
                        let timeSinceLastSeen = now.timeIntervalSince(presence.lastSeen)
                        return timeSinceLastSeen <= 300 // 5 minutes
                    }
                    return false
                }.sorted { $0.displayName < $1.displayName }
                
                let offlineUsers = allPresences.filter { presence in
                    // Consider offline if status is offline OR last seen more than 5 minutes ago
                    if presence.status == .offline {
                        return true
                    }
                    let timeSinceLastSeen = now.timeIntervalSince(presence.lastSeen)
                    return timeSinceLastSeen > 300 // More than 5 minutes
                }.sorted { $0.lastSeen > $1.lastSeen }
                
                DispatchQueue.main.async {
                    self.onlineUsers = onlineUsers
                    self.offlineUsers = offlineUsers
                    self.onlineUserCount = onlineUsers.count
                    self.offlineUserCount = offlineUsers.count
                    print("👥 Online users: \(onlineUsers.count), Offline: \(offlineUsers.count)")
                    
                    // Auto-update status for users who should be offline
                    self.autoUpdateStalePresences(allPresences: allPresences)
                }
            }
        
        // Start periodic update for current user
        startPeriodicUpdate()
    }
    
    func stopMonitoring() {
        listener?.remove()
        updateTimer?.invalidate()
        isMonitoring = false
    }
    
    // MARK: - Update Presence
    
    func updateUserPresence(status: PresenceStatus) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            print("❌ No authenticated user for presence update")
            return 
        }
        
        // Get user info from current user
        guard let currentUser = Auth.auth().currentUser else { 
            print("❌ No current user for presence update")
            return 
        }
        let email = currentUser.email ?? ""
        let displayName = currentUser.displayName ?? email.components(separatedBy: "@").first ?? "Unknown User"
        
        let presence = UserPresence(
            id: userId,
            displayName: displayName,
            email: email,
            status: status,
            lastSeen: Date()
        )
        
        db.collection("userPresence").document(userId).setData([
            "id": presence.id,
            "displayName": presence.displayName,
            "email": presence.email,
            "status": presence.status.rawValue,
            "lastSeen": Timestamp(date: presence.lastSeen)
        ], merge: true) { error in
            if let error = error {
                print("❌ Error updating presence: \(error)")
            } else {
                print("✓ Presence updated: \(status.rawValue)")
            }
        }
    }
    
    // MARK: - Set Online/Offline
    
    func setOnline() {
        updateUserPresence(status: .online)
    }
    
    func setOffline() {
        updateUserPresence(status: .offline)
    }
    
    func setAway() {
        updateUserPresence(status: .away)
    }
    
    func trackUserActivity() {
        lastActivityTime = Date()
        if UIApplication.shared.applicationState == .active {
            updateUserPresence(status: .online)
        }
    }
    
    // MARK: - Periodic Update
    
    private func startPeriodicUpdate() {
        // Update every 60 seconds to reduce Firebase load
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Check if user is still active (app in foreground)
                if UIApplication.shared.applicationState == .active {
                    // Check if user has been inactive for more than 5 minutes
                    let timeSinceLastActivity = Date().timeIntervalSince(self.lastActivityTime)
                    if timeSinceLastActivity > 300 { // 5 minutes
                        self.updateUserPresence(status: .away)
                    } else {
                        self.updateUserPresence(status: .online)
                    }
                } else {
                    self.updateUserPresence(status: .away)
                }
            }
        }
    }
    
    // MARK: - App State Observers
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastActivityTime = Date()
            self?.updateUserPresence(status: .online)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateUserPresence(status: .away)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateUserPresence(status: .offline)
        }
    }
    
    // MARK: - Auto Update Stale Presences
    
    private func autoUpdateStalePresences(allPresences: [UserPresence]) {
        let now = Date()
        
        for presence in allPresences {
            let timeSinceLastSeen = now.timeIntervalSince(presence.lastSeen)
            
            // If user is marked as online but last seen more than 5 minutes ago
            if presence.status == .online && timeSinceLastSeen > 300 {
                // Update their status to away
                updateUserPresenceStatus(userId: presence.id, status: .away)
            }
            // If user is marked as away but last seen more than 30 minutes ago
            else if presence.status == .away && timeSinceLastSeen > 1800 {
                // Update their status to offline
                updateUserPresenceStatus(userId: presence.id, status: .offline)
            }
        }
    }
    
    private func updateUserPresenceStatus(userId: String, status: PresenceStatus) {
        // Only update if it's not the current user (current user is handled by periodic update)
        guard userId != Auth.auth().currentUser?.uid else { return }
        
        db.collection("userPresence").document(userId).updateData([
            "status": status.rawValue,
            "lastSeen": Timestamp(date: Date())
        ]) { error in
            if let error = error {
                print("❌ Error updating stale presence: \(error)")
            } else {
                print("✅ Updated stale presence for user \(userId) to \(status.rawValue)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
}
