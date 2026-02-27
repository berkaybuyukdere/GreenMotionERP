import UIKit
import Photos
import FirebaseStorage
import FirebaseAuth

// MARK: - Compression Models

/// Image compression models for different use cases
enum CompressionModel {
    case ultraLight    // Maximum size reduction
    case balanced      // Quality and size balance (default)
    case highQuality   // Maximum quality
    case adaptive      // Smart selection based on image size
}

/// Configuration for each compression model
struct CompressionConfig {
    let maxDimension: CGFloat
    let compressionQuality: CGFloat
    let interpolationQuality: CGInterpolationQuality
    
    static let ultraLight = CompressionConfig(
        maxDimension: 1200,
        compressionQuality: 0.4,
        interpolationQuality: .low
    )
    
    static let balanced = CompressionConfig(
        maxDimension: 1600,
        compressionQuality: 0.6,
        interpolationQuality: .medium
    )
    
    static let highQuality = CompressionConfig(
        maxDimension: 2400,
        compressionQuality: 0.95,
        interpolationQuality: .high
    )
}

/// Advanced image optimization manager for Firebase Storage
/// Reduces image size by 70-90% while maintaining visual quality
class ImageOptimizationManager {
    static let shared = ImageOptimizationManager()
    
    // Legacy configuration (for backward compatibility)
    private let maxImageDimension: CGFloat = 1600
    private let compressionQuality: CGFloat = 0.6
    private let thumbnailSize: CGSize = CGSize(width: 300, height: 300)
    
    private init() {}
    
    // MARK: - Main Optimization
    
    /// Optimize image for storage - reduces size by 70-90%
    /// Uses balanced model by default for backward compatibility
    func optimizeForStorage(_ image: UIImage) -> UIImage {
        return optimizeForStorage(image, model: .balanced)
    }
    
    /// Optimize image for storage with specified compression model
    func optimizeForStorage(_ image: UIImage, model: CompressionModel) -> UIImage {
        let config = getCompressionConfig(for: model, image: image)
        
        print("🎨 Optimizing image with model: \(modelName(model))...")
        print("   Original size: \(image.size.width)x\(image.size.height)")
        
        // 1. Resize if too large
        let resized = resizeIfNeeded(image, maxDimension: config.maxDimension, interpolation: config.interpolationQuality)
        print("   Resized to: \(resized.size.width)x\(resized.size.height)")
        
        // 2. Fix orientation
        let oriented = fixOrientation(resized)
        
        // 3. Compress (this is done when converting to data)
        return oriented
    }
    
    /// Get optimized JPEG data with default balanced model
    func getOptimizedJPEGData(from image: UIImage) -> Data? {
        return getOptimizedJPEGData(from: image, model: .balanced)
    }
    
    /// Get optimized JPEG data with specified compression model
    func getOptimizedJPEGData(from image: UIImage, model: CompressionModel) -> Data? {
        let config = getCompressionConfig(for: model, image: image)
        let optimized = optimizeForStorage(image, model: model)
        
        guard let data = optimized.jpegData(compressionQuality: config.compressionQuality) else {
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
    
    // MARK: - Compression Model Helpers
    
    /// Get compression configuration for a model
    /// For adaptive model, analyzes image size and selects appropriate model
    private func getCompressionConfig(for model: CompressionModel, image: UIImage) -> CompressionConfig {
        switch model {
        case .ultraLight:
            return .ultraLight
        case .balanced:
            return .balanced
        case .highQuality:
            return .highQuality
        case .adaptive:
            let selectedModel = analyzeImageContent(image)
            return getCompressionConfig(for: selectedModel, image: image)
        }
    }
    
    /// Analyze image content and select appropriate compression model
    /// - <2MB: High Quality
    /// - 2-5MB: Balanced
    /// - >5MB: Balanced
    private func analyzeImageContent(_ image: UIImage) -> CompressionModel {
        // Get original image size in bytes
        guard let originalData = image.jpegData(compressionQuality: 1.0) else {
            return .balanced // Default fallback
        }
        
        let sizeInMB = Double(originalData.count) / (1024 * 1024)
        
        if sizeInMB < 2.0 {
            print("📊 Image size: \(String(format: "%.2f", sizeInMB)) MB → Using High Quality model")
            return .highQuality
        } else if sizeInMB <= 5.0 {
            print("📊 Image size: \(String(format: "%.2f", sizeInMB)) MB → Using Balanced model")
            return .balanced
        } else {
            print("📊 Image size: \(String(format: "%.2f", sizeInMB)) MB → Using Balanced model")
            return .balanced
        }
    }
    
    /// Get human-readable model name
    private func modelName(_ model: CompressionModel) -> String {
        switch model {
        case .ultraLight: return "Ultra Light"
        case .balanced: return "Balanced"
        case .highQuality: return "High Quality"
        case .adaptive: return "Adaptive"
        }
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
        return resizeIfNeeded(image, maxDimension: maxImageDimension, interpolation: .medium)
    }
    
    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat, interpolation: CGInterpolationQuality) -> UIImage {
        let size = image.size
        
        // Calculate new size if needed
        let needsResize = size.width > maxDimension || size.height > maxDimension
        let newSize: CGSize
        
        if needsResize {
            let ratio = min(maxDimension / size.width, maxDimension / size.height)
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
            context.cgContext.interpolationQuality = interpolation
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
    /// Uses adaptive model by default for smart optimization
    func uploadOptimizedImage(
        _ image: UIImage,
        to path: String,
        completion: @escaping (String?, Int?, Error?) -> Void
    ) {
        uploadOptimizedImage(image, to: path, model: .adaptive, completion: completion)
    }
    
    /// Upload optimized image to Firebase Storage with specified compression model
    func uploadOptimizedImage(
        _ image: UIImage,
        to path: String,
        model: CompressionModel,
        completion: @escaping (String?, Int?, Error?) -> Void
    ) {
        guard let optimizedData = getOptimizedJPEGData(from: image, model: model) else {
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
        let candidates = storageUploadPathCandidates(from: path)
        print("📤 Upload path candidates: \(candidates.joined(separator: " -> "))")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        uploadImageData(data, candidates: candidates, index: 0, metadata: metadata, completion: completion)
    }
    
    private func resolvedScopedStoragePath(from path: String) -> String {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return path }
        
        if normalized.hasPrefix("franchises/") {
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if components.count >= 3 {
                let franchiseId = String(components[1]).uppercased()
                let remainder = components.dropFirst(2).joined(separator: "/")
                return "franchises/\(franchiseId)/\(remainder)"
            }
            return normalized
        }
        
        if normalized.hasPrefix("demo_environments/") {
            return normalized
        }
        
        if let user = Auth.auth().currentUser {
            let email = (user.email ?? "").lowercased()
            let isDemoEmail = email == "demo@gmail.com" || email.contains("_demo@") || email.contains("demo_")
            if isDemoEmail {
                return "demo_environments/\(user.uid)/\(normalized)"
            }
        }
        
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        return "franchises/\(franchiseId)/\(normalized)"
    }
    
    private func storageUploadPathCandidates(from path: String) -> [String] {
        let normalized = resolvedScopedStoragePath(from: path)
        var candidates: [String] = []
        
        func appendCandidate(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }
        
        appendCandidate(normalized)
        
        // Scoped -> legacy fallback to handle mixed rulesets during migration.
        if normalized.hasPrefix("franchises/") {
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if components.count >= 3 {
                let legacy = components.dropFirst(2).joined(separator: "/")
                appendCandidate(legacy)
            }
        }
        
        if normalized.hasPrefix("demo_environments/") {
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if components.count >= 3 {
                let legacy = components.dropFirst(2).joined(separator: "/")
                appendCandidate(legacy)
            }
        }
        
        // If caller already provided a legacy path, keep it as an explicit fallback.
        appendCandidate(path)
        
        return candidates
    }
    
    private func uploadImageData(
        _ data: Data,
        candidates: [String],
        index: Int,
        metadata: StorageMetadata,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard index < candidates.count else {
            completion(nil, NSError(
                domain: "UploadError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "All upload path candidates failed."]
            ))
            return
        }
        
        let path = candidates[index]
        let storageRef = storage.reference().child(path)
        print("📤 Upload attempt path [\(index + 1)/\(candidates.count)]: \(path)")
        
        var isCompleted = false
        let timeout: TimeInterval = 30.0
        let timeoutTask = DispatchWorkItem { [weak self] in
            guard !isCompleted else { return }
            isCompleted = true
            if index + 1 < candidates.count {
                self?.uploadImageData(data, candidates: candidates, index: index + 1, metadata: metadata, completion: completion)
            } else {
                completion(nil, NSError(
                    domain: "UploadTimeout",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Photo upload timed out after \(Int(timeout)) seconds"]
                ))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
        
        _ = storageRef.putData(data, metadata: metadata) { [weak self] _, error in
            guard !isCompleted else { return }
            
            if let error {
                timeoutTask.cancel()
                isCompleted = true
                let nsError = error as NSError
                print("❌ Upload failed for path: \(path) | domain: \(nsError.domain) code: \(nsError.code) desc: \(nsError.localizedDescription)")
                if index + 1 < candidates.count {
                    self?.uploadImageData(data, candidates: candidates, index: index + 1, metadata: metadata, completion: completion)
                } else {
                    completion(nil, error)
                }
                return
            }
            
            storageRef.downloadURL { url, error in
                guard !isCompleted else { return }
                
                timeoutTask.cancel()
                isCompleted = true
                
                if let error {
                    let nsError = error as NSError
                    print("❌ DownloadURL failed for path: \(path) | domain: \(nsError.domain) code: \(nsError.code) desc: \(nsError.localizedDescription)")
                    if index + 1 < candidates.count {
                        self?.uploadImageData(data, candidates: candidates, index: index + 1, metadata: metadata, completion: completion)
                    } else {
                        completion(nil, error)
                    }
                    return
                }
                
                if let url {
                    let urlString = url.absoluteString
                    print("✅ Upload succeeded at path: \(path)")
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
        
    }
}


