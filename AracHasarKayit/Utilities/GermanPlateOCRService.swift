import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Germany plate OCR: EU strip crop → grayscale variants → Apple Vision OCR → strict parse.
/// No guessing, no character substitution, no seal compensation.
/// Reads exactly what Vision sees; validates against DE plate format.
final class GermanPlateOCRService {

    static let shared = GermanPlateOCRService()

    private init() {}

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let processingLock = NSLock()
    private var isProcessing = false

    // MARK: - Public API

    func recognizeTopCandidates(
        from image: UIImage,
        maxCandidates: Int = 3,
        completion: @escaping ([String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let plates = self?.recognizeTopCandidatesSync(from: image, maxCandidates: maxCandidates) ?? []
            DispatchQueue.main.async { completion(plates) }
        }
    }

    func recognizePlate(from image: UIImage, completion: @escaping (String?) -> Void) {
        recognizeTopCandidates(from: image, maxCandidates: 1) { completion($0.first) }
    }

    func recognizePlateFromPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        completion: @escaping (String?) -> Void
    ) {
        processingLock.lock()
        if isProcessing {
            processingLock.unlock()
            return
        }
        isProcessing = true
        processingLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                self?.processingLock.lock()
                self?.isProcessing = false
                self?.processingLock.unlock()
            }

            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let extent = ciImage.extent.integral
            guard extent.width > 2, extent.height > 2 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let cgImage = self.ciContext.createCGImage(ciImage, from: extent) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            let plates = self.recognizeTopCandidatesSync(from: uiImage, maxCandidates: 1)
            DispatchQueue.main.async { completion(plates.first) }
        }
    }

    // MARK: - Sync pipeline

    private func recognizeTopCandidatesSync(from image: UIImage, maxCandidates: Int) -> [String] {
        guard let base = image.cgImage else { return [] }

        let variants = Self.makeVariants(from: base, context: ciContext)
        guard !variants.isEmpty else { return [] }

        var scores: [String: Double] = [:]

        for variant in variants {
            autoreleasepool {
                let observations = Self.runVisionOCR(on: variant)
                for (text, conf) in observations {
                    let w = Swift.max(Double(conf), 0.01)
                    let candidates = Self.parseGermanPlateCandidates(text)
                    for (idx, plate) in candidates.enumerated() {
                        var weight = w * (idx == 0 ? 1.0 : 0.7)
                        // Dataset validation: known plates get a strong confidence boost.
                        if DEKnownPlateValidator.shared.isKnown(plate) {
                            weight += Double(DEKnownPlateValidator.shared.matchBonus) * 0.1
                        }
                        scores[plate, default: 0] += weight
                    }
                }
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(maxCandidates)
            .map(\.key)
    }

    // MARK: - Image variants (EU strip + academic pipeline)

    /// Produces up to 4 OCR-ready variants:
    ///   1. EU-cropped color
    ///   2. Grayscale enhanced
    ///   3. High contrast + sharpen
    ///   4. Gaussian blur → Otsu binarize → horizontal projection crop (article pipeline)
    private static func makeVariants(from base: CGImage, context: CIContext) -> [CGImage] {
        let scaled = downscale(base, maxLongSide: 1600, context: context) ?? base
        guard let eu = cropLeftFraction(scaled, left: 0.14) else { return [scaled] }

        var list: [CGImage] = [eu]

        if let gray = grayscale(eu, context: context) {
            list.append(gray)
            if let hi = highContrast(gray, context: context) {
                list.append(hi)
            }
            // Variant D: full academic ANPR pipeline
            // Step 1: Gaussian blur (noise reduction)
            // Step 2: Otsu binarization (global threshold)
            // Step 3: Horizontal projection → text-band crop
            // Step 4: Vertical projection → seal blob removal (size-based, color-independent)
            if let blurred    = gaussianBlurCG(gray, context: context),
               let binarized  = otsuBinarizeCG(blurred),
               let projected  = horizontalProjectionCrop(binarized) {
                let sealFree = removeSmallBlobsVP(projected) ?? projected
                list.append(sealFree)
            }
        }

        return list
    }

    // MARK: - Academic pipeline helpers (static, CG-based)

    /// Gaussian blur via CIGaussianBlur — removes speckle noise before thresholding.
    private static func gaussianBlurCG(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let f = CIFilter.gaussianBlur()
        f.inputImage = ci
        f.radius = 0.9
        guard let out = f.outputImage else { return nil }
        return context.createCGImage(out.clamped(to: ci.extent), from: ci.extent)
    }

    /// Otsu global thresholding on luminance: produces binary CGImage (0 = text, 255 = bg).
    private static func otsuBinarizeCG(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        let bpp = 4, bpr = w * bpp
        var buf = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Build luminance histogram
        var hist = [Int](repeating: 0, count: 256)
        var lumas = [UInt8](repeating: 0, count: w * h)
        var pi = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * bpr + x * bpp
                let lum = Int(0.299 * Float(buf[i]) + 0.587 * Float(buf[i+1]) + 0.114 * Float(buf[i+2]))
                let c = UInt8(min(255, max(0, lum)))
                lumas[pi] = c; pi += 1
                hist[Int(c)] += 1
            }
        }

        // Otsu's method
        let total = w * h
        var sumAll: Double = 0
        for t in 0..<256 { sumAll += Double(t) * Double(hist[t]) }
        var sumB: Double = 0, wB = 0, maxVar: Double = 0, thr = 127
        for t in 0..<256 {
            wB += hist[t]; guard wB > 0 else { continue }
            let wF = total - wB; guard wF > 0 else { break }
            sumB += Double(t) * Double(hist[t])
            let mB = sumB / Double(wB), mF = (sumAll - sumB) / Double(wF)
            let v = Double(wB) * Double(wF) * (mB - mF) * (mB - mF)
            if v > maxVar { maxVar = v; thr = t }
        }

        // Apply threshold
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                let i = y * bpr + x * bpp
                let v: UInt8 = lumas[idx] <= UInt8(thr) ? 0 : 255
                buf[i] = v; buf[i+1] = v; buf[i+2] = v; buf[i+3] = 255
            }
        }
        return ctx.makeImage()
    }

    /// Horizontal projection histogram crop — removes plate frame top/bottom margins.
    /// Finds the row-band with the most dark pixels (= plate text) and crops to it.
    private static func horizontalProjectionCrop(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 20, h > 12 else { return image }

        let bpp = 4, bpr = w * bpp
        var buf = [UInt8](repeating: 255, count: h * bpr)
        guard let ctx = CGContext(
            data: &buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Count dark pixels per row
        var rowDark = [Int](repeating: 0, count: h)
        for y in 0..<h {
            for x in 0..<w {
                if buf[y * bpr + x * bpp] < 128 { rowDark[y] += 1 }
            }
        }

        let minDark = max(3, w * 4 / 100)
        let margin  = max(1, h * 8 / 100)
        var topRow  = margin
        var botRow  = h - margin - 1

        for y in margin..<(h - margin) { if rowDark[y] >= minDark { topRow = y; break } }
        for y in stride(from: h - margin - 1, through: margin, by: -1) {
            if rowDark[y] >= minDark { botRow = y; break }
        }
        guard botRow > topRow else { return image }

        let pad = max(2, (botRow - topRow) * 12 / 100)
        let y0  = max(0, topRow - pad)
        let y1  = min(h - 1, botRow + pad)
        guard y1 - y0 >= 6 else { return image }

        return image.cropping(to: CGRect(x: 0, y: y0, width: w, height: y1 - y0 + 1).integral)
    }

    /// Vertical projection seal removal for binary images.
    ///
    /// Identical logic to `PlateNoiseExcluder.removeSealByVerticalProjection` — applied here
    /// on the full-frame fallback path so both pipelines suppress the seal consistently.
    ///
    /// Plate characters span ~90 % of text height; HU/TÜV seal is a small circle (~30–50 %).
    /// Contiguous short-span column blobs in the left 45 % are whited out.
    private static func removeSmallBlobsVP(_ binary: CGImage) -> CGImage? {
        let w = binary.width, h = binary.height
        guard w > 20, h > 8 else { return nil }

        let bpp = 4, bpr = w * bpp
        var buf = [UInt8](repeating: 255, count: h * bpr)
        guard let ctx = CGContext(
            data: &buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(binary, in: CGRect(x: 0, y: 0, width: w, height: h))

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

        let scanW   = max(1, w * 45 / 100)
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

    private static func downscale(_ image: CGImage, maxLongSide: CGFloat, context: CIContext) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let long = max(w, h)
        guard long > maxLongSide else { return image }
        let scale = maxLongSide / long
        let nw = max(1, Int(w * scale)), nh = max(1, Int(h * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: nw, height: nh,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    private static func cropLeftFraction(_ image: CGImage, left: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 32, h > 32 else { return nil }
        let x = w * left
        let nw = w * (1 - left)
        guard nw >= w * 0.45, nw >= 80 else { return nil }
        return image.cropping(to: CGRect(x: x, y: 0, width: nw, height: h).integral)
    }

    private static func grayscale(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let f = CIFilter.colorControls()
        f.inputImage = ci
        f.saturation = 0
        f.contrast = 1.3
        guard let out = f.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }

    private static func highContrast(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let controls = CIFilter.colorControls()
        controls.inputImage = ci
        controls.saturation = 0
        controls.brightness = 0.02
        controls.contrast = 1.8
        guard let contrasted = controls.outputImage else { return nil }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = contrasted
        sharpen.sharpness = 0.6
        guard let out = sharpen.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }

    // MARK: - Vision OCR (sync, height-filtered)

    private static func runVisionOCR(on cgImage: CGImage) -> [(String, Float)] {
        var rawResults: [(String, Float, CGRect)] = []

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else { return }
            let observations = (request.results as? [VNRecognizedTextObservation] ?? []).prefix(20)
            for obs in observations {
                let box = obs.boundingBox
                for cand in obs.topCandidates(3) where cand.confidence >= 0.30 {
                    rawResults.append((cand.string, cand.confidence, box))
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.03
        request.customWords = CountryManager.ocrHints(for: "de")

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        guard !rawResults.isEmpty else { return [] }

        // Height-based filtering: keep only text blobs whose height is comparable
        // to the tallest detected text (plate characters are uniform height).
        let maxHeight = rawResults.map { $0.2.height }.max() ?? 0
        let minHeight = maxHeight * 0.50

        return rawResults
            .filter { _, _, box in box.height >= minHeight && box.width >= 0.03 }
            .map { ($0.0, $0.1) }
    }

    // MARK: - Strict German plate parse

    /// Reads the exact OCR output, splits into valid DE area+series+digits.
    /// No character substitution. No seal compensation. Only exact matches.
    private static func parseGermanPlateCandidates(_ raw: String) -> [String] {
        let compact = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard compact.count >= 4 else { return [] }

        var results: [(plate: String, score: Int)] = []
        var seen = Set<String>()

        for areaLen in stride(from: 3, through: 1, by: -1) {
            guard compact.count > areaLen else { continue }
            let areaPart = String(compact.prefix(areaLen))
            guard areaPart.allSatisfy({ $0.isLetter }) else { continue }
            guard GermanPlateDatabase.isValid(areaPart) else { continue }

            let rest = String(compact.dropFirst(areaLen))
            guard !rest.isEmpty else { continue }
            guard let firstDigitIdx = rest.firstIndex(where: { $0.isNumber }) else { continue }

            let letterPart = String(rest[..<firstDigitIdx])
            guard (1...2).contains(letterPart.count), letterPart.allSatisfy({ $0.isLetter }) else { continue }

            var afterDigits = String(rest[firstDigitIdx...])
            var digits = ""
            while let ch = afterDigits.first, ch.isNumber {
                digits.append(ch)
                afterDigits.removeFirst()
            }
            guard (1...4).contains(digits.count) else { continue }

            var suffix = ""
            if let f = afterDigits.first, "EH".contains(f) {
                suffix = String(f)
            }

            let plate = "\(areaPart) \(letterPart)\(digits)\(suffix)"
            guard CountryManager.country(byId: "de")?.validatePlate(plate) == true else { continue }
            guard seen.insert(plate).inserted else { continue }

            let score = areaLen * 3 + letterPart.count * 4 + digits.count
            results.append((plate, score))
        }

        return results
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.plate < $1.plate }
            .map(\.plate)
    }

    /// Legacy API compatibility.
    static func appFormatFromCanonical(_ canonical: String) -> String? {
        parseGermanPlateCandidates(canonical).first
    }
}
