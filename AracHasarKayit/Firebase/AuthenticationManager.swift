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

    /// Fleet category rename / delete / bulk vehicle removal (aligned with franchise manager tooling).
    var canManageVehicleCategories: Bool {
        role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }
    
    /// Only global admins may operate cross-franchise from login picker context.
    var isCrossFranchisePlatformOperator: Bool {
        role == .globaladmin
    }

    /// Active `franchises/{id}` for reads/writes. Cross-franchise operators follow login/country picker; everyone else uses `users.franchiseId`.
    func resolvedFranchiseIdForDataAccess() -> String {
        if isCrossFranchisePlatformOperator {
            // Login franchise picker stores full doc id (e.g. DE_DUSSELDORF). Country id alone (DE) is wrong when data lives under a location-specific id.
            if let loginFid = UserDefaults.standard.loginSelectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !loginFid.isEmpty {
                return loginFid.uppercased()
            }
            return UserDefaults.standard.selectedCountry.id.uppercased()
        }
        let scope = scopeLevel.lowercased()
        let hasMem = franchiseMemberships?.contains(where: { $0.value }) ?? false
        if scope == "country_all" || hasMem {
            if let loginFid = UserDefaults.standard.loginSelectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !loginFid.isEmpty {
                return loginFid.uppercased()
            }
            if let def = defaultFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !def.isEmpty {
                return def.uppercased()
            }
        }
        return franchiseId.uppercased()
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
        guard let user = Auth.auth().currentUser else {
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringSession = false
            }
            return
        }
        
        // Get the last selected country from UserDefaults
        let savedCountry = UserDefaults.standard.selectedCountry
        let savedFranchise = UserDefaults.standard.loginSelectedFranchiseId
        
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
            legacyCrossFranchiseFlag: legacyCrossFranchiseFlag
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
            // Keep app-wide selected country aligned with profile — except cross-franchise operators, who keep login/country picker scope.
            if !profile.isCrossFranchisePlatformOperator {
                if let country = CountryManager.country(byId: profile.franchiseId) {
                    UserDefaults.standard.selectedCountryId = country.id
                } else if let country = CountryManager.country(byCode: profile.countryCode) {
                    UserDefaults.standard.selectedCountryId = country.id
                }
            }
            self.userProfile = profile
            LogManager.shared.info("User profile loaded: \(profile.fullName.isEmpty ? profile.email : profile.fullName)")
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
        if let fid = selectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !fid.isEmpty {
            UserDefaults.standard.loginSelectedFranchiseId = fid
        }
        // If country validation is needed, set flag to prevent auth state listener from triggering
        if selectedCountryCode != nil {
            beginCountryValidation()
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
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
        return false
    }

    /// Same rules as web `userCanAccessFranchiseAtLogin` for non–globaladmin users.
    private func profileAllowsSelectedFranchise(data: [String: Any], expectedFranchiseId: String?) -> Bool {
        guard let raw = expectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        let expU = raw.uppercased()
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
        
        if let exp = expectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !exp.isEmpty {
            if !profileAllowsSelectedFranchise(data: data, expectedFranchiseId: exp) {
                LogManager.shared.warning("Franchise mismatch for selected=\(exp)")
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid credentials for selected franchise".localized
                }
                completion(false)
                return
            }
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
        let currentUid = currentUser?.uid
        singleSessionListener?.remove()
        singleSessionListener = nil
        if let currentUid {
            markSessionInactive(for: currentUid)
        }

        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        SecureStorageManager.shared.clearSessionSecrets()
        UserDefaults.standard.loginSelectedFranchiseId = nil
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
