import UIKit
import CoreGraphics

/// Lightweight sharpness / size heuristics for guided inspection (no ML).
enum ImageInspectionQuality {
    /// Laplacian variance on a small grayscale bitmap — higher usually means sharper.
    static func laplacianVariance(for image: UIImage, maxSide: CGFloat = 128) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        guard w > 2, h > 2 else { return nil }
        let scale = min(1, maxSide / max(w, h))
        let tw = max(8, Int(w * scale))
        let th = max(8, Int(h * scale))

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = tw
        var pixels = [UInt8](repeating: 0, count: tw * th)
        guard let ctx = CGContext(
            data: &pixels,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))

        var sumLap = 0.0
        var sumSq = 0.0
        var count = 0
        for y in 1..<(th - 1) {
            for x in 1..<(tw - 1) {
                let c = Int(pixels[y * tw + x])
                let n = Int(pixels[(y - 1) * tw + x])
                let s = Int(pixels[(y + 1) * tw + x])
                let e = Int(pixels[y * tw + (x - 1)])
                let wP = Int(pixels[y * tw + (x + 1)])
                let lap = Double(4 * c - n - s - e - wP)
                sumLap += lap
                sumSq += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = sumLap / Double(count)
        let variance = (sumSq / Double(count)) - mean * mean
        return max(0, variance)
    }

    static func isAcceptable(_ image: UIImage, minShortSide: CGFloat = 640, minVariance: Double = 12) -> Bool {
        let short = min(image.size.width, image.size.height)
        guard short >= minShortSide else { return false }
        guard let v = laplacianVariance(for: image) else { return true }
        return v >= minVariance
    }
}
