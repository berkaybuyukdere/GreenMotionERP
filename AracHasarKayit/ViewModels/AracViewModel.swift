import Foundation
import Combine
import UIKit  // EKLENDI

class AracViewModel: ObservableObject {
    @Published var araclar: [Arac] = []
    @Published var servisler: [Servis] = []
    @Published var iadeIslemleri: [IadeIslemi] = []
    @Published var activities: [Activity] = []
    @Published var servisFirmalari: [ServisFirma] = []
    @Published var kategoriler: [String] = ["A", "B", "D", "F", "H", "J", "L", "M", "MB", "MC", "N", "R", "S", "T", "U", "V", "X", "Y", "Z"]

    private let firebaseService: FirebaseService  // Type annotation eklendi
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.firebaseService = FirebaseService.shared  // Explicit atama
        araclariYukle()
        servisleriYukle()
        iadeleriYukle()
        activitiesYukle()
        servisFirmalariYukle()
        setupRealtimeListeners()
    }
    
    // MARK: - Real-time Firebase Listeners
    func setupRealtimeListeners() {
        firebaseService.observeIadeIslemleri { [weak self] (iadeler: [IadeIslemi]) in
            DispatchQueue.main.async {
                self?.iadeIslemleri = iadeler
                print("✅ İade işlemleri real-time güncellendi: \(iadeler.count) adet")
            }
        }
        
        firebaseService.observeAraclar { [weak self] (araclar: [Arac]) in
            DispatchQueue.main.async {
                self?.araclar = araclar
                print("✅ Araçlar real-time güncellendi: \(araclar.count) adet")
            }
        }
    }
    
    // MARK: - Initial Loading Functions
    func araclariYukle() {
        firebaseService.loadAraclar { [weak self] (araclar: [Arac]?, error: Error?) in
            if let error = error {
                print("❌ Araçlar yüklenemedi: \(error.localizedDescription)")
            } else if let araclar = araclar {
                DispatchQueue.main.async {
                    self?.araclar = araclar
                    print("✅ Araçlar yüklendi: \(araclar.count) adet")
                }
            }
        }
    }
    
    func servisleriYukle() {
        firebaseService.loadServisler { [weak self] (servisKayitlari: [ServisKaydi]?, error: Error?) in
            if let error = error {
                print("❌ Servisler yüklenemedi: \(error.localizedDescription)")
            } else if let servisKayitlari = servisKayitlari {
                DispatchQueue.main.async {
                    self?.servisler = servisKayitlari.map { kayit in
                        Servis(
                            aracId: kayit.aracId,
                            aracPlaka: "",
                            servisFirmaId: nil,
                            servisFirmaAdi: kayit.servisTuru,
                            durum: .serviste,
                            gonderilmeTarihi: kayit.tarih,
                            aciklama: kayit.aciklama,
                            servisNedenleri: []
                        )
                    }
                    print("✅ Servisler yüklendi: \(servisKayitlari.count) adet")
                }
            }
        }
    }
    
    func iadeleriYukle() {
        firebaseService.loadIadeIslemleri { [weak self] (iadeler: [IadeIslemi]?, error: Error?) in
            if let error = error {
                print("❌ İadeler yüklenemedi: \(error.localizedDescription)")
            } else if let iadeler = iadeler {
                DispatchQueue.main.async {
                    self?.iadeIslemleri = iadeler
                    print("✅ İadeler yüklendi: \(iadeler.count) adet")
                }
            }
        }
    }
    
    func activitiesYukle() {
        firebaseService.loadActivities { [weak self] (activities: [Activity]?, error: Error?) in
            if let error = error {
                print("❌ Aktiviteler yüklenemedi: \(error.localizedDescription)")
            } else if let activities = activities {
                DispatchQueue.main.async {
                    self?.activities = activities
                    print("✅ Aktiviteler yüklendi: \(activities.count) adet")
                }
            }
        }
    }
    
    func servisFirmalariYukle() {
        firebaseService.loadServisFirmalari { [weak self] (firmalar: [ServisFirma]?, error: Error?) in
            if let error = error {
                print("❌ Servis firmaları yüklenemedi: \(error.localizedDescription)")
            } else if let firmalar = firmalar {
                DispatchQueue.main.async {
                    self?.servisFirmalari = firmalar
                    print("✅ Servis firmaları yüklendi: \(firmalar.count) adet")
                }
            }
        }
    }
    
    // MARK: - Araç İşlemleri
    func aracEkle(_ arac: Arac) {
        araclar.append(arac)
        firebaseService.saveArac(arac) { error in
            if let error = error {
                print("❌ Araç kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ Araç kaydedildi: \(arac.plakaFormatli)")
                HapticManager.shared.success()  // SUCCESS HAPTIC
            }
        }
        activityEkle(.aracEklendi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
    }

    // Araç Güncelle
    func aracGuncelle(_ arac: Arac) {
        if let index = araclar.firstIndex(where: { $0.id == arac.id }) {
            araclar[index] = arac
            firebaseService.updateArac(arac) { error in
                if let error = error {
                    print("❌ Araç güncellenemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Araç güncellendi: \(arac.plakaFormatli)")
                    HapticManager.shared.success()  // SUCCESS HAPTIC
                }
            }
        }
    }
    
    func aracSil(_ arac: Arac) {
        if let index = araclar.firstIndex(where: { $0.id == arac.id }) {
            araclar.remove(at: index)
            
            // Hasar fotoğraflarını sil
            let imageManager = FirebaseImageManager.shared
            for hasar in arac.hasarKayitlari {
                for fotoURL in hasar.fotograflar {
                    imageManager.deleteImage(fotoURL)
                }
            }
            
            firebaseService.deleteArac(id: arac.id) { error in
                if let error = error {
                    print("❌ Araç silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Araç silindi: \(arac.plakaFormatli)")
                }
            }
            
            activityEkle(.aracSilindi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
        }
    }
    
    func aracBulPlaka(plaka: String) -> Arac? {
        let temizPlaka = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        
        if let mevcutArac = araclar.first(where: {
            $0.plaka.replacingOccurrences(of: " ", with: "").uppercased() == temizPlaka
        }) {
            return mevcutArac
        }
        
        let yeniArac = Arac(plaka: temizPlaka, marka: "", model: "")
        return yeniArac
    }
    
    // MARK: - Hasar İşlemleri
    func hasarEkle(aracId: UUID, hasar: HasarKaydi) {
        if let index = araclar.firstIndex(where: { $0.id == aracId }) {
            araclar[index].hasarKayitlari.append(hasar)
            firebaseService.updateArac(araclar[index]) { error in
                if let error = error {
                    print("❌ Hasar eklenemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Hasar eklendi")
                    HapticManager.shared.success()  // SUCCESS HAPTIC
                }
            }
            activityEkle(.hasarEklendi, aciklama: "\(araclar[index].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[index].plakaFormatli)
        }
    }

    // Hasar Güncelle
    func hasarGuncelle(aracId: UUID, hasar: HasarKaydi) {
        if let aracIndex = araclar.firstIndex(where: { $0.id == aracId }),
           let hasarIndex = araclar[aracIndex].hasarKayitlari.firstIndex(where: { $0.id == hasar.id }) {
            araclar[aracIndex].hasarKayitlari[hasarIndex] = hasar
            firebaseService.updateArac(araclar[aracIndex]) { error in
                if let error = error {
                    print("❌ Hasar güncellenemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Hasar güncellendi")
                    HapticManager.shared.success()  // SUCCESS HAPTIC
                }
            }
            activityEkle(.hasarGuncellendi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[aracIndex].plakaFormatli)
        }
    }
    
    func hasarSil(aracId: UUID, hasarId: UUID) {
        if let aracIndex = araclar.firstIndex(where: { $0.id == aracId }),
           let hasarIndex = araclar[aracIndex].hasarKayitlari.firstIndex(where: { $0.id == hasarId }) {
            let hasar = araclar[aracIndex].hasarKayitlari[hasarIndex]
            
            // Fotoğrafları sil
            let imageManager = FirebaseImageManager.shared
            for fotoURL in hasar.fotograflar {
                imageManager.deleteImage(fotoURL)
            }
            
            araclar[aracIndex].hasarKayitlari.remove(at: hasarIndex)
            firebaseService.updateArac(araclar[aracIndex]) { error in
                if let error = error {
                    print("❌ Hasar silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Hasar silindi")
                }
            }
            activityEkle(.hasarSilindi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[aracIndex].plakaFormatli)
        }
    }
    
    // MARK: - Servis İşlemleri
    // Servis Ekle
    func servisEkle(_ servis: Servis) {
        servisler.append(servis)
        
        let servisKaydi = ServisKaydi(
            aracId: servis.aracId,
            servisTuru: servis.servisFirmaAdi,
            aciklama: servis.aciklama,
            tarih: servis.gonderilmeTarihi,
            ucret: 0
        )
        
        firebaseService.saveServis(servisKaydi) { error in
            if let error = error {
                print("❌ Servis kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ Servis kaydedildi")
                HapticManager.shared.success()  // SUCCESS HAPTIC
            }
        }
        activityEkle(.servisEklendi, aciklama: "\(servis.aracPlaka) - \(servis.servisFirmaAdi)", aracPlaka: servis.aracPlaka)
    }
    
    func servisGuncelle(_ servis: Servis) {
        if let index = servisler.firstIndex(where: { $0.id == servis.id }) {
            servisler[index] = servis
            print("✅ Servis güncellendi")
        }
    }
    
    func servisSil(_ servis: Servis) {
        if let index = servisler.firstIndex(where: { $0.id == servis.id }) {
            servisler.remove(at: index)
            print("✅ Servis silindi")
        }
    }
    
    func aracServisleri(aracId: UUID) -> [ServisKaydi] {
        return servisler.filter { $0.aracId == aracId }.map { servis in
            ServisKaydi(
                aracId: servis.aracId,
                servisTuru: servis.servisFirmaAdi,
                aciklama: servis.aciklama,
                tarih: servis.gonderilmeTarihi,
                ucret: 0
            )
        }
    }
    
    // MARK: - İade İşlemleri
    // İade Ekle
    func iadeEkle(_ iade: IadeIslemi) {
        iadeIslemleri.append(iade)
        firebaseService.saveIadeIslemi(iade) { error in
            if let error = error {
                print("❌ İade kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ İade kaydedildi: \(iade.aracPlaka)")
                HapticManager.shared.success()  // SUCCESS HAPTIC
            }
        }
        activityEkle(.iadeYapildi, aciklama: "\(iade.aracPlaka) - İade tamamlandı", aracPlaka: iade.aracPlaka)
    }
    
    func iadeSil(_ iade: IadeIslemi) {
        if let index = iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
            iadeIslemleri.remove(at: index)
            
            let imageManager = FirebaseImageManager.shared
            for foto in iade.fotograflar {
                imageManager.deleteImage(foto)
            }
            
            firebaseService.deleteIadeIslemi(iade) { error in
                if let error = error {
                    print("❌ İade silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ İade silindi")
                }
            }
        }
    }
    
    func iadeleriYenile() {
        firebaseService.loadIadeIslemleri { [weak self] (iadeler: [IadeIslemi]?, error: Error?) in
            if let error = error {
                print("❌ İadeler yüklenemedi: \(error.localizedDescription)")
            } else if let iadeler = iadeler {
                DispatchQueue.main.async {
                    self?.iadeIslemleri = iadeler
                    print("✅ İadeler manuel yenilendi: \(iadeler.count) adet")
                }
            }
        }
    }
    
    // MARK: - Servis Firma İşlemleri
    func servisFirmaEkle(_ firma: ServisFirma) {
        servisFirmalari.append(firma)
        firebaseService.saveServisFirmasi(firma) { error in
            if let error = error {
                print("❌ Servis firması kaydedilemedi: \(error.localizedDescription)")
            } else {
                print("✅ Servis firması kaydedildi: \(firma.ad)")
            }
        }
    }
    
    func servisFirmaGuncelle(_ firma: ServisFirma) {
        if let index = servisFirmalari.firstIndex(where: { $0.id == firma.id }) {
            servisFirmalari[index] = firma
            firebaseService.updateServisFirmasi(firma) { error in
                if let error = error {
                    print("❌ Servis firması güncellenemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Servis firması güncellendi: \(firma.ad)")
                }
            }
        }
    }
    
    func servisFirmaSil(_ firma: ServisFirma) {
        if let index = servisFirmalari.firstIndex(where: { $0.id == firma.id }) {
            servisFirmalari.remove(at: index)
            firebaseService.deleteServisFirmasi(firma) { error in
                if let error = error {
                    print("❌ Servis firması silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Servis firması silindi")
                }
            }
        }
    }
    
    // MARK: - Activity İşlemleri
    func activityEkle(_ tip: ActivityType, aciklama: String, aracPlaka: String? = nil, detayliAciklama: String? = nil) {
        let activity = Activity(
            tip: tip,
            aciklama: aciklama,
            tarih: Date(),
            aracPlaka: aracPlaka,
            detayliAciklama: detayliAciklama
        )
        activities.insert(activity, at: 0)
        
        firebaseService.saveActivity(activity) { error in
            if let error = error {
                print("❌ Aktivite kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Kategori İşlemleri
    // MARK: - Kategori İşlemleri
    func kategoriEkle(_ kategori: String) {
        if !kategoriler.contains(kategori) {
            kategoriler.append(kategori)
            kategoriler.sort()
        }
    }
    
    // MARK: - Computed Properties (Dashboard için)
    var damagedCarsCount: Int {
        araclar.filter { !$0.hasarKayitlari.isEmpty }.count
    }

    var availableCarsCount: Int {
        araclar.filter { $0.hasarKayitlari.isEmpty }.count
    }

    var toplamIadeSayisi: Int {
        iadeIslemleri.count
    }

    var aktifServisSayisi: Int {
        servisler.filter { $0.durum == .serviste }.count
    }

    var tamamlananServisSayisi: Int {
        servisler.filter { $0.durum == .tamamlandi }.count
    }

    var iptalServisSayisi: Int {
        servisler.filter { $0.durum == .iptal }.count
    }

    var vignetteOlanAraclar: Int {
        araclar.filter { $0.vignetteVar }.count
    }
}
