import Foundation

enum IadeStatus: String, Codable {
    case inProgress = "In Progress"
    case completed = "Completed"
}

struct ReturnChecklist: Codable, Equatable {
    var customerPresent: Bool = false
    var customerNoTime: Bool = false
    var keyFromKeybox: Bool = false
    var customerRefusedSignature: Bool = false
    var customerLeftKeyAtOffice: Bool = false
    
    var hasAnySelection: Bool {
        customerPresent ||
        customerNoTime ||
        keyFromKeybox ||
        customerRefusedSignature ||
        customerLeftKeyAtOffice
    }
}

struct IadeIslemi: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var iadeTarihi: Date // Kullanıcının seçtiği iade tarihi (DatePicker)
    var createdAt: Date // İşlemin gerçek oluşturulma tarihi (filtreleme için)
    var fotograflar: [String]
    var notlar: String
    var status: IadeStatus
    var createdBy: String? // User ID who created this record
    var franchiseId: String = "CH" // Franchise ID for data isolation
    var checklist: ReturnChecklist?
    var customerFirstName: String?
    var customerLastName: String?
    var customerEmail: String?
    /// Türkiye: T.C. kimlik veya pasaport numarası.
    var customerNationalId: String?
    /// Türkiye: test sürücüsü adı (manuel; müşteri bilgisinden ayrı).
    var testDriverFirstName: String?
    /// Türkiye: test sürücüsü soyadı.
    var testDriverLastName: String?
    var customerSignatureURL: String?
    var km: Int?
    var yakitSeviyesi: String?
    var bayiAdi: String?
    /// Same Firestore keys as checkout / web: optional branch labels.
    var pickUpBranch: String?
    var dropOffBranch: String?
    /// Links return row to the open checkout when filled from Front Desk (`linkedExitId` on web).
    var linkedExitId: UUID?
    /// Türkiye NAV / kontrat numarası (bağlı çıkış yokken veya PDF için yerel kopya).
    var navKodu: String?
    var returnEmailSentAt: Date?
    var returnEmailLastStatus: String?
    var returnEmailRecipient: String?
    /// Turkey checkout/return template: YES/NO selections for vehicle-delivered items.
    var vehicleItemsChecklist: [String: Bool]?
    /// Unique token used for the customer QR self-fill web form.
    /// Auto-generated on creation; preserved on updates.
    var qrToken: String = UUID().uuidString
    /// Web-aligned soft delete.
    var isDeleted: Bool = false
    var deletedAt: Date?
    var deletedBy: String?
    /// Web: planned return row created right after checkout completes (`expectedReturnPlanned` on Firestore).
    var expectedReturnPlanned: Bool = false
    /// Turkey: customer accepted General Rental Terms (timestamp + language + signature URL).
    var trRentalTermsAcceptedAt: Date?
    var trRentalTermsLanguage: String?
    var trRentalTermsSignatureURL: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.aracId = try container.decode(UUID.self, forKey: .aracId)
        self.aracPlaka = try container.decode(String.self, forKey: .aracPlaka)
        self.iadeTarihi = try container.decode(Date.self, forKey: .iadeTarihi)
        // Backward compatibility: Eğer createdAt yoksa iadeTarihi kullan
        let decodedCreatedAt = try? container.decode(Date.self, forKey: .createdAt)
        self.createdAt = decodedCreatedAt ?? self.iadeTarihi
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.notlar = try container.decode(String.self, forKey: .notlar)
        self.status = (try? container.decode(IadeStatus.self, forKey: .status)) ?? .completed
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.checklist = try container.decodeIfPresent(ReturnChecklist.self, forKey: .checklist)
        self.customerFirstName = try container.decodeIfPresent(String.self, forKey: .customerFirstName)
        self.customerLastName = try container.decodeIfPresent(String.self, forKey: .customerLastName)
        self.customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
        self.customerNationalId = try container.decodeIfPresent(String.self, forKey: .customerNationalId)
        self.testDriverFirstName = try container.decodeIfPresent(String.self, forKey: .testDriverFirstName)
        self.testDriverLastName = try container.decodeIfPresent(String.self, forKey: .testDriverLastName)
        self.customerSignatureURL = try container.decodeIfPresent(String.self, forKey: .customerSignatureURL)
        self.km = try container.decodeIfPresent(Int.self, forKey: .km)
        self.yakitSeviyesi = try container.decodeIfPresent(String.self, forKey: .yakitSeviyesi)
        self.bayiAdi = try container.decodeIfPresent(String.self, forKey: .bayiAdi)
        self.pickUpBranch = try container.decodeIfPresent(String.self, forKey: .pickUpBranch)
        self.dropOffBranch = try container.decodeIfPresent(String.self, forKey: .dropOffBranch)
        if let u = try container.decodeIfPresent(UUID.self, forKey: .linkedExitId) {
            self.linkedExitId = u
        } else if let s = try container.decodeIfPresent(String.self, forKey: .linkedExitId) {
            self.linkedExitId = UUID(uuidString: s)
        } else {
            self.linkedExitId = nil
        }
        self.navKodu = try container.decodeIfPresent(String.self, forKey: .navKodu)
        self.returnEmailSentAt = try container.decodeIfPresent(Date.self, forKey: .returnEmailSentAt)
        self.returnEmailLastStatus = try container.decodeIfPresent(String.self, forKey: .returnEmailLastStatus)
        self.returnEmailRecipient = try container.decodeIfPresent(String.self, forKey: .returnEmailRecipient)
        self.vehicleItemsChecklist = try container.decodeIfPresent([String: Bool].self, forKey: .vehicleItemsChecklist)
        // Backward compat: existing docs without qrToken get a stable token derived from their UUID
        self.qrToken = (try? container.decodeIfPresent(String.self, forKey: .qrToken)) ?? self.id.uuidString
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
        self.expectedReturnPlanned = try container.decodeIfPresent(Bool.self, forKey: .expectedReturnPlanned) ?? false
        self.trRentalTermsAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .trRentalTermsAcceptedAt)
        self.trRentalTermsLanguage = try container.decodeIfPresent(String.self, forKey: .trRentalTermsLanguage)
        self.trRentalTermsSignatureURL = try container.decodeIfPresent(String.self, forKey: .trRentalTermsSignatureURL)
    }
    
    /// - Parameter id: Defaults to a new UUID. Use a fixed id (e.g. same as linked checkout) for idempotent planned returns.
    init(id: UUID = UUID(), aracId: UUID, aracPlaka: String, iadeTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "", status: IadeStatus = .completed, createdAt: Date? = nil, createdBy: String? = nil, checklist: ReturnChecklist? = nil, customerFirstName: String? = nil, customerLastName: String? = nil, customerEmail: String? = nil, customerNationalId: String? = nil, testDriverFirstName: String? = nil, testDriverLastName: String? = nil, customerSignatureURL: String? = nil, km: Int? = nil, yakitSeviyesi: String? = nil, bayiAdi: String? = nil, pickUpBranch: String? = nil, dropOffBranch: String? = nil, linkedExitId: UUID? = nil, navKodu: String? = nil, returnEmailSentAt: Date? = nil, returnEmailLastStatus: String? = nil, returnEmailRecipient: String? = nil, vehicleItemsChecklist: [String: Bool]? = nil, qrToken: String? = nil, expectedReturnPlanned: Bool = false, trRentalTermsAcceptedAt: Date? = nil, trRentalTermsLanguage: String? = nil, trRentalTermsSignatureURL: String? = nil) {
        self.id = id
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.iadeTarihi = iadeTarihi
        // createdAt belirtilmediyse şu anki tarihi kullan (gerçek işlem tarihi)
        self.createdAt = createdAt ?? Date()
        self.fotograflar = fotograflar
        self.notlar = notlar
        self.status = status
        self.createdBy = createdBy
        self.checklist = checklist
        self.customerFirstName = customerFirstName
        self.customerLastName = customerLastName
        self.customerEmail = customerEmail
        self.customerNationalId = customerNationalId
        self.testDriverFirstName = testDriverFirstName
        self.testDriverLastName = testDriverLastName
        self.customerSignatureURL = customerSignatureURL
        self.km = km
        self.yakitSeviyesi = yakitSeviyesi
        self.bayiAdi = bayiAdi
        self.pickUpBranch = pickUpBranch
        self.dropOffBranch = dropOffBranch
        self.linkedExitId = linkedExitId
        self.navKodu = navKodu
        self.returnEmailSentAt = returnEmailSentAt
        self.returnEmailLastStatus = returnEmailLastStatus
        self.returnEmailRecipient = returnEmailRecipient
        self.vehicleItemsChecklist = vehicleItemsChecklist
        self.qrToken = qrToken ?? UUID().uuidString
        self.expectedReturnPlanned = expectedReturnPlanned
        self.trRentalTermsAcceptedAt = trRentalTermsAcceptedAt
        self.trRentalTermsLanguage = trRentalTermsLanguage
        self.trRentalTermsSignatureURL = trRentalTermsSignatureURL
    }

    var customerFullName: String {
        let first = customerFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = customerLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var testDriverFullName: String {
        let first = testDriverFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = testDriverLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
