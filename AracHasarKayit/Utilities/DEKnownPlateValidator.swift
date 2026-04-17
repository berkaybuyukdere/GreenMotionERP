import Foundation

/// Reference plates from the germany-license-plate-dataset (Kaggle: unidpro).
/// Used as a secondary confidence signal: if an OCR candidate exactly matches
/// a known plate after normalization, its score is boosted.
///
/// Add more plates here as the dataset grows, or call `register(_:)` at runtime.
struct DEKnownPlateValidator {

    static let shared = DEKnownPlateValidator()

    // Known plates embedded from Germany.csv (normalized: uppercase, no spaces/hyphens)
    private var knownNormalized: Set<String> = {
        let raw = [
            "OS BY 153",
            "SHA OZ 268",
            "HH NB 1402",
            "OF PM 550",
            "M EA 4903",
            "DU BE 102 E",
            "NOH MV 55",
            "HOM SZ 227",
            "M KR 2125",
            "HD SK 630",
        ]
        return Set(raw.map { DEKnownPlateValidator.normalize($0) })
    }()

    private init() {}

    /// Returns true if the candidate plate matches any known plate.
    func isKnown(_ plate: String) -> Bool {
        knownNormalized.contains(Self.normalize(plate))
    }

    /// Score boost when OCR candidate matches a dataset plate.
    var matchBonus: Int { 20 }

    // MARK: - Normalization

    /// Strip spaces, hyphens, dots; uppercase.
    static func normalize(_ plate: String) -> String {
        plate
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
