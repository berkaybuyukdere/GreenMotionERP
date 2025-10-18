import Foundation
import CryptoKit

/// Encryption manager for sensitive data
class EncryptionManager {
    static let shared = EncryptionManager()
    
    private let keychain = KeychainManager()
    private var encryptionKey: SymmetricKey?
    
    private init() {
        loadOrCreateKey()
    }
    
    private func loadOrCreateKey() {
        if let keyData = keychain.load(key: "encryption_key") {
            encryptionKey = SymmetricKey(data: keyData)
        } else {
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            keychain.save(key: "encryption_key", data: keyData)
            encryptionKey = key
        }
    }
    
    func encrypt(_ string: String) -> String? {
        guard let key = encryptionKey,
              let data = string.data(using: .utf8) else { return nil }
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            print("❌ Encryption failed: \(error)")
            return nil
        }
    }
    
    func decrypt(_ encryptedString: String) -> String? {
        guard let key = encryptionKey,
              let data = Data(base64Encoded: encryptedString) else { return nil }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            print("❌ Decryption failed: \(error)")
            return nil
        }
    }
}

// Simple keychain wrapper
class KeychainManager {
    func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
}

