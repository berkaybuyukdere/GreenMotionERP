import UIKit

/// Firebase Storage uploads — parallel (CachedImageManager limits concurrency); does not block main thread.
actor ImageUploadActor {
    static let shared = ImageUploadActor()

    func upload(image: UIImage, path: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                if let url, error == nil {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: error ?? ImageUploadActorError.uploadFailed)
                }
            }
        }
    }
}

enum ImageUploadActorError: Error {
    case uploadFailed
}
