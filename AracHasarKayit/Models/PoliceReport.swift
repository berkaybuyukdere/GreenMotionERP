import Foundation

/// Switzerland office flow: police report documents keyed by RES (`police_reports` collection).
struct PoliceReport: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var documentId: String?
    var photos: [String]
    /// Canonical `RES-{digits}`.
    var resCode: String
    var reportDate: Date
    var createdAt: Date
    var franchiseId: String
    var createdBy: String?
    var createdByName: String?
    /// `false` → orange status in list; `true` → green when staff marks handled.
    var isProcessed: Bool
    var notes: String

    var displayResCode: String {
        let c = TrafficAccidentContract.canonicalRES(from: resCode)
        return c.isEmpty ? "—" : c
    }

    init(
        id: UUID = UUID(),
        documentId: String? = nil,
        photos: [String] = [],
        resCode: String,
        reportDate: Date = Date(),
        createdAt: Date = Date(),
        franchiseId: String,
        createdBy: String? = nil,
        createdByName: String? = nil,
        isProcessed: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.documentId = documentId
        self.photos = photos
        self.resCode = resCode
        self.reportDate = reportDate
        self.createdAt = createdAt
        self.franchiseId = franchiseId
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.isProcessed = isProcessed
        self.notes = notes
    }
}
