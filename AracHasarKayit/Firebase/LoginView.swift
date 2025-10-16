import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Yeşil gradient arka plan
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.05, green: 0.5, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    Spacer()
                        .frame(height: 60)
                    
                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                        
                        Text("Green Motion AG")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(.white)
                            .tracking(2)
                        
                        Text("Zurich")
                            .font(.system(size: 18, weight: .thin))
                            .foregroundColor(.white.opacity(0.8))
                            .tracking(4)
                    }
                    .padding(.bottom, 40)
                    
                    // Form
                    VStack(spacing: 16) {
                        // First Name Field (only for sign up)
                        if isSignUp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("İsim")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                TextField("", text: $firstName)
                                    .placeholder(when: firstName.isEmpty) {
                                        Text("İsim")
                                            .foregroundColor(.gray)
                                    }
                                    .foregroundColor(.black)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .textContentType(.givenName)
                            }
                            
                            // Last Name Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Soyisim")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                TextField("", text: $lastName)
                                    .placeholder(when: lastName.isEmpty) {
                                        Text("Soyisim")
                                            .foregroundColor(.gray)
                                    }
                                    .foregroundColor(.black)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .textContentType(.familyName)
                            }
                        }
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("E-posta")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            TextField("", text: $email)
                                .placeholder(when: email.isEmpty) {
                                    Text("ornek@email.com")
                                        .foregroundColor(.gray)
                                }
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Şifre")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            SecureField("", text: $password)
                                .placeholder(when: password.isEmpty) {
                                    Text("En az 6 karakter")
                                        .foregroundColor(.gray)
                                }
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .textContentType(.password)
                        }
                        
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(8)
                        }
                        
                        Button {
                            handleAuth()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text(isSignUp ? "Kayıt Ol" : "Giriş Yap")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        .disabled(isLoading || email.isEmpty || password.isEmpty || (isSignUp && (firstName.isEmpty || lastName.isEmpty)))
                        .padding(.top, 8)
                        
                        Button {
                            isSignUp.toggle()
                            authManager.errorMessage = nil
                        } label: {
                            Text(isSignUp ? "Zaten hesabın var mı? Giriş Yap" : "Hesabın yok mu? Kayıt Ol")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .underline()
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    Spacer()
                        .frame(height: 60)
                }
            }
        }
        .onTapGesture {
            // Klavyeyi kapat
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    func handleAuth() {
        // Klavyeyi kapat
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        isLoading = true
        
        if isSignUp {
            authManager.signUp(email: email, password: password, firstName: firstName, lastName: lastName) { success in
                isLoading = false
                if !success {
                    showError = true
                }
            }
        } else {
            authManager.signIn(email: email, password: password) { success in
                isLoading = false
                if !success {
                    showError = true
                }
            }
        }
    }
}

// Helper extension for placeholder
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
