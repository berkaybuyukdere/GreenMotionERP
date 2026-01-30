import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var isLoading = false
    @State private var showPassword = false
    @State private var shakeAnimation = false
    @State private var rememberMe = false
    @State private var showX = false
    @State private var erpOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 80)
                    brandingSection
                    LoginFormCard(
                        email: $email,
                        password: $password,
                        rememberMe: $rememberMe,
                        showPassword: $showPassword,
                        isLoading: isLoading,
                        shakeAnimation: shakeAnimation,
                        colorScheme: colorScheme,
                        authManager: authManager,
                        onAuth: handleAuth
                    )
                    .padding(.horizontal, 30)
                    Spacer().frame(height: 40)
                    Text("Zurich".localized)
                        .font(.system(size: 14, weight: .light, design: .default))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                }
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { showX = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 1.0)) { erpOpacity = 1.0 }
            }
        }
    }
    
    private var brandingSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("E").font(.system(size: 72, weight: .thin, design: .default))
                    Text("R").font(.system(size: 72, weight: .thin, design: .default))
                    Text("P").font(.system(size: 72, weight: .thin, design: .default))
                }
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(erpOpacity) : Color.black.opacity(erpOpacity))
                Text("X")
                    .font(.system(size: 72, weight: .bold, design: .default))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .opacity(showX ? 1.0 : 0.0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
    
    func handleAuth() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isLoading = true
        authManager.signIn(email: email, password: password) { success in
            isLoading = false
            if !success {
                showError = true
                withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) {
                    shakeAnimation.toggle()
                }
            }
        }
    }
}

// MARK: - Login Form Card (extracted for compiler type-check)
private struct LoginFormCard: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var rememberMe: Bool
    @Binding var showPassword: Bool
    var isLoading: Bool
    var shakeAnimation: Bool
    var colorScheme: ColorScheme
    @ObservedObject var authManager: AuthenticationManager
    var onAuth: () -> Void
    
    private var labelColor: Color { colorScheme == .dark ? .white : .primary }
    private var fieldTextColor: Color { colorScheme == .dark ? .white : .primary }
    private var placeholderColor: Color { colorScheme == .dark ? Color.white.opacity(0.7) : .secondary }
    private var iconColor: Color { colorScheme == .dark ? Color.white.opacity(0.8) : .secondary }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back".localized)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(labelColor)
                .padding(.bottom, 8)
            
            emailField
            passwordField
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.white.opacity(0.9) : Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .shake(shakeAnimation: shakeAnimation)
            }
            rememberMeRow
            signInButton
        }
        .padding(24)
        .background(cardBackground)
        .cornerRadius(24)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), radius: colorScheme == .dark ? 20 : 16, x: 0, y: colorScheme == .dark ? 10 : 6)
    }
    
    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("E-posta".localized).font(.subheadline).fontWeight(.semibold).foregroundColor(labelColor)
            TextField("", text: $email)
                .placeholder(when: email.isEmpty) { Text("ornek@email.com".localized).foregroundColor(placeholderColor) }
                .foregroundColor(fieldTextColor).padding()
                .background(textFieldBackground).cornerRadius(16)
                .autocapitalization(.none).keyboardType(.emailAddress).textContentType(.emailAddress)
        }
    }
    
    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Şifre".localized).font(.subheadline).fontWeight(.semibold).foregroundColor(labelColor)
            HStack {
                Group {
                    if showPassword {
                        TextField("", text: $password)
                    } else {
                        SecureField("", text: $password)
                    }
                }
                .placeholder(when: password.isEmpty) { Text("En az 6 karakter".localized).foregroundColor(placeholderColor) }
                .foregroundColor(fieldTextColor).autocapitalization(.none).textContentType(.password)
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill").foregroundColor(iconColor)
                }
            }
            .padding().background(textFieldBackground).cornerRadius(16)
        }
    }
    
    @ViewBuilder private var textFieldBackground: some View {
        if colorScheme == .dark {
            Color.white.opacity(0.15)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        } else {
            Color(.systemGray6)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
    }
    
    private var rememberMeRow: some View {
        HStack {
            Button(action: { rememberMe.toggle() }) {
                Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                    .foregroundColor(labelColor).font(.system(size: 20))
            }
            Text("Remember Me".localized).font(.subheadline).foregroundColor(labelColor)
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var signInButton: some View {
        Button(action: onAuth) {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Giriş Yap".localized)
                    .font(.headline).foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(16)
        .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.25), radius: 10, x: 0, y: 5)
        .disabled(isLoading || email.isEmpty || password.isEmpty)
        .padding(.top, 8)
    }
    
    @ViewBuilder private var cardBackground: some View {
        if colorScheme == .dark {
            ZStack {
                Color.white.opacity(0.1)
                Color.white.opacity(0.05).blur(radius: 20)
            }
        } else {
            Color(.secondarySystemBackground)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
