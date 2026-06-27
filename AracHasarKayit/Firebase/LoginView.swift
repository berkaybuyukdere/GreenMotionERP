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
    @State private var selectedCountry: Country = UserDefaults.standard.hasPersistedCountrySelection
        ? UserDefaults.standard.selectedCountry
        : CountryManager.defaultCountry
    @State private var hasExplicitCountrySelection: Bool = UserDefaults.standard.hasPersistedCountrySelection
        && !AppSessionGate.requiresFreshLoginSelection
    @State private var showCountryPicker = false
    @State private var loginFranchises: [LoginFranchiseOption] = []
    @State private var selectedFranchiseId: String = ""
    @State private var isLoadingFranchises = false
    @State private var franchiseLoadError: String?
    @State private var showFranchisePicker = false
    @State private var showPasswordResetSheet = false
    /// Ignores stale franchise list responses when the user changes country quickly.
    @State private var franchiseLoadGeneration = 0
    
    /// Same gate as sign-in: country + franchise must be chosen when multiple locations exist.
    private var loginFranchiseGateOk: Bool {
        guard hasExplicitCountrySelection else { return false }
        if isLoadingFranchises { return false }
        if franchiseLoadError != nil { return false }
        if loginFranchises.isEmpty { return false }
        if loginFranchises.count > 1 {
            return !selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    
    /// Palantir login chrome when Switzerland country or CH franchise is selected.
    private var isCHLoginContext: Bool {
        if selectedCountry.countryCode.uppercased() == "CH" { return true }
        let fid = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !fid.isEmpty, FranchiseCapabilityMatrix.isSwitzerland(franchiseId: fid) { return true }
        return false
    }
    
    var body: some View {
        ZStack {
            PalantirWireframeBackground()
            
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
                        hasExplicitCountrySelection: $hasExplicitCountrySelection,
                        showCountryPicker: $showCountryPicker,
                        loginFranchises: loginFranchises,
                        selectedFranchiseId: $selectedFranchiseId,
                        isLoadingFranchises: isLoadingFranchises,
                        franchiseLoadError: franchiseLoadError,
                        isLoading: isLoading,
                        shakeAnimation: shakeAnimation,
                        colorScheme: colorScheme,
                        palantirMode: true,
                        authManager: authManager,
                        onAuth: handleAuth,
                        onCountrySelected: loadFranchisesForSelectedCountry,
                        onForgotPassword: { showPasswordResetSheet = true }
                    )
                    .padding(.horizontal, 30)
                    Spacer().frame(height: 40)
                }
            }
        }
        .sheet(isPresented: $showPasswordResetSheet) {
            PasswordResetSheet(
                initialEmail: email,
                isPresented: $showPasswordResetSheet
            )
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .environment(\.palantirModeEnabled, true)
        .tint(PalantirTheme.accent)
        .onAppear {
            loadRememberedCredentialsIfNeeded()
            if AppSessionGate.requiresFreshLoginSelection || !UserDefaults.standard.hasPersistedCountrySelection {
                hasExplicitCountrySelection = false
                selectedCountry = CountryManager.defaultCountry
                selectedFranchiseId = ""
                loginFranchises = []
            } else {
                hasExplicitCountrySelection = true
                loadFranchisesForSelectedCountry()
            }
            withAnimation(.easeOut(duration: 0.5)) { showX = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 1.0)) { erpOpacity = 1.0 }
            }
        }
        .onChange(of: selectedCountry.id) { _, _ in
            guard hasExplicitCountrySelection else { return }
            loadFranchisesForSelectedCountry()
        }
        .onChange(of: selectedFranchiseId) { _, _ in
            sanitizeSelectedFranchiseForCurrentCountry()
            if hasExplicitCountrySelection {
                persistLoginFranchiseSelection(countryCode: selectedCountry.countryCode)
            }
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
                .foregroundColor(
                    isCHLoginContext
                        ? PalantirTheme.textPrimary.opacity(erpOpacity)
                        : (colorScheme == .dark ? Color.white.opacity(erpOpacity) : Color.black.opacity(erpOpacity))
                )
                Text("X")
                    .font(.system(size: 72, weight: .bold, design: .default))
                    .foregroundColor(isCHLoginContext ? PalantirTheme.accent : (colorScheme == .dark ? .white : .black))
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
                persistLoginFranchiseSelection(countryCode: countryCode)
                if safe.isEmpty && !options.isEmpty {
                    franchiseLoadError = "No franchises available for this country".localized
                }
            case .failure(let error):
                franchiseLoadError = LoginFranchiseLoader.userFacingLoadError(error)
            }
        }
    }

    private func persistLoginFranchiseSelection(countryCode: String) {
        let fid = selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !fid.isEmpty else { return }
        UserDefaults.standard.loginSelectedFranchiseId = fid
        UserDefaults.standard.setLoginSelectedFranchiseId(fid, for: countryCode)
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

        guard hasExplicitCountrySelection else {
            franchiseLoadError = "Please select a country".localized
            return
        }

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
        persistLoginFranchiseSelection(countryCode: countryCode)

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            authManager.errorMessage = "Enter your password before signing in.".localized
            return
        }

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
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: trimmedPassword,
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
    @Binding var hasExplicitCountrySelection: Bool
    @Binding var showCountryPicker: Bool
    var loginFranchises: [LoginFranchiseOption]
    @Binding var selectedFranchiseId: String
    var isLoadingFranchises: Bool
    var franchiseLoadError: String?
    var isLoading: Bool
    var shakeAnimation: Bool
    var colorScheme: ColorScheme
    var palantirMode: Bool = false
    @ObservedObject var authManager: AuthenticationManager
    var onAuth: () -> Void
    var onCountrySelected: () -> Void = {}
    var onForgotPassword: (() -> Void)? = nil
    @State private var showFranchisePicker = false
    
    private var franchiseGateSatisfied: Bool {
        guard hasExplicitCountrySelection else { return false }
        if isLoadingFranchises { return false }
        if franchiseLoadError != nil { return false }
        if loginFranchises.isEmpty { return false }
        if loginFranchises.count > 1 {
            return !selectedFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
    
    private var labelColor: Color {
        palantirMode ? PalantirTheme.textPrimary : (colorScheme == .dark ? .white : .primary)
    }
    private var fieldTextColor: Color {
        palantirMode ? PalantirTheme.textPrimary : (colorScheme == .dark ? .white : .primary)
    }
    private var placeholderColor: Color {
        palantirMode ? PalantirTheme.textMuted : (colorScheme == .dark ? Color.white.opacity(0.7) : .secondary)
    }
    private var iconColor: Color {
        palantirMode ? PalantirTheme.textMuted : (colorScheme == .dark ? Color.white.opacity(0.8) : .secondary)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back".localized)
                .font(palantirMode ? PalantirTheme.labelFont(14) : .system(size: 24, weight: .bold))
                .foregroundColor(labelColor)
                .padding(.bottom, 8)
            
            countryField
            franchiseField
            emailField
            passwordField
            rememberMeToggle
            if let onForgot = onForgotPassword {
                Button(action: onForgot) {
                    Text("Forgot password".localized)
                        .font(palantirMode ? PalantirTheme.labelFont(10) : .caption)
                        .foregroundColor(palantirMode ? PalantirTheme.accent : .blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if let error = authManager.errorMessage {
                Text(error)
                    .font(palantirMode ? PalantirTheme.labelFont(10) : .caption)
                    .foregroundColor(palantirMode ? PalantirTheme.critical : .red)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        palantirMode
                            ? PalantirTheme.critical.opacity(0.1)
                            : (colorScheme == .dark ? Color.white.opacity(0.9) : Color.red.opacity(0.1))
                    )
                    .overlay(
                        Group {
                            if palantirMode {
                                Rectangle().stroke(PalantirTheme.critical.opacity(0.35), lineWidth: 1)
                            }
                        }
                    )
                    .shake(shakeAnimation: shakeAnimation)
            }
            signInButton
        }
        .padding(palantirMode ? 16 : 24)
        .background(cardBackground)
        .overlay(
            Group {
                if palantirMode {
                    Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: palantirMode ? 6 : 24))
        .shadow(color: palantirMode ? .clear : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)), radius: palantirMode ? 0 : (colorScheme == .dark ? 20 : 16), x: 0, y: palantirMode ? 0 : (colorScheme == .dark ? 10 : 6))
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
                    .font(.system(size: palantirMode ? 17 : 22, weight: .semibold))
                    .foregroundColor(rememberMe ? (palantirMode ? PalantirTheme.accent : .blue) : iconColor)
                Text("Remember me".localized)
                    .font(palantirMode ? PalantirTheme.bodyFont(13) : .subheadline)
                    .foregroundColor(labelColor)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(palantirMode ? PalantirTheme.labelFont(10) : .subheadline.weight(.semibold))
            .foregroundColor(palantirMode ? PalantirTheme.textMuted : labelColor)
    }
    
    private var countryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Country".localized)
            Button(action: { showCountryPicker = true }) {
                HStack {
                    if hasExplicitCountrySelection {
                        Text(selectedCountry.flag)
                            .font(.system(size: 28))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 22))
                            .foregroundColor(iconColor)
                    }
                    Text(hasExplicitCountrySelection ? selectedCountry.name : "Select country".localized)
                        .font(palantirMode ? PalantirTheme.bodyFont(14) : .body)
                        .foregroundColor(hasExplicitCountrySelection ? fieldTextColor : placeholderColor)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(iconColor)
                }
                .padding(palantirMode ? 11 : 16)
                .background(textFieldBackground)
                .overlay(palantirFieldBorder)
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(
                    selectedCountry: $selectedCountry,
                    hasExplicitCountrySelection: $hasExplicitCountrySelection,
                    isPresented: $showCountryPicker,
                    onCountryChosen: onCountrySelected
                )
            }
        }
    }
    
    private var franchiseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Franchise".localized)
            if !hasExplicitCountrySelection {
                Text("Select country first".localized)
                    .font(palantirMode ? PalantirTheme.bodyFont(12) : .caption)
                    .foregroundColor(placeholderColor)
                    .padding(palantirMode ? 11 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textFieldBackground)
                    .overlay(palantirFieldBorder)
            } else if isLoadingFranchises {
                HStack {
                    ProgressView()
                    Text("Loading locations…".localized)
                        .font(palantirMode ? PalantirTheme.bodyFont(12) : .caption)
                        .foregroundColor(labelColor.opacity(0.85))
                }
                .padding(palantirMode ? 11 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(textFieldBackground)
                .overlay(palantirFieldBorder)
            } else if let err = franchiseLoadError, !err.isEmpty {
                Text(err)
                    .font(palantirMode ? PalantirTheme.labelFont(10) : .caption)
                    .foregroundColor(palantirMode ? PalantirTheme.critical : .red)
                    .padding(palantirMode ? 11 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textFieldBackground)
                    .overlay(palantirFieldBorder)
            } else if loginFranchises.isEmpty {
                Text("No active franchise for this country.".localized)
                    .font(palantirMode ? PalantirTheme.bodyFont(12) : .caption)
                    .foregroundColor(palantirMode ? PalantirTheme.warning : .orange)
                    .padding(palantirMode ? 11 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textFieldBackground)
                    .overlay(palantirFieldBorder)
            } else if loginFranchises.count == 1, let one = loginFranchises.first {
                HStack(spacing: 10) {
                    Text(one.flag).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(one.displayName).foregroundColor(fieldTextColor).font(palantirMode ? PalantirTheme.bodyFont(14) : .body)
                        Text(one.franchiseId).font(palantirMode ? PalantirTheme.dataFont(11) : .caption).foregroundColor(placeholderColor)
                    }
                    Spacer()
                }
                .padding(palantirMode ? 11 : 16)
                .background(textFieldBackground)
                .overlay(palantirFieldBorder)
            } else {
                Button {
                    showFranchisePicker = true
                } label: {
                    HStack {
                        if let sel = loginFranchises.first(where: { $0.franchiseId == selectedFranchiseId }) {
                            Text(sel.flag).font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sel.displayName).foregroundColor(fieldTextColor)
                                Text(sel.franchiseId).font(palantirMode ? PalantirTheme.dataFont(11) : .caption).foregroundColor(placeholderColor)
                            }
                        } else {
                            Text("Select franchise".localized).foregroundColor(placeholderColor)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").foregroundColor(iconColor)
                    }
                    .padding(palantirMode ? 11 : 16)
                    .background(textFieldBackground)
                    .overlay(palantirFieldBorder)
                }
                .sheet(isPresented: $showFranchisePicker) {
                    FranchisePickerSheet(
                        options: loginFranchises,
                        countryCode: selectedCountry.countryCode,
                        selectedFranchiseId: $selectedFranchiseId,
                        isPresented: $showFranchisePicker
                    )
                }
            }
        }
    }
    
    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("E-posta".localized)
            TextField("ornek@email.com".localized, text: $email)
                .font(palantirMode ? PalantirTheme.dataFont(14) : .body)
                .foregroundColor(fieldTextColor)
                .padding(palantirMode ? 11 : 16)
                .background(textFieldBackground)
                .overlay(palantirFieldBorder)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .autocorrectionDisabled()
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Şifre".localized)
            HStack {
                Group {
                    if showPassword {
                        TextField("En az 6 karakter".localized, text: $password)
                            .textContentType(.password)
                    } else {
                        SecureField("En az 6 karakter".localized, text: $password)
                            .textContentType(.password)
                    }
                }
                .font(palantirMode ? PalantirTheme.dataFont(14) : .body)
                .foregroundColor(fieldTextColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill").foregroundColor(iconColor)
                }
            }
            .padding(palantirMode ? 11 : 16)
            .background(textFieldBackground)
            .overlay(palantirFieldBorder)
        }
    }
    
    @ViewBuilder private var palantirFieldBorder: some View {
        if palantirMode {
            Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
        }
    }
    
    @ViewBuilder private var textFieldBackground: some View {
        if palantirMode {
            PalantirTheme.background.opacity(0.55)
        } else if colorScheme == .dark {
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
        Group {
            if palantirMode {
                WheelSysPalantirPrimaryButton(
                    title: "Giriş Yap".localized,
                    icon: "arrow.right.circle.fill",
                    isLoading: isLoading,
                    disabled: isLoading
                        || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !franchiseGateSatisfied
                ) {
                    onAuth()
                }
                .padding(.top, 8)
            } else {
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
                .disabled(
                    isLoading
                    || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !franchiseGateSatisfied
                )
                .padding(.top, 8)
            }
        }
    }
    
    @ViewBuilder private var cardBackground: some View {
        if palantirMode {
            PalantirTheme.surface
        } else if colorScheme == .dark {
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

// MARK: - Email-only password reset
private struct PasswordResetSheet: View {
    private static let functionsRegion = "us-central1"

    @State private var email: String
    @Binding var isPresented: Bool
    @State private var busyPassword = false
    @State private var message: String?

    init(
        initialEmail: String,
        isPresented: Binding<Bool>
    ) {
        _email = State(initialValue: initialEmail)
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                WheelSysPalantirStatusStrip(
                    icon: "envelope.badge",
                    message: "Enter your account email and we will send a password reset link.",
                    tint: PalantirTheme.accent
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email".localized.uppercased())
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                    TextField("ornek@email.com".localized, text: $email)
                        .font(PalantirTheme.dataFont(14))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(11)
                        .background(PalantirTheme.background.opacity(0.55))
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }

                if let message {
                    Text(message)
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WheelSysPalantirPrimaryButton(
                    title: "Send password reset link".localized,
                    icon: "paperplane.fill",
                    isLoading: busyPassword,
                    disabled: busyPassword
                ) {
                    sendPasswordReset()
                }
            }
            .padding(16)
            .background(PalantirTheme.background)
            .navigationTitle("Forgot password".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
        .environment(\.palantirModeEnabled, true)
        .tint(PalantirTheme.accent)
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

}

struct FranchisePickerSheet: View {
    let options: [LoginFranchiseOption]
    let countryCode: String
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
                    let fid = option.franchiseId.uppercased()
                    selectedFranchiseId = fid
                    UserDefaults.standard.loginSelectedFranchiseId = fid
                    UserDefaults.standard.setLoginSelectedFranchiseId(fid, for: countryCode)
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
    @Binding var hasExplicitCountrySelection: Bool
    @Binding var isPresented: Bool
    var onCountryChosen: () -> Void = {}
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
                    hasExplicitCountrySelection = true
                    UserDefaults.standard.selectedCountryId = country.id
                    isPresented = false
                    onCountryChosen()
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
                        
                        if hasExplicitCountrySelection && country.id == selectedCountry.id {
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
