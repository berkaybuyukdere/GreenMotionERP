import Foundation

struct RaporGecmisi: Identifiable, Codable {
    var id = UUID()
    var tip: RaporTipi
    var aracPlaka: String
    var olusturulmaTarihi: Date
    var pdfURL: String
    var kullaniciEmail: String?
    var detaylar: String?
    
    enum RaporTipi: String, Codable, CaseIterable {
        case hasar = "Hasar Raporu"
        case iade = "İade Raporu"
        
        var icon: String {
            switch self {
            case .hasar:
                return "exclamationmark.triangle.fill"
            case .iade:
                return "arrow.uturn.backward.circle.fill"
            }
        }
        
        var renk: String {
            switch self {
            case .hasar:
                return "orange"
            case .iade:
                return "purple"
            }
        }
    }
}
