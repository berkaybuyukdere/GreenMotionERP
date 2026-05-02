import Foundation

/// Switzerland-only office flow: traffic accident contracts (`traffic_accident_contracts` collection).
struct TrafficAccidentContract: Identifiable, Equatable, Codable, Hashable {
    var id: UUID
    var documentId: String?
    /// Stored receipt / contract photo download URLs (Firebase Storage).
    var photos: [String]
    var amount: Double
    /// Canonical `RES-` + digits only (e.g. `RES-12345`).
    var resCode: String
    /// When set and equals `amount`, UI treats row as paid (green).
    var paidAmount: Double?
    var createdAt: Date
    var franchiseId: String
    var createdBy: String?
    /// Denormalized display name / email of the user who created the record (for lists).
    var createdByName: String?

    enum CodingKeys: String, CodingKey {
        case id, documentId, photos, amount, resCode, paidAmount, createdAt, franchiseId, createdBy, createdByName
    }

    /// Digits only from user input or legacy stored values.
    static func resDigits(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("RES-") {
            s = String(s.dropFirst(4))
        } else if s.hasPrefix("RES") {
            s = String(s.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        }
        return s.filter(\.isNumber)
    }

    /// Normalized storage form `RES-{digits}`.
    static func canonicalRES(from raw: String) -> String {
        let d = resDigits(from: raw)
        return d.isEmpty ? "" : "RES-\(d)"
    }

    /// Display string for lists and exports.
    var displayResCode: String {
        let c = Self.canonicalRES(from: resCode)
        return c.isEmpty ? "—" : c
    }

    init(
        id: UUID = UUID(),
        documentId: String? = nil,
        photos: [String] = [],
        amount: Double,
        resCode: String,
        paidAmount: Double? = nil,
        createdAt: Date = Date(),
        franchiseId: String = "CH",
        createdBy: String? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.photos = photos
        self.amount = amount
        self.resCode = Self.canonicalRES(from: resCode)
        self.paidAmount = paidAmount
        self.createdAt = createdAt
        self.franchiseId = franchiseId.uppercased()
        self.createdBy = createdBy
        self.createdByName = createdByName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId)
        self.photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        self.amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        let rawRes = try c.decodeIfPresent(String.self, forKey: .resCode) ?? ""
        self.resCode = Self.canonicalRES(from: rawRes)
        self.paidAmount = try c.decodeIfPresent(Double.self, forKey: .paidAmount)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.franchiseId = (try c.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        self.createdByName = try c.decodeIfPresent(String.self, forKey: .createdByName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(documentId, forKey: .documentId)
        try c.encode(photos, forKey: .photos)
        try c.encode(amount, forKey: .amount)
        try c.encode(resCode, forKey: .resCode)
        try c.encodeIfPresent(paidAmount, forKey: .paidAmount)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(franchiseId, forKey: .franchiseId)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(createdByName, forKey: .createdByName)
    }

    /// Derived payment status for UI (orange pending vs green paid).
    var isFullyPaid: Bool {
        let owed = max(0, amount)
        guard owed > 0 else { return paidAmount != nil && (paidAmount ?? 0) >= 0 }
        let paid = paidAmount ?? 0
        return paid >= owed - 0.009
    }

    /// Customer paid something but not the full contract amount (e.g. 400 of 1000).
    var hasPartialPayment: Bool {
        let paid = paidAmount ?? 0
        return paid > 0.009 && !isFullyPaid
    }

    /// Sum of `(amount − paid)` still outstanding per contract (partial counts).
    static func totalOutstanding(_ contracts: [TrafficAccidentContract]) -> Double {
        contracts.reduce(0) { acc, c in
            let paid = min(c.amount, c.paidAmount ?? 0)
            return acc + max(0, c.amount - paid)
        }
    }

    /// Sum of all payments collected (capped at each contract’s amount).
    static func totalPaidCollected(_ contracts: [TrafficAccidentContract]) -> Double {
        contracts.reduce(0) { $0 + min($1.amount, $1.paidAmount ?? 0) }
    }
}
