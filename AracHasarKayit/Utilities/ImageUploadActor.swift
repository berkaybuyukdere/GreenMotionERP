import UIKit

/// Serializes Firebase Storage uploads so rapid capture / retry paths queue instead of racing.
actor ImageUploadActor {
    static let shared = ImageUploadActor()

    private var last: Task<Void, Never>?

    func upload(image: UIImage, path: String) async throws -> String {
        let previous = last
        let work = Task<String, Error> {
            await previous?.value
            return try await withCheckedThrowingContinuation { cont in
                CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                    if let url, error == nil {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(throwing: error ?? ImageUploadActorError.uploadFailed)
                    }
                }
            }
        }
        last = Task {
            _ = try? await work.value
        }
        return try await work.value
    }
}

enum ImageUploadActorError: Error {
    case uploadFailed
}
