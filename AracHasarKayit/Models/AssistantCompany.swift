import Foundation

struct AssistantCompany: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var phoneNumber: String // İsviçre formatında telefon numarası
    var createdAt: Date
    var createdBy: String? // User ID who created this record
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    }
    
    init(name: String, phoneNumber: String, createdAt: Date = Date(), createdBy: String? = nil) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
        self.createdBy = createdBy
    }
    
    /// İsviçre telefon numarası formatını kontrol eder
    /// Format: +41 XX XXX XX XX veya 0XX XXX XX XX
    static func isValidSwissPhoneNumber(_ phone: String) -> Bool {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // +41 ile başlayan format (9 haneli numara)
        if cleaned.hasPrefix("+41") {
            let numberPart = String(cleaned.dropFirst(3))
            return numberPart.count == 9 && numberPart.allSatisfy { $0.isNumber }
        }
        
        // 0 ile başlayan format (10 haneli numara)
        if cleaned.hasPrefix("0") {
            return cleaned.count == 10 && cleaned.allSatisfy { $0.isNumber }
        }
        
        return false
    }
    
    /// Telefon numarasını İsviçre formatına çevirir
    static func formatSwissPhoneNumber(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // +41 ile başlayan format
        if cleaned.hasPrefix("+41") {
            let numberPart = String(cleaned.dropFirst(3))
            if numberPart.count == 9 {
                // +41 XX XXX XX XX formatına çevir
                let index1 = numberPart.index(numberPart.startIndex, offsetBy: 2)
                let index2 = numberPart.index(index1, offsetBy: 3)
                let index3 = numberPart.index(index2, offsetBy: 2)
                
                let part1 = String(numberPart[..<index1])
                let part2 = String(numberPart[index1..<index2])
                let part3 = String(numberPart[index2..<index3])
                let part4 = String(numberPart[index3...])
                
                return "+41 \(part1) \(part2) \(part3) \(part4)"
            }
        }
        
        // 0 ile başlayan format
        if cleaned.hasPrefix("0") && cleaned.count == 10 {
            let numberPart = String(cleaned.dropFirst(1))
            // 0XX XXX XX XX formatına çevir
            let index1 = numberPart.index(numberPart.startIndex, offsetBy: 2)
            let index2 = numberPart.index(index1, offsetBy: 3)
            let index3 = numberPart.index(index2, offsetBy: 2)
            
            let part1 = String(numberPart[..<index1])
            let part2 = String(numberPart[index1..<index2])
            let part3 = String(numberPart[index2..<index3])
            let part4 = String(numberPart[index3...])
            
            return "0\(part1) \(part2) \(part3) \(part4)"
        }
        
        return phone
    }
}

