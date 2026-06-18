import Foundation
import UIKit
import Vision

// Shared vision result types (used by camera UI + overlay).
struct CosmosDetectedObject: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Double
    /// Normalized 0…1, origin top-left.
    let rect: CGRect

    var confidencePercent: Int { Int((confidence * 100).rounded()) }

    var isPlateLike: Bool {
        let l = label.lowercased()
        return l.contains("plate") || l.contains("license") || l.contains("plaka")
            || l.contains("kennzeichen") || l.contains("nummernschild") || l.contains("text")
    }
}

struct CosmosVisionAnalysisResult: Equatable {
    let objects: [CosmosDetectedObject]
    let licensePlate: String?
    let plateConfidence: Double?
    let vehicleDescription: String?
    let summary: String
    let providerLabel: String
    let frameSize: CGSize

    static let empty = CosmosVisionAnalysisResult(
        objects: [],
        licensePlate: nil,
        plateConfidence: nil,
        vehicleDescription: nil,
        summary: "",
        providerLabel: "NVIDIA LocateAnything-3B",
        frameSize: .zero
    )
}

enum LocateAnythingVisionError: LocalizedError {
    case invalidImage
    case invalidResponse
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not encode camera frame."
        case .invalidResponse: return "Could not parse LocateAnything response."
        case .serviceUnavailable(let msg): return msg
        }
    }
}

/// NVIDIA LocateAnything-3B — Parallel Box Decoding for fleet object + plate localization.
final class LocateAnythingVisionService {
    static let shared = LocateAnythingVisionService()

    private let hfSpaceBase = "https://nvidia-locateanything.hf.space"
    private let localLocateURL = URL(string: "http://127.0.0.1:8080/v1/locate")!

    private let maxLongEdge: CGFloat = 768
    private let jpegQuality: CGFloat = 0.72
    private let fleetCategories = "car, truck, van, bus, motorcycle, person, license plate, vehicle, windshield, tire"

    private var lastBackend = "NVIDIA LocateAnything-3B"
    private var localReachable: Bool?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 50
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    var hasAPIKey: Bool { true }
    var activeBackendLabel: String { lastBackend }

    func analyzeFrame(_ image: UIImage, countryHint: String = "CH") async throws -> CosmosVisionAnalysisResult {
        let prepared = Self.prepareFrame(image, maxLongEdge: maxLongEdge, jpegQuality: jpegQuality)
        guard let jpeg = prepared.jpeg, prepared.frameSize.width > 0 else {
            throw LocateAnythingVisionError.invalidImage
        }

        if shouldTryLocal() {
            if let local = try? await analyzeViaLocalLocate(jpeg: jpeg, frameSize: prepared.frameSize, countryHint: countryHint) {
                localReachable = true
                lastBackend = "LocateAnything-3B · Local NIM"
                return local
            }
            localReachable = false
        }

        if let remote = try? await analyzeViaHFSpace(jpeg: jpeg, frameSize: prepared.frameSize, countryHint: countryHint) {
            lastBackend = "LocateAnything-3B · NVIDIA HF"
            return remote
        }

        let fallback = await analyzeOnDevice(image: image, frameSize: prepared.frameSize, countryHint: countryHint)
        lastBackend = "LocateAnything · On-Device Assist"
        return fallback
    }

    // MARK: - Local FastAPI (/v1/locate)

    private func analyzeViaLocalLocate(
        jpeg: Data,
        frameSize: CGSize,
        countryHint: String
    ) async throws -> CosmosVisionAnalysisResult {
        let b64 = jpeg.base64EncodedString()

        async let detectTask = localRequest(
            body: [
                "image_b64": b64,
                "task": "detect",
                "query": fleetCategories,
                "mode": "fast",
            ],
            timeout: 12
        )
        async let textTask = localRequest(
            body: [
                "image_b64": b64,
                "task": "detect_text",
                "mode": "fast",
            ],
            timeout: 12
        )

        let detect = try await detectTask
        let text = try await textTask
        return mergeAnswers(
            detectAnswer: detectAnswerString(detect),
            textAnswer: detectAnswerString(text),
            frameSize: frameSize,
            countryHint: countryHint,
            provider: "LocateAnything-3B · Local NIM"
        )
    }

    private func localRequest(body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var request = URLRequest(url: localLocateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocateAnythingVisionError.serviceUnavailable("Local LocateAnything unavailable.")
        }
        return json
    }

    // MARK: - Hugging Face Space (official demo API)

    private func analyzeViaHFSpace(
        jpeg: Data,
        frameSize: CGSize,
        countryHint: String
    ) async throws -> CosmosVisionAnalysisResult {
        let uploadPath = try await hfUpload(jpeg: jpeg)

        async let detectAnswer = hfRunInference(
            uploadPath: uploadPath,
            taskType: "Detection",
            category: fleetCategories,
            mode: "fast",
            shortSize: Int(maxLongEdge)
        )
        async let textAnswer = hfRunInference(
            uploadPath: uploadPath,
            taskType: "Scene Text Detection",
            category: "text",
            mode: "fast",
            shortSize: Int(maxLongEdge)
        )

        let detect = try await detectAnswer
        let text = try await textAnswer
        return mergeAnswers(
            detectAnswer: detect,
            textAnswer: text,
            frameSize: frameSize,
            countryHint: countryHint,
            provider: "LocateAnything-3B · NVIDIA HF"
        )
    }

    private func hfUpload(jpeg: Data) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "\(hfSpaceBase)/gradio_api/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 25

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code),
              let paths = try JSONSerialization.jsonObject(with: data) as? [String],
              let path = paths.first else {
            throw LocateAnythingVisionError.serviceUnavailable("HF upload failed.")
        }
        return path
    }

    private func hfRunInference(
        uploadPath: String,
        taskType: String,
        category: String,
        mode: String,
        shortSize: Int
    ) async throws -> String {
        let filePayload: [String: Any] = [
            "path": uploadPath,
            "meta": ["_type": "gradio.FileData"],
            "orig_name": "frame.jpg",
        ]
        let payload: [String: Any] = [
            "data": [
                "Image",
                filePayload,
                NSNull(),
                taskType,
                category,
                mode,
                0.1,
                0.9,
                20,
                shortSize,
                NSNull(),
                4,
            ],
        ]

        var start = URLRequest(url: URL(string: "\(hfSpaceBase)/gradio_api/call/run_inference")!)
        start.httpMethod = "POST"
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: payload)
        start.timeoutInterval = 30

        let (startData, _) = try await session.data(for: start)
        guard let startJSON = try JSONSerialization.jsonObject(with: startData) as? [String: Any],
              let eventId = startJSON["event_id"] as? String else {
            throw LocateAnythingVisionError.invalidResponse
        }

        var poll = URLRequest(url: URL(string: "\(hfSpaceBase)/gradio_api/call/run_inference/\(eventId)")!)
        poll.httpMethod = "GET"
        poll.timeoutInterval = 90

        let (pollData, _) = try await session.data(for: poll)
        let pollText = String(data: pollData, encoding: .utf8) ?? ""
        return try parseHFGradioSSE(pollText)
    }

    private func parseHFGradioSSE(_ sse: String) throws -> String {
        for line in sse.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("data: ") {
                let jsonPart = String(s.dropFirst(6))
                guard let data = jsonPart.data(using: .utf8),
                      let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
                      arr.count >= 3,
                      let meta = arr[2] as? [String: Any] else { continue }

                if let err = meta["error"] as? String, !err.isEmpty {
                    throw LocateAnythingVisionError.serviceUnavailable(err)
                }
                if let answer = meta["answer"] as? String, !answer.isEmpty {
                    return answer
                }
                if let raw = meta["raw_answer"] as? String, !raw.isEmpty {
                    return raw
                }
                if let response = meta["response"] as? String, !response.isEmpty {
                    return response
                }
            }
        }
        throw LocateAnythingVisionError.invalidResponse
    }

    // MARK: - On-device assist (instant fallback)

    private func analyzeOnDevice(
        image: UIImage,
        frameSize: CGSize,
        countryHint: String
    ) async -> CosmosVisionAnalysisResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var objects: [CosmosDetectedObject] = []
                var plate: String?
                var plateConf: Double?

                if let cg = image.cgImage {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .fast
                    request.usesLanguageCorrection = true
                    let handler = VNImageRequestHandler(cgImage: cg, orientation: .right, options: [:])
                    try? handler.perform([request])
                    let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
                    for o in obs.prefix(12) {
                        guard let text = o.topCandidates(1).first?.string else { continue }
                        let bb = o.boundingBox
                        let rect = CGRect(
                            x: bb.origin.x,
                            y: 1 - bb.origin.y - bb.height,
                            width: bb.width,
                            height: bb.height
                        )
                        let conf = Double(o.confidence)
                        objects.append(CosmosDetectedObject(label: "text", confidence: conf, rect: rect))
                        if plate == nil, let p = Self.extractPlate(from: text, countryHint: countryHint) {
                            plate = p
                            plateConf = conf
                        }
                    }
                }

                let result = CosmosVisionAnalysisResult(
                    objects: objects,
                    licensePlate: plate,
                    plateConfidence: plateConf,
                    vehicleDescription: objects.isEmpty ? nil : "On-device OCR assist",
                    summary: plate.map { "Plate: \($0)" } ?? "On-device text scan",
                    providerLabel: "LocateAnything · On-Device Assist",
                    frameSize: frameSize
                )
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Parsing LocateAnything answer

    private func mergeAnswers(
        detectAnswer: String,
        textAnswer: String,
        frameSize: CGSize,
        countryHint: String,
        provider: String
    ) -> CosmosVisionAnalysisResult {
        let combined = "\(detectAnswer)\n\(textAnswer)"
        var objects = Self.parseBoxes(from: combined, frameSize: frameSize)
        if objects.isEmpty {
            objects = Self.parseBoxes(from: combined, frameSize: frameSize, assumeXYXY: true)
        }

        let plate = Self.extractPlate(from: combined, countryHint: countryHint)
            ?? objects.compactMap { Self.extractPlate(from: $0.label, countryHint: countryHint) }.first

        let vehicle = objects.first {
            let l = $0.label.lowercased()
            return l.contains("car") || l.contains("truck") || l.contains("van") || l.contains("vehicle")
        }?.label

        return CosmosVisionAnalysisResult(
            objects: objects,
            licensePlate: plate,
            plateConfidence: plate == nil ? nil : 0.88,
            vehicleDescription: vehicle,
            summary: plate.map { "Plate detected: \($0)" } ?? "\(objects.count) objects located",
            providerLabel: provider,
            frameSize: frameSize
        )
    }

    static func parseBoxes(from answer: String, frameSize: CGSize, assumeXYXY: Bool = true) -> [CosmosDetectedObject] {
        let pattern = #"<box><(\d+)><(\d+)><(\d+)><(\d+)></box>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = answer as NSString
        let matches = regex.matches(in: answer, range: NSRange(location: 0, length: ns.length))
        var objects: [CosmosDetectedObject] = []

        for (idx, m) in matches.enumerated() {
            guard m.numberOfRanges == 5 else { continue }
            let x1 = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let y1 = Double(ns.substring(with: m.range(at: 2))) ?? 0
            let x2 = Double(ns.substring(with: m.range(at: 3))) ?? 0
            let y2 = Double(ns.substring(with: m.range(at: 4))) ?? 0

            let rect: CGRect
            if assumeXYXY {
                rect = CGRect(
                    x: min(x1, x2) / 1000,
                    y: min(y1, y2) / 1000,
                    width: abs(x2 - x1) / 1000,
                    height: abs(y2 - y1) / 1000
                )
            } else {
                rect = CGRect(x: x1 / 1000, y: y1 / 1000, width: x2 / 1000, height: y2 / 1000)
            }

            let label = labelBeforeBox(in: answer, boxRange: m.range, fallbackIndex: idx)
            objects.append(CosmosDetectedObject(label: label, confidence: 0.9, rect: rect))
        }
        return objects
    }

    private static func labelBeforeBox(in answer: String, boxRange: NSRange, fallbackIndex: Int) -> String {
        let prefix = (answer as NSString).substring(to: boxRange.location)
        let tokens = prefix
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { $0.count > 1 && $0.lowercased() != "locate" }

        if let last = tokens.last, last.count <= 40 {
            return last
        }
        return "object \(fallbackIndex + 1)"
    }

    static func extractPlate(from text: String, countryHint: String) -> String? {
        let upper = text.uppercased()
        let patterns: [String]
        if countryHint == "DE" {
            patterns = [#"\b[A-ZÄÖÜ]{1,3}\s?[A-Z]{1,2}\s?\d{1,4}\b"#, #"\b[A-Z]{1,3}[A-Z]{1,2}\d{1,4}\b"#]
        } else if countryHint == "CH" {
            patterns = [#"\b[A-Z]{2}\s?\d{1,6}\b"#]
        } else {
            patterns = [#"\b[A-Z]{2}\s?\d{1,6}\b"#, #"\b[A-ZÄÖÜ]{1,3}\s?[A-Z]{1,2}\s?\d{1,4}\b"#]
        }
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p),
               let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
               let range = Range(m.range, in: upper) {
                return String(upper[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func detectAnswerString(_ json: [String: Any]) -> String {
        if let answer = json["answer"] as? String { return answer }
        if let result = json["result"] as? [String: Any], let answer = result["answer"] as? String { return answer }
        return ""
    }

    private func shouldTryLocal() -> Bool {
#if targetEnvironment(simulator)
        return localReachable != false
#else
        return false
#endif
    }

    // MARK: - Frame prep

    static func prepareFrame(_ image: UIImage, maxLongEdge: CGFloat, jpegQuality: CGFloat) -> (jpeg: Data?, frameSize: CGSize) {
        let normalized = image.normalizedOrientation()
        let w = normalized.size.width
        let h = normalized.size.height
        guard w > 0, h > 0 else { return (nil, .zero) }

        let long = max(w, h)
        let scale = min(1, maxLongEdge / long)
        let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())

        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }
        return (scaled.jpegData(compressionQuality: jpegQuality), target)
    }
}

typealias NvidiaCosmosVisionService = LocateAnythingVisionService

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
