import Foundation
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

class AracViewModel: ObservableObject {
    @Published var araclar: [Arac] = []
    @Published var servisler: [Servis] = []
    @Published var iadeIslemleri: [IadeIslemi] = []
    @Published var exitIslemleri: [ExitIslemi] = []
    @Published var activities: [Activity] = []
    @Published var servisFirmalari: [ServisFirma] = []
    @Published var officeOperations: [OfficeOperation] = []
    @Published var officeReturns: [OfficeReturn] = []
    @Published var workSchedules: [WorkSchedule] = []
    @Published var vacationTimes: [VacationTime] = []
    @Published var kategoriler: [String] = ["A", "B", "D", "F", "H", "J", "L", "M", "MB", "MC", "N", "R", "S", "T", "U", "V", "X", "Y", "Z"]
    
    // Loading states for user feedback
    @Published var isSavingArac = false
    @Published var isUpdatingArac = false
    @Published var isDeletingArac = false
    
    private let firebaseService: FirebaseService
    private var cancellables = Set<AnyCancellable>()
    var authManager: AuthenticationManager?
    
    // Performance optimization for iOS 26
    private var debounceTimer: Timer?
    private var pendingUpdates: Set<String> = []
    
    // Listener cleanup
    private var hasPerformedHasarFix = false
    
    // Retry manager
    private let retryManager = RetryManager.shared
    
    // Firebase listeners
    private var exitIslemleriListener: ListenerRegistration?
    
    deinit {
        // Cleanup listeners
        exitIslemleriListener?.remove()
        exitIslemleriListener = nil
        // Cleanup timers
        // Cleanup timers
        debounceTimer?.invalidate()
        pendingUpdates.removeAll()
        cancellables.removeAll()
        print("🧹 AracViewModel deinitialized")
    }
    
    init() {
        self.firebaseService = FirebaseService.shared
        araclariYukle()
        servisleriYukle()
        iadeleriYukle()
        exitleriYukle()
        activitiesYukle()
        servisFirmalariYukle()
        // officeOperationsYukle() - Removed: observeOfficeOperations listener already loads data on first call
        officeReturnsYukle()
        workSchedulesYukle()
        vacationTimesYukle()
        setupRealtimeListeners()
        
        // Track app initialization
        AnalyticsManager.shared.trackScreenView("App Initialized")
    }
    
    // MARK: - Real-time Firebase Listeners
    func setupRealtimeListeners() {
        firebaseService.observeIadeIslemleri { [weak self] (iadeler: [IadeIslemi]) in
            self?.debouncedUpdate(key: "iadeIslemleri") {
                self?.iadeIslemleri = iadeler
                print("✅ İade işlemleri real-time güncellendi: \(iadeler.count) adet")
            }
        }
        
        exitIslemleriListener = firebaseService.observeExitIslemleri { [weak self] (exitler: [ExitIslemi]?, error: Error?) in
            if let error = error {
                print("❌ Exit işlemleri real-time listener hatası: \(error.localizedDescription)")
            } else if let exitler = exitler {
                self?.debouncedUpdate(key: "exitIslemleri") {
                    self?.exitIslemleri = exitler
                    print("✅ Exit işlemleri real-time güncellendi: \(exitler.count) adet")
                }
            }
        }
        
        firebaseService.observeAraclar { [weak self] (araclar: [Arac]) in
            self?.debouncedUpdate(key: "araclar") {
                // Fix missing aracId in damage records (only on first load)
                var fixedAraclar = araclar
                if !(self?.hasPerformedHasarFix ?? true) {
                    for i in 0..<fixedAraclar.count {
                        for j in 0..<fixedAraclar[i].hasarKayitlari.count {
                            // If aracId is empty UUID, set it to vehicle's ID
                            if fixedAraclar[i].hasarKayitlari[j].aracId == UUID() {
                                fixedAraclar[i].hasarKayitlari[j].aracId = fixedAraclar[i].id
                            }
                        }
                    }
                    self?.hasPerformedHasarFix = true
                }
                self?.araclar = fixedAraclar
                print("✅ Araçlar real-time güncellendi: \(araclar.count) adet")
            }
        }
        
        firebaseService.observeOfficeOperations { [weak self] (operations: [OfficeOperation]) in
            self?.debouncedUpdate(key: "officeOperations") {
                self?.officeOperations = operations
                print("✅ Office operations real-time güncellendi: \(operations.count) adet")
            }
        }
        
        firebaseService.observeOfficeReturns { [weak self] (returns: [OfficeReturn]) in
            self?.debouncedUpdate(key: "officeReturns") {
                self?.officeReturns = returns
                print("✅ Office returns real-time güncellendi: \(returns.count) adet")
            }
        }
        
        // Observe current week's schedules
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        firebaseService.observeWorkSchedules(weekStartDate: weekStart) { [weak self] (schedules: [WorkSchedule]) in
            self?.debouncedUpdate(key: "workSchedules") {
                self?.workSchedules = schedules
                print("✅ Work schedules real-time güncellendi: \(schedules.count) adet")
            }
        }
        
        firebaseService.observeVacationTimes { [weak self] (vacationTimes: [VacationTime]) in
            self?.debouncedUpdate(key: "vacationTimes") {
                self?.vacationTimes = vacationTimes
                print("✅ Vacation times real-time güncellendi: \(vacationTimes.count) adet")
            }
        }
    }
    
    // MARK: - Performance Optimization
    private let performanceOptimizer = PerformanceOptimizer.shared
    
    private func debouncedUpdate(key: String, update: @escaping () -> Void) {
        pendingUpdates.insert(key)
        
        // Use PerformanceOptimizer for better debouncing
        performanceOptimizer.debounce(identifier: key, delay: 0.3) { [weak self] in
            DispatchQueue.main.async {
                update()
                self?.pendingUpdates.removeAll()
            }
        }
    }
    
    // Optimized batch update
    private func batchUpdate<T>(items: [T], operation: @escaping (T) -> Void, completion: @escaping () -> Void) {
        performanceOptimizer.performBatch(
            items: items,
            maxConcurrent: 3,
            operation: operation,
            completion: completion
        )
    }
    
    // MARK: - Initial Loading Functions
    func araclariYukle() {
        // Check cache first
        let cacheKey = "araclar_cache"
        if let cached = performanceOptimizer.cachedData(forKey: cacheKey) as? [Arac] {
            self.araclar = cached
            print("✅ Araçlar cache'den yüklendi: \(cached.count) adet")
        }
        
        // Load from Firebase in background
        firebaseService.loadAraclar { [weak self] (araclar: [Arac]?, error: Error?) in
            if let error = error {
                print("❌ Araçlar yüklenemedi: \(error.localizedDescription)")
            } else if let araclar = araclar {
                DispatchQueue.main.async {
                    self?.araclar = araclar
                    // Cache the result
                    self?.performanceOptimizer.cacheData(araclar as AnyObject, forKey: cacheKey)
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
                        // Find vehicle and get its plate
                        let arac = self.araclar.first(where: { $0.id == kayit.aracId })
                        let plaka = arac?.plakaFormatli ?? ""
                        
                        // Convert status
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
                        
                        // Convert service reasons
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
    
    func exitleriYukle() {
        firebaseService.loadExitIslemleri { [weak self] (exitler: [ExitIslemi]?, error: Error?) in
            if let error = error {
                print("❌ Exit işlemleri yüklenemedi: \(error.localizedDescription)")
            } else if let exitler = exitler {
                DispatchQueue.main.async {
                    self?.exitIslemleri = exitler
                    print("✅ Exit işlemleri yüklendi: \(exitler.count) adet")
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
    
    func officeReturnsYukle() {
        firebaseService.loadOfficeReturns { [weak self] (returns: [OfficeReturn]?, error: Error?) in
            if let error = error {
                print("❌ Office returns yüklenemedi: \(error.localizedDescription)")
            } else if let returns = returns {
                DispatchQueue.main.async {
                    self?.officeReturns = returns
                    print("✅ Office returns yüklendi: \(returns.count) adet")
                }
            }
        }
    }
    
    func vacationTimesYukle() {
        firebaseService.loadVacationTimes { [weak self] vacationTimes, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Vacation times yüklenemedi: \(error.localizedDescription)")
                } else if let vacationTimes = vacationTimes {
                    self?.vacationTimes = vacationTimes
                    print("✅ Vacation times yüklendi: \(vacationTimes.count) adet")
                }
            }
        }
    }
    
    func workSchedulesYukle() {
        // Load all work schedules (not just current week) for accurate employee count
        firebaseService.loadWorkSchedules(weekStartDate: nil) { [weak self] (schedules: [WorkSchedule]?, error: Error?) in
            if let error = error {
                print("❌ Work schedules yüklenemedi: \(error.localizedDescription)")
            } else if let schedules = schedules {
                DispatchQueue.main.async {
                    self?.workSchedules = schedules
                    print("✅ Work schedules yüklendi: \(schedules.count) adet")
                }
            }
        }
    }
    
    // MARK: - Work Schedule Operations
    
    func workScheduleKaydet(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        firebaseService.saveWorkSchedule(schedule) { [weak self] error in
            if let error = error {
                ErrorManager.shared.showError(error, context: "Save Work Schedule")
                completion(error)
            } else {
                // Reload schedules after save
                self?.workSchedulesYukle()
                ToastManager.shared.show("✓ Schedule saved", type: .success)
                
                // Track analytics
                AnalyticsManager.shared.trackWorkScheduleCreated()
                
                completion(nil)
            }
        }
    }
    
    func workScheduleGuncelle(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        firebaseService.updateWorkSchedule(schedule) { [weak self] error in
            if let error = error {
                ErrorManager.shared.showError(error, context: "Update Work Schedule")
                completion(error)
            } else {
                self?.workSchedulesYukle()
                ToastManager.shared.show("✓ Schedule updated", type: .success)
                
                // Track analytics
                AnalyticsManager.shared.trackWorkScheduleUpdated()
                
                completion(nil)
            }
        }
    }
    
    func workScheduleSil(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        firebaseService.deleteWorkSchedule(schedule) { [weak self] error in
            if let error = error {
                ErrorManager.shared.showError(error, context: "Delete Work Schedule")
                completion(error)
            } else {
                self?.workSchedules.removeAll { $0.id == schedule.id }
                ToastManager.shared.show("✓ Schedule deleted", type: .success)
                
                // Track analytics
                AnalyticsManager.shared.trackWorkScheduleDeleted()
                
                completion(nil)
            }
        }
    }
    
    // MARK: - Vehicle Operations
    func aracEkle(_ arac: Arac, completion: ((Bool) -> Void)? = nil) {
        // Optimistic update - add to local array immediately
        araclar.append(arac)
        
        // Set loading state and provide haptic feedback
        isSavingArac = true
        HapticManager.shared.medium()
        
        firebaseService.saveArac(arac) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSavingArac = false
                
                if let error = error {
                    // Rollback optimistic update on error
                    self.araclar.removeAll { $0.id == arac.id }
                    print("❌ Araç kaydedilemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Vehicle Save")
                    HapticManager.shared.error()
                    completion?(false)
                } else {
                    print("✅ Araç kaydedildi: \(arac.plakaFormatli)")
                    ToastManager.shared.show("✓ Vehicle \(arac.plakaFormatli) saved", type: .success)
                    HapticManager.shared.success()
                    
                    // Track analytics
                    AnalyticsManager.shared.trackVehicleCreated(vehiclePlate: arac.plaka, category: arac.kategori)
                    
                    // Award points for vehicle record
                    GamificationManager.shared.awardPoints(for: .vehicleRecord) { success, points in
                        if success {
                            print("🎮 Awarded \(points) points for vehicle record")
                        }
                    }
                    
                    self.activityEkle(.aracEklendi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
                    completion?(true)
                }
            }
        }
    }

    func aracGuncelle(_ arac: Arac, completion: ((Bool) -> Void)? = nil) {
        guard let index = araclar.firstIndex(where: { $0.id == arac.id }) else {
            ErrorManager.shared.showError(message: "Vehicle not found")
            completion?(false)
            return
        }
        
        // Store old value for rollback
        let oldArac = araclar[index]
        
        // Optimistic update
        araclar[index] = arac
        
        // Set loading state and provide haptic feedback
        isUpdatingArac = true
        HapticManager.shared.medium()
        
        firebaseService.updateArac(arac) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingArac = false
                
                if let error = error {
                    // Rollback optimistic update on error
                    self.araclar[index] = oldArac
                    print("❌ Araç güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Vehicle Update")
                    HapticManager.shared.error()
                    completion?(false)
                } else {
                    print("✅ Araç güncellendi: \(arac.plakaFormatli)")
                    ToastManager.shared.show("✓ Vehicle \(arac.plakaFormatli) updated", type: .success)
                    HapticManager.shared.success()
                    
                    // Track analytics
                    AnalyticsManager.shared.trackVehicleUpdated(vehiclePlate: arac.plaka)
                    
                    completion?(true)
                }
            }
        }
    }
    
    func aracSil(_ arac: Arac, completion: ((Bool) -> Void)? = nil) {
        guard let index = araclar.firstIndex(where: { $0.id == arac.id }) else {
            ErrorManager.shared.showError(message: "Vehicle not found")
            completion?(false)
            return
        }
        
        // Revoke points if createdBy exists
        if let createdBy = arac.createdBy {
            GamificationManager.shared.revokePoints(for: .vehicleRecord, userId: createdBy) { success, points in
                if success {
                    print("🎮 Revoked \(points) points for deleted vehicle record")
                }
            }
        }
        
        // Store for rollback
        let aracToDelete = araclar[index]
        
        // Optimistic update
        araclar.remove(at: index)
        
        // Set loading state and provide haptic feedback
        isDeletingArac = true
        HapticManager.shared.medium()
        
        // Delete images from cache
        let imageManager = CachedImageManager.shared
        for hasar in arac.hasarKayitlari {
            for fotoURL in hasar.fotograflar {
                imageManager.deleteImage(fotoURL)
            }
        }
        
        firebaseService.deleteArac(id: arac.id) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDeletingArac = false
                
                if let error = error {
                    // Rollback optimistic update on error
                    self.araclar.insert(aracToDelete, at: index)
                    print("❌ Araç silinemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Vehicle Delete")
                    HapticManager.shared.error()
                    completion?(false)
                } else {
                    print("✅ Araç silindi: \(arac.plakaFormatli)")
                    ToastManager.shared.show("✓ Vehicle \(arac.plakaFormatli) deleted", type: .success)
                    HapticManager.shared.success()
                    
                    // Track analytics
                    AnalyticsManager.shared.trackVehicleDeleted(vehiclePlate: arac.plaka)
                    
                    self.activityEkle(.aracSilindi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
                    completion?(true)
                }
            }
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
    
    // MARK: - Damage Operations
    func hasarEkle(aracId: UUID, hasar: HasarKaydi) {
        if let index = araclar.firstIndex(where: { $0.id == aracId }) {
            araclar[index].hasarKayitlari.append(hasar)
            firebaseService.updateArac(araclar[index]) { error in
                if let error = error {
                    print("❌ Hasar eklenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Damage Save")
                } else {
                    print("✅ Hasar eklendi")
                    ErrorManager.shared.showSuccess("Damage record saved successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackDamageRecorded(vehiclePlate: self.araclar[index].plaka, resCode: hasar.resKodu)
                    
                    // Award points for damage record
                    GamificationManager.shared.awardPoints(for: .damageRecord) { success, points in
                        if success {
                            print("🎮 Awarded \(points) points for damage record")
                        }
                    }
                }
            }
            activityEkle(.hasarEklendi, aciklama: "\(araclar[index].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[index].plakaFormatli)
        }
    }

    func hasarGuncelle(aracId: UUID, hasar: HasarKaydi) {
        print("🔄 Hasar güncelleniyor - ID: \(hasar.id.uuidString), Status: \(hasar.status.rawValue), RES: \(hasar.resKodu)")
        
        guard let aracIndex = araclar.firstIndex(where: { $0.id == aracId }) else {
            print("❌ Araç bulunamadı: \(aracId.uuidString)")
            ErrorManager.shared.showError(message: "Vehicle not found")
            return
        }
        
        // Always update Firebase, even if hasar not found in local array
        var updatedArac = araclar[aracIndex]
        
        // Update or add hasar in local array
        if let hasarIndex = updatedArac.hasarKayitlari.firstIndex(where: { $0.id == hasar.id }) {
            updatedArac.hasarKayitlari[hasarIndex] = hasar
            print("✅ Local array'de hasar bulundu ve güncellendi")
        } else {
            // If not found, add it (might be from another device)
            updatedArac.hasarKayitlari.append(hasar)
            print("⚠️ Hasar local array'de bulunamadı, eklendi")
        }
        
        // Save to Firebase
        firebaseService.updateArac(updatedArac) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("❌ Hasar güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Damage Update")
                } else {
                    // Update local array
                    self.araclar[aracIndex] = updatedArac
                    print("✅ Hasar Firebase'e kaydedildi: \(hasar.resKodu), Status: \(hasar.status.rawValue)")
                    ErrorManager.shared.showSuccess("Damage record updated successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackDamageUpdated(vehiclePlate: self.araclar[aracIndex].plaka, resCode: hasar.resKodu)
                }
            }
        }
        
        // Add activity
        activityEkle(.hasarGuncellendi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu) (Status: \(hasar.status.rawValue))", aracPlaka: araclar[aracIndex].plakaFormatli)
    }
    
    func hasarSil(aracId: UUID, hasarId: UUID) {
        if let aracIndex = araclar.firstIndex(where: { $0.id == aracId }),
           let hasarIndex = araclar[aracIndex].hasarKayitlari.firstIndex(where: { $0.id == hasarId }) {
            let hasar = araclar[aracIndex].hasarKayitlari[hasarIndex]
            
            // Revoke points if createdBy exists
            if let createdBy = hasar.createdBy {
                GamificationManager.shared.revokePoints(for: .damageRecord, userId: createdBy) { success, points in
                    if success {
                        print("🎮 Revoked \(points) points for deleted damage record")
                    }
                }
            }
            
            let imageManager = CachedImageManager.shared
            for fotoURL in hasar.fotograflar {
                imageManager.deleteImage(fotoURL)
            }
            
            araclar[aracIndex].hasarKayitlari.remove(at: hasarIndex)
            firebaseService.updateArac(araclar[aracIndex]) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Hasar silinemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Damage Delete")
                } else {
                    print("✅ Hasar silindi")
                    ErrorManager.shared.showSuccess("Damage record deleted successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackDamageDeleted(vehiclePlate: self.araclar[aracIndex].plaka, resCode: hasar.resKodu)
                }
            }
            activityEkle(.hasarSilindi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[aracIndex].plakaFormatli)
        }
    }
    
    // MARK: - Service Operations
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
                ErrorManager.shared.showError(error, context: "Service Save")
            } else {
                print("✅ Servis kaydedildi")
                ErrorManager.shared.showSuccess("Service record saved successfully")
                
                // Track analytics
                AnalyticsManager.shared.trackServiceRecorded(vehiclePlate: servis.aracPlaka, serviceType: servis.servisFirmaAdi)
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
                    ErrorManager.shared.showError(error, context: "Service Update")
                } else {
                    print("✅ Servis güncellendi")
                    HapticManager.shared.success()
                    
                    // Track analytics
                    AnalyticsManager.shared.trackServiceUpdated(vehiclePlate: servis.aracPlaka, serviceType: servis.servisFirmaAdi)
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
                    
                    // Track analytics
                    AnalyticsManager.shared.trackServiceDeleted(vehiclePlate: servis.aracPlaka, serviceType: servis.servisFirmaAdi)
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
    
    // MARK: - Return Operations
    func iadeEkle(_ iade: IadeIslemi) {
        iadeIslemleri.append(iade)
        firebaseService.saveIadeIslemi(iade) { error in
            if let error = error {
                print("❌ İade kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Return Save")
            } else {
                print("✅ İade kaydedildi: \(iade.aracPlaka)")
                ErrorManager.shared.showSuccess("Return record for \(iade.aracPlaka) saved successfully")
                
                // Track analytics
                AnalyticsManager.shared.trackReturnCreated(returnType: iade.status.rawValue, amount: 0) // Amount not available in IadeIslemi
                
                // Award points for return operation
                GamificationManager.shared.awardPoints(for: .returnOperation) { success, points in
                    if success {
                        print("🎮 Awarded \(points) points for return operation")
                    }
                }
            }
        }
        activityEkle(.iadeYapildi, aciklama: "\(iade.aracPlaka) - İade tamamlandı", aracPlaka: iade.aracPlaka)
    }
    
    func iadeGuncelle(_ iade: IadeIslemi) {
        print("🔄 İade güncelleniyor - ID: \(iade.id.uuidString), Status: \(iade.status.rawValue)")
        
        // Always save to Firebase, even if not found in local array
        firebaseService.saveIadeIslemi(iade) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ İade güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Return Update")
                } else {
                    print("✅ İade Firebase'e kaydedildi: \(iade.aracPlaka), Status: \(iade.status.rawValue)")
                    
                    // Update local array if found
                    if let index = self?.iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
                        self?.iadeIslemleri[index] = iade
                        print("✅ Local array güncellendi")
                    } else {
                        // If not found in local array, add it (might be a new item from another device)
                        self?.iadeIslemleri.append(iade)
                        print("⚠️ İade local array'de bulunamadı, eklendi")
                    }
                    
                    ErrorManager.shared.showSuccess("Return record for \(iade.aracPlaka) updated successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnUpdated(returnType: iade.status.rawValue, amount: 0)
                }
            }
        }
        
        // Add activity
        activityEkle(.iadeYapildi, aciklama: "\(iade.aracPlaka) - İade güncellendi (Status: \(iade.status.rawValue))", aracPlaka: iade.aracPlaka)
    }
    
    func iadeSil(_ iade: IadeIslemi) {
        if let index = iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
            // Revoke points if createdBy exists
            if let createdBy = iade.createdBy {
                GamificationManager.shared.revokePoints(for: .returnOperation, userId: createdBy) { success, points in
                    if success {
                        print("🎮 Revoked \(points) points for deleted return operation")
                    }
                }
            }
            
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
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnDeleted(returnType: iade.status.rawValue)
                }
            }
        }
    }
    
    // MARK: - Exit Operations
    
    func exitEkle(_ exit: ExitIslemi) {
        exitIslemleri.append(exit)
        firebaseService.saveExitIslemi(exit) { error in
            if let error = error {
                print("❌ Exit kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Exit Save")
            } else {
                print("✅ Exit kaydedildi: \(exit.aracPlaka)")
                ErrorManager.shared.showSuccess("Exit record for \(exit.aracPlaka) saved successfully")
                
                // Track analytics
                AnalyticsManager.shared.trackReturnCreated(returnType: exit.status.rawValue, amount: 0)
                
                // Award points for check out operation
                GamificationManager.shared.awardPoints(for: .checkOut) { success, points in
                    if success {
                        print("🎮 Awarded \(points) points for check out operation")
                    }
                }
            }
        }
        activityEkle(.iadeYapildi, aciklama: "\(exit.aracPlaka) - Exit tamamlandı", aracPlaka: exit.aracPlaka)
    }
    
    func exitGuncelle(_ exit: ExitIslemi) {
        print("🔄 Exit güncelleniyor - ID: \(exit.id.uuidString), Status: \(exit.status.rawValue)")
        
        // Always save to Firebase, even if not found in local array
        firebaseService.saveExitIslemi(exit) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Exit güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Exit Update")
                } else {
                    print("✅ Exit Firebase'e kaydedildi: \(exit.aracPlaka), Status: \(exit.status.rawValue)")
                    
                    // Update local array if found
                    if let index = self?.exitIslemleri.firstIndex(where: { $0.id == exit.id }) {
                        self?.exitIslemleri[index] = exit
                        print("✅ Local array güncellendi")
                    } else {
                        // If not found in local array, add it (might be a new item from another device)
                        self?.exitIslemleri.append(exit)
                        print("⚠️ Exit local array'de bulunamadı, eklendi")
                    }
                    
                    ErrorManager.shared.showSuccess("Exit record for \(exit.aracPlaka) updated successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnUpdated(returnType: exit.status.rawValue, amount: 0)
                }
            }
        }
        
        // Add activity
        activityEkle(.iadeYapildi, aciklama: "\(exit.aracPlaka) - Exit güncellendi (Status: \(exit.status.rawValue))", aracPlaka: exit.aracPlaka)
    }
    
    func exitSil(_ exit: ExitIslemi) {
        if let index = exitIslemleri.firstIndex(where: { $0.id == exit.id }) {
            // Revoke points if createdBy exists
            if let createdBy = exit.createdBy {
                GamificationManager.shared.revokePoints(for: .checkOut, userId: createdBy) { success, points in
                    if success {
                        print("🎮 Revoked \(points) points for deleted check out operation")
                    }
                }
            }
            
            exitIslemleri.remove(at: index)
            
            let imageManager = CachedImageManager.shared
            for foto in exit.fotograflar {
                imageManager.deleteImage(foto)
            }
            
            firebaseService.deleteExitIslemi(exit) { error in
                if let error = error {
                    print("❌ Exit silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Exit silindi")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnDeleted(returnType: exit.status.rawValue)
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
    
    // MARK: - Office Operations
    func officeOperationEkle(_ operation: OfficeOperation) {
        // Don't append to array - observeOfficeOperations listener will update it automatically
        firebaseService.saveOfficeOperation(operation) { error in
            if let error = error {
                print("❌ Office operation kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Office Operation Save")
            } else {
                print("✅ Office operation kaydedildi - listener will update the array automatically")
                ErrorManager.shared.showSuccess("Office operation saved successfully")
                
                // Track analytics
                AnalyticsManager.shared.trackOfficeOperationCreated(operationType: operation.type.rawValue, amount: operation.amount)
                
                // Award points for office operation
                GamificationManager.shared.awardPoints(for: .officeOperation) { success, points in
                    if success {
                        print("🎮 Awarded \(points) points for office operation")
                    }
                }
                
                // Add activity for office operation
                let aciklama = "\(operation.type.rawValue) - \(String(format: "%.2f CHF", operation.amount))"
                self.activityEkle(
                    .officeOperation,
                    aciklama: aciklama,
                    aracPlaka: operation.vehiclePlate,
                    detayliAciklama: operation.notes.isEmpty ? nil : operation.notes,
                    officeOperationId: operation.id
                )
            }
        }
    }
    
    func officeOperationGuncelle(_ operation: OfficeOperation, completion: ((Bool) -> Void)? = nil) {
        if let index = officeOperations.firstIndex(where: { $0.id == operation.id }) {
            // Store old value for rollback
            let oldOperation = officeOperations[index]
            
            // Optimistic update
            officeOperations[index] = operation
            
            // Update in Firebase
            firebaseService.updateOfficeOperation(operation) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        // Rollback optimistic update on error
                        self?.officeOperations[index] = oldOperation
                        print("❌ Office operation güncellenemedi: \(error.localizedDescription)")
                        ErrorManager.shared.showError(error, context: "Office Operation Update")
                        completion?(false)
                    } else {
                        print("✅ Office operation güncellendi")
                        ToastManager.shared.show("✓ Operation updated", type: .success)
                        
                        // Track analytics
                        AnalyticsManager.shared.trackOfficeOperationUpdated(operationType: operation.type.rawValue, amount: operation.amount)
                        
                        completion?(true)
                    }
                }
            }
        } else {
            ErrorManager.shared.showError(message: "Operation not found")
            completion?(false)
        }
    }
    
    func officeOperationSil(_ operation: OfficeOperation) {
        // Revoke points if createdBy exists
        if let createdBy = operation.createdBy {
            GamificationManager.shared.revokePoints(for: .officeOperation, userId: createdBy) { success, points in
                if success {
                    print("🎮 Revoked \(points) points for deleted office operation")
                }
            }
        }
        
        // Don't remove from array - observeOfficeOperations listener will update it automatically
        let imageManager = CachedImageManager.shared
        for foto in operation.photos {
            imageManager.deleteImage(foto)
        }
        
        firebaseService.deleteOfficeOperation(operation) { [weak self] error in
            if let error = error {
                print("❌ Office operation silinemedi: \(error.localizedDescription)")
            } else {
                print("✅ Office operation silindi - listener will update the array automatically")
                
                // Track analytics
                AnalyticsManager.shared.trackOfficeOperationDeleted(operationType: operation.type.rawValue)
                
                // Add activity for deleted office operation
                let aciklama = "\(operation.type.rawValue) - \(String(format: "%.2f CHF", operation.amount))"
                self?.activityEkle(
                    .officeOperationSilindi,
                    aciklama: aciklama,
                    aracPlaka: operation.vehiclePlate,
                    detayliAciklama: operation.notes.isEmpty ? nil : operation.notes,
                    officeOperationId: operation.id
                )
            }
        }
    }
    
    
    // MARK: - Office Returns
    func officeReturnEkle(_ returnOp: OfficeReturn) {
        officeReturns.append(returnOp)
        firebaseService.saveOfficeReturn(returnOp) { error in
            if let error = error {
                print("❌ Office return kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Office Return Save")
            } else {
                print("✅ Office return kaydedildi")
                ErrorManager.shared.showSuccess("Customer return saved successfully")
                
                // Track analytics
                AnalyticsManager.shared.trackReturnCreated(returnType: returnOp.reason.rawValue, amount: returnOp.amount)
            }
        }
    }
    
    func officeReturnGuncelle(_ returnOp: OfficeReturn) {
        if let index = officeReturns.firstIndex(where: { $0.id == returnOp.id }) {
            officeReturns[index] = returnOp
            firebaseService.updateOfficeReturn(returnOp) { error in
                if let error = error {
                    print("❌ Office return güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Office Return Update")
                } else {
                    print("✅ Office return güncellendi")
                    ErrorManager.shared.showSuccess("Customer return updated successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnUpdated(returnType: returnOp.reason.rawValue, amount: returnOp.amount)
                }
            }
        }
    }
    
    func officeReturnSil(_ returnOp: OfficeReturn) {
        if let index = officeReturns.firstIndex(where: { $0.id == returnOp.id }) {
            officeReturns.remove(at: index)
            
            let imageManager = CachedImageManager.shared
            for foto in returnOp.photos {
                imageManager.deleteImage(foto)
            }
            
            firebaseService.deleteOfficeReturn(returnOp) { error in
                if let error = error {
                    print("❌ Office return silinemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Office Return Delete")
                } else {
                    print("✅ Office return silindi")
                    ErrorManager.shared.showSuccess("Customer return deleted successfully")
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnDeleted(returnType: returnOp.reason.rawValue)
                }
            }
        }
    }
    
    // MARK: - Service Company Operations
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
    
    // MARK: - Activity Operations
    func activityEkle(_ tip: ActivityType, aciklama: String, aracPlaka: String? = nil, detayliAciklama: String? = nil, officeOperationId: UUID? = nil) {
        var kullaniciAdi: String?
        var kullaniciEmail: String?
        
        // Get user information
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
            kullaniciEmail: kullaniciEmail,
            officeOperationId: officeOperationId
        )
        activities.insert(activity, at: 0)
        
        firebaseService.saveActivity(activity) { error in
            if let error = error {
                print("❌ Aktivite kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Category Operations
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
    
    // MARK: - Today's Statistics
    var todayDamageReportsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return araclar.flatMap { $0.hasarKayitlari }
            .filter { hasar in
                hasar.tarih >= today && hasar.tarih < tomorrow
            }
            .count
    }
    
    var yesterdayDamageReportsCount: Int {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStart = calendar.startOfDay(for: yesterday)
        let yesterdayEnd = calendar.date(byAdding: .day, value: 1, to: yesterdayStart)!
        
        return araclar.flatMap { $0.hasarKayitlari }
            .filter { hasar in
                hasar.tarih >= yesterdayStart && hasar.tarih < yesterdayEnd
            }
            .count
    }
    
    var todayReportsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Today's damage reports
        let todayDamages = todayDamageReportsCount
        
        // Today's return reports
        let todayReturns = iadeIslemleri.filter { iade in
            iade.iadeTarihi >= today && iade.iadeTarihi < tomorrow
        }.count
        
        // Today's service records (using gonderilmeTarihi)
        let todayServices = servisler.filter { servis in
            servis.gonderilmeTarihi >= today && servis.gonderilmeTarihi < tomorrow
        }.count
        
        return todayDamages + todayReturns + todayServices
    }
    
    var todayReturnsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return iadeIslemleri.filter { iade in
            iade.iadeTarihi >= today && iade.iadeTarihi < tomorrow
        }.count
    }
    
    var damageReportsChangeMetric: String {
        let today = todayDamageReportsCount
        let yesterday = yesterdayDamageReportsCount
        
        if yesterday == 0 {
            return today > 0 ? "+\(today)" : "0"
        }
        
        let change = today - yesterday
        if change == 0 {
            return "0"
        } else if change > 0 {
            return "+\(change)"
        } else {
            return "\(change)"
        }
    }
    
    // MARK: - Vacation Times Management
    func saveVacationTime(_ vacationTime: VacationTime, completion: @escaping (Error?) -> Void) {
        firebaseService.saveVacationTime(vacationTime) { error in
            DispatchQueue.main.async {
                if error == nil {
                    // Reload vacation times after save
                    self.vacationTimesYukle()
                }
                completion(error)
            }
        }
    }
    
    func deleteVacationTime(_ vacationTime: VacationTime, completion: @escaping (Error?) -> Void) {
        firebaseService.deleteVacationTime(vacationTime) { error in
            DispatchQueue.main.async {
                if error == nil {
                    // Reload vacation times after delete
                    self.vacationTimesYukle()
                }
                completion(error)
            }
        }
    }
    
    // Check if current user can edit vacation times (only front@gmail.com)
    func isYaseminOrFrontUser() -> Bool {
        guard let userEmail = authManager?.currentUser?.email?.lowercased() else { return false }
        // Only front@gmail.com can edit
        return userEmail == "front@gmail.com"
    }
    
    // MARK: - Additional Sales Metrics
    func calculateAdditionalSalesDailyComparison() -> (amountChange: Double, countChange: Int, amountPercent: Double, countPercent: Double) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let yesterdayEnd = calendar.startOfDay(for: today)
        
        let todaySales = officeOperations.filter { op in
            op.type == .additionalSales && op.date >= today && op.date < tomorrow
        }
        let yesterdaySales = officeOperations.filter { op in
            op.type == .additionalSales && op.date >= yesterday && op.date < yesterdayEnd
        }
        
        let todayAmount = todaySales.reduce(0) { $0 + $1.amount }
        let yesterdayAmount = yesterdaySales.reduce(0) { $0 + $1.amount }
        let todayCount = todaySales.count
        let yesterdayCount = yesterdaySales.count
        
        let amountChange = todayAmount - yesterdayAmount
        let countChange = todayCount - yesterdayCount
        
        let amountPercent = yesterdayAmount > 0 ? (amountChange / yesterdayAmount) * 100 : (todayAmount > 0 ? 100 : 0)
        let countPercent = yesterdayCount > 0 ? (Double(countChange) / Double(yesterdayCount)) * 100 : (todayCount > 0 ? 100 : 0)
        
        return (amountChange, countChange, amountPercent, countPercent)
    }
    
    func calculateAdditionalSalesMonthlyComparison(selectedMonth: Date) -> (amountChange: Double, countChange: Int, amountPercent: Double, countPercent: Double) {
        let calendar = Calendar.current
        
        // Current month range
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let currentMonthStart = calendar.date(from: currentMonthComponents) ?? selectedMonth
        let currentMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: currentMonthStart) ?? selectedMonth
        
        // Previous month range
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? selectedMonth
        let previousMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: previousMonthStart) ?? selectedMonth
        
        let currentMonthSales = officeOperations.filter { op in
            op.type == .additionalSales && op.date >= currentMonthStart && op.date <= currentMonthEnd
        }
        let previousMonthSales = officeOperations.filter { op in
            op.type == .additionalSales && op.date >= previousMonthStart && op.date <= previousMonthEnd
        }
        
        let currentAmount = currentMonthSales.reduce(0) { $0 + $1.amount }
        let previousAmount = previousMonthSales.reduce(0) { $0 + $1.amount }
        let currentCount = currentMonthSales.count
        let previousCount = previousMonthSales.count
        
        let amountChange = currentAmount - previousAmount
        let countChange = currentCount - previousCount
        
        let amountPercent = previousAmount > 0 ? (amountChange / previousAmount) * 100 : (currentAmount > 0 ? 100 : 0)
        let countPercent = previousCount > 0 ? (Double(countChange) / Double(previousCount)) * 100 : (currentCount > 0 ? 100 : 0)
        
        return (amountChange, countChange, amountPercent, countPercent)
    }
    
    // MARK: - Office Operation Monthly Comparison
    func calculateOfficeOperationMonthlyComparison(operationType: OfficeOperationType, selectedMonth: Date) -> (amountChange: Double, countChange: Int, amountPercent: Double, countPercent: Double) {
        let calendar = Calendar.current
        
        // Current month range
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let currentMonthStart = calendar.date(from: currentMonthComponents) ?? selectedMonth
        let currentMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: currentMonthStart) ?? selectedMonth
        
        // Previous month range
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? selectedMonth
        let previousMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: previousMonthStart) ?? selectedMonth
        
        let currentMonthOps = officeOperations.filter { op in
            op.type == operationType && op.date >= currentMonthStart && op.date <= currentMonthEnd
        }
        let previousMonthOps = officeOperations.filter { op in
            op.type == operationType && op.date >= previousMonthStart && op.date <= previousMonthEnd
        }
        
        let currentAmount = currentMonthOps.reduce(0) { $0 + $1.amount }
        let previousAmount = previousMonthOps.reduce(0) { $0 + $1.amount }
        let currentCount = currentMonthOps.count
        let previousCount = previousMonthOps.count
        
        let amountChange = currentAmount - previousAmount
        let countChange = currentCount - previousCount
        
        let amountPercent = previousAmount > 0 ? (amountChange / previousAmount) * 100 : (currentAmount > 0 ? 100 : 0)
        let countPercent = previousCount > 0 ? (Double(countChange) / Double(previousCount)) * 100 : (currentCount > 0 ? 100 : 0)
        
        return (amountChange, countChange, amountPercent, countPercent)
    }
}

