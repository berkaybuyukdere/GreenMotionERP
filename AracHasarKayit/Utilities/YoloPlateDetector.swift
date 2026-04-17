import Foundation
import Vision
import CoreML
import CoreVideo

struct PlateDetection {
    let boundingBox: CGRect
    let confidence: Float
}

final class YoloPlateDetector {
    static let shared = YoloPlateDetector()

    private let queue = DispatchQueue(label: "plate.yolo.detector.queue", qos: .userInitiated)
    private let modelProvider: () -> VNCoreMLModel?
    private var cachedModel: VNCoreMLModel?
    private let lock = NSLock()

    init(modelProvider: (() -> VNCoreMLModel?)? = nil) {
        self.modelProvider = modelProvider ?? { Self.loadModelFromBundle() }
    }

    func detectPlate(
        in pixelBuffer: CVPixelBuffer,
        completion: @escaping (PlateDetection?) -> Void
    ) {
        queue.async {
            let detection = self.detectPlateSync(in: pixelBuffer)
            DispatchQueue.main.async {
                completion(detection)
            }
        }
    }

    func detectPlateSync(in pixelBuffer: CVPixelBuffer) -> PlateDetection? {
        guard let model = resolvedModel() else { return nil }

        var bestDetection: PlateDetection?
        let request = VNCoreMLRequest(model: model) { request, _ in
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            bestDetection = observations
                .map { PlateDetection(boundingBox: $0.boundingBox, confidence: $0.confidence) }
                .max(by: { $0.confidence < $1.confidence })
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return bestDetection
    }

    var isModelAvailable: Bool {
        resolvedModel() != nil
    }

    private func resolvedModel() -> VNCoreMLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedModel {
            return cachedModel
        }
        let model = modelProvider()
        cachedModel = model
        return model
    }

    private static func loadModelFromBundle() -> VNCoreMLModel? {
        let modelNames = [
            "LicensePlateDetectorYOLO",
            "YoloPlateDetector",
            "PlateDetectorYOLO",
            "PlateDetector"
        ]

        for name in modelNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { continue }
            do {
                let mlModel = try MLModel(contentsOf: url)
                return try VNCoreMLModel(for: mlModel)
            } catch {
                continue
            }
        }
        return nil
    }
}
