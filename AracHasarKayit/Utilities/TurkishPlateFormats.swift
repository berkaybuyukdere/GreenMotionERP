//
//  TurkishPlateFormats.swift
//  AracHasarKayit
//
//  Türkiye plaka kuralları (01–81 il kodu + 1–3 harf + 2–4 rakam).
//  Sadece franchise / ülke `tr` için kullanılır; CH, DE vb. etkilenmez.
//

import Foundation

enum TurkishPlateFormats {
    
    /// Boşluksuz doğrulama — üç yakalama grubu: il, harfler, rakamlar.
    private static let validationPattern = "^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})([0-9]{2,4})$"
    
    /// `Country.platePattern` ile uyumlu dışa açık özet (dokümantasyon / eşleştirme).
    static var compactRegexDocumentation: String { validationPattern }
    
    private static var validationRegex: NSRegularExpression? {
        try? NSRegularExpression(pattern: validationPattern, options: [])
    }
    
    private static var searchRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: "(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}[0-9]{2,4}",
            options: []
        )
    }
    
    // MARK: - Validation
    
    static func normalizeCompact(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    }
    
    static func isValidCompact(_ compact: String) -> Bool {
        let s = normalizeCompact(compact)
        guard !s.isEmpty else { return false }
        guard let regex = validationRegex else { return false }
        let range = NSRange(location: 0, length: s.utf16.count)
        return regex.firstMatch(in: s, range: range) != nil
    }
    
    /// Görüntü: `34 FC 6302`
    static func formatForDisplay(_ raw: String) -> String {
        let c = normalizeCompact(raw)
        guard let parts = parseComponents(compact: c) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return "\(parts.il) \(parts.letters) \(parts.digits)"
    }
    
    struct Components {
        let il: String
        let letters: String
        let digits: String
    }
    
    static func parseComponents(compact: String) -> Components? {
        let c = normalizeCompact(compact)
        guard let regex = validationRegex else { return nil }
        let range = NSRange(location: 0, length: c.utf16.count)
        guard let match = regex.firstMatch(in: c, range: range),
              match.numberOfRanges >= 4,
              let r1 = Range(match.range(at: 1), in: c),
              let r2 = Range(match.range(at: 2), in: c),
              let r3 = Range(match.range(at: 3), in: c) else { return nil }
        return Components(il: String(c[r1]), letters: String(c[r2]), digits: String(c[r3]))
    }
    
    // MARK: - OCR: Vision metinlerinden en iyi aday
    
    static func bestPlate(from texts: [String]) -> String? {
        var pool: [String] = []
        for raw in texts {
            let n = normalizeCompact(raw)
            if !n.isEmpty { pool.append(n) }
            for v in ocrVariations(n) where !v.isEmpty {
                pool.append(v)
            }
        }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0).inserted }
        
        for candidate in pool {
            if isValidCompact(candidate) { return normalizeCompact(candidate) }
            if let extracted = extractFirstMatch(in: candidate) { return extracted }
            for v in ocrVariations(candidate) {
                if isValidCompact(v) { return normalizeCompact(v) }
                if let extracted = extractFirstMatch(in: v) { return extracted }
            }
        }
        return nil
    }
    
    private static func extractFirstMatch(in compact: String) -> String? {
        let s = normalizeCompact(compact)
        guard let regex = searchRegex, s.count >= 5 else { return nil }
        let range = NSRange(location: 0, length: s.utf16.count)
        guard let match = regex.firstMatch(in: s, range: range),
              let r = Range(match.range, in: s) else { return nil }
        let sub = String(s[r])
        return isValidCompact(sub) ? normalizeCompact(sub) : nil
    }
    
    private static func ocrVariations(_ text: String) -> [String] {
        var variations: [String] = []
        let pairs: [(String, String)] = [
            ("O", "0"), ("0", "O"),
            ("I", "1"), ("1", "I"),
            ("S", "5"), ("5", "S"),
            ("B", "8"), ("8", "B"),
            ("Z", "2"), ("2", "Z")
        ]
        for (a, b) in pairs where text.contains(a) {
            variations.append(text.replacingOccurrences(of: a, with: b))
        }
        return variations
    }
}
