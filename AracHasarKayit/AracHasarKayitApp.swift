import SwiftUI
import FirebaseCore

@main
struct AracHasarKayitApp: App {
    @StateObject private var viewModel = AracViewModel()
    @StateObject private var authManager = AuthenticationManager()
    
    init() {
        FirebaseApp.configure()
        // ❌ Bunu kaldır: UISplitViewController.appearance()...
    }
    
    // ViewModel'e authManager'ı inject et
    private func setupViewModel() {
        viewModel.authManager = authManager
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
                    .onAppear {
                        setupViewModel()
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .environmentObject(viewModel)
                    .onAppear {
                        setupViewModel()
                    }
            }
        }
    }
}
