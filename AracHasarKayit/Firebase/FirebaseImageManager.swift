import UIKit
import FirebaseStorage

class FirebaseImageManager {
    static let shared = FirebaseImageManager()
    private let firebaseService = FirebaseService.shared
    
    // Önbellek için
    private var imageCache: [String: UIImage] = [:]
    
    private init() {}
    
    private let maxImageSize: CGFloat = 1600
    private let compressionQuality: CGFloat = 0.75
    
    // Fotoğrafı Firebase Storage'a kaydet
    func saveImage(_ image: UIImage, withDate date: Date = Date(), isHandover: Bool = false, completion: @escaping (String?) -> Void) {
        guard let resizedImage = smartResize(image, maxSize: maxImageSize) else {
            print("Görüntü yeniden boyutlandırılamadı")
            completion(nil)
            return
        }
        
        let filename = UUID().uuidString + ".jpg"
        let path = "hasar_fotograflari/\(filename)"
        
        firebaseService.uploadImage(resizedImage, path: path) { urlString, error in
            if let error = error {
                print("❌ Fotoğraf yüklenemedi: \(error.localizedDescription)")
                completion(nil)
            } else if let urlString = urlString {
                print("✅ Fotoğraf yüklendi: \(filename)")
                completion(urlString)
            }
        }
    }
    
    // Firebase Storage'dan fotoğraf yükle
    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        // Önce cache'e bak
        if let cachedImage = imageCache[urlString] {
            completion(cachedImage)
            return
        }
        
        // Firebase'den indir
        firebaseService.downloadImage(from: urlString) { [weak self] (image: UIImage?, error: Error?) in
            if let error = error {
                print("❌ Fotoğraf indirilemedi: \(error.localizedDescription)")
                completion(nil)
            } else if let image = image {
                // Cache'e ekle
                self?.imageCache[urlString] = image
                completion(image)
            } else {
                completion(nil)
            }
        }
    }
    
    // Firebase Storage'dan fotoğraf sil
    func deleteImage(_ urlString: String) {
        if let url = URL(string: urlString), let path = url.path.components(separatedBy: "/o/").last {
            let decodedPath = path.removingPercentEncoding ?? path
            firebaseService.deleteImage(at: decodedPath) { error in
                if let error = error {
                    print("❌ Fotoğraf silinemedi: \(error.localizedDescription)")
                } else {
                    print("✅ Fotoğraf silindi")
                }
            }
        }
        
        imageCache.removeValue(forKey: urlString)
    }
    
    func deleteImages(_ urlStrings: [String]) {
        urlStrings.forEach { deleteImage($0) }
    }
    
    // MARK: - Helper Methods
    
    private func smartResize(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        let widthRatio = maxSize / size.width
        let heightRatio = maxSize / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
