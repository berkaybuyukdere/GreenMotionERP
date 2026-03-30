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
    var customerSignatureURL: String?
    var returnEmailSentAt: Date?
    var returnEmailLastStatus: String?
    var returnEmailRecipient: String?
    /// Unique token used for the customer QR self-fill web form.
    /// Auto-generated on creation; preserved on updates.
    var qrToken: String = UUID().uuidString

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
        self.customerSignatureURL = try container.decodeIfPresent(String.self, forKey: .customerSignatureURL)
        self.returnEmailSentAt = try container.decodeIfPresent(Date.self, forKey: .returnEmailSentAt)
        self.returnEmailLastStatus = try container.decodeIfPresent(String.self, forKey: .returnEmailLastStatus)
        self.returnEmailRecipient = try container.decodeIfPresent(String.self, forKey: .returnEmailRecipient)
        // Backward compat: existing docs without qrToken get a stable token derived from their UUID
        self.qrToken = (try? container.decodeIfPresent(String.self, forKey: .qrToken)) ?? self.id.uuidString
    }
    
    init(aracId: UUID, aracPlaka: String, iadeTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "", status: IadeStatus = .completed, createdAt: Date? = nil, createdBy: String? = nil, checklist: ReturnChecklist? = nil, customerFirstName: String? = nil, customerLastName: String? = nil, customerEmail: String? = nil, customerSignatureURL: String? = nil, returnEmailSentAt: Date? = nil, returnEmailLastStatus: String? = nil, returnEmailRecipient: String? = nil, qrToken: String? = nil) {
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
        self.customerSignatureURL = customerSignatureURL
        self.returnEmailSentAt = returnEmailSentAt
        self.returnEmailLastStatus = returnEmailLastStatus
        self.returnEmailRecipient = returnEmailRecipient
        self.qrToken = qrToken ?? UUID().uuidString
    }

    var customerFullName: String {
        let first = customerFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = customerLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
