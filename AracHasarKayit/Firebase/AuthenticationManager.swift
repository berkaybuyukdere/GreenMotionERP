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
    
    init() {
        checkAuthStatus()
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
        try? Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUser = nil
        self.userProfile = nil
    }
}
