import Foundation
import Combine
import UIKit

/// Performance optimization utilities for the application
class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()
    
    private let backgroundQueue = DispatchQueue(label: "com.greenmotion.performance", qos: .utility)
    private let serialQueue = DispatchQueue(label: "com.greenmotion.serial", qos: .userInitiated)
    private var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3 // Limit concurrent operations
        queue.qualityOfService = .utility
        return queue
    }()
    
    private var imageCache = NSCache<NSString, UIImage>()
    private var dataCache = NSCache<NSString, AnyObject>()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Configure image cache
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        // Configure data cache
        dataCache.countLimit = 50
        dataCache.totalCostLimit = 10 * 1024 * 1024 // 10 MB
        
        // Listen to memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.clearCaches()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Background Operations
    
    /// Execute on background queue with priority
    func performInBackground(_ work: @escaping () -> Void) {
        backgroundQueue.async {
            work()
        }
    }
    
    /// Execute on background queue with result callback on main
    func performInBackground<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        backgroundQueue.async {
            do {
                let result = try work()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Batch operations with concurrency limit
    func performBatch<T>(items: [T], maxConcurrent: Int = 3, operation: @escaping (T) -> Void, completion: @escaping () -> Void) {
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        
        for item in items {
            semaphore.wait()
            group.enter()
            
            backgroundQueue.async {
                operation(item)
                semaphore.signal()
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion()
        }
    }
    
    // MARK: - Caching
    
    func cacheImage(_ image: UIImage, forKey key: String) {
        imageCache.setObject(image, forKey: key as NSString)
    }
    
    func cachedImage(forKey key: String) -> UIImage? {
        return imageCache.object(forKey: key as NSString)
    }
    
    func cacheData(_ data: AnyObject, forKey key: String) {
        dataCache.setObject(data, forKey: key as NSString)
    }
    
    func cachedData(forKey key: String) -> AnyObject? {
        return dataCache.object(forKey: key as NSString)
    }
    
    func clearCaches() {
        imageCache.removeAllObjects()
        dataCache.removeAllObjects()
        print("🧹 Performance caches cleared")
    }
    
    // MARK: - Debouncing
    
    private var debounceTimers: [String: Timer] = [:]
    
    func debounce(identifier: String, delay: TimeInterval = 0.3, work: @escaping () -> Void) {
        debounceTimers[identifier]?.invalidate()
        debounceTimers[identifier] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            work()
            self?.debounceTimers.removeValue(forKey: identifier)
        }
    }
    
    // MARK: - Throttling
    
    private var throttleTimers: [String: Date] = [:]
    
    func throttle(identifier: String, interval: TimeInterval = 1.0, work: @escaping () -> Void) {
        let now = Date()
        if let lastExecution = throttleTimers[identifier] {
            let timeSinceLastExecution = now.timeIntervalSince(lastExecution)
            if timeSinceLastExecution < interval {
                return
            }
        }
        
        throttleTimers[identifier] = now
        work()
    }
    
    // MARK: - Lazy Loading Helper
    
    func loadLazyData<T>(key: String, loader: @escaping () -> T, completion: @escaping (T) -> Void) {
        // Check cache first
        if let cached = cachedData(forKey: key) as? T {
            completion(cached)
            return
        }
        
        // Load in background
        performInBackground {
            loader()
        } completion: { result in
            switch result {
            case .success(let data):
                self.cacheData(data as AnyObject, forKey: key)
                completion(data)
            case .failure(let error):
                print("❌ Lazy load error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Memory Management
    
    func optimizeMemoryUsage() {
        // Clear caches
        clearCaches()
        
        // Force garbage collection hint
        autoreleasepool {
            // Any temporary objects will be released
        }
    }
    
    // MARK: - Performance Monitoring
    
    func measureExecution<T>(_ operation: String, work: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            if timeElapsed > 0.1 { // Log if > 100ms
                print("⏱️ \(operation) took \(String(format: "%.3f", timeElapsed))s")
            }
        }
        return try work()
    }
}

