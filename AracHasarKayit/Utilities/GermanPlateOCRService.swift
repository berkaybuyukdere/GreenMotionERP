import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Almanya plakası: sol EU / ikon şeridi OCR'a dahil edilmez (kırpma),
/// tek veya iki hafif görüntü varyantı + Vision, ardından parçalı güvenli ayrıştırma.
/// Ağır paralel pipeline kaldırıldı — bellek ve crash riski azaltıldı.
final class GermanPlateOCRService {

    static let shared = GermanPlateOCRService()

    private init() {}

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let processingLock = NSLock()
    private var isProcessing = false

    // MARK: - Public API

    /// Arka planda çalışır; tamamlanınca main queue'da döner.
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

    // MARK: - Sync pipeline (always called from background)

    private func recognizeTopCandidatesSync(from image: UIImage, maxCandidates: Int) -> [String] {
        guard let base = image.cgImage else { return [] }

        let variants = Self.makeVariants(from: base, context: ciContext)
        guard !variants.isEmpty else { return [] }

        var scores: [String: Double] = [:]

        for variant in variants {
            autoreleasepool {
                let observations = Self.runVisionSync(on: variant)
                for (text, conf) in observations {
                    let w = Swift.max(Double(conf), 0.01)
                    let parsedCandidates = Self.parseSegmentedGermanPlateCandidates(text)
                    for (idx, plate) in parsedCandidates.enumerated() {
                        // Keep top-ranked parser candidate dominant, but still score alternatives.
                        let candidateWeight = w * (idx == 0 ? 1.0 : 0.72)
                        scores[plate, default: 0] += candidateWeight
                    }
                    let asciiOnly = Self.asciiLettersDigits(text)
                    if asciiOnly != text.uppercased() {
                        let asciiCandidates = Self.parseSegmentedGermanPlateCandidates(asciiOnly)
                        for (idx, plate) in asciiCandidates.enumerated() {
                            let candidateWeight = (w * 0.95) * (idx == 0 ? 1.0 : 0.72)
                            scores[plate, default: 0] += candidateWeight
                        }
                    }
                }
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .prefix(maxCandidates)
            .map(\.key)
    }

    // MARK: - Image: EU strip crop + downscale (ikon alanını düşür)

    private static func makeVariants(from base: CGImage, context: CIContext) -> [CGImage] {
        let scaled = downscale(base, maxLongSide: 1600, context: context) ?? base
        var list: [CGImage] = []

        if let eu = cropLeftFraction(scaled, left: 0.16) {
            list.append(eu)
        } else {
            list.append(scaled)
        }

        if let eu = cropLeftFraction(scaled, left: 0.16),
           let gray = grayscale(eu, context: context) {
            list.append(gray)
            if let high = highContrast(gray, context: context) {
                list.append(high)
            }
        }

        return dedupe(list)
    }

    private static func downscale(_ image: CGImage, maxLongSide: CGFloat, context: CIContext) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let long = max(w, h)
        guard long > maxLongSide else { return image }
        let scale = maxLongSide / long
        let nw = max(1, Int(w * scale)), nh = max(1, Int(h * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: nw,
            height: nh,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    /// Sol taraftaki mavi EU şeridi + yuvarlak damga görüntüsünü mümkün olduğunca keser.
    private static func cropLeftFraction(_ image: CGImage, left: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 32, h > 32 else { return nil }
        let x = w * left
        let nw = w * (1 - left)
        guard nw >= w * 0.45, nw >= 80 else { return nil }
        let rect = CGRect(x: x, y: 0, width: nw, height: h).integral
        return image.cropping(to: rect)
    }

    private static func grayscale(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let f = CIFilter.colorControls()
        f.inputImage = ci
        f.saturation = 0
        f.contrast = 1.2
        guard let out = f.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }

    private static func highContrast(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let controls = CIFilter.colorControls()
        controls.inputImage = ci
        controls.saturation = 0
        controls.brightness = 0.02
        controls.contrast = 1.7
        guard let contrasted = controls.outputImage else { return nil }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = contrasted
        sharpen.sharpness = 0.7
        guard let out = sharpen.outputImage else { return nil }
        return context.createCGImage(out, from: out.extent)
    }

    private static func dedupe(_ images: [CGImage]) -> [CGImage] {
        var seen = Set<String>()
        return images.filter {
            let k = "\($0.width)x\($0.height)"
            return seen.insert(k).inserted
        }
    }

    // MARK: - Vision (sync)

    private static func runVisionSync(on cgImage: CGImage) -> [(String, Float)] {
        var collected: [(String, Float)] = []

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else { return }
            let observations = (request.results as? [VNRecognizedTextObservation] ?? []).prefix(20)
            for obs in observations {
                for cand in obs.topCandidates(5) where cand.confidence >= 0.25 {
                    collected.append((cand.string, cand.confidence))
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = false
        request.customWords = CountryManager.ocrHints(for: "de")

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return collected
    }

    // MARK: - Parçalı ayrıştırma (il kodu 1–3 harf + kalan)

    private struct GermanPlateSplitCandidate {
        let plate: String
        let score: Int
    }
    
    private struct BoundaryMutation {
        let area: String
        let letters: String
        let penalty: Int
    }
    
    /// OCR metninden birden fazla plaka adayı üretir ve güven skoruna göre sıralar.
    /// Bu, `DGM804` benzeri metinlerde `DG M804` ve `D GM804` gibi olası bölünmeleri
    /// birlikte değerlendirip en güvenilir adayı seçebilmemizi sağlar.
    private static func parseSegmentedGermanPlateCandidates(_ raw: String) -> [String] {
        let compact = asciiLettersDigits(raw)
        guard compact.count >= 4 else { return [] }

        // Only keep the most reliable circular-sticker confusions.
        // Using letter-shaped chars like C/G here can collapse valid series blocks
        // (e.g. DGM... -> DM...).
        let stickerChars: Set<Character> = ["O", "0", "Q"]
        let singleLetterAreaCodes: Set<String> = ["B", "D", "F", "G", "H", "K", "L", "M", "N", "S", "W"]
        var ranked: [GermanPlateSplitCandidate] = []
        var seen = Set<String>()

        for areaLen in stride(from: 3, through: 1, by: -1) {
            guard compact.count > areaLen else { continue }
            let areaRaw = String(compact.prefix(areaLen))
            let areaPart = normalizeLikelyLetterOCR(areaRaw)
            guard areaPart.count == areaLen, areaPart.allSatisfy({ $0.isLetter }) else { continue }

            var areaFixed = areaPart
            if !GermanPlateDatabase.isValid(areaPart) {
                let c = GermanPlateDatabase.correctOCRAreaToken(areaPart)
                guard GermanPlateDatabase.isValid(c) else { continue }
                areaFixed = c
            }
            if GermanPlateDatabase.isKnownMisread(areaFixed) { continue }

            var rest = String(compact.dropFirst(areaLen))
            guard !rest.isEmpty else { continue }

            var strips = 0
            while strips < 2, let first = rest.first, stickerChars.contains(first) {
                rest.removeFirst()
                strips += 1
            }
            guard !rest.isEmpty else { continue }

            guard let firstDigitIdx = rest.firstIndex(where: { $0.isNumber }) else { continue }
            let letterPart = normalizeLikelyLetterOCR(String(rest[..<firstDigitIdx]))
            var afterDigits = String(rest[firstDigitIdx...])

            guard (1...2).contains(letterPart.count), letterPart.allSatisfy({ $0.isLetter }) else { continue }

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

            let mutations = boundaryMutations(
                area: areaFixed,
                letterPart: letterPart,
                areaLen: areaLen
            )
            for mutation in mutations {
                let plate = "\(mutation.area) \(mutation.letters)\(digits)\(suffix)"
                guard CountryManager.country(byId: "de")?.validatePlate(plate) == true else { continue }
                guard seen.insert(plate).inserted else { continue }
                
                var score = 0
                score += mutation.letters.count * 6
                score += mutation.area.count * 2
                
                // Prefer single-letter metropolitan areas when the series has 2 letters (e.g. D GM 804).
                if mutation.area.count == 1, singleLetterAreaCodes.contains(mutation.area), mutation.letters.count == 2 {
                    score += 10
                }
                
                // Penalize less informative split patterns such as 2-letter area + 1-letter series.
                if mutation.area.count == 2, mutation.letters.count == 1 {
                    score -= 5
                }
                
                // If the compact OCR starts with a valid 3-char area and we are using it, boost slightly.
                if compact.count >= 3 {
                    let threePrefix = String(compact.prefix(3))
                    if mutation.area.count == 3, mutation.area == threePrefix, GermanPlateDatabase.isValid(threePrefix) {
                        score += 3
                    }
                }
                
                score -= mutation.penalty
                ranked.append(.init(plate: plate, score: score))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.plate < rhs.plate
            }
            .map(\.plate)
    }
    
    /// Produces boundary variants for area/letter ambiguities.
    /// - Keeps base split.
    /// - Tries conservative one-letter insertions before a 1-letter series for common
    ///   dropped-middle-letter OCR cases (e.g. DM3020 -> DGM3020).
    private static func boundaryMutations(
        area: String,
        letterPart: String,
        areaLen: Int
    ) -> [BoundaryMutation] {
        var variants: [BoundaryMutation] = [
            .init(area: area, letters: letterPart, penalty: 0)
        ]
        
        // Conservative insertion support for missing middle-letter ambiguities:
        //   BM M906  -> BM GM906
        //   D M3020  -> D GM3020
        // We keep this scoped to the boundary and apply a penalty so it only wins
        // when it materially improves structural plausibility.
        if areaLen <= 2, letterPart.count == 1 {
            let insertHints: [Character] = ["G", "C", "E", "D"]
            for hint in insertHints {
                let mutated = "\(hint)\(letterPart)"
                variants.append(.init(area: area, letters: mutated, penalty: 7))
            }
        }
        
        var seen = Set<String>()
        return variants.filter { seen.insert("\($0.area)|\($0.letters)").inserted }
    }
    
    /// Legacy API compatibility: returns top-ranked candidate.
    private static func parseSegmentedGermanPlate(_ raw: String) -> String? {
        parseSegmentedGermanPlateCandidates(raw).first
    }

    private static func asciiLettersDigits(_ s: String) -> String {
        s.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func normalizeLikelyLetterOCR(_ s: String) -> String {
        String(s.uppercased().map { ch -> Character in
            switch ch {
            case "0": return "O"
            case "1": return "I"
            case "5": return "S"
            case "8": return "B"
            case "2": return "Z"
            case "6": return "G"
            default: return ch
            }
        })
    }

    /// Eski API uyumluluğu — artık doğrudan `parseSegmentedGermanPlate` app formatı döner.
    static func appFormatFromCanonical(_ canonical: String) -> String? {
        parseSegmentedGermanPlate(canonical)
    }
}
