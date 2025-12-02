import SwiftUI

// MARK: - Analytics View Extensions
// Non-invasive modifiers for tracking user interactions

extension View {
    /// Track button tap - adds analytics tracking without modifying button behavior
    /// - Parameters:
    ///   - action: Action identifier (e.g., "save", "delete", "cancel")
    ///   - screen: Screen name where button is located
    ///   - buttonLabel: Optional button label for better analytics
    ///   - parameters: Additional parameters to track
    /// - Returns: Modified view with analytics tracking
    func analytics(action: String, screen: String, buttonLabel: String? = nil, parameters: [String: Any]? = nil) -> some View {
        self.onTapGesture {
            AnalyticsManager.shared.trackButtonTap(
                action: action,
                screen: screen,
                buttonLabel: buttonLabel,
                parameters: parameters
            )
        }
    }
    
    /// Track screen view on appear
    /// - Parameters:
    ///   - screenName: Name of the screen
    ///   - screenClass: Optional screen class
    func trackScreen(_ screenName: String, screenClass: String? = nil) -> some View {
        self.onAppear {
            AnalyticsManager.shared.trackScreenView(screenName, screenClass: screenClass)
        }
    }
    
    /// Track screen view and exit
    /// - Parameters:
    ///   - screenName: Name of the screen
    ///   - screenClass: Optional screen class
    /// - Returns: Modified view with screen tracking
    func trackScreenLifecycle(_ screenName: String, screenClass: String? = nil) -> some View {
        self
            .onAppear {
                AnalyticsManager.shared.trackScreenView(screenName, screenClass: screenClass)
            }
            .onDisappear {
                AnalyticsManager.shared.trackScreenExit(screenName)
            }
    }
    
    /// Track swipe gesture
    /// - Parameters:
    ///   - direction: Swipe direction ("left", "right", "up", "down")
    ///   - screen: Screen name
    ///   - parameters: Additional parameters
    /// - Returns: Modified view with swipe tracking
    func trackSwipe(direction: String, screen: String, parameters: [String: Any]? = nil) -> some View {
        self.gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let detectedDirection: String
                    if abs(value.translation.width) > abs(value.translation.height) {
                        detectedDirection = value.translation.width > 0 ? "right" : "left"
                    } else {
                        detectedDirection = value.translation.height > 0 ? "down" : "up"
                    }
                    
                    if detectedDirection == direction {
                        AnalyticsManager.shared.trackSwipe(
                            direction: direction,
                            screen: screen,
                            parameters: parameters
                        )
                    }
                }
        )
    }
    
    /// Track long press gesture
    /// - Parameters:
    ///   - screen: Screen name
    ///   - parameters: Additional parameters
    /// - Returns: Modified view with long press tracking
    func trackLongPress(screen: String, parameters: [String: Any]? = nil) -> some View {
        self.onLongPressGesture {
            AnalyticsManager.shared.trackLongPress(screen: screen, parameters: parameters)
        }
    }
}

// MARK: - Button Analytics Extension
// Convenience extension for Button views

extension Button {
    /// Add analytics tracking to a button without modifying its action
    /// - Parameters:
    ///   - action: Action identifier
    ///   - screen: Screen name
    ///   - buttonLabel: Optional button label
    ///   - parameters: Additional parameters
    /// - Returns: Button with analytics tracking
    func analytics(action: String, screen: String, buttonLabel: String? = nil, parameters: [String: Any]? = nil) -> some View {
        // Note: This is a conceptual extension
        // In practice, we'll use the View extension on the button's label
        self
    }
}

// MARK: - Helper for Button Tracking
// Since Button doesn't easily support modifiers on its action,
// we provide a helper function to wrap button actions

struct AnalyticsButton<Label: View>: View {
    let action: () -> Void
    let label: Label
    let analyticsAction: String
    let screen: String
    let buttonLabel: String?
    let parameters: [String: Any]?
    
    init(
        action: @escaping () -> Void,
        analyticsAction: String,
        screen: String,
        buttonLabel: String? = nil,
        parameters: [String: Any]? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
        self.analyticsAction = analyticsAction
        self.screen = screen
        self.buttonLabel = buttonLabel
        self.parameters = parameters
    }
    
    var body: some View {
        Button(action: {
            // Track analytics first
            AnalyticsManager.shared.trackButtonTap(
                action: analyticsAction,
                screen: screen,
                buttonLabel: buttonLabel,
                parameters: parameters
            )
            // Then execute original action
            action()
        }) {
            label
        }
    }
}

// MARK: - Convenience Initializer
extension AnalyticsButton where Label == Text {
    /// Create an analytics-tracked button with text label
    init(
        _ title: String,
        analyticsAction: String,
        screen: String,
        parameters: [String: Any]? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            action: action,
            analyticsAction: analyticsAction,
            screen: screen,
            buttonLabel: title,
            parameters: parameters
        ) {
            Text(title)
        }
    }
}

