import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    
    let pages = [
        OnboardingPage(
            title: "Welcome to Green Motion",
            description: "Manage your vehicle fleet, track damages, and handle operations all in one place.",
            imageName: "car.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Track Damages",
            description: "Record vehicle damages with photos, track repair status, and manage RES codes efficiently.",
            imageName: "exclamationmark.triangle.fill",
            color: .orange
        ),
        OnboardingPage(
            title: "Office Operations",
            description: "Manage fuel receipts, POS transactions, and office expenses with photo documentation.",
            imageName: "doc.text.fill",
            color: .green
        ),
        OnboardingPage(
            title: "Real-time Updates",
            description: "Get instant notifications and real-time updates across all your devices.",
            imageName: "bell.fill",
            color: .purple
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [pages[currentPage].color.opacity(0.1), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .buttonStyle(LinkButtonStyle(color: .secondary))
                    .padding()
                }
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button("Previous") {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                        .buttonStyle(AppTheme.secondaryButtonStyle)
                    }
                    
                    Spacer()
                    
                    Button(currentPage == pages.count - 1 ? "Get Started" : "Next") {
                        if currentPage == pages.count - 1 {
                            completeOnboarding()
                        } else {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                    }
                    .buttonStyle(AppTheme.primaryButtonStyle)
                }
                .padding()
            }
        }
        .onAppear {
            AnalyticsManager.shared.trackScreenView("Onboarding")
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        AnalyticsManager.shared.trackUserAction(action: "onboarding_completed", screen: "Onboarding")
        isPresented = false
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: page.imageName)
                .font(.system(size: 80))
                .foregroundColor(page.color)
                .padding()
            
            // Title
            Text(page.title)
                .font(AppTheme.largeTitleFont)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Description
            Text(page.description)
                .font(AppTheme.bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}

