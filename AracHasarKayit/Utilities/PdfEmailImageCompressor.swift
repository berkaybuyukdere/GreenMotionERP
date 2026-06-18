import UIKit

enum PdfEmailImageCompressor {
    /// Max condition photos embedded in checkout/return customer email PDFs.
    static let maxPhotos = 50

    static func cappedPhotoURLs(_ urls: [String]) -> [String] {
        Array(urls.prefix(maxPhotos))
    }

    /// Downscale + JPEG re-encode so large fleets (40+ photos) stay mailable.
    static func compressForEmailPdf(_ image: UIImage) -> UIImage {
        let maxEdge: CGFloat = 1100
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxEdge / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.68),
              let out = UIImage(data: data) else {
            return rendered
        }
        return out
    }

    static func compressAll(_ images: [UIImage]) -> [UIImage] {
        images.map { compressForEmailPdf($0) }
    }
}
