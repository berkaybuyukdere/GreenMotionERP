import UIKit
import FirebaseStorage

class FirebaseImageManager {
    static let shared = FirebaseImageManager()
    private let storage = Storage.storage()
    
    private init() {}
    
    func uploadImage(_ image: UIImage, path: String, completion: @escaping (String?, Error?) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(nil, NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert image to data"]))
            return
        }
        
        let storageRef = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        storageRef.putData(imageData, metadata: metadata) { metadata, error in
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
    
    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let image = UIImage(data: data) {
                completion(image)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    func deleteImage(_ urlString: String) {
        let storageRef = storage.reference(forURL: urlString)
        storageRef.delete { error in
            if let error = error {
                print("❌ Image deletion failed: \(error.localizedDescription)")
            } else {
                print("✅ Image deleted successfully")
            }
        }
    }
}
