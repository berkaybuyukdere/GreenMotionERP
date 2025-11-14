import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
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
                                Text(profile.fullName)
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
                                Text("User")
                                    .font(.headline)
                                Text(user.email ?? "Unknown")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Profile")
                }
                
                // Appearance Section
                Section {
                    Picker("Appearance", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearanceMode) { _, newValue in
                        updateAppearance(newValue)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose how the app looks. System follows your device settings.")
                }
                
                // Notification Settings Section
                Section {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            if newValue {
                                requestNotificationPermission()
                            }
                        }
                    
                    if notificationsEnabled {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Toggle("Damage Record Notifications", isOn: $damageNotificationsEnabled)
                        Toggle("Return Notifications", isOn: $returnNotificationsEnabled)
                        Toggle("Shuttle Notifications", isOn: $shuttleNotificationsEnabled)
                        Toggle("Service Reminder Notifications", isOn: $serviceReminderNotificationsEnabled)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if notificationsEnabled {
                        Text("Control which types of notifications you receive.")
                    } else {
                        Text("Enable notifications to receive updates about damage records, returns, shuttle services, and service reminders.")
                    }
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
                
                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
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
}

// MARK: - Notification Settings Manager
class NotificationSettingsManager {
    static let shared = NotificationSettingsManager()
    
    private init() {}
    
    func shouldSendNotification(type: NotificationType) -> Bool {
        let defaults = UserDefaults.standard
        
        // Check if notifications are enabled
        guard defaults.bool(forKey: "notificationsEnabled") else {
            return false
        }
        
        // Check specific notification type
        switch type {
        case .damageRecord:
            return defaults.bool(forKey: "damageNotificationsEnabled")
        case .vehicleReturn:
            return defaults.bool(forKey: "returnNotificationsEnabled")
        case .shuttle:
            return defaults.bool(forKey: "shuttleNotificationsEnabled")
        case .serviceReminder:
            return defaults.bool(forKey: "serviceReminderNotificationsEnabled")
        }
    }
}

enum NotificationType {
    case damageRecord
    case vehicleReturn
    case shuttle
    case serviceReminder
}

