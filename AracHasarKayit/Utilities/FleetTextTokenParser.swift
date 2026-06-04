import Foundation

enum FleetTextTokenKind: Equatable {
    case plain(String)
    case resCode(String)
    case plate(String)
}

struct FleetActiveToken {
    let prefix: String
    let range: NSRange
}

enum FleetTextTokenParser {
    private static let resPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(RES-?\d{3,8})\b"#,
        options: []
    )

    private static let platePattern = try! NSRegularExpression(
        pattern: #"\b([A-Z]{1,3}[-\s]?[A-Z0-9]{2,8})\b"#,
        options: []
    )

    private static let activeWordPattern = try! NSRegularExpression(
        pattern: #"(?:^|\s)([A-Za-z]{1,3}[-]?\d{0,8}|[Rr][Ee][Ss]-?\d{0,8})$"#,
        options: []
    )

    static func tokenize(_ text: String, knownPlates: Set<String>) -> [FleetTextTokenKind] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var matches: [(range: NSRange, kind: FleetTextTokenKind)] = []

        for match in resPattern.matches(in: text, range: fullRange) {
            let raw = ns.substring(with: match.range(at: 1))
            let canonical = TrafficAccidentContract.canonicalRES(from: raw)
            matches.append((match.range, .resCode(canonical)))
        }

        for match in platePattern.matches(in: text, range: fullRange) {
            let raw = ns.substring(with: match.range(at: 1))
            let normalized = normalizePlate(raw)
            guard normalized.count >= 4 else { continue }
            if knownPlates.contains(normalized) {
                matches.append((match.range, .plate(normalized)))
            }
        }

        matches.sort { $0.range.location < $1.range.location }

        var result: [FleetTextTokenKind] = []
        var cursor = 0
        for item in matches {
            guard item.range.location >= cursor else { continue }
            if item.range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: item.range.location - cursor))
                result.append(.plain(plain))
            }
            result.append(item.kind)
            cursor = item.range.location + item.range.length
        }
        if cursor < ns.length {
            result.append(.plain(ns.substring(from: cursor)))
        }
        if result.isEmpty, !text.isEmpty {
            result = [.plain(text)]
        }
        return result
    }

    static func normalizePlate(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    static func knownPlates(from vehicles: [Arac]) -> Set<String> {
        Set(vehicles.map { normalizePlate($0.plaka) }.filter { !$0.isEmpty })
    }

    static func activeToken(in text: String) -> FleetActiveToken? {
        guard let match = activeWordPattern.matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)).last else {
            return nil
        }
        let prefix = (text as NSString).substring(with: match.range(at: 1))
        guard !prefix.isEmpty else { return nil }
        return FleetActiveToken(prefix: prefix, range: match.range(at: 1))
    }

    static func looksLikePlatePrefix(_ prefix: String) -> Bool {
        let upper = prefix.uppercased()
        guard !upper.isEmpty else { return false }
        let letters = upper.prefix(while: { $0.isLetter })
        let digits = upper.dropFirst(letters.count).prefix(while: { $0.isNumber })
        return letters.count >= 1 && letters.count <= 3 && (digits.count <= 8)
    }

    static func looksLikeRESPrefix(_ prefix: String) -> Bool {
        let upper = prefix.uppercased().replacingOccurrences(of: "-", with: "")
        return upper.hasPrefix("RES")
    }

    static func plateSuggestions(prefix: String, vehicles: [Arac], limit: Int = 8) -> [String] {
        let needle = normalizePlate(prefix)
        guard needle.count >= 1 else { return [] }
        var seen = Set<String>()
        var results: [String] = []
        for arac in vehicles {
            let normalized = normalizePlate(arac.plaka)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            let matches = normalized.hasPrefix(needle)
                || normalizePlate(arac.plakaFormatli).hasPrefix(needle)
            guard matches else { continue }
            seen.insert(normalized)
            results.append(normalized)
            if results.count >= limit { break }
        }
        return results.sorted()
    }

    static func resSuggestions(prefix: String, vehicles: [Arac], limit: Int = 8) -> [String] {
        let upper = prefix.uppercased().replacingOccurrences(of: "-", with: "")
        let digits = upper.replacingOccurrences(of: "RES", with: "")
        var seen = Set<String>()
        var results: [String] = []
        for arac in vehicles {
            for hasar in arac.hasarKayitlari {
                let code = TrafficAccidentContract.canonicalRES(from: hasar.resKodu)
                guard !code.isEmpty else { continue }
                let compact = code.replacingOccurrences(of: "-", with: "")
                let matches: Bool
                if digits.isEmpty {
                    matches = compact.hasPrefix("RES")
                } else {
                    matches = compact.uppercased().contains(digits) || code.uppercased().hasPrefix(upper)
                }
                guard matches, !seen.contains(code) else { continue }
                seen.insert(code)
                results.append(code)
                if results.count >= limit { break }
            }
            if results.count >= limit { break }
        }
        return results.sorted()
    }
}
