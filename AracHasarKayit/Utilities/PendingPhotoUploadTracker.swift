import Foundation
import UIKit
import CryptoKit

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

    func photoKey(for image: UIImage) -> String {
        let data = image.jpegData(compressionQuality: 0.92) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    func startUploadIfNeeded(image: UIImage, storagePath: String) {
        let key = photoKey(for: image)
        if let state = states[key] {
            switch state {
            case .uploading, .uploaded:
                return
            case .cancelled, .failed:
                break
            }
        }

        states[key] = .uploading
        CachedImageManager.shared.uploadImage(image, path: storagePath) { [weak self] url, _ in
            DispatchQueue.main.async {
                guard let self else { return }
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
