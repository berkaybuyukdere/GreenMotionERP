import UIKit

/// Shared checkout/return photo helpers (sync mutations only).
@MainActor
enum CheckoutReturnPhotoCapture {
    /// Fingerprint off the main thread; returns nil when duplicate.
    static func fingerprintForNewPhoto(
        _ image: UIImage,
        existingKeys: [String],
        additionalKnownKeys: [String] = []
    ) async -> String? {
        let key = await PendingPhotoFingerprint.keyAsync(for: image)
        guard !existingKeys.contains(key), !additionalKnownKeys.contains(key) else { return nil }
        return key
    }

    static func removeCameraPhoto(
        at index: Int,
        cameraPhotos: inout [UIImage],
        fingerprintKeys: inout [String],
        pendingUploadTracker: PendingPhotoUploadTracker
    ) {
        guard cameraPhotos.indices.contains(index), fingerprintKeys.indices.contains(index) else { return }
        let key = fingerprintKeys[index]
        pendingUploadTracker.markRemoved(key: key)
        cameraPhotos.remove(at: index)
        fingerprintKeys.remove(at: index)
    }

    static func removeGalleryPhoto(
        at index: Int,
        fotograflar: inout [UIImage],
        fingerprintKeys: inout [String],
        pendingUploadTracker: PendingPhotoUploadTracker
    ) {
        guard fotograflar.indices.contains(index), fingerprintKeys.indices.contains(index) else { return }
        let key = fingerprintKeys[index]
        pendingUploadTracker.markRemoved(key: key)
        fotograflar.remove(at: index)
        fingerprintKeys.remove(at: index)
    }

    static func revertSerialSession(
        from baseline: Int,
        cameraPhotos: inout [UIImage],
        fingerprintKeys: inout [String],
        pendingUploadTracker: PendingPhotoUploadTracker
    ) {
        guard cameraPhotos.count > baseline else { return }
        for index in baseline..<cameraPhotos.count {
            if fingerprintKeys.indices.contains(index) {
                pendingUploadTracker.markRemoved(key: fingerprintKeys[index])
            }
        }
        cameraPhotos.removeSubrange(baseline..<cameraPhotos.count)
        if fingerprintKeys.count > baseline {
            fingerprintKeys.removeSubrange(baseline..<fingerprintKeys.count)
        }
    }
}
