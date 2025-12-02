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
    var totalPoints: Int = 0
    var activityStats: ActivityStats = ActivityStats()
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

struct ActivityStats: Codable {
    var damageRecords: Int = 0
    var returnOperations: Int = 0
    var checkOutOperations: Int = 0
    var officeOperations: Int = 0
    var vehicleRecords: Int = 0
    
    var totalActivities: Int {
        damageRecords + returnOperations + checkOutOperations + officeOperations + vehicleRecords
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
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                LogManager.shared.error("Error loading user profile: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data() else {
                LogManager.shared.warning("No user profile data found for uid: \(uid)")
                return
            }
            
            // Manually extract fields to avoid Timestamp serialization issues
            guard let email = data["email"] as? String,
                  let firstName = data["firstName"] as? String,
                  let lastName = data["lastName"] as? String else {
                LogManager.shared.error("Missing required user profile fields")
                return
            }
            
            // Convert Firestore Timestamp to Date
            let createdAt: Date
            if let timestamp = data["createdAt"] as? Timestamp {
                createdAt = timestamp.dateValue()
            } else {
                createdAt = Date() // Fallback to current date
            }
            
            // Extract points and activity stats (with defaults for backward compatibility)
            let totalPoints = data["totalPoints"] as? Int ?? 0
            
            // Extract activity stats from nested dictionary
            var activityStatsDict: [String: Any] = [:]
            if let stats = data["activityStats"] as? [String: Any] {
                activityStatsDict = stats
            }
            
            let activityStats = ActivityStats(
                damageRecords: activityStatsDict["damageRecords"] as? Int ?? 0,
                returnOperations: activityStatsDict["returnOperations"] as? Int ?? 0,
                checkOutOperations: activityStatsDict["checkOutOperations"] as? Int ?? 0,
                officeOperations: activityStatsDict["officeOperations"] as? Int ?? 0,
                vehicleRecords: activityStatsDict["vehicleRecords"] as? Int ?? 0
            )
            
            let profile = UserProfile(
                uid: uid,
                email: email,
                firstName: firstName,
                lastName: lastName,
                createdAt: createdAt,
                totalPoints: totalPoints,
                activityStats: activityStats
            )
            
            DispatchQueue.main.async {
                self?.userProfile = profile
                LogManager.shared.info("User profile loaded: \(profile.fullName)")
            }
        }
    }
    
    // Email/Password ile giriş
    func signIn(email: String, password: String, completion: @escaping (Bool) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                if let user = result?.user {
                    self?.currentUser = user
                    self?.isAuthenticated = true
                    
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
                    self?.loadUserProfile(uid: user.uid)
                    // Set user online after successful login
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
    
    // Yeni kullanıcı kaydı
    func signUp(email: String, password: String, firstName: String, lastName: String, completion: @escaping (Bool) -> Void) {
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
                    totalPoints: 0,
                    activityStats: ActivityStats()
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
