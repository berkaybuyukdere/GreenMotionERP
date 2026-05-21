import Foundation
import CryptoKit

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
    /// Contract / incident issue date (business date).
    var contractIssueDate: Date
    /// When the office processed / recorded the entry in the system.
    var processedDate: Date
    var franchiseId: String
    var createdBy: String?
    /// Denormalized display name / email of the user who created the record (for lists).
    var createdByName: String?
    /// How the customer paid (aligned with Payments hub categories).
    var paymentMethod: FleetPaymentCategory?
    /// When set, links to `office_operations/{id}` (Payments record).
    var linkedPaymentOfficeOperationDocumentId: String?
    /// If set, this row is an additional contract line for the same RES; value is the primary document’s Firestore id.
    var supplementOfDocumentId: String?
    /// Client idempotency key for primary creates (`franchise|RES|primary`); optional on legacy rows.
    var idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case id, documentId, photos, amount, resCode, paidAmount, createdAt, franchiseId, createdBy, createdByName
        case contractIssueDate, processedDate, supplementOfDocumentId, idempotencyKey
        case paymentMethod, linkedPaymentOfficeOperationDocumentId
    }

    var effectivePaymentMethod: FleetPaymentCategory {
        paymentMethod ?? .bankingTransaction
    }

    /// Stable idempotency token for a franchise-scoped primary contract line.
    static func primaryIdempotencyKey(franchiseId: String, canonicalRES: String) -> String {
        "\(franchiseId.uppercased())|\(canonicalRES)|primary"
    }

    /// Deterministic Firestore document id derived from `idempotencyKey` (create-only / dedupe).
    static func stableDocumentId(forIdempotencyKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "tac_" + String(hex.prefix(32))
    }

    var isSupplementLine: Bool { supplementOfDocumentId != nil }

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

    /// Whether `query` matches a RES field (`RES`, `RES-12345`, digits-only) or optional notes.
    static func matchesRESSearch(query: String, resField: String, notes: String? = nil) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }

        let fieldCanon = canonicalRES(from: resField)
        let qCanon = canonicalRES(from: q)
        if !qCanon.isEmpty, !fieldCanon.isEmpty, fieldCanon.localizedCaseInsensitiveCompare(qCanon) == .orderedSame {
            return true
        }
        if !fieldCanon.isEmpty, fieldCanon.localizedCaseInsensitiveContains(q) {
            return true
        }

        let qDigits = resDigits(from: q)
        if !qDigits.isEmpty {
            let fieldDigits = resDigits(from: resField)
            if !fieldDigits.isEmpty, fieldDigits.contains(qDigits) { return true }
        }

        let qUpper = q.uppercased()
        if (qUpper == "RES" || qUpper == "RES-"), !fieldCanon.isEmpty {
            return true
        }

        if let notes, notes.localizedCaseInsensitiveContains(q) {
            return true
        }
        return false
    }

    init(
        id: UUID = UUID(),
        documentId: String? = nil,
        photos: [String] = [],
        amount: Double,
        resCode: String,
        paidAmount: Double? = nil,
        createdAt: Date = Date(),
        contractIssueDate: Date? = nil,
        processedDate: Date? = nil,
        franchiseId: String = "CH",
        createdBy: String? = nil,
        createdByName: String? = nil,
        paymentMethod: FleetPaymentCategory? = nil,
        linkedPaymentOfficeOperationDocumentId: String? = nil,
        supplementOfDocumentId: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.photos = photos
        self.amount = amount
        self.resCode = Self.canonicalRES(from: resCode)
        self.paidAmount = paidAmount
        self.createdAt = createdAt
        self.contractIssueDate = contractIssueDate ?? createdAt
        self.processedDate = processedDate ?? createdAt
        self.franchiseId = franchiseId.uppercased()
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.paymentMethod = paymentMethod
        self.linkedPaymentOfficeOperationDocumentId = linkedPaymentOfficeOperationDocumentId
        self.supplementOfDocumentId = supplementOfDocumentId
        self.idempotencyKey = idempotencyKey
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
        self.contractIssueDate = try c.decodeIfPresent(Date.self, forKey: .contractIssueDate) ?? self.createdAt
        self.processedDate = try c.decodeIfPresent(Date.self, forKey: .processedDate) ?? self.createdAt
        self.franchiseId = (try c.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        self.createdByName = try c.decodeIfPresent(String.self, forKey: .createdByName)
        self.paymentMethod = try c.decodeIfPresent(FleetPaymentCategory.self, forKey: .paymentMethod)
        self.linkedPaymentOfficeOperationDocumentId = try c.decodeIfPresent(String.self, forKey: .linkedPaymentOfficeOperationDocumentId)
        self.supplementOfDocumentId = try c.decodeIfPresent(String.self, forKey: .supplementOfDocumentId)
        self.idempotencyKey = try c.decodeIfPresent(String.self, forKey: .idempotencyKey)
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
        try c.encode(contractIssueDate, forKey: .contractIssueDate)
        try c.encode(processedDate, forKey: .processedDate)
        try c.encode(franchiseId, forKey: .franchiseId)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(createdByName, forKey: .createdByName)
        try c.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try c.encodeIfPresent(linkedPaymentOfficeOperationDocumentId, forKey: .linkedPaymentOfficeOperationDocumentId)
        try c.encodeIfPresent(supplementOfDocumentId, forKey: .supplementOfDocumentId)
        try c.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
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
