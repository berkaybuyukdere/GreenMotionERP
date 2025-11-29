import SwiftUI
import WebKit

/// Full-screen view for Wheelsys login using in-app web view
struct WheelsysLoginView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var sessionManager = WheelsysSessionManager.shared
    
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var reloadTrigger = UUID()
    @State private var hasLoaded = false
    
    private let wheelsysURL = URL(string: "https://ch.wheelsys.greenmotion.com/fs/fs-beta/#111")!
    
    var body: some View {
        NavigationView {
            ZStack {
                // Web View
                WheelsysWebView(
                    url: wheelsysURL,
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    sessionManager: sessionManager
                )
                .id(reloadTrigger)
                .edgesIgnoringSafeArea(.all)
                
                // Loading Indicator
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading Wheelsys...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
                            .shadow(radius: 10)
                    )
                }
            }
            .navigationTitle("Wheelsys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        reloadWebView()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Restore session on appear
                sessionManager.restoreCookies()
                
                // Set initial loading state
                if !hasLoaded {
                    isLoading = true
                    hasLoaded = true
                }
            }
            .onChange(of: isLoading) { oldValue, newValue in
                // Log loading state changes for debugging
                if newValue {
                    print("🔄 Loading started")
                } else {
                    print("✅ Loading finished")
                }
            }
        }
    }
    
    private func reloadWebView() {
        // Trigger reload by changing the ID
        reloadTrigger = UUID()
        sessionManager.restoreCookies()
    }
}

// MARK: - Preview
struct WheelsysLoginView_Previews: PreviewProvider {
    static var previews: some View {
        WheelsysLoginView()
    }
}

