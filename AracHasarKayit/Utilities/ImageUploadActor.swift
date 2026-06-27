import UIKit

/// Firebase Storage uploads — parallel (CachedImageManager limits concurrency); does not block main thread.
actor ImageUploadActor {
    static let shared = ImageUploadActor()

    func upload(image: UIImage, path: String) async throws -> String {
        let prepared = image.uploadOptimizedForDraft(maxPixel: 1920) ?? image
        return try await withCheckedThrowingContinuation { cont in
            CachedImageManager.shared.uploadImage(prepared, path: path) { url, error in
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

private extension UIImage {
    func uploadOptimizedForDraft(maxPixel: CGFloat) -> UIImage? {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxPixel, maxSide > 0 else { return self }
        let scale = maxPixel / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
