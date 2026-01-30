import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Cascade delete manager for handling related data deletion
/// Ensures data integrity by removing all related records
class CascadeDeleteManager {
    static let shared = CascadeDeleteManager()
    
    private let db = Firestore.firestore()
    private let imageManager = CachedImageManager.shared
    
    // Demo user email (backward compatibility)
    private let demoUserEmail = "demo@gmail.com"
    
    // Check if current user is demo user
    private var isDemoUser: Bool {
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
    
    // Get collection reference - handles both production and demo (subcollection) collections
    private func getCollectionReference(_ baseName: String) -> CollectionReference {
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
    
    // Get collection name with demo prefix if needed (backward compatibility - use getCollectionReference instead)
    private func collectionName(_ baseName: String) -> String {
        // Old demo user (demo@gmail.com) uses demo_* prefix
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return "demo_\(baseName)"
        }
        // New demo users will use subcollection structure via getCollectionReference()
        return baseName
    }
    
    private init() {
        print("✅ CascadeDeleteManager initialized")
    }
    
    // MARK: - Vehicle Cascade Delete
    
    /// Delete vehicle and all related data
    func deleteVehicle(_ arac: Arac, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting cascade delete for vehicle: \(arac.plakaFormatli)")
        
        let batch = db.batch()
        var imagesToDelete: [String] = []
        
        // 1. Collect all images to delete
        for hasar in arac.hasarKayitlari {
            imagesToDelete.append(contentsOf: hasar.fotograflar)
        }
        
        if let headDoc = arac.headDocumentURL {
            imagesToDelete.append(headDoc)
        }
        
        // 2. Delete vehicle document
        let aracRef = getCollectionReference("araclar").document(arac.id.uuidString)
        batch.deleteDocument(aracRef)
        
        // 3. Query and delete related service records
        getCollectionReference("servisler")
            .whereField("aracId", isEqualTo: arac.id.uuidString)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                snapshot?.documents.forEach { doc in
                    batch.deleteDocument(doc.reference)
                }
                
                // 4. Query and delete related activities
                self.db.collection(self.collectionName("activities"))
                    .whereField("aracPlaka", isEqualTo: arac.plaka)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        
                        snapshot?.documents.forEach { doc in
                            batch.deleteDocument(doc.reference)
                        }
                        
                        // 5. Query and delete related returns
                        self.db.collection(self.collectionName("iadeIslemleri"))
                            .whereField("aracId", isEqualTo: arac.id.uuidString)
                            .getDocuments { snapshot, error in
                                if let error = error {
                                    completion(.failure(error))
                                    return
                                }
                                
                                snapshot?.documents.forEach { doc in
                                    batch.deleteDocument(doc.reference)
                                    
                                    // Collect return images
                                    if let data = try? doc.data(as: IadeIslemi.self) {
                                        imagesToDelete.append(contentsOf: data.fotograflar)
                                    }
                                }
                                
                                // 6. Commit the batch
                                batch.commit { error in
                                    if let error = error {
                                        print("❌ Batch delete failed: \(error.localizedDescription)")
                                        completion(.failure(error))
                                        return
                                    }
                                    
                                    // 7. Delete all images
                                    self.deleteImages(imagesToDelete)
                                    
                                    print("✅ Cascade delete completed for vehicle: \(arac.plakaFormatli)")
                                    print("📊 Deleted: 1 vehicle, \(imagesToDelete.count) images")
                                    completion(.success(()))
                                }
                            }
                    }
            }
    }
    
    // MARK: - Damage Cascade Delete
    
    /// Delete damage record and its photos
    func deleteDamage(_ hasar: HasarKaydi, from arac: Arac, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting cascade delete for damage: \(hasar.resKodu)")
        
        // 1. Delete photos
        deleteImages(hasar.fotograflar)
        
        // 2. Update vehicle document (remove damage from array)
        var updatedArac = arac
        updatedArac.hasarKayitlari.removeAll { $0.id == hasar.id }
        
        do {
            try self.getCollectionReference("araclar")
                .document(arac.id.uuidString)
                .setData(from: updatedArac) { error in
                    if let error = error {
                        print("❌ Failed to update vehicle: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Damage deleted: \(hasar.resKodu)")
                        completion(.success(()))
                    }
                }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Service Record Cascade Delete
    
    /// Delete service record
    func deleteService(_ servis: ServisKaydi, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Deleting service record: \(servis.id.uuidString)")
        
        getCollectionReference("servisler")
            .document(servis.id.uuidString)
            .delete { error in
                if let error = error {
                    print("❌ Failed to delete service: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Service deleted")
                    completion(.success(()))
                }
            }
    }
    
    // MARK: - Return Operation Cascade Delete
    
    /// Delete return operation and its photos
    func deleteReturn(_ iade: IadeIslemi, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting cascade delete for return: \(iade.aracPlaka)")
        
        // 1. Delete photos
        deleteImages(iade.fotograflar)
        
        // 2. Delete return document
        getCollectionReference("iadeIslemleri")
            .document(iade.id.uuidString)
            .delete { error in
                if let error = error {
                    print("❌ Failed to delete return: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Return deleted: \(iade.aracPlaka)")
                    completion(.success(()))
                }
            }
    }
    
    // MARK: - Office Operation Cascade Delete
    
    /// Delete office operation and its photos
    func deleteOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting cascade delete for office operation: \(operation.type.rawValue)")
        
        // 1. Delete photos
        deleteImages(operation.photos)
        
        // 2. Delete operation document
        getCollectionReference("office_operations")
            .document(operation.id.uuidString)
            .delete { error in
                if let error = error {
                    print("❌ Failed to delete operation: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Office operation deleted")
                    completion(.success(()))
                }
            }
    }
    
    // MARK: - Service Company Cascade Delete
    
    /// Delete service company and update related services
    func deleteServiceCompany(_ firma: ServisFirma, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Starting cascade delete for service company: \(firma.ad)")
        
        let batch = db.batch()
        
        // 1. Delete company document
        let firmaRef = getCollectionReference("servisFirmalari").document(firma.id.uuidString)
        batch.deleteDocument(firmaRef)
        
        // 2. Query services using this company
        getCollectionReference("servisler")
            .whereField("servisTuru", isEqualTo: firma.ad)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Update or delete related services
                snapshot?.documents.forEach { doc in
                    // Option 1: Delete service records
                    // batch.deleteDocument(doc.reference)
                    
                    // Option 2: Update service records to remove company reference
                    batch.updateData(["servisTuru": "Unknown"], forDocument: doc.reference)
                }
                
                // Commit batch
                batch.commit { error in
                    if let error = error {
                        print("❌ Failed to delete company: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Service company deleted: \(firma.ad)")
                        completion(.success(()))
                    }
                }
            }
    }
    
    // MARK: - Activity Cascade Delete
    
    /// Delete activity record
    func deleteActivity(_ activity: Activity, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Deleting activity: \(activity.tip.rawValue)")
        
        getCollectionReference("activities")
            .document(activity.id.uuidString)
            .delete { error in
                if let error = error {
                    print("❌ Failed to delete activity: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Activity deleted")
                    completion(.success(()))
                }
            }
    }
    
    // MARK: - Bulk Delete Operations
    
    /// Delete multiple vehicles at once
    func bulkDeleteVehicles(_ araclar: [Arac], progress: @escaping (Int, Int) -> Void, completion: @escaping (Result<Int, Error>) -> Void) {
        print("🗑️ Starting bulk delete for \(araclar.count) vehicles")
        
        var deletedCount = 0
        var lastError: Error?
        let group = DispatchGroup()
        
        for (index, arac) in araclar.enumerated() {
            group.enter()
            
            deleteVehicle(arac) { result in
                switch result {
                case .success:
                    deletedCount += 1
                case .failure(let error):
                    lastError = error
                }
                
                DispatchQueue.main.async {
                    progress(index + 1, araclar.count)
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let error = lastError {
                completion(.failure(error))
            } else {
                print("✅ Bulk delete completed: \(deletedCount)/\(araclar.count) vehicles")
                completion(.success(deletedCount))
            }
        }
    }
    
    /// Delete old activities (older than specified days)
    func deleteOldActivities(olderThan days: Int, completion: @escaping (Result<Int, Error>) -> Void) {
        print("🗑️ Deleting activities older than \(days) days")
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        getCollectionReference("activities")
            .whereField("tarih", isLessThan: Timestamp(date: cutoffDate))
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success(0))
                    return
                }
                
                let batch = self.db.batch()
                
                documents.forEach { doc in
                    batch.deleteDocument(doc.reference)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("❌ Failed to delete old activities: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        print("✅ Deleted \(documents.count) old activities")
                        completion(.success(documents.count))
                    }
                }
            }
    }
    
    // MARK: - Private Helper Methods
    
    private func deleteImages(_ urls: [String]) {
        for url in urls {
            imageManager.deleteImage(url)
        }
        print("🗑️ Queued \(urls.count) images for deletion")
    }
}

// MARK: - Safety Checks

extension CascadeDeleteManager {
    /// Check if vehicle can be safely deleted
    func canDeleteVehicle(_ arac: Arac) -> (canDelete: Bool, reason: String?) {
        // Check if vehicle has active services
        // This would require a real-time check, but for now we allow deletion
        
        if !arac.hasarKayitlari.isEmpty {
            return (true, "Vehicle has \(arac.hasarKayitlari.count) damage records that will be deleted")
        }
        
        return (true, nil)
    }
    
    /// Check if service company can be safely deleted
    func canDeleteServiceCompany(_ firma: ServisFirma, completion: @escaping (Bool, String?) -> Void) {
        getCollectionReference("servisler")
            .whereField("servisTuru", isEqualTo: firma.ad)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(false, "Error checking: \(error.localizedDescription)")
                    return
                }
                
                let count = snapshot?.documents.count ?? 0
                if count > 0 {
                    completion(true, "Company has \(count) service records that will be updated")
                } else {
                    completion(true, nil)
                }
            }
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

struct CascadeDeleteConfirmation: View {
    let title: String
    let message: String
    let itemCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("This will delete \(itemCount) related items")
                .font(.caption)
                .foregroundColor(.red)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Delete") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
    }
}

