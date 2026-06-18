import Foundation

enum WheelSysResCode {
    static func isReservationCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: #"^RES[-\s]?\d+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func normalizedReservationCode(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isReservationCode(trimmed) ? trimmed : nil
    }
}
