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
    
    private var canManageSMTP: Bool {
        authManager.userProfile?.isElevatedAdmin == true
    }
    
    var body: some View {
        NavigationView {
            Form {
                // User Profile Section
                Section {
                    if let profile = authManager.userProfile {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            
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
                                .foregroundColor(.blue)
                            
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
            .navigationTitle("Settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
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
}

