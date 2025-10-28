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
    @State private var showPassword = false
    @State private var shakeAnimation = false
    @State private var rememberMe = false
    
    var body: some View {
        ZStack {
            // Modern gradient background with animated particles
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.7, blue: 0.3),
                        Color(red: 0.08, green: 0.6, blue: 0.25),
                        Color(red: 0.05, green: 0.5, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Animated particles background
                AnimatedParticlesView()
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 60)
                    
                    // Enhanced Logo with Shadow
                    VStack(spacing: 12) {
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 140, height: 140)
                                .blur(radius: 20)
                            
                            // Logo circle with gradient
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "car.fill")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 6) {
                            Text("Green Motion AG")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Text("Zurich, Switzerland")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                        }
                    }
                    .padding(.bottom, 20)
                    
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
                            Color.white.opacity(0.15)
                            Color.white.opacity(0.05)
                                .blur(radius: 20)
                        }
                    )
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
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

// Animated particles background
struct AnimatedParticlesView: View {
    @State private var particles: [Particle] = []
    
    struct Particle {
        var position: CGPoint
        var opacity: Double
        var speed: Double
    }
    
    init() {
        var tempParticles: [Particle] = []
        for _ in 0..<20 {
            tempParticles.append(Particle(
                position: CGPoint(x: Double.random(in: 0...400), y: Double.random(in: 0...800)),
                opacity: Double.random(in: 0.1...0.3),
                speed: Double.random(in: 0.5...2.0)
            ))
        }
        _particles = State(initialValue: tempParticles)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<particles.count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(particles[index].opacity))
                    .frame(width: 4, height: 4)
                    .position(
                        x: CGFloat(particles[index].position.x.truncatingRemainder(dividingBy: geometry.size.width)),
                        y: CGFloat((particles[index].position.y + particles[index].speed).truncatingRemainder(dividingBy: geometry.size.height))
                    )
                    .animation(.linear(duration: 10).repeatForever(autoreverses: false), value: particles[index].position.y)
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
