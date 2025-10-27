import Foundation

/// Manages retry logic for failed operations
class RetryManager {
    static let shared = RetryManager()
    
    private init() {}
    
    /// Retries an operation with exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 3)
    ///   - initialDelay: Initial delay in seconds (default: 1.0)
    ///   - operation: The operation to retry
    ///   - completion: Completion handler with result or error
    func retryOperation<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        Task {
            var attempt = 1
            let delay = initialDelay
            
            while attempt <= maxAttempts {
                do {
                    let result = try await operation()
                    await MainActor.run {
                        completion(.success(result))
                    }
                    return
                } catch {
                    print("⚠️ Attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                    
                    if attempt >= maxAttempts {
                        await MainActor.run {
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    // Exponential backoff
                    let backoffDelay = delay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                    
                    attempt += 1
                }
            }
        }
    }
    
    /// Retries an operation with exponential backoff (async version)
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 3)
    ///   - initialDelay: Initial delay in seconds (default: 1.0)
    ///   - operation: The operation to retry
    /// - Returns: Result of the operation
    func retryOperationAsync<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 1
        let delay = initialDelay
        
        while attempt <= maxAttempts {
            do {
                return try await operation()
            } catch {
                print("⚠️ Attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                
                if attempt >= maxAttempts {
                    throw error
                }
                
                // Exponential backoff
                let backoffDelay = delay * pow(2.0, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                
                attempt += 1
            }
        }
        
        throw NSError(domain: "RetryManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max attempts reached"])
    }
}

// MARK: - Retry Policies

enum RetryPolicy {
    case none
    case standard(maxAttempts: Int = 3)
    case aggressive(maxAttempts: Int = 5)
    case critical(maxAttempts: Int = 7)
    
    var maxAttempts: Int {
        switch self {
        case .none: return 1
        case .standard(let attempts): return attempts
        case .aggressive(let attempts): return attempts
        case .critical(let attempts): return attempts
        }
    }
}

