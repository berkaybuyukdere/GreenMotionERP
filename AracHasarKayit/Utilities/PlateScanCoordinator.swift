import Foundation
import CoreVideo
import UIKit

/// Coordinates German plate recognition: YOLO detection → ROI crop → EU strip + grayscale → Vision OCR → strict parse.
/// Falls back to full-frame OCR when YOLO model is not bundled.
final class PlateScanCoordinator {
    static let shared = PlateScanCoordinator()

    private let detector: YoloPlateDetector
    private let roiNormalizer: PlateRoiNormalizer
    private let noiseExcluder: PlateNoiseExcluder
    private let ocrService: GermanPlateOCRService

    private let stateLock = NSLock()
    private var isProcessing = false
    private var scanningCallback: ((Bool) -> Void)?

    init(
        detector: YoloPlateDetector = .shared,
        roiNormalizer: PlateRoiNormalizer = PlateRoiNormalizer(),
        noiseExcluder: PlateNoiseExcluder = PlateNoiseExcluder(),
        ocrService: GermanPlateOCRService = .shared
    ) {
        self.detector = detector
        self.roiNormalizer = roiNormalizer
        self.noiseExcluder = noiseExcluder
        self.ocrService = ocrService
    }

    func scanGermanPlate(
        from pixelBuffer: CVPixelBuffer,
        scanningChanged: ((Bool) -> Void)? = nil,
        completion: @escaping (String?) -> Void
    ) {
        guard beginProcessing() else { return }
        scanningCallback = scanningChanged
        notifyScanning(true)

        detector.detectPlate(in: pixelBuffer) { [weak self] detection in
            guard let self else {
                Self.shared.endProcessing(completion: completion, value: nil)
                return
            }

            guard let detection,
                  let plateImage = self.roiNormalizer.cropPlateImage(from: pixelBuffer, detectionBox: detection.boundingBox)
            else {
                self.fallbackOCR(pixelBuffer: pixelBuffer, completion: completion)
                return
            }

            let variants = self.noiseExcluder.makeGermanSealExcludedVariants(from: plateImage, countryId: "de")
            self.recognizeBestFromVariants(variants, fallbackPixelBuffer: pixelBuffer, completion: completion)
        }
    }

    // MARK: - Private

    private func fallbackOCR(pixelBuffer: CVPixelBuffer, completion: @escaping (String?) -> Void) {
        ocrService.recognizePlateFromPixelBuffer(pixelBuffer) { [weak self] plate in
            self?.endProcessing(completion: completion, value: plate)
        }
    }

    private func recognizeBestFromVariants(
        _ variants: [UIImage],
        fallbackPixelBuffer: CVPixelBuffer,
        completion: @escaping (String?) -> Void
    ) {
        guard !variants.isEmpty else {
            fallbackOCR(pixelBuffer: fallbackPixelBuffer, completion: completion)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var scores: [String: Int] = [:]

        for image in variants {
            group.enter()
            ocrService.recognizeTopCandidates(from: image, maxCandidates: 3) { candidates in
                lock.lock()
                for (idx, value) in candidates.enumerated() {
                    let plate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    guard !plate.isEmpty else { continue }
                    scores[plate, default: 0] += (idx == 0 ? 3 : 1)
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            let winner = Self.bestPlateByValidation(scores)
            guard let self else {
                Self.shared.endProcessing(completion: completion, value: winner)
                return
            }
            if let winner {
                self.endProcessing(completion: completion, value: winner)
            } else {
                self.fallbackOCR(pixelBuffer: fallbackPixelBuffer, completion: completion)
            }
        }
    }

    /// Pick highest-scored plate that passes DE format validation.
    /// Known-dataset plates receive an extra score boost.
    private static func bestPlateByValidation(_ scores: [String: Int]) -> String? {
        guard !scores.isEmpty else { return nil }
        func adjusted(_ key: String, _ value: Int) -> Int {
            var s = value
            if DEKnownPlateValidator.shared.isKnown(key) {
                s += DEKnownPlateValidator.shared.matchBonus
            }
            return s
        }
        return scores
            .filter { CountryManager.validatePlate($0.key, forCountry: "de") }
            .max { lhs, rhs in
                let la = adjusted(lhs.key, lhs.value)
                let ra = adjusted(rhs.key, rhs.value)
                if la != ra { return la < ra }
                return lhs.key > rhs.key
            }?.key
    }

    private func notifyScanning(_ active: Bool) {
        guard let cb = scanningCallback else { return }
        if Thread.isMainThread { cb(active) }
        else { DispatchQueue.main.async { cb(active) } }
    }

    private func endProcessing(completion: @escaping (String?) -> Void, value: String?) {
        notifyScanning(false)
        scanningCallback = nil
        stateLock.lock()
        isProcessing = false
        stateLock.unlock()
        completion(value)
    }

    private func beginProcessing() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if isProcessing { return false }
        isProcessing = true
        return true
    }
}
