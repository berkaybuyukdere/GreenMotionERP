import Foundation
import UIKit

struct Servis: Identifiable, Codable {
    var id: UUID
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
        
        var displayTitle: String {
            switch self {
            case .serviste: return "In Service"
            case .tamamlandi: return "Completed"
            case .iptal: return "Cancelled"
            }
        }
        
        var icon: String {
            switch self {
            case .serviste: return "wrench.and.screwdriver.fill"
            case .tamamlandi: return "checkmark.circle.fill"
            case .iptal: return "xmark.circle.fill"
            }
        }
        
        var renk: UIColor {
            switch self {
            case .serviste: return .systemOrange
            case .tamamlandi: return .systemGreen
            case .iptal: return .systemRed
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
        
        var localizationKey: String {
            switch self {
            case .aydinlatma: return "service.reason.aydinlatma"
            case .farlar: return "service.reason.farlar"
            case .silecekler: return "service.reason.silecekler"
            case .silecekSuyu: return "service.reason.silecekSuyu"
            case .onCam: return "service.reason.onCam"
            case .vignette: return "service.reason.vignette"
            case .klimaIsitma: return "service.reason.klimaIsitma"
            case .korna: return "service.reason.korna"
            case .akinor: return "service.reason.aku"
            case .motorYag: return "service.reason.motorYag"
            case .motorKontrol: return "service.reason.motorKontrol"
            case .frenSistemi: return "service.reason.frenSistemi"
            case .frenHidrolic: return "service.reason.frenHidrolic"
            case .supensiyon: return "service.reason.supansiyonDireksiyon"
            case .lastikler: return "service.reason.lastikler"
            case .lastikBasinci: return "service.reason.lastikBasinci"
            case .hasarKontrol: return "service.reason.hasarKontrolu"
            case .genelServis: return "service.reason.genelServis"
            case .googleYorum: return "service.reason.googleDegerlendirme"
            }
        }
        
        var displayTitle: String {
            localizationKey.localized
        }
        
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
    
    init(id: UUID = UUID(), aracId: UUID, aracPlaka: String, servisFirmaId: UUID? = nil, servisFirmaAdi: String, durum: ServisDurum = .serviste, gonderilmeTarihi: Date = Date(), teslimTarihi: Date? = nil, aciklama: String = "", servisNedenleri: [ServisNeden] = []) {
        self.id = id
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.servisFirmaId = servisFirmaId
        self.servisFirmaAdi = servisFirmaAdi
        self.durum = durum
        self.gonderilmeTarihi = gonderilmeTarihi
        self.teslimTarihi = teslimTarihi
        self.aciklama = aciklama
        self.servisNedenleri = servisNedenleri
    }
}
