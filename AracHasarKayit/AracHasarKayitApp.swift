import SwiftUI
import FirebaseCore

@main
struct AracHasarKayitApp: App {
    @StateObject private var viewModel = AracViewModel()
    @StateObject private var authManager = AuthenticationManager()
    
    init() {
        // Firebase'i başlat
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
                
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(viewModel)
            }
        }
    }
}
