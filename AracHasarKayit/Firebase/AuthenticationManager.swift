import Foundation
import FirebaseAuth
import SwiftUI

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    
    init() {
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        if let user = Auth.auth().currentUser {
            self.currentUser = user
            self.isAuthenticated = true
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
                
                self?.currentUser = result?.user
                self?.isAuthenticated = true
                completion(true)
            }
        }
    }
    
    // Yeni kullanıcı kaydı
    func signUp(email: String, password: String, completion: @escaping (Bool) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                self?.currentUser = result?.user
                self?.isAuthenticated = true
                completion(true)
            }
        }
    }
    
    // Çıkış yap
    func signOut() {
        try? Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUser = nil
    }
}
