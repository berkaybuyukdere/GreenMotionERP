import UIKit
import FirebaseStorage

/// Advanced image caching manager with memory and disk cache
/// Provides 3-tier caching: Memory → Disk → Network
class CachedImageManager {
    static let shared = CachedImageManager()
    
    // MARK: - Properties
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    internal let storage = Storage.storage()  // internal for ImageOptimizationManager
    private let ioQueue = DispatchQueue(label: "com.greenmotion.imagecache", qos: .utility)
    
    // Track ongoing downloads to prevent duplicates
    private var activeDownloads: [String: [(UIImage?) -> Void]] = [:]
    private let downloadLock = NSLock()
    
    private var diskCacheURL: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ImageCache")
    }
    
    // MARK: - Initialization
    
    private init() {
        // Create disk cache directory
        try? fileManager.createDirectory(
            at: diskCacheURL,
            withIntermediateDirectories: true
        )
        
        // Configure memory cache (50MB limit, 100 images max)
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024
        
        // Setup cache cleanup on memory warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        print("✅ CachedImageManager initialized")
        print("📁 Disk cache: \(diskCacheURL.path)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Load image with 3-tier caching
    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = NSString(string: urlString)
        
        // 1. Check memory cache
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            print("✅ Image from MEMORY cache: \(urlString.suffix(30))")
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // 2. Check disk cache (async)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            let filename = self.cacheFilename(for: urlString)
            let fileURL = self.diskCacheURL.appendingPathComponent(filename)
            
            if let diskImage = UIImage(contentsOfFile: fileURL.path) {
                print("✅ Image from DISK cache: \(urlString.suffix(30))")
                
                // Store in memory cache for faster access next time
                self.memoryCache.setObject(diskImage, forKey: cacheKey)
                
                DispatchQueue.main.async {
                    completion(diskImage)
                }
                return
            }
            
            // 3. Download from network
            self.downloadImage(urlString, cacheKey: cacheKey, completion: completion)
        }
    }
    
    /// Upload image and return URL (with automatic optimization, timeout, and retry)
    func uploadImage(_ image: UIImage, path: String, completion: @escaping (String?, Error?) -> Void) {
        uploadImageWithRetry(image, path: path, retryCount: 0, maxRetries: 3, completion: completion)
    }
    
    /// Upload image with retry mechanism and timeout
    private func uploadImageWithRetry(
        _ image: UIImage,
        path: String,
        retryCount: Int,
        maxRetries: Int,
        completion: @escaping (String?, Error?) -> Void
    ) {
        // Use ImageOptimizationManager for automatic optimization
        ImageOptimizationManager.shared.uploadOptimizedImage(image, to: path) { url, size, error in
            if let url = url {
                print("✅ Image uploaded successfully: \(url)")
                if let size = size {
                    print("   Final size: \(size) bytes")
                }
                completion(url, nil)
            } else if let error = error, retryCount < maxRetries {
                // Retry with exponential backoff
                let delay = Double(retryCount + 1) * 1.0 // 1s, 2s, 3s
                print("⚠️ Upload failed, retrying in \(delay)s (attempt \(retryCount + 1)/\(maxRetries))...")
                
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.uploadImageWithRetry(image, path: path, retryCount: retryCount + 1, maxRetries: maxRetries, completion: completion)
                }
            } else {
                print("❌ Image upload failed after \(retryCount) retries: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil, error)
            }
        }
    }
    
    /// Delete image from cache and Firebase Storage
    func deleteImage(_ urlString: String) {
        // Remove from memory cache
        let cacheKey = NSString(string: urlString)
        memoryCache.removeObject(forKey: cacheKey)
        
        // Remove from disk cache
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let filename = self.cacheFilename(for: urlString)
            let fileURL = self.diskCacheURL.appendingPathComponent(filename)
            try? self.fileManager.removeItem(at: fileURL)
        }
        
        // Remove from Firebase Storage
        let storageRef = storage.reference(forURL: urlString)
        storageRef.delete { error in
            if let error = error {
                print("❌ Firebase image deletion failed: \(error.localizedDescription)")
            } else {
                print("✅ Image deleted from Firebase Storage")
            }
        }
    }
    
    /// Preload images in background
    func preloadImages(_ urlStrings: [String]) {
        for urlString in urlStrings {
            loadImage(urlString) { _ in
                // Images are now cached
            }
        }
    }
    
    /// Clear all caches
    func clearCache() {
        clearMemoryCache()
        clearDiskCache()
    }
    
    /// Get cache statistics
    func getCacheInfo() -> CacheInfo {
        var diskSize: Int64 = 0
        var fileCount = 0
        
        if let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) {
            fileCount = files.count
            diskSize = files.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + Int64(size)
            }
        }
        
        return CacheInfo(
            memoryCacheCount: memoryCache.countLimit,
            diskCacheSize: diskSize,
            diskFileCount: fileCount,
            diskCachePath: diskCacheURL.path
        )
    }
    
    // MARK: - Private Methods
    
    private func downloadImage(_ urlString: String, cacheKey: NSString, completion: @escaping (UIImage?) -> Void) {
        // Check if already downloading
        downloadLock.lock()
        if var callbacks = activeDownloads[urlString] {
            callbacks.append(completion)
            activeDownloads[urlString] = callbacks
            downloadLock.unlock()
            print("⏳ Already downloading, adding callback: \(urlString.suffix(30))")
            return
        } else {
            activeDownloads[urlString] = [completion]
            downloadLock.unlock()
        }
        
        print("⬇️ Downloading from network: \(urlString.suffix(30))")
        
        guard let url = URL(string: urlString) else {
            notifyDownloadCallbacks(for: urlString, with: nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                self?.notifyDownloadCallbacks(for: urlString, with: nil)
                return
            }
            
            // Cache the image
            self.cacheImage(image, for: urlString)
            
            print("✅ Image downloaded and cached: \(urlString.suffix(30))")
            
            // Notify all waiting callbacks
            self.notifyDownloadCallbacks(for: urlString, with: image)
        }.resume()
    }
    
    internal func cacheImage(_ image: UIImage, for urlString: String) {  // internal for ImageOptimizationManager
        let cacheKey = NSString(string: urlString)
        
        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey)
        
        // Store in disk cache (async)
        ioQueue.async { [weak self] in
            guard let self = self,
                  let data = image.jpegData(compressionQuality: 0.8) else { return }
            
            let filename = self.cacheFilename(for: urlString)
            let fileURL = self.diskCacheURL.appendingPathComponent(filename)
            
            try? data.write(to: fileURL)
        }
    }
    
    private func notifyDownloadCallbacks(for urlString: String, with image: UIImage?) {
        downloadLock.lock()
        let callbacks = activeDownloads[urlString] ?? []
        activeDownloads.removeValue(forKey: urlString)
        downloadLock.unlock()
        
        DispatchQueue.main.async {
            callbacks.forEach { $0(image) }
        }
    }
    
    private func cacheFilename(for urlString: String) -> String {
        // Use MD5-like hash for filename
        let hash = urlString.hash
        return "\(abs(hash)).jpg"
    }
    
    @objc private func clearMemoryCache() {
        memoryCache.removeAllObjects()
        print("🗑️ Memory cache cleared")
    }
    
    private func clearDiskCache() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            try? self.fileManager.removeItem(at: self.diskCacheURL)
            try? self.fileManager.createDirectory(
                at: self.diskCacheURL,
                withIntermediateDirectories: true
            )
            
            print("🗑️ Disk cache cleared")
        }
    }
}

// MARK: - Cache Info Model

struct CacheInfo {
    let memoryCacheCount: Int
    let diskCacheSize: Int64
    let diskFileCount: Int
    let diskCachePath: String
    
    var diskCacheSizeFormatted: String {
        let mb = Double(diskCacheSize) / 1024 / 1024
        return String(format: "%.2f MB", mb)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

struct CachedAsyncImage: View {
    let url: String
    let placeholder: Image
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    init(url: String, placeholder: Image = Image(systemName: "photo")) {
        self.url = url
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else if isLoading {
                placeholder
                    .resizable()
                    .foregroundColor(.gray)
                    .opacity(0.3)
            } else {
                placeholder
                    .resizable()
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        CachedImageManager.shared.loadImage(url) { loadedImage in
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

