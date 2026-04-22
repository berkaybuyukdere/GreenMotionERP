import Foundation

enum ExitStatus: String, Codable {
    case inProgress = "In Progress"
    case parked = "Parked"
    case completed = "Completed"
}

struct ExitIslemi: Identifiable, Codable {
    private enum CodingKeys: String, CodingKey {
        case id, aracId, aracPlaka, exitTarihi, createdAt, fotograflar, notlar, resKodu, navKodu, km, yakitSeviyesi, bayiAdi, pickUpBranch, dropOffBranch
        /// Web + Firestore use `plannedCheckinAt`; legacy iOS used `plannedReturnAt`.
        case plannedCheckinAt
        case plannedReturnAtLegacy = "plannedReturnAt"
        case customerFirstName, customerLastName, customerEmail, customerSignatureURL
        case checkoutEmailSentAt, checkoutEmailLastStatus, checkoutEmailRecipient, qrToken, status, createdBy
        case assistantCompanyName, assistantCompanyPhone, franchiseId, isDeleted, deletedAt, deletedBy, expectedReturnDismissedAt
    }

    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var exitTarihi: Date // Sadece PDF için kullanılan tarih
    var createdAt: Date // İşlemin gerçek oluşturulma tarihi (filtreleme için)
    var fotograflar: [String]
    var notlar: String
    var resKodu: String
    var navKodu: String?
    var km: Int?
    var yakitSeviyesi: String?
    var bayiAdi: String?
    /// Web-aligned branch labels (`pickupBranchName` / `dropoffBranchName` on kiosk handover).
    var pickUpBranch: String?
    var dropOffBranch: String?
    /// Expected return (from web `plannedCheckinAt`); used for Operations planner after checkout completes.
    var plannedReturnAt: Date?
    var customerFirstName: String?
    var customerLastName: String?
    var customerEmail: String?
    var customerSignatureURL: String?
    var checkoutEmailSentAt: Date?
    var checkoutEmailLastStatus: String?
    var checkoutEmailRecipient: String?
    /// Unique token used for the customer QR self-fill web form (check-out flow).
    var qrToken: String = UUID().uuidString
    var status: ExitStatus
    var createdBy: String? // User ID who created this record
    var assistantCompanyName: String? // Assistant company name
    var assistantCompanyPhone: String? // Assistant company phone number
    var franchiseId: String = "CH" // Franchise ID for data isolation
    /// Web-aligned soft delete (`isDeleted` + `deletedAt` + `deletedBy` on Firestore).
    var isDeleted: Bool = false
    var deletedAt: Date?
    var deletedBy: String?
    /// When set, expected-return generators must not recreate a waiting return for this checkout.
    var expectedReturnDismissedAt: Date? = nil
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.aracId = try container.decode(UUID.self, forKey: .aracId)
        self.aracPlaka = try container.decode(String.self, forKey: .aracPlaka)
        self.exitTarihi = try container.decode(Date.self, forKey: .exitTarihi)
        // Backward compatibility: Eğer createdAt yoksa exitTarihi kullan
        let decodedCreatedAt = try? container.decode(Date.self, forKey: .createdAt)
        self.createdAt = decodedCreatedAt ?? self.exitTarihi
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.notlar = (try? container.decode(String.self, forKey: .notlar)) ?? ""
        self.resKodu = (try? container.decode(String.self, forKey: .resKodu)) ?? ""
        self.navKodu = try container.decodeIfPresent(String.self, forKey: .navKodu)
        self.km = try container.decodeIfPresent(Int.self, forKey: .km)
        self.yakitSeviyesi = try container.decodeIfPresent(String.self, forKey: .yakitSeviyesi)
        self.bayiAdi = try container.decodeIfPresent(String.self, forKey: .bayiAdi)
        self.pickUpBranch = try container.decodeIfPresent(String.self, forKey: .pickUpBranch)
        self.dropOffBranch = try container.decodeIfPresent(String.self, forKey: .dropOffBranch)
        if let d = try container.decodeIfPresent(Date.self, forKey: .plannedCheckinAt) {
            self.plannedReturnAt = d
        } else if let d = try container.decodeIfPresent(Date.self, forKey: .plannedReturnAtLegacy) {
            self.plannedReturnAt = d
        } else {
            self.plannedReturnAt = nil
        }
        self.customerFirstName = try container.decodeIfPresent(String.self, forKey: .customerFirstName)
        self.customerLastName = try container.decodeIfPresent(String.self, forKey: .customerLastName)
        self.customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
        self.customerSignatureURL = try container.decodeIfPresent(String.self, forKey: .customerSignatureURL)
        self.checkoutEmailSentAt = try container.decodeIfPresent(Date.self, forKey: .checkoutEmailSentAt)
        self.checkoutEmailLastStatus = try container.decodeIfPresent(String.self, forKey: .checkoutEmailLastStatus)
        self.checkoutEmailRecipient = try container.decodeIfPresent(String.self, forKey: .checkoutEmailRecipient)
        self.qrToken = (try? container.decodeIfPresent(String.self, forKey: .qrToken)) ?? self.id.uuidString
        self.status = (try? container.decode(ExitStatus.self, forKey: .status)) ?? .completed
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.assistantCompanyName = try container.decodeIfPresent(String.self, forKey: .assistantCompanyName)
        self.assistantCompanyPhone = try container.decodeIfPresent(String.self, forKey: .assistantCompanyPhone)
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
        self.expectedReturnDismissedAt = try container.decodeIfPresent(Date.self, forKey: .expectedReturnDismissedAt)
    }
    
    init(aracId: UUID, aracPlaka: String, exitTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "", resKodu: String = "", navKodu: String? = nil, km: Int? = nil, yakitSeviyesi: String? = nil, bayiAdi: String? = nil, pickUpBranch: String? = nil, dropOffBranch: String? = nil, plannedReturnAt: Date? = nil, customerFirstName: String? = nil, customerLastName: String? = nil, customerEmail: String? = nil, customerSignatureURL: String? = nil, checkoutEmailSentAt: Date? = nil, checkoutEmailLastStatus: String? = nil, checkoutEmailRecipient: String? = nil, qrToken: String? = nil, status: ExitStatus = .completed, createdAt: Date? = nil, createdBy: String? = nil, assistantCompanyName: String? = nil, assistantCompanyPhone: String? = nil) {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.exitTarihi = exitTarihi
        // createdAt belirtilmediyse şu anki tarihi kullan (gerçek işlem tarihi)
        self.createdAt = createdAt ?? Date()
        self.fotograflar = fotograflar
        self.notlar = notlar
        self.resKodu = resKodu
        self.navKodu = navKodu
        self.km = km
        self.yakitSeviyesi = yakitSeviyesi
        self.bayiAdi = bayiAdi
        self.pickUpBranch = pickUpBranch
        self.dropOffBranch = dropOffBranch
        self.plannedReturnAt = plannedReturnAt
        self.customerFirstName = customerFirstName
        self.customerLastName = customerLastName
        self.customerEmail = customerEmail
        self.customerSignatureURL = customerSignatureURL
        self.checkoutEmailSentAt = checkoutEmailSentAt
        self.checkoutEmailLastStatus = checkoutEmailLastStatus
        self.checkoutEmailRecipient = checkoutEmailRecipient
        self.qrToken = qrToken ?? UUID().uuidString
        self.status = status
        self.createdBy = createdBy
        self.assistantCompanyName = assistantCompanyName
        self.assistantCompanyPhone = assistantCompanyPhone
    }

    var customerFullName: String {
        let first = customerFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = customerLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(aracId, forKey: .aracId)
        try c.encode(aracPlaka, forKey: .aracPlaka)
        try c.encode(exitTarihi, forKey: .exitTarihi)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(fotograflar, forKey: .fotograflar)
        try c.encode(notlar, forKey: .notlar)
        try c.encode(resKodu, forKey: .resKodu)
        try c.encodeIfPresent(navKodu, forKey: .navKodu)
        try c.encodeIfPresent(km, forKey: .km)
        try c.encodeIfPresent(yakitSeviyesi, forKey: .yakitSeviyesi)
        try c.encodeIfPresent(bayiAdi, forKey: .bayiAdi)
        try c.encodeIfPresent(pickUpBranch, forKey: .pickUpBranch)
        try c.encodeIfPresent(dropOffBranch, forKey: .dropOffBranch)
        try c.encodeIfPresent(plannedReturnAt, forKey: .plannedCheckinAt)
        try c.encodeIfPresent(customerFirstName, forKey: .customerFirstName)
        try c.encodeIfPresent(customerLastName, forKey: .customerLastName)
        try c.encodeIfPresent(customerEmail, forKey: .customerEmail)
        try c.encodeIfPresent(customerSignatureURL, forKey: .customerSignatureURL)
        try c.encodeIfPresent(checkoutEmailSentAt, forKey: .checkoutEmailSentAt)
        try c.encodeIfPresent(checkoutEmailLastStatus, forKey: .checkoutEmailLastStatus)
        try c.encodeIfPresent(checkoutEmailRecipient, forKey: .checkoutEmailRecipient)
        try c.encode(qrToken, forKey: .qrToken)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(assistantCompanyName, forKey: .assistantCompanyName)
        try c.encodeIfPresent(assistantCompanyPhone, forKey: .assistantCompanyPhone)
        try c.encode(franchiseId, forKey: .franchiseId)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(deletedBy, forKey: .deletedBy)
        try c.encodeIfPresent(expectedReturnDismissedAt, forKey: .expectedReturnDismissedAt)
    }
}

