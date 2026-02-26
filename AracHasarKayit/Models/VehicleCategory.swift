import Foundation

struct VehicleCategory: Identifiable, Codable {
    var id: String
    var name: String
    var franchiseId: String = "CH"
    var createdAt: Date = Date()
    
    init(name: String, franchiseId: String = "CH") {
        let normalized = VehicleCategory.normalizeName(name)
        self.id = VehicleCategory.makeDocumentId(from: normalized)
        self.name = normalized
        self.franchiseId = franchiseId
        self.createdAt = Date()
    }
    
    static func normalizeName(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }
    
    static func makeDocumentId(from categoryName: String) -> String {
        let normalized = normalizeName(categoryName)
        return normalized
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
    }
}
