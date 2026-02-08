import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import FirebaseCrashlytics

// MARK: - User Roles
enum UserRole: String, Codable, CaseIterable {
    case superadmin
    case admin
    case manager
    case staff
    case viewer
}

struct UserProfile: Codable {
    var uid: String
    var email: String
    var firstName: String
    var lastName: String
    var createdAt: Date
    var isDemoAccount: Bool = false  // Demo hesap mı?
    var parentUserId: String? = nil  // Ana kullanıcı ID (demo hesap ise)
    var demoExpiresAt: Date? = nil   // Demo bitiş tarihi
    var countryCode: String = "CH"   // Kullanıcının kayıtlı olduğu ülke kodu (varsayılan: İsviçre)
    var franchiseId: String = "ch"   // Kullanıcının franchise ID'si (varsayılan: Switzerland)
    var role: UserRole = .staff      // Kullanıcı rolü (varsayılan: staff)
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    /// Check if user is a superadmin
    var isSuperAdmin: Bool {
        role == .superadmin
    }
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var tokenRefreshTimer: Timer?
    
    // Flag to prevent auth state listener from setting isAuthenticated during country validation
    private var isValidatingCountry = false
    private var validationTimeoutWork: DispatchWorkItem?
    
    init() {
        checkAuthStatus()
        setupAuthStateListener()
        setupTokenRefreshMonitoring()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
        tokenRefreshTimer?.invalidate()
    }
    
    func checkAuthStatus() {
        guard let user = Auth.auth().currentUser else { return }
        
        // Get the last selected country from UserDefaults
        let savedCountry = UserDefaults.standard.selectedCountry
        
        // Validate country before allowing access
        beginCountryValidation()
        validateUserCountry(uid: user.uid, selectedCountryCode: savedCountry.countryCode) { [weak self] isValid in
            DispatchQueue.main.async {
                self?.endCountryValidation()
                if isValid {
                    self?.currentUser = user
                    self?.isAuthenticated = true
                    self?.loadUserProfile(uid: user.uid)
                } else {
                    // Country mismatch on restart - sign out
                    LogManager.shared.warning("Country mismatch on app restart, signing out")
                    try? Auth.auth().signOut()
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                    self?.userProfile = nil
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
        
        // firstName and lastName are optional (web users might not have them)
        let firstName = data["firstName"] as? String ?? ""
        let lastName = data["lastName"] as? String ?? ""
        
        // Convert Firestore Timestamp to Date
        let createdAt: Date
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date() // Fallback to current date
        }
        
        // Extract optional demo account fields (check both field names for compatibility)
        let isDemoAccount = (data["isDemoAccount"] as? Bool) ?? (data["isDemo"] as? Bool) ?? false
        let parentUserId = data["parentUserId"] as? String
        let countryCode = data["countryCode"] as? String ?? "CH"
        let franchiseId = data["franchiseId"] as? String ?? "ch"
        
        // Extract role field
        let roleString = data["role"] as? String ?? "staff"
        let role = UserRole(rawValue: roleString) ?? .staff
        
        // Convert demoExpiresAt Timestamp to Date
        var demoExpiresAt: Date? = nil
        if let demoTimestamp = data["demoExpiresAt"] as? Timestamp {
            demoExpiresAt = demoTimestamp.dateValue()
        }
        
        let profile = UserProfile(
            uid: uid,
            email: email,
            firstName: firstName,
            lastName: lastName,
            createdAt: createdAt,
            isDemoAccount: isDemoAccount,
            parentUserId: parentUserId,
            demoExpiresAt: demoExpiresAt,
            countryCode: countryCode,
            franchiseId: franchiseId,
            role: role
        )
        
        DispatchQueue.main.async {
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
    func signIn(email: String, password: String, selectedCountryCode: String? = nil, completion: @escaping (Bool) -> Void) {
        // If country validation is needed, set flag to prevent auth state listener from triggering
        if selectedCountryCode != nil {
            beginCountryValidation()
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.endCountryValidation()
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                guard let user = result?.user else {
                    self?.endCountryValidation()
                    completion(false)
                    return
                }
                
                // Eğer ülke kontrolü gerekiyorsa, önce profili kontrol et
                if let countryCode = selectedCountryCode {
                    self?.validateUserCountry(uid: user.uid, selectedCountryCode: countryCode) { isValid in
                        self?.endCountryValidation()
                        
                        if isValid {
                            self?.completeSignIn(user: user)
                            completion(true)
                        } else {
                            // Ülke eşleşmedi - çıkış yap ve hata göster
                            try? Auth.auth().signOut()
                            self?.errorMessage = "Invalid credentials for selected country".localized
                            completion(false)
                        }
                    }
                } else {
                    // Ülke kontrolü yok, normal giriş
                    self?.endCountryValidation()
                    self?.completeSignIn(user: user)
                    completion(true)
                }
            }
        }
    }
    
    // Kullanıcının ülke kodunu doğrula
    private func validateUserCountry(uid: String, selectedCountryCode: String, completion: @escaping (Bool) -> Void) {
        // First try document ID
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error validating user country: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let data = snapshot?.data() {
                // Found by document ID
                self?.checkCountryCode(data: data, selectedCountryCode: selectedCountryCode, completion: completion)
            } else {
                // Not found by document ID, try query
                self?.validateUserCountryByQuery(uid: uid, selectedCountryCode: selectedCountryCode, completion: completion)
            }
        }
    }
    
    // Query-based country validation (for web-created users)
    private func validateUserCountryByQuery(uid: String, selectedCountryCode: String, completion: @escaping (Bool) -> Void) {
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
            
            self?.checkCountryCode(data: document.data(), selectedCountryCode: selectedCountryCode, completion: completion)
        }
    }
    
    // Check country code match
    private func checkCountryCode(data: [String: Any], selectedCountryCode: String, completion: @escaping (Bool) -> Void) {
        let userCountryCode = data["countryCode"] as? String ?? "CH"
        let isValid = userCountryCode.uppercased() == selectedCountryCode.uppercased()
        
        if !isValid {
            LogManager.shared.warning("Country mismatch: user=\(userCountryCode), selected=\(selectedCountryCode)")
        }
        
        completion(isValid)
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
        // Set user online after successful login
        UserPresenceManager.shared.setOnline()
        // Start monitoring presence
        UserPresenceManager.shared.startMonitoring()
    }
    
    // Yeni kullanıcı kaydı - ülke kodu ile
    func signUp(email: String, password: String, firstName: String, lastName: String, countryCode: String = "CH", isDemoAccount: Bool = false, demoExpiresAt: Date? = nil, completion: @escaping (Bool) -> Void) {
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
                
                // Firestore'a kullanıcı profili kaydet
                let userProfile = UserProfile(
                    uid: user.uid,
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    createdAt: Date(),
                    isDemoAccount: isDemoAccount,
                    parentUserId: nil,
                    demoExpiresAt: demoExpiresAt,
                    countryCode: countryCode
                )
                
                self?.saveUserProfile(userProfile) { success in
                    if success {
                        self?.currentUser = user
                        self?.userProfile = userProfile
                        self?.isAuthenticated = true
                        // Set user online after successful signup
                        UserPresenceManager.shared.setOnline()
                        // Start monitoring presence
                        UserPresenceManager.shared.startMonitoring()
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
                    createdAt: Date(),
                    isDemoAccount: true,
                    parentUserId: parentUserId
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
    
    // Çıkış yap
    func signOut() {
        // Set user offline before signing out
        UserPresenceManager.shared.setOffline()
        // Stop monitoring presence
        UserPresenceManager.shared.stopMonitoring()
        
        // Stop token refresh monitoring
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
        
        // Remove auth state listener to prevent redundant processing after sign out
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authStateListener = nil
        }
        
        // Clear secure storage
        _ = SecureStorageManager.shared.clearAll()
        
        try? Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUser = nil
        self.userProfile = nil
        
        // Re-setup auth state listener for next sign-in
        setupAuthStateListener()
    }
    
    // MARK: - Token Refresh Handling
    
    /// Setup auth state listener for automatic token refresh
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            DispatchQueue.main.async {
                // Skip if we're in the middle of country validation
                // This prevents data loading before country validation completes
                if self?.isValidatingCountry == true {
                    LogManager.shared.debug("Auth state change skipped - country validation in progress")
                    return
                }
                
                if let user = user {
                    // User is authenticated, update state
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
