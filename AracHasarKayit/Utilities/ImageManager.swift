import Foundation
import UIKit

/// Manages image compression, resizing, and optimization
class ImageManager {
    static let shared = ImageManager()
    
    private init() {}
    
    // MARK: - Image Compression
    
    /// Compresses an image to reduce file size
    /// - Parameters:
    ///   - image: The image to compress
    ///   - maxSizeInMB: Maximum file size in MB (default: 2MB)
    ///   - maxDimension: Maximum dimension for resizing (default: 1024)
    /// - Returns: Compressed image
    func compressImage(_ image: UIImage, maxSizeInMB: Double = 2.0, maxDimension: CGFloat = 1024) -> UIImage? {
        // First, resize if needed
        var resizedImage = image
        let maxSize = maxDimension
        
        // Check if resizing is needed
        if image.size.width > maxSize || image.size.height > maxSize {
            if let resized = resizeImage(image, maxDimension: maxSize) {
                resizedImage = resized
            }
        }
        
        // Then compress
        let maxSizeInBytes = Int(maxSizeInMB * 1024 * 1024) // Convert to bytes
        var compression: CGFloat = 0.8
        var finalData: Data?
        
        repeat {
            if let data = resizedImage.jpegData(compressionQuality: compression) {
                if data.count <= maxSizeInBytes || compression <= 0.1 {
                    finalData = data
                    break
                }
            }
            compression -= 0.1
        } while compression >= 0.1
        
        guard let data = finalData else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Image Resizing
    
    /// Resizes an image to specified maximum dimension while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The image to resize
    ///   - maxDimension: Maximum dimension (width or height)
    /// - Returns: Resized image or original if resizing fails
    func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        
        if size.width > size.height {
            // Landscape
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait or square
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Only resize if new size is smaller
        if newSize.width < size.width || newSize.height < size.height {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resizedImage
        }
        
        return image
    }
    
    /// Creates a thumbnail from an image
    /// - Parameters:
    ///   - image: The image to create thumbnail from
    ///   - size: Thumbnail size (default: 200x200)
    /// - Returns: Thumbnail image
    func createThumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumbnail
    }
    
    // MARK: - Image Validation
    
    /// Validates if an image is acceptable for upload
    /// - Parameter image: The image to validate
    /// - Returns: True if valid, false otherwise
    func validateImage(_ image: UIImage) -> Bool {
        // Check if image has valid size
        guard image.size.width > 0 && image.size.height > 0 else {
            return false
        }
        
        // Check if image has valid data
        guard let _ = ImageOptimizationManager.shared.getOptimizedJPEGData(from: image) else {
            return false
        }
        
        return true
    }
    
    /// Gets the file size of an image in MB
    /// - Parameter image: The image
    /// - Returns: File size in MB
    func getImageSizeInMB(_ image: UIImage) -> Double {
        guard let data = image.jpegData(compressionQuality: 1.0) else {
            return 0.0
        }
        return Double(data.count) / (1024 * 1024)
    }
    
    /// Gets the dimensions of an image as string
    /// - Parameter image: The image
    /// - Returns: Dimensions string (e.g., "1920x1080")
    func getImageDimensions(_ image: UIImage) -> String {
        return "\(Int(image.size.width))x\(Int(image.size.height))"
    }
}

// MARK: - Batch Image Processing

extension ImageManager {
    /// Processes multiple images in batch
    /// - Parameters:
    ///   - images: Array of images to process
    ///   - progressCallback: Callback for progress updates (0.0 to 1.0)
    /// - Returns: Array of compressed images
    func processImagesBatch(_ images: [UIImage], progressCallback: @escaping (Double) -> Void) -> [UIImage] {
        var processedImages: [UIImage] = []
        
        for (index, image) in images.enumerated() {
            if let compressed = compressImage(image) {
                processedImages.append(compressed)
            } else {
                // Fallback to original if compression fails
                processedImages.append(image)
            }
            
            // Report progress
            let progress = Double(index + 1) / Double(images.count)
            progressCallback(progress)
        }
        
        return processedImages
    }
}

