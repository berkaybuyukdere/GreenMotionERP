import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UIKit
import FirebaseCrashlytics

@main
struct AracHasarKayitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var viewModel: AracViewModel
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        // Configure Firebase first (HeartbeatLogging disabled)
        FirebaseApp.configure()
        
        // Initialize authManager and viewModel with proper connection
        let tempAuthManager = AuthenticationManager()
        let tempViewModel = AracViewModel()
        tempViewModel.authManager = tempAuthManager
        
        // Assign to StateObjects
        _authManager = StateObject(wrappedValue: tempAuthManager)
        _viewModel = StateObject(wrappedValue: tempViewModel)
        
        // Initialize LogManager
        _ = LogManager.shared
        
        // Setup Crashlytics
        if let userId = tempAuthManager.currentUser?.uid {
            Crashlytics.crashlytics().setUserID(userId)
        }
        
        LogManager.shared.info("App initialized with Firebase configured and authManager injected to viewModel")
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
                    .environmentObject(notificationManager)
                    .onAppear {
                        applyAppearanceMode()
                        // Restore Wheelsys session on app start
                        WheelsysSessionManager.shared.restoreCookies()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        // Save cookies when app goes to background
                        WheelsysSessionManager.shared.saveCookies()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                        // Save cookies when app is about to terminate
                        WheelsysSessionManager.shared.saveCookies()
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(viewModel)
                    .environmentObject(notificationManager)
                    .onAppear {
                        applyAppearanceMode()
                    }
            }
        }
    }
    
    private func applyAppearanceMode() {
        let appearanceMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        switch appearanceMode {
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
}
