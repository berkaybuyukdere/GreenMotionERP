import UIKit
import Photos
import FirebaseStorage

/// Advanced image optimization manager for Firebase Storage
/// Reduces image size by 70-90% while maintaining visual quality
class ImageOptimizationManager {
    static let shared = ImageOptimizationManager()
    
    // Configuration
    private let maxImageDimension: CGFloat = 1600  // Max width or height (daha küçük)
    private let compressionQuality: CGFloat = 0.6  // 60% quality (daha agresif)
    private let thumbnailSize: CGSize = CGSize(width: 300, height: 300)
    
    private init() {}
    
    // MARK: - Main Optimization
    
    /// Optimize image for storage - reduces size by 70-90%
    func optimizeForStorage(_ image: UIImage) -> UIImage {
        print("🎨 Optimizing image...")
        print("   Original size: \(image.size.width)x\(image.size.height)")
        
        // 1. Resize if too large
        let resized = resizeIfNeeded(image)
        print("   Resized to: \(resized.size.width)x\(resized.size.height)")
        
        // 2. Fix orientation
        let oriented = fixOrientation(resized)
        
        // 3. Compress (this is done when converting to data)
        return oriented
    }
    
    /// Get optimized JPEG data
    func getOptimizedJPEGData(from image: UIImage) -> Data? {
        let optimized = optimizeForStorage(image)
        
        guard let data = optimized.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        
        let originalSize = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        let optimizedSize = data.count
        let reduction = originalSize > 0 ? ((Double(originalSize - optimizedSize) / Double(originalSize)) * 100) : 0
        
        print("   Original data: \(formatBytes(originalSize))")
        print("   Optimized data: \(formatBytes(optimizedSize))")
        print("   ✅ Reduced by: \(String(format: "%.1f", reduction))%")
        
        return data
    }
    
    /// Create thumbnail for preview
    func createThumbnail(from image: UIImage) -> UIImage? {
        let size = calculateThumbnailSize(for: image.size)
        
        // Scale = 1.0 ve opaque = true
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail
    }
    
    // MARK: - Private Helpers
    
    private func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        
        // Calculate new size if needed
        let needsResize = size.width > maxImageDimension || size.height > maxImageDimension
        let newSize: CGSize
        
        if needsResize {
            let ratio = min(maxImageDimension / size.width, maxImageDimension / size.height)
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        } else {
            newSize = size
        }
        
        // HER ZAMAN scale = 1.0 kullan (ÇOK ÖNEMLİ!)
        // Image'in kendi scale'i 2x veya 3x olabilir, bunu normalize et
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1x scale kullan (2x veya 3x değil!)
        format.opaque = true  // Transparanlık yok, daha küçük
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .medium  // High yerine medium
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func fixOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        
        // Scale = 1.0 kullan!
        UIGraphicsBeginImageContextWithOptions(image.size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalized ?? image
    }
    
    private func calculateThumbnailSize(for originalSize: CGSize) -> CGSize {
        let ratio = min(
            thumbnailSize.width / originalSize.width,
            thumbnailSize.height / originalSize.height
        )
        
        return CGSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        
        if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else {
            return String(format: "%.2f KB", kb)
        }
    }
}

// MARK: - Firebase Storage Integration

extension ImageOptimizationManager {
    /// Upload optimized image to Firebase Storage
    func uploadOptimizedImage(
        _ image: UIImage,
        to path: String,
        completion: @escaping (String?, Int?, Error?) -> Void
    ) {
        guard let optimizedData = getOptimizedJPEGData(from: image) else {
            completion(nil, nil, NSError(
                domain: "ImageOptimization",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to optimize image"]
            ))
            return
        }
        
        let size = optimizedData.count
        
        // Use CachedImageManager for upload
        CachedImageManager.shared.uploadImageData(
            optimizedData,
            path: path
        ) { url, error in
            if let url = url {
                print("✅ Uploaded optimized image: \(self.formatBytes(size))")
                completion(url, size, nil)
            } else {
                completion(nil, nil, error)
            }
        }
    }
}

// MARK: - CachedImageManager Extension

extension CachedImageManager {
    /// Upload raw image data (used by ImageOptimizationManager) with timeout
    func uploadImageData(_ data: Data, path: String, completion: @escaping (String?, Error?) -> Void) {
        let storageRef = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // Create timeout task
        var isCompleted = false
        let timeout: TimeInterval = 30.0 // 30 seconds timeout
        
        let timeoutTask = DispatchWorkItem {
            if !isCompleted {
                isCompleted = true
                let timeoutError = NSError(
                    domain: "UploadTimeout",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Photo upload timed out after \(Int(timeout)) seconds"]
                )
                completion(nil, timeoutError)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        
        // Upload task
        let uploadTask = storageRef.putData(data, metadata: metadata) { [weak self] metadata, error in
            guard !isCompleted else { return }
            
            if let error = error {
                timeoutTask.cancel()
                isCompleted = true
                completion(nil, error)
                return
            }
            
            storageRef.downloadURL { url, error in
                guard !isCompleted else { return }
                
                timeoutTask.cancel()
                isCompleted = true
                
                if let error = error {
                    completion(nil, error)
                } else if let url = url {
                    let urlString = url.absoluteString
                    
                    // Cache the uploaded image
                    if let image = UIImage(data: data) {
                        self?.cacheImage(image, for: urlString)
                    }
                    
                    completion(urlString, nil)
                } else {
                    completion(nil, NSError(
                        domain: "UploadError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]
                    ))
                }
            }
        }
        
        // Resume upload task
        uploadTask.resume()
    }
}

