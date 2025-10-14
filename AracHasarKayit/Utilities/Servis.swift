import Foundation

struct Servis: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var servisFirmaId: UUID?
    var servisFirmaAdi: String
    var durum: ServisDurum
    var gonderilmeTarihi: Date
    var teslimTarihi: Date?
    var aciklama: String
    var servisNedenleri: [ServisNeden] // Servis sebepleri
    
    enum ServisDurum: String, Codable, CaseIterable {
        case serviste = "Serviste"
        case tamamlandi = "Tamamlandı"
        case iptal = "İptal"
        
        var icon: String {
            switch self {
            case .serviste: return "wrench.and.screwdriver.fill"
            case .tamamlandi: return "checkmark.circle.fill"
            case .iptal: return "xmark.circle.fill"
            }
        }
        
        var renk: String {
            switch self {
            case .serviste: return "orange"
            case .tamamlandi: return "green"
            case .iptal: return "red"
            }
        }
    }
    
    enum ServisNeden: String, Codable, CaseIterable {
        case aydinlatma = "Aydınlatma Sistemi"
        case farlar = "Farlar"
        case silecekler = "Silecekler ve Durumu"
        case silecekSuyu = "Silecek Suyu ve Antifriz"
        case onCam = "Ön Cam Kontrolü"
        case vignette = "Vignette Kontrolü"
        case klimaIsitma = "Klima/Isıtma Sistemi"
        case korna = "Korna"
        case akinor = "Akü"
        case motorYag = "Motor Yağı Seviyesi"
        case motorKontrol = "Motor Kontrol (Yağ Sızıntısı/Ses)"
        case frenSistemi = "Fren Sistemi"
        case frenHidrolic = "Fren Hidroliği"
        case supensiyon = "Süspansiyon/Direksiyon"
        case lastikler = "Lastikler (Profil/Durum)"
        case lastikBasinci = "Lastik Basıncı"
        case hasarKontrol = "Hasar Kontrolü"
        case genelServis = "Genel Servis"
        case googleYorum = "Google Değerlendirme"
        
        var icon: String {
            switch self {
            case .aydinlatma: return "lightbulb.fill"
            case .farlar: return "light.beacon.max.fill"
            case .silecekler: return "windshield.front.and.wiper"
            case .silecekSuyu: return "drop.fill"
            case .onCam: return "windshield.front.and.wiper"
            case .vignette: return "ticket.fill"
            case .klimaIsitma: return "thermometer.medium"
            case .korna: return "speaker.wave.3.fill"
            case .akinor: return "battery.100"
            case .motorYag: return "oil.can.fill"
            case .motorKontrol: return "engine.combustion.fill"
            case .frenSistemi: return "brake.signal"
            case .frenHidrolic: return "drop.triangle.fill"
            case .supensiyon: return "car.side.fill"
            case .lastikler: return "circle.circle"
            case .lastikBasinci: return "gauge.medium"
            case .hasarKontrol: return "checkmark.shield.fill"
            case .genelServis: return "wrench.and.screwdriver.fill"
            case .googleYorum: return "star.fill"
            }
        }
    }
    
    init(aracId: UUID, aracPlaka: String, servisFirmaId: UUID? = nil, servisFirmaAdi: String, durum: ServisDurum = .serviste, gonderilmeTarihi: Date = Date(), aciklama: String = "", servisNedenleri: [ServisNeden] = []) {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.servisFirmaId = servisFirmaId
        self.servisFirmaAdi = servisFirmaAdi
        self.durum = durum
        self.gonderilmeTarihi = gonderilmeTarihi
        self.aciklama = aciklama
        self.servisNedenleri = servisNedenleri
    }
}
