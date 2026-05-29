import Foundation
import UIKit

@MainActor
final class PendingPhotoUploadTracker: ObservableObject {
    enum State {
        case uploading
        case uploaded(String)
        case cancelled
        case failed
    }

    private var states: [String: State] = [:]
    private var imageKeyCache: [ObjectIdentifier: String] = [:]

    private var cancelRequested: Set<String> = []
    /// Photo keys uploaded during the current operation form session; deleted on discard unless committed.
    private var sessionDiscardableKeys: Set<String> = []
    private var sessionCommittedToOperation = false

    func photoKey(for image: UIImage) -> String {
        let oid = ObjectIdentifier(image)
        if let cached = imageKeyCache[oid] { return cached }
        let key = PendingPhotoFingerprint.key(for: image)
        imageKeyCache[oid] = key
        return key
    }

    private func cacheKey(_ key: String, for image: UIImage) {
        imageKeyCache[ObjectIdentifier(image)] = key
    }

    /// Marks a photo as part of the current draft operation; removed from Firebase if the form is discarded before commit.
    func registerSessionPhoto(fingerprintKey key: String) {
        guard !sessionCommittedToOperation else { return }
        sessionDiscardableKeys.insert(key)
    }

    /// Call after in-progress or completed save so draft uploads are kept with the operation record.
    func commitSessionToOperation() {
        sessionCommittedToOperation = true
        sessionDiscardableKeys.removeAll()
    }

    /// Deletes Firebase uploads made in this session when the user abandons the form without saving.
    func discardSessionUploads() {
        guard !sessionCommittedToOperation else { return }
        let keys = sessionDiscardableKeys
        sessionDiscardableKeys.removeAll()
        for key in keys {
            markRemoved(key: key)
        }
    }

    func startUploadIfNeeded(
        image: UIImage,
        storagePath: String,
        fingerprintKey: String? = nil,
        trackForSessionDiscard: Bool = true
    ) {
        Task { @MainActor in
            let key: String
            if let fingerprintKey {
                key = fingerprintKey
                cacheKey(key, for: image)
            } else {
                key = await PendingPhotoFingerprint.keyAsync(for: image)
                cacheKey(key, for: image)
            }

            if trackForSessionDiscard {
                registerSessionPhoto(fingerprintKey: key)
            }
            if let state = states[key] {
                switch state {
                case .uploading, .uploaded:
                    return
                case .cancelled, .failed:
                    break
                }
            }

            states[key] = .uploading
            Task { [weak self] in
                guard let self else { return }
                let url = try? await ImageUploadActor.shared.upload(image: image, path: storagePath)
                await MainActor.run {
                    if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if self.cancelRequested.contains(key) {
                            self.cancelRequested.remove(key)
                            self.states[key] = .cancelled
                            CachedImageManager.shared.deleteImage(url)
                        } else {
                            self.states[key] = .uploaded(url)
                        }
                    } else {
                        self.states[key] = .failed
                    }
                }
            }
        }
    }

    func markRemoved(image: UIImage) {
        markRemoved(key: photoKey(for: image))
    }

    func markRemoved(key: String) {
        sessionDiscardableKeys.remove(key)
        if case .uploaded(let url) = states[key] {
            CachedImageManager.shared.deleteImage(url)
            states[key] = .cancelled
            return
        }
        cancelRequested.insert(key)
        states[key] = .cancelled
    }

    func uploadedURL(for image: UIImage) -> String? {
        let key = photoKey(for: image)
        if case .uploaded(let url) = states[key] {
            return url
        }
        return nil
    }
}
