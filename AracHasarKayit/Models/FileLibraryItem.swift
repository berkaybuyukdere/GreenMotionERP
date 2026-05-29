import Foundation
import FirebaseFirestore

struct FileLibraryItem: Identifiable, Equatable {
    let id: String
    let franchiseId: String
    let type: ItemType
    let name: String
    let note: String
    let parentId: String
    let category: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let storagePath: String
    let downloadURL: String
    let uploadedByName: String
    let uploadedByEmail: String
    let updatedAt: Date?

    enum ItemType: String {
        case folder
        case file
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let typeRaw = data["type"] as? String,
              let type = ItemType(rawValue: typeRaw) else { return nil }

        id = document.documentID
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        self.type = type
        name = data["name"] as? String ?? ""
        note = data["note"] as? String ?? ""
        parentId = data["parentId"] as? String ?? ""
        category = data["category"] as? String ?? "other"
        fileName = data["fileName"] as? String ?? ""
        mimeType = data["mimeType"] as? String ?? ""
        if let n = data["fileSize"] as? Int64 {
            fileSize = n
        } else if let n = data["fileSize"] as? Int {
            fileSize = Int64(n)
        } else if let n = data["fileSize"] as? Double {
            fileSize = Int64(n)
        } else {
            fileSize = 0
        }
        storagePath = data["storagePath"] as? String ?? ""
        downloadURL = data["downloadURL"] as? String ?? ""
        uploadedByName = data["uploadedByName"] as? String
            ?? data["createdByName"] as? String ?? ""
        uploadedByEmail = data["uploadedByEmail"] as? String ?? ""
        updatedAt = Self.parseTimestamp(data["updatedAt"]) ?? Self.parseTimestamp(data["createdAt"])
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }

    var displayTitle: String {
        type == .file ? (fileName.isEmpty ? name : fileName) : name
    }

    var categoryLabelKey: String {
        "files.category.\(category)"
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        let n = Double(max(0, bytes))
        if n < 1024 { return "\(Int(n)) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", n / 1024) }
        if n < 1024 * 1024 * 1024 { return String(format: "%.1f MB", n / (1024 * 1024)) }
        return String(format: "%.2f GB", n / (1024 * 1024 * 1024))
    }
}
