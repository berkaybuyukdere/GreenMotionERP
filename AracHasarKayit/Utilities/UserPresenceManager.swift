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
        status == .online
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
    @Published var isMonitoring = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var updateTimer: Timer?
    
    private init() {}
    
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
                        var presence = try doc.data(as: UserPresence.self)
                        allPresences.append(presence)
                    } catch {
                        print("âŒ Error decoding presence: \(error)")
                    }
                }
                
                // Separate online and offline users
                let onlineUsers = allPresences.filter { $0.isOnline }.sorted { $0.displayName < $1.displayName }
                let offlineUsers = allPresences.filter { !$0.isOnline }.sorted { $0.lastSeen > $1.lastSeen }
                
                DispatchQueue.main.async {
                    self.onlineUsers = onlineUsers
                    self.offlineUsers = offlineUsers
                    print("👥 Online users: \(onlineUsers.count), Offline: \(offlineUsers.count)")
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
        
        do {
            try db.collection("userPresence").document(userId).setData([
                "id": presence.id,
                "displayName": presence.displayName,
                "email": presence.email,
                "status": presence.status.rawValue,
                "lastSeen": Timestamp(date: presence.lastSeen)
            ], merge: true)
            print("âœ… Presence updated: \(status.rawValue)")
        } catch {
            print("âŒ Error updating presence: \(error)")
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
    
    // MARK: - Periodic Update
    
    private func startPeriodicUpdate() {
        // Update every 30 seconds to keep presence fresh
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateUserPresence(status: .online)
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}
