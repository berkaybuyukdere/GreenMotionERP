import Foundation

/// Manages draft saves for unsaved changes
class DraftManager {
    static let shared = DraftManager()
    
    private let userDefaults = UserDefaults.standard
    private let draftKeyPrefix = "draft_"
    
    private init() {}
    
    // MARK: - Save Draft
    
    /// Saves a draft for damage record
    func saveDamageDraft(for vehicleId: UUID, draft: DamageDraft) {
        let key = draftKeyPrefix + "damage_" + vehicleId.uuidString
        if let encoded = try? JSONEncoder().encode(draft) {
            userDefaults.set(encoded, forKey: key)
            print("💾 Draft saved for vehicle: \(vehicleId)")
        }
    }
    
    /// Saves a draft for return record
    func saveReturnDraft(for vehicleId: UUID, draft: ReturnDraft) {
        let key = draftKeyPrefix + "return_" + vehicleId.uuidString
        if let encoded = try? JSONEncoder().encode(draft) {
            userDefaults.set(encoded, forKey: key)
            print("💾 Draft saved for vehicle: \(vehicleId)")
        }
    }
    
    // MARK: - Load Draft
    
    /// Loads damage draft for a vehicle
    func loadDamageDraft(for vehicleId: UUID) -> DamageDraft? {
        let key = draftKeyPrefix + "damage_" + vehicleId.uuidString
        if let data = userDefaults.data(forKey: key),
           let draft = try? JSONDecoder().decode(DamageDraft.self, from: data) {
            print("📂 Draft loaded for vehicle: \(vehicleId)")
            return draft
        }
        return nil
    }
    
    /// Loads return draft for a vehicle
    func loadReturnDraft(for vehicleId: UUID) -> ReturnDraft? {
        let key = draftKeyPrefix + "return_" + vehicleId.uuidString
        if let data = userDefaults.data(forKey: key),
           let draft = try? JSONDecoder().decode(ReturnDraft.self, from: data) {
            print("📂 Draft loaded for vehicle: \(vehicleId)")
            return draft
        }
        return nil
    }
    
    // MARK: - Delete Draft
    
    /// Deletes damage draft for a vehicle
    func deleteDamageDraft(for vehicleId: UUID) {
        let key = draftKeyPrefix + "damage_" + vehicleId.uuidString
        userDefaults.removeObject(forKey: key)
        print("🗑️ Draft deleted for vehicle: \(vehicleId)")
    }
    
    /// Deletes return draft for a vehicle
    func deleteReturnDraft(for vehicleId: UUID) {
        let key = draftKeyPrefix + "return_" + vehicleId.uuidString
        userDefaults.removeObject(forKey: key)
        print("🗑️ Draft deleted for vehicle: \(vehicleId)")
    }
    
    /// Deletes all drafts (cleanup)
    func deleteAllDrafts() {
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(draftKeyPrefix) {
            userDefaults.removeObject(forKey: key)
        }
        print("🗑️ All drafts deleted")
    }
}

// MARK: - Draft Models

struct DamageDraft: Codable {
    var resKodu: String
    var km: String
    var tarih: Date
    var handoverTarihi: Date
    var durum: String
    var notlar: String
    var photoCount: Int
    var savedAt: Date
}

struct ReturnDraft: Codable {
    var iadeTarihi: Date
    var notlar: String
    var photoCount: Int
    var savedAt: Date
}

