import Foundation

/// Centralized, non-breaking runtime flags for performance optimizations.
/// Defaults are conservative and can be overridden via UserDefaults.
enum OptimizationFeatureFlags {
    private enum Keys {
        static let listenerScopeV2 = "opt.listenerScopeV2.enabled"
        static let detailMemoV2 = "opt.detailMemoV2.enabled"
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

    static func isUK(franchiseId: String) -> Bool {
        let id = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return id.hasPrefix("UK") || id.hasPrefix("GB")
    }

    /// CH + DE + UK share the Swiss HTML-style PDF renderer (DE: 4 photos on first photo page).
    static func swissStyleReportPdfEnabled(franchiseId: String) -> Bool {
        isSwitzerland(franchiseId: franchiseId) || isGermany(franchiseId: franchiseId) || isUK(franchiseId: franchiseId)
    }

    static func isSwitzerland(franchiseId: String) -> Bool {
        franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("CH")
    }

    /// Switzerland franchise path / profile (not Germany). Used for CH-only products such as traffic accident contracts.
    static func isSwitzerlandFranchiseContext(serviceFranchiseId: String, userProfile: UserProfile?, fallbackCountryCode: String) -> Bool {
        let s = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("CH") { return true }
        guard let p = userProfile else {
            return fallbackCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CH"
        }
        let pid = p.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if pid.hasPrefix("CH") { return true }
        let cc = p.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cc == "CH" || fallbackCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CH"
    }

    /// Operations and TR-only (parked / waiting) checkout & return surfaces.
    static func operationsEnabled(franchiseId: String) -> Bool {
        isTurkey(franchiseId: franchiseId)
    }

    /// Parked checkout list / dashboard tile — CH, DE, UK, TR (session franchise only).
    static func parkedCheckoutsEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: ""
        ) || isGermanyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isUKFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }

    /// TR capabilities are franchise-scoped (not user country-scoped).
    /// This prevents CH sessions from accidentally enabling TR-only flows
    /// (e.g. auto planned-return creation / waiting rows) for staff whose
    /// profile countryCode happens to be TR.
    static func isTurkeyFranchiseContext(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        let s = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("TR") { return true }
        guard let p = userProfile else { return false }
        let pid = p.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return pid.hasPrefix("TR")
    }

    /// Germany franchise-scoped context (mirrors the TR scoping rule).
    static func isGermanyFranchiseContext(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        let s = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("DE") { return true }
        guard let p = userProfile else { return false }
        let pid = p.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return pid.hasPrefix("DE")
    }

    /// United Kingdom franchise-scoped context (GB document IDs are treated as UK).
    static func isUKFranchiseContext(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        let s = serviceFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("UK") || s.hasPrefix("GB") { return true }
        guard let p = userProfile else { return false }
        let pid = p.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if pid.hasPrefix("UK") || pid.hasPrefix("GB") { return true }
        let cc = p.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cc == "UK" || cc == "GB"
    }

    /// Customer QR self-fill (return.html / checkout.html) — any valid franchise document ID.
    static func customerSelfFillQrEnabled(franchiseId: String) -> Bool {
        let id = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard id.count >= 2, id.count <= 64 else { return false }
        return id.range(of: "^[A-Z0-9][A-Z0-9_-]*[A-Z0-9]$|^[A-Z0-9]{1,2}$", options: .regularExpression) != nil
    }

    /// Session-wide TR product surface (Operations hub, parked / waiting aggregation, TR-only handover, return-PDF email tracking).
    static func operationsEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }

    /// Fuel / POS / expense office flows: Firestore listeners, Report tile, dashboard shortcut — TR, CH, DE, UK franchises.
    static func officeOperationsProductEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isSwitzerlandFranchiseContext(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: ""
            ) ||
            isGermanyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isUKFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }

    /// Office customer returns — Firestore rules allow TR + CH scoped paths only.
    static func officeReturnsProductEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isSwitzerlandFranchiseContext(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: ""
            )
    }

    /// Police reports + traffic accident contracts — Switzerland franchise only.
    static func policeReportsAndTrafficContractsEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?
    ) -> Bool {
        isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: ""
        )
    }

    /// Customer check-out confirmation email — Turkey and Germany franchises
    /// (both have franchise-scoped SMTP configured). The Cloud Function applies
    /// the same allow-list server-side.
    static func checkoutCustomerEmailEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isGermanyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }

    /// Return confirmation email — TR, DE, and CH (CH uses `smtpConfigurations/CH` via Cloud Functions).
    static func returnCustomerEmailEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        checkoutCustomerEmailEnabledForSession(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile) ||
            isSwitzerlandFranchiseContext(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: ""
            )
    }

    /// In-app burst/serial camera for checkout & return — Turkey franchises only.
    static func serialPhotoCaptureEnabledForSession(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        isTurkeyFranchiseContext(serviceFranchiseId: serviceFranchiseId, userProfile: userProfile)
    }

    /// Shuttle reports + live map entry — CH franchises; staff+ may add records, admin+ full access.
    static func shuttleModuleEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        guard isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        ) else { return false }
        return userProfile?.canAddShuttleRecords == true
    }

    /// Navbar Shuttle Map tab disabled — map opens from Reports → Shuttle toolbar.
    static func shuttleMapTabEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        _ = serviceFranchiseId
        _ = userProfile
        _ = fallbackCountryCode
        return false
    }

    /// Switzerland admin analytics tab (Panel) — franchise admin and platform elevated roles only.
    static func chAdminPanelTabEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        guard isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        ) else { return false }
        return userProfile?.canAccessFranchiseAdminPanel == true
    }

    /// WheelSys hub tab — CH franchises only; admin + platform elevated roles (temporary gate).
    static func chOpsJournalTabEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        guard userProfile?.role != .garage else { return false }
        guard isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        ) else { return false }
        return userProfile?.canAccessFranchiseAdminPanel == true
    }

    /// Franchise document library (Reports → Files). Switzerland franchises only — mirrors web ERP Files.
    static func fileLibraryEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        )
    }

    /// Reports → Announcements + team chat. Switzerland franchises only.
    static func announcementsEnabledForSession(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        )
    }

    /// Garage portal Semes invoices (read-only). Switzerland + garage role.
    static func garageSemesPortalEnabled(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        guard userProfile?.isGaragePortalUser == true else { return false }
        return isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        )
    }
}
