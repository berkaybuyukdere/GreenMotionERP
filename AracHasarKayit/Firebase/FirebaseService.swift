import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit
import FirebaseCrashlytics

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    // Protocol listener cleanup
    private var protocolListener: ListenerRegistration?
    
    // Vacation Times listener
    private var vacationTimesListener: ListenerRegistration?
    
    // Timeout configuration
    private let defaultTimeout: TimeInterval = 30.0 // 30 seconds
    
    // Demo user email (backward compatibility)
    private let demoUserEmail = "demo@gmail.com"
    
    /// Cached demo account flag from UserProfile.isDemoAccount (Firestore authoritative source)
    /// Set by AracViewModel after AuthenticationManager loads the user profile
    private(set) var isDemoAccountCached: Bool = false
    
    /// Cached franchise context - set by AracViewModel after profile loads
    private(set) var currentFranchiseId: String = "CH"
    private(set) var currentIsSuperAdmin: Bool = false
    
    /// Franchise-scoped migration flags (runtime switchable via UserDefaults).
    private struct MigrationFlags {
        static let scopedReadsEnabled = "migration.scoped.reads.enabled"
        static let scopedWritesEnabled = "migration.scoped.writes.enabled"
        static let dualWriteEnabled = "migration.dual.write.enabled"
        static let readFallbackToLegacyEnabled = "migration.read.fallback.legacy.enabled"
        static let storageScopedWritesEnabled = "migration.storage.scoped.writes.enabled"
        static let storageDualWriteEnabled = "migration.storage.dual.write.enabled"
        static let storageReadFallbackLegacyEnabled = "migration.storage.read.fallback.legacy.enabled"
    }
    
    /// Update the cached demo status from UserProfile
    func setDemoAccountStatus(_ isDemo: Bool) {
        let previousStatus = isDemoAccountCached
        isDemoAccountCached = isDemo
        if previousStatus != isDemo {
            LogManager.shared.info("FirebaseService demo status updated: \(isDemo)")
        }
    }
    
    /// Update the franchise context from UserProfile
    func setFranchiseContext(franchiseId: String, isSuperAdmin: Bool) {
        let prevFranchise = currentFranchiseId
        let prevAdmin = currentIsSuperAdmin
        currentFranchiseId = franchiseId.uppercased()
        currentIsSuperAdmin = isSuperAdmin
        if prevFranchise != franchiseId || prevAdmin != isSuperAdmin {
            LogManager.shared.info("FirebaseService franchise context updated: franchiseId=\(franchiseId), isSuperAdmin=\(isSuperAdmin)")
        }
    }
    
    // Check if current user is demo user
    // Uses BOTH email pattern matching AND the authoritative isDemoAccount flag from Firestore
    var isDemoUser: Bool {
        // First check the Firestore-backed flag (most reliable)
        if isDemoAccountCached {
            return true
        }
        
        guard let user = Auth.auth().currentUser else { return false }
        let email = user.email?.lowercased() ?? ""
        
        // Check email pattern: *_demo@* or demo_*@* or @demo.example.com
        if email.contains("_demo@") || email.hasPrefix("demo_") || email.hasSuffix("@demo.example.com") {
            return true
        }
        
        // Check old demo email (backward compatibility)
        if email == demoUserEmail {
            return true
        }
        
        return false
    }
    
    // Get collection name with demo prefix if needed (backward compatibility for old demo_* collections)
    private func collectionName(_ baseName: String) -> String {
        // Old demo user (demo@gmail.com) uses demo_* prefix
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return "demo_\(baseName)"
        }
        // New demo users will use subcollection structure via getCollectionReference()
        return baseName
    }
    
    /// Check if user is currently authenticated. Returns false and logs if not.
    private func requireAuth(context: String) -> Bool {
        guard Auth.auth().currentUser != nil else {
            LogManager.shared.warning("Skipping \(context) - user not authenticated")
            return false
        }
        return true
    }
    
    /// Check if a Firestore error is a permission error
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
    }
    
    // Legacy collection reference - handles both production and demo (subcollection) collections.
    private func getLegacyCollectionReference(_ baseName: String) -> CollectionReference {
        guard isDemoUser, let userId = Auth.auth().currentUser?.uid else {
            // Production: normal collection
            return db.collection(baseName)
        }
        
        // Old demo user (demo@gmail.com) uses demo_* prefix for backward compatibility
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return db.collection("demo_\(baseName)")
        }
        
        // New demo users: subcollection structure - demo_environments/{userId}/{baseName}
        return db.collection("demo_environments")
            .document(userId)
            .collection(baseName)
    }
    
    private func getScopedCollectionReference(_ baseName: String) -> CollectionReference {
        // Demo users remain on existing demo isolation model.
        if isDemoUser {
            return getLegacyCollectionReference(baseName)
        }
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
            "fcmTokens"
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
    
    private func getWriteCollectionTargets(_ baseName: String) -> [CollectionReference] {
        if isGlobalCollection(baseName) {
            return [getLegacyCollectionReference(baseName)]
        }
        if isDemoUser {
            return [getLegacyCollectionReference(baseName)]
        }
        
        if isDualWriteEnabled {
            return [getLegacyCollectionReference(baseName), getScopedCollectionReference(baseName)]
        }
        
        if isScopedWritesEnabled {
            return [getScopedCollectionReference(baseName)]
        }
        
        return [getLegacyCollectionReference(baseName)]
    }
    
    /// Get a filtered query for a collection - applies franchise filter unless superadmin
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
        
        // Demo users don't need franchise filtering (they have their own subcollection)
        if isDemoUser {
            return collRef
        }
        
        // Superadmin sees all data across franchises
        if currentIsSuperAdmin {
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
    
    var isScopedWritesEnabled: Bool {
        true
    }
    
    var isDualWriteEnabled: Bool {
        false
    }
    
    var isReadFallbackToLegacyEnabled: Bool {
        false
    }
    
    var isStorageScopedWritesEnabled: Bool {
        true
    }
    
    var isStorageDualWriteEnabled: Bool {
        false
    }
    
    var isStorageReadFallbackLegacyEnabled: Bool {
        false
    }
    
    func configureMigration(
        scopedReads: Bool? = nil,
        scopedWrites: Bool? = nil,
        dualWrite: Bool? = nil,
        readFallbackToLegacy: Bool? = nil,
        storageScopedWrites: Bool? = nil,
        storageDualWrite: Bool? = nil,
        storageReadFallbackLegacy: Bool? = nil
    ) {
        let defaults = UserDefaults.standard
        if let scopedReads {
            defaults.set(scopedReads, forKey: MigrationFlags.scopedReadsEnabled)
        }
        if let scopedWrites {
            defaults.set(scopedWrites, forKey: MigrationFlags.scopedWritesEnabled)
        }
        if let dualWrite {
            defaults.set(dualWrite, forKey: MigrationFlags.dualWriteEnabled)
        }
        if let readFallbackToLegacy {
            defaults.set(readFallbackToLegacy, forKey: MigrationFlags.readFallbackToLegacyEnabled)
        }
        if let storageScopedWrites {
            defaults.set(storageScopedWrites, forKey: MigrationFlags.storageScopedWritesEnabled)
        }
        if let storageDualWrite {
            defaults.set(storageDualWrite, forKey: MigrationFlags.storageDualWriteEnabled)
        }
        if let storageReadFallbackLegacy {
            defaults.set(storageReadFallbackLegacy, forKey: MigrationFlags.storageReadFallbackLegacyEnabled)
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
    
    private func readQueryWithFallback(
        baseName: String,
        queryBuilder: @escaping (Query) -> Query = { $0 },
        completion: @escaping (QuerySnapshot?, Error?) -> Void
    ) {
        let primaryQuery = queryBuilder(getFilteredQuery(baseName))
        primaryQuery.getDocuments { [weak self] snapshot, error in
            guard let self = self else {
                completion(snapshot, error)
                return
            }
            
            // If primary query succeeds and returns rows, use it.
            if let snapshot = snapshot, !snapshot.documents.isEmpty {
                completion(snapshot, nil)
                return
            }
            
            // If scoped read mode is off or fallback is disabled, return as-is.
            guard self.isScopedReadsEnabled, self.isReadFallbackToLegacyEnabled else {
                completion(snapshot, error)
                return
            }
            
            // Fall back to legacy query to avoid migration window data loss in UI.
            let fallbackBaseQuery = self.getLegacyCollectionReference(baseName)
            let fallbackQuery: Query
            if self.isDemoUser || self.currentIsSuperAdmin {
                fallbackQuery = queryBuilder(fallbackBaseQuery)
            } else {
                fallbackQuery = queryBuilder(
                    fallbackBaseQuery.whereField("franchiseId", isEqualTo: self.currentFranchiseId)
                )
            }
            
            fallbackQuery.getDocuments { fallbackSnapshot, fallbackError in
                completion(fallbackSnapshot, fallbackError ?? error)
            }
        }
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
    
    private func scopedStoragePathIfNeeded(_ legacyPath: String) -> String {
        guard !isDemoUser, isStorageScopedWritesEnabled else { return legacyPath }
        let normalized = legacyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("franchises/") {
            return normalized
        }
        return "franchises/\(currentFranchiseId)/\(normalized)"
    }
    
    private func storageWritePaths(for legacyPath: String) -> [String] {
        let scoped = scopedStoragePathIfNeeded(legacyPath)
        guard !isDemoUser else { return [legacyPath] }
        if isStorageDualWriteEnabled && scoped != legacyPath {
            return [legacyPath, scoped]
        }
        return [scoped]
    }
    
    // MARK: - Araç İşlemleri

    func loadAraclar(completion: @escaping ([Arac]?, Error?) -> Void) {
        // Use performance optimizer for background processing
        PerformanceOptimizer.shared.performInBackground {
            self.readQueryWithFallback(baseName: "araclar") { querySnapshot, error in
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
    
    // MARK: - Vehicle Categories
    
    func loadVehicleCategories(completion: @escaping ([VehicleCategory]?, Error?) -> Void) {
        readQueryWithFallback(baseName: "vehicleCategories", queryBuilder: { $0.order(by: "name") }) { querySnapshot, error in
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
        readQueryWithFallback(baseName: "servisler") { querySnapshot, error in
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
        readQueryWithFallback(baseName: "iadeIslemleri") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let iadeler = documents.compactMap { document -> IadeIslemi? in
                try? document.data(as: IadeIslemi.self)
            }
            
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
        deleteDocument(baseName: "iadeIslemleri", documentId: iade.id.uuidString, completion: completion)
    }

    // MARK: - Exit İşlemleri
    
    func loadExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) {
        readQueryWithFallback(baseName: "exitIslemleri") { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let exitler = documents.compactMap { document -> ExitIslemi? in
                try? document.data(as: ExitIslemi.self)
            }
            
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
        deleteDocument(baseName: "exitIslemleri", documentId: exit.id.uuidString, completion: completion)
    }
    
    func observeExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) -> ListenerRegistration? {
        guard requireAuth(context: "observeExitIslemleri") else {
            completion([], nil)
            return nil
        }
        let listener = getFilteredQuery("exitIslemleri")
            .addSnapshotListener { querySnapshot, error in
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
                
                let exitler = documents.compactMap { document -> ExitIslemi? in
                    try? document.data(as: ExitIslemi.self)
                }
                
                completion(exitler, nil)
            }
        
        return listener
    }

    // MARK: - Migration: Add createdAt to existing exit operations
    /// Migrates existing exit operations to add createdAt field (30 November 2024)
    /// This function safely adds createdAt to all exit operations that don't have it
    func migrateExitOperationsCreatedAt(completion: @escaping (Int, Error?) -> Void) {
        // Set today's date (30 November 2024)
        let today = Date()
        var updateCount = 0
        var allErrors: [Error] = []
        
        self.readQueryWithFallback(baseName: "exitIslemleri") { [weak self] querySnapshot, error in
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

    func loadActivities(completion: @escaping ([Activity]?, Error?) -> Void) {
        readQueryWithFallback(
            baseName: "activities",
            queryBuilder: { $0.order(by: "tarih", descending: true).limit(to: 100) }
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
        db.collection("smtpConfigurations").document(currentFranchiseId).getDocument { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let snapshot = snapshot, snapshot.exists else {
                completion(SMTPConfiguration(franchiseId: self.currentFranchiseId), nil)
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
        completion: @escaping (Error?) -> Void
    ) {
        let idempotencyKey = "\(returnId)|\(recipient.lowercased())|\(currentFranchiseId)"
        let payload: [String: Any] = [
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
        
        let shouldDualQueue = isDualWriteEnabled
        let shouldScopedOnlyQueue = isScopedWritesEnabled && !shouldDualQueue
        let group = DispatchGroup()
        var firstError: Error?
        
        if !shouldScopedOnlyQueue {
            group.enter()
            db.collection("outgoingEmails").addDocument(data: payload) { error in
                if firstError == nil, let error {
                    firstError = error
                }
                group.leave()
            }
        }
        
        if shouldDualQueue || shouldScopedOnlyQueue {
            group.enter()
            db.collection("franchises")
                .document(currentFranchiseId)
                .collection("outgoingEmails")
                .addDocument(data: payload) { error in
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
        return getFilteredQuery("iadeIslemleri")
            .addSnapshotListener { querySnapshot, error in
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
                
                let iadeler = documents.compactMap { document -> IadeIslemi? in
                    try? document.data(as: IadeIslemi.self)
                }
                
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
                
                let araclar = documents.compactMap { document -> Arac? in
                    try? document.data(as: Arac.self)
                }
                
                completion(araclar)
            }
    }

    // MARK: - Servis Firma İşlemleri

    func loadServisFirmalari(completion: @escaping ([ServisFirma]?, Error?) -> Void) {
        readQueryWithFallback(baseName: "servisFirmalari") { querySnapshot, error in
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
            
            // Web uyumluluğu için Traffic Fine için plate field'ını ekle
            if operation.type == .trafficFine, let vehiclePlate = operation.vehiclePlate {
                dict["plate"] = vehiclePlate
                // Web'de status field'ı var, paymentStatus yerine
                if let paymentStatus = operation.paymentStatus {
                    dict["status"] = paymentStatus.lowercased()
                }
            }
            
            // Web uyumluluğu için Banking için resCode field'ını ekle
            if operation.type == .banking, let referenceNumber = operation.referenceNumber {
                dict["resCode"] = referenceNumber
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
        readQueryWithFallback(baseName: "office_operations") { snapshot, error in
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
        if let timestamp = data["date"] as? Timestamp {
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

    func updateOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Error?) -> Void) {
        do {
            let data = try JSONEncoder().encode(operation)
            var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // Web uygulaması TimeInterval formatında date bekliyor (seconds since 2001-01-01)
            // Date zaten encode edilirken TimeInterval formatına çevriliyor
            
            // Web uyumluluğu için Traffic Fine için plate field'ını ekle
            if operation.type == .trafficFine, let vehiclePlate = operation.vehiclePlate {
                dict["plate"] = vehiclePlate
                // Web'de status field'ı var, paymentStatus yerine
                if let paymentStatus = operation.paymentStatus {
                    dict["status"] = paymentStatus.lowercased()
                }
            }
            
            // Web uyumluluğu için Banking için resCode field'ını ekle
            if operation.type == .banking, let referenceNumber = operation.referenceNumber {
                dict["resCode"] = referenceNumber
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
        readQueryWithFallback(baseName: "office_Return") { snapshot, error in
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
        let collection = getFilteredQuery("workSchedules")
        
        // Always load all documents, then filter client-side if needed
        // This is more reliable than Firestore queries which may require indexes
        collection.getDocuments { snapshot, error in
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
                completion(filtered, nil)
            } else {
                // Return all schedules
                completion(allSchedules, nil)
            }
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
        
        // Always load all schedules first, then filter client-side
        // This ensures we get all data even if query fails
        return collection.addSnapshotListener { snapshot, error in
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
                completion(filtered)
            } else {
                // Return all schedules
                completion(allSchedules)
            }
        }
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
        readQueryWithFallback(baseName: "protocols") { querySnapshot, error in
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
        readQueryWithFallback(baseName: "vacationTimes") { snapshot, error in
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
                    if let startDate = data["startDate"] as? Timestamp {
                        let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                        processedData["startDate"] = startDate.dateValue().timeIntervalSince(baseDate)
                    }
                    if let endDate = data["endDate"] as? Timestamp {
                        let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                        processedData["endDate"] = endDate.dateValue().timeIntervalSince(baseDate)
                    }
                    if let createdAt = data["createdAt"] as? Timestamp {
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
                        if let startDate = data["startDate"] as? Timestamp {
                            let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                            processedData["startDate"] = startDate.dateValue().timeIntervalSince(baseDate)
                        }
                        if let endDate = data["endDate"] as? Timestamp {
                            let baseDate = Date(timeIntervalSince1970: 978307200) // 2001-01-01
                            processedData["endDate"] = endDate.dateValue().timeIntervalSince(baseDate)
                        }
                        if let createdAt = data["createdAt"] as? Timestamp {
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

