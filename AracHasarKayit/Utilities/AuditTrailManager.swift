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
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
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
            deviceInfo: getDeviceInfo(),
            franchiseId: FirebaseService.shared.currentFranchiseId
        )
        
        do {
            try FirebaseService.shared.getCollectionReference("audit_logs").document(auditLog.id.uuidString).setData(from: auditLog)
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
        FirebaseService.shared.getFilteredQuery("audit_logs")
            .whereField("recordId", isEqualTo: recordId)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                let logs = snapshot?.documents.compactMap { try? $0.data(as: AuditLog.self) } ?? []
                completion(logs)
            }
    }
}

