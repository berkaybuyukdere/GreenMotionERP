import Foundation

/// Centralized, non-breaking runtime flags for performance optimizations.
/// Defaults are conservative and can be overridden via UserDefaults.
enum OptimizationFeatureFlags {
    private enum Keys {
        static let listenerScopeV2 = "opt.listenerScopeV2.enabled"
        static let detailMemoV2 = "opt.detailMemoV2.enabled"
        static let operationsMemoV2 = "opt.operationsMemoV2.enabled"
        static let mediaPipelineV2 = "opt.mediaPipelineV2.enabled"
        static let pdfPipelineV2 = "opt.pdfPipelineV2.enabled"
        static let enableScopedWorkScheduleQuery = "opt.workSchedules.scopedQuery.enabled"
    }

    private static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    static var listenerScopeV2: Bool { bool(Keys.listenerScopeV2, default: true) }
    static var detailMemoV2: Bool { bool(Keys.detailMemoV2, default: true) }
    static var operationsMemoV2: Bool { bool(Keys.operationsMemoV2, default: true) }
    static var mediaPipelineV2: Bool { bool(Keys.mediaPipelineV2, default: true) }
    static var pdfPipelineV2: Bool { bool(Keys.pdfPipelineV2, default: true) }
    static var enableScopedWorkScheduleQuery: Bool { bool(Keys.enableScopedWorkScheduleQuery, default: true) }

    static func set(_ key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum FranchiseCapabilityMatrix {
    static func isTurkey(franchiseId: String) -> Bool {
        franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("TR")
    }

    static func isGermany(franchiseId: String) -> Bool {
        franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("DE")
    }

    /// Operations and TR-only (parked / waiting) checkout & return surfaces.
    static func operationsEnabled(franchiseId: String) -> Bool {
        isTurkey(franchiseId: franchiseId)
    }

    /// Matches `ExitIslemView` / `IadeIslemView`: service franchise, profile franchise, or `countryCode` TR.
    static func isTurkeyFranchiseContext(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        let s = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("TR") { return true }
        guard let p = userProfile else { return false }
        let pid = p.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if pid.hasPrefix("TR") { return true }
        let cc = p.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cc == "TR"
    }

    /// Session-wide TR product surface (Operations hub, office ops/returns, parked checkout aggregation, TR-only handover).
    static func operationsEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }
}
