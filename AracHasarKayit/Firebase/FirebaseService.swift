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
    
    private init() {}
    
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
    
    // MARK: - Araç İşlemleri

    func loadAraclar(completion: @escaping ([Arac]?, Error?) -> Void) {
        // Use performance optimizer for background processing
        PerformanceOptimizer.shared.performInBackground {
            self.db.collection("araclar").getDocuments { querySnapshot, error in
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
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            do {
                try self.db.collection("araclar").document(arac.id.uuidString).setData(from: arac) { error in
                    resultCompletion(error)
                }
            } catch {
                resultCompletion(error)
            }
        }, completion: { error in
            completion(error)
        })
    }

    func updateArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            do {
                try self.db.collection("araclar").document(arac.id.uuidString).setData(from: arac) { error in
                    resultCompletion(error)
                }
            } catch {
                resultCompletion(error)
            }
        }, completion: { error in
            completion(error)
        })
    }

    func deleteArac(id: UUID, completion: @escaping (Error?) -> Void) {
        executeWithTimeout(timeout: defaultTimeout, operation: { resultCompletion in
            self.db.collection("araclar").document(id.uuidString).delete { error in
                resultCompletion(error)
            }
        }, completion: { error in
            completion(error)
        })
    }

    // MARK: - Servis İşlemleri

    func loadServisler(completion: @escaping ([ServisKaydi]?, Error?) -> Void) {
        db.collection("servisler").getDocuments { querySnapshot, error in
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
        do {
            try db.collection("servisler").document(servis.id.uuidString).setData(from: servis) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteServis(_ servis: ServisKaydi, completion: @escaping (Error?) -> Void) {
        db.collection("servisler").document(servis.id.uuidString).delete { error in
            completion(error)
        }
    }

    // MARK: - İade İşlemleri

    func loadIadeIslemleri(completion: @escaping ([IadeIslemi]?, Error?) -> Void) {
        db.collection("iadeIslemleri").getDocuments { querySnapshot, error in
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
        do {
            LogManager.shared.firebase("Saving iade to Firebase", operation: "saveIadeIslemi")
            try db.collection("iadeIslemleri").document(iade.id.uuidString).setData(from: iade) { error in
                if let error = error {
                    LogManager.shared.error("Error saving iade", error: error)
                    Crashlytics.crashlytics().record(error: error)
                } else {
                    LogManager.shared.success("İade başarıyla Firebase'e kaydedildi - Status: \(iade.status.rawValue)")
                }
                completion(error)
            }
        } catch {
            LogManager.shared.error("Error encoding iade", error: error)
            Crashlytics.crashlytics().record(error: error)
            completion(error)
        }
    }

    func deleteIadeIslemi(_ iade: IadeIslemi, completion: @escaping (Error?) -> Void) {
        db.collection("iadeIslemleri").document(iade.id.uuidString).delete { error in
            completion(error)
        }
    }

    // MARK: - Exit İşlemleri
    
    func loadExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) {
        db.collection("exitIslemleri").getDocuments { querySnapshot, error in
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
        do {
            LogManager.shared.firebase("Saving exit to Firebase", operation: "saveExitIslemi")
            try db.collection("exitIslemleri").document(exit.id.uuidString).setData(from: exit) { error in
                if let error = error {
                    LogManager.shared.error("Error saving exit", error: error)
                    Crashlytics.crashlytics().record(error: error)
                } else {
                    LogManager.shared.success("Exit başarıyla Firebase'e kaydedildi - Status: \(exit.status.rawValue)")
                }
                completion(error)
            }
        } catch {
            LogManager.shared.error("Error encoding exit", error: error)
            Crashlytics.crashlytics().record(error: error)
            completion(error)
        }
    }

    func deleteExitIslemi(_ exit: ExitIslemi, completion: @escaping (Error?) -> Void) {
        db.collection("exitIslemleri").document(exit.id.uuidString).delete { error in
            completion(error)
        }
    }
    
    func observeExitIslemleri(completion: @escaping ([ExitIslemi]?, Error?) -> Void) -> ListenerRegistration? {
        let listener = db.collection("exitIslemleri")
            .addSnapshotListener { querySnapshot, error in
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
        
        db.collection("exitIslemleri").getDocuments { [weak self] querySnapshot, error in
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
                    let docRef = self.db.collection("exitIslemleri").document(document.documentID)
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
        db.collection("activities")
            .order(by: "tarih", descending: true)
            .limit(to: 100)
            .getDocuments { querySnapshot, error in
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
        do {
            try db.collection("activities").document(activity.id.uuidString).setData(from: activity) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteActivity(_ activity: Activity, completion: @escaping (Error?) -> Void) {
        db.collection("activities").document(activity.id.uuidString).delete { error in
            completion(error)
        }
    }

    // MARK: - Real-Time Listeners

    func observeIadeIslemleri(completion: @escaping ([IadeIslemi]) -> Void) {
        db.collection("iadeIslemleri")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ İade listener hatası: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Observe Returns")
                    // ✅ Error durumunda da completion çağır - UI donmasını önler
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

    func observeAraclar(completion: @escaping ([Arac]) -> Void) {
        db.collection("araclar")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Araç listener hatası: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Observe Vehicles")
                    // ✅ Error durumunda da completion çağır - UI donmasını önler
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
        db.collection("servisFirmalari").getDocuments { querySnapshot, error in
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
        do {
            try db.collection("servisFirmalari").document(firma.id.uuidString).setData(from: firma) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func updateServisFirmasi(_ firma: ServisFirma, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("servisFirmalari").document(firma.id.uuidString).setData(from: firma) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteServisFirmasi(_ firma: ServisFirma, completion: @escaping (Error?) -> Void) {
        db.collection("servisFirmalari").document(firma.id.uuidString).delete { error in
            completion(error)
        }
    }

    // MARK: - Firebase Storage İşlemleri (EKSİK OLAN BÖLÜM)
    
    func uploadImage(_ image: UIImage, path: String, completion: @escaping (String?, Error?) -> Void) {
        // Use ImageOptimizationManager for consistent compression (0.6 quality)
        guard let imageData = ImageOptimizationManager.shared.getOptimizedJPEGData(from: image) else {
            completion(nil, NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Görüntü verisi oluşturulamadı"]))
            return
        }
        
        let storageRef = storage.reference().child(path)
        
        storageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(nil, error)
                } else if let url = url {
                    completion(url.absoluteString, nil)
                }
            }
        }
    }
    
    // Generic data upload (e.g., PDF)
    func uploadData(_ data: Data, path: String, contentType: String? = nil, completion: @escaping (String?, Error?) -> Void) {
        let storageRef = storage.reference().child(path)
        let metadata = StorageMetadata()
        if let contentType = contentType {
            metadata.contentType = contentType
        }
        storageRef.putData(data, metadata: metadata) { metadata, error in
            if let error = error {
                completion(nil, error)
                return
            }
            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(nil, error)
                } else if let url = url {
                    completion(url.absoluteString, nil)
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
        let imageRef = storage.reference().child(path)
        imageRef.delete { error in
            completion(error)
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
            
            // Use documentId if available (for web-compatible operations), otherwise use id.uuidString
            let documentID = operation.documentId ?? operation.id.uuidString
            
            print("💾 Saving office operation: type=\(operation.type.rawValue), id=\(documentID)")
            print("💾 Operation data keys: \(dict.keys.sorted())")
            
            db.collection("office_operations").document(documentID).setData(dict) { error in
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
        db.collection("office_operations").getDocuments { snapshot, error in
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

    func observeOfficeOperations(completion: @escaping ([OfficeOperation]) -> Void) {
        db.collection("office_operations").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Office operations listener error: \(error.localizedDescription)")
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
            
            // Use documentId if available (for web-compatible operations), otherwise use id.uuidString
            let documentID = operation.documentId ?? operation.id.uuidString
            
            db.collection("office_operations").document(documentID).setData(dict) { error in
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
        db.collection("office_operations").document(documentID).delete { error in
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
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            db.collection("office_Return").document(returnOp.id.uuidString).setData(dict) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func loadOfficeReturns(completion: @escaping ([OfficeReturn]?, Error?) -> Void) {
        db.collection("office_Return").getDocuments { snapshot, error in
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

    func observeOfficeReturns(completion: @escaping ([OfficeReturn]) -> Void) {
        db.collection("office_Return").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Office returns listener error: \(error.localizedDescription)")
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
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            db.collection("office_Return").document(returnOp.id.uuidString).setData(dict) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteOfficeReturn(_ returnOp: OfficeReturn, completion: @escaping (Error?) -> Void) {
        db.collection("office_Return").document(returnOp.id.uuidString).delete { error in
            completion(error)
        }
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
            db.collection("workSchedules").document(documentId).setData(data) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    func loadWorkSchedules(weekStartDate: Date? = nil, completion: @escaping ([WorkSchedule]?, Error?) -> Void) {
        let collection = db.collection("workSchedules")
        
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
    
    func observeWorkSchedules(weekStartDate: Date? = nil, completion: @escaping ([WorkSchedule]) -> Void) {
        // Check authentication first
        guard Auth.auth().currentUser != nil else {
            print("❌ User not authenticated - cannot load work schedules")
            completion([])
            return
        }
        
        let collection = db.collection("workSchedules")
        
        // Always load all schedules first, then filter client-side
        // This ensures we get all data even if query fails
        collection.addSnapshotListener { snapshot, error in
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
        db.collection("workSchedules").document(id).delete { error in
            completion(error)
        }
    }
    
    // MARK: - Protocol İşlemleri
    
    func loadProtocols(completion: @escaping ([Protocol]?, Error?) -> Void) {
        print("🔄 Firestore'dan protokoller yükleniyor...")
        db.collection("protocols").getDocuments { querySnapshot, error in
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
        do {
            try db.collection("protocols").document(`protocol`.id).setData(from: `protocol`) { error in
                if let error = error {
                    print("❌ Protocol kaydetme hatası: \(error.localizedDescription)")
                } else {
                    print("✅ Protocol başarıyla kaydedildi: \(`protocol`.id)")
                }
                completion(error)
            }
        } catch {
            print("❌ Protocol encode hatası: \(error.localizedDescription)")
            completion(error)
        }
    }
    
    func updateProtocol(_ `protocol`: Protocol, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("protocols").document(`protocol`.id).setData(from: `protocol`) { error in
                if let error = error {
                    print("❌ Protocol güncelleme hatası: \(error.localizedDescription)")
                } else {
                    print("✅ Protocol başarıyla güncellendi: \(`protocol`.id)")
                }
                completion(error)
            }
        } catch {
            print("❌ Protocol encode hatası: \(error.localizedDescription)")
            completion(error)
        }
    }
    
    func deleteProtocol(id: String, completion: @escaping (Error?) -> Void) {
        db.collection("protocols").document(id).delete { error in
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
        
        protocolListener = db.collection("protocols")
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
            
            // Use documentId if available, otherwise use id.uuidString
            let documentID = vacationTime.documentId ?? vacationTime.id.uuidString
            
            db.collection("vacationTimes").document(documentID).setData(dict) { error in
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
        db.collection("vacationTimes").getDocuments { snapshot, error in
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
    
    func observeVacationTimes(completion: @escaping ([VacationTime]) -> Void) {
        // Remove previous listener
        vacationTimesListener?.remove()
        
        vacationTimesListener = db.collection("vacationTimes")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Vacation times listener error: \(error.localizedDescription)")
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
    }
    
    func deleteVacationTime(_ vacationTime: VacationTime, completion: @escaping (Error?) -> Void) {
        let documentID = vacationTime.documentId ?? vacationTime.id.uuidString
        
        db.collection("vacationTimes").document(documentID).delete { error in
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
        db.collection("assistantCompanies").order(by: "name").getDocuments { querySnapshot, error in
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
        do {
            LogManager.shared.firebase("Saving assistant company to Firebase", operation: "saveAssistantCompany")
            try db.collection("assistantCompanies").document(company.id.uuidString).setData(from: company) { error in
                if let error = error {
                    LogManager.shared.error("Error saving assistant company", error: error)
                    Crashlytics.crashlytics().record(error: error)
                } else {
                    LogManager.shared.success("Assistant company başarıyla Firebase'e kaydedildi: \(company.name)")
                }
                completion(error)
            }
        } catch {
            LogManager.shared.error("Error encoding assistant company", error: error)
            Crashlytics.crashlytics().record(error: error)
            completion(error)
        }
    }
    
    func deleteAssistantCompany(_ company: AssistantCompany, completion: @escaping (Error?) -> Void) {
        db.collection("assistantCompanies").document(company.id.uuidString).delete { error in
            if let error = error {
                LogManager.shared.error("Error deleting assistant company", error: error)
            } else {
                LogManager.shared.success("Assistant company silindi: \(company.name)")
            }
            completion(error)
        }
    }
    
    func observeAssistantCompanies(completion: @escaping ([AssistantCompany]?, Error?) -> Void) -> ListenerRegistration? {
        let listener = db.collection("assistantCompanies")
            .order(by: "name")
            .addSnapshotListener { querySnapshot, error in
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
        
        return listener
    }
}

