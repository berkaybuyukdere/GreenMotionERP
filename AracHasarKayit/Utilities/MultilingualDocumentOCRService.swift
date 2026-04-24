import Foundation
import UIKit
import Vision

struct OCRNameExtractionResult {
    let firstName: String
    let lastName: String
    let fullNameRaw: String
    let fullText: String
}

final class MultilingualDocumentOCRService {
    static let shared = MultilingualDocumentOCRService()
    private init() {}

    func extractName(from image: UIImage, completion: @escaping (OCRNameExtractionResult?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let fullText = lines.joined(separator: "\n")
            let rawName = Self.pickBestNameLine(from: lines)
            let parsed = Self.splitName(rawName)
            completion(OCRNameExtractionResult(
                firstName: parsed.firstName,
                lastName: parsed.lastName,
                fullNameRaw: rawName,
                fullText: fullText
            ))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["tr-TR", "en-US", "de-DE", "fr-FR", "es-ES", "it-IT"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    /// Full-page OCR (invoices, spreadsheets, printed text) using accurate recognition.
    func recognizeFullDocumentText(from image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }
            let lines = observations
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            completion(lines.joined(separator: "\n"))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "tr-TR", "it-IT", "es-ES"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private static func pickBestNameLine(from lines: [String]) -> String {
        let normalizedLines = lines.map {
            $0.replacingOccurrences(of: ":", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Swiss ID calibration:
        // On this card, label lines are multilingual and the actual value is usually in the next line.
        // We first locate the anchor labels, then read the nearest non-label value line.
        for (index, line) in normalizedLines.enumerated() {
            let l = normalize(line)
            if l.contains("name nom cognome num surname"),
               let value = nearestValueLine(from: normalizedLines, after: index) {
                return value
            }
            if l.contains("given names") || l.contains("vorname") || l.contains("prenom"),
               let given = nearestValueLine(from: normalizedLines, after: index) {
                return given
            }
        }

        let preferredKeys = [
            "name surname", "surname name", "full name",
            "first name", "given name", "name", "soyad", "ad soyad",
            "nachname", "vorname", "nom", "apellido"
        ]
        for key in preferredKeys {
            if let idx = normalizedLines.firstIndex(where: { normalize($0).contains(key) }),
               let value = nearestValueLine(from: normalizedLines, after: idx) {
                return value
            }
        }

        // Fallback: pick the first line that looks like a person's name and not a metadata/label line.
        return normalizedLines.first(where: looksLikeNameValueLine) ?? ""
    }

    private static func splitName(_ line: String) -> (firstName: String, lastName: String) {
        let cleaned = line
            .replacingOccurrences(of: "Name Surname", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Surname Name", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "First Name", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Given Name", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Last Name", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Name", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Soyad", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Ad", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { return ("", "") }
        if parts.count == 1 { return (parts[0], "") }
        return (parts.dropLast().joined(separator: " "), parts.last ?? "")
    }

    private static func normalize(_ raw: String) -> String {
        raw.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private static func nearestValueLine(from lines: [String], after anchorIndex: Int) -> String? {
        guard anchorIndex + 1 < lines.count else { return nil }
        for idx in (anchorIndex + 1)..<min(lines.count, anchorIndex + 6) {
            let candidate = lines[idx]
            if looksLikeNameValueLine(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func looksLikeNameValueLine(_ line: String) -> Bool {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let lower = normalize(cleaned)

        // Reject multilingual label lines and metadata lines.
        let blockedTokens = [
            "identity card", "identitatskarte", "carte d'identite",
            "name nom cognome", "given names", "date of birth", "date of expiry",
            "nationality", "sex", "sesso", "geschlecht", "natio", "che"
        ]
        if blockedTokens.contains(where: { lower.contains($0) }) { return false }
        if cleaned.contains("•") { return false }
        if cleaned.rangeOfCharacter(from: .decimalDigits) != nil { return false }

        let parts = cleaned.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 1, parts.count <= 5 else { return false }
        return cleaned.count >= 2
    }
}

