import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var localization: LocalizationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("damageNotificationsEnabled") private var damageNotificationsEnabled: Bool = true
    @AppStorage("returnNotificationsEnabled") private var returnNotificationsEnabled: Bool = true
    @AppStorage("shuttleNotificationsEnabled") private var shuttleNotificationsEnabled: Bool = true
    @AppStorage("serviceReminderNotificationsEnabled") private var serviceReminderNotificationsEnabled: Bool = true
    @State private var showLogoutConfirmation = false
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var smtpUsername = ""
    @State private var smtpPassword = ""
    @State private var smtpSenderName = ""
    @State private var smtpSenderEmail = ""
    @State private var smtpUseTLS = true
    @State private var isSavingSMTP = false
    @State private var trPdfStaffSignatureDraft: UIImage?
    @State private var showTrStaffSignatureSheet = false

    private var canManageSMTP: Bool {
        authManager.userProfile?.isElevatedAdmin == true
    }

    private var isTurkeySettingsContext: Bool {
        if FirebaseService.shared.currentFranchiseId.uppercased().hasPrefix("TR") { return true }
        let cc = authManager.userProfile?.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return cc == "TR"
    }

    private var resolvedTurkeyStaffPdfDisplayName: String {
        (authManager.userProfile?.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCHSettingsContext: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    var body: some View {
        NavigationView {
            Group {
                if isCHSettingsContext {
                    palantirSettingsScroll
                } else {
                    legacySettingsForm
                }
            }
            .navigationTitle("Settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        HapticManager.shared.light()
                        dismiss()
                    }
                }
            }
            .alert("Sign Out".localized, isPresented: $showLogoutConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Sign Out".localized, role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?".localized)
            }
            .onAppear {
                // SMTP config loaded server-side only
            }
            .sheet(isPresented: $showTrStaffSignatureSheet) {
                NavigationStack {
                    SignatureCaptureView(signatureImage: $trPdfStaffSignatureDraft)
                        .navigationTitle("Draw signature".localized)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done".localized) { showTrStaffSignatureSheet = false }
                            }
                        }
                }
            }
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: isCHSettingsContext))
    }

    // MARK: - Palantir (CH session)

    private var palantirSettingsScroll: some View {
        ScrollView {
            VStack(spacing: 13) {
                palantirProfileSection
                palantirLanguageSection
                palantirAppearanceSection
                palantirNotificationsSection
                palantirAboutSection
                palantirSignOutSection
            }
            .padding(16)
        }
        .background(PalantirTheme.background)
    }

    @ViewBuilder
    private var palantirProfileSection: some View {
        WheelSysPalantirSectionCard(title: "Profile".localized, icon: "person.fill") {
            HStack(spacing: 12) {
                PalantirOpsIconTile(systemName: "person.fill", tint: PalantirTheme.accent, size: 44)
                if let profile = authManager.userProfile {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(PalantirTheme.bodyFont(14))
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text(profile.email)
                            .font(PalantirTheme.dataFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                } else if let user = authManager.currentUser {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User".localized)
                            .font(PalantirTheme.bodyFont(14))
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text(user.email ?? "Unknown".localized)
                            .font(PalantirTheme.dataFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var palantirLanguageSection: some View {
        WheelSysPalantirSectionCard(
            title: "Language".localized,
            icon: "globe",
            footer: "App language. The rest of the app will follow.".localized
        ) {
            HStack(spacing: 8) {
                ForEach(LocalizationManager.Language.allCases, id: \.self) { language in
                    let selected = localization.currentLanguage == language
                    Button {
                        localization.setLanguage(language)
                        HapticManager.shared.light()
                    } label: {
                        VStack(spacing: 6) {
                            Text(language.flagEmoji)
                                .font(.system(size: 28))
                            Text(language.displayName.uppercased())
                                .font(PalantirTheme.labelFont(9))
                                .foregroundStyle(selected ? PalantirTheme.accent : PalantirTheme.textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selected ? PalantirTheme.accent.opacity(0.12) : PalantirTheme.background.opacity(0.55))
                        .overlay(
                            Rectangle().stroke(selected ? PalantirTheme.accent : PalantirTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var palantirAppearanceSection: some View {
        WheelSysPalantirSectionCard(
            title: "Appearance".localized,
            icon: "circle.lefthalf.filled",
            footer: "Choose how the app looks. System follows your device settings.".localized
        ) {
            Picker("Appearance".localized, selection: $appearanceMode) {
                Text("System".localized).tag("system")
                Text("Light".localized).tag("light")
                Text("Dark".localized).tag("dark")
            }
            .pickerStyle(.segmented)
            .onChange(of: appearanceMode) { _, newValue in
                updateAppearance(newValue)
            }
        }
    }

    private var palantirNotificationsSection: some View {
        WheelSysPalantirSectionCard(
            title: "Notifications".localized,
            icon: "bell.fill",
            footer: notificationsEnabled
                ? "Control which types of notifications you receive.".localized
                : "Enable notifications to receive updates about damage records, returns, shuttle services, and service reminders.".localized
        ) {
            WheelSysPalantirToggleRow(label: "Enable Notifications".localized, isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, newValue in
                    if newValue { requestNotificationPermission() }
                }
            if notificationsEnabled {
                WheelSysPalantirInsetDivider()
                WheelSysPalantirToggleRow(label: "Damage Record Notifications".localized, isOn: $damageNotificationsEnabled)
                WheelSysPalantirToggleRow(label: "Return Notifications".localized, isOn: $returnNotificationsEnabled)
                WheelSysPalantirToggleRow(label: "Shuttle Notifications".localized, isOn: $shuttleNotificationsEnabled)
                WheelSysPalantirToggleRow(label: "Service Reminder Notifications".localized, isOn: $serviceReminderNotificationsEnabled)
            }
        }
    }

    private var palantirAboutSection: some View {
        WheelSysPalantirSectionCard(title: "About".localized, icon: "info.circle.fill") {
            WheelSysPalantirDataRow(
                label: "Version".localized,
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
            WheelSysPalantirDataRow(
                label: "Build".localized,
                value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            )
        }
    }

    private var palantirSignOutSection: some View {
        PalantirOpsActionButton(title: "Sign Out".localized, icon: "rectangle.portrait.and.arrow.right", style: .destructive) {
            showLogoutConfirmation = true
        }
    }

    // MARK: - Legacy (TR / DE)

    private var legacySettingsForm: some View {
        Form {
                // User Profile Section
                Section {
                    if let profile = authManager.userProfile {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(isCHSettingsContext ? PalantirTheme.accent : Color.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName)
                                    .font(.headline)
                                Text(profile.email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } else if let user = authManager.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(isCHSettingsContext ? PalantirTheme.accent : Color.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("User".localized)
                                    .font(.headline)
                                Text(user.email ?? "Unknown".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Profile".localized)
                }
                
                // Language Section (3 flags)
                Section {
                    HStack(spacing: 20) {
                        ForEach(LocalizationManager.Language.allCases, id: \.self) { language in
                            Button {
                                localization.setLanguage(language)
                            } label: {
                                VStack(spacing: 6) {
                                    Text(language.flagEmoji)
                                        .font(.system(size: 36))
                                    Text(language.displayName)
                                        .font(.caption)
                                        .foregroundColor(localization.currentLanguage == language ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(localization.currentLanguage == language ? Color.blue.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(localization.currentLanguage == language ? Color.blue : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("Language".localized)
                } footer: {
                    Text("App language. The rest of the app will follow.".localized)
                }
                
                // Appearance Section
                Section {
                    Picker("Appearance".localized, selection: $appearanceMode) {
                        Text("System".localized).tag("system")
                        Text("Light".localized).tag("light")
                        Text("Dark".localized).tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearanceMode) { _, newValue in
                        updateAppearance(newValue)
                    }
                } header: {
                    Text("Appearance".localized)
                } footer: {
                    Text("Choose how the app looks. System follows your device settings.".localized)
                }
                
                // Notification Settings Section
                Section {
                    Toggle("Enable Notifications".localized, isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            if newValue {
                                requestNotificationPermission()
                            }
                        }
                    
                    if notificationsEnabled {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Toggle("Damage Record Notifications".localized, isOn: $damageNotificationsEnabled)
                        Toggle("Return Notifications".localized, isOn: $returnNotificationsEnabled)
                        Toggle("Shuttle Notifications".localized, isOn: $shuttleNotificationsEnabled)
                        Toggle("Service Reminder Notifications".localized, isOn: $serviceReminderNotificationsEnabled)
                    }
                } header: {
                    Text("Notifications".localized)
                } footer: {
                    if notificationsEnabled {
                        Text("Control which types of notifications you receive.".localized)
                    } else {
                        Text("Enable notifications to receive updates about damage records, returns, shuttle services, and service reminders.".localized)
                    }
                }

                if isTurkeySettingsContext {
                    Section {
                        if let kioskURL = URL(string: CustomerFormWebLinks.frontDeskKioskURLForSession()) {
                            Link(destination: kioskURL) {
                                Label("settings.tr_kiosk.open".localized, systemImage: "display")
                            }
                        }
                        if FirebaseService.shared.currentFranchiseId
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()
                            .hasPrefix("TR_") {
                            Text(
                                CustomerFormWebLinks.frontDeskKioskURL(
                                    forTurkeyBranch: FirebaseService.shared.currentFranchiseId
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        }
                    } header: {
                        Text("settings.tr_kiosk.section".localized)
                    } footer: {
                        Text("settings.tr_kiosk.footer".localized)
                    }

                    Section {
                        NavigationLink {
                            TurkeyDocumentationListView()
                        } label: {
                            Label("tr_docs.title".localized, systemImage: "book.closed.fill")
                        }
                    } header: {
                        Text("tr_docs.settings.section".localized)
                    } footer: {
                        Text("tr_docs.settings.footer".localized)
                    }

                    Section {
                        LabeledContent("Staff name on PDF".localized) {
                            Text(resolvedTurkeyStaffPdfDisplayName.isEmpty ? "—" : resolvedTurkeyStaffPdfDisplayName)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                        Button {
                            HapticManager.shared.light()
                            showTrStaffSignatureSheet = true
                        } label: {
                            Label("Draw signature".localized, systemImage: "pencil.and.outline")
                        }
                        if let img = trPdfStaffSignatureDraft {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 120)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                Button {
                                    HapticManager.shared.light()
                                    trPdfStaffSignatureDraft = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .accessibilityLabel("Delete".localized)
                                .padding(6)
                            }
                        }
                        Button("tr_staff_signature.redraw".localized) {
                            HapticManager.shared.light()
                            showTrStaffSignatureSheet = true
                        }
                        Button("Save as template".localized) {
                            HapticManager.shared.success()
                            let profileName = resolvedTurkeyStaffPdfDisplayName
                            TurkeyStaffPdfSignatureStore.saveDisplayName(profileName.isEmpty ? nil : profileName)
                            TurkeyStaffPdfSignatureStore.saveSignatureImage(trPdfStaffSignatureDraft)
                            ToastManager.shared.show("Saved.".localized, type: .success)
                        }
                        .disabled(trPdfStaffSignatureDraft == nil)
                        Button("Remove saved signature".localized, role: .destructive) {
                            HapticManager.shared.warning()
                            trPdfStaffSignatureDraft = nil
                            TurkeyStaffPdfSignatureStore.saveSignatureImage(nil)
                            TurkeyStaffPdfSignatureStore.saveDisplayName(nil)
                        }
                    } header: {
                        Text("Turkey PDF staff signature".localized)
                    } footer: {
                        Text("Turkey PDF staff signature footer".localized)
                    }
                    .onAppear {
                        trPdfStaffSignatureDraft = TurkeyStaffPdfSignatureStore.loadSignatureImage()
                    }
                }

                // About Section
                Section {
                    HStack {
                        Text("Version".localized)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build".localized)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About".localized)
                }
                
                // Email configuration is managed server-side only
                
                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out".localized, systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
    }
    
    private func updateAppearance(_ mode: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        switch mode {
        case "light":
            windowScene.windows.forEach { $0.overrideUserInterfaceStyle = .light }
        case "dark":
            windowScene.windows.forEach { $0.overrideUserInterfaceStyle = .dark }
        case "system":
            windowScene.windows.forEach { $0.overrideUserInterfaceStyle = .unspecified }
        default:
            break
        }
    }
    
    private var emailConfigurationSection: some View {
        Section {
            TextField("SMTP Host".localized, text: $smtpHost)
            TextField("SMTP Port".localized, text: $smtpPort)
                .keyboardType(.numberPad)
            TextField("SMTP Username".localized, text: $smtpUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            SecureField("SMTP Password".localized, text: $smtpPassword)
            TextField("Sender Name".localized, text: $smtpSenderName)
            TextField("Sender Email".localized, text: $smtpSenderEmail)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
            Toggle("Use TLS".localized, isOn: $smtpUseTLS)
            
            Button {
                saveSMTPConfiguration()
            } label: {
                HStack {
                    if isSavingSMTP {
                        ProgressView()
                    }
                    Text("Save Email Configuration".localized)
                }
            }
            .disabled(isSavingSMTP)
        } header: {
            Text("Email Configuration".localized)
        } footer: {
            Text("These SMTP settings are used for sending Return PDF emails to customers.".localized)
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("❌ Notification permission denied")
                    notificationsEnabled = false
                }
            }
        }
    }
    
    private func loadSMTPConfiguration() {
        FirebaseService.shared.loadSMTPConfiguration { config, error in
            DispatchQueue.main.async {
                guard error == nil else { return }

                if let config = config {
                    applySMTPToFields(config)
                }
            }
        }
    }
    
    private func applySMTPToFields(_ config: SMTPConfiguration) {
        smtpHost = config.host
        smtpPort = "\(config.port)"
        smtpUsername = config.username
        smtpPassword = config.password
        smtpSenderName = config.senderName
        smtpSenderEmail = config.senderEmail
        smtpUseTLS = config.useTLS
    }
    
    private func saveSMTPConfiguration() {
        guard let port = Int(smtpPort), port > 0 else {
            ErrorManager.shared.showError(message: "Invalid SMTP port".localized)
            return
        }
        isSavingSMTP = true
        
        let config = SMTPConfiguration(
            host: smtpHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: smtpUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            password: smtpPassword,
            senderName: smtpSenderName.trimmingCharacters(in: .whitespacesAndNewlines),
            senderEmail: smtpSenderEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            useTLS: smtpUseTLS
        )
        
        FirebaseService.shared.saveSMTPConfiguration(config) { error in
            DispatchQueue.main.async {
                isSavingSMTP = false
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Save SMTP Configuration")
                } else {
                    ToastManager.shared.show("✓ Email configuration saved".localized, type: .success)
                }
            }
        }
    }
}

// MARK: - Notification Settings Manager
class NotificationSettingsManager {
    static let shared = NotificationSettingsManager()
    
    private init() {}
    
    /// Whether this device should show a local banner/sound for the given type.
    /// Does not affect franchise-wide Firestore push queue (other users still receive push).
    func shouldSendNotification(type: NotificationType) -> Bool {
        let defaults = UserDefaults.standard
        
        // Check if notifications are enabled (default: true if not set)
        // object(forKey:) returns nil if key doesn't exist, so we check that first
        let notificationsEnabled: Bool
        if defaults.object(forKey: "notificationsEnabled") == nil {
            // Key doesn't exist, use default value (true)
            notificationsEnabled = true
            print("🔔 [SETTINGS] notificationsEnabled key not found, using default: true")
        } else {
            // Key exists, use stored value
            notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
            print("🔔 [SETTINGS] notificationsEnabled from UserDefaults: \(notificationsEnabled)")
        }
        
        guard notificationsEnabled else {
            print("⚠️ [SETTINGS] Notifications are disabled globally")
            return false
        }
        
        // Check specific notification type (default: true if not set)
        let typeEnabled: Bool
        switch type {
        case .damageRecord:
            if defaults.object(forKey: "damageNotificationsEnabled") == nil {
                typeEnabled = true
                print("🔔 [SETTINGS] damageNotificationsEnabled key not found, using default: true")
            } else {
                typeEnabled = defaults.bool(forKey: "damageNotificationsEnabled")
                print("🔔 [SETTINGS] damageNotificationsEnabled from UserDefaults: \(typeEnabled)")
            }
        case .vehicleReturn:
            if defaults.object(forKey: "returnNotificationsEnabled") == nil {
                typeEnabled = true
                print("🔔 [SETTINGS] returnNotificationsEnabled key not found, using default: true")
            } else {
                typeEnabled = defaults.bool(forKey: "returnNotificationsEnabled")
                print("🔔 [SETTINGS] returnNotificationsEnabled from UserDefaults: \(typeEnabled)")
            }
        case .shuttle:
            if defaults.object(forKey: "shuttleNotificationsEnabled") == nil {
                typeEnabled = true
                print("🔔 [SETTINGS] shuttleNotificationsEnabled key not found, using default: true")
            } else {
                typeEnabled = defaults.bool(forKey: "shuttleNotificationsEnabled")
                print("🔔 [SETTINGS] shuttleNotificationsEnabled from UserDefaults: \(typeEnabled)")
            }
        case .serviceReminder:
            if defaults.object(forKey: "serviceReminderNotificationsEnabled") == nil {
                typeEnabled = true
                print("🔔 [SETTINGS] serviceReminderNotificationsEnabled key not found, using default: true")
            } else {
                typeEnabled = defaults.bool(forKey: "serviceReminderNotificationsEnabled")
                print("🔔 [SETTINGS] serviceReminderNotificationsEnabled from UserDefaults: \(typeEnabled)")
            }
        case .dailyReport, .announcement:
            typeEnabled = true
        case .wheelsys:
            if defaults.object(forKey: "wheelsysNotificationsEnabled") == nil {
                typeEnabled = true
            } else {
                typeEnabled = defaults.bool(forKey: "wheelsysNotificationsEnabled")
            }
        }
        
        print("🔔 [SETTINGS] Final result for \(type): \(typeEnabled)")
        return typeEnabled
    }
}

enum NotificationType {
    case damageRecord
    case vehicleReturn
    case shuttle
    case serviceReminder
    case dailyReport
    case announcement
    case wheelsys
}

