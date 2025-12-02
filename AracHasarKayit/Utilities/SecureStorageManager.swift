import Foundation
import KeychainSwift

/// Secure storage manager using KeychainSwift for sensitive data
class SecureStorageManager {
    static let shared = SecureStorageManager()
    
    private let keychain = KeychainSwift()
    
    private init() {
        // Configure keychain settings
        keychain.synchronizable = false // Don't sync to iCloud by default
    }
    
    // MARK: - Token Storage
    
    /// Store Firebase auth token securely
    func storeAuthToken(_ token: String) -> Bool {
        return keychain.set(token, forKey: "firebase_auth_token")
    }
    
    /// Alias for storeAuthToken (for compatibility)
    func saveAuthToken(_ token: String) -> Bool {
        return storeAuthToken(token)
    }
    
    /// Retrieve Firebase auth token
    func getAuthToken() -> String? {
        return keychain.get("firebase_auth_token")
    }
    
    /// Delete Firebase auth token
    func deleteAuthToken() -> Bool {
        return keychain.delete("firebase_auth_token")
    }
    
    // MARK: - User ID Storage
    
    /// Store user ID securely
    func saveUserId(_ userId: String) -> Bool {
        return keychain.set(userId, forKey: "user_id")
    }
    
    /// Retrieve stored user ID
    func getUserId() -> String? {
        return keychain.get("user_id")
    }
    
    /// Delete stored user ID
    func deleteUserId() -> Bool {
        return keychain.delete("user_id")
    }
    
    // MARK: - User Credentials (Remember Me)
    
    /// Store user email for "Remember Me" feature
    func storeUserEmail(_ email: String) -> Bool {
        return keychain.set(email, forKey: "user_email")
    }
    
    /// Retrieve stored user email
    func getUserEmail() -> String? {
        return keychain.get("user_email")
    }
    
    /// Delete stored user email
    func deleteUserEmail() -> Bool {
        return keychain.delete("user_email")
    }
    
    // MARK: - Generic Storage
    
    /// Store any string value securely
    func store(_ value: String, forKey key: String) -> Bool {
        return keychain.set(value, forKey: key)
    }
    
    /// Retrieve stored string value
    func get(forKey key: String) -> String? {
        return keychain.get(key)
    }
    
    /// Delete stored value
    func delete(forKey key: String) -> Bool {
        return keychain.delete(key)
    }
    
    /// Check if a key exists
    func hasValue(forKey key: String) -> Bool {
        return keychain.get(key) != nil
    }
    
    // MARK: - Clear All
    
    /// Clear all stored values (use with caution)
    func clearAll() -> Bool {
        return keychain.clear()
    }
}
