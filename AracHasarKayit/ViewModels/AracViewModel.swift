import Foundation
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

class AracViewModel: ObservableObject {
    @Published var araclar: [Arac] = []
    /// Full vehicle list including soft-deleted ones — used only for aggregate reporting
    /// (damage counts etc.) to match the web dashboard which counts all vehicles' records.
    @Published var allVehiclesForReports: [Arac] = []
    @Published var servisler: [Servis] = []
    @Published var iadeIslemleri: [IadeIslemi] = []
    @Published var exitIslemleri: [ExitIslemi] = []
    @Published var activities: [Activity] = []
    @Published var servisFirmalari: [ServisFirma] = []
    @Published var officeOperations: [OfficeOperation] = []
    /// `franchises/{franchiseId}/garageServiceJobs` — external garage service sends (MVP).
    @Published var garageServiceJobs: [GarageServiceJob] = []
    @Published var officeReturns: [OfficeReturn] = []
    @Published var trafficAccidentContracts: [TrafficAccidentContract] = []
    @Published var workSchedules: [WorkSchedule] = []
    @Published var vacationTimes: [VacationTime] = []
    @Published var assistantCompanies: [AssistantCompany] = []
    /// Top-level damage records (new model). When non-empty, UI should prefer this over nested vehicle arrays.
    @Published var topLevelHasarKayitlari: [HasarKaydi] = []
    @Published var kategoriler: [String] = []
    @Published var returnEmailSentFallbackByReturnId: [String: Date] = [:]
    @Published var additionalSalesPeople: [String] = []
    /// Franchise display name loaded from Firestore franchises/{id}.name
    @Published var franchiseName: String = ""
    /// `garageBranches` (or `locations`) from the same `franchises/{id}` document — used by TR branch pickers and fleet import.
    @Published var franchiseGarageBranches: [FranchiseGarageBranch] = []
    /// Türkiye lokasyonları: `franchises` koleksiyonunda doküman ID’si `TR_` ile başlayan girişler (ör. `TR_NEVSEHIR`, `TR_SABIHAGOKCEN`).
    @Published var turkeyFranchiseLocationBranches: [FranchiseGarageBranch] = []
    
    // Loading states for user feedback
    @Published var isSavingArac = false
    @Published var isUpdatingArac = false
    @Published var isDeletingArac = false
    
    let firebaseService: FirebaseService
    private var cancellables = Set<AnyCancellable>()
    var authManager: AuthenticationManager?
    
    // Performance optimization for iOS 26
    private var debounceTimer: Timer?
    private var pendingUpdates: Set<String> = []
    
    // Listener cleanup
    private var hasPerformedHasarFix = false
    
    // Load generation counter - prevents stale async callbacks from overwriting data after resetData()
    private var loadGeneration: Int = 0
    
    // Retry manager
    private let retryManager = RetryManager.shared
    
    // Firebase listeners
    private var iadeIslemleriListener: ListenerRegistration?
    private var exitIslemleriListener: ListenerRegistration?
    private var assistantCompaniesListener: ListenerRegistration?
    private var araclarListener: ListenerRegistration?
    private var officeOperationsListener: ListenerRegistration?
    private var garageServiceJobsListener: ListenerRegistration?
    private var officeReturnsListener: ListenerRegistration?
    private var trafficAccidentContractsListener: ListenerRegistration?
    private var workSchedulesListener: ListenerRegistration?
    private var vacationTimesListener: ListenerRegistration?
    private var vehicleCategoriesListener: ListenerRegistration?
    private var hasarKayitlariTopLevelListener: ListenerRegistration?
    private var outgoingEmailsScopedListener: ListenerRegistration?
    private var additionalSalesPeopleListener: ListenerRegistration?
    
    // Track last user ID to detect user changes
    private var lastUserId: String?
    
    deinit {
        // Cleanup all listeners
        removeAllListeners()
        
        // Cleanup timers
        debounceTimer?.invalidate()
        pendingUpdates.removeAll()
        cancellables.removeAll()
        print("🧹 AracViewModel deinitialized")
    }
    
    // Track whether initial data load has happened
    private var hasLoadedInitialData = false
    
    // Ensure vehicle arrays never contain duplicate IDs (prevents SwiftUI ForEach warnings)
    private func uniqueVehicles(_ list: [Arac]) -> [Arac] {
        var seen = Set<UUID>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// Keeps `allVehiclesForReports` aligned with optimistic edits to `araclar`.
    /// Reports / `damageSource` flatten `allVehiclesForReports`; without this, add/remove/update
    /// damage only changed `araclar`, so dashboard vs. reports counters stayed wrong until the
    /// debounced Firestore listener fired.
    private func mirrorAracToAllVehiclesForReports(_ arac: Arac) {
        if let idx = allVehiclesForReports.firstIndex(where: { $0.id == arac.id }) {
            allVehiclesForReports[idx] = arac
        }
    }
    
    init() {
        self.firebaseService = FirebaseService.shared
        lastUserId = Auth.auth().currentUser?.uid
        
        // Do NOT load data here or setup Firebase auth listener
        // Data loading is triggered by observeAuthManager() after authManager is set
        // This prevents loading data before country validation completes
        
        // Track app initialization
        AnalyticsManager.shared.trackScreenView("App Initialized")
    }
    
    /// Sync trial account status from AuthenticationManager to FirebaseService
    /// Must be called BEFORE loadAllData() to keep runtime context current
    private func syncDemoStatus() {
        let isDemo = authManager?.userProfile?.effectiveIsTrialUser ?? false
        firebaseService.setTrialUserStatus(isDemo)
        if isDemo {
            LogManager.shared.info("Trial user detected")
        }
    }
    
    /// Sync franchise context from AuthenticationManager to FirebaseService
    /// Must be called BEFORE loadAllData() and after syncDemoStatus()
    private func syncFranchiseContext() {
        let franchiseId = authManager?.userProfile?.resolvedFranchiseIdForDataAccess() ?? "CH"
        let crossFranchise = authManager?.userProfile?.isCrossFranchisePlatformOperator ?? false
        AppCurrency.setActiveFranchiseId(franchiseId)
        firebaseService.setFranchiseContext(franchiseId: franchiseId, hasCrossFranchiseAccess: crossFranchise)
        LogManager.shared.info("Franchise context synced: franchiseId=\(franchiseId), hasCrossFranchiseAccess=\(crossFranchise)")
    }
    
    /// Fetches the franchise display name, currency, and `garageBranches` from Firestore `franchises/{id}`.
    /// Uses `firebaseService.currentFranchiseId` so it stays aligned with login / `setFranchiseContext` (not a stale profile-only id).
    private func loadFranchiseName() {
        let raw = firebaseService.currentFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
        let franchiseId = raw.isEmpty ? (authManager?.userProfile?.resolvedFranchiseIdForDataAccess() ?? "CH") : raw.uppercased()
        Firestore.firestore()
            .collection("franchises")
            .document(franchiseId)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                if error != nil || snapshot?.exists != true || snapshot?.data() == nil {
                    DispatchQueue.main.async {
                        self.franchiseName = ""
                        self.franchiseGarageBranches = []
                        AppCurrency.clearFranchiseCurrencyOverride()
                    }
                    return
                }
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async {
                        self.franchiseName = ""
                        self.franchiseGarageBranches = []
                        AppCurrency.clearFranchiseCurrencyOverride()
                    }
                    return
                }
                let name = (data["name"] as? String)
                    ?? (data["franchiseName"] as? String)
                    ?? franchiseId
                if let cur = data["currency"] as? String,
                   !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AppCurrency.setFranchiseCurrencyCode(cur)
                } else {
                    AppCurrency.clearFranchiseCurrencyOverride()
                }
                let branches = FranchiseGarageBranch.parseList(from: data)
                DispatchQueue.main.async {
                    self.franchiseName = name
                    self.franchiseGarageBranches = branches
                }
            }
    }

    /// Re-fetch franchise name + nested garage branches + `TR_*` franchise documents from the `franchises` collection.
    func reloadFranchiseGarageMetadataFromFirestore() {
        loadFranchiseName()
        loadTurkeyFranchiseLocationBranchesFromCollection()
    }

    /// Lists `franchises/{docId}` documents whose id starts with `TR_` (Turkey locations as separate franchise docs).
    private func loadTurkeyFranchiseLocationBranchesFromCollection() {
        Firestore.firestore().collection("franchises").getDocuments { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("⚠️ turkeyFranchiseLocationBranches: \(error.localizedDescription)")
                DispatchQueue.main.async { self.turkeyFranchiseLocationBranches = [] }
                return
            }
            let docs = snapshot?.documents ?? []
            let branches: [FranchiseGarageBranch] = docs.compactMap { doc -> FranchiseGarageBranch? in
                let id = doc.documentID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard id.hasPrefix("TR_") else { return nil }
                let data = doc.data()
                let title = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (data["franchiseName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let display: String = {
                    if let t = title, !t.isEmpty { return t }
                    return TurkiyeGarajSubeleri.displayTitle(forStoredKey: id)
                }()
                return FranchiseGarageBranch(storageKey: id, displayName: display, countryCode: "TR")
            }
            .sorted { $0.storageKey < $1.storageKey }
            DispatchQueue.main.async {
                self.turkeyFranchiseLocationBranches = branches
            }
        }
    }

    /// Garage branches from the loaded franchise doc, filtered by ISO country (e.g. TR). Entries without `countryCode` apply to all countries.
    func garageBranchesForSelectedCountry(countryCode: String) -> [FranchiseGarageBranch] {
        let cc = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cc.isEmpty else { return franchiseGarageBranches }
        return franchiseGarageBranches.filter { branch in
            guard let bcc = branch.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !bcc.isEmpty else {
                return true
            }
            return bcc == cc
        }
    }

    /// Load all data from Firebase - called when authenticated
    func loadAllData() {
        guard Auth.auth().currentUser != nil else {
            print("⚠️ Skipping data load - user not authenticated")
            return
        }
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        
        // Increment generation to invalidate any pending async callbacks from previous loads
        loadGeneration += 1
        let currentGeneration = loadGeneration
        
        // Ensure demo status and franchise context are synced before loading any data
        syncDemoStatus()
        syncFranchiseContext()
        loadFranchiseName()
        loadTurkeyFranchiseLocationBranchesFromCollection()

        araclariYukle(generation: currentGeneration)
        servisleriYukle(generation: currentGeneration)
        iadeleriYukle(generation: currentGeneration)
        exitleriYukle(generation: currentGeneration)
        activitiesYukle(generation: currentGeneration)
        servisFirmalariYukle(generation: currentGeneration)
        assistantCompaniesYukle(generation: currentGeneration)
        officeReturnsYukle(generation: currentGeneration)
        workSchedulesYukle(generation: currentGeneration)
        vacationTimesYukle(generation: currentGeneration)
        kategorileriYukle(generation: currentGeneration)
        setupRealtimeListeners()
    }
    
    // MARK: - Auth Manager Observer
    
    /// Call this after setting authManager to start observing authentication state.
    /// Data will only load when authManager.isAuthenticated becomes true 
    /// (which happens AFTER country validation succeeds).
    func observeAuthManager() {
        guard let authManager = authManager else { return }
        
        // Observe isAuthenticated changes via Combine
        authManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthenticated in
                guard let self = self else { return }
                let currentUserId = Auth.auth().currentUser?.uid
                
                if isAuthenticated && !self.hasLoadedInitialData {
                    // First time authenticated (country validation passed)
                    self.lastUserId = currentUserId
                    
                    // Check if profile is already available to set correct context immediately
                    if let profile = authManager.userProfile {
                        self.firebaseService.setTrialUserStatus(profile.effectiveIsTrialUser)
                        self.firebaseService.setFranchiseContext(
                            franchiseId: profile.resolvedFranchiseIdForDataAccess(),
                            hasCrossFranchiseAccess: profile.isCrossFranchisePlatformOperator
                        )
                        self.loadAllData()
                        print("✅ Initial data loaded with profile context")
                    } else {
                        // Profile not yet available - DON'T load data yet
                        // The userProfile observer below will trigger loadAllData when profile arrives
                        print("⏳ Waiting for user profile before loading data...")
                    }
                } else if isAuthenticated && currentUserId != self.lastUserId {
                    // User changed (different user logged in)
                    print("🔄 User changed: \(self.lastUserId ?? "nil") -> \(currentUserId ?? "nil")")
                    self.resetData()
                    self.lastUserId = currentUserId
                    
                    // Check if profile is already available
                    if let profile = authManager.userProfile {
                        self.firebaseService.setTrialUserStatus(profile.effectiveIsTrialUser)
                        self.firebaseService.setFranchiseContext(
                            franchiseId: profile.resolvedFranchiseIdForDataAccess(),
                            hasCrossFranchiseAccess: profile.isCrossFranchisePlatformOperator
                        )
                        self.loadAllData()
                        print("✅ Data reloaded for new user with profile context")
                    } else {
                        print("⏳ User changed, waiting for profile before loading data...")
                    }
                } else if !isAuthenticated && self.hasLoadedInitialData {
                    // User signed out - reset everything
                    print("🔄 User signed out, resetting data")
                    self.resetData()
                    self.lastUserId = nil
                    // Clear demo status and franchise context on sign out
                    self.firebaseService.setTrialUserStatus(false)
                    // Safe idle franchise id (empty string breaks scoped Firestore paths).
                    self.firebaseService.setFranchiseContext(franchiseId: "CH", hasCrossFranchiseAccess: false)
                }
            }
            .store(in: &cancellables)
        
        // Observe userProfile changes to update demo status and franchise context in FirebaseService
        // This handles both: (1) initial profile arrival after auth, (2) profile changes during session
        authManager.$userProfile
            .receive(on: DispatchQueue.main)
            .compactMap { $0 } // Only when profile is non-nil
            .sink { [weak self] profile in
                guard let self = self, authManager.isAuthenticated else { return }
                let isDemo = profile.effectiveIsTrialUser
                let previousDemoStatus = self.firebaseService.isTrialUserCached
                let previousFranchiseId = self.firebaseService.currentFranchiseId
                
                self.firebaseService.setTrialUserStatus(isDemo)
                self.firebaseService.setFranchiseContext(
                    franchiseId: profile.resolvedFranchiseIdForDataAccess(),
                    hasCrossFranchiseAccess: profile.isCrossFranchisePlatformOperator
                )
                
                if !self.hasLoadedInitialData {
                    // Profile arrived BEFORE any data load - this is the first load with correct context
                    self.lastUserId = Auth.auth().currentUser?.uid
                    self.loadAllData()
                    print("✅ Initial data loaded after profile received (demo:\(isDemo), franchise:\(profile.resolvedFranchiseIdForDataAccess()))")
                } else {
                    // Already loaded data - check if context changed and needs reload
                    let demoChanged = isDemo != previousDemoStatus
                    let franchiseChanged = profile.resolvedFranchiseIdForDataAccess() != previousFranchiseId
                    
                    if demoChanged || franchiseChanged {
                        LogManager.shared.warning("Context changed after data load (demo:\(demoChanged) franchise:\(franchiseChanged)) - reloading")
                        self.resetData()
                        self.loadAllData()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Remove all active Firestore snapshot listeners
    private func removeAllListeners() {
        iadeIslemleriListener?.remove()
        iadeIslemleriListener = nil
        exitIslemleriListener?.remove()
        exitIslemleriListener = nil
        assistantCompaniesListener?.remove()
        assistantCompaniesListener = nil
        araclarListener?.remove()
        araclarListener = nil
        officeOperationsListener?.remove()
        officeOperationsListener = nil
        garageServiceJobsListener?.remove()
        garageServiceJobsListener = nil
        officeReturnsListener?.remove()
        officeReturnsListener = nil
        trafficAccidentContractsListener?.remove()
        trafficAccidentContractsListener = nil
        workSchedulesListener?.remove()
        workSchedulesListener = nil
        vacationTimesListener?.remove()
        vacationTimesListener = nil
        vehicleCategoriesListener?.remove()
        vehicleCategoriesListener = nil
        outgoingEmailsScopedListener?.remove()
        outgoingEmailsScopedListener = nil
        additionalSalesPeopleListener?.remove()
        additionalSalesPeopleListener = nil
        hasarKayitlariTopLevelListener?.remove()
        hasarKayitlariTopLevelListener = nil
        print("🗑️ All ViewModel listeners removed")
    }
    
    private func resetData() {
        print("🔄 Resetting all ViewModel data...")
        hasLoadedInitialData = false
        
        // Increment generation to invalidate any pending async callbacks
        loadGeneration += 1
        
        // Remove ALL active listeners first to prevent stale data
        removeAllListeners()
        
        // Clear all published properties
        araclar = []
        servisler = []
        iadeIslemleri = []
        exitIslemleri = []
        activities = []
        servisFirmalari = []
        officeOperations = []
        garageServiceJobs = []
        officeReturns = []
        trafficAccidentContracts = []
        workSchedules = []
        vacationTimes = []
        assistantCompanies = []
        kategoriler = []
        returnEmailSentFallbackByReturnId = [:]
        additionalSalesPeople = []
        turkeyFranchiseLocationBranches = []

        // Reset ShuttleManager data
        ShuttleManager.shared.reset()
        
        // Post notification for views to reset their local state
        NotificationCenter.default.post(name: NSNotification.Name("UserChanged"), object: nil)
        
        // Clear cache
        pendingUpdates.removeAll()
        performanceOptimizer.clearCaches()
        
        print("✅ ViewModel data reset complete")
    }
    
    // MARK: - Real-time Firebase Listeners
    func setupRealtimeListeners() {
        // Remove any existing listeners before setting up new ones
        removeAllListeners()
        let franchiseId = firebaseService.currentFranchiseId
        let officeOperationsProductEnabled = FranchiseCapabilityMatrix.officeOperationsProductEnabledForSession(
            serviceFranchiseId: franchiseId,
            userProfile: authManager?.userProfile
        )
        
        iadeIslemleriListener = firebaseService.observeIadeIslemleri { [weak self] (iadeler: [IadeIslemi]) in
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
                    let today = Calendar.current.startOfDay(for: Date())
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                    let todayExits = exitler.filter { $0.createdAt >= today && $0.createdAt < tomorrow }
                    print("✅ Exit işlemleri real-time güncellendi: \(exitler.count) adet | bugün(oluşturma): \(todayExits.count) (dashboard kartı)")
                }
            }
        }
        
        assistantCompaniesListener = firebaseService.observeAssistantCompanies { [weak self] (companies: [AssistantCompany]?, error: Error?) in
            if let error = error {
                print("❌ Assistant companies real-time listener hatası: \(error.localizedDescription)")
            } else if let companies = companies {
                self?.debouncedUpdate(key: "assistantCompanies") {
                    self?.assistantCompanies = companies
                    print("✅ Assistant companies real-time güncellendi: \(companies.count) adet")
                }
            }
        }
        
        araclarListener = firebaseService.observeAraclar { [weak self] (araclar: [Arac]) in
            self?.debouncedUpdate(key: "araclar") {
                guard let self else { return }
                // Fix missing aracId in damage records (only on first load)
                var allUnique = self.uniqueVehicles(araclar)
                if !self.hasPerformedHasarFix {
                    for i in 0..<allUnique.count {
                        for j in 0..<allUnique[i].hasarKayitlari.count {
                            if allUnique[i].hasarKayitlari[j].aracId == UUID() {
                                allUnique[i].hasarKayitlari[j].aracId = allUnique[i].id
                            }
                        }
                    }
                    self.hasPerformedHasarFix = true
                }
                // All vehicles (incl. soft-deleted) — for report counts matching web
                self.allVehiclesForReports = allUnique
                // Display list: non-deleted only
                self.araclar = allUnique.filter { !$0.isDeleted }

                let allDamageCount = self.allVehiclesForReports.flatMap { $0.hasarKayitlari }.count
                let visibleDamageCount = self.araclar.flatMap { $0.hasarKayitlari }.count
                print("✅ Araçlar real-time güncellendi: \(self.araclar.count) adet (toplam \(allUnique.count)), hasar(all)=\(allDamageCount), hasar(visible)=\(visibleDamageCount)")
            }
        }
        
        garageServiceJobsListener = firebaseService.observeGarageServiceJobs { [weak self] jobs in
            self?.debouncedUpdate(key: "garageServiceJobs") {
                self?.garageServiceJobs = jobs
                print("✅ Garage service jobs güncellendi: \(jobs.count) adet")
            }
        }

        if officeOperationsProductEnabled {
            officeOperationsListener = firebaseService.observeOfficeOperations { [weak self] (operations: [OfficeOperation]) in
                self?.debouncedUpdate(key: "officeOperations") {
                    self?.officeOperations = operations
                    print("✅ Office operations real-time güncellendi: \(operations.count) adet")
                }
            }
            
            officeReturnsListener = firebaseService.observeOfficeReturns { [weak self] (returns: [OfficeReturn]) in
                self?.debouncedUpdate(key: "officeReturns") {
                    self?.officeReturns = returns
                    print("✅ Office returns real-time güncellendi: \(returns.count) adet")
                }
            }

            trafficAccidentContractsListener = firebaseService.observeTrafficAccidentContracts { [weak self] contracts in
                self?.debouncedUpdate(key: "trafficAccidentContracts") {
                    self?.trafficAccidentContracts = contracts
                    print("✅ Traffic accident contracts güncellendi: \(contracts.count) adet")
                }
            }
        } else {
            officeOperations = []
            officeReturns = []
            trafficAccidentContracts = []
        }
        
        // Observe current week's schedules
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        workSchedulesListener = firebaseService.observeWorkSchedules(weekStartDate: weekStart) { [weak self] (schedules: [WorkSchedule]) in
            self?.debouncedUpdate(key: "workSchedules") {
                self?.workSchedules = schedules
                print("✅ Work schedules real-time güncellendi: \(schedules.count) adet")
            }
        }
        
        vacationTimesListener = firebaseService.observeVacationTimes { [weak self] (vacationTimes: [VacationTime]) in
            self?.debouncedUpdate(key: "vacationTimes") {
                self?.vacationTimes = vacationTimes
                print("✅ Vacation times real-time güncellendi: \(vacationTimes.count) adet")
            }
        }
        
        vehicleCategoriesListener = firebaseService.observeVehicleCategories { [weak self] categories in
            self?.debouncedUpdate(key: "vehicleCategories") {
                self?.applyLoadedCategories(categories.map { $0.name })
            }
        }
        
        // Return (and TR checkout) PDF email delivery uses franchise SMTP only; track status for all franchises.
        setupOutgoingEmailTrackingListeners()
        
        additionalSalesPeopleListener = firebaseService.observeAdditionalSalesPeople { [weak self] names in
            self?.debouncedUpdate(key: "additionalSalesPeople") {
                self?.additionalSalesPeople = names
            }
        }
    }
    
    private func setupOutgoingEmailTrackingListeners() {
        let db = Firestore.firestore()

        outgoingEmailsScopedListener = db.collection("franchises")
            .document(firebaseService.currentFranchiseId)
            .collection("outgoingEmails")
            .whereField("type", isEqualTo: "return_pdf")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    if !FirebaseService.isPermissionError(error) {
                        print("⚠️ outgoingEmails scoped tracking listener error: \(error.localizedDescription)")
                    }
                    return
                }
                self?.mergeOutgoingEmailTracking(snapshot: snapshot)
            }
    }
    
    private func mergeOutgoingEmailTracking(snapshot: QuerySnapshot?) {
        guard let documents = snapshot?.documents else { return }
        
        var updates: [String: Date] = [:]
        for doc in documents {
            let data = doc.data()
            guard let returnId = data["returnId"] as? String, !returnId.isEmpty else { continue }
            let status = String(describing: data["status"] ?? "")
            guard status == "sent" || status == "duplicate_skipped" else { continue }
            
            let sentAt = (data["sentAt"] as? Timestamp)?.dateValue()
                ?? (data["processedAt"] as? Timestamp)?.dateValue()
                ?? (data["createdAt"] as? Timestamp)?.dateValue()
                ?? Date.distantPast
            
            if let existing = updates[returnId] {
                if sentAt > existing { updates[returnId] = sentAt }
            } else {
                updates[returnId] = sentAt
            }
        }
        
        guard !updates.isEmpty else { return }
        DispatchQueue.main.async {
            for (returnId, sentAt) in updates {
                if let current = self.returnEmailSentFallbackByReturnId[returnId] {
                    if sentAt > current {
                        self.returnEmailSentFallbackByReturnId[returnId] = sentAt
                    }
                } else {
                    self.returnEmailSentFallbackByReturnId[returnId] = sentAt
                }
            }
        }
    }
    
    func hasEmailSentRecord(for returnId: String) -> Bool {
        return returnEmailSentFallbackByReturnId[returnId] != nil
    }
    
    func addAdditionalSalesPerson(name: String, completion: ((Bool) -> Void)? = nil) {
        firebaseService.addAdditionalSalesPerson(name: name) { error in
            DispatchQueue.main.async {
                if let error {
                    print("❌ Additional sales person add failed: \(error.localizedDescription)")
                    completion?(false)
                } else {
                    completion?(true)
                }
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
    
    /// Check if a load generation is still current (prevents stale async callbacks)
    private func isCurrentGeneration(_ generation: Int) -> Bool {
        return generation == loadGeneration
    }
    
    func araclariYukle(generation: Int = 0) {
        // Skip cache when generation tracking is active (prevents stale data)
        if generation == 0 {
            let cacheKey = "araclar_cache_\(firebaseService.currentFranchiseId)_\(Auth.auth().currentUser?.uid ?? "anon")"
            if let cached = performanceOptimizer.cachedData(forKey: cacheKey) as? [Arac] {
                let allUnique = uniqueVehicles(cached)
                self.allVehiclesForReports = allUnique
                self.araclar = allUnique.filter { !$0.isDeleted }
                let allDamageCount = self.allVehiclesForReports.flatMap { $0.hasarKayitlari }.count
                let visibleDamageCount = self.araclar.flatMap { $0.hasarKayitlari }.count
                print("✅ Araçlar cache'den yüklendi: \(self.araclar.count) adet (toplam \(allUnique.count)), hasar(all)=\(allDamageCount), hasar(visible)=\(visibleDamageCount)")
            }
        }
        
        // Load from Firebase in background
        firebaseService.loadAraclar { [weak self] (araclar: [Arac]?, error: Error?) in
            if let error = error {
                print("❌ Araçlar yüklenemedi: \(error.localizedDescription)")
            } else if let araclar = araclar {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Araçlar load discarded (stale generation)")
                        return
                    }
                    let unique = self.uniqueVehicles(araclar)
                    self.allVehiclesForReports = unique
                    self.araclar = unique.filter { !$0.isDeleted }
                    self.syncCategoriesFromVehicles(unique.filter { !$0.isDeleted })
                    let cacheKey = "araclar_cache_\(self.firebaseService.currentFranchiseId)_\(Auth.auth().currentUser?.uid ?? "anon")"
                    self.performanceOptimizer.cacheData(unique as AnyObject, forKey: cacheKey)
                    let allDamageCount = self.allVehiclesForReports.flatMap { $0.hasarKayitlari }.count
                    let visibleDamageCount = self.araclar.flatMap { $0.hasarKayitlari }.count
                    print("✅ Araçlar yüklendi: \(self.araclar.count) adet (toplam \(unique.count)), hasar(all)=\(allDamageCount), hasar(visible)=\(visibleDamageCount)")

                    // Keep top-level damages in sync for reporting/analytics.
                    self.observeTopLevelHasarKayitlari()
                }
            }
        }
    }

    private func observeTopLevelHasarKayitlari() {
        hasarKayitlariTopLevelListener?.remove()
        hasarKayitlariTopLevelListener = firebaseService.observeHasarKayitlariTopLevel { [weak self] items, error in
            guard let self else { return }
            if let error {
                print("❌ Top-level damage observe error: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                self.topLevelHasarKayitlari = items ?? []
            }
        }
    }
    
    func kategorileriYukle(generation: Int = 0) {
        firebaseService.loadVehicleCategories { [weak self] categories, error in
            if let error = error {
                print("❌ Kategoriler yüklenemedi: \(error.localizedDescription)")
                return
            }
            
            guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                print("⚠️ Kategoriler load discarded (stale generation)")
                return
            }
            
            let names = categories?.map { $0.name } ?? []
            DispatchQueue.main.async {
                self.applyLoadedCategories(names)
            }
        }
    }
    
    func servisleriYukle(generation: Int = 0, completion: (() -> Void)? = nil) {
        firebaseService.loadServisler { [weak self] (servisKayitlari: [ServisKaydi]?, error: Error?) in
            if let error = error {
                print("❌ Servisler yüklenemedi: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?() }
            } else if let servisKayitlari = servisKayitlari {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Servisler load discarded (stale generation)")
                        completion?()
                        return
                    }
                    
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
                    completion?()
                }
            } else {
                DispatchQueue.main.async { completion?() }
            }
        }
    }
    
    func iadeleriYukle(generation: Int = 0) {
        firebaseService.loadIadeIslemleri { [weak self] (iadeler: [IadeIslemi]?, error: Error?) in
            if let error = error {
                print("❌ İadeler yüklenemedi: \(error.localizedDescription)")
            } else if let iadeler = iadeler {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ İadeler load discarded (stale generation)")
                        return
                    }
                    self.iadeIslemleri = iadeler
                    print("✅ İadeler yüklendi: \(iadeler.count) adet")
                }
            }
        }
    }
    
    func exitleriYukle(generation: Int = 0) {
        firebaseService.loadExitIslemleri { [weak self] (exitler: [ExitIslemi]?, error: Error?) in
            if let error = error {
                print("❌ Exit işlemleri yüklenemedi: \(error.localizedDescription)")
            } else if let exitler = exitler {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Exit load discarded (stale generation)")
                        return
                    }
                    self.exitIslemleri = exitler
                    print("✅ Exit işlemleri yüklendi: \(exitler.count) adet")
                }
            }
        }
    }
    
    func activitiesYukle(generation: Int = 0, completion: (() -> Void)? = nil) {
        firebaseService.loadActivities(limit: 250) { [weak self] (activities: [Activity]?, error: Error?) in
            if let error = error {
                print("❌ Aktiviteler yüklenemedi: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?() }
            } else if let activities = activities {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Activities load discarded (stale generation)")
                        completion?()
                        return
                    }
                    self.activities = activities
                    print("✅ Aktiviteler yüklendi: \(activities.count) adet")
                    completion?()
                }
            } else {
                DispatchQueue.main.async { completion?() }
            }
        }
    }
    
    func servisFirmalariYukle(generation: Int = 0) {
        firebaseService.loadServisFirmalari { [weak self] (firmalar: [ServisFirma]?, error: Error?) in
            if let error = error {
                print("❌ Servis firmaları yüklenemedi: \(error.localizedDescription)")
            } else if let firmalar = firmalar {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Servis firmaları load discarded (stale generation)")
                        return
                    }
                    self.servisFirmalari = self.dedupedServiceCompanies(firmalar)
                    print("✅ Servis firmaları yüklendi: \(self.servisFirmalari.count) adet")
                }
            }
        }
    }
    
    func assistantCompaniesYukle(generation: Int = 0) {
        firebaseService.loadAssistantCompanies { [weak self] (companies: [AssistantCompany]?, error: Error?) in
            if let error = error {
                print("❌ Assistant companies yüklenemedi: \(error.localizedDescription)")
            } else if let companies = companies {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Assistant companies load discarded (stale generation)")
                        return
                    }
                    self.assistantCompanies = companies
                    print("✅ Assistant companies yüklendi: \(companies.count) adet")
                }
            }
        }
    }
    
    func officeOperationsYukle(generation: Int = 0) {
        firebaseService.loadOfficeOperations { [weak self] (operations: [OfficeOperation]?, error: Error?) in
            if let error = error {
                print("❌ Office operations yüklenemedi: \(error.localizedDescription)")
            } else if let operations = operations {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Office operations load discarded (stale generation)")
                        return
                    }
                    self.officeOperations = operations
                    print("✅ Office operations yüklendi: \(operations.count) adet")
                }
            }
        }
    }
    
    func officeReturnsYukle(generation: Int = 0) {
        firebaseService.loadOfficeReturns { [weak self] (returns: [OfficeReturn]?, error: Error?) in
            if let error = error {
                print("❌ Office returns yüklenemedi: \(error.localizedDescription)")
            } else if let returns = returns {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Office returns load discarded (stale generation)")
                        return
                    }
                    self.officeReturns = returns
                    print("✅ Office returns yüklendi: \(returns.count) adet")
                }
            }
        }
    }
    
    func vacationTimesYukle(generation: Int = 0) {
        firebaseService.loadVacationTimes { [weak self] vacationTimes, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Vacation times yüklenemedi: \(error.localizedDescription)")
                } else if let vacationTimes = vacationTimes {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Vacation times load discarded (stale generation)")
                        return
                    }
                    self.vacationTimes = vacationTimes
                    print("✅ Vacation times yüklendi: \(vacationTimes.count) adet")
                }
            }
        }
    }
    
    func workSchedulesYukle(generation: Int = 0) {
        // Load all work schedules (not just current week) for accurate employee count
        firebaseService.loadWorkSchedules(weekStartDate: nil) { [weak self] (schedules: [WorkSchedule]?, error: Error?) in
            if let error = error {
                print("❌ Work schedules yüklenemedi: \(error.localizedDescription)")
            } else if let schedules = schedules {
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrentGeneration(generation) || generation == 0 else {
                        print("⚠️ Work schedules load discarded (stale generation)")
                        return
                    }
                    self.workSchedules = schedules
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
        if !allVehiclesForReports.contains(where: { $0.id == arac.id }) {
            allVehiclesForReports.append(arac)
        }
        
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
                    self.allVehiclesForReports.removeAll { $0.id == arac.id }
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
                    
                    self.activityEkle(.aracEklendi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
                    completion?(true)
                }
            }
        }
    }

    /// Bulk fleet import: saves via Firestore only (no per-vehicle success toasts). Categories are ensured first.
    @MainActor
    func importFleetVehiclesQuietly(rows: [FleetVehicleImportRow], turkeyGarageBranchFallback: String? = nil) async -> (imported: Int, failed: Int, skippedDuplicate: Int) {
        guard !rows.isEmpty else { return (0, 0, 0) }
        let fid = authManager?.userProfile?.resolvedFranchiseIdForDataAccess()
            ?? firebaseService.currentFranchiseId
        var existingKeys = Set(araclar.map { FleetListImportParser.plateDedupeKey(franchiseId: fid, storedPlate: $0.plaka) })
        let filteredRows = rows.filter { row in
            let key = FleetListImportParser.plateDedupeKey(franchiseId: fid, storedPlate: row.plateStored)
            guard !key.isEmpty, !existingKeys.contains(key) else { return false }
            existingKeys.insert(key)
            return true
        }
        let skippedDuplicate = max(0, rows.count - filteredRows.count)
        guard !filteredRows.isEmpty else { return (0, 0, skippedDuplicate) }

        let uniqueCategories = Set(filteredRows.map(\.kategori)).sorted()
        for c in uniqueCategories {
            kategoriEkle(c)
        }
        isSavingArac = true
        defer { isSavingArac = false }
        let uid = Auth.auth().currentUser?.uid
        let trimmedFallback = turkeyGarageBranchFallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackBranch: String? = (trimmedFallback?.isEmpty == false) ? trimmedFallback : nil
        let isTR = FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: fid,
            userProfile: authManager?.userProfile
        )
        let sessionGarage = TurkiyeGarajSubeleri.sessionBranchStorageKey()

        var imported = 0
        var failed = 0
        for row in filteredRows {
            let rowBranch = row.garageBranchStorageKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedGarageId: String? = {
                if isTR {
                    if let r = rowBranch, !r.isEmpty {
                        return TurkiyeGarajSubeleri.persistedGarageBranchIdForTurkeyVehicle(csvOrPickerValue: r)
                    }
                    if let f = fallbackBranch, !f.isEmpty {
                        return TurkiyeGarajSubeleri.persistedGarageBranchIdForTurkeyVehicle(csvOrPickerValue: f)
                    }
                    return sessionGarage
                }
                if let r = rowBranch, !r.isEmpty { return r }
                if let f = fallbackBranch, !f.isEmpty { return f }
                return nil
            }()
            let arac = Arac(
                plaka: row.plateStored,
                marka: row.marka,
                model: row.model,
                kategori: row.kategori,
                vin: row.vin,
                vignetteVar: false,
                spareKeyCount: 0,
                headDocumentURL: nil,
                createdBy: uid,
                garageBranchId: resolvedGarageId
            )
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                firebaseService.saveArac(arac) { err in
                    cont.resume(returning: err == nil)
                }
            }
            if ok {
                imported += 1
            } else {
                failed += 1
            }
        }
        return (imported, failed, skippedDuplicate)
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
        mirrorAracToAllVehiclesForReports(arac)
        
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
                    self.mirrorAracToAllVehiclesForReports(oldArac)
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
    
    /// Check-in UI path: same Firestore update as `aracGuncelle` but errors return to caller (no global alert/toast).
    func aracGuncelleForCheckInSync(_ arac: Arac, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let index = araclar.firstIndex(where: { $0.id == arac.id }) else {
            completion(.failure(NSError(
                domain: "AracHasarKayit",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Vehicle not found"]
            )))
            return
        }
        
        let oldArac = araclar[index]
        araclar[index] = arac
        mirrorAracToAllVehiclesForReports(arac)
        isUpdatingArac = true
        
        firebaseService.updateArac(arac) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingArac = false
                
                if let error = error {
                    self.araclar[index] = oldArac
                    self.mirrorAracToAllVehiclesForReports(oldArac)
                    print("❌ Check-in vehicle update failed: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Check-in vehicle update ok: \(arac.plakaFormatli)")
                    AnalyticsManager.shared.trackVehicleUpdated(vehiclePlate: arac.plaka)
                    completion(.success(()))
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
        
        // Store for rollback
        let aracToDelete = araclar[index]
        
        // Optimistic update (fleet list + report mirror)
        araclar.remove(at: index)
        allVehiclesForReports.removeAll { $0.id == aracToDelete.id }
        
        // Set loading state and provide haptic feedback
        isDeletingArac = true
        HapticManager.shared.medium()

        // Archive snapshot (restore / audit), then hard-delete doc so web + Firebase console stay in sync.
        archiveDeletedItem(
            originalPath: "franchises/\(firebaseService.currentFranchiseId)/araclar",
            originalId: aracToDelete.id.uuidString,
            type: .arac,
            description: "\(aracToDelete.plakaFormatli) - \(aracToDelete.marka) \(aracToDelete.model)",
            encodable: aracToDelete
        )

        firebaseService.deleteArac(id: aracToDelete.id) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDeletingArac = false
                
                if let error = error {
                    // Rollback optimistic update on error
                    self.araclar.insert(aracToDelete, at: index)
                    if !self.allVehiclesForReports.contains(where: { $0.id == aracToDelete.id }) {
                        self.allVehiclesForReports.append(aracToDelete)
                    }
                    print("❌ Araç silinemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Vehicle Delete")
                    HapticManager.shared.error()
                    completion?(false)
                } else {
                    print("✅ Araç silindi (Firestore): \(arac.plakaFormatli)")
                    ToastManager.shared.show("✓ Vehicle \(arac.plakaFormatli) removed", type: .success)
                    HapticManager.shared.success()
                    
                    // Track analytics
                    AnalyticsManager.shared.trackVehicleDeleted(vehiclePlate: arac.plaka)

                    AuditTrailManager.shared.logDeletion(
                        tableName: "araclar",
                        recordId: aracToDelete.id.uuidString,
                        data: [
                            "plaka": aracToDelete.plakaFormatli,
                            "marka": aracToDelete.marka,
                            "model": aracToDelete.model,
                            "garageBranchId": aracToDelete.garageBranchId ?? ""
                        ]
                    )
                    
                    self.activityEkle(.aracSilindi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
                    completion?(true)
                }
            }
        }
    }

    /// Archive + Firestore delete one vehicle (same persistence as `aracSil`, without optimistic pre-remove).
    private func archiveAndHardDeleteAracDocument(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        archiveDeletedItem(
            originalPath: "franchises/\(firebaseService.currentFranchiseId)/araclar",
            originalId: arac.id.uuidString,
            type: .arac,
            description: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)",
            encodable: arac
        )
        firebaseService.deleteArac(id: arac.id) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(error)
                    return
                }
                if error == nil {
                    self.araclar.removeAll { $0.id == arac.id }
                    self.allVehiclesForReports.removeAll { $0.id == arac.id }
                    AnalyticsManager.shared.trackVehicleDeleted(vehiclePlate: arac.plaka)
                    self.activityEkle(.aracSilindi, aciklama: "\(arac.plakaFormatli) - \(arac.marka) \(arac.model)", aracPlaka: arac.plakaFormatli)
                }
                completion(error)
            }
        }
    }

    /// Bulk hard-delete vehicles after typing `DELETE` (Category manager — same Firestore outcome as `aracSil`).
    func bulkDeleteVehiclesIfConfirmed(ids: [UUID], typedConfirmation: String, completion: @escaping (Bool) -> Void) {
        guard typedConfirmation == "DELETE" else {
            completion(false)
            return
        }
        let idSet = Set(ids)
        let targets = araclar.filter { idSet.contains($0.id) }
        guard targets.count == idSet.count, !targets.isEmpty else {
            if !idSet.isEmpty {
                ErrorManager.shared.showError(message: "Some vehicles are no longer in the fleet list.".localized)
            }
            completion(false)
            return
        }
        let ordered = targets.sorted { $0.plakaFormatli < $1.plakaFormatli }
        func run(at index: Int) {
            if index >= ordered.count {
                ToastManager.shared.show("Selected vehicles removed from fleet".localized, type: .success)
                HapticManager.shared.success()
                completion(true)
                return
            }
            archiveAndHardDeleteAracDocument(ordered[index]) { error in
                if error != nil {
                    ErrorManager.shared.showError(message: "Some vehicles could not be removed".localized)
                    HapticManager.shared.error()
                    completion(false)
                } else {
                    run(at: index + 1)
                }
            }
        }
        HapticManager.shared.medium()
        run(at: 0)
    }

    /// Hard-delete all vehicles in the given categories, then remove `vehicleCategories` docs.
    func deleteCategoriesAndVehiclesIfConfirmed(_ categoryNames: [String], typedConfirmation: String, completion: @escaping (Bool) -> Void) {
        guard typedConfirmation == "DELETE" else {
            completion(false)
            return
        }
        let normalizedCats = Set(categoryNames.map { VehicleCategory.normalizeName($0) }.filter { !$0.isEmpty })
        guard !normalizedCats.isEmpty else {
            completion(false)
            return
        }
        let vehicles = araclar.filter { v in
            let k = VehicleCategory.normalizeName(v.kategori)
            return normalizedCats.contains(k)
        }.sorted { $0.plakaFormatli < $1.plakaFormatli }

        func deleteCategoriesOnly() {
            let catGroup = DispatchGroup()
            var catFailed = false
            for cat in normalizedCats {
                catGroup.enter()
                self.firebaseService.deleteVehicleCategory(cat) { err in
                    DispatchQueue.main.async {
                        defer { catGroup.leave() }
                        if err != nil { catFailed = true }
                    }
                }
            }
            catGroup.notify(queue: .main) { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                if catFailed {
                    ErrorManager.shared.showError(message: "Vehicles removed but some category records could not be deleted".localized)
                    HapticManager.shared.error()
                    completion(false)
                } else {
                    self.kategoriler.removeAll { normalizedCats.contains(VehicleCategory.normalizeName($0)) }
                    ToastManager.shared.show("Categories and fleet entries updated".localized, type: .success)
                    HapticManager.shared.success()
                    completion(true)
                }
            }
        }

        guard !vehicles.isEmpty else {
            deleteCategoriesOnly()
            return
        }

        func runVehicle(at index: Int) {
            if index >= vehicles.count {
                deleteCategoriesOnly()
                return
            }
            archiveAndHardDeleteAracDocument(vehicles[index]) { error in
                if error != nil {
                    ErrorManager.shared.showError(message: "Some vehicles could not be removed".localized)
                    HapticManager.shared.error()
                    completion(false)
                } else {
                    runVehicle(at: index + 1)
                }
            }
        }

        HapticManager.shared.medium()
        runVehicle(at: 0)
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
            mirrorAracToAllVehiclesForReports(araclar[index])
            firebaseService.updateArac(araclar[index]) { error in
                if let error = error {
                    print("❌ Hasar eklenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Damage Save")
                } else {
                    print("✅ Hasar eklendi")
                    // Success UI: in-app banner from the view (NotificationManager), not Toast — avoids duplicate banners.
                    
                    // Track analytics
                    AnalyticsManager.shared.trackDamageRecorded(vehiclePlate: self.araclar[index].plaka, resCode: hasar.resKodu)

                    // Dual-write to top-level damage collection (best-effort).
                    self.firebaseService.saveHasarKaydiTopLevel(hasar) { err in
                        if let err {
                            print("⚠️ Top-level damage write failed: \(err.localizedDescription)")
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
                    self.mirrorAracToAllVehiclesForReports(updatedArac)
                    print("✅ Hasar Firebase'e kaydedildi: \(hasar.resKodu), Status: \(hasar.status.rawValue)")
                    // Success UI: in-app banner from HasarEkleView (NotificationManager), not Toast.
                    
                    // Track analytics
                    AnalyticsManager.shared.trackDamageUpdated(vehiclePlate: self.araclar[aracIndex].plaka, resCode: hasar.resKodu)

                    // Dual-write to top-level damage collection (best-effort).
                    self.firebaseService.saveHasarKaydiTopLevel(hasar) { err in
                        if let err {
                            print("⚠️ Top-level damage update failed: \(err.localizedDescription)")
                        }
                    }
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

            archiveDeletedItem(
                originalPath: "franchises/\(firebaseService.currentFranchiseId)/araclar/\(aracId.uuidString)/hasarKayitlari",
                originalId: hasar.id.uuidString,
                type: .hasarKaydi,
                description: "\(araclar[aracIndex].plakaFormatli) — \(hasar.resKodu)",
                encodable: hasar
            )
            
            araclar[aracIndex].hasarKayitlari.remove(at: hasarIndex)
            mirrorAracToAllVehiclesForReports(araclar[aracIndex])
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

                    AuditTrailManager.shared.logDeletion(
                        tableName: "hasar_kayitlari",
                        recordId: hasar.id.uuidString,
                        data: [
                            "aracId": aracId.uuidString,
                            "plaka": self.araclar[aracIndex].plakaFormatli,
                            "resKodu": hasar.resKodu
                        ]
                    )

                    // Dual-delete top-level damage record (best-effort).
                    self.firebaseService.deleteHasarKaydiTopLevel(id: hasarId) { err in
                        if let err {
                            print("⚠️ Top-level damage delete failed: \(err.localizedDescription)")
                        }
                    }
                }
            }
            activityEkle(.hasarSilindi, aciklama: "\(araclar[aracIndex].plakaFormatli) - \(hasar.resKodu)", aracPlaka: araclar[aracIndex].plakaFormatli)
        }
    }

    /// Removes only condition-form marker mapping from an existing damage record.
    /// Does NOT delete the damage record or its photos.
    func hasarConditionMappingSil(aracId: UUID, hasarId: UUID, completion: ((Bool) -> Void)? = nil) {
        guard let aracIndex = araclar.firstIndex(where: { $0.id == aracId }),
              let hasarIndex = araclar[aracIndex].hasarKayitlari.firstIndex(where: { $0.id == hasarId }) else {
            completion?(false)
            return
        }
        var hasar = araclar[aracIndex].hasarKayitlari[hasarIndex]
        hasar.isConditionForm = false
        hasar.conditionRegionId = nil
        hasar.conditionPointX = nil
        hasar.conditionPointY = nil
        hasar.conditionViewBlockId = nil
        hasar.markerNumber = nil
        hasar.damageZone = nil

        hasarGuncelle(aracId: aracId, hasar: hasar)
        completion?(true)
    }
    
    /// Removes one operational check-in snapshot from the vehicle (updates Firestore `araclar` document).
    func aracCheckInKaydiSil(aracId: UUID, checkInId: UUID, completion: ((Bool) -> Void)? = nil) {
        guard let aracIndex = araclar.firstIndex(where: { $0.id == aracId }) else {
            completion?(false)
            return
        }
        var arac = araclar[aracIndex]
        let before = arac.checkInKayitlari.count
        arac.checkInKayitlari.removeAll { $0.id == checkInId }
        guard arac.checkInKayitlari.count != before else {
            completion?(false)
            return
        }
        aracGuncelle(arac) { ok in
            completion?(ok)
        }
    }
    
    /// Loads recent activities filtered to operational audit types (for admin).
    func loadAuditActivities(limit: Int = 300, completion: @escaping ([Activity]) -> Void) {
        let capped = min(max(limit, 1), 500)
        firebaseService.loadActivities(limit: capped) { activities, _ in
            DispatchQueue.main.async {
                let list = activities ?? []
                let types: Set<ActivityType> = [
                    .exitYapildi, .iadeYapildi, .hasarEklendi, .hasarGuncellendi, .hasarSilindi, .checkInKaydedildi
                ]
                completion(list.filter { types.contains($0.tip) }.sorted { $0.tarih > $1.tarih })
            }
        }
    }

    /// Removes every activity document for the current franchise (dashboard + admin audit). Caller should enforce role checks.
    func clearAllFranchiseActivities(completion: @escaping (Error?) -> Void) {
        firebaseService.deleteAllActivitiesForCurrentFranchise { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.activities = []
                }
                completion(error)
            }
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
        firebaseService.saveIadeIslemi(iade) { error in
            if let error = error {
                print("❌ İade kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Return Save")
            } else {
                print("✅ İade kaydedildi: \(iade.aracPlaka)")
                // Success UI: delayed in-app banner from IadeIslemView (NotificationManager), not Toast.
                
                if iade.status == .completed {
                    self.activityEkle(.iadeYapildi, aciklama: "\(iade.aracPlaka) - Return completed", aracPlaka: iade.aracPlaka)
                }
                AnalyticsManager.shared.trackReturnCreated(returnType: iade.status.rawValue, amount: 0)
            }
        }
    }
    
    func iadeGuncelle(_ iade: IadeIslemi) {
        print("🔄 İade güncelleniyor - ID: \(iade.id.uuidString), Status: \(iade.status.rawValue)")
        let previous = iadeIslemleri.first(where: { $0.id == iade.id })
        
        firebaseService.saveIadeIslemi(iade) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ İade güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Return Update")
                } else {
                    print("✅ İade Firebase'e kaydedildi: \(iade.aracPlaka), Status: \(iade.status.rawValue)")
                    
                    if let index = self?.iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
                        self?.iadeIslemleri[index] = iade
                        print("✅ Local array güncellendi")
                    } else {
                        self?.iadeIslemleri.append(iade)
                        print("⚠️ İade local array'de bulunamadı, eklendi")
                    }
                    
                    // Success UI: delayed in-app banner from IadeIslemView when applicable, not Toast.
                    
                    if iade.status == .completed {
                        let firstComplete = previous?.status != .completed
                        let aciklama = firstComplete
                            ? "\(iade.aracPlaka) - Return completed"
                            : "\(iade.aracPlaka) - Return updated"
                        self?.activityEkle(.iadeYapildi, aciklama: aciklama, aracPlaka: iade.aracPlaka)
                    }
                    
                    AnalyticsManager.shared.trackReturnUpdated(returnType: iade.status.rawValue, amount: 0)
                }
            }
        }
    }
    
    /// Saves a snapshot to `franchises/{id}/deletedItems` before hard-deleting.
    private func archiveDeletedItem(
        originalPath: String,
        originalId: String,
        type: DeletedItemRecord.DeletedItemType,
        description: String,
        encodable: some Encodable
    ) {
        let franchiseId = authManager?.userProfile.map { $0.resolvedFranchiseIdForDataAccess() } ?? firebaseService.currentFranchiseId
        guard !franchiseId.isEmpty else { return }
        let uid = authManager?.userProfile?.uid ?? "unknown"
        let name = authManager?.userProfile?.displayName ?? "Unknown"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(encodable),
              let json = String(data: data, encoding: .utf8) else { return }

        let record = DeletedItemRecord(
            originalCollectionPath: originalPath,
            originalDocumentId: originalId,
            itemType: type,
            description: description,
            franchiseId: franchiseId,
            deletedAt: Date(),
            deletedByUid: uid,
            deletedByName: name,
            dataJSON: json
        )

        let db = Firestore.firestore()
        let ref = db.collection("franchises").document(franchiseId)
            .collection("deletedItems").document()

        if let encoded = try? Firestore.Encoder().encode(record) {
            ref.setData(encoded) { error in
                if let error = error {
                    print("⚠️ [Archive] Failed to archive deleted item: \(error.localizedDescription)")
                }
            }
        }
    }

    func iadeSil(_ iade: IadeIslemi) {
        if let index = iadeIslemleri.firstIndex(where: { $0.id == iade.id }) {
            iadeIslemleri.remove(at: index)

            archiveDeletedItem(
                originalPath: "franchises/\(firebaseService.currentFranchiseId)/iadeIslemleri",
                originalId: iade.id.uuidString,
                type: .iadeIslemi,
                description: iade.aracPlaka,
                encodable: iade
            )

            firebaseService.deleteIadeIslemi(iade) { error in
                if let error = error {
                    print("❌ İade silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ İade silindi")
                    if iade.status == .completed, let linkedExitId = iade.linkedExitId {
                        self.firebaseService.markExpectedReturnDismissed(forExitId: linkedExitId) { dismissalError in
                            if let dismissalError {
                                print("⚠️ Expected return dismiss flag yazılamadı: \(dismissalError.localizedDescription)")
                            } else {
                                print("✅ Expected return dismiss flag kaydedildi: \(linkedExitId.uuidString)")
                            }
                        }
                    }
                    
                    // Track analytics
                    AnalyticsManager.shared.trackReturnDeleted(returnType: iade.status.rawValue)
                }
            }
        }
    }
    
    // MARK: - Exit Operations
    
    func exitEkle(_ exit: ExitIslemi) {
        firebaseService.saveExitIslemi(exit) { error in
            if let error = error {
                print("❌ Exit kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Exit Save")
            } else {
                print("✅ Exit kaydedildi: \(exit.aracPlaka)")
                // Success UI: in-app banner from ExitIslemView (NotificationManager), not Toast.
                
                if exit.status == .completed {
                    self.activityEkle(.exitYapildi, aciklama: "\(exit.aracPlaka) - Check Out completed", aracPlaka: exit.aracPlaka)
                    if let plannedDate = exit.plannedReturnAt {
                        self.maybeCreateAutoReturn(for: exit, plannedDate: plannedDate)
                    }
                }
                AnalyticsManager.shared.trackReturnCreated(returnType: exit.status.rawValue, amount: 0)
            }
        }
    }
    
    func exitGuncelle(_ exit: ExitIslemi) {
        print("🔄 Exit güncelleniyor - ID: \(exit.id.uuidString), Status: \(exit.status.rawValue)")
        let previous = exitIslemleri.first(where: { $0.id == exit.id })
        
        firebaseService.saveExitIslemi(exit) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Exit güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Exit Update")
                } else {
                    print("✅ Exit Firebase'e kaydedildi: \(exit.aracPlaka), Status: \(exit.status.rawValue)")
                    
                    if let index = self?.exitIslemleri.firstIndex(where: { $0.id == exit.id }) {
                        self?.exitIslemleri[index] = exit
                        print("✅ Local array güncellendi")
                    } else {
                        self?.exitIslemleri.append(exit)
                        print("⚠️ Exit local array'de bulunamadı, eklendi")
                    }
                    
                    // Success UI: in-app banner from ExitIslemView (NotificationManager), not Toast.
                    
                    if exit.status == .completed {
                        let firstComplete = previous?.status != .completed
                        let aciklama = firstComplete
                            ? "\(exit.aracPlaka) - Check Out completed"
                            : "\(exit.aracPlaka) - Check Out updated"
                        self?.activityEkle(.exitYapildi, aciklama: aciklama, aracPlaka: exit.aracPlaka)
                        if let plannedDate = exit.plannedReturnAt {
                            self?.maybeCreateAutoReturn(for: exit, plannedDate: plannedDate)
                        }
                    }
                    
                    AnalyticsManager.shared.trackReturnUpdated(returnType: exit.status.rawValue, amount: 0)
                }
            }
        }
    }
    
    /// Checks whether a planned return already exists for `exit` and creates one if not.
    /// Called on the main queue after exit is saved with status `.completed`.
    private func maybeCreateAutoReturn(for exit: ExitIslemi, plannedDate: Date) {
        let isTurkeyFranchise = FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: firebaseService.currentFranchiseId,
            userProfile: authManager?.userProfile
        )
        guard isTurkeyFranchise else {
            print("ℹ️ [AutoReturn] Skipping planned return auto-create outside TR franchise context")
            return
        }
        if exit.expectedReturnDismissedAt != nil {
            print("🔕 [AutoReturn] Skipping auto-create – expected return dismissed for exit \(exit.id.uuidString)")
            return
        }
        let oneDaySeconds: TimeInterval = 86400
        let alreadyExists = iadeIslemleri.contains { iade in
            if iade.linkedExitId == exit.id { return true }
            if iade.aracId == exit.aracId && iade.status != .completed {
                let diff = abs(iade.iadeTarihi.timeIntervalSince(plannedDate))
                if diff <= oneDaySeconds { return true }
            }
            return false
        }
        guard !alreadyExists else {
            print("🔁 [AutoReturn] Skipping auto-create – existing return found for exit \(exit.id.uuidString)")
            return
        }
        let plannedStr = ISO8601DateFormatter().string(from: plannedDate)
        print("🔁 [AutoReturn] Created planned return for exit \(exit.id.uuidString) on \(plannedStr)")
        // Same Firestore document id as the completed checkout — idempotent with web `maybeCreateAutoReturn` (no duplicate rows).
        let autoReturn = IadeIslemi(
            id: exit.id,
            aracId: exit.aracId,
            aracPlaka: exit.aracPlaka,
            iadeTarihi: plannedDate,
            fotograflar: [],
            notlar: "",
            status: .inProgress,
            createdAt: Date(),
            createdBy: exit.createdBy,
            customerFirstName: exit.customerFirstName,
            customerLastName: exit.customerLastName,
            customerEmail: exit.customerEmail,
            pickUpBranch: exit.pickUpBranch,
            dropOffBranch: exit.dropOffBranch,
            linkedExitId: exit.id,
            navKodu: exit.navKodu,
            expectedReturnPlanned: true
        )
        iadeEkle(autoReturn)
    }

    func exitSil(_ exit: ExitIslemi) {
        if let index = exitIslemleri.firstIndex(where: { $0.id == exit.id }) {
            exitIslemleri.remove(at: index)

            archiveDeletedItem(
                originalPath: "franchises/\(firebaseService.currentFranchiseId)/exitIslemleri",
                originalId: exit.id.uuidString,
                type: .exitIslemi,
                description: "\(exit.aracPlaka) — \(exit.resKodu)",
                encodable: exit
            )

            firebaseService.deleteExitIslemi(exit) { error in
                if let error = error {
                    print("❌ Exit silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Exit silindi")
                    if exit.status == .completed {
                        self.firebaseService.softDeleteSiblingPendingExits(matching: exit) { siblingCount, siblingError in
                            if let siblingError {
                                print("⚠️ Stale sibling checkout cleanup failed: \(siblingError.localizedDescription)")
                            } else if siblingCount > 0 {
                                print("🧹 \(siblingCount) sibling waiting checkout soft-deleted")
                            }
                        }
                    }
                    
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
        var op = operation
        enrichOfficeOperationMetadata(&op)
        // Don't append to array - observeOfficeOperations listener will update it automatically
        firebaseService.saveOfficeOperation(op) { [weak self] error in
            if let error = error {
                print("❌ Office operation kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Office Operation Save")
            } else {
                print("✅ Office operation kaydedildi - listener will update the array automatically")
                ErrorManager.shared.showSuccess("Office operation saved successfully")

                self?.runFleetPaymentTrafficLinkPassAfterOfficeSave(op)

                // Track analytics
                AnalyticsManager.shared.trackOfficeOperationCreated(operationType: op.type.rawValue, amount: op.amount)

                // Add activity for office operation
                let aciklama = "\(op.type.hubTitleLocalized) - \(AppCurrency.amountWithCode(op.amount))"
                self?.activityEkle(
                    .officeOperation,
                    aciklama: aciklama,
                    aracPlaka: op.vehiclePlate,
                    detayliAciklama: op.notes.isEmpty ? nil : op.notes,
                    officeOperationId: op.id
                )
            }
        }
    }

    func garageServiceJobs(forVehicleId vehicleId: UUID) -> [GarageServiceJob] {
        garageServiceJobs
            .filter { $0.vehicleId == vehicleId }
            .sorted { $0.serviceDate > $1.serviceDate }
    }

    func garageServiceJobKaydet(_ job: GarageServiceJob, completion: ((Error?) -> Void)? = nil) {
        var j = job
        if j.createdBy == nil {
            j.createdBy = Auth.auth().currentUser?.uid
        }
        j.franchiseId = firebaseService.currentFranchiseId.uppercased()
        firebaseService.saveGarageServiceJob(j) { error in
            DispatchQueue.main.async {
                if let error {
                    print("❌ Garage service job kaydedilemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Garage Service")
                } else {
                    ErrorManager.shared.showSuccess("garage_service.saved".localized)
                }
                completion?(error)
            }
        }
    }

    func garageServiceJobSil(_ job: GarageServiceJob, completion: ((Error?) -> Void)? = nil) {
        let docId = job.documentId ?? job.id.uuidString
        firebaseService.deleteGarageServiceJob(documentId: docId) { error in
            DispatchQueue.main.async {
                if let error {
                    ErrorManager.shared.showError(error, context: "Garage Service Delete")
                } else {
                    ErrorManager.shared.showSuccess("garage_service.delete_success".localized)
                }
                completion?(error)
            }
        }
    }

    private func dedupedServiceCompanies(_ source: [ServisFirma]) -> [ServisFirma] {
        var seen: Set<String> = []
        var out: [ServisFirma] = []
        for item in source {
            let key = item.ad.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(item)
        }
        return out.sorted { $0.ad.localizedCaseInsensitiveCompare($1.ad) == .orderedAscending }
    }
    
    func lastWashingPriceForCurrentFranchise() -> Double? {
        let value = UserDefaults.standard.double(forKey: washingPriceDefaultsKey())
        return value > 0 ? value : nil
    }
    
    func addWashingRecord(
        aracId: UUID,
        price: Double,
        photoURLs: [String],
        notes: String = "",
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let index = araclar.firstIndex(where: { $0.id == aracId }) else {
            ErrorManager.shared.showError(message: "Vehicle not found")
            completion?(false)
            return
        }
        
        let actor = currentActorDisplayName()
        let timestamp = Date()
        let franchiseId = currentFranchiseScopeId()
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let whenText = timestamp.formatted(date: .abbreviated, time: .shortened)
        let officeNoteHeader = "Washing by \(actor) at \(whenText)"
        let officeNotes = cleanNotes.isEmpty ? officeNoteHeader : "\(officeNoteHeader)\n\(cleanNotes)"
        
        let record = VehicleWashingRecord(
            createdAt: timestamp,
            price: price,
            createdBy: actor,
            photoURLs: photoURLs,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            franchiseId: franchiseId
        )
        
        var updatedArac = araclar[index]
        updatedArac.washingRecords.append(record)
        updatedArac.washingRecords.sort { $0.createdAt > $1.createdAt }
        
        aracGuncelleForCheckInSync(updatedArac) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.rememberLastWashingPrice(price)
                    
                    var op = OfficeOperation(
                        type: .washing,
                        date: timestamp,
                        amount: price,
                        photos: photoURLs,
                        vehiclePlate: updatedArac.plakaFormatli,
                        notes: officeNotes
                    )
                    op.createdBy = actor
                    self?.officeOperationEkle(op)
                    
                    self?.activityEkle(
                        .officeOperation,
                        aciklama: "Washing - \(updatedArac.plakaFormatli) - \(AppCurrency.amountWithCode(price))",
                        aracPlaka: updatedArac.plakaFormatli,
                        detayliAciklama: officeNotes,
                        officeOperationId: op.id
                    )
                    completion?(true)
                case .failure(let error):
                    print("❌ Washing record save failed: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Washing Save")
                    completion?(false)
                }
            }
        }
    }

    func updateWashingRecord(
        aracId: UUID,
        recordId: UUID,
        price: Double,
        notes: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard price > 0 else {
            ErrorManager.shared.showError(message: "Invalid washing price")
            completion?(false)
            return
        }
        guard let aracIndex = araclar.firstIndex(where: { $0.id == aracId }) else {
            ErrorManager.shared.showError(message: "Vehicle not found")
            completion?(false)
            return
        }
        guard let recordIndex = araclar[aracIndex].washingRecords.firstIndex(where: { $0.id == recordId }) else {
            ErrorManager.shared.showError(message: "Washing record not found")
            completion?(false)
            return
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedArac = araclar[aracIndex]
        updatedArac.washingRecords[recordIndex].price = price
        updatedArac.washingRecords[recordIndex].notes = cleanNotes.isEmpty ? nil : cleanNotes
        updatedArac.washingRecords.sort { $0.createdAt > $1.createdAt }

        aracGuncelleForCheckInSync(updatedArac) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.rememberLastWashingPrice(price)
                    ToastManager.shared.show("✓ Washing record updated", type: .success)
                    completion?(true)
                case .failure(let error):
                    print("❌ Washing record update failed: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Washing Update")
                    completion?(false)
                }
            }
        }
    }

    func deleteWashingRecord(
        aracId: UUID,
        recordId: UUID,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let aracIndex = araclar.firstIndex(where: { $0.id == aracId }) else {
            ErrorManager.shared.showError(message: "Vehicle not found")
            completion?(false)
            return
        }
        guard araclar[aracIndex].washingRecords.contains(where: { $0.id == recordId }) else {
            ErrorManager.shared.showError(message: "Washing record not found")
            completion?(false)
            return
        }

        var updatedArac = araclar[aracIndex]
        updatedArac.washingRecords.removeAll { $0.id == recordId }
        updatedArac.washingRecords.sort { $0.createdAt > $1.createdAt }

        aracGuncelleForCheckInSync(updatedArac) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    ToastManager.shared.show("Washing record deleted", type: .info)
                    completion?(true)
                case .failure(let error):
                    print("❌ Washing record delete failed: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Washing Delete")
                    completion?(false)
                }
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

                        self?.runFleetPaymentTrafficLinkPassAfterOfficeSave(operation)

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

    /// Payments hub: cycle `fleetPaymentRecordStatus` (pending → partial → received → closed).
    func advanceFleetPaymentRecordStatus(_ operation: OfficeOperation) {
        guard operation.type == .banking else { return }
        var op = operation
        let next = (op.fleetPaymentRecordStatus ?? .pending).next
        op.fleetPaymentRecordStatus = next
        officeOperationGuncelle(op)
        HapticManager.shared.medium()
    }
    
    private func currentFranchiseScopeId() -> String {
        let franchise = authManager?.userProfile?.resolvedFranchiseIdForDataAccess()
            ?? firebaseService.currentFranchiseId
        let normalized = franchise.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? "CH" : normalized
    }
    
    private func washingPriceDefaultsKey() -> String {
        "last_washing_price_\(currentFranchiseScopeId())"
    }
    
    private func rememberLastWashingPrice(_ value: Double) {
        guard value > 0 else { return }
        UserDefaults.standard.set(value, forKey: washingPriceDefaultsKey())
    }
    
    private func currentActorDisplayName() -> String {
        if let profile = authManager?.userProfile {
            let display = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                return display
            }
            let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty {
                return email
            }
        }
        
        if let user = Auth.auth().currentUser {
            let name = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
            let email = (user.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty {
                return email
            }
            return user.uid
        }
        
        return "Unknown"
    }
    
    func officeOperationSil(_ operation: OfficeOperation) {
        // Archive before deleting so it can be restored from admin panel
        archiveDeletedItem(
            originalPath: "franchises/\(firebaseService.currentFranchiseId)/office_operations",
            originalId: operation.id.uuidString,
            type: .officeOperation,
            description: "\(operation.type.rawValue)\(operation.vehiclePlate.map { " — \($0)" } ?? "")",
            encodable: operation
        )

        // Don't remove from array - observeOfficeOperations listener will update it automatically
        firebaseService.deleteOfficeOperation(operation) { [weak self] error in
            if let error = error {
                print("❌ Office operation silinemedi: \(error.localizedDescription)")
            } else {
                print("✅ Office operation silindi - listener will update the array automatically")
                
                // Track analytics
                AnalyticsManager.shared.trackOfficeOperationDeleted(operationType: operation.type.rawValue)
                
                // Add activity for deleted office operation
                let aciklama = "\(operation.type.rawValue) - \(AppCurrency.amountWithCode(operation.amount))"
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
    
    
    // MARK: - Traffic accident contracts (CH office hub)
    /// Primary line (non-supplement) for this canonical `RES-…` already exists.
    func hasPrimaryTrafficContract(res canonical: String, excludingDocumentId: String? = nil) -> Bool {
        trafficAccidentContracts.contains { c in
            guard !c.isSupplementLine else { return false }
            guard TrafficAccidentContract.canonicalRES(from: c.resCode) == canonical else { return false }
            let docKey = c.documentId ?? c.id.uuidString
            if let ex = excludingDocumentId, docKey == ex { return false }
            return true
        }
    }

    func trafficAccidentContractEkle(_ contract: TrafficAccidentContract) {
        let useIdempotentCreate = contract.idempotencyKey != nil && !contract.isSupplementLine
        let save: (@escaping (Error?) -> Void) -> Void = { completion in
            if useIdempotentCreate {
                self.firebaseService.saveTrafficAccidentContractCreateIfAbsent(contract, completion: completion)
            } else {
                self.firebaseService.saveTrafficAccidentContract(contract, completion: completion)
            }
        }
        save { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Traffic Accident Contract Save")
                } else {
                    ToastManager.shared.show("Contract saved".localized, type: .success)
                    self?.runFleetPaymentTrafficSideEffectsAfterContractSave(contract)
                }
            }
        }
    }

    func trafficAccidentContractGuncelle(_ contract: TrafficAccidentContract) {
        firebaseService.updateTrafficAccidentContract(contract) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Traffic Accident Contract Update")
                } else {
                    self?.runFleetPaymentTrafficSideEffectsAfterContractSave(contract)
                }
            }
        }
    }

    func trafficAccidentContractSil(_ contract: TrafficAccidentContract) {
        let recordId = contract.documentId ?? contract.id.uuidString
        firebaseService.deleteTrafficAccidentContract(contract) { error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Traffic Accident Contract Delete")
                } else {
                    AuditTrailManager.shared.logDeletion(
                        tableName: "traffic_accident_contracts",
                        recordId: recordId,
                        data: [
                            "resCode": contract.displayResCode,
                            "amount": String(contract.amount),
                            "franchiseId": contract.franchiseId,
                            "photoCount": String(contract.photos.count)
                        ]
                    )
                }
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
                    AuditTrailManager.shared.logDeletion(
                        tableName: "servis_firmalari",
                        recordId: firma.id.uuidString,
                        data: ["ad": firma.ad, "telefon": firma.telefon]
                    )
                }
            }
        }
    }
    
    // MARK: - Assistant Company Operations
    
    func assistantCompanyEkle(_ company: AssistantCompany) {
        assistantCompanies.append(company)
        firebaseService.saveAssistantCompany(company) { error in
            if let error = error {
                print("❌ Assistant company kaydedilemedi: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "Assistant Company Save")
            } else {
                print("✅ Assistant company kaydedildi: \(company.name)")
                ToastManager.shared.show("✓ Assistant Company Saved", type: .success)
            }
        }
    }
    
    func assistantCompanyGuncelle(_ company: AssistantCompany) {
        if let index = assistantCompanies.firstIndex(where: { $0.id == company.id }) {
            assistantCompanies[index] = company
            firebaseService.saveAssistantCompany(company) { error in
                if let error = error {
                    print("❌ Assistant company güncellenemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Assistant Company Update")
                } else {
                    print("✅ Assistant company güncellendi: \(company.name)")
                    ToastManager.shared.show("✓ Assistant Company Updated", type: .success)
                }
            }
        }
    }
    
    func assistantCompanySil(_ company: AssistantCompany) {
        if let index = assistantCompanies.firstIndex(where: { $0.id == company.id }) {
            assistantCompanies.remove(at: index)
            firebaseService.deleteAssistantCompany(company) { error in
                if let error = error {
                    print("❌ Assistant company silinemedi: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Assistant Company Delete")
                } else {
                    print("✅ Assistant company silindi: \(company.name)")
                    ToastManager.shared.show("✓ Assistant Company Deleted", type: .success)
                }
            }
        }
    }
    
    // MARK: - Activity Operations
    func activityEkle(_ tip: ActivityType, aciklama: String, aracPlaka: String? = nil, detayliAciklama: String? = nil, officeOperationId: UUID? = nil) {
        let normalizedType = normalizedActivityType(for: tip, description: aciklama)
        var kullaniciAdi: String?
        var kullaniciEmail: String?
        
        func emailPrefix(_ email: String?) -> String? {
            guard let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty else {
                return nil
            }
            if let prefix = e.split(separator: "@").first, !prefix.isEmpty {
                return String(prefix)
            }
            return e
        }
        
        // Get user information
        if let profile = authManager?.userProfile {
            let display = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciEmail = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciAdi = display.isEmpty ? emailPrefix(kullaniciEmail) : display
            print("✅ Activity with user: \(kullaniciAdi ?? "unknown")")
        } else if let user = Auth.auth().currentUser {
            let authDisplay = (user.displayName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciEmail = user.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciAdi = authDisplay.isEmpty ? emailPrefix(kullaniciEmail) : authDisplay
            print("⚠️ Activity without profile, using email: \(kullaniciEmail ?? "unknown")")
        } else {
            print("❌ Activity with no user info")
        }
        
        let activity = Activity(
            tip: normalizedType,
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
    
    private func normalizedActivityType(for proposed: ActivityType, description: String) -> ActivityType {
        let lower = description.lowercased()
        let hasExitKeyword = lower.contains("exit") || lower.contains("check out")
        let hasReturnKeyword = lower.contains("return") || lower.contains("iade")
        
        if proposed == .iadeYapildi && hasExitKeyword {
            return .exitYapildi
        }
        if proposed == .exitYapildi && hasReturnKeyword && !hasExitKeyword {
            return .iadeYapildi
        }
        return proposed
    }
    
    // MARK: - Category Operations
    func kategoriEkle(_ kategori: String) {
        let normalized = VehicleCategory.normalizeName(kategori)
        guard !normalized.isEmpty else { return }
        
        if !kategoriler.contains(normalized) {
            kategoriler.append(normalized)
            kategoriler.sort()
            firebaseService.saveVehicleCategory(normalized) { error in
                if let error = error {
                    print("❌ Kategori kaydedilemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Kategori kaydedildi: \(normalized)")
                }
            }
        }
    }

    func kategoriYenidenAdlandir(_ eskiKategori: String, yeniKategori: String, completion: ((Bool) -> Void)? = nil) {
        let oldNormalized = VehicleCategory.normalizeName(eskiKategori)
        let newNormalized = VehicleCategory.normalizeName(yeniKategori)

        guard !oldNormalized.isEmpty, !newNormalized.isEmpty else {
            ErrorManager.shared.showError(message: "Category name cannot be empty".localized)
            completion?(false)
            return
        }
        guard oldNormalized != newNormalized else {
            completion?(true)
            return
        }
        guard kategoriler.contains(oldNormalized) else {
            ErrorManager.shared.showError(message: "Category not found".localized)
            completion?(false)
            return
        }
        guard !kategoriler.contains(newNormalized) else {
            ErrorManager.shared.showError(message: "Category already exists".localized)
            completion?(false)
            return
        }

        let impacted = araclar
            .enumerated()
            .filter { _, vehicle in VehicleCategory.normalizeName(vehicle.kategori) == oldNormalized }
            .map { $0.offset }

        firebaseService.saveVehicleCategory(newNormalized) { [weak self] saveError in
            guard let self = self else {
                completion?(false)
                return
            }
            if let saveError {
                DispatchQueue.main.async {
                    ErrorManager.shared.showError(saveError, context: "Category Rename")
                    completion?(false)
                }
                return
            }

            let group = DispatchGroup()
            var firstError: Error?

            for index in impacted {
                guard index < self.araclar.count else { continue }
                var updatedVehicle = self.araclar[index]
                updatedVehicle.kategori = newNormalized

                group.enter()
                self.firebaseService.updateArac(updatedVehicle) { error in
                    if firstError == nil, let error {
                        firstError = error
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let firstError {
                    ErrorManager.shared.showError(firstError, context: "Category Rename")
                    completion?(false)
                    return
                }

                DispatchQueue.main.async {
                    for index in impacted where index < self.araclar.count {
                        self.araclar[index].kategori = newNormalized
                        self.mirrorAracToAllVehiclesForReports(self.araclar[index])
                    }

                    let mergedCategories = Set(self.kategoriler.filter { $0 != oldNormalized })
                        .union([newNormalized])
                    self.kategoriler = Array(mergedCategories).sorted()

                    // Remove old category document so stale category doesn't reappear.
                    self.firebaseService.deleteVehicleCategory(oldNormalized) { deleteError in
                        DispatchQueue.main.async {
                            if let deleteError {
                                print("⚠️ Old category cleanup failed: \(deleteError.localizedDescription)")
                            }
                            ToastManager.shared.show(
                                String(format: "Category renamed: %@ → %@".localized, oldNormalized, newNormalized),
                                type: .success
                            )
                            completion?(true)
                        }
                    }
                }
            }
        }
    }

    func kategoriSil(_ kategori: String, completion: ((Bool) -> Void)? = nil) {
        let normalized = VehicleCategory.normalizeName(kategori)
        guard !normalized.isEmpty else {
            completion?(false)
            return
        }

        let stillUsed = araclar.contains { VehicleCategory.normalizeName($0.kategori) == normalized }
        if stillUsed {
            ErrorManager.shared.showError(message: "Category is still assigned to vehicles".localized)
            completion?(false)
            return
        }

        firebaseService.deleteVehicleCategory(normalized) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    completion?(false)
                    return
                }
                if let error {
                    ErrorManager.shared.showError(error, context: "Category Delete")
                    completion?(false)
                    return
                }
                self.kategoriler.removeAll { VehicleCategory.normalizeName($0) == normalized }
                ToastManager.shared.show("Category deleted".localized, type: .success)
                completion?(true)
            }
        }
    }
    
    private func applyLoadedCategories(_ loaded: [String]) {
        let normalizedLoaded = loaded
            .map(VehicleCategory.normalizeName)
            .filter { !$0.isEmpty }
        
        let merged = Set(normalizedLoaded)
            .union(araclar.map { VehicleCategory.normalizeName($0.kategori) }.filter { !$0.isEmpty })
        kategoriler = Array(merged).sorted()
    }
    
    private func syncCategoriesFromVehicles(_ vehicles: [Arac]) {
        let vehicleCategories = vehicles
            .map { VehicleCategory.normalizeName($0.kategori) }
            .filter { !$0.isEmpty }
        guard !vehicleCategories.isEmpty else { return }
        
        let merged = Set(kategoriler).union(vehicleCategories)
        kategoriler = Array(merged).sorted()
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

    /// Same damage universe as `RaporView.damageSource` (all vehicles, incl. soft-deleted).
    /// Must stay in sync via `mirrorAracToAllVehiclesForReports` when damage rows change.
    var allHasarKayitlariForReporting: [HasarKaydi] {
        allVehiclesForReports.flatMap { $0.hasarKayitlari }
    }

    /// Damage rows that are compatible with the condition-form map layer (have a non-empty location token).
    /// Falls back to reporting-cache vehicle list when the live list does not contain the target vehicle.
    func conditionFormDamages(for vehicleId: UUID) -> [HasarKaydi] {
        damagesForVehicle(vehicleId).filter {
            let zone = $0.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !zone.isEmpty
        }
    }

    /// Legacy damage rows without location info. These should stay visible in UI/PDF with explicit no-location labeling.
    func legacyDamagesWithoutLocation(for vehicleId: UUID) -> [HasarKaydi] {
        damagesForVehicle(vehicleId).filter {
            let zone = $0.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return zone.isEmpty
        }
    }

    /// Damage map list: Turkey keeps condition‑canvas vs legacy split; other franchises use a single combined list (legacy behaviour).
    func damagesForDamageMapView(for vehicleId: UUID, franchiseId: String?) -> [HasarKaydi] {
        let normalized = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let isTurkey = normalized.hasPrefix("TR")
            || UserDefaults.standard.selectedCountry.countryCode.uppercased() == "TR"
        if isTurkey {
            return conditionFormDamages(for: vehicleId) + legacyDamagesWithoutLocation(for: vehicleId)
        }
        return damagesForVehicle(vehicleId)
    }

    private func damagesForVehicle(_ vehicleId: UUID) -> [HasarKaydi] {
        let sourceVehicle =
            araclar.first(where: { $0.id == vehicleId }) ??
            allVehiclesForReports.first(where: { $0.id == vehicleId })
        return (sourceVehicle?.hasarKayitlari ?? []).sorted { lhs, rhs in
            if lhs.tarih != rhs.tarih { return lhs.tarih > rhs.tarih }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
    
    // MARK: - Today's / Monthly Statistics
    var todayDamageReportsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return allHasarKayitlariForReporting
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
        
        return allHasarKayitlariForReporting
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
        
        // Today's completed returns should use creation date to reflect real operations performed today.
        let todayReturns = iadeIslemleri.filter { iade in
            iade.status == .completed &&
            iade.createdAt >= today && iade.createdAt < tomorrow
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
            iade.status == .completed &&
            iade.createdAt >= today && iade.createdAt < tomorrow
        }.count
    }
    
    var todayExitCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return exitIslemleri.filter { exit in
            exit.createdAt >= today && exit.createdAt < tomorrow
        }.count
    }
    
    var todayOfficeOperationsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return officeOperations.filter { operation in
            operation.date >= today && operation.date < tomorrow
        }.count
    }
    
    // MARK: - 7-day sparkline data for dashboard cards
    func sparklineData(forDays count: Int = 7, counter: (Date, Date) -> Int) -> [Double] {
        let calendar = Calendar.current
        return (0..<count).reversed().map { offset in
            let dayAgo = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let start = calendar.startOfDay(for: dayAgo)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return Double(counter(start, end))
        }
    }

    var damageSparkline: [Double] {
        sparklineData { start, end in
            allHasarKayitlariForReporting.filter { $0.tarih >= start && $0.tarih < end }.count
        }
    }

    var exitSparkline: [Double] {
        sparklineData { start, end in
            exitIslemleri.filter { $0.createdAt >= start && $0.createdAt < end }.count
        }
    }

    var returnSparkline: [Double] {
        sparklineData { start, end in
            iadeIslemleri.filter { $0.status == .completed && $0.createdAt >= start && $0.createdAt < end }.count
        }
    }

    var officeOpsSparkline: [Double] {
        sparklineData { start, end in
            officeOperations.filter { $0.date >= start && $0.date < end }.count
        }
    }

    /// Compare today's damage count with yesterday's (used on the Dashboard daily card).
    var damageReportsChangeMetric: String {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return "0"
        }

        let allDamages = allHasarKayitlariForReporting
        let todayCount     = allDamages.filter { $0.tarih >= todayStart     && $0.tarih < tomorrowStart  }.count
        let yesterdayCount = allDamages.filter { $0.tarih >= yesterdayStart && $0.tarih < todayStart     }.count

        let change = todayCount - yesterdayCount
        if change == 0 { return "0" }
        return change > 0 ? "+\(change)" : "\(change)"
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
    
    // All authenticated users can edit vacation times (role restriction removed)
    func isYaseminOrFrontUser() -> Bool {
        // All users can edit vacation times - no role restriction needed
        return authManager?.currentUser != nil
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

