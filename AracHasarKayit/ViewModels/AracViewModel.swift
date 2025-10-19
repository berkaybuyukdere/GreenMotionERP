import Foundation
import Combine
import UIKit
import FirebaseAuth

class AracViewModel: ObservableObject {
    @Published var araclar: [Arac] = []
    @Published var servisler: [Servis] = []
    @Published var iadeIslemleri: [IadeIslemi] = []
    @Published var activities: [Activity] = []
    @Published var servisFirmalari: [ServisFirma] = []
    @Published var officeOperations: [OfficeOperation] = []
    @Published var kategoriler: [String] = ["A", "B", "D", "F", "H", "J", "L", "M", "MB", "MC", "N", "R", "S", "T", "U", "V", "X", "Y", "Z"]

    private let firebaseService: FirebaseService
    private var cancellables = Set<AnyCancellable>()
    var authManager: AuthenticationManager?
    
    init() {
        self.firebaseService = FirebaseService.shared
        araclariYukle()
        servisleriYukle()
        iadeleriYukle()
        activitiesYukle()
        servisFirmalariYukle()
        officeOperationsYukle()
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
        
        firebaseService.observeOfficeOperations { [weak self] (operations: [OfficeOperation]) in
            DispatchQueue.main.async {
                self?.officeOperations = operations
                print("✅ Office operations real-time güncellendi: \(operations.count) adet")
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
                    guard let self = self else { return }
                    
                    self.servisler = servisKayitlari.compactMap { kayit in
                        // Aracı bul ve plakasını al
                        let arac = self.araclar.first(where: { $0.id == kayit.aracId })
                        let plaka = arac?.plakaFormatli ?? ""
                        
                        // Durumu dönüştür
                        let durum: Servis.ServisDurum
                        switch kayit.durum.lowercased() {
                        case "serviste":
                            durum = .serviste
                        case "tamamlandı", "tamamlandi":
                            durum = .tamamlandi
                        case "iptal":
                            durum = .iptal
                        default:
                            durum = .serviste
                        }
                        
                        // Servis nedenlerini dönüştür
                        let servisNedenleri = kayit.servisNedenleri.compactMap { nedenStr -> Servis.ServisNeden? in
                            return Servis.ServisNeden.allCases.first(where: { $0.rawValue == nedenStr })
                        }
                        
                        return Servis(
                            id: kayit.id,
                            aracId: kayit.aracId,
                            aracPlaka: plaka,
                            servisFirmaId: nil,
                            servisFirmaAdi: kayit.servisTuru,
                            durum: durum,
                            gonderilmeTarihi: kayit.tarih,
                            teslimTarihi: kayit.teslimTarihi,
                            aciklama: kayit.aciklama,
                            servisNedenleri: servisNedenleri
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
    
    func officeOperationsYukle() {
        firebaseService.loadOfficeOperations { [weak self] (operations: [OfficeOperation]?, error: Error?) in
            if let error = error {
                print("❌ Office operations yüklenemedi: \(error.localizedDescription)")
            } else if let operations = operations {
                DispatchQueue.main.async {
                    self?.officeOperations = operations
                    print("✅ Office operations yüklendi: \(operations.count) adet")
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
                HapticManager.shared.success()
            }
        }
        activityEkle(.aracEklendi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
    }

    func aracGuncelle(_ arac: Arac) {
        if let index = araclar.firstIndex(where: { $0.id == arac.id }) {
            araclar[index] = arac
            firebaseService.updateArac(arac) { error in
                if let error = error {
                    print("❌ Araç güncellenemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Araç güncellendi: \(arac.plakaFormatli)")
                    HapticManager.shared.success()
                }
            }
        }
    }
    
    func aracSil(_ arac: Arac) {
        if let index = araclar.firstIndex(where: { $0.id == arac.id }) {
            araclar.remove(at: index)
            
            let imageManager = CachedImageManager.shared
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
                    HapticManager.shared.success()
                }
            }
            activityEkle(.hasarEklendi, aciklama: "\(araclar[index].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[index].plakaFormatli)
        }
    }

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
                    HapticManager.shared.success()
                }
            }
            activityEkle(.hasarGuncellendi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[aracIndex].plakaFormatli)
        }
    }
    
    func hasarSil(aracId: UUID, hasarId: UUID) {
        if let aracIndex = araclar.firstIndex(where: { $0.id == aracId }),
           let hasarIndex = araclar[aracIndex].hasarKayitlari.firstIndex(where: { $0.id == hasarId }) {
            let hasar = araclar[aracIndex].hasarKayitlari[hasarIndex]
            
            let imageManager = CachedImageManager.shared
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
    func servisEkle(_ servis: Servis) {
        servisler.append(servis)
        
        let servisKaydi = ServisKaydi(
            id: servis.id,
            aracId: servis.aracId,
            servisTuru: servis.servisFirmaAdi,
            aciklama: servis.aciklama,
            tarih: servis.gonderilmeTarihi,
            ucret: 0,
            teslimTarihi: servis.teslimTarihi,
            servisNedenleri: servis.servisNedenleri.map { $0.rawValue },
            durum: servis.durum.rawValue
        )
        
        firebaseService.saveServis(servisKaydi) { error in
            if let error = error {
                print("❌ Servis kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ Servis kaydedildi")
                HapticManager.shared.success()
            }
        }
        
        // ✅ Schedule service reminder if delivery date exists
        if let teslimTarihi = servis.teslimTarihi {
            NotificationManager.shared.scheduleServiceReminder(
                servisId: servis.id.uuidString,
                carPlate: servis.aracPlaka,
                serviceName: servis.servisFirmaAdi,
                deliveryDate: teslimTarihi
            )
            print("🔔 Service reminder scheduled for \(servis.aracPlaka)")
        }
        
        activityEkle(.servisEklendi, aciklama: "\(servis.aracPlaka) - \(servis.servisFirmaAdi)", aracPlaka: servis.aracPlaka)
    }
    
    func servisGuncelle(_ servis: Servis) {
        if let index = servisler.firstIndex(where: { $0.id == servis.id }) {
            let eskiServis = servisler[index]
            servisler[index] = servis
            
            // Save updated service to Firebase
            let servisKaydi = ServisKaydi(
                id: servis.id,
                aracId: servis.aracId,
                servisTuru: servis.servisFirmaAdi,
                aciklama: servis.aciklama,
                tarih: servis.gonderilmeTarihi,
                ucret: 0,
                teslimTarihi: servis.teslimTarihi,
                servisNedenleri: servis.servisNedenleri.map { $0.rawValue },
                durum: servis.durum.rawValue
            )
            
            firebaseService.saveServis(servisKaydi) { error in
                if let error = error {
                    print("❌ Servis güncellenemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Servis güncellendi")
                    HapticManager.shared.success()
                }
            }
            
            // Cancel old reminder if it existed
            if eskiServis.teslimTarihi != nil {
                NotificationManager.shared.cancelServiceReminder(servisId: eskiServis.id.uuidString)
            }
            
            // Schedule new reminder if delivery date exists
            if let teslimTarihi = servis.teslimTarihi {
                NotificationManager.shared.scheduleServiceReminder(
                    servisId: servis.id.uuidString,
                    carPlate: servis.aracPlaka,
                    serviceName: servis.servisFirmaAdi,
                    deliveryDate: teslimTarihi
                )
                print("🔔 Service reminder updated for \(servis.aracPlaka)")
            }
        }
    }
    
    func servisSil(_ servis: Servis) {
        if let index = servisler.firstIndex(where: { $0.id == servis.id }) {
            servisler.remove(at: index)
            
            // Delete from Firebase
            let servisKaydi = ServisKaydi(
                id: servis.id,
                aracId: servis.aracId,
                servisTuru: servis.servisFirmaAdi,
                aciklama: servis.aciklama,
                tarih: servis.gonderilmeTarihi,
                ucret: 0,
                teslimTarihi: servis.teslimTarihi,
                servisNedenleri: servis.servisNedenleri.map { $0.rawValue },
                durum: servis.durum.rawValue
            )
            
            firebaseService.deleteServis(servisKaydi) { error in
                if let error = error {
                    print("❌ Servis Firebase'den silinemedi: \(error.localizedDescription)")
                    HapticManager.shared.error()
                } else {
                    print("✅ Servis Firebase'den silindi")
                    HapticManager.shared.success()
                }
            }
            
            // Cancel reminder when service is deleted
            NotificationManager.shared.cancelServiceReminder(servisId: servis.id.uuidString)
            print("🔔 Service reminder cancelled for \(servis.aracPlaka)")
            
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
    func iadeEkle(_ iade: IadeIslemi) {
        iadeIslemleri.append(iade)
        firebaseService.saveIadeIslemi(iade) { error in
            if let error = error {
                print("❌ İade kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ İade kaydedildi: \(iade.aracPlaka)")
                HapticManager.shared.success()
            }
        }
        activityEkle(.iadeYapildi, aciklama: "\(iade.aracPlaka) - İade tamamlandı", aracPlaka: iade.aracPlaka)
    }
    
    func iadeSil(_ iade: IadeIslemi) {
        if let index = iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
            iadeIslemleri.remove(at: index)
            
            let imageManager = CachedImageManager.shared
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
    
    // MARK: - Office Operations İşlemleri
    func officeOperationEkle(_ operation: OfficeOperation) {
        officeOperations.append(operation)
        firebaseService.saveOfficeOperation(operation) { error in
            if let error = error {
                print("❌ Office operation kaydedilemedi: \(error.localizedDescription)")
                HapticManager.shared.error()
            } else {
                print("✅ Office operation kaydedildi")
                HapticManager.shared.success()
            }
        }
    }
    
    func officeOperationSil(_ operation: OfficeOperation) {
        if let index = officeOperations.firstIndex(where: { $0.id == operation.id }) {
            officeOperations.remove(at: index)
            
            let imageManager = CachedImageManager.shared
            for foto in operation.photos {
                imageManager.deleteImage(foto)
            }
            
            firebaseService.deleteOfficeOperation(operation) { error in
                if let error = error {
                    print("❌ Office operation silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Office operation silindi")
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
        var kullaniciAdi: String?
        var kullaniciEmail: String?
        
        // Kullanıcı bilgilerini al
        if let profile = authManager?.userProfile {
            kullaniciAdi = profile.fullName
            kullaniciEmail = profile.email
            print("✅ Activity with user: \(kullaniciAdi ?? "unknown")")
        } else if let user = Auth.auth().currentUser {
            kullaniciEmail = user.email
            print("⚠️ Activity without profile, using email: \(kullaniciEmail ?? "unknown")")
        } else {
            print("❌ Activity with no user info")
        }
        
        let activity = Activity(
            tip: tip,
            aciklama: aciklama,
            tarih: Date(),
            aracPlaka: aracPlaka,
            detayliAciklama: detayliAciklama,
            kullaniciAdi: kullaniciAdi,
            kullaniciEmail: kullaniciEmail
        )
        activities.insert(activity, at: 0)
        
        firebaseService.saveActivity(activity) { error in
            if let error = error {
                print("❌ Aktivite kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }
    
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
    
    // MARK: - Office Operations Statistics
    var totalCreditCardAmount: Double {
        officeOperations.filter { $0.type == .creditCard }.reduce(0) { $0 + $1.amount }
    }
    
    var totalPOSAmount: Double {
        officeOperations.filter { $0.type == .posClosing }.reduce(0) { $0 + $1.amount }
    }
    
    var totalFuelAmount: Double {
        officeOperations.filter { $0.type == .fuelReceipt }.reduce(0) { $0 + $1.amount }
    }
    
    var totalWashingAmount: Double {
        officeOperations.filter { $0.type == .washing }.reduce(0) { $0 + $1.amount }
    }
}
