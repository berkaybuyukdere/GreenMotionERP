import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit
import FirebaseCrashlytics

class FirebaseService {
    static let shared = FirebaseService()
    
    struct MarketingExportResult {
        let exportedCount: Int
        let skippedCount: Int
        let campaignPath: String?
        let totalTrackedEmails: Int
    }
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    // Protocol listener cleanup
    private var protocolListener: ListenerRegistration?
    
    // Vacation Times listener
    private var vacationTimesListener: ListenerRegistration?
    
    // Timeout configuration
    private let defaultTimeout: TimeInterval = 30.0 // 30 seconds
    
    /// Cached trial flag from UserProfile.
    /// Used for UI/runtime signaling only (not for data path routing).
    private(set) var isTrialUserCached: Bool = false
    
    /// Cached franchise context - set by AracViewModel after profile loads
    private(set) var currentFranchiseId: String = "CH"
    /// True when `users.role` is superadmin or globaladmin — unfiltered legacy queries for cross-franchise reads.
    private(set) var currentHasCrossFranchiseAccess: Bool = false
    
    /// Shadow timestamp preference (optional UserDefaults toggle).
    private struct MigrationFlags {
        static let preferShadowTimestampsEnabled = "migration.date.prefer.shadow.timestamps.enabled"
    }
    
    /// Update the cached trial status from UserProfile.
    func setTrialUserStatus(_ isTrialUser: Bool) {
        let previousStatus = isTrialUserCached
        isTrialUserCached = isTrialUser
        if previousStatus != isTrialUser {
            LogManager.shared.info("FirebaseService trial status updated: \(isTrialUser)")
        }
    }
    
    /// Backward-compatible alias.
    func setDemoAccountStatus(_ isDemo: Bool) {
        setTrialUserStatus(isDemo)
    }
    
    /// Update the franchise context from UserProfile
    func setFranchiseContext(franchiseId: String, hasCrossFranchiseAccess: Bool) {
        let prevFranchise = currentFranchiseId
        let prevAccess = currentHasCrossFranchiseAccess
        let trimmed = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Never use an empty document id — `franchises/{id}/…` with "" can crash listeners after sign-out.
        currentFranchiseId = trimmed.isEmpty ? "CH" : trimmed
        currentHasCrossFranchiseAccess = hasCrossFranchiseAccess
        if prevFranchise != franchiseId || prevAccess != hasCrossFranchiseAccess {
            LogManager.shared.info("FirebaseService franchise context updated: franchiseId=\(franchiseId), hasCrossFranchiseAccess=\(hasCrossFranchiseAccess)")
        }
    }
    
    // Trial mode no longer changes collection/storage routing.
    var isDemoUser: Bool {
        false
    }
    
    /// Check if user is currently authenticated. Returns false and logs if not.
    private func requireAuth(context: String) -> Bool {
        guard Auth.auth().currentUser != nil else {
            LogManager.shared.warning("Skipping \(context) - user not authenticated")
            return false
        }
        return true
    }

    private func logPerf(_ name: String, start: CFAbsoluteTime, count: Int? = nil) {
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        if let count {
            print("⏱️ [Perf] \(name) \(elapsedMs)ms (\(count) docs)")
        } else {
            print("⏱️ [Perf] \(name) \(elapsedMs)ms")
        }
    }
    
    /// Check if a Firestore error is a permission error
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
    }
    
    // Legacy collection reference for global/top-level collections.
    private func getLegacyCollectionReference(_ baseName: String) -> CollectionReference {
        db.collection(baseName)
    }
    
    private func getScopedCollectionReference(_ baseName: String) -> CollectionReference {
        return db.collection("franchises")
            .document(currentFranchiseId)
            .collection(baseName)
    }
    
    private func isGlobalCollection(_ baseName: String) -> Bool {
        let globalCollections: Set<String> = [
            "users",
            "franchises",
            "smtpConfigurations",
            "notifications",
            "outgoingEmails",
            "plateFormats",
            "protocolTemplates",
            "accidentCodes",
            "fcmTokens",
            "adminTests",
            "adminTestLogs"
        ]
        return globalCollections.contains(baseName)
    }
    
    // Get primary collection reference for write operations.
    // Migration modes:
    // - default: legacy writes
    // - scoped writes: writes target franchised path
    func getCollectionReference(_ baseName: String) -> CollectionReference {
        if isGlobalCollection(baseName) {
            return getLegacyCollectionReference(baseName)
        }
        if isScopedWritesEnabled {
            return getScopedCollectionReference(baseName)
        }
        return getLegacyCollectionReference(baseName)
    }
    
    /// Tek hedef: global koleksiyonlar kökte; domain verisi yalnızca `franchises/{id}/…`.
    private func getWriteCollectionTargets(_ baseName: String) -> [CollectionReference] {
        if isGlobalCollection(baseName) {
            return [getLegacyCollectionReference(baseName)]
        }
        return [getScopedCollectionReference(baseName)]
    }
    
    /// Get a filtered query for a collection - applies franchise filter unless elevated admin (superadmin / globaladmin)
    /// Use this for ALL read operations (getDocuments, addSnapshotListener)
    /// Write operations should use getCollectionReference() directly (franchiseId is in the model data)
    func getFilteredQuery(_ baseName: String) -> Query {
        if isGlobalCollection(baseName) {
            return getLegacyCollectionReference(baseName)
        }
        if isScopedReadsEnabled {
            return getScopedCollectionReference(baseName)
        }
        
        let collRef = getLegacyCollectionReference(baseName)
        
        // Elevated admins see all data across franchises (legacy root collections)
        if currentHasCrossFranchiseAccess {
            return collRef
        }
        
        // Regular users: filter by franchiseId
        return collRef.whereField("franchiseId", isEqualTo: currentFranchiseId)
    }
    
    private init() {}
    
    // MARK: - Migration Configuration
    
    var isScopedReadsEnabled: Bool {
        true
    }
    
    var isScopedWritesEnabled: Bool { true }

    var isStorageScopedWritesEnabled: Bool { true }

    /// When true, read paths prefer `*Ts` shadow timestamp fields.
    /// Defaults to true for new builds; can be toggled via `configureMigration`.
    var preferShadowTimestamps: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: MigrationFlags.preferShadowTimestampsEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: MigrationFlags.preferShadowTimestampsEnabled)
    }
    
    /// Kök koleksiyona çift yazma / legacy okuma kaldırıldı; yalnızca gölge tarih tercihi kalır.
    func configureMigration(
        preferShadowTimestamps: Bool? = nil
    ) {
        let defaults = UserDefaults.standard
        if let preferShadowTimestamps {
            defaults.set(preferShadowTimestamps, forKey: MigrationFlags.preferShadowTimestampsEnabled)
        }
    }
    
    // MARK: - Timeout Helper with Retry
    /// Execute a Firebase operation with timeout and retry mechanism
    private func executeWithTimeout(
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 3,
        operation: @escaping (@escaping (Error?) -> Void) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        executeWithRetry(
            maxAttempts: maxRetries,
            operation: { retryCompletion in
                var hasCompleted = false
                let lock = NSLock()
                
                // Create timeout timer
                let timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    
                    let timeoutError = NSError(
                        domain: "FirebaseTimeout",
                        code: -1001,
                        userInfo: [NSLocalizedDescriptionKey: "Request timed out after \(Int(timeout)) seconds. Please check your internet connection and try again."]
                    )
                    retryCompletion(timeoutError)
                }
                
                // Execute operation
                operation { error in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    timeoutTimer.invalidate()
                    retryCompletion(error)
                }
            },
            completion: completion
        )
    }
    
    /// Execute operation with retry logic for network errors
    private func executeWithRetry(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping (@escaping (Error?) -> Void) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        var attempt = 1
        
        func tryOperation() {
            operation { error in
                // Check if error is retryable (network errors)
                if let error = error, self.shouldRetry(error: error), attempt < maxAttempts {
                    attempt += 1
                    let delay = initialDelay * pow(2.0, Double(attempt - 2)) // Exponential backoff
                    LogManager.shared.warning("Retrying operation (attempt \(attempt)/\(maxAttempts)) after \(delay)s delay...")
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        tryOperation()
                    }
                } else {
                    // Final attempt or non-retryable error
                    completion(error)
                }
            }
        }
        
        tryOperation()
    }
    
    /// Determine if an error should trigger a retry
    private func shouldRetry(error: Error) -> Bool {
        guard let nsError = error as NSError? else { return false }
        
        // Retry on network errors
        let retryableDomains = ["NSURLErrorDomain", "FIRFirestoreErrorDomain"]
        let retryableCodes: [Int] = [
            -1001, // Timeout
            -1009, // No internet connection
            -1004, // Could not connect
            -1005, // Network connection lost
            14,    // UNAVAILABLE
            8      // RESOURCE_EXHAUSTED
        ]
        
        if retryableDomains.contains(nsError.domain) && retryableCodes.contains(nsError.code) {
            return true
        }
        
        // Check error description for network-related keywords
        let errorDescription = error.localizedDescription.lowercased()
        let networkKeywords = ["network", "timeout", "unavailable", "connection", "internet"]
        
        if networkKeywords.contains(where: { errorDescription.contains($0) }) {
            return true
        }
        
        return false
    }
    
    // MARK: - Migration Read/Write Helpers
    
    /// Domain okumaları yalnızca `getFilteredQuery` (scoped path veya global).
    private func readFilteredQuery(
        baseName: String,
        queryBuilder: @escaping (Query) -> Query = { $0 },
        completion: @escaping (QuerySnapshot?, Error?) -> Void
    ) {
        queryBuilder(getFilteredQuery(baseName)).getDocuments(completion: completion)
    }
    
    private func writeEncodableDocument<T: Encodable>(
        baseName: String,
        documentId: String,
        value: T,
        completion: @escaping (Error?) -> Void
    ) {
        let targets = getWriteCollectionTargets(baseName)
        let group = DispatchGroup()
        var firstError: Error?
        
        for target in targets {
            group.enter()
            do {
                try target.document(documentId).setData(from: value) { error in
                    if firstError == nil, let error {
                        firstError = error
                    }
                    group.leave()
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(firstError)
        }
    }
    
    private func writeDictionaryDocument(
        baseName: String,
        documentId: String,
        data: [String: Any],
        merge: Bool = false,
        completion: @escaping (Error?) -> Void
    ) {
        let targets = getWriteCollectionTargets(baseName)
        let group = DispatchGroup()
        var firstError: Error?
        
        for target in targets {
            group.enter()
            target.document(documentId).setData(data, merge: merge) { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(firstError)
        }
    }
    
    private func deleteDocument(
        baseName: String,
        documentId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let targets = getWriteCollectionTargets(baseName)
        let group = DispatchGroup()
        var firstError: Error?
        
        for target in targets {
            group.enter()
            target.document(documentId).delete { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(firstError)
        }
    }

    /// Matches web `softDeleteExitOperation` / `softDeleteReturnOperation` (same field names).
    private func softDeleteDocument(
        baseName: String,
        documentId: String,
        completion: @escaping (Error?) -> Void
    ) {
        let targets = getWriteCollectionTargets(baseName)
        let group = DispatchGroup()
        var firstError: Error?
        var data: [String: Any] = [
            "isDeleted": true,
            "deletedAt": Timestamp(date: Date()),
        ]
        if let uid = Auth.auth().currentUser?.uid {
            data["deletedBy"] = uid
        } else {
            data["deletedBy"] = NSNull()
        }

        for target in targets {
            group.enter()
            target.document(documentId).updateData(data) { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(firstError)
        }
    }

    private func scopedStoragePathIfNeeded(_ legacyPath: String) -> String {
        guard isStorageScopedWritesEnabled else { return legacyPath }
        let normalized = legacyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("franchises/") {
            return normalized
        }
        return "franchises/\(currentFranchiseId)/\(normalized)"
    }
    
    private func storageWritePaths(for legacyPath: String) -> [String] {
        [scopedStoragePathIfNeeded(legacyPath)]
    }
    
    // MARK: - Araç İşlemleri

    func loadAraclar(completion: @escaping ([Arac]?, Error?) -> Void) {
        // Use performance optimizer for background processing
        PerformanceOptimizer.shared.performInBackground {
            self.readFilteredQuery(baseName: "araclar") { querySnapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    DispatchQueue.main.async {
                        completion([], nil)
                    }
                    return
                }
                
                // Decode on background queue
                let araclar = documents.compactMap { document -> Arac? in
                    try? document.data(as: Arac.self)
                }
                .filter { !$0.isDeleted }
                
                DispatchQueue.main.async {
                    completion(araclar, nil)
                }
            }
        }
    }

    func saveArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        var aracToSave = arac
        aracToSave.franchiseId = currentFranchiseId
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            self.writeEncodableDocument(
                baseName: "araclar",
                documentId: aracToSave.id.uuidString,
                value: aracToSave,
                completion: resultCompletion
            )
        }, completion: { error in
            completion(error)
        })
    }

    func updateArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        var aracToSave = arac
        aracToSave.franchiseId = currentFranchiseId
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            self.writeEncodableDocument(
                baseName: "araclar",
                documentId: aracToSave.id.uuidString,
                value: aracToSave,
                completion: resultCompletion
            )
        }, completion: { error in
            completion(error)
        })
    }

    func deleteArac(id: UUID, completion: @escaping (Error?) -> Void) {
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            self.deleteDocument(baseName: "araclar", documentId: id.uuidString, completion: resultCompletion)
        }, completion: { error in
            completion(error)
        })
    }

    // MARK: - Damage Records (Top-level)

    func saveHasarKaydiTopLevel(_ hasar: HasarKaydi, completion: @escaping (Error?) -> Void) {
        var toSave = hasar
        toSave.franchiseId = currentFranchiseId
        writeEncodableDocument(
            baseName: "hasarKayitlari",
            documentId: toSave.id.uuidString,
            value: toSave,
            completion: completion
        )
    }

    func deleteHasarKaydiTopLevel(id: UUID, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "hasarKayitlari", documentId: id.uuidString, completion: completion)
    }

    func fetchHasarKaydiTopLevel(id: UUID, completion: @escaping (HasarKaydi?, Error?) -> Void) {
        guard requireAuth(context: "fetchHasarKaydiTopLevel") else {
            completion(nil, nil)
            return
        }
        getCollectionReference("hasarKayitlari").document(id.uuidString).getDocument { snapshot, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let snapshot, snapshot.exists else {
                completion(nil, nil)
                return
            }
            do {
                let hasar = try snapshot.data(as: HasarKaydi.self)
                completion(hasar, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    @discardableResult
    func observeHasarKayitlariTopLevel(completion: @escaping ([HasarKaydi]?, Error?) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeHasarKayitlariTopLevel") else {
            completion([], nil)
            return nil
        }
        // Franchise filtered by getFilteredQuery.
        return getFilteredQuery("hasarKayitlari")
            .order(by: "tarih", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                let docs = snapshot?.documents ?? []
                let items = docs.compactMap { doc in
                    try? doc.data(as: HasarKaydi.self)
                }
                completion(items, nil)
            }
    }
    
    // MARK: - Vehicle Categories
    
    func loadVehicleCategories(completion: @escaping ([VehicleCategory]?, Error?) -> Void) {
        readFilteredQuery(baseName: "vehicleCategories", queryBuilder: { $0.order(by: "name") }) { querySnapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                let categories = documents.compactMap { document -> VehicleCategory? in
                    var category = try? document.data(as: VehicleCategory.self)
                    if category == nil, let name = document.data()["name"] as? String {
                        category = VehicleCategory(name: name, franchiseId: self.currentFranchiseId)
                    }
                    category?.id = document.documentID
                    return category
                }
                
                completion(categories, nil)
        }
    }
    
    func saveVehicleCategory(_ categoryName: String, completion: @escaping (Error?) -> Void) {
        let category = VehicleCategory(name: categoryName, franchiseId: currentFranchiseId)
        writeEncodableDocument(
            baseName: "vehicleCategories",
            documentId: category.id,
            value: category,
            completion: completion
        )
    }

    func deleteVehicleCategory(_ categoryName: String, completion: @escaping (Error?) -> Void) {
        let normalized = VehicleCategory.normalizeName(categoryName)
        guard !normalized.isEmpty else {
            completion(nil)
            return
        }
        let documentId = VehicleCategory.makeDocumentId(from: normalized)
        deleteDocument(baseName: "vehicleCategories", documentId: documentId, completion: completion)
    }
    
    @discardableResult
    func observeVehicleCategories(completion: @escaping ([VehicleCategory]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeVehicleCategories") else {
            completion([])
            return nil
        }
        
        return getFilteredQuery("vehicleCategories")
            .order(by: "name")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Vehicle categories listener error: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([])
                    return
                }
                
                let categories = documents.compactMap { document -> VehicleCategory? in
                    var category = try? document.data(as: VehicleCategory.self)
                    if category == nil, let name = document.data()["name"] as? String {
                        category = VehicleCategory(name: name, franchiseId: self.currentFranchiseId)
                    }
                    category?.id = document.documentID
                    return category
                }
                
                completion(categories)
            }
    }

    // MARK: - Servis İşlemleri

    func loadServisler(completion: @escaping ([ServisKaydi]?, Error?) -> Void) {
        readFilteredQuery(baseName: "servisler") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let servisler = documents.compactMap { document -> ServisKaydi? in
                try? document.data(as: ServisKaydi.self)
            }
            
            completion(servisler, nil)
        }
    }

    func saveServis(_ servis: ServisKaydi, completion: @escaping (Error?) -> Void) {
        var servisToSave = servis
        servisToSave.franchiseId = currentFranchiseId
        self.writeEncodableDocument(
            baseName: "servisler",
            documentId: servisToSave.id.uuidString,
            value: servisToSave,
            completion: completion
        )
    }

    func deleteServis(_ servis: ServisKaydi, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "servisler", documentId: servis.id.uuidString, completion: completion)
    }

    // MARK: - İade İşlemleri

    func loadIadeIslemleri(completion: @escaping ([IadeIslemi]?, Error?) -> Void) {
        readFilteredQuery(baseName: "iadeIslemleri") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let raw = documents.compactMap { document -> IadeIslemi? in
                try? document.data(as: IadeIslemi.self)
            }
            let deduped: [IadeIslemi] = {
                var seen = Set<UUID>()
                var result = [IadeIslemi]()
                for item in raw { if seen.insert(item.id).inserted { result.append(item) } }
                if result.count != raw.count {
                    print("🔧 [ReturnSync] deduped \(raw.count)→\(result.count) docs (same-UUID duplicates removed)")
                }
                return result
            }()
            let iadeler = self.filterActiveReturns(deduped, source: "loadIadeIslemleri")
            completion(iadeler, nil)
        }
    }

    func saveIadeIslemi(_ iade: IadeIslemi, completion: @escaping (Error?) -> Void) {
        var iadeToSave = iade
        iadeToSave.franchiseId = currentFranchiseId
        LogManager.shared.firebase("Saving iade to Firebase", operation: "saveIadeIslemi")
        self.writeEncodableDocument(
            baseName: "iadeIslemleri",
            documentId: iadeToSave.id.uuidString,
            value: iadeToSave
        ) { error in
            if let error = error {
                LogManager.shared.error("Error saving iade", error: error)
                Crashlytics.crashlytics().record(error: error)
            } else {
                LogManager.shared.success("İade başarıyla Firebase'e kaydedildi - Status: \(iadeToSave.status.rawValue)")
            }
            completion(error)
        }
    }

    func deleteIadeIslemi(_ iade: IadeIslemi, completion: @escaping (Error?) -> Void) {
        softDeleteDocument(baseName: "iadeIslemleri", documentId: iade.id.uuidString, completion: completion)
    }

    /// Suppresses expected-return regeneration for a checkout after a user intentionally removed a return row.
    func markExpectedReturnDismissed(forExitId exitId: UUID, completion: @escaping (Error?) -> Void) {
        guard requireAuth(context: "markExpectedReturnDismissed") else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let targets = getWriteCollectionTargets("exitIslemleri")
        let group = DispatchGroup()
        var firstError: Error?
        let payload: [String: Any] = [
            "expectedReturnDismissedAt": Timestamp(date: Date())
        ]
        for target in targets {
            group.enter()
            target.document(exitId.uuidString).setData(payload, merge: true) { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(firstError)
        }
    }

    /// Single-document read (writes path). Used after offline media sync to merge new Storage URLs.
    func fetchIadeIslemi(id: UUID, completion: @escaping (IadeIslemi?, Error?) -> Void) {
        guard requireAuth(context: "fetchIadeIslemi") else {
            completion(nil, nil)
            return
        }
        getCollectionReference("iadeIslemleri").document(id.uuidString).getDocument { snapshot, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let snapshot, snapshot.exists else {
                completion(nil, nil)
                return
            }
            do {
                let iade = try snapshot.data(as: IadeIslemi.self)
                completion(iade, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Exit İşlemleri
    
    func loadExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) {
        readFilteredQuery(baseName: "exitIslemleri") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let raw = documents.compactMap { document -> ExitIslemi? in
                try? document.data(as: ExitIslemi.self)
            }
            let deduped: [ExitIslemi] = {
                var seen = Set<UUID>()
                var result = [ExitIslemi]()
                for item in raw { if seen.insert(item.id).inserted { result.append(item) } }
                if result.count != raw.count {
                    print("🔧 [ExitSync] deduped \(raw.count)→\(result.count) docs (same-UUID duplicates removed)")
                }
                return result
            }()
            let exitler = self.filterActiveExits(deduped, source: "loadExitIslemleri")
            completion(exitler, nil)
        }
    }

    func saveExitIslemi(_ exit: ExitIslemi, completion: @escaping (Error?) -> Void) {
        var exitToSave = exit
        exitToSave.franchiseId = currentFranchiseId
        LogManager.shared.firebase("Saving exit to Firebase", operation: "saveExitIslemi")
        self.writeEncodableDocument(
            baseName: "exitIslemleri",
            documentId: exitToSave.id.uuidString,
            value: exitToSave
        ) { error in
            if let error = error {
                LogManager.shared.error("Error saving exit", error: error)
                Crashlytics.crashlytics().record(error: error)
            } else {
                LogManager.shared.success("Exit başarıyla Firebase'e kaydedildi - Status: \(exitToSave.status.rawValue)")
            }
            completion(error)
        }
    }

    func deleteExitIslemi(_ exit: ExitIslemi, completion: @escaping (Error?) -> Void) {
        softDeleteDocument(baseName: "exitIslemleri", documentId: exit.id.uuidString, completion: completion)
    }

    /// After deleting a completed checkout, suppress stale waiting siblings (same vehicle + NAV/RES token).
    func softDeleteSiblingPendingExits(
        matching deletedExit: ExitIslemi,
        completion: @escaping (Int, Error?) -> Void
    ) {
        guard requireAuth(context: "softDeleteSiblingPendingExits") else {
            completion(0, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }

        func normalizedToken(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = trimmed.filter { $0.isNumber }
            return digits.isEmpty ? trimmed.uppercased() : String(digits)
        }

        let targetToken = normalizedToken((deletedExit.navKodu ?? deletedExit.resKodu))
        guard !targetToken.isEmpty else {
            completion(0, nil)
            return
        }

        getFilteredQuery("exitIslemleri")
            .whereField("aracId", isEqualTo: deletedExit.aracId.uuidString)
            .whereField("status", in: ["In Progress", "Parked"])
            .limit(to: 100)
            .getDocuments { [weak self] snapshot, error in
                guard let self else {
                    completion(0, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"]))
                    return
                }
                if let error {
                    completion(0, error)
                    return
                }
                let docs = snapshot?.documents ?? []
                let candidates = docs.compactMap { doc -> ExitIslemi? in
                    try? doc.data(as: ExitIslemi.self)
                }.filter { ex in
                    guard ex.id != deletedExit.id else { return false }
                    guard !ex.isDeleted else { return false }
                    let token = normalizedToken(ex.navKodu ?? ex.resKodu)
                    return token == targetToken
                }

                guard !candidates.isEmpty else {
                    completion(0, nil)
                    return
                }

                let group = DispatchGroup()
                var firstError: Error?
                var deletedCount = 0
                for ex in candidates {
                    group.enter()
                    self.deleteExitIslemi(ex) { deleteError in
                        if let deleteError, firstError == nil {
                            firstError = deleteError
                        } else if deleteError == nil {
                            deletedCount += 1
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    completion(deletedCount, firstError)
                }
            }
    }

    func fetchExitIslemi(id: UUID, completion: @escaping (ExitIslemi?, Error?) -> Void) {
        guard requireAuth(context: "fetchExitIslemi") else {
            completion(nil, nil)
            return
        }
        getCollectionReference("exitIslemleri").document(id.uuidString).getDocument { snapshot, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let snapshot, snapshot.exists else {
                completion(nil, nil)
                return
            }
            do {
                let exit = try snapshot.data(as: ExitIslemi.self)
                completion(exit, nil)
            } catch {
                completion(nil, error)
            }
        }
    }
    
    func observeExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeExitIslemleri") else {
            completion([], nil)
            return nil
        }
        var query = getFilteredQuery("exitIslemleri")
        if OptimizationFeatureFlags.listenerScopeV2 {
            query = query
                .order(by: "createdAt", descending: true)
                .limit(to: 1200)
        }
        let listener = query
            .addSnapshotListener { querySnapshot, error in
                let t0 = CFAbsoluteTimeGetCurrent()
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        print("⚠️ Permission denied for Exit listener - user may need to re-authenticate")
                    }
                    completion(nil, error)
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                let raw = documents.compactMap { document -> ExitIslemi? in
                    try? document.data(as: ExitIslemi.self)
                }
                let deduped: [ExitIslemi] = {
                    var seen = Set<UUID>()
                    var result = [ExitIslemi]()
                    for item in raw { if seen.insert(item.id).inserted { result.append(item) } }
                    if result.count != raw.count {
                        print("🔧 [ExitSync] deduped \(raw.count)→\(result.count) docs (same-UUID duplicates removed)")
                    }
                    return result
                }()
                let exitler = self.filterActiveExits(deduped, source: "observeExitIslemleri")
                self.logPerf("observeExitIslemleri", start: t0, count: documents.count)
                completion(exitler, nil)
            }
        
        return listener
    }

    // MARK: - Exit / return sync diagnostics (soft-delete + duplicates)

    private func filterActiveExits(_ raw: [ExitIslemi], source: String) -> [ExitIslemi] {
        let active = raw.filter { !$0.isDeleted }
        logExitDiagnostics(raw: raw, active: active, source: source)
        return active
    }

    private func filterActiveReturns(_ raw: [IadeIslemi], source: String) -> [IadeIslemi] {
        let active = raw.filter { !$0.isDeleted }
        logReturnDiagnostics(raw: raw, active: active, source: source)
        return active
    }

    private func logExitDiagnostics(raw: [ExitIslemi], active: [ExitIslemi], source: String) {
        let hidden = raw.filter { $0.isDeleted }.count
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let todayActive = active.filter { $0.createdAt >= today && $0.createdAt < tomorrow }
        let todayWaiting = todayActive.filter { $0.status == .inProgress }.count
        let todayParked = todayActive.filter { $0.status == .parked }.count
        let todayCompleted = todayActive.filter { $0.status == .completed }.count
        print("📊 [ExitSync] \(source) docs=\(raw.count) active=\(active.count) softDeletedHidden=\(hidden) | today: total=\(todayActive.count) inProgress=\(todayWaiting) parked=\(todayParked) completed=\(todayCompleted)")

        // Duplicate checks should only consider open rows.
        // Completed checkouts naturally repeat for the same vehicle/NAV over time.
        let open = active.filter { $0.status == .inProgress || $0.status == .parked }

        // UUID-based duplicate detection (same document loaded from two Firestore paths)
        var uuidCounts: [UUID: Int] = [:]
        for ex in open { uuidCounts[ex.id, default: 0] += 1 }
        let uuidDupes = uuidCounts.filter { $0.value > 1 }
        if !uuidDupes.isEmpty {
            for (uuid, count) in uuidDupes.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                print("⚠️ [ExitSync] DUPLICATE active checkout UUID=\(uuid.uuidString) appears \(count) times (cross-path duplicate)")
            }
        }

        // Business-logic duplicate detection (same plate+NAV, different UUIDs)
        var buckets: [String: [UUID]] = [:]
        for ex in open {
            let nav = normalizedNavToken(nav: ex.navKodu, res: ex.resKodu)
            let plt = normalizedPlateKey(ex.aracPlaka)
            guard !plt.isEmpty else { continue }
            let key = "\(plt)|\(nav.lowercased())"
            buckets[key, default: []].append(ex.id)
        }
        let dupes = buckets.filter { $0.value.count > 1 }
        if !dupes.isEmpty {
            for (key, ids) in dupes.sorted(by: { $0.key < $1.key }) {
                print("⚠️ [ExitSync] DUPLICATE active checkouts (plate|NAV)=\(key) ids=\(ids.map { $0.uuidString })")
            }
        }
        if hidden > 0 {
            let sample = raw.filter { $0.isDeleted }.prefix(5).map { "\($0.id.uuidString.prefix(8))…" }
            print("🧹 [ExitSync] soft-deleted rows still in Firestore (filtered on client): \(sample.joined(separator: ", "))")
        }
    }

    private func logReturnDiagnostics(raw: [IadeIslemi], active: [IadeIslemi], source: String) {
        let hidden = raw.filter { $0.isDeleted }.count
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let todayActive = active.filter { $0.createdAt >= today && $0.createdAt < tomorrow }
        let todayInProg = todayActive.filter { $0.status != .completed }.count
        let todayDone = todayActive.filter { $0.status == .completed }.count
        print("📊 [ReturnSync] \(source) docs=\(raw.count) active=\(active.count) softDeletedHidden=\(hidden) | today: total=\(todayActive.count) open=\(todayInProg) completed=\(todayDone)")

        // Duplicate checks should only consider open rows.
        // Completed returns are historical records and can repeat for the same plate.
        let open = active.filter { $0.status != .completed }
        var buckets: [String: [UUID]] = [:]
        for r in open {
            let key = returnDedupeKey(r)
            guard !key.isEmpty else { continue }
            buckets[key, default: []].append(r.id)
        }
        let dupes = buckets.filter { $0.value.count > 1 }
        if !dupes.isEmpty {
            for (plate, ids) in dupes.sorted(by: { $0.key < $1.key }) {
                print("⚠️ [ReturnSync] DUPLICATE active returns plate=\(plate) ids=\(ids.map { $0.uuidString })")
            }
        }
    }

    private func normalizedPlateKey(_ plate: String) -> String {
        plate
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    }

    private func normalizedNavToken(nav: String?, res: String) -> String {
        let raw = (nav ?? res).trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = raw.filter { $0.isNumber }
        if !digits.isEmpty { return String(digits) }
        return raw.uppercased()
            .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    }

    private func returnDedupeKey(_ item: IadeIslemi) -> String {
        if let linked = item.linkedExitId {
            return "le:\(linked.uuidString.lowercased())"
        }
        return "plt:\(normalizedPlateKey(item.aracPlaka))"
    }

    // MARK: - Migration: Add createdAt to existing exit operations
    /// Migrates existing exit operations to add createdAt field (30 November 2024)
    /// This function safely adds createdAt to all exit operations that don't have it
    func migrateExitOperationsCreatedAt(completion: @escaping (Int, Error?) -> Void) {
        // Set today's date (30 November 2024)
        let today = Date()
        var updateCount = 0
        var allErrors: [Error] = []
        
        self.readFilteredQuery(baseName: "exitIslemleri") { [weak self] querySnapshot, error in
            guard let self = self else {
                completion(0, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"]))
                return
            }
            
            if let error = error {
                completion(0, error)
                return
            }
            
            guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                print("✅ No exit operations found to migrate")
                completion(0, nil)
                return
            }
            
            // Filter documents that need createdAt
            let documentsToUpdate = documents.filter { doc in
                let data = doc.data()
                return data["createdAt"] == nil
            }
            
            if documentsToUpdate.isEmpty {
                print("✅ All exit operations already have createdAt field")
                completion(0, nil)
                return
            }
            
            print("🔄 Starting migration: \(documentsToUpdate.count) exit operations need createdAt field")
            
            // Process documents in batches (Firestore batch limit is 500)
            let batchSize = 500
            let batches = documentsToUpdate.chunked(into: batchSize)
            let group = DispatchGroup()
            
            for (batchIndex, batch) in batches.enumerated() {
                group.enter()
                let currentBatch = self.db.batch()
                
                for document in batch {
                    let docRef = self.getCollectionReference("exitIslemleri").document(document.documentID)
                    currentBatch.updateData(["createdAt": Timestamp(date: today)], forDocument: docRef)
                    updateCount += 1
                }
                
                currentBatch.commit { batchError in
                    if let batchError = batchError {
                        print("❌ Batch \(batchIndex + 1) update error: \(batchError.localizedDescription)")
                        allErrors.append(batchError)
                    } else {
                        print("✅ Batch \(batchIndex + 1) of \(batch.count) documents updated")
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                if allErrors.isEmpty {
                    print("✅ Migration completed successfully: \(updateCount) exit operations updated with createdAt (30 November 2024)")
                    completion(updateCount, nil)
                } else {
                    let finalError = allErrors.first ?? NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Some batches failed"])
                    print("⚠️ Migration completed with errors: \(updateCount) updated, \(allErrors.count) batches failed")
                    completion(updateCount, finalError)
                }
            }
        }
    }

    // MARK: - Activity İşlemleri

    func loadActivities(limit: Int = 100, completion: @escaping ([Activity]?, Error?) -> Void) {
        let capped = max(1, min(limit, 500))
        readFilteredQuery(
            baseName: "activities",
            queryBuilder: { $0.order(by: "tarih", descending: true).limit(to: capped) }
        ) { querySnapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                let activities = documents.compactMap { document -> Activity? in
                    try? document.data(as: Activity.self)
                }
                
                completion(activities, nil)
        }
    }

    /// Deletes all `activities` documents for `currentFranchiseId` (scoped path). Paginates in batches of at most 450 writes per commit.
    func deleteAllActivitiesForCurrentFranchise(completion: @escaping (Error?) -> Void) {
        let pageSize = 450
        func deleteNextBatch() {
            readFilteredQuery(
                baseName: "activities",
                queryBuilder: { $0.order(by: "tarih", descending: true).limit(to: pageSize) }
            ) { snapshot, error in
                if let error {
                    DispatchQueue.main.async { completion(error) }
                    return
                }
                let docs = snapshot?.documents ?? []
                if docs.isEmpty {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let batch = self.db.batch()
                for doc in docs {
                    batch.deleteDocument(doc.reference)
                }
                batch.commit { batchError in
                    if let batchError {
                        DispatchQueue.main.async { completion(batchError) }
                        return
                    }
                    if docs.count < pageSize {
                        DispatchQueue.main.async { completion(nil) }
                    } else {
                        deleteNextBatch()
                    }
                }
            }
        }
        deleteNextBatch()
    }

    func saveActivity(_ activity: Activity, completion: @escaping (Error?) -> Void) {
        var activityToSave = activity
        activityToSave.franchiseId = currentFranchiseId
        writeEncodableDocument(
            baseName: "activities",
            documentId: activityToSave.id.uuidString,
            value: activityToSave,
            completion: completion
        )
    }
    
    // MARK: - SMTP Configuration + Outgoing Email
    
    func loadSMTPConfiguration(completion: @escaping (SMTPConfiguration?, Error?) -> Void) {
        let candidateIds = smtpConfigurationLookupIds(for: currentFranchiseId)
        loadSMTPConfiguration(from: candidateIds, index: 0, completion: completion)
    }

    private func smtpConfigurationLookupIds(for franchiseId: String) -> [String] {
        let normalized = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("CH_") {
            return dedupeSmtpIds([normalized, "CH"])
        }
        if normalized.hasPrefix("TR_") {
            var ids: [String] = [normalized]
            // Branch storage keys vs older franchise doc ids (smtpConfigurations).
            if normalized == "TR_IST_SABIHA" { ids.append("TR_SABIHAGOKCEN") }
            if normalized == "TR_SABIHAGOKCEN" { ids.append("TR_IST_SABIHA") }
            ids.append("TR")
            return dedupeSmtpIds(ids)
        }
        return [normalized]
    }

    private func dedupeSmtpIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in ids {
            let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    private func loadSMTPConfiguration(from ids: [String], index: Int, completion: @escaping (SMTPConfiguration?, Error?) -> Void) {
        guard index < ids.count else {
            completion(defaultSMTPConfigurationForCurrentFranchise(), nil)
            return
        }
        let id = ids[index]
        db.collection("smtpConfigurations").document(id).getDocument { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let snapshot = snapshot, snapshot.exists else {
                self.loadSMTPConfiguration(from: ids, index: index + 1, completion: completion)
                return
            }
            do {
                let config = try snapshot.data(as: SMTPConfiguration.self)
                completion(config, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    private func defaultSMTPConfigurationForCurrentFranchise() -> SMTPConfiguration {
        return SMTPConfiguration(franchiseId: currentFranchiseId)
    }
    
    func saveSMTPConfiguration(_ config: SMTPConfiguration, completion: @escaping (Error?) -> Void) {
        do {
            var toSave = config
            toSave.franchiseId = currentFranchiseId
            toSave.updatedAt = Date()
            try db.collection("smtpConfigurations")
                .document(currentFranchiseId)
                .setData(from: toSave) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }
    
    func queueReturnEmail(
        to recipient: String,
        subject: String,
        body: String,
        pdfURL: String?,
        returnId: String,
        vehiclePlate: String,
        signerName: String,
        signerEmail: String,
        forceResend: Bool = false,
        pdfURLs: [String]? = nil,
        rentalTermsLanguageCode: String? = nil,
        idempotencyKeySuffix: String = "",
        completion: @escaping (Error?, [String]) -> Void
    ) {
        let baseIdempotencyKey =
            "\(returnId)|\(recipient.lowercased())|\(currentFranchiseId)\(idempotencyKeySuffix)"
        let idempotencyKey: String
        if forceResend {
            idempotencyKey = "\(baseIdempotencyKey)|resend|\(UUID().uuidString)"
            print("📧 [ReturnEmailDebug] force resend enabled for returnId=\(returnId)")
        } else {
            idempotencyKey = baseIdempotencyKey
        }

        var payload: [String: Any] = [
            "type": "return_pdf",
            "to": recipient,
            "subject": subject,
            "body": body,
            "pdfURL": pdfURL ?? "",
            "returnId": returnId,
            "vehiclePlate": vehiclePlate,
            "signerName": signerName,
            "signerEmail": signerEmail,
            "franchiseId": currentFranchiseId,
            "idempotencyKey": idempotencyKey,
            "status": "queued",
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let pdfURLs = pdfURLs?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), !pdfURLs.isEmpty {
            payload["pdfURLs"] = pdfURLs
        }
        if let rentalTermsLanguageCode = rentalTermsLanguageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rentalTermsLanguageCode.isEmpty {
            payload["rentalTermsLanguage"] = rentalTermsLanguageCode.lowercased()
        }
        if forceResend {
            payload["forceResend"] = true
            payload["resendRequestedAt"] = FieldValue.serverTimestamp()
        }
        
        let ref = db.collection("franchises")
            .document(currentFranchiseId)
            .collection("outgoingEmails")
            .document()
        ref.setData(payload) { [weak self] error in
            guard let self else {
                completion(error, [])
                return
            }
            if error == nil {
                self.debugObserveQueuedEmailStatus(ref)
                completion(nil, [ref.path])
            } else {
                completion(error, [])
            }
        }
    }
    
    func saveMarketingCampaign(
        name: String,
        emails: [String],
        source: String = "returns",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard requireAuth(context: "saveMarketingCampaign") else {
            completion(.failure(NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }
        
        let normalized = Set(
            emails
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && $0.contains("@") }
        )
        let normalizedEmails = Array(normalized).sorted()
        
        guard !normalizedEmails.isEmpty else {
            completion(.failure(NSError(
                domain: "FirebaseService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No valid emails to export"]
            )))
            return
        }
        
        let campaignName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Return Email Export \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let payload: [String: Any] = [
            "name": campaignName,
            "source": source,
            "franchiseId": currentFranchiseId,
            "emails": normalizedEmails,
            "recipientCount": normalizedEmails.count,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": Auth.auth().currentUser?.uid ?? ""
        ]
        
        let ref = getCollectionReference("marketingCampaigns").document()
        ref.setData(payload) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(ref.path))
            }
        }
    }

    func saveCustomerInfoScan(_ record: CustomerInfoScanRecord, completion: @escaping (Error?) -> Void) {
        var toSave = record
        toSave.franchiseId = currentFranchiseId
        if toSave.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toSave.id = UUID().uuidString
        }
        writeEncodableDocument(
            baseName: "customerInfoScans",
            documentId: toSave.id,
            value: toSave,
            completion: completion
        )
    }

    @discardableResult
    func observeCustomerInfoScans(completion: @escaping ([CustomerInfoScanRecord]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeCustomerInfoScans") else {
            completion([])
            return nil
        }
        return getFilteredQuery("customerInfoScans")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { querySnapshot, error in
                if let error {
                    print("❌ customerInfoScans listener error: \(error.localizedDescription)")
                    completion([])
                    return
                }
                let docs = querySnapshot?.documents ?? []
                let records: [CustomerInfoScanRecord] = docs.compactMap { doc in
                    var item = try? doc.data(as: CustomerInfoScanRecord.self)
                    if item == nil {
                        let data = doc.data()
                        item = CustomerInfoScanRecord(
                            id: doc.documentID,
                            franchiseId: data["franchiseId"] as? String ?? self.currentFranchiseId,
                            documentType: data["documentType"] as? String ?? "",
                            navCode: data["navCode"] as? String ?? "",
                            firstName: data["firstName"] as? String ?? "",
                            lastName: data["lastName"] as? String ?? "",
                            fullNameRaw: data["fullNameRaw"] as? String ?? "",
                            photoURLs: data["photoURLs"] as? [String] ?? [],
                            extractedText: data["extractedText"] as? String ?? "",
                            createdBy: data["createdBy"] as? String ?? "",
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }
                    item?.id = doc.documentID
                    return item
                }
                completion(records)
            }
    }

    func deleteCustomerInfoScan(_ id: String, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "customerInfoScans", documentId: id, completion: completion)
    }

    // MARK: - Front desk TR handover (web → iOS prefill)

    func fetchFrontDeskHandoverDocuments(
        forVehicleId aracId: UUID,
        completion: @escaping (QuerySnapshot?, Error?) -> Void
    ) {
        guard requireAuth(context: "fetchFrontDeskHandoverDocuments") else {
            completion(nil, nil)
            return
        }
        let base = getFilteredQuery("frontDeskCustomers")
            .whereField("handoverAracId", isEqualTo: aracId.uuidString)
            .limit(to: 24)
        // Prefer ordered query for deterministic "latest prefill" selection.
        // Fallback is the legacy path to avoid hard dependency on a new index.
        if OptimizationFeatureFlags.listenerScopeV2 {
            base
                .order(by: "submittedAt", descending: true)
                .getDocuments { snapshot, error in
                    if let error = error as NSError?,
                       error.domain == "FIRFirestoreErrorDomain",
                       (error.code == 9 || error.code == 7) {
                        base.getDocuments(completion: completion)
                        return
                    }
                    completion(snapshot, error)
                }
            return
        }
        base.getDocuments(completion: completion)
    }

    func updateFrontDeskCustomerHandoverLifecycle(
        documentId: String,
        iosPrefillStatus: String,
        linkedExitId: String?,
        linkedIadeId: String?,
        completion: @escaping (Error?) -> Void
    ) {
        guard requireAuth(context: "updateFrontDeskCustomerHandoverLifecycle") else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        var payload: [String: Any] = [
            "iosPrefillStatus": iosPrefillStatus,
            "lastHandoverUpdatedAt": FieldValue.serverTimestamp()
        ]
        if let linkedExitId {
            payload["linkedExitId"] = linkedExitId
        }
        if let linkedIadeId {
            payload["linkedIadeId"] = linkedIadeId
        }
        getCollectionReference("frontDeskCustomers").document(documentId).updateData(payload) { error in
            if let error {
                LogManager.shared.warning("Front desk handover lifecycle update failed: \(error.localizedDescription)")
            }
            completion(error)
        }
    }

    /// Same `frontDeskCustomers` rows as the web kiosk — for attaching ID scans / PDFs from the device.
    func observeFrontDeskCustomersForDocuments(
        completion: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration? {
        guard requireAuth(context: "observeFrontDeskCustomersForDocuments") else {
            completion([])
            return nil
        }
        return getFilteredQuery("frontDeskCustomers")
            .order(by: "submittedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("❌ frontDeskCustomers listener: \(error.localizedDescription)")
                    completion([])
                    return
                }
                completion(snapshot?.documents ?? [])
            }
    }

    func appendFrontDeskCustomerDocumentAsset(
        customerDocumentId: String,
        category: String,
        url: String,
        contentType: String,
        fileName: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard requireAuth(context: "appendFrontDeskCustomerDocumentAsset") else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = getCollectionReference("frontDeskCustomers").document(customerDocumentId)
        // Firestore forbids FieldValue.serverTimestamp() inside array elements — use client Timestamp.
        let entry: [String: Any] = [
            "url": url,
            "contentType": contentType,
            "fileName": fileName,
            "uploadedAt": Timestamp(date: Date())
        ]
        ref.getDocument { snap, err in
            if let err {
                completion(err)
                return
            }
            var data = snap?.data() ?? [:]
            var docs = data["customerDocuments"] as? [String: Any] ?? [:]
            var arr = docs[category] as? [[String: Any]] ?? []
            let maxPerCategory = 3
            if arr.count >= maxPerCategory {
                completion(NSError(
                    domain: "FirebaseService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Maximum number of files for this document type is 3."]
                ))
                return
            }
            arr.append(entry)
            docs[category] = arr
            let payload: [String: Any] = [
                "customerDocuments": docs,
                "lastHandoverUpdatedAt": FieldValue.serverTimestamp()
            ]
            if snap?.exists == true {
                ref.updateData(payload, completion: completion)
            } else {
                ref.setData(payload, merge: true, completion: completion)
            }
        }
    }

    /// Removes one asset from `customerDocuments[category]` and optionally deletes the Storage object.
    func removeFrontDeskCustomerDocumentAsset(
        customerDocumentId: String,
        category: String,
        url: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard requireAuth(context: "removeFrontDeskCustomerDocumentAsset") else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }
        let ref = getCollectionReference("frontDeskCustomers").document(customerDocumentId)
        ref.getDocument { snap, err in
            if let err {
                completion(err)
                return
            }
            var data = snap?.data() ?? [:]
            var docs = data["customerDocuments"] as? [String: Any] ?? [:]
            var arr = docs[category] as? [[String: Any]] ?? []
            let before = arr.count
            arr.removeAll { ($0["url"] as? String) == url }
            guard arr.count < before else {
                completion(NSError(domain: "FirebaseService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Asset not found"]))
                return
            }
            docs[category] = arr
            let payload: [String: Any] = [
                "customerDocuments": docs,
                "lastHandoverUpdatedAt": FieldValue.serverTimestamp()
            ]
            ref.updateData(payload) { fireErr in
                if let fireErr {
                    completion(fireErr)
                    return
                }
                if let host = URL(string: url)?.host?.lowercased(),
                   host.contains("firebasestorage.googleapis.com") || host.contains("firebasestorage.app") {
                    self.storage.reference(forURL: url).delete { _ in completion(nil) }
                } else {
                    completion(nil)
                }
            }
        }
    }

    /// Observe a single `frontDeskCustomers` document (e.g. uploaded ID/PDF list).
    func observeFrontDeskCustomerDocument(
        documentId: String,
        completion: @escaping (DocumentSnapshot?, Error?) -> Void
    ) -> ListenerRegistration? {
        guard requireAuth(context: "observeFrontDeskCustomerDocument") else {
            completion(nil, nil)
            return nil
        }
        return getCollectionReference("frontDeskCustomers").document(documentId)
            .addSnapshotListener { snap, err in
                completion(snap, err)
            }
    }

    // MARK: - Customer contact remember (per franchise, keyed by email — same as web `customerContactRemember`)

    private func customerRememberDocId(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "#", with: "_")
            .replacingOccurrences(of: "?", with: "_")
    }

    func fetchCustomerContactRemember(email: String, completion: @escaping ([String: Any]?, Error?) -> Void) {
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard em.contains("@"), em.contains(".") else {
            completion(nil, nil)
            return
        }
        guard requireAuth(context: "fetchCustomerContactRemember") else {
            completion(nil, NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            ))
            return
        }
        let id = customerRememberDocId(email: em)
        let ref = db.collection("franchises").document(currentFranchiseId).collection("customerContactRemember").document(id)
        ref.getDocument { snap, err in
            if let err {
                completion(nil, err)
                return
            }
            guard let snap, snap.exists else {
                completion(nil, nil)
                return
            }
            completion(snap.data(), nil)
        }
    }

    func upsertCustomerContactRemember(
        firstName: String,
        lastName: String,
        email: String,
        source: String,
        completion: @escaping (Error?) -> Void
    ) {
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard em.contains("@"), em.contains(".") else {
            completion(nil)
            return
        }
        guard requireAuth(context: "upsertCustomerContactRemember") else {
            completion(NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            ))
            return
        }
        let id = customerRememberDocId(email: em)
        let ref = db.collection("franchises").document(currentFranchiseId).collection("customerContactRemember").document(id)
        let payload: [String: Any] = [
            "franchiseId": currentFranchiseId.uppercased(),
            "email": em,
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "familyName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastSource": source,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        ref.setData(payload, merge: true, completion: completion)
    }
    
    func exportReturnEmailsIncremental(
        campaignBaseName: String,
        source: String = "returns",
        candidates: [(email: String, sentAt: Date)],
        completion: @escaping (Result<MarketingExportResult, Error>) -> Void
    ) {
        guard requireAuth(context: "exportReturnEmailsIncremental") else {
            completion(.failure(NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )))
            return
        }
        
        var latestByEmail: [String: Date] = [:]
        for candidate in candidates {
            let normalizedEmail = candidate.email
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else { continue }
            if let existingDate = latestByEmail[normalizedEmail] {
                if candidate.sentAt > existingDate {
                    latestByEmail[normalizedEmail] = candidate.sentAt
                }
            } else {
                latestByEmail[normalizedEmail] = candidate.sentAt
            }
        }
        
        guard !latestByEmail.isEmpty else {
            completion(.success(MarketingExportResult(
                exportedCount: 0,
                skippedCount: 0,
                campaignPath: nil,
                totalTrackedEmails: 0
            )))
            return
        }
        
        let campaignsRef = getCollectionReference("marketingCampaigns")
        let safeSource = source
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let targetDocId = "return_emails_\(safeSource)"
        let targetRef = campaignsRef.document(targetDocId)
        
        campaignsRef.whereField("source", isEqualTo: source).getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }
            
            let documents = snapshot?.documents ?? []
            var existingEmails = Set<String>()
            for doc in documents {
                let emails = doc.data()["emails"] as? [String] ?? []
                for email in emails {
                    let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !normalized.isEmpty, normalized.contains("@") {
                        existingEmails.insert(normalized)
                    }
                }
            }
            
            let candidateEmails = Set(latestByEmail.keys)
            let newEmails = Array(candidateEmails.subtracting(existingEmails)).sorted()
            let skippedCount = candidateEmails.count - newEmails.count
            let mergedEmails = Array(existingEmails.union(candidateEmails)).sorted()
            let latestExportedDate = latestByEmail.values.max() ?? Date()
            
            guard !newEmails.isEmpty else {
                completion(.success(MarketingExportResult(
                    exportedCount: 0,
                    skippedCount: skippedCount,
                    campaignPath: targetRef.path,
                    totalTrackedEmails: mergedEmails.count
                )))
                return
            }
            
            let campaignName = campaignBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Return Email Export".localized
                : campaignBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetExists = documents.contains { $0.documentID == targetDocId }
            
            var payload: [String: Any] = [
                "name": campaignName,
                "source": source,
                "franchiseId": self.currentFranchiseId,
                "emails": mergedEmails,
                "recipientCount": mergedEmails.count,
                "lastExportedAt": Timestamp(date: latestExportedDate),
                "lastAddedCount": newEmails.count,
                "updatedAt": FieldValue.serverTimestamp(),
                "createdBy": Auth.auth().currentUser?.uid ?? ""
            ]
            if !targetExists {
                payload["createdAt"] = FieldValue.serverTimestamp()
            }
            
            targetRef.setData(payload, merge: true) { writeError in
                if let writeError {
                    completion(.failure(writeError))
                } else {
                    completion(.success(MarketingExportResult(
                        exportedCount: newEmails.count,
                        skippedCount: skippedCount,
                        campaignPath: targetRef.path,
                        totalTrackedEmails: mergedEmails.count
                    )))
                }
            }
        }
    }

    private func debugObserveQueuedEmailStatus(_ ref: DocumentReference) {
#if DEBUG
        print("📧 [ReturnEmailDebug] watching: \(ref.path)")
        var registration: ListenerRegistration?
        registration = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ [ReturnEmailDebug] listener error (\(ref.path)): \(error.localizedDescription)")
                registration?.remove()
                registration = nil
                return
            }
            guard let data = snapshot?.data() else {
                print("⚠️ [ReturnEmailDebug] document missing: \(ref.path)")
                registration?.remove()
                registration = nil
                return
            }
            
            let status = String(describing: data["status"] ?? "unknown")
            let errorText = String(describing: data["error"] ?? "")
            print("📨 [ReturnEmailDebug] \(ref.path) status=\(status) error=\(errorText)")
            
            let terminalStatuses: Set<String> = [
                "sent",
                "failed",
                "duplicate_skipped"
            ]
            if terminalStatuses.contains(status) {
                print("✅ [ReturnEmailDebug] final status for \(ref.path): \(status)")
                registration?.remove()
                registration = nil
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            if registration != nil {
                print("⏱️ [ReturnEmailDebug] timeout, stop watching: \(ref.path)")
                registration?.remove()
                registration = nil
            }
        }
#endif
    }

    func deleteActivity(_ activity: Activity, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "activities", documentId: activity.id.uuidString, completion: completion)
    }

    // MARK: - Real-Time Listeners

    @discardableResult
    func observeIadeIslemleri(completion: @escaping ([IadeIslemi]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeIadeIslemleri") else {
            completion([])
            return nil
        }
        var query = getFilteredQuery("iadeIslemleri")
        if OptimizationFeatureFlags.listenerScopeV2 {
            query = query
                .order(by: "createdAt", descending: true)
                .limit(to: 1200)
        }
        return query
            .addSnapshotListener { querySnapshot, error in
                let t0 = CFAbsoluteTimeGetCurrent()
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        print("⚠️ Permission denied for İade listener - user may need to re-authenticate")
                    } else {
                        print("❌ İade listener hatası: \(error.localizedDescription)")
                    }
                    ErrorManager.shared.showError(error, context: "Observe Returns")
                    completion([])
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([])
                    return
                }
                
                let raw = documents.compactMap { document -> IadeIslemi? in
                    try? document.data(as: IadeIslemi.self)
                }
                let deduped: [IadeIslemi] = {
                    var seen = Set<UUID>()
                    var result = [IadeIslemi]()
                    for item in raw { if seen.insert(item.id).inserted { result.append(item) } }
                    if result.count != raw.count {
                        print("🔧 [ReturnSync] deduped \(raw.count)→\(result.count) docs (same-UUID duplicates removed)")
                    }
                    return result
                }()
                let iadeler = self.filterActiveReturns(deduped, source: "observeIadeIslemleri")
                self.logPerf("observeIadeIslemleri", start: t0, count: documents.count)
                completion(iadeler)
            }
    }

    @discardableResult
    func observeAraclar(completion: @escaping ([Arac]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeAraclar") else {
            completion([])
            return nil
        }
        return getFilteredQuery("araclar")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        print("⚠️ Permission denied for Araç listener - user may need to re-authenticate")
                    } else {
                        print("❌ Araç listener hatası: \(error.localizedDescription)")
                    }
                    ErrorManager.shared.showError(error, context: "Observe Vehicles")
                    completion([])
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    completion([])
                    return
                }
                
                // Return all vehicles (including soft-deleted) so callers can decide what to
                // filter. The ViewModel keeps two arrays: `araclar` (non-deleted, for display)
                // and `allVehiclesForReports` (all, for counting — matches web behaviour which
                // does not exclude deleted vehicles from damage reports).
                let araclar = documents.compactMap { document -> Arac? in
                    try? document.data(as: Arac.self)
                }

                completion(araclar)
            }
    }

    // MARK: - Servis Firma İşlemleri

    func loadServisFirmalari(completion: @escaping ([ServisFirma]?, Error?) -> Void) {
        readFilteredQuery(baseName: "servisFirmalari") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let firmalar = documents.compactMap { document -> ServisFirma? in
                try? document.data(as: ServisFirma.self)
            }
            
            completion(firmalar, nil)
        }
    }

    func saveServisFirmasi(_ firma: ServisFirma, completion: @escaping (Error?) -> Void) {
        var firmaToSave = firma
        firmaToSave.franchiseId = currentFranchiseId
        writeEncodableDocument(
            baseName: "servisFirmalari",
            documentId: firmaToSave.id.uuidString,
            value: firmaToSave,
            completion: completion
        )
    }

    func updateServisFirmasi(_ firma: ServisFirma, completion: @escaping (Error?) -> Void) {
        var firmaToSave = firma
        firmaToSave.franchiseId = currentFranchiseId
        writeEncodableDocument(
            baseName: "servisFirmalari",
            documentId: firmaToSave.id.uuidString,
            value: firmaToSave,
            completion: completion
        )
    }

    func deleteServisFirmasi(_ firma: ServisFirma, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "servisFirmalari", documentId: firma.id.uuidString, completion: completion)
    }

    // MARK: - Firebase Storage İşlemleri (EKSİK OLAN BÖLÜM)
    
    func uploadImage(_ image: UIImage, path: String, completion: @escaping (String?, Error?) -> Void) {
        // Use ImageOptimizationManager with high quality for best photo quality (0.95 quality)
        guard let imageData = ImageOptimizationManager.shared.getOptimizedJPEGData(from: image, model: .highQuality) else {
            completion(nil, NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Görüntü verisi oluşturulamadı"]))
            return
        }
        let paths = storageWritePaths(for: path)
        let primaryPath = paths.first ?? path
        let primaryRef = storage.reference().child(primaryPath)
        
        primaryRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            let mirrorPaths = Array(paths.dropFirst())
            let group = DispatchGroup()
            var mirrorError: Error?
            for mirrorPath in mirrorPaths {
                group.enter()
                let mirrorRef = self.storage.reference().child(mirrorPath)
                mirrorRef.putData(imageData, metadata: nil) { _, error in
                    if mirrorError == nil, let error {
                        mirrorError = error
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                primaryRef.downloadURL { url, error in
                    if let error = error {
                        completion(nil, error)
                    } else if let url = url {
                        completion(url.absoluteString, mirrorError)
                    }
                }
            }
        }
    }
    
    // Generic data upload (e.g., PDF)
    func uploadData(_ data: Data, path: String, contentType: String? = nil, completion: @escaping (String?, Error?) -> Void) {
        let paths = storageWritePaths(for: path)
        let primaryPath = paths.first ?? path
        let storageRef = storage.reference().child(primaryPath)
        let metadata = StorageMetadata()
        if let contentType = contentType {
            metadata.contentType = contentType
        }
        storageRef.putData(data, metadata: metadata) { metadata, error in
            if let error = error {
                completion(nil, error)
                return
            }
            let mirrorPaths = Array(paths.dropFirst())
            let group = DispatchGroup()
            var mirrorError: Error?
            
            for mirrorPath in mirrorPaths {
                group.enter()
                let mirrorRef = self.storage.reference().child(mirrorPath)
                mirrorRef.putData(data, metadata: metadata) { _, error in
                    if mirrorError == nil, let error {
                        mirrorError = error
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                storageRef.downloadURL { url, error in
                    if let error = error {
                        completion(nil, error)
                    } else if let url = url {
                        completion(url.absoluteString, mirrorError)
                    }
                }
            }
        }
    }

    func downloadImage(from urlString: String, completion: @escaping (UIImage?, Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "URLError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"]))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                completion(nil, NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Görüntü yüklenemedi"]))
                return
            }
            
            completion(image, nil)
        }.resume()
    }
    
    func deleteImage(at path: String, completion: @escaping (Error?) -> Void) {
        let paths = storageWritePaths(for: path)
        let group = DispatchGroup()
        var firstError: Error?
        
        for storagePath in paths {
            group.enter()
            let imageRef = storage.reference().child(storagePath)
            imageRef.delete { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(firstError)
        }
    }
    
    // MARK: - Office Operations
    func saveOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(operation)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // Verify date format - should be TimeInterval since 2001-01-01
            if let dateValue = dict["date"] as? Double {
                print("💾 Date value from encode: \(dateValue)")
                // Check if it's a Unix timestamp (too large) or TimeInterval (smaller)
                // Unix timestamp for 2025 is ~1.7 billion, TimeInterval since 2001 is ~780 million
                if dateValue > 1000000000 {
                    print("⚠️ Date appears to be Unix timestamp, converting to TimeInterval format")
                    // Convert Unix timestamp to TimeInterval format
                    let unixDate = Date(timeIntervalSince1970: dateValue)
                    let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                    let timeInterval = unixDate.timeIntervalSince(baseDate)
                    dict["date"] = timeInterval
                    print("💾 Converted to TimeInterval: \(timeInterval)")
                }
            }

            // Shadow field (Timestamp) for safe cross-platform date encoding.
            // Keep legacy `date` (Apple epoch Double) for backward compatibility.
            dict["dateTs"] = Timestamp(date: operation.date)
            
            // Web uyumluluğu için Traffic Fine için plate field'ını ekle
            if operation.type == .trafficFine, let vehiclePlate = operation.vehiclePlate {
                dict["plate"] = vehiclePlate
                // Web'de status field'ı var, paymentStatus yerine
                if let paymentStatus = operation.paymentStatus {
                    dict["status"] = paymentStatus.lowercased()
                }
            }
            
            // Web uyumluluğu için Banking (Payments): canonical RES + extra fields
            if operation.type == .banking {
                let canon = TrafficAccidentContract.canonicalRES(from: operation.referenceNumber ?? "")
                if !canon.isEmpty {
                    dict["resCode"] = canon
                }
                if let pc = operation.paymentCategory {
                    dict["paymentCategory"] = pc.rawValue
                }
                if let link = operation.linkedTrafficContractDocumentId {
                    dict["linkedTrafficContractDocumentId"] = link
                }
                if let nm = operation.createdByName {
                    dict["createdByName"] = nm
                }
                if let ex = operation.expectedAmount {
                    dict["expectedAmount"] = ex
                }
                if let st = operation.fleetPaymentRecordStatus {
                    dict["fleetPaymentRecordStatus"] = st.rawValue
                }
            }
            
            // Ensure documentId is preserved in the data
            if let documentId = operation.documentId {
                dict["documentId"] = documentId
            }
            
            dict["franchiseId"] = self.currentFranchiseId
            
            // Use documentId if available (for web-compatible operations), otherwise use id.uuidString
            let documentID = operation.documentId ?? operation.id.uuidString
            
            print("💾 Saving office operation: type=\(operation.type.rawValue), id=\(documentID)")
            print("💾 Operation data keys: \(dict.keys.sorted())")
            
            self.writeDictionaryDocument(
                baseName: "office_operations",
                documentId: documentID,
                data: dict
            ) { error in
                if let error = error {
                    print("❌ Error saving office operation: \(error.localizedDescription)")
                } else {
                    print("✅ Office operation saved successfully with ID: \(documentID)")
                }
                completion(error)
            }
        } catch {
            print("❌ Error encoding office operation: \(error.localizedDescription)")
            completion(error)
        }
    }

    func loadOfficeOperations(completion: @escaping ([OfficeOperation]?, Error?) -> Void) {
        readFilteredQuery(baseName: "office_operations") { snapshot, error in
            if let error = error {
                print("❌ Error loading office operations: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents found in office_operations")
                completion([], nil)
                return
            }
            
            print("📊 Loading \(documents.count) office operations from Firebase")
            
            let operations = documents.compactMap { doc -> OfficeOperation? in
                do {
                    let data = doc.data()
                    let operation = try self.decodeOfficeOperation(from: data, documentID: doc.documentID)
                    return operation
                } catch {
                    print("❌ Error decoding office operation \(doc.documentID): \(error.localizedDescription)")
                    print("❌ Document data: \(doc.data())")
                    return nil
                }
            }
            
            print("✅ Successfully loaded \(operations.count) office operations")
            completion(operations, nil)
        }
    }
    
    // Helper function to decode OfficeOperation from Firestore document data
    private func decodeOfficeOperation(from data: [String: Any], documentID: String) throws -> OfficeOperation {
        // Parse date - Web uses TimeInterval, iOS can also use Timestamp
        var date = Date()
        if preferShadowTimestamps, let ts = data["dateTs"] as? Timestamp {
            date = ts.dateValue()
        } else if let timestamp = data["date"] as? Timestamp {
            date = timestamp.dateValue()
        } else if let dateValue = data["date"] as? Double {
            // Handle both formats:
            // 1. TimeInterval format (seconds since 2001-01-01) - used by web and iOS encode
            // 2. Unix timestamp (seconds since 1970-01-01) - sometimes saved incorrectly
            
            let baseDate1970: TimeInterval = 978307200 // 2001-01-01 in seconds since 1970
            
            if dateValue > 1000000000 {
                // Likely a Unix timestamp (values > 1 billion are Unix timestamps for dates after 2001)
                date = Date(timeIntervalSince1970: dateValue)
            } else {
                // TimeInterval format (seconds since 2001-01-01)
                let dateMillis = baseDate1970 + dateValue
                date = Date(timeIntervalSince1970: dateMillis)
            }
        } else {
            print("⚠️ No date field found in document \(documentID), using current date")
        }
        
        // Parse id
        var id = UUID()
        if let idString = data["id"] as? String, let uuid = UUID(uuidString: idString) {
            id = uuid
        }
        
        // Parse type - Handle both iOS and Web format
        guard let typeString = data["type"] as? String else {
            print("⚠️ Missing type field in document \(documentID)")
            throw NSError(domain: "OfficeOperationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing operation type"])
        }
        
        // Normalize type string - handle legacy formats
        let normalizedTypeString: String
        switch typeString.lowercased() {
        case "additionalsales", "additional_sales":
            normalizedTypeString = "Additional Sales"
        case "creditcard", "credit_card":
            normalizedTypeString = "Credit Card Receipt"
        case "posclosing", "pos_closing", "posdailyclosing", "pos_daily_closing":
            normalizedTypeString = "POS Daily Closing"
        case "fuelreceipt", "fuel_receipt":
            normalizedTypeString = "Fuel Receipt"
        case "washing", "washingexpense", "washing_expense":
            normalizedTypeString = "Washing Expense"
        case "banking", "bankingtransaction", "banking_transaction":
            normalizedTypeString = "Banking Transaction"
        case "trafficfine", "traffic_fine":
            normalizedTypeString = "Traffic Fine"
        default:
            normalizedTypeString = typeString // Use as-is if already in correct format
        }
        
        // Try to get type from enum
        guard let type = OfficeOperationType(rawValue: normalizedTypeString) else {
            print("⚠️ Invalid type '\(typeString)' (normalized: '\(normalizedTypeString)') in document \(documentID). Available types: \(OfficeOperationType.allCases.map { $0.rawValue })")
            throw NSError(domain: "OfficeOperationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid operation type: \(typeString)"])
        }
        
        // Parse vehiclePlate - Web uses "plate" for Traffic Fine, iOS uses "vehiclePlate"
        var vehiclePlate: String? = data["vehiclePlate"] as? String
        if vehiclePlate == nil, let plate = data["plate"] as? String {
            vehiclePlate = plate
        }
        
        // Create operation
        var operation = OfficeOperation(
            type: type,
            date: date,
            amount: data["amount"] as? Double ?? 0,
            photos: data["photos"] as? [String] ?? [],
            vehiclePlate: vehiclePlate,
            posCount: data["posCount"] as? Int,
            posAmounts: data["posAmounts"] as? [Double],
            notes: data["notes"] as? String ?? "",
            isCompleted: data["isCompleted"] as? Bool ?? false
        )
        
        operation.id = id
        operation.documentId = documentID
        
        // Set additional fields - Web compatibility
        // Traffic Fine: Web uses "status", iOS uses "paymentStatus"
        if let status = data["status"] as? String {
            operation.paymentStatus = status.capitalized // "pending" -> "Pending"
        } else {
            operation.paymentStatus = data["paymentStatus"] as? String
        }
        
        // Traffic Fine: Web uses "plate" but we already handled it above
        // Traffic Fine: customerName
        operation.customerName = data["customerName"] as? String
        
        // Banking: Web uses "resCode" and "referenceNumber"
        if let resCode = data["resCode"] as? String {
            operation.referenceNumber = resCode
        } else {
            operation.referenceNumber = data["referenceNumber"] as? String
        }
        if type == .banking, let ref = operation.referenceNumber, !TrafficAccidentContract.resDigits(from: ref).isEmpty {
            operation.referenceNumber = TrafficAccidentContract.canonicalRES(from: ref)
        }

        // Other fields
        operation.fineNumber = data["fineNumber"] as? String
        operation.fineType = data["fineType"] as? String
        operation.transactionNumber = data["transactionNumber"] as? String
        operation.bankName = data["bankName"] as? String
        operation.accountNumber = data["accountNumber"] as? String
        operation.transactionType = data["transactionType"] as? String
        operation.productName = data["productName"] as? String
        operation.quantity = data["quantity"] as? Double
        operation.unitPrice = data["unitPrice"] as? Double
        operation.invoiceNumber = data["invoiceNumber"] as? String
        operation.salesPerson = data["salesPerson"] as? String ?? data["additionalSalesBy"] as? String

        operation.createdBy = data["createdBy"] as? String
        operation.createdByName = data["createdByName"] as? String
        operation.franchiseId = (data["franchiseId"] as? String ?? operation.franchiseId).uppercased()
        if let pc = data["paymentCategory"] as? String, let cat = FleetPaymentCategory(rawValue: pc) {
            operation.paymentCategory = cat
        }
        operation.linkedTrafficContractDocumentId = data["linkedTrafficContractDocumentId"] as? String
        operation.expectedAmount = data["expectedAmount"] as? Double
        if let st = data["fleetPaymentRecordStatus"] as? String, let parsed = FleetPaymentRecordStatus(rawValue: st) {
            operation.fleetPaymentRecordStatus = parsed
        }

        return operation
    }

    @discardableResult
    func observeOfficeOperations(completion: @escaping ([OfficeOperation]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeOfficeOperations") else {
            completion([])
            return nil
        }
        return getFilteredQuery("office_operations").addSnapshotListener { snapshot, error in
            if let error = error {
                if FirebaseService.isPermissionError(error) {
                    print("⚠️ Permission denied for Office operations - user may need to re-authenticate")
                } else {
                    print("❌ Office operations listener error: \(error.localizedDescription)")
                }
                completion([])
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents in snapshot")
                completion([])
                return
            }
            
            var successCount = 0
            var errorCount = 0
            
            let operations = documents.compactMap { doc -> OfficeOperation? in
                do {
                    let data = doc.data()
                    let operation = try self.decodeOfficeOperation(from: data, documentID: doc.documentID)
                    successCount += 1
                    return operation
                } catch {
                    errorCount += 1
                    print("❌ Error decoding office operation \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
            
            if errorCount == 0 {
                print("✅ Office operations decoded: \(successCount) items")
            } else {
                print("✅ Office operations decoded: \(successCount) successful, \(errorCount) failed")
            }
            completion(operations)
        }
    }

    // MARK: - Garage service jobs (`franchises/{id}/garageServiceJobs`)

    func saveGarageServiceJob(_ job: GarageServiceJob, completion: @escaping (Error?) -> Void) {
        let docId = job.documentId ?? job.id.uuidString
        var dict: [String: Any] = [
            "id": job.id.uuidString,
            "vehicleId": job.vehicleId.uuidString,
            "vehiclePlate": job.vehiclePlate,
            "targetGarageId": job.targetGarageId,
            "purpose": job.purpose,
            "notes": job.notes,
            "photoURLs": job.photoURLs,
            "completionPhotoURLs": job.completionPhotoURLs,
            "serviceDate": Timestamp(date: job.serviceDate),
            "serviceDateTs": Timestamp(date: job.serviceDate),
            "status": job.status.rawValue,
            "createdAt": Timestamp(date: job.createdAt),
            "createdAtTs": Timestamp(date: job.createdAt),
            "franchiseId": currentFranchiseId,
        ]
        if let createdBy = job.createdBy {
            dict["createdBy"] = createdBy
        }
        if let completedAt = job.completedAt {
            dict["completedAt"] = Timestamp(date: completedAt)
            dict["completedAtTs"] = Timestamp(date: completedAt)
        }
        if let documentId = job.documentId {
            dict["documentId"] = documentId
        }
        if let targetGarageName = job.targetGarageName?.trimmingCharacters(in: .whitespacesAndNewlines), !targetGarageName.isEmpty {
            dict["targetGarageName"] = targetGarageName
            dict["garageName"] = targetGarageName
        }
        if let completionNotes = job.completionNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !completionNotes.isEmpty {
            dict["completionNotes"] = completionNotes
        }
        if let em = job.pickupNotifyEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !em.isEmpty {
            dict["pickupNotifyEmail"] = em
        }

        writeDictionaryDocument(
            baseName: "garageServiceJobs",
            documentId: docId,
            data: dict,
            completion: completion
        )
    }

    private func decodeGarageServiceJob(from data: [String: Any], documentID: String) -> GarageServiceJob? {
        var id = UUID()
        if let idString = data["id"] as? String, let u = UUID(uuidString: idString) {
            id = u
        }

        let vehicleIdString = (data["vehicleId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let vehicleId = UUID(uuidString: vehicleIdString) else {
            print("⚠️ garageServiceJobs \(documentID): missing or invalid vehicleId")
            return nil
        }

        let plate = (data["vehiclePlate"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let garageId = (data["targetGarageId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let purpose = (data["purpose"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = data["notes"] as? String ?? ""
        let photoURLs = data["photoURLs"] as? [String] ?? []
        let completionPhotoURLs = data["completionPhotoURLs"] as? [String] ?? []

        func dateField(primary: String, shadow: String) -> Date? {
            if preferShadowTimestamps, let ts = data[shadow] as? Timestamp {
                return ts.dateValue()
            }
            if let ts = data[primary] as? Timestamp {
                return ts.dateValue()
            }
            return nil
        }

        let serviceDate = dateField(primary: "serviceDate", shadow: "serviceDateTs") ?? Date()
        let createdAt = dateField(primary: "createdAt", shadow: "createdAtTs") ?? Date()
        var completedAt: Date?
        if preferShadowTimestamps, let ts = data["completedAtTs"] as? Timestamp {
            completedAt = ts.dateValue()
        } else if let ts = data["completedAt"] as? Timestamp {
            completedAt = ts.dateValue()
        }

        let statusRaw = (data["status"] as? String ?? GarageServiceJobStatus.pending.rawValue).lowercased()
        let status = GarageServiceJobStatus(rawValue: statusRaw) ?? .pending

        let franchise = (data["franchiseId"] as? String ?? currentFranchiseId).uppercased()
        let notify = (data["pickupNotifyEmail"] as? String ?? data["customerEmail"] as? String ?? data["notifyEmail"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pickupEmail = (notify?.isEmpty == false) ? notify : nil

        return GarageServiceJob(
            id: id,
            documentId: documentID,
            vehicleId: vehicleId,
            vehiclePlate: plate,
            targetGarageId: garageId,
            targetGarageName: (data["targetGarageName"] as? String ?? data["garageName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            purpose: purpose,
            notes: notes,
            photoURLs: photoURLs,
            completionPhotoURLs: completionPhotoURLs,
            serviceDate: serviceDate,
            status: status,
            createdAt: createdAt,
            createdBy: data["createdBy"] as? String,
            completedAt: completedAt,
            completionNotes: (data["completionNotes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            franchiseId: franchise,
            pickupNotifyEmail: pickupEmail
        )
    }

    func deleteGarageServiceJob(documentId: String, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "garageServiceJobs", documentId: documentId, completion: completion)
    }

    @discardableResult
    func observeGarageServiceJobs(completion: @escaping ([GarageServiceJob]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeGarageServiceJobs") else {
            completion([])
            return nil
        }
        return getFilteredQuery("garageServiceJobs").addSnapshotListener { snapshot, error in
            if let error = error {
                if FirebaseService.isPermissionError(error) {
                    print("⚠️ Permission denied for garageServiceJobs")
                } else {
                    print("❌ garageServiceJobs listener error: \(error.localizedDescription)")
                }
                completion([])
                return
            }
            guard let documents = snapshot?.documents else {
                completion([])
                return
            }
            let jobs = documents.compactMap { doc -> GarageServiceJob? in
                self.decodeGarageServiceJob(from: doc.data(), documentID: doc.documentID)
            }
            completion(jobs)
        }
    }
    
    @discardableResult
    func observeAdditionalSalesPeople(completion: @escaping ([String]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeAdditionalSalesPeople") else {
            completion([])
            return nil
        }
        
        return getFilteredQuery("additional_sales_people")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        print("⚠️ Permission denied for additional_sales_people listener")
                    } else {
                        print("❌ additional_sales_people listener error: \(error.localizedDescription)")
                    }
                    completion([])
                    return
                }
                
                let names = (snapshot?.documents ?? [])
                    .compactMap { doc -> String? in
                        let name = (doc.data()["name"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return name.isEmpty ? nil : name
                    }
                let uniqueSorted = Array(Set(names)).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                completion(uniqueSorted)
            }
    }
    
    func addAdditionalSalesPerson(name: String, completion: @escaping (Error?) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(NSError(
                domain: "AdditionalSalesPeople",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"]
            ))
            return
        }
        
        let normalized = trimmed.lowercased()
        let collection = getCollectionReference("additional_sales_people")
        
        collection
            .whereField("normalizedName", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }
                
                if snapshot?.documents.isEmpty == false {
                    completion(nil)
                    return
                }
                
                guard let self else {
                    completion(NSError(
                        domain: "AdditionalSalesPeople",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Service unavailable"]
                    ))
                    return
                }
                
                let payload: [String: Any] = [
                    "name": trimmed,
                    "normalizedName": normalized,
                    "franchiseId": self.currentFranchiseId,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                collection.addDocument(data: payload, completion: completion)
            }
    }

    func updateOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(operation)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // Web uygulaması TimeInterval formatında date bekliyor (seconds since 2001-01-01)
            // Date zaten encode edilirken TimeInterval formatına çevriliyor

            // Shadow field (Timestamp) for safe cross-platform date encoding.
            dict["dateTs"] = Timestamp(date: operation.date)
            
            // Web uyumluluğu için Traffic Fine için plate field'ını ekle
            if operation.type == .trafficFine, let vehiclePlate = operation.vehiclePlate {
                dict["plate"] = vehiclePlate
                // Web'de status field'ı var, paymentStatus yerine
                if let paymentStatus = operation.paymentStatus {
                    dict["status"] = paymentStatus.lowercased()
                }
            }
            
            if operation.type == .banking {
                let canon = TrafficAccidentContract.canonicalRES(from: operation.referenceNumber ?? "")
                if !canon.isEmpty {
                    dict["resCode"] = canon
                }
                if let pc = operation.paymentCategory {
                    dict["paymentCategory"] = pc.rawValue
                }
                if let link = operation.linkedTrafficContractDocumentId {
                    dict["linkedTrafficContractDocumentId"] = link
                }
                if let nm = operation.createdByName {
                    dict["createdByName"] = nm
                }
                if let ex = operation.expectedAmount {
                    dict["expectedAmount"] = ex
                }
                if let st = operation.fleetPaymentRecordStatus {
                    dict["fleetPaymentRecordStatus"] = st.rawValue
                }
            }
            
            // Ensure documentId is preserved in the data
            if let documentId = operation.documentId {
                dict["documentId"] = documentId
            }
            
            dict["franchiseId"] = self.currentFranchiseId
            
            // Use documentId if available (for web-compatible operations), otherwise use id.uuidString
            let documentID = operation.documentId ?? operation.id.uuidString
            
            self.writeDictionaryDocument(
                baseName: "office_operations",
                documentId: documentID,
                data: dict
            ) { error in
                if let error = error {
                    print("❌ Error updating office operation: \(error.localizedDescription)")
                } else {
                    print("✅ Office operation updated successfully with ID: \(documentID)")
                }
                completion(error)
            }
        } catch {
            print("❌ Error encoding office operation for update: \(error.localizedDescription)")
            completion(error)
        }
    }

    func deleteOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Error?) -> Void) {
        // Use documentId if available (for web-compatible operations), otherwise use id.uuidString
        let documentID = operation.documentId ?? operation.id.uuidString
        deleteDocument(baseName: "office_operations", documentId: documentID) { error in
            if let error = error {
                print("❌ Error deleting office operation with documentID \(documentID): \(error.localizedDescription)")
            }
            completion(error)
        }
    }

    // MARK: - Traffic accident contracts (Switzerland — franchise scoped only)
    //
    // Firestore path: `franchises/{franchiseId}/traffic_accident_contracts/{docId}` (same pattern as `office_operations`).
    // Primary creates: optional `idempotencyKey` + `saveTrafficAccidentContractCreateIfAbsent` (stable doc id, transaction no-op on replay).
    //
    // *** Deploy Firestore rules *** — allow this collection only for Swiss franchise ids (`ch`, `ch_*`).
    // See `firestore.rules`: helper `isSwitzerlandFranchiseId` + `scopedRestrictedOfficeAccess` includes `traffic_accident_contracts`.

    func saveTrafficAccidentContract(_ contract: TrafficAccidentContract, completion: @escaping (Error?) -> Void) {
        let documentID = contract.documentId ?? contract.id.uuidString
        let dict = trafficAccidentContractDictionary(contract)
        writeDictionaryDocument(
            baseName: "traffic_accident_contracts",
            documentId: documentID,
            data: dict,
            completion: completion
        )
    }

    /// Primary create with stable doc id + optional `idempotencyKey`: second submit with the same key is a no-op success.
    func saveTrafficAccidentContractCreateIfAbsent(_ contract: TrafficAccidentContract, completion: @escaping (Error?) -> Void) {
        let documentID = contract.documentId ?? contract.id.uuidString
        let dict = trafficAccidentContractDictionary(contract)
        let targets = getWriteCollectionTargets("traffic_accident_contracts")
        guard let coll = targets.first else {
            completion(nil)
            return
        }
        let docRef = coll.document(documentID)
        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(docRef)
                if snapshot.exists {
                    let existingKey = snapshot.data()?["idempotencyKey"] as? String
                    let incoming = contract.idempotencyKey ?? ""
                    if existingKey == incoming || incoming.isEmpty {
                        return nil
                    }
                    let err = NSError(
                        domain: "TrafficAccidentContract",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "A different contract already exists for this document id."]
                    )
                    errorPointer?.pointee = err
                    return nil
                }
                transaction.setData(dict, forDocument: docRef)
                return nil
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }, completion: { _, error in
            completion(error)
        })
    }

    func updateTrafficAccidentContract(_ contract: TrafficAccidentContract, completion: @escaping (Error?) -> Void) {
        let documentID = contract.documentId ?? contract.id.uuidString
        let dict = trafficAccidentContractDictionary(contract)
        writeDictionaryDocument(
            baseName: "traffic_accident_contracts",
            documentId: documentID,
            data: dict,
            completion: completion
        )
    }

    func deleteTrafficAccidentContract(_ contract: TrafficAccidentContract, completion: @escaping (Error?) -> Void) {
        let documentID = contract.documentId ?? contract.id.uuidString
        deleteDocument(baseName: "traffic_accident_contracts", documentId: documentID, completion: completion)
    }

    @discardableResult
    func observeTrafficAccidentContracts(completion: @escaping ([TrafficAccidentContract]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeTrafficAccidentContracts") else {
            completion([])
            return nil
        }
        return getFilteredQuery("traffic_accident_contracts").addSnapshotListener { snapshot, error in
            if let error = error {
                if FirebaseService.isPermissionError(error) {
                    print("⚠️ Permission denied for traffic_accident_contracts listener")
                } else {
                    print("❌ traffic_accident_contracts listener error: \(error.localizedDescription)")
                }
                completion([])
                return
            }
            guard let documents = snapshot?.documents else {
                completion([])
                return
            }
            let items = documents.map { doc in
                self.decodeTrafficAccidentContract(from: doc.data(), documentID: doc.documentID)
            }.sorted { $0.createdAt > $1.createdAt }
            completion(items)
        }
    }

    private func trafficAccidentContractDictionary(_ contract: TrafficAccidentContract) -> [String: Any] {
        let ts = Timestamp(date: contract.createdAt)
        var dict: [String: Any] = [
            "id": contract.id.uuidString,
            "photos": contract.photos,
            "amount": contract.amount,
            "resCode": contract.resCode,
            "createdAt": ts,
            "createdTs": ts,
            "contractIssueDate": Timestamp(date: contract.contractIssueDate),
            "processedDate": Timestamp(date: contract.processedDate),
            "franchiseId": currentFranchiseId
        ]
        if let paid = contract.paidAmount {
            dict["paidAmount"] = paid
        }
        if let cb = contract.createdBy {
            dict["createdBy"] = cb
        }
        if let nm = contract.createdByName {
            dict["createdByName"] = nm
        }
        if let doc = contract.documentId {
            dict["documentId"] = doc
        }
        if let sup = contract.supplementOfDocumentId {
            dict["supplementOfDocumentId"] = sup
        }
        if let idem = contract.idempotencyKey {
            dict["idempotencyKey"] = idem
        }
        if let pm = contract.paymentMethod {
            dict["paymentMethod"] = pm.rawValue
        }
        if let lp = contract.linkedPaymentOfficeOperationDocumentId {
            dict["linkedPaymentOfficeOperationDocumentId"] = lp
        }
        return dict
    }

    private func decodeTrafficAccidentContract(from data: [String: Any], documentID: String) -> TrafficAccidentContract {
        var createdAt = Date()
        if preferShadowTimestamps, let ts = data["createdTs"] as? Timestamp {
            createdAt = ts.dateValue()
        } else if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else if let d = data["createdAt"] as? Double {
            let baseDate1970: TimeInterval = 978307200
            if d > 1000000000 {
                createdAt = Date(timeIntervalSince1970: d)
            } else {
                createdAt = Date(timeIntervalSince1970: baseDate1970 + d)
            }
        }

        var id = UUID()
        if let idStr = data["id"] as? String, let u = UUID(uuidString: idStr) {
            id = u
        }

        let photos = data["photos"] as? [String] ?? []
        let amount = data["amount"] as? Double ?? 0
        let resCode = data["resCode"] as? String ?? ""
        let paidAmount = data["paidAmount"] as? Double
        let createdBy = data["createdBy"] as? String
        let createdByName = data["createdByName"] as? String
        let fid = (data["franchiseId"] as? String ?? currentFranchiseId).uppercased()
        let contractIssueDate: Date = {
            if let ts = data["contractIssueDate"] as? Timestamp { return ts.dateValue() }
            return createdAt
        }()
        let processedDate: Date = {
            if let ts = data["processedDate"] as? Timestamp { return ts.dateValue() }
            return createdAt
        }()
        let supplementOfDocumentId = data["supplementOfDocumentId"] as? String
        let idempotencyKey = data["idempotencyKey"] as? String
        let paymentMethod = (data["paymentMethod"] as? String).flatMap { FleetPaymentCategory(rawValue: $0) }
        let linkedPaymentOfficeOperationDocumentId = data["linkedPaymentOfficeOperationDocumentId"] as? String

        return TrafficAccidentContract(
            id: id,
            documentId: documentID,
            photos: photos,
            amount: amount,
            resCode: resCode,
            paidAmount: paidAmount,
            createdAt: createdAt,
            contractIssueDate: contractIssueDate,
            processedDate: processedDate,
            franchiseId: fid,
            createdBy: createdBy,
            createdByName: createdByName,
            paymentMethod: paymentMethod,
            linkedPaymentOfficeOperationDocumentId: linkedPaymentOfficeOperationDocumentId,
            supplementOfDocumentId: supplementOfDocumentId,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: - Office Returns
    func saveOfficeReturn(_ returnOp: OfficeReturn, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(returnOp)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            dict["franchiseId"] = self.currentFranchiseId
            self.writeDictionaryDocument(
                baseName: "office_Return",
                documentId: returnOp.id.uuidString,
                data: dict,
                completion: completion
            )
        } catch {
            completion(error)
        }
    }

    func loadOfficeReturns(completion: @escaping ([OfficeReturn]?, Error?) -> Void) {
        readFilteredQuery(baseName: "office_Return") { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([], nil)
                return
            }
            
            do {
                let returns = try documents.compactMap { doc -> OfficeReturn? in
                    let data = try JSONSerialization.data(withJSONObject: doc.data())
                    return try JSONDecoder().decode(OfficeReturn.self, from: data)
                }
                completion(returns, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    @discardableResult
    func observeOfficeReturns(completion: @escaping ([OfficeReturn]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeOfficeReturns") else {
            completion([])
            return nil
        }
        return getFilteredQuery("office_Return").addSnapshotListener { snapshot, error in
            if let error = error {
                if FirebaseService.isPermissionError(error) {
                    print("⚠️ Permission denied for Office returns - user may need to re-authenticate")
                } else {
                    print("❌ Office returns listener error: \(error.localizedDescription)")
                }
                completion([])
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([])
                return
            }
            
            do {
                let returns = try documents.compactMap { doc -> OfficeReturn? in
                    let data = try JSONSerialization.data(withJSONObject: doc.data())
                    return try JSONDecoder().decode(OfficeReturn.self, from: data)
                }
                completion(returns)
            } catch {
                print("❌ Office returns decode error: \(error)")
                completion([])
            }
        }
    }

    func updateOfficeReturn(_ returnOp: OfficeReturn, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(returnOp)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            dict["franchiseId"] = self.currentFranchiseId
            self.writeDictionaryDocument(
                baseName: "office_Return",
                documentId: returnOp.id.uuidString,
                data: dict,
                completion: completion
            )
        } catch {
            completion(error)
        }
    }

    func deleteOfficeReturn(_ returnOp: OfficeReturn, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "office_Return", documentId: returnOp.id.uuidString, completion: completion)
    }
    
    // MARK: - Work Schedules (Timetable)
    
    func saveWorkSchedule(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        do {
            guard let userId = schedule.userId as String? else {
                completion(NSError(domain: "WorkScheduleError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"]))
                return
            }
            
            let data: [String: Any] = [
                "userId": userId,
                "userName": schedule.userName,
                "weekStartDate": Timestamp(date: schedule.weekStartDate),
                "franchiseId": self.currentFranchiseId,
                "schedules": schedule.schedules.map { daily in
                    [
                        "dayOfWeek": daily.dayOfWeek,
                        "startTime": daily.startTime,
                        "endTime": daily.endTime,
                        "isVacation": daily.isVacation,
                        "shiftType": daily.shiftType.rawValue
                    ] as [String: Any]
                },
                "weeklyHours": schedule.calculatedWeeklyHours,
                "vacationDays": schedule.calculatedVacationDays,
                "createdAt": Timestamp(date: schedule.createdAt),
                "updatedAt": Timestamp(date: Date())
            ]
            
            let documentId = schedule.id ?? "\(userId)_\(Int(schedule.weekStartDate.timeIntervalSince1970))"
            self.writeDictionaryDocument(
                baseName: "workSchedules",
                documentId: documentId,
                data: data,
                completion: completion
            )
        } catch {
            completion(error)
        }
    }
    
    func loadWorkSchedules(weekStartDate: Date? = nil, completion: @escaping ([WorkSchedule]?, Error?) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let collection = getFilteredQuery("workSchedules")
        var query = collection
        if OptimizationFeatureFlags.enableScopedWorkScheduleQuery,
           let weekStartDate {
            let calendar = Calendar.current
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
            query = collection
                .whereField("weekStartDate", isGreaterThanOrEqualTo: Timestamp(date: weekStartDate))
                .whereField("weekStartDate", isLessThan: Timestamp(date: weekEnd))
                .limit(to: 300)
        }

        query.getDocuments { snapshot, error in
            if let error = error as NSError?,
               OptimizationFeatureFlags.enableScopedWorkScheduleQuery,
               error.domain == "FIRFirestoreErrorDomain",
               (error.code == 9 || error.code == 7) {
                // Non-breaking fallback: load all documents then filter client-side.
                collection.getDocuments { fallbackSnapshot, fallbackError in
                    self.handleLoadWorkSchedulesSnapshot(
                        snapshot: fallbackSnapshot,
                        error: fallbackError,
                        weekStartDate: weekStartDate,
                        completion: completion,
                        start: t0
                    )
                }
                return
            }
            self.handleLoadWorkSchedulesSnapshot(
                snapshot: snapshot,
                error: error,
                weekStartDate: weekStartDate,
                completion: completion,
                start: t0
            )
        }
    }

    private func handleLoadWorkSchedulesSnapshot(
        snapshot: QuerySnapshot?,
        error: Error?,
        weekStartDate: Date?,
        completion: @escaping ([WorkSchedule]?, Error?) -> Void,
        start: CFAbsoluteTime
    ) {
            if let error = error {
                print("❌ Error loading work schedules: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents found in workSchedules collection")
                completion([], nil)
                return
            }
            
            print("📥 Loaded \(documents.count) work schedule documents")
            
            // Parse all documents using the improved parser
            let allSchedules = self.parseWorkSchedulesDocuments(documents)
            print("✅ Parsed \(allSchedules.count) work schedules successfully")
            
            // Filter by week if weekStartDate is provided
            if let weekStart = weekStartDate {
                let calendar = Calendar.current
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                
                let filtered = allSchedules.filter { schedule in
                    let scheduleWeekStart = schedule.weekStartDate
                    let scheduleWeekEnd = calendar.date(byAdding: .day, value: 7, to: scheduleWeekStart) ?? scheduleWeekStart
                    return scheduleWeekStart < weekEnd && scheduleWeekEnd > weekStart
                }
                
                print("📅 Filtered to \(filtered.count) schedules for week starting \(weekStart)")
                self.logPerf("loadWorkSchedules", start: start, count: documents.count)
                completion(filtered, nil)
            } else {
                // Return all schedules
                self.logPerf("loadWorkSchedules", start: start, count: documents.count)
                completion(allSchedules, nil)
            }
    }
    
    private func handleWorkSchedulesDocuments(snapshot: QuerySnapshot?, error: Error?, completion: @escaping ([WorkSchedule]?, Error?) -> Void) {
        if let error = error {
            completion(nil, error)
            return
        }
        
        guard let documents = snapshot?.documents else {
            completion([], nil)
            return
        }
        
        let schedules = documents.compactMap { doc -> WorkSchedule? in
            let data = doc.data()
            var schedule = WorkSchedule(
                userId: data["userId"] as? String ?? "",
                userName: data["userName"] as? String ?? "",
                weekStartDate: (data["weekStartDate"] as? Timestamp)?.dateValue() ?? Date(),
                schedules: [],
                weeklyHours: data["weeklyHours"] as? Double ?? 0,
                vacationDays: data["vacationDays"] as? Int ?? 0
            )
            schedule.id = doc.documentID
            schedule.franchiseId = (data["franchiseId"] as? String ?? "CH").uppercased()
            
            // Parse daily schedules
            if let schedulesData = data["schedules"] as? [[String: Any]] {
                schedule.schedules = schedulesData.compactMap { dailyData in
                    guard let dayOfWeek = dailyData["dayOfWeek"] as? Int,
                          let startTime = dailyData["startTime"] as? String,
                          let endTime = dailyData["endTime"] as? String,
                          let isVacation = dailyData["isVacation"] as? Bool,
                          let shiftTypeString = dailyData["shiftType"] as? String,
                          let shiftType = DailySchedule.ShiftType(rawValue: shiftTypeString) else {
                        return nil
                    }
                    
                    return DailySchedule(
                        dayOfWeek: dayOfWeek,
                        startTime: startTime,
                        endTime: endTime,
                        isVacation: isVacation,
                        shiftType: shiftType
                    )
                }
            }
            
            if let createdAt = data["createdAt"] as? Timestamp {
                schedule.createdAt = createdAt.dateValue()
            }
            if let updatedAt = data["updatedAt"] as? Timestamp {
                schedule.updatedAt = updatedAt.dateValue()
            }
            
            return schedule
        }
        
        completion(schedules, nil)
    }
    
    @discardableResult
    func observeWorkSchedules(weekStartDate: Date? = nil, completion: @escaping ([WorkSchedule]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeWorkSchedules") else {
            completion([])
            return nil
        }
        
        let collection = getFilteredQuery("workSchedules")
        var query = collection
        if OptimizationFeatureFlags.enableScopedWorkScheduleQuery,
           let weekStartDate {
            let calendar = Calendar.current
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
            query = collection
                .whereField("weekStartDate", isGreaterThanOrEqualTo: Timestamp(date: weekStartDate))
                .whereField("weekStartDate", isLessThan: Timestamp(date: weekEnd))
                .limit(to: 300)
        }

        let attachListener: (Query) -> ListenerRegistration = { q in
            q.addSnapshotListener { snapshot, error in
                let t0 = CFAbsoluteTimeGetCurrent()
            if let error = error {
                let nsError = error as NSError
                print("❌ Work schedules listener error: \(error.localizedDescription)")
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   User info: \(nsError.userInfo)")
                
                // Check if it's a permission error
                if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                    print("⚠️ Permission denied - checking authentication...")
                    if Auth.auth().currentUser == nil {
                        print("   User is not authenticated")
                    } else {
                        print("   User is authenticated: \(Auth.auth().currentUser?.uid ?? "unknown")")
                    }
                }
                
                completion([])
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents found in workSchedules collection")
                completion([])
                return
            }
            
            print("📥 Loaded \(documents.count) work schedule documents from Firestore")
            
            // Parse all documents
            let allSchedules = self.parseWorkSchedulesDocuments(documents)
            print("✅ Parsed \(allSchedules.count) work schedules successfully")
            
            // If weekStartDate is provided, filter client-side
            if let weekStart = weekStartDate {
                let calendar = Calendar.current
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                
                let filtered = allSchedules.filter { schedule in
                    let scheduleWeekStart = schedule.weekStartDate
                    let scheduleWeekEnd = calendar.date(byAdding: .day, value: 7, to: scheduleWeekStart) ?? scheduleWeekStart
                    let overlaps = scheduleWeekStart < weekEnd && scheduleWeekEnd > weekStart
                    return overlaps
                }
                
                print("📅 Filtered to \(filtered.count) schedules for week starting \(weekStart)")
                self.logPerf("observeWorkSchedules", start: t0, count: documents.count)
                completion(filtered)
            } else {
                // Return all schedules
                self.logPerf("observeWorkSchedules", start: t0, count: documents.count)
                completion(allSchedules)
            }
        }
        }

        if OptimizationFeatureFlags.enableScopedWorkScheduleQuery {
            return attachListener(query)
        }
        return attachListener(collection)
    }
    
    func updateWorkSchedule(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        saveWorkSchedule(schedule, completion: completion)
    }
    
    // Helper function to parse WorkSchedule documents
    private func parseWorkSchedulesDocuments(_ documents: [QueryDocumentSnapshot]) -> [WorkSchedule] {
        return documents.compactMap { doc -> WorkSchedule? in
            let data = doc.data()
            
            // Parse weekStartDate - try multiple formats
            var weekStartDate: Date = Date()
            if let timestamp = data["weekStartDate"] as? Timestamp {
                weekStartDate = timestamp.dateValue()
            } else if let dateValue = data["weekStartDate"] as? Date {
                weekStartDate = dateValue
            } else {
                // Try to extract from document ID if it contains timestamp
                let docId = doc.documentID
                if let timestampString = docId.components(separatedBy: "_").last,
                   let timestamp = Int(timestampString) {
                    weekStartDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                }
            }
            
            // Parse userId and userName
            let userId = data["userId"] as? String ?? ""
            let userName = data["userName"] as? String ?? ""
            
            var schedule = WorkSchedule(
                userId: userId,
                userName: userName.isEmpty ? "Unknown User" : userName,
                weekStartDate: weekStartDate,
                schedules: [],
                weeklyHours: data["weeklyHours"] as? Double ?? 0,
                vacationDays: data["vacationDays"] as? Int ?? 0
            )
            schedule.id = doc.documentID
            schedule.franchiseId = (data["franchiseId"] as? String ?? "CH").uppercased()
            
            // Parse schedules array
            if let schedulesData = data["schedules"] as? [[String: Any]] {
                schedule.schedules = schedulesData.compactMap { dailyData in
                    guard let dayOfWeek = dailyData["dayOfWeek"] as? Int,
                          let startTime = dailyData["startTime"] as? String,
                          let endTime = dailyData["endTime"] as? String,
                          let isVacation = dailyData["isVacation"] as? Bool,
                          let shiftTypeString = dailyData["shiftType"] as? String,
                          let shiftType = DailySchedule.ShiftType(rawValue: shiftTypeString) else {
                        print("   ⚠️ Failed to parse daily schedule: \(dailyData)")
                        return nil
                    }
                    
                    return DailySchedule(
                        dayOfWeek: dayOfWeek,
                        startTime: startTime,
                        endTime: endTime,
                        isVacation: isVacation,
                        shiftType: shiftType
                    )
                }
            }
            
            // Parse timestamps
            if let createdAt = data["createdAt"] as? Timestamp {
                schedule.createdAt = createdAt.dateValue()
            } else if let createdAtDate = data["createdAt"] as? Date {
                schedule.createdAt = createdAtDate
            }
            
            if let updatedAt = data["updatedAt"] as? Timestamp {
                schedule.updatedAt = updatedAt.dateValue()
            } else if let updatedAtDate = data["updatedAt"] as? Date {
                schedule.updatedAt = updatedAtDate
            }
            
            return schedule
        }
    }
    
    func deleteWorkSchedule(_ schedule: WorkSchedule, completion: @escaping (Error?) -> Void) {
        guard let id = schedule.id else {
            completion(NSError(domain: "WorkScheduleError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Schedule ID is required"]))
            return
        }
        deleteDocument(baseName: "workSchedules", documentId: id, completion: completion)
    }
    
    // MARK: - Protocol İşlemleri
    
    func loadProtocols(completion: @escaping ([Protocol]?, Error?) -> Void) {
        print("🔄 Firestore'dan protokoller yükleniyor...")
        readFilteredQuery(baseName: "protocols") { querySnapshot, error in
            if let error = error {
                print("❌ Protocol yükleme hatası: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                print("⚠️ QuerySnapshot documents nil")
                completion([], nil)
                return
            }
            
            print("📊 Firestore'dan \(documents.count) document alındı")
            
            // İlk document'i debug için yazdır
            if let firstDoc = documents.first {
                print("🔍 İlk document data: \(firstDoc.data())")
            }
            
            let protocols = documents.compactMap { document -> Protocol? in
                do {
                    var protocolData = try document.data(as: Protocol.self)
                    // Firestore document ID'sini kullan
                    protocolData.id = document.documentID
                    print("✅ Protocol başarıyla decode edildi: \(protocolData.protocolName)")
                    return protocolData
                } catch {
                    print("❌ Protocol decode hatası: \(error.localizedDescription)")
                    print("❌ Document data: \(document.data())")
                    return nil
                }
            }
            
            print("✅ Firestore'dan \(protocols.count) protokol yüklendi")
            completion(protocols, nil)
        }
    }
    
    func saveProtocol(_ `protocol`: Protocol, completion: @escaping (Error?) -> Void) {
        var protocolToSave = `protocol`
        protocolToSave.franchiseId = currentFranchiseId
        self.writeEncodableDocument(
            baseName: "protocols",
            documentId: protocolToSave.id,
            value: protocolToSave
        ) { error in
            if let error = error {
                print("❌ Protocol kaydetme hatası: \(error.localizedDescription)")
            } else {
                print("✅ Protocol başarıyla kaydedildi: \(protocolToSave.id)")
            }
            completion(error)
        }
    }
    
    func updateProtocol(_ `protocol`: Protocol, completion: @escaping (Error?) -> Void) {
        var protocolToSave = `protocol`
        protocolToSave.franchiseId = currentFranchiseId
        self.writeEncodableDocument(
            baseName: "protocols",
            documentId: protocolToSave.id,
            value: protocolToSave
        ) { error in
            if let error = error {
                print("❌ Protocol güncelleme hatası: \(error.localizedDescription)")
            } else {
                print("✅ Protocol başarıyla güncellendi: \(protocolToSave.id)")
            }
            completion(error)
        }
    }
    
    func deleteProtocol(id: String, completion: @escaping (Error?) -> Void) {
        deleteDocument(baseName: "protocols", documentId: id) { error in
            if let error = error {
                print("❌ Protocol silme hatası: \(error.localizedDescription)")
            } else {
                print("✅ Protocol başarıyla silindi: \(id)")
            }
            completion(error)
        }
    }
    
    func observeProtocols(completion: @escaping ([Protocol]) -> Void) {
        print("🔄 Firestore real-time listener başlatılıyor...")
        
        // Önceki listener'ı temizle
        protocolListener?.remove()
        
        protocolListener = getFilteredQuery("protocols")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Protocol listener hatası: \(error.localizedDescription)")
                    print("❌ Listener error details: \(error)")
                    completion([])  // ✅ Error durumunda da completion çağır
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("⚠️ Listener: QuerySnapshot documents nil")
                    completion([])
                    return
                }
                
                print("📊 Listener: Firestore'dan \(documents.count) document alındı")
                
                let protocols = documents.compactMap { document -> Protocol? in
                    do {
                        var protocolData = try document.data(as: Protocol.self)
                        // Firestore document ID'sini kullan
                        protocolData.id = document.documentID
                        print("✅ Listener: Protocol başarıyla decode edildi: \(protocolData.protocolName)")
                        return protocolData
                    } catch {
                        print("❌ Listener: Protocol decode hatası: \(error.localizedDescription)")
                        print("❌ Listener: Document data: \(document.data())")
                        return nil
                    }
                }
                
                print("✅ Real-time update: \(protocols.count) protokol yüklendi")
                completion(protocols)
            }
    }
    
    // Protocol listener cleanup
    func removeProtocolListener() {
        protocolListener?.remove()
        protocolListener = nil
        print("🗑️ Protocol listener removed")
    }
}

// MARK: - Protocol Statistics
struct ProtocolStatistics {
    let totalProtocols: Int
    let draftCount: Int
    let pendingCount: Int
    let completedCount: Int
    let overdueCount: Int
    let cancelledCount: Int
    let totalBaseCost: Double
    let averageBaseCost: Double
    let protocolsByType: [String: Int]
    let protocolsByStatus: [String: Int]
    
    init(protocols: [Protocol]) {
        self.totalProtocols = protocols.count
        
        let statusCounts = Dictionary(grouping: protocols, by: { $0.status.uppercased() })
        self.draftCount = statusCounts["DRAFT"]?.count ?? 0
        self.pendingCount = statusCounts["PENDING"]?.count ?? 0
        self.completedCount = statusCounts["COMPLETE"]?.count ?? 0
        self.overdueCount = statusCounts["OVERDUE"]?.count ?? 0
        self.cancelledCount = statusCounts["CANCELLED"]?.count ?? 0
        
        let baseCosts = protocols.compactMap { $0.baseCostDouble }
        self.totalBaseCost = baseCosts.reduce(0, +)
        self.averageBaseCost = baseCosts.isEmpty ? 0 : totalBaseCost / Double(baseCosts.count)
        
        self.protocolsByType = Dictionary(grouping: protocols, by: { $0.protocolType })
            .mapValues { $0.count }
        
        self.protocolsByStatus = Dictionary(grouping: protocols, by: { $0.status.uppercased() })
            .mapValues { $0.count }
    }
}

// MARK: - Vacation Times
extension FirebaseService {
    func saveVacationTime(_ vacationTime: VacationTime, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(vacationTime)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // Ensure documentId is preserved
            if let documentId = vacationTime.documentId {
                dict["documentId"] = documentId
            }
            
            dict["franchiseId"] = self.currentFranchiseId

            // Shadow fields (Timestamp) for safe cross-platform date encoding.
            // Keep legacy Double fields for backward compatibility (web/iOS).
            dict["startDateTs"] = Timestamp(date: vacationTime.startDate)
            dict["endDateTs"] = Timestamp(date: vacationTime.endDate)
            dict["createdAtTs"] = Timestamp(date: vacationTime.createdAt)
            
            // Use documentId if available, otherwise use id.uuidString
            let documentID = vacationTime.documentId ?? vacationTime.id.uuidString
            
            self.writeDictionaryDocument(
                baseName: "vacationTimes",
                documentId: documentID,
                data: dict
            ) { error in
                if let error = error {
                    print("❌ Vacation time save error: \(error.localizedDescription)")
                } else {
                    print("✅ Vacation time saved: \(vacationTime.employeeName)")
                }
                completion(error)
            }
        } catch {
            print("❌ Vacation time encode error: \(error.localizedDescription)")
            completion(error)
        }
    }
    
    func loadVacationTimes(completion: @escaping ([VacationTime]?, Error?) -> Void) {
        readFilteredQuery(baseName: "vacationTimes") { snapshot, error in
            if let error = error {
                print("❌ Vacation times load error: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No vacation times documents")
                completion([], nil)
                return
            }
            
            let vacationTimes = documents.compactMap { doc -> VacationTime? in
                do {
                    let data = doc.data()
                    // Convert Firestore Timestamps to TimeInterval format
                    var processedData = data
                    
                    // Convert Timestamp fields to TimeInterval
                    let startTs = self.preferShadowTimestamps ? (data["startDateTs"] as? Timestamp) : nil
                    if let startDate = startTs ?? (data["startDate"] as? Timestamp) {
                        let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                        processedData["startDate"] = startDate.dateValue().timeIntervalSince(baseDate)
                    }
                    let endTs = self.preferShadowTimestamps ? (data["endDateTs"] as? Timestamp) : nil
                    if let endDate = endTs ?? (data["endDate"] as? Timestamp) {
                        let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                        processedData["endDate"] = endDate.dateValue().timeIntervalSince(baseDate)
                    }
                    let createdTs = self.preferShadowTimestamps ? (data["createdAtTs"] as? Timestamp) : nil
                    if let createdAt = createdTs ?? (data["createdAt"] as? Timestamp) {
                        let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                        processedData["createdAt"] = createdAt.dateValue().timeIntervalSince(baseDate)
                    }
                    
                    let jsonData = try JSONSerialization.data(withJSONObject: processedData)
                    var vacationTime = try JSONDecoder().decode(VacationTime.self, from: jsonData)
                    vacationTime.documentId = doc.documentID
                    return vacationTime
                } catch {
                    print("❌ Error decoding vacation time \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
            
            print("✅ Loaded \(vacationTimes.count) vacation times")
            completion(vacationTimes, nil)
        }
    }
    
    @discardableResult
    func observeVacationTimes(completion: @escaping ([VacationTime]) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeVacationTimes") else {
            completion([])
            return nil
        }
        // Remove previous listener
        vacationTimesListener?.remove()
        
        vacationTimesListener = getFilteredQuery("vacationTimes")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        print("⚠️ Permission denied for Vacation times - user may need to re-authenticate")
                    } else {
                        print("❌ Vacation times listener error: \(error.localizedDescription)")
                    }
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let vacationTimes = documents.compactMap { doc -> VacationTime? in
                    do {
                        let data = doc.data()
                        // Convert Firestore Timestamps to TimeInterval format
                        var processedData = data
                        
                        // Convert Timestamp fields to TimeInterval
                        let startTs = self.preferShadowTimestamps ? (data["startDateTs"] as? Timestamp) : nil
                        if let startDate = startTs ?? (data["startDate"] as? Timestamp) {
                            let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                            processedData["startDate"] = startDate.dateValue().timeIntervalSince(baseDate)
                        }
                        let endTs = self.preferShadowTimestamps ? (data["endDateTs"] as? Timestamp) : nil
                        if let endDate = endTs ?? (data["endDate"] as? Timestamp) {
                            let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                            processedData["endDate"] = endDate.dateValue().timeIntervalSince(baseDate)
                        }
                        let createdTs = self.preferShadowTimestamps ? (data["createdAtTs"] as? Timestamp) : nil
                        if let createdAt = createdTs ?? (data["createdAt"] as? Timestamp) {
                            let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                            processedData["createdAt"] = createdAt.dateValue().timeIntervalSince(baseDate)
                        }
                        
                        let jsonData = try JSONSerialization.data(withJSONObject: processedData)
                        var vacationTime = try JSONDecoder().decode(VacationTime.self, from: jsonData)
                        vacationTime.documentId = doc.documentID
                        return vacationTime
                    } catch {
                        print("❌ Error decoding vacation time \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                
                print("✅ Vacation times updated: \(vacationTimes.count) items")
                completion(vacationTimes)
            }
        return vacationTimesListener
    }
    
    func deleteVacationTime(_ vacationTime: VacationTime, completion: @escaping (Error?) -> Void) {
        let documentID = vacationTime.documentId ?? vacationTime.id.uuidString
        
        deleteDocument(baseName: "vacationTimes", documentId: documentID) { error in
            if let error = error {
                print("❌ Vacation time delete error: \(error.localizedDescription)")
            } else {
                print("✅ Vacation time deleted: \(vacationTime.employeeName)")
            }
            completion(error)
        }
    }
    
    // MARK: - Assistant Company İşlemleri
    
    func loadAssistantCompanies(completion: @escaping ([AssistantCompany]?, Error?) -> Void) {
        getFilteredQuery("assistantCompanies").order(by: "name").getDocuments { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let companies = documents.compactMap { document -> AssistantCompany? in
                try? document.data(as: AssistantCompany.self)
            }
            
            completion(companies, nil)
        }
    }
    
    func saveAssistantCompany(_ company: AssistantCompany, completion: @escaping (Error?) -> Void) {
        var companyToSave = company
        companyToSave.franchiseId = currentFranchiseId
        // CRITICAL: Use lowercase UUID string to match Firestore document ID format
        let documentId = companyToSave.id.uuidString.lowercased()
        LogManager.shared.firebase("Saving assistant company to Firebase: \(companyToSave.name), documentID: \(documentId)", operation: "saveAssistantCompany")
        self.writeEncodableDocument(
            baseName: "assistantCompanies",
            documentId: documentId,
            value: companyToSave
        ) { error in
            if let error = error {
                LogManager.shared.error("Error saving assistant company", error: error)
                Crashlytics.crashlytics().record(error: error)
            } else {
                LogManager.shared.success("Assistant company başarıyla Firebase'e kaydedildi: \(company.name)")
            }
            completion(error)
        }
    }
    
    func deleteAssistantCompany(_ company: AssistantCompany, completion: @escaping (Error?) -> Void) {
        // CRITICAL FIX: Use lowercase UUID string to match Firestore document ID exactly
        // uuidString property returns uppercase, but Firestore document IDs are lowercase
        // We need to use lowercase to ensure exact match
        let documentId = company.id.uuidString.lowercased()
        LogManager.shared.firebase("Deleting assistant company: \(company.name), documentID: \(documentId) (original: \(company.id.uuidString))", operation: "deleteAssistantCompany")
        
        deleteDocument(baseName: "assistantCompanies", documentId: documentId) { error in
            if let error = error {
                LogManager.shared.error("Error deleting assistant company: \(company.name), documentID: \(documentId)", error: error)
                Crashlytics.crashlytics().record(error: error)
            } else {
                LogManager.shared.success("✅ Assistant company silindi: \(company.name), documentID: \(documentId)")
            }
            completion(error)
        }
    }
    
    func observeAssistantCompanies(completion: @escaping ([AssistantCompany]?, Error?) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeAssistantCompanies") else {
            completion([], nil)
            return nil
        }
        let listener = getFilteredQuery("assistantCompanies")
            .order(by: "name")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    if FirebaseService.isPermissionError(error) {
                        LogManager.shared.warning("Permission denied for assistant companies - user may need to re-authenticate")
                    } else {
                        LogManager.shared.error("Error observing assistant companies", error: error)
                    }
                    completion(nil, error)
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    LogManager.shared.firebase("No assistant companies found", operation: "observeAssistantCompanies")
                    completion([], nil)
                    return
                }
                
                LogManager.shared.firebase("Assistant companies snapshot received: \(documents.count) documents", operation: "observeAssistantCompanies")
                
                let companies = documents.compactMap { document -> AssistantCompany? in
                    // CRITICAL FIX: Use document ID as the primary ID, not the id field inside the document
                    // This ensures that deletion works correctly when documents are created from web
                    guard var company = try? document.data(as: AssistantCompany.self) else {
                        LogManager.shared.error("Failed to decode assistant company from document: \(document.documentID)", error: nil)
                        return nil
                    }
                    
                    // CRITICAL: Use document ID (lowercase) as the source of truth for the id field
                    // UUID(uuidString:) is case-insensitive but uuidString property always returns uppercase
                    // We need to preserve the original document ID case to match Firestore exactly
                    let documentIdLowercase = document.documentID.lowercased()
                    if let documentIdUUID = UUID(uuidString: documentIdLowercase) {
                        company.id = documentIdUUID
                        LogManager.shared.firebase("Assistant company decoded: \(company.name), documentID: \(document.documentID), id: \(company.id.uuidString.lowercased())", operation: "observeAssistantCompanies")
                    } else {
                        LogManager.shared.error("Invalid UUID format in document ID: \(document.documentID)", error: nil)
                        return nil
                    }
                    
                    return company
                }
                
                LogManager.shared.firebase("Assistant companies processed: \(companies.count) companies", operation: "observeAssistantCompanies")
                completion(companies, nil)
            }
        
        return listener
    }
}

