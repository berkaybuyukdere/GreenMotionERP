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
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var updateTimer: Timer?
    
    private init() {}
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        // Listen to all user presence
        listener = db.collection("userPresence")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error monitoring presence: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                var allPresences: [UserPresence] = []
                
                for doc in documents {
                    do {
                        var presence = try doc.data(as: UserPresence.self)
                        allPresences.append(presence)
                    } catch {
                        print("❌ Error decoding presence: \(error)")
                    }
                }
                
                // Separate online and offline users
                self.onlineUsers = allPresences.filter { $0.isOnline }.sorted { $0.displayName < $1.displayName }
                self.offlineUsers = allPresences.filter { !$0.isOnline }.sorted { $0.lastSeen > $1.lastSeen }
                
                print("👥 Online users: \(self.onlineUsers.count), Offline: \(self.offlineUsers.count)")
            }
        
        // Start periodic update for current user
        startPeriodicUpdate()
    }
    
    func stopMonitoring() {
        listener?.remove()
        updateTimer?.invalidate()
    }
    
    // MARK: - Update Presence
    
    func updateUserPresence(status: PresenceStatus) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Get user info from current user
        guard let currentUser = Auth.auth().currentUser else { return }
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
            try db.collection("userPresence").document(userId).setData(from: presence)
            print("✅ Presence updated: \(status.rawValue)")
        } catch {
            print("❌ Error updating presence: \(error)")
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
            self?.updateUserPresence(status: .online)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}

