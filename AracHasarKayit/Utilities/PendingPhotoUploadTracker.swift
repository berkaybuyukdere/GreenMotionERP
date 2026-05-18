import Foundation
import UIKit
import CryptoKit

/// Lightweight pixel fingerprint for dedupe + upload state. Uses a small thumbnail hash so dismiss/camera flows
/// do not JPEG-encode full-resolution images on the main thread (upload still uses the original `UIImage`).
enum PendingPhotoFingerprint {
    private static let thumbMaxSide: CGFloat = 160
    private static let hashJPEGQuality: CGFloat = 0.82

    static func key(for image: UIImage) -> String {
        let thumb = image.preparingThumbnail(of: CGSize(width: thumbMaxSide, height: thumbMaxSide)) ?? image
        let data = thumb.jpegData(compressionQuality: hashJPEGQuality) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class PendingPhotoUploadTracker: ObservableObject {
    enum State {
        case uploading
        case uploaded(String)
        case cancelled
        case failed
    }

    @Published private(set) var states: [String: State] = [:]

    private var cancelRequested: Set<String> = []
    /// Photo keys uploaded during the current operation form session; deleted on discard unless committed.
    private var sessionDiscardableKeys: Set<String> = []
    private var sessionCommittedToOperation = false

    func photoKey(for image: UIImage) -> String {
        PendingPhotoFingerprint.key(for: image)
    }

    /// Marks a photo as part of the current draft operation; removed from Firebase if the form is discarded before commit.
    func registerSessionPhoto(image: UIImage) {
        guard !sessionCommittedToOperation else { return }
        sessionDiscardableKeys.insert(photoKey(for: image))
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

    func startUploadIfNeeded(image: UIImage, storagePath: String, trackForSessionDiscard: Bool = true) {
        let key = photoKey(for: image)
        if trackForSessionDiscard {
            registerSessionPhoto(image: image)
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

    func markRemoved(image: UIImage) {
        let key = photoKey(for: image)
        markRemoved(key: key)
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
