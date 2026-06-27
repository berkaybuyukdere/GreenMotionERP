import Foundation

/// Maps raw WheelSys / integration errors to localized user-facing copy.
enum WheelSysUserFacingError {
    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let desc = localized.errorDescription,
           !desc.isEmpty,
           !looksLikeRawWheelSysPayload(desc) {
            return desc
        }
        return message(forRaw: error.localizedDescription)
    }

    static func isSessionExpiredRaw(_ raw: String) -> Bool {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return false }
        if upper.contains("WHEELSYS_SESSION_EXPIRED")
            || upper.contains("WHEELSYS_SESSION_MISSING") {
            return true
        }
        if upper.contains("MISSING WHEELSYS SESSION")
            || upper.contains("NO ACTIVE WHEELSYS SESSION") {
            return true
        }
        if upper.contains("SESSION EXPIRED") || upper.contains("SESSION MISSING") {
            return true
        }
        if upper.contains("HTTP 401") {
            return true
        }
        if upper.contains("HTTP 403")
            && (upper.contains("SESSION") || upper.contains("LOGIN") || upper.contains("WHEELSYS")) {
            return true
        }
        return false
    }

    /// True when a backend/journal failure is operational — not an auth expiry.
    static func isOperationalFailure(_ raw: String) -> Bool {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.isEmpty { return false }
        return upper.contains("FLEET CHART")
            || upper.contains("JOURNAL")
            || upper.contains("PARSE FAILED")
            || upper == "INTERNAL"
            || upper.hasPrefix("INTERNAL ")
    }

    static func isTransientServiceError(_ raw: String) -> Bool {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return false }
        if upper == "UNAVAILABLE" || upper.contains(" UNAVAILABLE") || upper.hasPrefix("UNAVAILABLE ") {
            return true
        }
        if upper.contains("RESOURCE_EXHAUSTED") || upper.contains("DEADLINE EXCEEDED") {
            return true
        }
        if upper.contains("NETWORK") || upper.contains("TIMEOUT") || upper.contains("CONNECTION") {
            return true
        }
        return false
    }

    static func message(forRaw raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "wheelsys_fleet.unknown_error".localized
        }
        let upper = trimmed.uppercased()

        if isTransientServiceError(trimmed) {
            return "wheelsys_fleet.service_unavailable".localized
        }
        if upper == "INTERNAL" || upper.hasPrefix("INTERNAL ") || upper.hasSuffix(" INTERNAL") {
            return "wheelsys_fleet.unknown_error".localized
        }
        if isSessionExpiredRaw(trimmed) {
            return "wheelsys_fleet.session_expired".localized
        }
        if upper.contains("COULD NOT RESOLVE WHEELSYS VEHICLE") {
            return "wheelsys.damage_history.vehicle_not_found".localized
        }
        if upper.contains("RENTAL OVERLAP") {
            return "wheelsys_ntr.rental_overlap".localized
        }
        if upper.contains("RECORD WAS CHANGED") {
            return "wheelsys.error.record_changed".localized
        }
        if upper.contains("PREVIEW TIMEOUT") || upper.contains("TIMED OUT AFTER 15") {
            return "wheelsys.return.preview_timeout".localized
        }
        if upper.contains("CANNOT BE BEFORE CHECKOUT")
            || upper.contains("BEFORE CHECKOUT TIME")
            || upper.contains("RETURN TIME CANNOT") {
            return "wheelsys.error.return_before_checkout".localized
        }
        if upper.contains("TIMEZONE")
            || upper.contains("TIME ZONE")
            || upper.contains("INVALID DATE")
            || upper.contains("DATE/TIME")
            || upper.contains("ZURICH") && upper.contains("INVALID") {
            return "wheelsys.error.time_invalid".localized
        }
        if upper.contains("TOISOSTRING") || upper.contains("UTC CONVERSION") {
            return "wheelsys.error.time_invalid".localized
        }

        return trimmed
    }

    private static func looksLikeRawWheelSysPayload(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("RENTAL OVERLAP")
            || upper.contains("RECORD WAS CHANGED")
            || upper.contains("HTTP ")
            || upper.contains("JAVASCRIPT ERROR")
            || upper.contains("PARSE FAILED")
    }
}
