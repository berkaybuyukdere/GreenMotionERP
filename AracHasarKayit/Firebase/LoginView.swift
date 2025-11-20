import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var isLoading = false
    @State private var showPassword = false
    @State private var shakeAnimation = false
    @State private var rememberMe = false
    @State private var showX = false
    @State private var erpOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // Background adapts to color scheme
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 80)
                    
                    // ERPX Branding with Animation
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            // ERP letters - animated opacity
                            HStack(spacing: 0) {
                                Text("E")
                                    .font(.system(size: 72, weight: .thin, design: .default))
                                Text("R")
                                    .font(.system(size: 72, weight: .thin, design: .default))
                                Text("P")
                                    .font(.system(size: 72, weight: .thin, design: .default))
                            }
                            .foregroundColor(colorScheme == .dark ? 
                                Color.white.opacity(erpOpacity) : 
                                Color.black.opacity(erpOpacity))
                            
                            // X letter - appears first
                            Text("X")
                                .font(.system(size: 72, weight: .bold, design: .default))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .opacity(showX ? 1.0 : 0.0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                    
                    // Modern Card Container with Neumorphism
                    VStack(spacing: 20) {
                        // Login/Sign Up Title
                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
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
                        
                        // Email Field with Neumorphism
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
                                .background(
                                    ZStack {
                                        Color.white
                                        Color.white.opacity(0.95)
                                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                                            .shadow(color: Color.white, radius: 5, x: 0, y: -2)
                                    }
                                )
                                .cornerRadius(16)
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
                            
                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("", text: $password)
                                    } else {
                                        SecureField("", text: $password)
                                    }
                                }
                                .placeholder(when: password.isEmpty) {
                                    Text("En az 6 karakter")
                                        .foregroundColor(.gray)
                                }
                                .foregroundColor(.black)
                                .autocapitalization(.none)
                                .textContentType(.password)
                                
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(
                                ZStack {
                                    Color.white
                                    Color.white.opacity(0.95)
                                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                                        .shadow(color: Color.white, radius: 5, x: 0, y: -2)
                                }
                            )
                            .cornerRadius(16)
                        }
                        
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(8)
                                .shake(shakeAnimation: shakeAnimation)
                        }
                        
                        // Remember Me (only for login, not sign up)
                        if !isSignUp {
                            HStack {
                                Button(action: {
                                    rememberMe.toggle()
                                }) {
                                    Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                        .foregroundColor(.white)
                                        .font(.system(size: 20))
                                }
                                
                                Text("Remember Me")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        
                        Button {
                            handleAuth()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Kayıt Ol" : "Giriş Yap")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
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
                    .padding(24)
                    .background(
                        ZStack {
                            Color.white.opacity(0.1)
                            Color.white.opacity(0.05)
                                .blur(radius: 20)
                        }
                    )
                    .cornerRadius(24)
                    .shadow(color: Color.white.opacity(0.1), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 30)
                    
                    Spacer()
                        .frame(height: 40)
                    
                    // Zurich text at bottom
                    Text("Zurich")
                        .font(.system(size: 14, weight: .light, design: .default))
                        .foregroundColor(.gray)
                        .padding(.bottom, 20)
                }
            }
        }
        .onTapGesture {
            // Klavyeyi kapat
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            // Start animation sequence
            // First show X
            withAnimation(.easeOut(duration: 0.5)) {
                showX = true
            }
            
            // Then fade in ERP letters
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 1.0)) {
                    erpOpacity = 1.0
                }
            }
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
                    // Trigger shake animation
                    withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) {
                        shakeAnimation.toggle()
                    }
                }
            }
        } else {
            authManager.signIn(email: email, password: password) { success in
                isLoading = false
                if !success {
                    showError = true
                    // Trigger shake animation
                    withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) {
                        shakeAnimation.toggle()
                    }
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
    
    func shake(shakeAnimation: Bool) -> some View {
        self.modifier(ShakeEffect(shake: shakeAnimation))
    }
}

// Shake animation modifier
struct ShakeEffect: GeometryEffect {
    var shake: Bool
    
    var animatableData: Bool {
        get { shake }
        set { shake = newValue }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = shake ? CGFloat(-10) : CGFloat(0)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
