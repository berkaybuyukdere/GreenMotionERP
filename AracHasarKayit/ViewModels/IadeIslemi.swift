import Foundation

struct IadeIslemi: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var iadeTarihi: Date
    var fotograflar: [String]
    var notlar: String
    
    init(aracId: UUID, aracPlaka: String, iadeTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "") {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.iadeTarihi = iadeTarihi
        self.fotograflar = fotograflar
        self.notlar = notlar
    }
}
