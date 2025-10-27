import SwiftUI
import FirebaseCore
import FirebaseMessaging

@main
struct AracHasarKayitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var viewModel: AracViewModel
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        // Configure Firebase first
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
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(viewModel)
                    .environmentObject(notificationManager)
            }
        }
    }
}
