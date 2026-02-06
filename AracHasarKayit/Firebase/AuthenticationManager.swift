import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import FirebaseCrashlytics

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
    
    var fullName: String {
        "\(firstName) \(lastName)"
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
        if let user = Auth.auth().currentUser {
            self.currentUser = user
            self.isAuthenticated = true
            loadUserProfile(uid: user.uid)
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
            countryCode: countryCode
        )
        
        DispatchQueue.main.async {
            self.userProfile = profile
            LogManager.shared.info("User profile loaded: \(profile.fullName.isEmpty ? profile.email : profile.fullName)")
        }
    }
    
    // Email/Password ile giriş - ülke kontrolü ile
    func signIn(email: String, password: String, selectedCountryCode: String? = nil, completion: @escaping (Bool) -> Void) {
        // If country validation is needed, set flag to prevent auth state listener from triggering
        if selectedCountryCode != nil {
            isValidatingCountry = true
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isValidatingCountry = false
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                guard let user = result?.user else {
                    self?.isValidatingCountry = false
                    completion(false)
                    return
                }
                
                // Eğer ülke kontrolü gerekiyorsa, önce profili kontrol et
                if let countryCode = selectedCountryCode {
                    self?.validateUserCountry(uid: user.uid, selectedCountryCode: countryCode) { isValid in
                        self?.isValidatingCountry = false
                        
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
                    self?.isValidatingCountry = false
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
        
        // Clear secure storage
        _ = SecureStorageManager.shared.clearAll()
        
        try? Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUser = nil
        self.userProfile = nil
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
                LogManager.shared.error("Token refresh failed", error: error)
                Crashlytics.crashlytics().record(error: error)
                self.errorMessage = "Session expired. Please sign in again."
                
                // Check if user needs to re-authenticate
                if let authError = error as NSError?,
                   authError.code == AuthErrorCode.userTokenExpired.rawValue ||
                   authError.code == AuthErrorCode.invalidUserToken.rawValue {
                    // Token is invalid, sign out user
                    LogManager.shared.warning("Invalid token, signing out user...")
                    self.signOut()
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
