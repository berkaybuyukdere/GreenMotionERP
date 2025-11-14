import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UIKit

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
        
        print("✅ App initialized with Firebase configured and authManager injected to viewModel")
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
