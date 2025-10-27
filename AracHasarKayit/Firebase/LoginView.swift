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
    
    var body: some View {
        ZStack {
            // Enhanced gradient background with animated particles
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.05, green: 0.5, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Animated particles background
                AnimatedParticlesView()
            }
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
                            .background(Color.white)
                            .cornerRadius(12)
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
