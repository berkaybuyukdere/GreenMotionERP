import Foundation
import FirebaseFirestore
import FirebaseStorage
import UIKit

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Araç İşlemleri

    func loadAraclar(completion: @escaping ([Arac]?, Error?) -> Void) {
        db.collection("araclar").getDocuments { querySnapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                completion([], nil)
                return
            }
            
            let araclar = documents.compactMap { document -> Arac? in
                try? document.data(as: Arac.self)
            }
            
            completion(araclar, nil)
        }
    }

    func saveArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("araclar").document(arac.id.uuidString).setData(from: arac) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func updateArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("araclar").document(arac.id.uuidString).setData(from: arac) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteArac(id: UUID, completion: @escaping (Error?) -> Void) {
        db.collection("araclar").document(id.uuidString).delete { error in
            completion(error)
        }
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
            try db.collection("iadeIslemleri").document(iade.id.uuidString).setData(from: iade) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func deleteIadeIslemi(_ iade: IadeIslemi, completion: @escaping (Error?) -> Void) {
        db.collection("iadeIslemleri").document(iade.id.uuidString).delete { error in
            completion(error)
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
        guard let imageData = image.jpegData(compressionQuality: 0.75) else {
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
}
