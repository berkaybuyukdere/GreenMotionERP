import Foundation

/// Single source of truth for plate normalization across Firebase `araclar`,
/// WheelSys fleet chart, and operation matching.
///
/// Swiss / EU plates appear in many display forms — `ZH123123`, `ZH 123123`,
/// `ZH 123 123`, `ZH-123123` — but represent the same vehicle. Matching must
/// ignore separators and case while preserving the letter+digit identity.
///
/// Mirror of `functions/wheelsys/fleetChart.js` `normalizePlate` / `platesEqual`.
enum WheelSysPlateNormalizer {

    /// Canonical, comparison-safe plate key.
    /// NFKC normalize -> uppercase -> strip everything except A-Z and 0-9.
    static func canonical(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let folded = raw.precomposedStringWithCompatibilityMapping.uppercased()
        let scalars = folded.unicodeScalars.filter { scalar in
            (scalar.value >= 65 && scalar.value <= 90) ||   // A-Z
            (scalar.value >= 48 && scalar.value <= 57)       // 0-9
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// True when two plates refer to the same vehicle regardless of formatting.
    static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
        let a = canonical(lhs)
        let b = canonical(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b
    }

    /// Human-friendly display form: 2-letter canton prefix + spaced digits.
    /// Falls back to the trimmed original when the pattern does not match.
    static func display(_ raw: String?) -> String {
        let key = canonical(raw)
        guard key.count >= 3 else {
            return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let letters = key.prefix { $0.isLetter }
        let digits = key.drop { $0.isLetter }
        guard letters.count == 2, !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
            return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key
        }
        return "\(letters) \(digits)"
    }
}
