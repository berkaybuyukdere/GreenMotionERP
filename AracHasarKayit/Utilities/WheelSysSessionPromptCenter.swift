import Foundation

extension Notification.Name {
    /// Posted when a WheelSys operation fails because the session cookie is missing or expired.
    static let wheelSysSessionRequired = Notification.Name("wheelSysSessionRequired")
    /// Posted after a fresh WheelSys login is saved successfully.
    static let wheelSysSessionRestored = Notification.Name("wheelSysSessionRestored")
}

/// Detects WheelSys session failures and broadcasts a global login prompt (ContentView sheet).
enum WheelSysSessionPromptCenter {
    private static var lastPromptAt: Date?
    private static var snoozedUntil: Date?
    private static let promptCooldown: TimeInterval = 120

    static func snoozePrompts(for seconds: TimeInterval = 900) {
        snoozedUntil = Date().addingTimeInterval(seconds)
    }

    static func resetSnooze() {
        snoozedUntil = nil
        lastPromptAt = nil
    }

    static func notifyIfSessionError(_ error: Error) {
        guard shouldPresentPrompt, wheelSysActiveForCurrentSession, isSessionError(error) else { return }
        postPrompt()
    }

    static func notifyIfSessionMessage(_ message: String) {
        guard shouldPresentPrompt, wheelSysActiveForCurrentSession, isSessionMessage(message) else { return }
        postPrompt()
    }

    private static var shouldPresentPrompt: Bool {
        if WheelSysCookieCache.hasUsableSession {
            return false
        }
        if let until = snoozedUntil, Date() < until { return false }
        if let last = lastPromptAt, Date().timeIntervalSince(last) < promptCooldown { return false }
        return true
    }

    private static func postPrompt() {
        lastPromptAt = Date()
        NotificationCenter.default.post(name: .wheelSysSessionRequired, object: nil)
    }

    private static var wheelSysActiveForCurrentSession: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: nil
        )
    }

    static func isSessionError(_ error: Error) -> Bool {
        if let op = error as? WheelSysVehicleDamageServiceError,
           case .operationFailed(let msg) = op {
            return isSessionExpiredRaw(msg)
        }
        if let op = error as? WheelSysCheckinServiceError,
           case .operationFailed(let msg) = op {
            return isSessionExpiredRaw(msg)
        }
        let userFacing = WheelSysUserFacingError.message(for: error)
        return isSessionMessage(userFacing)
    }

    private static func isSessionExpiredRaw(_ raw: String) -> Bool {
        WheelSysUserFacingError.isSessionExpiredRaw(raw)
    }

    static func isSessionMessage(_ message: String) -> Bool {
        let lower = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower.contains("wheelsys_session_expired") || lower.contains("wheelsys_session_missing") {
            return true
        }
        if lower.contains("missing wheelsys session") { return true }
        if lower.contains("session expired") || lower.contains("session missing") { return true }
        if lower.contains("oturum") && (lower.contains("sona") || lower.contains("süresi") || lower.contains("expired")) {
            return true
        }
        if lower.contains("sitzung") && lower.contains("abgelaufen") { return true }
        return false
    }
}
