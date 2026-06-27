import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import FirebaseCrashlytics

// MARK: - User Roles
enum UserRole: String, Codable, CaseIterable {
    case superadmin
    /// Cross-franchise operational access (same Firestore bypass and admin UI as superadmin).
    case globaladmin
    case admin
    case manager
    case staff
    case shuttle   // Same permissions as staff
    case viewer
    /// External service partner: only vehicles with `garageServiceJobs` targeting their linked `ServisFirma` id (`linkedGarageId` / `garageId` on user doc).
    case garage
}

enum TrialStatus: String, Codable, CaseIterable {
    case active
    case expired
    case converted
}

/// Unified roleScope (mirrors `users/{uid}.roleScope` on the server).
/// Backward compatible: when the doc has no `roleScope` we derive it from
/// `role` + `franchiseId` + `scopeLevel` + `franchiseMemberships` + `countryCode`.
enum RoleScopeLevel: String, Codable {
    case global
    case country
    case franchise
}

struct UserRoleScope: Codable, Equatable {
    var level: RoleScopeLevel
    /// ISO country code (empty for `level == .global`).
    var countryCode: String
    /// Explicit franchise list (empty + `.country` ⇒ entire country).
    var franchiseIds: [String]

    static let franchiseDefault = UserRoleScope(
        level: .franchise,
        countryCode: "",
        franchiseIds: []
    )
}

struct UserProfile: Codable {
    var uid: String
    var email: String
    var firstName: String
    var lastName: String
    /// In-app handle (`users.username`). Defaults to first name when unset; legacy `nickname` is read only for migration.
    var username: String? = nil
    /// `single` | `selected` | `country_all` — aligns with web `userAccess` / Firestore rules.
    var scopeLevel: String = "single"
    /// Franchise IDs the user may select at login (when `scopeLevel == "selected"`).
    var franchiseMemberships: [String: Bool]? = nil
    /// Preferred franchise when no login picker value is stored.
    var defaultFranchiseId: String? = nil
    var createdAt: Date
    var isDemoAccount: Bool = false  // Demo hesap mı?
    var parentUserId: String? = nil  // Ana kullanıcı ID (demo hesap ise)
    var demoExpiresAt: Date? = nil   // Demo bitiş tarihi
    var isTrialUser: Bool = false
    var trialStartedAt: Date? = nil
    var trialEndsAt: Date? = nil
    var trialStatus: TrialStatus = .active
    var convertedAt: Date? = nil
    var countryCode: String = "CH"   // Kullanıcının kayıtlı olduğu ülke kodu (varsayılan: İsviçre)
    var franchiseId: String = "CH"   // Kullanıcının franchise ID'si (varsayılan: Switzerland)
    var role: UserRole = .staff      // Kullanıcı rolü (varsayılan: staff)
    /// Firestore `linkedGarageId` or `garageId`: **ServisFirma.id** UUID string for `role == .garage` (which service company portal this login is for).
    var linkedGarageId: String? = nil
    var isActive: Bool = true        // Kullanıcı aktif mi?
    
    /// Firestore legacy field (kept for backward-compatible decoding).
    var legacyCrossFranchiseFlag: Bool = false
    /// Unified scope — preferred when present (parsed from Firestore `users.roleScope`).
    var roleScope: UserRoleScope? = nil
    
    var fullName: String {
        "\(firstName) \(lastName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Display name used across app UI (username, else first name, else full name / email).
    var displayName: String {
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u
        }
        let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fn.isEmpty {
            return fn
        }
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = emailTrimmed.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return emailTrimmed.isEmpty ? "User" : emailTrimmed
    }

    /// Username or real name for audit fields (e.g. traffic contracts); does **not** use email.
    var nameOrUsernameForAudit: String? {
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u
        }
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fn.isEmpty { return fn }
        return nil
    }
    
    /// Platform superadmin (`users.role == "superadmin"`).
    var isSuperAdmin: Bool {
        role == .superadmin
    }

    /// Global admin: all franchises (same app + rules treatment as superadmin).
    var isGlobalAdmin: Bool {
        role == .globaladmin
    }

    /// Unfiltered queries and elevated panels (superadmin or globaladmin).
    var isElevatedAdmin: Bool {
        isSuperAdmin || isGlobalAdmin
    }

    /// Live admin monitor, franchise user list, audit log, and clearing franchise activities (franchise `admin` or platform operators).
    var canAccessFranchiseAdminPanel: Bool {
        isElevatedAdmin || role == .admin
    }

    /// WheelSys journal / daily view ops (assign, return, pre-check-in) — all CH staff except garage/viewer.
    var canPerformWheelSysVehicleOps: Bool {
        switch role {
        case .staff, .shuttle, .manager, .admin, .superadmin, .globaladmin:
            return true
        case .viewer, .garage:
            return false
        }
    }

    /// Shuttle module visibility + record entry (CH daily shuttle reports).
    var canAccessShuttleModule: Bool {
        switch role {
        case .staff, .shuttle, .manager, .admin, .superadmin, .globaladmin:
            return true
        case .viewer, .garage:
            return false
        }
    }

    /// Shuttle record entry (pickup/dropoff) — staff tier and above.
    var canAddShuttleRecords: Bool {
        canAccessShuttleModule
    }

    /// Fleet category rename / delete / bulk vehicle removal (aligned with franchise manager tooling).
    var canManageVehicleCategories: Bool {
        role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    /// Announcements publish / edit / delete (manager tier and above).
    var canPublishAnnouncements: Bool {
        role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }
    
    /// Only global admins may operate cross-franchise from login picker context.
    var isCrossFranchisePlatformOperator: Bool {
        if case .globaladmin = role { return true }
        if let lvl = roleScope?.level, lvl == .global { return true }
        return false
    }

    /// Canonical resolved scope: prefers `roleScope` from Firestore, else derives
    /// from legacy `role`/`franchiseId`/`scopeLevel`/`franchiseMemberships`.
    /// Mirrors `green-motion-web/src/utilities/roleScope.js#resolveRoleScope`.
    var resolvedScope: UserRoleScope {
        if let scope = roleScope {
            return scope
        }
        if role == .globaladmin {
            return UserRoleScope(level: .global, countryCode: "", franchiseIds: [])
        }
        let cc = countryCode.uppercased()
        let primary = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let memIds: [String] = {
            guard let mem = franchiseMemberships else { return [] }
            return mem.compactMap { (k, v) -> String? in
                guard v else { return nil }
                let t = k.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return t.isEmpty ? nil : t
            }
        }()
        let lvl = scopeLevel.lowercased()
        if lvl == "country_all" {
            return UserRoleScope(level: .country, countryCode: cc, franchiseIds: [])
        }
        if lvl == "selected" {
            return UserRoleScope(
                level: .country,
                countryCode: cc,
                franchiseIds: memIds.isEmpty ? (primary.isEmpty ? [] : [primary]) : memIds
            )
        }
        return UserRoleScope(
            level: .franchise,
            countryCode: cc,
            franchiseIds: primary.isEmpty ? [] : [primary]
        )
    }

    /// Franchise IDs the user may select in the login branch picker.
    /// Returns `nil` for global admins or country-wide admins (caller must
    /// fetch the franchises collection filtered by `resolvedScope.countryCode`).
    var availableFranchiseIds: [String]? {
        let scope = resolvedScope
        switch scope.level {
        case .global:
            return nil
        case .country:
            return scope.franchiseIds.isEmpty ? nil : scope.franchiseIds
        case .franchise:
            return scope.franchiseIds
        }
    }

    /// Web `scopeLevel == single` or one franchise in roleScope — user must stay on assigned branch only.
    var isLockedToSingleFranchise: Bool {
        if isCrossFranchisePlatformOperator { return false }
        let lvl = scopeLevel.lowercased()
        if lvl == "country_all" { return false }
        if lvl == "selected" {
            let active = franchiseMemberships?.filter { $0.value }.count ?? 0
            return active <= 1
        }
        switch resolvedScope.level {
        case .global, .country:
            return false
        case .franchise:
            return true
        }
    }

    /// Assigned branch from Firestore (`franchiseId` / `defaultFranchiseId` / roleScope).
    func authoritativeFranchiseId() -> String {
        let memIds: [String] = franchiseMemberships?.compactMap { key, enabled -> String? in
            guard enabled else { return nil }
            let t = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return t.isEmpty ? nil : t
        } ?? []
        return LoginFranchiseCountryGuard.pickAuthoritativeFranchiseId(
            countryCode: countryCode,
            defaultFranchiseId: defaultFranchiseId,
            roleScopeFranchiseIds: resolvedScope.franchiseIds,
            membershipIds: memIds,
            primaryFranchiseId: franchiseId
        )
    }

    private func sessionFranchiseAllowed(_ franchiseId: String) -> Bool {
        if isCrossFranchisePlatformOperator { return true }
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !fid.isEmpty else { return false }
        let cc = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !cc.isEmpty {
            guard LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                franchiseId: fid,
                documentCountryCode: cc,
                selectedCountryCode: cc
            ) else { return false }
        }
        guard let allowed = availableFranchiseIds else { return true }
        return allowed.contains(fid)
    }

    /// Active `franchises/{id}` for reads/writes. Single-franchise users never inherit a stale login cache (e.g. CH).
    func resolvedFranchiseIdForDataAccess() -> String {
        if isLockedToSingleFranchise {
            return authoritativeFranchiseId()
        }

        let loginCC = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let sessionBranch = UserDefaults.standard.sessionLoginFranchiseId(preferredCountryCode: loginCC),
           sessionFranchiseAllowed(sessionBranch) {
            return sessionBranch
        }

        if isCrossFranchisePlatformOperator {
            if UserDefaults.standard.hasPersistedCountrySelection {
                return UserDefaults.standard.selectedCountry.countryCode.uppercased()
            }
            return franchiseId.uppercased()
        }

        let scope = resolvedScope
        if scope.level == .country && scope.franchiseIds.isEmpty {
            if let sessionBranch = UserDefaults.standard.sessionLoginFranchiseId(preferredCountryCode: loginCC),
               sessionFranchiseAllowed(sessionBranch) {
                return sessionBranch
            }
        }
        if scope.level == .country, !scope.franchiseIds.isEmpty {
            if let sessionBranch = UserDefaults.standard.sessionLoginFranchiseId(preferredCountryCode: loginCC),
               scope.franchiseIds.contains(sessionBranch) {
                return sessionBranch
            }
            if let def = defaultFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !def.isEmpty {
                return def.uppercased()
            }
            return scope.franchiseIds[0].uppercased()
        }

        return authoritativeFranchiseId()
    }
    
    var effectiveIsTrialUser: Bool {
        isTrialUser || isDemoAccount
    }
    
    var effectiveTrialEndsAt: Date? {
        trialEndsAt ?? demoExpiresAt
    }

    var isGaragePortalUser: Bool {
        role == .garage
    }
}

/// Outcome of an email/password sign-in attempt (single-session aware).
enum SignInResult {
    case success
    case failed
    /// Another device has an active session; user can confirm takeover.
    case activeSessionElsewhere
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var errorMessage: String?
    /// True while validating stored session on launch (avoids flashing Login before main UI).
    @Published private(set) var isRestoringSession = false
    
    private let db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var singleSessionListener: ListenerRegistration?
    private var tokenRefreshTimer: Timer?
    
    // Flag to prevent auth state listener from setting isAuthenticated during country validation
    private var isValidatingCountry = false
    private var validationTimeoutWork: DispatchWorkItem?
    /// While true, ignore auth listener for session / auth UI (email sign-in guard in progress).
    private var isSessionGuardPending = false
    private var localSessionId: String {
        let key = "localSessionId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
    
    init() {
        if Auth.auth().currentUser != nil {
            isRestoringSession = true
        }
        checkAuthStatus()
        setupAuthStateListener()
        setupTokenRefreshMonitoring()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
        singleSessionListener?.remove()
        tokenRefreshTimer?.invalidate()
    }
    
    func checkAuthStatus() {
        if AppSessionGate.requiresFreshLoginSelection {
            try? Auth.auth().signOut()
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringSession = false
                self?.isAuthenticated = false
                self?.currentUser = nil
                self?.userProfile = nil
            }
            return
        }

        guard let user = Auth.auth().currentUser else {
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringSession = false
            }
            return
        }

        guard UserDefaults.standard.hasPersistedCountrySelection else {
            LogManager.shared.warning("Session restore blocked: no country selected at login")
            try? Auth.auth().signOut()
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringSession = false
                self?.isAuthenticated = false
                self?.currentUser = nil
                self?.userProfile = nil
            }
            return
        }

        let savedCountry = UserDefaults.standard.selectedCountry
        let savedFranchise = UserDefaults.standard.loginSelectedFranchiseId(for: savedCountry.countryCode)
            ?? UserDefaults.standard.loginSelectedFranchiseId
        guard let savedFranchise, !savedFranchise.isEmpty else {
            LogManager.shared.warning("Session restore blocked: no franchise selected at login")
            try? Auth.auth().signOut()
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringSession = false
                self?.isAuthenticated = false
                self?.currentUser = nil
                self?.userProfile = nil
            }
            return
        }
        
        // Validate country before allowing access
        beginCountryValidation()
        validateUserCountry(
            uid: user.uid,
            selectedCountryCode: savedCountry.countryCode,
            expectedFranchiseId: savedFranchise
        ) { [weak self] isValid in
            DispatchQueue.main.async {
                self?.endCountryValidation()
                guard let self = self else { return }
                if isValid {
                    self.claimSingleSessionLock(for: user.uid, forceTakeover: false) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let granted):
                                if granted {
                                    self.currentUser = user
                                    self.isAuthenticated = true
                                    self.loadUserProfile(uid: user.uid)
                                    self.startSingleSessionEnforcement(for: user.uid)
                                } else {
                                    LogManager.shared.warning("Session held elsewhere on app restart, signing out")
                                    self.errorMessage = "Session ended elsewhere login required".localized
                                    try? Auth.auth().signOut()
                                    self.isAuthenticated = false
                                    self.currentUser = nil
                                    self.userProfile = nil
                                }
                                self.isRestoringSession = false
                            case .failure(let error):
                                LogManager.shared.error("Session lock failed on startup: \(error.localizedDescription)")
                                self.errorMessage = error.localizedDescription
                                try? Auth.auth().signOut()
                                self.isAuthenticated = false
                                self.currentUser = nil
                                self.userProfile = nil
                                self.isRestoringSession = false
                            }
                        }
                    }
                } else {
                    // Country mismatch on restart - sign out
                    LogManager.shared.warning("Country mismatch on app restart, signing out")
                    try? Auth.auth().signOut()
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.userProfile = nil
                    self.isRestoringSession = false
                }
            }
        }
    }
    
    func loadUserProfile(uid: String) {
        LogManager.shared.debug("Loading user profile for uid: \(uid)")
        
        // First try to find by document ID (uid)
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error loading user profile: \(error.localizedDescription)")
                return
            }
            
            if let data = snapshot?.data() {
                // Found by document ID
                self?.parseAndSetUserProfile(uid: uid, data: data)
            } else {
                // Not found by document ID, try query by uid field
                LogManager.shared.debug("Profile not found by document ID, trying query...")
                self?.loadUserProfileByQuery(uid: uid)
            }
        }
    }
    
    // Query-based profile loading (for web-created users with different document IDs)
    private func loadUserProfileByQuery(uid: String) {
        db.collection("users").whereField("uid", isEqualTo: uid).limit(to: 1).getDocuments { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error querying user profile: \(error.localizedDescription)")
                return
            }
            
            guard let document = snapshot?.documents.first,
                  let data = document.data() as? [String: Any] else {
                LogManager.shared.warning("No user profile found for uid: \(uid)")
                return
            }
            
            self?.parseAndSetUserProfile(uid: uid, data: data)
        }
    }

    /// Applies franchise-level currency override as early as possible after profile parsing.
    private func applyFranchiseCurrencyOverride(franchiseId: String) {
        let normalizedId = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedId.isEmpty else {
            AppCurrency.clearFranchiseCurrencyOverride()
            return
        }
        db.collection("franchises").document(normalizedId).getDocument { snapshot, _ in
            let currency = snapshot?.data()?["currency"] as? String
            AppCurrency.setFranchiseCurrencyCode(currency)
        }
    }
    
    // Parse profile data and set userProfile
    private func parseAndSetUserProfile(uid: String, data: [String: Any]) {
        // DEBUG: Log all raw Firestore document fields for troubleshooting
        LogManager.shared.debug("🔍 Raw user document keys: \(data.keys.sorted().joined(separator: ", "))")
        LogManager.shared.debug("🔍 franchiseId raw value: \(String(describing: data["franchiseId"])) (type: \(type(of: data["franchiseId"])))")
        LogManager.shared.debug("🔍 isDemoAccount raw value: \(String(describing: data["isDemoAccount"])) (type: \(type(of: data["isDemoAccount"])))")
        LogManager.shared.debug("🔍 role raw value: \(String(describing: data["role"])) (type: \(type(of: data["role"])))")
        LogManager.shared.debug("🔍 isActive raw value: \(String(describing: data["isActive"])) (type: \(type(of: data["isActive"])))")
        
        // Email is required
        guard let email = data["email"] as? String else {
            LogManager.shared.error("Missing required email field")
            return
        }
        
        // firstName/lastName are optional; support legacy web schemas using name/fullName/displayName.
        let rawFirstName = (data["firstName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLastName = (data["lastName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyName = (
            (data["name"] as? String) ??
            (data["fullName"] as? String) ??
            (data["displayName"] as? String) ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let firstName: String
        let lastName: String
        if !rawFirstName.isEmpty || !rawLastName.isEmpty {
            firstName = rawFirstName
            lastName = rawLastName
        } else if !legacyName.isEmpty {
            let parts = legacyName.split(separator: " ", maxSplits: 1).map(String.init)
            firstName = parts.first ?? ""
            lastName = parts.count > 1 ? parts[1] : ""
        } else {
            firstName = ""
            lastName = ""
        }
        let legacyNickname = (data["nickname"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Convert Firestore Timestamp to Date
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date() // Fallback to current date
        }
        
        // Backward-compatible demo/trial fields.
        let isDemoAccount = (data["isDemoAccount"] as? Bool) ?? (data["isDemo"] as? Bool) ?? false
        let parentUserId = data["parentUserId"] as? String
        let countryCode = data["countryCode"] as? String ?? "CH"
        let franchiseId = (data["franchiseId"] as? String ?? "CH").uppercased()
        
        // Extract role field
        let roleString = data["role"] as? String ?? "staff"
        let role = UserRole(rawValue: roleString) ?? .staff
        let isActive = (data["isActive"] as? Bool) ?? true
        let rawGarageLink = (data["linkedGarageId"] as? String) ?? (data["garageId"] as? String)
        let linkedGarageId: String? = {
            let t = rawGarageLink?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }()
        
        // Convert demo/trial timestamp fields to Date.
        var demoExpiresAt: Date? = nil
        if let demoTimestamp = data["demoExpiresAt"] as? Timestamp {
            demoExpiresAt = demoTimestamp.dateValue()
        }
        
        var trialStartedAt: Date? = nil
        if let trialStart = data["trialStartedAt"] as? Timestamp {
            trialStartedAt = trialStart.dateValue()
        }
        
        var trialEndsAt: Date? = nil
        if let trialEnd = data["trialEndsAt"] as? Timestamp {
            trialEndsAt = trialEnd.dateValue()
        }
        
        var convertedAt: Date? = nil
        if let convertedTs = data["convertedAt"] as? Timestamp {
            convertedAt = convertedTs.dateValue()
        }
        
        let trialStatusRaw = (data["trialStatus"] as? String) ?? ""
        let isTrialUser = (data["isTrialUser"] as? Bool) ?? isDemoAccount
        
        let resolvedTrialStatus: TrialStatus = {
            if let parsed = TrialStatus(rawValue: trialStatusRaw) {
                return parsed
            }
            if convertedAt != nil {
                return .converted
            }
            if isTrialUser, let endAt = trialEndsAt ?? demoExpiresAt, endAt <= Date() {
                return .expired
            }
            return .active
        }()
        
        let legacyCrossFranchiseFlag = (data["isGlobalAdmin"] as? Bool) ?? false

        let rawUsername = (data["username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedUsername: String? = {
            if let u = rawUsername, !u.isEmpty { return u }
            let fnTrim = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fnTrim.isEmpty { return fnTrim }
            if let n = legacyNickname, !n.isEmpty { return n }
            return nil
        }()
        let scopeLevelStr = (data["scopeLevel"] as? String ?? "single")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let defaultFranchiseRaw = (data["defaultFranchiseId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var membershipMap: [String: Bool]? = nil
        if let mem = data["franchiseMemberships"] as? [String: Any] {
            var built: [String: Bool] = [:]
            for (k, v) in mem {
                if let b = v as? Bool, b {
                    built[k.uppercased()] = true
                }
            }
            membershipMap = built.isEmpty ? nil : built
        }

        // Parse unified `roleScope` map (preferred over legacy scopeLevel/franchiseMemberships).
        var parsedRoleScope: UserRoleScope? = nil
        if let rs = data["roleScope"] as? [String: Any] {
            let lvlStr = (rs["level"] as? String ?? "").lowercased()
            let lvl: RoleScopeLevel? = {
                switch lvlStr {
                case "global": return .global
                case "country": return .country
                case "franchise": return .franchise
                default: return nil
                }
            }()
            if let resolvedLevel = lvl {
                let ccRaw = (rs["countryCode"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                let rawIds = rs["franchiseIds"] as? [Any] ?? []
                let fids: [String] = rawIds.compactMap { raw in
                    let s = (raw as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                    return s.isEmpty ? nil : s
                }
                parsedRoleScope = UserRoleScope(
                    level: resolvedLevel,
                    countryCode: resolvedLevel == .global ? "" : ccRaw,
                    franchiseIds: fids
                )
            }
        }

        let profile = UserProfile(
            uid: uid,
            email: email,
            firstName: firstName,
            lastName: lastName,
            username: mergedUsername,
            scopeLevel: ["single", "selected", "country_all"].contains(scopeLevelStr) ? scopeLevelStr : "single",
            franchiseMemberships: membershipMap,
            defaultFranchiseId: (defaultFranchiseRaw?.isEmpty == true) ? nil : defaultFranchiseRaw?.uppercased(),
            createdAt: createdAt,
            isDemoAccount: isDemoAccount,
            parentUserId: parentUserId,
            demoExpiresAt: demoExpiresAt,
            isTrialUser: isTrialUser,
            trialStartedAt: trialStartedAt,
            trialEndsAt: trialEndsAt ?? demoExpiresAt,
            trialStatus: resolvedTrialStatus,
            convertedAt: convertedAt,
            countryCode: countryCode,
            franchiseId: franchiseId,
            role: role,
            linkedGarageId: linkedGarageId,
            isActive: isActive,
            legacyCrossFranchiseFlag: legacyCrossFranchiseFlag,
            roleScope: parsedRoleScope
        )

        AppCurrency.setActiveFranchiseId(profile.resolvedFranchiseIdForDataAccess())
        applyFranchiseCurrencyOverride(franchiseId: profile.resolvedFranchiseIdForDataAccess())
        
        if profile.effectiveIsTrialUser,
           profile.role != .admin,
           profile.role != .superadmin,
           profile.role != .globaladmin,
           profile.role != .garage,
           let trialEnd = profile.effectiveTrialEndsAt,
           trialEnd <= Date(),
           profile.trialStatus != .converted {
            DispatchQueue.main.async {
                self.errorMessage = "30 gunluk demo surumu bitti, admin ile contacta geciniz.".localized
                self.signOut()
            }
            return
        }
        
        DispatchQueue.main.async {
            self.persistSessionBranchFromProfile(profile)
            self.userProfile = profile
            WheelSysCookieCache.rebindToCurrentUser()
            let fid = profile.resolvedFranchiseIdForDataAccess()
            if FranchiseCapabilityMatrix.wheelSysEnabledForActiveFranchise(fid) {
                WheelSysCookieCache.restorePersistedSession(franchiseId: fid)
            }
            LogManager.shared.info("User profile loaded: \(profile.fullName.isEmpty ? profile.email : profile.fullName)")
            NotificationManager.shared.refreshPushRegistrationAfterAuth()
        }
    }
    
    /// Start country validation with a timeout safety net (10 seconds)
    private func beginCountryValidation() {
        isValidatingCountry = true
        validationTimeoutWork?.cancel()
        
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard self?.isValidatingCountry == true else { return }
            LogManager.shared.warning("Country validation timed out after 10 seconds, resetting flag")
            self?.isValidatingCountry = false
        }
        validationTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWork)
    }
    
    /// End country validation and cancel timeout
    private func endCountryValidation() {
        isValidatingCountry = false
        validationTimeoutWork?.cancel()
        validationTimeoutWork = nil
    }
    
    // Email/Password ile giriş - ülke kontrolü ile
    func signIn(
        email: String,
        password: String,
        selectedCountryCode: String? = nil,
        selectedFranchiseId: String? = nil,
        forceSessionTakeover: Bool = false,
        completion: @escaping (SignInResult) -> Void
    ) {
        if let countryCode = selectedCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !countryCode.isEmpty {
            if let global = UserDefaults.standard.loginSelectedFranchiseId,
               !LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                   franchiseId: global,
                   documentCountryCode: nil,
                   selectedCountryCode: countryCode
               ) {
                UserDefaults.standard.loginSelectedFranchiseId = nil
            }
        }
        if let fid = selectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !fid.isEmpty {
            let normalized = fid.uppercased()
            UserDefaults.standard.loginSelectedFranchiseId = normalized
            if let countryCode = selectedCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines), !countryCode.isEmpty {
                UserDefaults.standard.setLoginSelectedFranchiseId(normalized, for: countryCode)
            }
        }
        // If country validation is needed, set flag to prevent auth state listener from triggering
        if selectedCountryCode != nil {
            beginCountryValidation()
        }
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.endCountryValidation()
                    self?.errorMessage = error.localizedDescription
                    completion(.failed)
                    return
                }
                
                guard let user = result?.user else {
                    self?.endCountryValidation()
                    completion(.failed)
                    return
                }
                
                // Block auth listener from marking session / showing main UI until Firestore lock is decided.
                self?.isSessionGuardPending = true
                
                // Eğer ülke kontrolü gerekiyorsa, önce profili kontrol et
                if let countryCode = selectedCountryCode {
                    self?.errorMessage = nil
                    self?.validateUserCountry(
                        uid: user.uid,
                        selectedCountryCode: countryCode,
                        expectedFranchiseId: selectedFranchiseId
                    ) { isValid in
                        self?.endCountryValidation()
                        
                        if isValid {
                            self?.guardSingleSessionAndCompleteSignIn(
                                user: user,
                                forceTakeover: forceSessionTakeover,
                                completion: completion
                            )
                        } else {
                            // Ülke eşleşmedi - çıkış yap ve hata göster
                            self?.isSessionGuardPending = false
                            try? Auth.auth().signOut()
                            if self?.errorMessage == nil {
                                self?.errorMessage = "Invalid credentials for selected country".localized
                            }
                            completion(.failed)
                        }
                    }
                } else {
                    // Ülke kontrolü yok, normal giriş
                    self?.endCountryValidation()
                    self?.guardSingleSessionAndCompleteSignIn(
                        user: user,
                        forceTakeover: forceSessionTakeover,
                        completion: completion
                    )
                }
            }
        }
    }

    private func guardSingleSessionAndCompleteSignIn(
        user: User,
        forceTakeover: Bool,
        completion: @escaping (SignInResult) -> Void
    ) {
        claimSingleSessionLock(for: user.uid, forceTakeover: forceTakeover) { [weak self] result in
            DispatchQueue.main.async {
                defer { self?.isSessionGuardPending = false }
                guard let self = self else {
                    completion(.failed)
                    return
                }

                switch result {
                case .failure(let error):
                    LogManager.shared.error("Session lock failed: \(error.localizedDescription)")
                    try? Auth.auth().signOut()
                    self.errorMessage = error.localizedDescription
                    completion(.failed)
                case .success(let granted):
                    guard granted else {
                        try? Auth.auth().signOut()
                        self.errorMessage = nil
                        completion(.activeSessionElsewhere)
                        return
                    }
                    self.completeSignIn(user: user)
                    self.startSingleSessionEnforcement(for: user.uid)
                    completion(.success)
                }
            }
        }
    }

    private func claimSingleSessionLock(for uid: String, forceTakeover: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userRef = db.collection("users").document(uid)
        let now = Date()

        db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(userRef)
                let data = snapshot.data() ?? [:]
                let activeSessionId = data["activeSessionId"] as? String
                let isSessionActive = (data["isSessionActive"] as? Bool) ?? false
                // No time-based grace: if another client holds the lock, that is a conflict until sign-out or takeover.
                let sid = (activeSessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let hasConflict = isSessionActive &&
                    !sid.isEmpty &&
                    sid != self.localSessionId

                if hasConflict && !forceTakeover {
                    return false
                }

                transaction.setData([
                    "activeSessionId": self.localSessionId,
                    "isSessionActive": true,
                    "activeSessionUpdatedAt": Timestamp(date: now)
                ], forDocument: userRef, merge: true)
                return true
            } catch let error as NSError {
                errorPointer?.pointee = error
                return false
            }
        } completion: { object, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success((object as? Bool) == true))
        }
    }

    private func markSessionActive(for uid: String) {
        db.collection("users").document(uid).setData([
            "activeSessionId": localSessionId,
            "isSessionActive": true,
            "activeSessionUpdatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func markSessionInactive(for uid: String) {
        let userRef = db.collection("users").document(uid)
        db.runTransaction { transaction, _ -> Any? in
            let snapshot = try? transaction.getDocument(userRef)
            let activeSessionId = snapshot?.data()?["activeSessionId"] as? String
            if activeSessionId == nil || activeSessionId == self.localSessionId {
                transaction.setData([
                    "isSessionActive": false,
                    "activeSessionUpdatedAt": Timestamp(date: Date())
                ], forDocument: userRef, merge: true)
            }
            return nil
        } completion: { _, _ in }
    }

    private func startSingleSessionEnforcement(for uid: String) {
        singleSessionListener?.remove()
        // includeMetadataChanges: true so we can inspect isFromCache and skip stale
        // local-cache snapshots that arrive immediately after a Firestore transaction
        // (the transaction write may not have propagated to the local cache yet,
        // causing a false "session taken over" detection on the device that just claimed the lock).
        singleSessionListener = db.collection("users").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                guard let self = self else { return }
                // Skip snapshots sourced from the local cache; only act on
                // server-confirmed state to avoid false positives right after
                // a forced session takeover transaction.
                guard snapshot?.metadata.isFromCache == false else { return }
                let data = snapshot?.data() ?? [:]
                let activeSessionId = data["activeSessionId"] as? String
                let isSessionActive = (data["isSessionActive"] as? Bool) ?? false
                let sid = (activeSessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let sessionTakenOver = isSessionActive &&
                    !sid.isEmpty &&
                    sid != self.localSessionId

                if sessionTakenOver {
                    DispatchQueue.main.async {
                        self.errorMessage = "Your account was opened on another device. You have been signed out.".localized
                        self.signOut()
                    }
                }
            }
    }
    
    // Kullanıcının ülke kodunu doğrula
    private func validateUserCountry(
        uid: String,
        selectedCountryCode: String,
        expectedFranchiseId: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        // First try document ID
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error validating user country: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let data = snapshot?.data() {
                // Found by document ID
                self?.checkCountryCode(
                    data: data,
                    selectedCountryCode: selectedCountryCode,
                    expectedFranchiseId: expectedFranchiseId,
                    completion: completion
                )
            } else {
                // Not found by document ID, try query
                self?.validateUserCountryByQuery(
                    uid: uid,
                    selectedCountryCode: selectedCountryCode,
                    expectedFranchiseId: expectedFranchiseId,
                    completion: completion
                )
            }
        }
    }
    
    // Query-based country validation (for web-created users)
    private func validateUserCountryByQuery(
        uid: String,
        selectedCountryCode: String,
        expectedFranchiseId: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("users").whereField("uid", isEqualTo: uid).limit(to: 1).getDocuments { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error querying user country: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot?.documents.first else {
                LogManager.shared.warning("No user profile found for country validation")
                completion(false)
                return
            }
            
            self?.checkCountryCode(
                data: document.data(),
                selectedCountryCode: selectedCountryCode,
                expectedFranchiseId: expectedFranchiseId,
                completion: completion
            )
        }
    }
    
    /// Matches web logic: only globaladmin can bypass country/franchise gate.
    private func normalizedRoleKey(from data: [String: Any]) -> String {
        let raw = (data["role"] as? String ?? "staff").lowercased()
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func bypassesCountryGate(data: [String: Any]) -> Bool {
        let r = normalizedRoleKey(from: data)
        if r == UserRole.globaladmin.rawValue { return true }
        if let rs = data["roleScope"] as? [String: Any],
           let lvl = (rs["level"] as? String)?.lowercased(),
           lvl == "global" {
            return true
        }
        return false
    }

    /// Same rules as web `userCanAccessFranchiseAtLogin` for non–globaladmin users.
    /// Now roleScope-aware: prefers `users.roleScope.franchiseIds` when present.
    private func profileAllowsSelectedFranchise(data: [String: Any], expectedFranchiseId: String?) -> Bool {
        guard let raw = expectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        let expU = raw.uppercased()

        // 1) Canonical roleScope.
        if let rs = data["roleScope"] as? [String: Any] {
            let lvl = (rs["level"] as? String ?? "").lowercased()
            if lvl == "global" { return true }
            let rawIds = rs["franchiseIds"] as? [Any] ?? []
            let fids: Set<String> = Set(rawIds.compactMap { raw in
                (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }.filter { !$0.isEmpty })
            if lvl == "country" && fids.isEmpty {
                // Country-wide; country code is checked elsewhere.
                return true
            }
            if !fids.isEmpty {
                return fids.contains(expU)
            }
        }

        // 2) Legacy fields.
        let scope = (data["scopeLevel"] as? String ?? "single").lowercased()
        if scope == "country_all" {
            return true
        }
        if let mem = data["franchiseMemberships"] as? [String: Any] {
            for (k, v) in mem {
                if let b = v as? Bool, b, k.uppercased() == expU {
                    return true
                }
            }
        }
        let primary = (data["franchiseId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return primary == expU
    }

    // MARK: - Session branch (login picker vs profile — prevents stale CH cache for DE users)

    private func persistSessionBranchFromProfile(_ profile: UserProfile) {
        guard !profile.isCrossFranchisePlatformOperator else { return }
        let cc = profile.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cc.isEmpty else { return }
        if profile.isLockedToSingleFranchise {
            let fid = profile.authoritativeFranchiseId()
            UserDefaults.standard.loginSelectedFranchiseId = fid
            UserDefaults.standard.setLoginSelectedFranchiseId(fid, for: cc)
        }
        if let country = CountryManager.country(byCode: cc) {
            UserDefaults.standard.selectedCountryId = country.id
        }
    }

    private func persistSessionBranchFromUserData(_ data: [String: Any], preferredFranchiseId: String? = nil) {
        guard !bypassesCountryGate(data: data) else { return }
        let cc = (data["countryCode"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !cc.isEmpty else { return }
        let fid: String = {
            if let preferred = preferredFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
                return preferred.uppercased()
            }
            return Self.authoritativeFranchiseId(fromUserData: data)
        }()
        guard !fid.isEmpty else { return }
        UserDefaults.standard.loginSelectedFranchiseId = fid
        UserDefaults.standard.setLoginSelectedFranchiseId(fid, for: cc)
        if let country = CountryManager.country(byCode: cc) {
            UserDefaults.standard.selectedCountryId = country.id
        }
    }

    private static func isLockedToSingleFranchise(fromUserData data: [String: Any]) -> Bool {
        if bypassesCountryGateStatic(data: data) { return false }
        let scope = (data["scopeLevel"] as? String ?? "single").lowercased()
        if scope == "country_all" { return false }
        if scope == "selected" {
            if let mem = data["franchiseMemberships"] as? [String: Any] {
                let active = mem.compactMap { key, value -> String? in
                    guard let b = value as? Bool, b else { return nil }
                    let t = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    return t.isEmpty ? nil : t
                }
                return active.count <= 1
            }
            return true
        }
        if let rs = data["roleScope"] as? [String: Any] {
            let lvl = (rs["level"] as? String ?? "").lowercased()
            if lvl == "global" || lvl == "country" { return false }
            if lvl == "franchise" { return true }
        }
        return true
    }

    private static func authoritativeFranchiseId(fromUserData data: [String: Any]) -> String {
        let cc = (data["countryCode"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let defaultFranchise = (data["defaultFranchiseId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var roleScopeIds: [String] = []
        if let rs = data["roleScope"] as? [String: Any] {
            let rawIds = rs["franchiseIds"] as? [Any] ?? []
            roleScopeIds = rawIds.compactMap { raw -> String? in
                let s = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return s.isEmpty ? nil : s
            }
        }
        var memIds: [String] = []
        if let mem = data["franchiseMemberships"] as? [String: Any] {
            memIds = mem.compactMap { key, value -> String? in
                guard let b = value as? Bool, b else { return nil }
                let t = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return t.isEmpty ? nil : t
            }
        }
        let primary = (data["franchiseId"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LoginFranchiseCountryGuard.pickAuthoritativeFranchiseId(
            countryCode: cc,
            defaultFranchiseId: defaultFranchise,
            roleScopeFranchiseIds: roleScopeIds,
            membershipIds: memIds,
            primaryFranchiseId: primary
        )
    }

    private static func bypassesCountryGateStatic(data: [String: Any]) -> Bool {
        let r = (data["role"] as? String ?? "staff").lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        if r == UserRole.globaladmin.rawValue { return true }
        if let rs = data["roleScope"] as? [String: Any],
           (rs["level"] as? String)?.lowercased() == "global" {
            return true
        }
        return false
    }

    // Check country code match
    private func checkCountryCode(
        data: [String: Any],
        selectedCountryCode: String,
        expectedFranchiseId: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let userCountryCode = data["countryCode"] as? String ?? "CH"
        let isActive = (data["isActive"] as? Bool) ?? true
        
        guard isActive else {
            LogManager.shared.warning("Inactive user blocked during login")
            DispatchQueue.main.async {
                self.errorMessage = "Your account is inactive. Please contact administrator.".localized
            }
            completion(false)
            return
        }

        if bypassesCountryGate(data: data) {
            if isTrialAccessExpired(data: data) {
                LogManager.shared.warning("Expired trial user blocked during login")
                DispatchQueue.main.async {
                    self.errorMessage = "30 gunluk demo surumu bitti, admin ile contacta geciniz.".localized
                }
                completion(false)
                return
            }
            completion(true)
            return
        }
        
        let isValid = userCountryCode.uppercased() == selectedCountryCode.uppercased()
        
        if !isValid {
            LogManager.shared.warning("Country mismatch: user=\(userCountryCode), selected=\(selectedCountryCode)")
            DispatchQueue.main.async {
                self.errorMessage = nil
            }
        }
        
        guard isValid else {
            completion(false)
            return
        }
        
        if Self.isLockedToSingleFranchise(fromUserData: data) {
            let authoritative = Self.authoritativeFranchiseId(fromUserData: data)
            if let exp = expectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !exp.isEmpty,
               exp.uppercased() != authoritative {
                LogManager.shared.warning("Login franchise mismatch: selected=\(exp) profile=\(authoritative)")
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid credentials for selected franchise".localized
                }
                completion(false)
                return
            }
            persistSessionBranchFromUserData(data)
        } else if let exp = expectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !exp.isEmpty {
            if !profileAllowsSelectedFranchise(data: data, expectedFranchiseId: exp) {
                LogManager.shared.warning("Franchise mismatch for selected=\(exp)")
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid credentials for selected franchise".localized
                }
                completion(false)
                return
            }
            persistSessionBranchFromUserData(data, preferredFranchiseId: exp.uppercased())
        }
        
        if isTrialAccessExpired(data: data) {
            LogManager.shared.warning("Expired trial user blocked during login")
            DispatchQueue.main.async {
                self.errorMessage = "30 gunluk demo surumu bitti, admin ile contacta geciniz.".localized
            }
            completion(false)
            return
        }
        
        completion(true)
    }
    
    private func isTrialAccessExpired(data: [String: Any]) -> Bool {
        let role = (data["role"] as? String ?? "staff").lowercased()
        if role == UserRole.admin.rawValue || role == UserRole.superadmin.rawValue || role == UserRole.globaladmin.rawValue {
            return false
        }
        
        let isTrialUser = (data["isTrialUser"] as? Bool) ??
            (data["isDemoAccount"] as? Bool) ??
            (data["isDemo"] as? Bool) ??
            false
        guard isTrialUser else { return false }
        
        if let status = data["trialStatus"] as? String, status.lowercased() == TrialStatus.converted.rawValue {
            return false
        }
        
        if let trialEndsAt = data["trialEndsAt"] as? Timestamp {
            return trialEndsAt.dateValue() <= Date()
        }
        
        if let demoExpiresAt = data["demoExpiresAt"] as? Timestamp {
            return demoExpiresAt.dateValue() <= Date()
        }
        
        return false
    }
    
    // Giriş işlemini tamamla
    private func completeSignIn(user: User) {
        AppSessionGate.markFreshLoginCompleted()
        self.currentUser = user
        self.isAuthenticated = true

        // Save user ID to Keychain
        _ = SecureStorageManager.shared.saveUserId(user.uid)
        
        // Get and save auth token
        user.getIDToken { token, error in
            if let token = token {
                _ = SecureStorageManager.shared.saveAuthToken(token)
            }
        }
        
        // Set Crashlytics user ID
        Crashlytics.crashlytics().setUserID(user.uid)
        
        // Load user profile after successful login
        self.loadUserProfile(uid: user.uid)
    }
    
    // Yeni kullanıcı kaydı - ülke kodu ile
    func signUp(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        countryCode: String = "CH",
        isDemoAccount: Bool = false,
        demoExpiresAt: Date? = nil,
        isTrialUser: Bool? = nil,
        trialDays: Int = 30,
        completion: @escaping (Bool) -> Void
    ) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                guard let user = result?.user else {
                    completion(false)
                    return
                }
                
                let resolvedIsTrialUser = isTrialUser ?? isDemoAccount
                let resolvedTrialStartsAt = resolvedIsTrialUser ? Date() : nil
                let resolvedTrialEndsAt = resolvedIsTrialUser ?
                    (demoExpiresAt ?? Calendar.current.date(byAdding: .day, value: trialDays, to: Date())) :
                    nil
                
                let derivedFranchiseId = CountryManager.country(byCode: countryCode)?.id.uppercased()
                    ?? countryCode.uppercased()

                let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let initialUsername: String? = trimmedFirst.isEmpty ? nil : String(trimmedFirst.prefix(64))
                
                // Firestore'a kullanıcı profili kaydet
                let userProfile = UserProfile(
                    uid: user.uid,
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    username: initialUsername,
                    createdAt: Date(),
                    isDemoAccount: isDemoAccount,
                    parentUserId: nil,
                    demoExpiresAt: demoExpiresAt,
                    isTrialUser: resolvedIsTrialUser,
                    trialStartedAt: resolvedTrialStartsAt,
                    trialEndsAt: resolvedTrialEndsAt,
                    trialStatus: resolvedIsTrialUser ? .active : .converted,
                    convertedAt: nil,
                    countryCode: countryCode,
                    franchiseId: derivedFranchiseId
                )
                
                self?.saveUserProfile(userProfile) { success in
                    if success {
                        self?.currentUser = user
                        self?.userProfile = userProfile
                        self?.isAuthenticated = true
                        let uid = user.uid
                        self?.claimSingleSessionLock(for: uid, forceTakeover: false) { result in
                            DispatchQueue.main.async {
                                if case .success(let granted) = result, granted {
                                    self?.startSingleSessionEnforcement(for: uid)
                                }
                            }
                        }
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            }
        }
    }
    
    func saveUserProfile(_ profile: UserProfile, completion: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(profile)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            db.collection("users").document(profile.uid).setData(json) { error in
                if let error = error {
                    LogManager.shared.error("Error saving user profile", error: error)
                    Crashlytics.crashlytics().record(error: error)
                    completion(false)
                } else {
                    LogManager.shared.success("User profile saved successfully")
                    completion(true)
                }
            }
        } catch {
            LogManager.shared.error("Error encoding user profile", error: error)
            Crashlytics.crashlytics().record(error: error)
            completion(false)
        }
    }
    
    // MARK: - Demo Account Creation
    
    /// Create a demo account for a parent user
    /// - Parameters:
    ///   - parentUserId: The ID of the parent (production) user
    ///   - completion: Callback with success status and demo user email (if successful)
    func createDemoAccount(for parentUserId: String, completion: @escaping (Bool, String?) -> Void) {
        // Generate demo email: {parentUserId}_demo@example.com
        let demoEmail = "\(parentUserId)_demo@example.com"
        // Generate random password (can be customized)
        let demoPassword = "Demo123!\(parentUserId.prefix(4))"
        
        db.collection("users").document(parentUserId).getDocument { [weak self] parentSnapshot, _ in
            let parentData = parentSnapshot?.data()
            let parentCountryCode = parentData?["countryCode"] as? String ?? "CH"
            let parentFranchiseId = (parentData?["franchiseId"] as? String ?? "CH").uppercased()
            let trialStart = Date()
            let trialEnd = Calendar.current.date(byAdding: .day, value: 30, to: trialStart)
            
            Auth.auth().createUser(withEmail: demoEmail, password: demoPassword) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    LogManager.shared.error("Error creating demo account", error: error)
                    completion(false, nil)
                    return
                }
                
                guard let user = result?.user else {
                    completion(false, nil)
                    return
                }
                
                // Create UserProfile with isDemoAccount flag
                let demoProfile = UserProfile(
                    uid: user.uid,
                    email: demoEmail,
                    firstName: "Demo",
                    lastName: "User",
                    username: "Demo",
                    createdAt: Date(),
                    isDemoAccount: true,
                    parentUserId: parentUserId,
                    demoExpiresAt: trialEnd,
                    isTrialUser: true,
                    trialStartedAt: trialStart,
                    trialEndsAt: trialEnd,
                    trialStatus: .active,
                    convertedAt: nil,
                    countryCode: parentCountryCode,
                    franchiseId: parentFranchiseId
                )
                
                self?.saveUserProfile(demoProfile) { success in
                    if success {
                        LogManager.shared.success("Demo account created successfully: \(demoEmail)")
                        completion(true, demoEmail)
                    } else {
                        LogManager.shared.error("Failed to save demo user profile")
                        completion(false, nil)
                    }
                }
            }
            }
        }
    }
    
    // Çıkış yap
    func signOut() {
        LiveActivityTracker.shared.recordLogout(userProfile: userProfile)
        ShuttleLocationSharingService.shared.resetSession()
        let currentUid = currentUser?.uid
        singleSessionListener?.remove()
        singleSessionListener = nil
        if let currentUid {
            markSessionInactive(for: currentUid)
        }

        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        SecureStorageManager.shared.clearSessionSecrets()
        WheelSysCookieCache.clearAllPersisted()
        WheelSysLoginWebView.clearWebsiteData()
        AppSessionGate.clearLoginBranchPreferences()
        AppCurrency.clearFranchiseCurrencyOverride()
        AppCurrency.clearActiveFranchiseId()

        do {
            try Auth.auth().signOut()
        } catch {
            LogManager.shared.error("Sign out failed: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.currentUser = nil
            self.userProfile = nil
            self.isRestoringSession = false
        }

        if authStateListener == nil {
            setupAuthStateListener()
        }
    }
    
    // MARK: - Token Refresh Handling
    
    /// Setup auth state listener for automatic token refresh
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            DispatchQueue.main.async {
                // Skip if we're in the middle of country validation or email sign-in session guard.
                // Never call markSessionActive from here — it bypasses claimSingleSessionLock and breaks single-session.
                if self?.isValidatingCountry == true || self?.isSessionGuardPending == true {
                    LogManager.shared.debug("Auth state change skipped - validation or session guard in progress")
                    return
                }

                if AppSessionGate.requiresFreshLoginSelection {
                    if user != nil { try? Auth.auth().signOut() }
                    return
                }

                if let user = user {
                    self?.currentUser = user
                    self?.isAuthenticated = true
                    // Refresh token if needed
                    self?.refreshTokenIfNeeded()
                    // Load user profile if not already loaded
                    if self?.userProfile == nil {
                        self?.loadUserProfile(uid: user.uid)
                    }
                } else {
                    // User is signed out
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                    self?.userProfile = nil
                    self?.isRestoringSession = false
                    self?.tokenRefreshTimer?.invalidate()
                    self?.tokenRefreshTimer = nil
                }
            }
        }
    }
    
    /// Setup periodic token refresh monitoring
    private func setupTokenRefreshMonitoring() {
        // Check token every 30 minutes
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.refreshTokenIfNeeded()
        }
    }
    
    /// Refresh token if needed
    func refreshTokenIfNeeded() {
        guard let user = Auth.auth().currentUser else {
            return
        }
        
        Task {
            do {
                // Get current token (non-forcing refresh)
                let token = try await user.getIDToken(forcingRefresh: false)
                // Save token to Keychain
                _ = SecureStorageManager.shared.saveAuthToken(token)
                LogManager.shared.debug("Token is valid")
            } catch {
                LogManager.shared.warning("Token refresh check failed: \(error.localizedDescription)")
                
                // Check if token is expired or invalid
                if let authError = error as NSError?,
                   authError.code == AuthErrorCode.userTokenExpired.rawValue {
                    LogManager.shared.warning("Token expired, attempting refresh...")
                    await refreshToken()
                }
            }
        }
    }
    
    /// Force token refresh
    private func refreshToken() async {
        guard let user = Auth.auth().currentUser else {
            return
        }
        
        do {
            let token = try await user.getIDToken(forcingRefresh: true)
            // Save refreshed token to Keychain
            _ = SecureStorageManager.shared.saveAuthToken(token)
            await MainActor.run {
                LogManager.shared.success("Token refreshed successfully")
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                let nsError = error as NSError
                LogManager.shared.error("Token refresh failed", error: error)
                Crashlytics.crashlytics().record(error: error)
                
                // Only sign out on definitive auth errors, not transient network failures
                let isNetworkError = nsError.domain == NSURLErrorDomain ||
                    nsError.code == NSURLErrorNotConnectedToInternet ||
                    nsError.code == NSURLErrorTimedOut ||
                    nsError.code == NSURLErrorNetworkConnectionLost ||
                    nsError.code == NSURLErrorCannotConnectToHost
                
                if isNetworkError {
                    LogManager.shared.warning("Token refresh failed due to network error, will retry later")
                    self.errorMessage = nil // Don't show error for transient network issues
                } else if nsError.code == AuthErrorCode.userTokenExpired.rawValue ||
                          nsError.code == AuthErrorCode.invalidUserToken.rawValue ||
                          nsError.code == AuthErrorCode.userDisabled.rawValue ||
                          nsError.code == AuthErrorCode.userNotFound.rawValue {
                    // Token is permanently invalid, sign out user
                    LogManager.shared.warning("Invalid token (code: \(nsError.code)), signing out user...")
                    self.errorMessage = "Session expired. Please sign in again."
                    self.signOut()
                } else {
                    // Unknown error - log but don't sign out
                    LogManager.shared.warning("Token refresh failed with code \(nsError.code), will retry later")
                    self.errorMessage = nil
                }
            }
        }
    }
    
    /// Re-authenticate user (for sensitive operations)
    func reauthenticate(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    LogManager.shared.error("Re-authentication failed: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                } else {
                    LogManager.shared.info("Re-authentication successful")
                    // Refresh token after re-authentication (async)
                    Task {
                        await self?.refreshToken()
                    }
                    completion(true)
                }
            }
        }
    }
}
