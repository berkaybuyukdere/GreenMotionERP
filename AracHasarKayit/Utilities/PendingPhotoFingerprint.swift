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

    /// Off main thread — use before appending photos so Take Photo stays responsive.
    static func keyAsync(for image: UIImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            key(for: image)
        }.value
    }
}
