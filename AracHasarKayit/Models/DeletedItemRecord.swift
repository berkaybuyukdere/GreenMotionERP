import Foundation
import FirebaseFirestore

/// Stores a snapshot of a deleted document for potential restoration.
struct DeletedItemRecord: Identifiable, Codable {
    @DocumentID var documentId: String?

    var id: String { documentId ?? localId }
    private var localId: String = UUID().uuidString

    let originalCollectionPath: String
    let originalDocumentId: String
    let itemType: DeletedItemType
    let description: String
    let franchiseId: String
    let deletedAt: Date
    let deletedByUid: String
    let deletedByName: String
    /// Serialized JSON of the original document data
    let dataJSON: String

    enum CodingKeys: String, CodingKey {
        case documentId
        case originalCollectionPath, originalDocumentId, itemType, description
        case franchiseId, deletedAt, deletedByUid, deletedByName, dataJSON
        // localId is intentionally excluded — it is only an in-memory fallback
    }

    init(
        originalCollectionPath: String,
        originalDocumentId: String,
        itemType: DeletedItemType,
        description: String,
        franchiseId: String,
        deletedAt: Date,
        deletedByUid: String,
        deletedByName: String,
        dataJSON: String
    ) {
        self.originalCollectionPath = originalCollectionPath
        self.originalDocumentId = originalDocumentId
        self.itemType = itemType
        self.description = description
        self.franchiseId = franchiseId
        self.deletedAt = deletedAt
        self.deletedByUid = deletedByUid
        self.deletedByName = deletedByName
        self.dataJSON = dataJSON
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId)
        self.originalCollectionPath = try c.decode(String.self, forKey: .originalCollectionPath)
        self.originalDocumentId = try c.decode(String.self, forKey: .originalDocumentId)
        self.itemType = try c.decode(DeletedItemType.self, forKey: .itemType)
        self.description = try c.decode(String.self, forKey: .description)
        self.franchiseId = try c.decode(String.self, forKey: .franchiseId)
        self.deletedAt = try c.decode(Date.self, forKey: .deletedAt)
        self.deletedByUid = try c.decode(String.self, forKey: .deletedByUid)
        self.deletedByName = try c.decode(String.self, forKey: .deletedByName)
        self.dataJSON = try c.decode(String.self, forKey: .dataJSON)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(documentId, forKey: .documentId)
        try c.encode(originalCollectionPath, forKey: .originalCollectionPath)
        try c.encode(originalDocumentId, forKey: .originalDocumentId)
        try c.encode(itemType, forKey: .itemType)
        try c.encode(description, forKey: .description)
        try c.encode(franchiseId, forKey: .franchiseId)
        try c.encode(deletedAt, forKey: .deletedAt)
        try c.encode(deletedByUid, forKey: .deletedByUid)
        try c.encode(deletedByName, forKey: .deletedByName)
        try c.encode(dataJSON, forKey: .dataJSON)
    }

    enum DeletedItemType: String, Codable, CaseIterable {
        case iadeIslemi = "return"
        case exitIslemi = "exit"
        case hasarKaydi = "damage"
        case arac = "vehicle"
        case officeOperation = "office_operation"

        var icon: String {
            switch self {
            case .iadeIslemi: return "arrow.uturn.left.circle"
            case .exitIslemi: return "arrow.right.circle"
            case .hasarKaydi: return "exclamationmark.triangle"
            case .arac: return "car.fill"
            case .officeOperation: return "briefcase.fill"
            }
        }

        var label: String {
            switch self {
            case .iadeIslemi: return "Return"
            case .exitIslemi: return "Exit / Check-Out"
            case .hasarKaydi: return "Damage Record"
            case .arac: return "Vehicle"
            case .officeOperation: return "Office Operation"
            }
        }

        var accentColor: String {
            switch self {
            case .iadeIslemi: return "blue"
            case .exitIslemi: return "orange"
            case .hasarKaydi: return "red"
            case .arac: return "green"
            case .officeOperation: return "purple"
            }
        }
    }
}
