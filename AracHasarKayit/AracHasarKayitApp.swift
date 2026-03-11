import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UIKit
import FirebaseCrashlytics
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

#if canImport(FirebaseAppCheck)
final class DefaultAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
        #endif
    }
}
#endif

@main
struct AracHasarKayitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var viewModel: AracViewModel
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var localization = LocalizationManager.shared
    
    init() {
        #if canImport(FirebaseAppCheck)
        AppCheck.setAppCheckProviderFactory(DefaultAppCheckProviderFactory())
        #endif
        // Configure Firebase first (HeartbeatLogging disabled)
        FirebaseApp.configure()
        
        // Initialize authManager and viewModel with proper connection
        let tempAuthManager = AuthenticationManager()
        let tempViewModel = AracViewModel()
        tempViewModel.authManager = tempAuthManager
        // Start observing auth state - data loads only after country validation passes
        tempViewModel.observeAuthManager()
        
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
                    .environmentObject(localization)
                    .onAppear {
                        applyAppearanceMode()
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(viewModel)
                    .environmentObject(notificationManager)
                    .environmentObject(localization)
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
