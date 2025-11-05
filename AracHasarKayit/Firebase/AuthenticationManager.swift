import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct UserProfile: Codable {
    var uid: String
    var email: String
    var firstName: String
    var lastName: String
    var createdAt: Date
    
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
        print("🔄 Loading user profile for uid: \(uid)")
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("❌ Error loading user profile: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data() else {
                print("⚠️ No user profile data found for uid: \(uid)")
                return
            }
            
            // Manually extract fields to avoid Timestamp serialization issues
            guard let email = data["email"] as? String,
                  let firstName = data["firstName"] as? String,
                  let lastName = data["lastName"] as? String else {
                print("❌ Missing required user profile fields")
                return
            }
            
            // Convert Firestore Timestamp to Date
            let createdAt: Date
            if let timestamp = data["createdAt"] as? Timestamp {
                createdAt = timestamp.dateValue()
            } else {
                createdAt = Date() // Fallback to current date
            }
            
            let profile = UserProfile(
                uid: uid,
                email: email,
                firstName: firstName,
                lastName: lastName,
                createdAt: createdAt
            )
            
            DispatchQueue.main.async {
                self?.userProfile = profile
                print("✅ User profile loaded: \(profile.fullName)")
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
                    createdAt: Date()
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
                    print("Error saving user profile: \(error)")
                    completion(false)
                } else {
                    print("✅ User profile saved successfully")
                    completion(true)
                }
            }
        } catch {
            print("Error encoding user profile: \(error)")
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
                print("✅ Token is valid: \(token.prefix(20))...")
            } catch {
                print("⚠️ Token refresh check failed: \(error.localizedDescription)")
                
                // Check if token is expired or invalid
                if let authError = error as NSError?,
                   authError.code == AuthErrorCode.userTokenExpired.rawValue {
                    print("❌ Token expired, attempting refresh...")
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
            await MainActor.run {
                print("✅ Token refreshed successfully: \(token.prefix(20))...")
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                print("❌ Token refresh failed: \(error.localizedDescription)")
                self.errorMessage = "Session expired. Please sign in again."
                
                // Check if user needs to re-authenticate
                if let authError = error as NSError?,
                   authError.code == AuthErrorCode.userTokenExpired.rawValue ||
                   authError.code == AuthErrorCode.invalidUserToken.rawValue {
                    // Token is invalid, sign out user
                    print("⚠️ Invalid token, signing out user...")
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
                    print("❌ Re-authentication failed: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                } else {
                    print("✅ Re-authentication successful")
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
