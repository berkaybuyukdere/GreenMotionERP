import SwiftUI
import FirebaseAuth
import FirebaseFunctions

private enum LoginRememberKeys {
    static let rememberMeEnabled = "loginRememberMeEnabled"
}

private enum SessionTakeoverTrustStore {
    private static let trustTTL: TimeInterval = 60 * 60 * 6 // 6 hours

    private static func trustKey(email: String, countryCode: String, franchiseId: String) -> String {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let f = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "sessionTakeoverTrustedAt|\(e)|\(c)|\(f)"
    }

    static func hasValidTrust(email: String, countryCode: String, franchiseId: String) -> Bool {
        let key = trustKey(email: email, countryCode: countryCode, franchiseId: franchiseId)
        let ts = UserDefaults.standard.double(forKey: key)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < trustTTL
    }

    static func grantTrust(email: String, countryCode: String, franchiseId: String) {
        let key = trustKey(email: email, countryCode: countryCode, franchiseId: franchiseId)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showPassword = false
    @State private var shakeAnimation = false
    @State private var rememberMe = UserDefaults.standard.bool(forKey: LoginRememberKeys.rememberMeEnabled)
    @State private var showSessionTakeoverConfirm = false
    @State private var showX = false
    @State private var erpOpacity: Double = 0.0
    @State private var selectedCountry: Country = UserDefaults.standard.selectedCountry
    @State private var showCountryPicker = false
    @State private var loginFranchises: [LoginFranchiseOption] = []
    @State private var selectedFranchiseId: String = ""
    @State private var isLoadingFranchises = false
    @State private var franchiseLoadError: String?
    @State private var showFranchisePicker = false
    @State private var showUsernameRecovery = false
    /// Ignores stale franchise list responses when the user changes country quickly.
    @State private var franchiseLoadGeneration = 0
    
    /// Same gate as sign-in: country + franchise must be chosen when multiple locations exist.
    private var loginFranchiseGateOk: Bool {
        if isLoadingFranchises { return false }
        if franchiseLoadError != nil { return false }
        if loginFranchises.isEmpty { return false }
        if loginFranchises.count > 1 {
            return !selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    
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
                        showPassword: $showPassword,
                        rememberMe: $rememberMe,
                        selectedCountry: $selectedCountry,
                        showCountryPicker: $showCountryPicker,
                        loginFranchises: loginFranchises,
                        selectedFranchiseId: $selectedFranchiseId,
                        isLoadingFranchises: isLoadingFranchises,
                        franchiseLoadError: franchiseLoadError,
                        isLoading: isLoading,
                        shakeAnimation: shakeAnimation,
                        colorScheme: colorScheme,
                        authManager: authManager,
                        onAuth: handleAuth,
                        onForgotUsername: { showUsernameRecovery = true }
                    )
                    .padding(.horizontal, 30)
                    Spacer().frame(height: 40)
                }
            }
        }
        .sheet(isPresented: $showUsernameRecovery) {
            UsernameRecoverySheet(
                initialEmail: email,
                countryCode: selectedCountry.countryCode,
                franchiseHint: selectedFranchiseId,
                franchiseGateSatisfied: loginFranchiseGateOk,
                isPresented: $showUsernameRecovery
            )
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            loadRememberedCredentialsIfNeeded()
            loadFranchisesForSelectedCountry()
            withAnimation(.easeOut(duration: 0.5)) { showX = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 1.0)) { erpOpacity = 1.0 }
            }
        }
        .onChange(of: selectedCountry.id) { _, _ in
            loadFranchisesForSelectedCountry()
        }
        .onChange(of: selectedFranchiseId) { _, _ in
            sanitizeSelectedFranchiseForCurrentCountry()
        }
        .onChange(of: loginFranchises) { _, _ in
            sanitizeSelectedFranchiseForCurrentCountry()
        }
        .alert("Account already in use".localized, isPresented: $showSessionTakeoverConfirm) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Sign in anyway".localized) {
                let fid = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fid.isEmpty {
                    SessionTakeoverTrustStore.grantTrust(
                        email: email,
                        countryCode: selectedCountry.countryCode,
                        franchiseId: fid
                    )
                }
                performSignIn(forceSessionTakeover: true)
            }
        } message: {
            Text("Session takeover explanation".localized)
        }
    }
    
    private func loadRememberedCredentialsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: LoginRememberKeys.rememberMeEnabled) else { return }
        rememberMe = true
        if let savedEmail = SecureStorageManager.shared.getUserEmail() {
            email = savedEmail
        }
        if let savedPassword = SecureStorageManager.shared.getRememberedLoginPassword() {
            password = savedPassword
        }
    }
    
    private func persistRememberMePreference() {
        UserDefaults.standard.set(rememberMe, forKey: LoginRememberKeys.rememberMeEnabled)
        if rememberMe {
            _ = SecureStorageManager.shared.storeUserEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
            _ = SecureStorageManager.shared.saveRememberedLoginPassword(password)
        } else {
            _ = SecureStorageManager.shared.deleteUserEmail()
            _ = SecureStorageManager.shared.deleteRememberedLoginPassword()
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
            if isSabihaGokcenFranchiseSelected {
                USaveMiniLogoView(size: CGSize(width: 108, height: 38))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    private var isSabihaGokcenFranchiseSelected: Bool {
        let normalized = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.contains("SABIHA") || normalized.contains("SAW")
    }
    
    func handleAuth() {
        performSignIn(forceSessionTakeover: false)
    }
    
    private func loadFranchisesForSelectedCountry() {
        franchiseLoadGeneration += 1
        let generation = franchiseLoadGeneration
        let countryCode = selectedCountry.countryCode

        franchiseLoadError = nil
        isLoadingFranchises = true
        selectedFranchiseId = ""
        loginFranchises = []
        showFranchisePicker = false

        LoginFranchiseLoader.fetchOptions(countryCode: countryCode) { result in
            guard generation == franchiseLoadGeneration else { return }

            isLoadingFranchises = false
            switch result {
            case .success(let options):
                let safe = LoginFranchiseCountryGuard.filterOptions(options, countryCode: countryCode)
                loginFranchises = safe
                let savedForCountry = UserDefaults.standard.loginSelectedFranchiseId(for: countryCode)
                selectedFranchiseId = LoginFranchiseCountryGuard.resolveInitialSelection(
                    options: safe,
                    countryCode: countryCode,
                    savedFranchiseId: savedForCountry
                )
                if safe.isEmpty && !options.isEmpty {
                    franchiseLoadError = "No franchises available for this country".localized
                }
            case .failure(let error):
                franchiseLoadError = LoginFranchiseLoader.userFacingLoadError(error)
            }
        }
    }

    private func sanitizeSelectedFranchiseForCurrentCountry() {
        let countryCode = selectedCountry.countryCode
        let fid = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fid.isEmpty else { return }
        let allowed = loginFranchises.contains { $0.franchiseId == fid.uppercased() }
            && LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                franchiseId: fid,
                documentCountryCode: nil,
                selectedCountryCode: countryCode
            )
        if !allowed {
            selectedFranchiseId = LoginFranchiseCountryGuard.resolveInitialSelection(
                options: loginFranchises,
                countryCode: countryCode,
                savedFranchiseId: nil
            )
        }
    }
    
    private func performSignIn(forceSessionTakeover: Bool) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        HapticManager.shared.medium()

        sanitizeSelectedFranchiseForCurrentCountry()

        let countryCode = selectedCountry.countryCode
        let trimmedFranchise = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFranchise.isEmpty,
           !LoginFranchiseCountryGuard.franchiseBelongsToCountry(
               franchiseId: trimmedFranchise,
               documentCountryCode: nil,
               selectedCountryCode: countryCode
           ) {
            franchiseLoadError = "Invalid franchise for selected country".localized
            return
        }
        if loginFranchises.count > 1,
           !loginFranchises.contains(where: { $0.franchiseId == trimmedFranchise.uppercased() }) {
            franchiseLoadError = "Please select a franchise".localized
            return
        }

        UserDefaults.standard.selectedCountryId = selectedCountry.id

        isLoading = true
        let franchiseForSignIn: String? = {
            let trimmed = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.uppercased()
        }()
        let trustedTakeover = {
            guard let franchiseForSignIn else { return false }
            return SessionTakeoverTrustStore.hasValidTrust(
                email: email,
                countryCode: selectedCountry.countryCode,
                franchiseId: franchiseForSignIn
            )
        }()
        authManager.signIn(
            email: email,
            password: password,
            selectedCountryCode: selectedCountry.countryCode,
            selectedFranchiseId: franchiseForSignIn,
            forceSessionTakeover: forceSessionTakeover || trustedTakeover
        ) { result in
            isLoading = false
            switch result {
            case .success:
                persistRememberMePreference()
            case .failed:
                withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) {
                    shakeAnimation.toggle()
                }
            case .activeSessionElsewhere:
                showSessionTakeoverConfirm = true
            }
        }
    }
}

// MARK: - Login Form Card (extracted for compiler type-check)
private struct LoginFormCard: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var rememberMe: Bool
    @Binding var selectedCountry: Country
    @Binding var showCountryPicker: Bool
    var loginFranchises: [LoginFranchiseOption]
    @Binding var selectedFranchiseId: String
    var isLoadingFranchises: Bool
    var franchiseLoadError: String?
    var isLoading: Bool
    var shakeAnimation: Bool
    var colorScheme: ColorScheme
    @ObservedObject var authManager: AuthenticationManager
    var onAuth: () -> Void
    var onForgotUsername: (() -> Void)? = nil
    @State private var showFranchisePicker = false
    
    private var franchiseGateSatisfied: Bool {
        if isLoadingFranchises { return false }
        if franchiseLoadError != nil { return false }
        if loginFranchises.isEmpty { return false }
        if loginFranchises.count > 1 {
            return !selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    
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
            
            countryField
            franchiseField
            emailField
            passwordField
            rememberMeToggle
            if let onForgot = onForgotUsername {
                Button(action: onForgot) {
                    Text("Forgot username")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
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
            signInButton
        }
        .padding(24)
        .background(cardBackground)
        .cornerRadius(24)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), radius: colorScheme == .dark ? 20 : 16, x: 0, y: colorScheme == .dark ? 10 : 6)
        .onChange(of: rememberMe) { _, newValue in
            if !newValue {
                UserDefaults.standard.set(false, forKey: LoginRememberKeys.rememberMeEnabled)
                _ = SecureStorageManager.shared.deleteUserEmail()
                _ = SecureStorageManager.shared.deleteRememberedLoginPassword()
            }
        }
    }
    
    private var rememberMeToggle: some View {
        Button {
            rememberMe.toggle()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(rememberMe ? .blue : iconColor)
                Text("Remember me".localized)
                    .font(.subheadline)
                    .foregroundColor(labelColor)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var countryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Country".localized).font(.subheadline).fontWeight(.semibold).foregroundColor(labelColor)
            Button(action: { showCountryPicker = true }) {
                HStack {
                    Text(selectedCountry.flag)
                        .font(.system(size: 28))
                    
                    Text(selectedCountry.name)
                        .foregroundColor(fieldTextColor)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(iconColor)
                }
                .padding()
                .background(textFieldBackground)
                .cornerRadius(16)
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
            }
        }
    }
    
    private var franchiseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Franchise".localized).font(.subheadline).fontWeight(.semibold).foregroundColor(labelColor)
            if isLoadingFranchises {
                HStack {
                    ProgressView()
                    Text("Loading locations…".localized).font(.caption).foregroundColor(labelColor.opacity(0.85))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(textFieldBackground)
                .cornerRadius(16)
            } else if let err = franchiseLoadError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textFieldBackground)
                    .cornerRadius(16)
            } else if loginFranchises.isEmpty {
                Text("No active franchise for this country.".localized)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textFieldBackground)
                    .cornerRadius(16)
            } else if loginFranchises.count == 1, let one = loginFranchises.first {
                HStack(spacing: 10) {
                    Text(one.flag).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(one.displayName).foregroundColor(fieldTextColor).font(.body)
                        Text(one.franchiseId).font(.caption).foregroundColor(placeholderColor)
                    }
                    Spacer()
                }
                .padding()
                .background(textFieldBackground)
                .cornerRadius(16)
            } else {
                Button {
                    showFranchisePicker = true
                } label: {
                    HStack {
                        if let sel = loginFranchises.first(where: { $0.franchiseId == selectedFranchiseId }) {
                            Text(sel.flag).font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sel.displayName).foregroundColor(fieldTextColor)
                                Text(sel.franchiseId).font(.caption).foregroundColor(placeholderColor)
                            }
                        } else {
                            Text("Select franchise".localized).foregroundColor(placeholderColor)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").foregroundColor(iconColor)
                    }
                    .padding()
                    .background(textFieldBackground)
                    .cornerRadius(16)
                }
                .sheet(isPresented: $showFranchisePicker) {
                    FranchisePickerSheet(
                        options: loginFranchises,
                        selectedFranchiseId: $selectedFranchiseId,
                        isPresented: $showFranchisePicker
                    )
                }
            }
        }
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
        .disabled(isLoading || email.isEmpty || password.isEmpty || !franchiseGateSatisfied)
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

// MARK: - Forgot username + password reset (callable region must match backend)
private struct UsernameRecoverySheet: View {
    private static let functionsRegion = "us-central1"

    @State private var email: String
    let countryCode: String
    let franchiseHint: String
    let franchiseGateSatisfied: Bool
    @Binding var isPresented: Bool
    @State private var busyReminder = false
    @State private var busyPassword = false
    @State private var message: String?
    @Environment(\.colorScheme) private var colorScheme

    init(
        initialEmail: String,
        countryCode: String,
        franchiseHint: String,
        franchiseGateSatisfied: Bool,
        isPresented: Binding<Bool>
    ) {
        _email = State(initialValue: initialEmail)
        self.countryCode = countryCode
        self.franchiseHint = franchiseHint
        self.franchiseGateSatisfied = franchiseGateSatisfied
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Username reminder uses the country and franchise you chose above. Password reset only needs your email.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .padding(12)
                        .background(fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        sendReminder()
                    } label: {
                        HStack {
                            Spacer()
                            if busyReminder {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Email username reminder")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busyReminder || busyPassword || !franchiseGateSatisfied)

                    Button {
                        sendPasswordReset()
                    } label: {
                        HStack {
                            Spacer()
                            if busyPassword {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Text("Send password reset link")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busyReminder || busyPassword)

                    Text(
                        "ERPX-branded reset needs SMTP on Cloud Functions. If not configured, you get Firebase’s default email (subject/body may show the project id—set Firebase Project settings → General → Public-facing name to ERPX to improve that). Check Spam or Junk."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
            .navigationTitle("Forgot username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color(.systemGray6)
    }

    private func sendReminder() {
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard em.contains("@") else {
            message = "Enter a valid email."
            return
        }
        guard franchiseGateSatisfied else {
            message = "Select country and franchise on the login screen first."
            return
        }
        busyReminder = true
        message = nil
        var payload: [String: Any] = [
            "email": em,
            "countryCode": countryCode.uppercased(),
        ]
        let hint = franchiseHint.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !hint.isEmpty {
            payload["franchiseHint"] = hint
        }
        let callable = Functions.functions(region: Self.functionsRegion).httpsCallable("startUsernameRecovery")
        callable.call(payload) { _, error in
            DispatchQueue.main.async {
                busyReminder = false
                if let error {
                    message = Self.mapCallableError(error)
                } else {
                    isPresented = false
                }
            }
        }
    }

    private func sendPasswordReset() {
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard em.contains("@") else {
            message = "Enter a valid email."
            return
        }
        busyPassword = true
        message = nil
        let callable = Functions.functions(region: Self.functionsRegion).httpsCallable("sendCustomPasswordResetEmail")
        callable.call(["email": em]) { _, error in
            DispatchQueue.main.async {
                if let error {
                    if Self.shouldFallbackPasswordResetFromCallable(error) {
                        Auth.auth().sendPasswordReset(withEmail: em) { authError in
                            DispatchQueue.main.async {
                                busyPassword = false
                                if let authError {
                                    message = authError.localizedDescription
                                } else {
                                    isPresented = false
                                }
                            }
                        }
                    } else {
                        busyPassword = false
                        message = Self.mapPasswordResetCallableError(error)
                    }
                } else {
                    busyPassword = false
                    isPresented = false
                }
            }
        }
    }

    /// Match web `App.js`: use Firebase default reset only when branded path is unavailable.
    private static func shouldFallbackPasswordResetFromCallable(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        if ns.code == FunctionsErrorCode.notFound.rawValue { return true }
        if ns.code == FunctionsErrorCode.failedPrecondition.rawValue {
            let reason = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String) ?? ""
            let combined = (ns.localizedDescription + " " + reason).lowercased()
            return combined.contains("smtp_not_configured")
        }
        return false
    }

    private static func mapPasswordResetCallableError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, ns.code == FunctionsErrorCode.notFound.rawValue {
            return "Recovery service is not available. Check for an app update, or try again later."
        }
        return ns.localizedDescription
    }

    private static func mapCallableError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, ns.code == FunctionsErrorCode.notFound.rawValue {
            return "Recovery service is not available. Check for an app update, or try again later."
        }
        return ns.localizedDescription
    }
}

struct FranchisePickerSheet: View {
    let options: [LoginFranchiseOption]
    @Binding var selectedFranchiseId: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""

    private var filteredOptions: [LoginFranchiseOption] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) ||
            $0.franchiseId.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationView {
            List(filteredOptions) { option in
                Button {
                    selectedFranchiseId = option.franchiseId
                    isPresented = false
                } label: {
                    HStack(spacing: 12) {
                        Text(option.flag)
                            .font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .foregroundColor(.primary)
                            Text(option.franchiseId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if option.franchiseId == selectedFranchiseId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Search franchise".localized)
            .navigationTitle("Select Franchise".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        isPresented = false
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

// MARK: - Country Picker Sheet
struct CountryPickerSheet: View {
    @Binding var selectedCountry: Country
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""
    
    private var filteredCountries: [Country] {
        if searchText.isEmpty {
            return CountryManager.allCountries
        }
        return CountryManager.allCountries.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.countryCode.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            List(filteredCountries) { country in
                Button(action: {
                    selectedCountry = country
                    isPresented = false
                }) {
                    HStack(spacing: 16) {
                        Text(country.flag)
                            .font(.system(size: 32))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(country.countryCode)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if country.id == selectedCountry.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Select Country".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        isPresented = false
                    }
                }
            }
        }
    }
}
