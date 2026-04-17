import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Germany-only plate image preparation.
///
/// Implements the academic ANPR preprocessing pipeline from:
///   "Automatic License Plate Detection & Recognition using deep learning"
///
/// Pipeline:
///   Input → EU strip crop → Chroma seal whitening
///        → [Variant A] Color (Vision uses its own preprocessing)
///        → [Variant B] Grayscale enhanced
///        → [Variant C] High contrast + sharpen
///        → [Variant D] BGR→GRAY → Gaussian blur → Otsu binarize
///                      → Horizontal projection → text-band crop
///                      → Vertical projection → seal blob removal
///
/// Variant D is the direct implementation of the article's Step 2 segmentation.
/// The vertical projection step exploits the key physical property of the HU/TÜV
/// seal: it is a small circle, significantly shorter in height than plate characters.
/// Plate characters span ~90 % of the text band; the seal spans only ~30–50 %.
/// Any contiguous group of columns in the left 45 % of the plate whose vertical
/// dark-pixel span is < 65 % of the tallest character column is whited out.
final class PlateNoiseExcluder {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func removeEUStripIfNeeded(from image: UIImage, countryId: String) -> UIImage {
        guard countryId.lowercased() == "de" else { return image }
        guard let cgImage = image.cgImage else { return image }
        guard let cleanedCG = cropEUStrip(from: cgImage) else { return image }
        return UIImage(cgImage: cleanedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Returns up to 4 variants for Vision OCR.
    func makeGermanSealExcludedVariants(from image: UIImage, countryId: String) -> [UIImage] {
        guard countryId.lowercased() == "de" else { return [image] }
        guard let cgImage = image.cgImage else { return [image] }

        // Step 1: crop EU blue strip (left ~14%)
        let euCropped = cropEUStrip(from: cgImage) ?? cgImage

        // Step 2: whiten HU/TÜV seal columns (chroma-based — black text untouched)
        let sealRemoved = removeSealColumns(from: euCropped) ?? euCropped

        // Variant A – color, seal-removed (Vision applies its own binarization)
        let varA = UIImage(cgImage: sealRemoved, scale: image.scale, orientation: image.imageOrientation)
        var out: [UIImage] = [varA]

        // Variant B – grayscale enhanced
        if let gray = grayscale(sealRemoved) {
            out.append(UIImage(cgImage: gray, scale: image.scale, orientation: image.imageOrientation))

            // Variant C – high contrast + sharpen
            if let hi = highContrast(gray) {
                out.append(UIImage(cgImage: hi, scale: image.scale, orientation: image.imageOrientation))
            }

            // Variant D – academic pipeline:
            //   blur → Otsu binarize → horizontal projection crop → vertical projection seal removal
            // After text-band crop the image is pure black/white. The seal is the only blob
            // whose column-height is significantly shorter than the plate characters → removed.
            if let blurred   = gaussianBlur(gray),
               let binarized = otsuBinarize(blurred),
               let cropped   = cropToTextBand(binarized) {
                let sealFree = removeSealByVerticalProjection(cropped) ?? cropped
                out.append(UIImage(cgImage: sealFree, scale: image.scale, orientation: image.imageOrientation))
            }
        }

        return out
    }

    // MARK: - EU strip crop

    private func cropEUStrip(from image: CGImage, leftCutRatio: CGFloat = 0.14) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w >= 80, h >= 24 else { return image }
        let cut = w * leftCutRatio
        let nw  = w - cut
        guard nw >= w * 0.45 else { return image }
        return image.cropping(to: CGRect(x: cut, y: 0, width: nw, height: h).integral)
    }

    // MARK: - Chroma-based seal whitening

    /// Scans the left 55 % of the plate column-by-column.
    /// Columns whose average chroma > threshold are seal sticker → painted white.
    /// FE-Schrift black letters have near-zero chroma → never affected.
    /// Threshold lowered to 22 to catch lightly-saturated or JPEG-compressed stickers.
    private func removeSealColumns(from image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 60, height > 20 else { return nil }

        let bpp = 4, bpr = width * bpp
        var buf = [UInt8](repeating: 0, count: height * bpr)

        guard let ctx = CGContext(
            data: &buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scanW = min(width, Int(Double(width) * 0.55))
        var colChroma = [Float](repeating: 0, count: scanW)
        for x in 0..<scanW {
            var sum: Float = 0
            for y in 0..<height {
                let i = y * bpr + x * bpp
                let r = Float(buf[i]), g = Float(buf[i+1]), b = Float(buf[i+2])
                sum += max(r, max(g, b)) - min(r, min(g, b))
            }
            colChroma[x] = sum / Float(height)
        }

        let threshold: Float = 22
        var sealCols = IndexSet()
        var blobStart = -1
        for x in 0...scanW {
            let isColored = x < scanW && colChroma[x] > threshold
            if isColored {
                if blobStart == -1 { blobStart = x }
            } else if blobStart != -1 {
                if x - blobStart >= 2 { sealCols.insert(integersIn: blobStart..<x) }
                blobStart = -1
            }
        }

        guard !sealCols.isEmpty else { return nil }

        var expanded = IndexSet()
        for x in sealCols {
            expanded.insert(integersIn: max(0, x-2)...min(width-1, x+2))
        }
        for x in expanded {
            for y in 0..<height {
                let i = y * bpr + x * bpp
                buf[i] = 255; buf[i+1] = 255; buf[i+2] = 255; buf[i+3] = 255
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Vertical projection seal removal (size-based, color-independent)

    /// Removes the HU/TÜV seal from a **binary** plate image using column-height analysis.
    ///
    /// Key physical insight: plate characters (FE-Schrift) are tall — their dark pixel columns
    /// span almost the full text-band height. The seal is a small circle: its dark pixel columns
    /// have a much shorter vertical span (~30–50 % of character height).
    ///
    /// Algorithm:
    ///   1. For every column compute the vertical span of dark pixels (topmost – bottommost).
    ///   2. Find `maxSpan` = tallest column (= a character column).
    ///   3. Any contiguous blob of columns in the left 45 % where span < 65 % of maxSpan
    ///      is classified as a seal and whited out (±2 px padding).
    private func removeSealByVerticalProjection(_ binaryImage: CGImage) -> CGImage? {
        let w = binaryImage.width, h = binaryImage.height
        guard w > 20, h > 8 else { return nil }

        let bpp = 4, bpr = w * bpp
        var buf = [UInt8](repeating: 255, count: h * bpr)
        guard let ctx = CGContext(
            data: &buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(binaryImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Per-column: find topmost and bottommost dark pixel
        var colTop = [Int](repeating: h, count: w)
        var colBot = [Int](repeating: -1, count: w)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * bpr + x * bpp
                if buf[i] < 128 {
                    if y < colTop[x] { colTop[x] = y }
                    if y > colBot[x] { colBot[x] = y }
                }
            }
        }

        var colSpan = [Int](repeating: 0, count: w)
        for x in 0..<w {
            if colBot[x] >= colTop[x] { colSpan[x] = colBot[x] - colTop[x] + 1 }
        }

        let maxSpan = colSpan.max() ?? 0
        guard maxSpan >= 4 else { return nil }

        // Only examine left 45 % of the plate (seal is always before the ID letters)
        let scanW  = max(1, w * 45 / 100)
        let spanThr = maxSpan * 65 / 100

        var sealCols = IndexSet()
        var blobStart = -1
        for x in 0...scanW {
            let isSeal = x < scanW && colSpan[x] > 0 && colSpan[x] < spanThr
            if isSeal {
                if blobStart == -1 { blobStart = x }
            } else if blobStart != -1 {
                if x - blobStart >= 2 { sealCols.insert(integersIn: blobStart..<x) }
                blobStart = -1
            }
        }
        guard !sealCols.isEmpty else { return nil }

        // Expand by ±2 px so any partial-column edge pixels are also removed
        var expanded = IndexSet()
        for x in sealCols {
            expanded.insert(integersIn: max(0, x-2)...min(w-1, x+2))
        }
        for x in expanded {
            for y in 0..<h {
                let i = y * bpr + x * bpp
                buf[i] = 255; buf[i+1] = 255; buf[i+2] = 255; buf[i+3] = 255
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Grayscale + contrast (CIImage path — GPU accelerated)

    private func grayscale(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let f = CIFilter.colorControls()
        f.inputImage = ci; f.saturation = 0; f.contrast = 1.35
        guard let out = f.outputImage else { return nil }
        return ciContext.createCGImage(out, from: out.extent)
    }

    private func highContrast(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let c = CIFilter.colorControls()
        c.inputImage = ci; c.saturation = 0; c.brightness = 0.03; c.contrast = 1.85
        guard let contrasted = c.outputImage else { return nil }
        let s = CIFilter.sharpenLuminance()
        s.inputImage = contrasted; s.sharpness = 0.65
        guard let out = s.outputImage else { return nil }
        return ciContext.createCGImage(out, from: out.extent)
    }

    // MARK: - Academic pipeline: Gaussian blur → Otsu binarize → projection crop

    /// Step: Gaussian blur to reduce noise before binarization.
    /// CIGaussianBlur on CPU/GPU; radius = 0.8 (light smoothing, preserves edge sharpness).
    private func gaussianBlur(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let f = CIFilter.gaussianBlur()
        f.inputImage = ci
        f.radius = 0.8
        guard let out = f.outputImage else { return nil }
        // Gaussian blur extends extent; clamp to original bounds.
        let clamped = out.clamped(to: ci.extent)
        return ciContext.createCGImage(clamped, from: ci.extent)
    }

    /// Step: Otsu global thresholding on luminance channel.
    /// Output: binary CGImage (0 = text, 255 = background).
    private func otsuBinarize(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        let bpp = 4, bpr = width * bpp
        var buf = [UInt8](repeating: 0, count: height * bpr)

        guard let ctx = CGContext(
            data: &buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Build luminance histogram
        var histogram = [Int](repeating: 0, count: 256)
        var lumas = [UInt8](repeating: 0, count: width * height)
        var pi = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bpr + x * bpp
                let lum = Int(0.299 * Float(buf[i]) + 0.587 * Float(buf[i+1]) + 0.114 * Float(buf[i+2]))
                let clamped = UInt8(min(255, max(0, lum)))
                lumas[pi] = clamped
                pi += 1
                histogram[Int(clamped)] += 1
            }
        }

        // Otsu's method: maximize inter-class variance
        let total = width * height
        var sumAll: Double = 0
        for t in 0..<256 { sumAll += Double(t) * Double(histogram[t]) }

        var sumB: Double = 0, wB = 0, maxVar: Double = 0, threshold = 127
        for t in 0..<256 {
            wB += histogram[t]
            guard wB > 0 else { continue }
            let wF = total - wB
            guard wF > 0 else { break }
            sumB += Double(t) * Double(histogram[t])
            let mB = sumB / Double(wB)
            let mF = (sumAll - sumB) / Double(wF)
            let v = Double(wB) * Double(wF) * (mB - mF) * (mB - mF)
            if v > maxVar { maxVar = v; threshold = t }
        }

        // Apply threshold: pixels darker than threshold → black text, rest → white
        for idx in 0..<(width * height) {
            let y = idx / width
            let x = idx % width
            let bi = y * bpr + x * bpp
            let v: UInt8 = lumas[idx] <= UInt8(threshold) ? 0 : 255
            buf[bi] = v; buf[bi+1] = v; buf[bi+2] = v; buf[bi+3] = 255
        }

        return ctx.makeImage()
    }

    /// Step: Horizontal projection histogram to find the text band.
    /// Row-wise dark pixel count → find densest rows → crop to that band.
    /// Eliminates plate frame top/bottom margins so Vision only sees characters.
    private func cropToTextBand(_ binaryImage: CGImage) -> CGImage? {
        let width = binaryImage.width, height = binaryImage.height
        guard width > 20, height > 12 else { return nil }

        let bpp = 4, bpr = width * bpp
        var buf = [UInt8](repeating: 255, count: height * bpr)

        guard let ctx = CGContext(
            data: &buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(binaryImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Horizontal projection: count dark pixels per row
        var rowDark = [Int](repeating: 0, count: height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bpr + x * bpp
                if buf[i] < 128 { rowDark[y] += 1 }
            }
        }

        // Minimum dark pixels to qualify as a "text row" (≥ 4 % of width)
        let minDark = max(3, width * 4 / 100)

        // Skip border rows (top/bottom 8 %)
        let margin = max(1, height * 8 / 100)

        var topRow = margin
        var botRow = height - margin - 1

        for y in margin..<(height - margin) {
            if rowDark[y] >= minDark { topRow = y; break }
        }
        for y in stride(from: height - margin - 1, through: margin, by: -1) {
            if rowDark[y] >= minDark { botRow = y; break }
        }

        guard botRow > topRow else { return binaryImage }

        // Add vertical padding (12 % of text height)
        let pad = max(2, (botRow - topRow) * 12 / 100)
        let y0 = max(0, topRow - pad)
        let y1 = min(height - 1, botRow + pad)
        let cropH = y1 - y0 + 1
        guard cropH >= 6 else { return binaryImage }

        return binaryImage.cropping(to: CGRect(x: 0, y: y0, width: width, height: cropH).integral)
    }
}
