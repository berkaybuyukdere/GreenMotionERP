import Foundation
import FirebaseFirestore

/// Firestore settings must be applied before the first `Firestore.firestore()` call
/// (e.g. before `AuthenticationManager` / `FirebaseService` init).
enum FirestorePersistenceConfigurator {
    private static let lock = NSLock()
    private static var didConfigure = false

    static func configure() {
        lock.lock()
        defer { lock.unlock() }
        guard !didConfigure else { return }
        didConfigure = true
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
        LogManager.shared.info("Firestore offline persistence enabled (100MB cache)")
    }
}
