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
    private let uploadQueue = DispatchQueue(label: "com.greenmotion.imagecache.upload", qos: .utility, attributes: .concurrent)
    private let uploadSemaphore = DispatchSemaphore(value: 3)
    
    // Track ongoing downloads to prevent duplicates
    private var activeDownloads: [String: [(UIImage?) -> Void]] = [:]
    private let downloadLock = NSLock()
    
    private var diskCacheURL: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ImageCache")
    }
    
    // MARK: - Initialization
    
    // Cache configuration
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB
    
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
        
        // Perform initial cache cleanup
        performCacheCleanup()
        
        // Schedule periodic cleanup (every 24 hours)
        schedulePeriodicCleanup()
        
        print("✅ CachedImageManager initialized")
        print("📁 Disk cache: \(diskCacheURL.path)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Load image with 3-tier caching and progressive loading
    /// ⚠️ DEPRECATED: Use Kingfisher's KFImage instead for better performance and caching
    @available(*, deprecated, message: "Use Kingfisher's KFImage instead. This method will be removed in a future version.")
    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        loadImageProgressive(urlString, completion: completion)
    }
    
    /// Load image with progressive loading (thumbnail first, then full image)
    /// ⚠️ DEPRECATED: Use Kingfisher's KFImage instead
    @available(*, deprecated, message: "Use Kingfisher's KFImage instead. This method will be removed in a future version.")
    private func loadImageProgressive(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
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
            
            // 3. Progressive download: Try thumbnail first, then full image
            self.downloadImageProgressive(urlString, cacheKey: cacheKey, completion: completion)
        }
    }
    
    /// Upload image and return URL (with automatic optimization, timeout, and retry)
    func uploadImage(_ image: UIImage, path: String, completion: @escaping (String?, Error?) -> Void) {
        uploadQueue.async {
            self.uploadSemaphore.wait()
            self.uploadImageWithRetry(image, path: path, retryCount: 0, maxRetries: 3) { url, error in
                self.uploadSemaphore.signal()
                completion(url, error)
            }
        }
    }
    
    /// Upload image with retry mechanism and timeout
    private func uploadImageWithRetry(
        _ image: UIImage,
        path: String,
        retryCount: Int,
        maxRetries: Int,
        completion: @escaping (String?, Error?) -> Void
    ) {
        // Use ImageOptimizationManager with high quality for check out, damage, and return photos
        ImageOptimizationManager.shared.uploadOptimizedImage(image, to: path, model: .highQuality) { url, size, error in
            if let url = url {
                print("✅ Image uploaded successfully: \(url)")
                if let size = size {
                    print("   Final size: \(size) bytes")
                }
                completion(url, nil)
            } else if let error = error, retryCount < maxRetries {
                // Retry with exponential backoff
                let delay = Double(retryCount + 1) * 1.0 // 1s, 2s, 3s
                print("⚠️ Upload failed: \(error.localizedDescription), retrying in \(delay)s (attempt \(retryCount + 1)/\(maxRetries))...")
                
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
    /// ⚠️ DEPRECATED: Use Kingfisher's prefetching instead
    @available(*, deprecated, message: "Use Kingfisher's ImagePrefetcher instead. This method will be removed in a future version.")
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
    
    /// Perform automatic cache cleanup (old files and size limit)
    func performCacheCleanup() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let files = try? self.fileManager.contentsOfDirectory(
                at: self.diskCacheURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            ) else {
                return
            }
            
            let now = Date()
            var totalSize: Int64 = 0
            var filesToDelete: [URL] = []
            
            // Check each file
            for fileURL in files {
                // Check modification date
                if let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    let age = now.timeIntervalSince(modificationDate)
                    if age > self.maxCacheAge {
                        filesToDelete.append(fileURL)
                        continue
                    }
                }
                
                // Calculate total size
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
            
            // Delete old files
            for fileURL in filesToDelete {
                try? self.fileManager.removeItem(at: fileURL)
            }
            
            // If cache size exceeds limit, delete oldest files
            if totalSize > self.maxCacheSize {
                let filesWithDates = files.compactMap { url -> (URL, Date)? in
                    guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                        return nil
                    }
                    return (url, date)
                }.sorted { $0.1 < $1.1 } // Sort by date (oldest first)
                
                var remainingSize = totalSize
                for (fileURL, _) in filesWithDates {
                    if remainingSize <= self.maxCacheSize {
                        break
                    }
                    
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        try? self.fileManager.removeItem(at: fileURL)
                        remainingSize -= Int64(size)
                    }
                }
            }
            
            if !filesToDelete.isEmpty {
                print("🧹 Cleaned \(filesToDelete.count) old cache files")
            }
        }
    }
    
    /// Schedule periodic cache cleanup
    private func schedulePeriodicCleanup() {
        // Cleanup every 24 hours
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.performCacheCleanup()
        }
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
    
    /// Progressive download: Load optimized version first, then full image
    private func downloadImageProgressive(_ urlString: String, cacheKey: NSString, completion: @escaping (UIImage?) -> Void) {
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
        
        print("⬇️ Progressive download from network: \(urlString.suffix(30))")
        
        guard let url = URL(string: urlString) else {
            notifyDownloadCallbacks(for: urlString, with: nil)
            return
        }
        
        // Download with adaptive quality based on network
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15.0
        sessionConfig.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: sessionConfig)
        
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                self?.notifyDownloadCallbacks(for: urlString, with: nil)
                return
            }
            
            // For progressive loading, create optimized version first
            let optimizedImage = ImageOptimizationManager.shared.optimizeForStorage(image)
            
            // Cache the optimized image
            self.cacheImage(optimizedImage, for: urlString)
            
            print("✅ Image downloaded and cached (optimized): \(urlString.suffix(30))")
            
            // Notify all waiting callbacks with optimized image
            self.notifyDownloadCallbacks(for: urlString, with: optimizedImage)
        }.resume()
    }
    
    internal func cacheImage(_ image: UIImage, for urlString: String) {  // internal for ImageOptimizationManager
        let cacheKey = NSString(string: urlString)
        
        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey)
        
        // Store in disk cache (async)
        ioQueue.async { [weak self] in
            guard let self = self,
                  let data = ImageOptimizationManager.shared.getOptimizedJPEGData(from: image) else { return }
            
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
// ⚠️ REMOVED: CachedAsyncImage has been removed. Use Kingfisher's KFImage instead.
// Example: KFImage(URL(string: urlString))

