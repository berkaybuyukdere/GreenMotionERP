import Foundation

enum IadeStatus: String, Codable {
    case inProgress = "In Progress"
    case completed = "Completed"
}

struct IadeIslemi: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var iadeTarihi: Date
    var fotograflar: [String]
    var notlar: String
    var status: IadeStatus
    var createdBy: String? // User ID who created this record
    var franchiseId: String = "ch" // Franchise ID for data isolation
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.aracId = try container.decode(UUID.self, forKey: .aracId)
        self.aracPlaka = try container.decode(String.self, forKey: .aracPlaka)
        self.iadeTarihi = try container.decode(Date.self, forKey: .iadeTarihi)
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.notlar = try container.decode(String.self, forKey: .notlar)
        self.status = (try? container.decode(IadeStatus.self, forKey: .status)) ?? .completed
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.franchiseId = try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "ch"
    }
    
    init(aracId: UUID, aracPlaka: String, iadeTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "", status: IadeStatus = .completed, createdBy: String? = nil) {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.iadeTarihi = iadeTarihi
        self.fotograflar = fotograflar
        self.notlar = notlar
        self.status = status
        self.createdBy = createdBy
    }
}
