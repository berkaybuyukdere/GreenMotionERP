import Foundation

struct CustomerInfoScanRecord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var franchiseId: String
    var documentType: String
    var navCode: String
    var firstName: String
    var lastName: String
    var fullNameRaw: String
    var photoURLs: [String]
    var extractedText: String
    var createdBy: String
    var createdAt: Date = Date()
}

