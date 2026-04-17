import Foundation
import UIKit
import CoreImage
import CoreVideo

final class PlateRoiNormalizer {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func cropPlateImage(
        from pixelBuffer: CVPixelBuffer,
        detectionBox: CGRect,
        padding: CGFloat = 0.06
    ) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let expanded = expandNormalizedRect(detectionBox, padding: padding)
        let cropRect = denormalizeVisionRect(expanded, in: extent)
        guard cropRect.width > 8, cropRect.height > 8 else { return nil }

        let cropped = ciImage.cropped(to: cropRect.integral)
        guard let cgImage = ciContext.createCGImage(cropped, from: cropped.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

    // Placeholder for future perspective correction support.
    func normalizePerspectiveIfNeeded(_ image: UIImage) -> UIImage {
        image
    }

    private func expandNormalizedRect(_ rect: CGRect, padding: CGFloat) -> CGRect {
        let dx = rect.width * padding
        let dy = rect.height * padding
        let expanded = rect.insetBy(dx: -dx, dy: -dy)

        return CGRect(
            x: max(0, expanded.origin.x),
            y: max(0, expanded.origin.y),
            width: min(1, expanded.maxX) - max(0, expanded.minX),
            height: min(1, expanded.maxY) - max(0, expanded.minY)
        )
    }

    private func denormalizeVisionRect(_ normalizedRect: CGRect, in extent: CGRect) -> CGRect {
        let x = normalizedRect.origin.x * extent.width
        let y = normalizedRect.origin.y * extent.height
        let w = normalizedRect.width * extent.width
        let h = normalizedRect.height * extent.height
        // Vision uses bottom-left origin; CI uses bottom-left too for extent coordinates.
        return CGRect(x: x, y: y, width: w, height: h).intersection(extent)
    }
}
