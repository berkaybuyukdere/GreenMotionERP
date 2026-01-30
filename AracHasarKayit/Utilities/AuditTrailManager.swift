import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Audit Log Model

struct AuditLog: Identifiable, Codable {
    var id = UUID()
    var timestamp: Date
    var userId: String
    var userName: String?
    var action: AuditAction
    var tableName: String
    var recordId: String
    var changes: [String: ChangeValue]
    var ipAddress: String?
    var deviceInfo: String?
    
    struct ChangeValue: Codable {
        let before: String?
        let after: String?
    }
}

enum AuditAction: String, Codable {
    case created = "CREATED"
    case updated = "UPDATED"
    case deleted = "DELETED"
    case accessed = "ACCESSED"
}

// MARK: - Audit Trail Manager

class AuditTrailManager {
    static let shared = AuditTrailManager()
    
    private let db = Firestore.firestore()
    
    // Demo user email (backward compatibility)
    private let demoUserEmail = "demo@gmail.com"
    
    // Check if current user is demo user
    private var isDemoUser: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        let email = user.email?.lowercased() ?? ""
        
        // Check email pattern: *_demo@* or demo_*@* or @demo.example.com
        if email.contains("_demo@") || email.hasPrefix("demo_") || email.hasSuffix("@demo.example.com") {
            return true
        }
        
        // Check old demo email (backward compatibility)
        if email == demoUserEmail {
            return true
        }
        
        return false
    }
    
    // Get collection reference - handles both production and demo (subcollection) collections
    private func getCollectionReference(_ baseName: String) -> CollectionReference {
        guard isDemoUser, let userId = Auth.auth().currentUser?.uid else {
            // Production: normal collection
            return db.collection(baseName)
        }
        
        // Old demo user (demo@gmail.com) uses demo_* prefix for backward compatibility
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return db.collection("demo_\(baseName)")
        }
        
        // New demo users: subcollection structure - demo_environments/{userId}/{baseName}
        return db.collection("demo_environments")
            .document(userId)
            .collection(baseName)
    }
    
    // Get collection name with demo prefix if needed (backward compatibility - use getCollectionReference instead)
    private func collectionName(_ baseName: String) -> String {
        // Old demo user (demo@gmail.com) uses demo_* prefix
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return "demo_\(baseName)"
        }
        // New demo users will use subcollection structure via getCollectionReference()
        return baseName
    }
    
    private init() {}
    
    // MARK: - Log Methods
    
    func logCreation(tableName: String, recordId: String, data: [String: Any]) {
        let changes = data.mapValues { AuditLog.ChangeValue(before: nil, after: "\($0)") }
        log(action: .created, tableName: tableName, recordId: recordId, changes: changes)
    }
    
    func logUpdate(tableName: String, recordId: String, oldData: [String: Any], newData: [String: Any]) {
        var changes: [String: AuditLog.ChangeValue] = [:]
        
        // Find differences
        for (key, newValue) in newData {
            let oldValue = oldData[key]
            if "\(oldValue ?? "")" != "\(newValue)" {
                changes[key] = AuditLog.ChangeValue(before: "\(oldValue ?? "")", after: "\(newValue)")
            }
        }
        
        if !changes.isEmpty {
            log(action: .updated, tableName: tableName, recordId: recordId, changes: changes)
        }
    }
    
    func logDeletion(tableName: String, recordId: String, data: [String: Any]) {
        let changes = data.mapValues { AuditLog.ChangeValue(before: "\($0)", after: nil) }
        log(action: .deleted, tableName: tableName, recordId: recordId, changes: changes)
    }
    
    func logAccess(tableName: String, recordId: String) {
        log(action: .accessed, tableName: tableName, recordId: recordId, changes: [:])
    }
    
    // MARK: - Private Methods
    
    private func log(action: AuditAction, tableName: String, recordId: String, changes: [String: AuditLog.ChangeValue]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let auditLog = AuditLog(
            timestamp: Date(),
            userId: userId,
            userName: getUserName(),
            action: action,
            tableName: tableName,
            recordId: recordId,
            changes: changes,
            deviceInfo: getDeviceInfo()
        )
        
        do {
            try self.getCollectionReference("audit_logs").document(auditLog.id.uuidString).setData(from: auditLog)
            print("✅ Audit log created: \(action.rawValue) on \(tableName)")
        } catch {
            print("❌ Failed to create audit log: \(error.localizedDescription)")
        }
    }
    
    private func getUserName() -> String? {
        return Auth.auth().currentUser?.displayName ?? Auth.auth().currentUser?.email
    }
    
    private func getDeviceInfo() -> String {
        let model = UIDevice.current.model
        let version = UIDevice.current.systemVersion
        return "\(model) iOS \(version)"
    }
    
    // MARK: - Query Methods
    
    func fetchLogs(for recordId: String, completion: @escaping ([AuditLog]) -> Void) {
        getCollectionReference("audit_logs")
            .whereField("recordId", isEqualTo: recordId)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                let logs = snapshot?.documents.compactMap { try? $0.data(as: AuditLog.self) } ?? []
                completion(logs)
            }
    }
}

