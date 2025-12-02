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
    @State private var userStats: UserStats?
    @State private var userRank: Int?
    @State private var isLoadingStats = true
    
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
                
                // Gamification Statistics Section
                Section {
                    if isLoadingStats {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    } else if let stats = userStats {
                        // Total Points
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Total Points")
                            Spacer()
                            Text("\(stats.totalPoints)")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        if let rank = userRank {
                            Divider()
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(rank <= 3 ? .yellow : .gray)
                                Text("Rank")
                                Spacer()
                                Text("#\(rank)")
                                    .fontWeight(.bold)
                                    .foregroundColor(rank <= 3 ? .yellow : .blue)
                            }
                        }
                        
                        Divider()
                        
                        // Activity Breakdown
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity Breakdown")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            ActivityStatRow(
                                icon: "exclamationmark.triangle.fill",
                                label: "Damage Records",
                                count: stats.activityStats.damageRecords,
                                points: stats.activityStats.damageRecords * 100,
                                color: .orange
                            )
                            
                            ActivityStatRow(
                                icon: "arrow.uturn.backward.circle.fill",
                                label: "Return Operations",
                                count: stats.activityStats.returnOperations,
                                points: stats.activityStats.returnOperations * 80,
                                color: .purple
                            )
                            
                            ActivityStatRow(
                                icon: "arrow.right.circle.fill",
                                label: "Check Out Operations",
                                count: stats.activityStats.checkOutOperations,
                                points: stats.activityStats.checkOutOperations * 60,
                                color: .blue
                            )
                            
                            ActivityStatRow(
                                icon: "briefcase.fill",
                                label: "Office Operations",
                                count: stats.activityStats.officeOperations,
                                points: stats.activityStats.officeOperations * 40,
                                color: .indigo
                            )
                            
                            ActivityStatRow(
                                icon: "car.fill",
                                label: "Vehicle Records",
                                count: stats.activityStats.vehicleRecords,
                                points: stats.activityStats.vehicleRecords * 20,
                                color: .green
                            )
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Gamification")
                } footer: {
                    if let stats = userStats {
                        Text("You have completed \(stats.totalActivities) activities and earned \(stats.totalPoints) points.")
                    }
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
            .onAppear {
                loadUserStats()
            }
            .refreshable {
                loadUserStats()
            }
        }
    }
    
    private func loadUserStats() {
        isLoadingStats = true
        
        // Load user statistics
        GamificationManager.shared.getCurrentUserStats { stats, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading user stats: \(error.localizedDescription)")
                }
                self.userStats = stats
                
                // Load user rank
                GamificationManager.shared.getCurrentUserRank { rank, error in
                    DispatchQueue.main.async {
                        self.userRank = rank
                        self.isLoadingStats = false
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

