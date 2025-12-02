import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages gamification system: points, leaderboard, and user statistics
class GamificationManager {
    static let shared = GamificationManager()
    
    private let db = Firestore.firestore()
    
    // Point values for each activity type (in priority order)
    enum ActivityType: Int, CaseIterable {
        case damageRecord = 1      // 100 points - Highest priority
        case returnOperation = 2   // 80 points
        case checkOut = 3          // 60 points
        case officeOperation = 4   // 40 points
        case vehicleRecord = 5     // 20 points - Lowest priority
        
        var points: Int {
            switch self {
            case .damageRecord: return 100
            case .returnOperation: return 80
            case .checkOut: return 60
            case .officeOperation: return 40
            case .vehicleRecord: return 20
            }
        }
        
        var displayName: String {
            switch self {
            case .damageRecord: return "Damage Record"
            case .returnOperation: return "Return Operation"
            case .checkOut: return "Check Out"
            case .officeOperation: return "Office Operation"
            case .vehicleRecord: return "Vehicle Record"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Award Points
    
    /// Award points to a specific user for completing an activity
    func awardPoints(for activityType: ActivityType, userId: String? = nil, completion: ((Bool, Int) -> Void)? = nil) {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let uid = targetUserId else {
            print("❌ Cannot award points: User not authenticated")
            completion?(false, 0)
            return
        }
        
        awardPointsToUser(uid: uid, activityType: activityType, completion: completion)
    }
    
    /// Award points to a specific user ID
    private func awardPointsToUser(uid: String, activityType: ActivityType, completion: ((Bool, Int) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ Cannot award points: User not authenticated")
            completion?(false, 0)
            return
        }
        
        let points = activityType.points
        
        // Update user's points and activity stats atomically
        let userRef = db.collection("users").document(uid)
        
        db.runTransaction { transaction, errorPointer in
            do {
                let userDoc = try transaction.getDocument(userRef)
                guard var userData = userDoc.data() else {
                    throw NSError(domain: "Gamification", code: -1, userInfo: [NSLocalizedDescriptionKey: "User document not found"])
                }
                
                // Get current values (with defaults for backward compatibility)
                let currentPoints = userData["totalPoints"] as? Int ?? 0
                var activityStats = userData["activityStats"] as? [String: Any] ?? [:]
                
                // Update points
                let newPoints = currentPoints + points
                userData["totalPoints"] = newPoints
                
                // Update activity stats
                switch activityType {
                case .damageRecord:
                    let current = activityStats["damageRecords"] as? Int ?? 0
                    activityStats["damageRecords"] = current + 1
                case .returnOperation:
                    let current = activityStats["returnOperations"] as? Int ?? 0
                    activityStats["returnOperations"] = current + 1
                case .checkOut:
                    let current = activityStats["checkOutOperations"] as? Int ?? 0
                    activityStats["checkOutOperations"] = current + 1
                case .officeOperation:
                    let current = activityStats["officeOperations"] as? Int ?? 0
                    activityStats["officeOperations"] = current + 1
                case .vehicleRecord:
                    let current = activityStats["vehicleRecords"] as? Int ?? 0
                    activityStats["vehicleRecords"] = current + 1
                }
                
                userData["activityStats"] = activityStats
                
                // Update document
                transaction.setData(userData, forDocument: userRef, merge: true)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        } completion: { result, error in
            if let error = error {
                print("❌ Error awarding points: \(error.localizedDescription)")
                completion?(false, 0)
            } else {
                print("✅ Awarded \(points) points for \(activityType.displayName)")
                completion?(true, points)
            }
        }
    }
    
    // MARK: - Revoke Points
    
    /// Revoke points from a user when an activity is deleted
    func revokePoints(for activityType: ActivityType, userId: String, completion: ((Bool, Int) -> Void)? = nil) {
        let points = activityType.points
        
        // Update user's points and activity stats atomically
        let userRef = db.collection("users").document(userId)
        
        db.runTransaction { transaction, errorPointer in
            do {
                let userDoc = try transaction.getDocument(userRef)
                guard var userData = userDoc.data() else {
                    throw NSError(domain: "Gamification", code: -1, userInfo: [NSLocalizedDescriptionKey: "User document not found"])
                }
                
                // Get current values (with defaults for backward compatibility)
                let currentPoints = userData["totalPoints"] as? Int ?? 0
                var activityStats = userData["activityStats"] as? [String: Any] ?? [:]
                
                // Update points (subtract)
                let newPoints = max(0, currentPoints - points) // Don't go below 0
                userData["totalPoints"] = newPoints
                
                // Update activity stats (decrement, but don't go below 0)
                switch activityType {
                case .damageRecord:
                    let current = max(0, (activityStats["damageRecords"] as? Int ?? 0) - 1)
                    activityStats["damageRecords"] = current
                case .returnOperation:
                    let current = max(0, (activityStats["returnOperations"] as? Int ?? 0) - 1)
                    activityStats["returnOperations"] = current
                case .checkOut:
                    let current = max(0, (activityStats["checkOutOperations"] as? Int ?? 0) - 1)
                    activityStats["checkOutOperations"] = current
                case .officeOperation:
                    let current = max(0, (activityStats["officeOperations"] as? Int ?? 0) - 1)
                    activityStats["officeOperations"] = current
                case .vehicleRecord:
                    let current = max(0, (activityStats["vehicleRecords"] as? Int ?? 0) - 1)
                    activityStats["vehicleRecords"] = current
                }
                
                userData["activityStats"] = activityStats
                
                // Update document
                transaction.setData(userData, forDocument: userRef, merge: true)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        } completion: { result, error in
            if let error = error {
                print("❌ Error revoking points: \(error.localizedDescription)")
                completion?(false, 0)
            } else {
                print("✅ Revoked \(points) points for \(activityType.displayName) from user \(userId)")
                completion?(true, points)
            }
        }
    }
    
    // MARK: - Leaderboard
    
    /// Get leaderboard with top users
    func getLeaderboard(limit: Int = 10, completion: @escaping ([LeaderboardEntry]?, Error?) -> Void) {
        db.collection("users")
            .order(by: "totalPoints", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching leaderboard: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                var entries: [LeaderboardEntry] = []
                var rank = 1
                
                for document in documents {
                    let data = document.data()
                    let uid = document.documentID
                    let firstName = data["firstName"] as? String ?? ""
                    let lastName = data["lastName"] as? String ?? ""
                    let totalPoints = data["totalPoints"] as? Int ?? 0
                    let activityStats = data["activityStats"] as? [String: Any] ?? [:]
                    
                    let entry = LeaderboardEntry(
                        uid: uid,
                        name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces),
                        totalPoints: totalPoints,
                        rank: rank,
                        activityStats: ActivityStats(
                            damageRecords: activityStats["damageRecords"] as? Int ?? 0,
                            returnOperations: activityStats["returnOperations"] as? Int ?? 0,
                            checkOutOperations: activityStats["checkOutOperations"] as? Int ?? 0,
                            officeOperations: activityStats["officeOperations"] as? Int ?? 0,
                            vehicleRecords: activityStats["vehicleRecords"] as? Int ?? 0
                        )
                    )
                    entries.append(entry)
                    rank += 1
                }
                
                completion(entries, nil)
            }
    }
    
    /// Get current user's rank in leaderboard
    func getCurrentUserRank(completion: @escaping (Int?, Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil, NSError(domain: "Gamification", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Get user's points first
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = snapshot?.data(),
                  let userPoints = data["totalPoints"] as? Int else {
                completion(nil, nil)
                return
            }
            
            // Count users with more points
            self.db.collection("users")
                .whereField("totalPoints", isGreaterThan: userPoints)
                .getDocuments { snapshot, error in
                    if let error = error {
                        completion(nil, error)
                        return
                    }
                    
                    let rank = (snapshot?.documents.count ?? 0) + 1
                    completion(rank, nil)
                }
        }
    }
    
    // MARK: - Admin Functions
    
    /// Reset all users' points and activity stats (Admin only)
    func resetAllPoints(completion: @escaping (Bool, Int, Error?) -> Void) {
        self.db.collection("users")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(false, 0, NSError(domain: "Gamification", code: -1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"]))
                    return
                }
                
                if let error = error {
                    print("❌ Error fetching users: \(error.localizedDescription)")
                    completion(false, 0, error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(false, 0, nil)
                    return
                }
                
                let batch = self.db.batch()
                var updateCount = 0
                
                for document in documents {
                    let userRef = self.db.collection("users").document(document.documentID)
                    batch.updateData([
                        "totalPoints": 0,
                        "activityStats": [
                            "damageRecords": 0,
                            "returnOperations": 0,
                            "checkOutOperations": 0,
                            "officeOperations": 0,
                            "vehicleRecords": 0
                        ]
                    ], forDocument: userRef)
                    updateCount += 1
                }
                
                // Commit batch update
                batch.commit { error in
                    if let error = error {
                        print("❌ Error resetting points: \(error.localizedDescription)")
                        completion(false, 0, error)
                    } else {
                        print("✅ Reset points for \(updateCount) users")
                        completion(true, updateCount, nil)
                    }
                }
            }
    }
    
    // MARK: - User Statistics
    
    /// Get current user's statistics
    func getCurrentUserStats(completion: @escaping (UserStats?, Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil, NSError(domain: "Gamification", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(nil, nil)
                return
            }
            
            let totalPoints = data["totalPoints"] as? Int ?? 0
            let activityStats = data["activityStats"] as? [String: Any] ?? [:]
            
            let stats = UserStats(
                totalPoints: totalPoints,
                activityStats: ActivityStats(
                    damageRecords: activityStats["damageRecords"] as? Int ?? 0,
                    returnOperations: activityStats["returnOperations"] as? Int ?? 0,
                    checkOutOperations: activityStats["checkOutOperations"] as? Int ?? 0,
                    officeOperations: activityStats["officeOperations"] as? Int ?? 0,
                    vehicleRecords: activityStats["vehicleRecords"] as? Int ?? 0
                )
            )
            
            completion(stats, nil)
        }
    }
}

// MARK: - Data Models

struct LeaderboardEntry: Identifiable {
    let id = UUID()
    let uid: String
    let name: String
    let totalPoints: Int
    let rank: Int
    let activityStats: ActivityStats
    
    var isCurrentUser: Bool {
        Auth.auth().currentUser?.uid == uid
    }
}

struct UserStats {
    let totalPoints: Int
    let activityStats: ActivityStats
    
    var totalActivities: Int {
        activityStats.totalActivities
    }
    
    var pointsPerActivity: Double {
        guard totalActivities > 0 else { return 0 }
        return Double(totalPoints) / Double(totalActivities)
    }
}

