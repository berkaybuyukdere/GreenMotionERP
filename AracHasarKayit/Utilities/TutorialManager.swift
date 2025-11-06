import Foundation
import SwiftUI

/// Tutorial manager for contextual help and guided tours
class TutorialManager: ObservableObject {
    static let shared = TutorialManager()
    
    @Published var activeTutorial: TutorialStep?
    @Published var completedTutorials: Set<String> = []
    
    private init() {
        loadCompletedTutorials()
    }
    
    // MARK: - Tutorial Steps
    
    struct TutorialStep: Identifiable {
        let id: String
        let title: String
        let description: String
        let targetView: String? // View identifier
        let action: (() -> Void)?
    }
    
    // MARK: - Tutorial Management
    
    func showTutorial(_ tutorialId: String, step: TutorialStep) {
        // Check if tutorial was already completed
        if completedTutorials.contains(tutorialId) {
            return
        }
        
        activeTutorial = step
        AnalyticsManager.shared.trackFeatureUsage("tutorial", action: "shown", additionalInfo: ["tutorial_id": tutorialId])
    }
    
    func completeTutorial(_ tutorialId: String) {
        completedTutorials.insert(tutorialId)
        saveCompletedTutorials()
        activeTutorial = nil
        AnalyticsManager.shared.trackFeatureUsage("tutorial", action: "completed", additionalInfo: ["tutorial_id": tutorialId])
    }
    
    func dismissTutorial() {
        activeTutorial = nil
    }
    
    func resetTutorial(_ tutorialId: String) {
        completedTutorials.remove(tutorialId)
        saveCompletedTutorials()
    }
    
    // MARK: - Contextual Help
    
    func showContextualHelp(for view: String, message: String) {
        let step = TutorialStep(
            id: "contextual_\(view)",
            title: "Help",
            description: message,
            targetView: view,
            action: nil
        )
        showTutorial("contextual_\(view)", step: step)
    }
    
    // MARK: - Feature Highlights
    
    func highlightFeature(_ featureId: String, title: String, description: String) {
        let step = TutorialStep(
            id: featureId,
            title: title,
            description: description,
            targetView: nil,
            action: nil
        )
        showTutorial(featureId, step: step)
    }
    
    // MARK: - Persistence
    
    private func loadCompletedTutorials() {
        if let data = UserDefaults.standard.data(forKey: "completedTutorials"),
           let tutorials = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedTutorials = tutorials
        }
    }
    
    private func saveCompletedTutorials() {
        if let data = try? JSONEncoder().encode(completedTutorials) {
            UserDefaults.standard.set(data, forKey: "completedTutorials")
        }
    }
}

// MARK: - Tutorial View Modifier

struct TutorialOverlay: ViewModifier {
    @ObservedObject var tutorialManager = TutorialManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let tutorial = tutorialManager.activeTutorial {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        tutorialManager.dismissTutorial()
                    }
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Text(tutorial.title)
                            .font(AppTheme.titleFont)
                            .foregroundColor(.primary)
                        
                        Text(tutorial.description)
                            .font(AppTheme.bodyFont)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 12) {
                            Button("Got it") {
                                tutorialManager.dismissTutorial()
                            }
                            .buttonStyle(AppTheme.primaryButtonStyle)
                            
                            if tutorial.action != nil {
                                Button("Show me") {
                                    tutorial.action?()
                                    tutorialManager.dismissTutorial()
                                }
                                .buttonStyle(AppTheme.secondaryButtonStyle)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(AppTheme.cornerRadius)
                    .shadow(radius: 10)
                    .padding()
                }
            }
        }
    }
}

extension View {
    func tutorialOverlay() -> some View {
        modifier(TutorialOverlay())
    }
}

