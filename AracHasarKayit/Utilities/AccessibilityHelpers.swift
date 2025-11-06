import SwiftUI

/// Accessibility helpers for consistent accessibility implementation
struct AccessibilityHelpers {
    
    // MARK: - Common Accessibility Labels
    
    static func buttonLabel(_ action: String, context: String? = nil) -> String {
        if let context = context {
            return "\(action) \(context)"
        }
        return action
    }
    
    static func imageLabel(_ description: String) -> String {
        return description
    }
    
    static func formFieldLabel(_ fieldName: String, required: Bool = false) -> String {
        return required ? "\(fieldName), required" : fieldName
    }
    
    // MARK: - Common Accessibility Hints
    
    static func buttonHint(_ action: String) -> String {
        return "Double tap to \(action.lowercased())"
    }
    
    static func navigationHint(_ destination: String) -> String {
        return "Double tap to navigate to \(destination)"
    }
    
    static func formFieldHint(_ fieldName: String) -> String {
        return "Enter \(fieldName.lowercased())"
    }
}

// MARK: - Accessibility View Modifiers

extension View {
    /// Add accessibility label and hint to a button
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? AccessibilityHelpers.buttonHint(label))
            .accessibilityAddTraits(.isButton)
    }
    
    /// Add accessibility label to an image
    func accessibleImage(description: String) -> some View {
        self
            .accessibilityLabel(description)
            .accessibilityRemoveTraits(.isImage)
    }
    
    /// Add accessibility support for form fields
    func accessibleField(label: String, hint: String? = nil, required: Bool = false) -> some View {
        self
            .accessibilityLabel(AccessibilityHelpers.formFieldLabel(label, required: required))
            .accessibilityHint(hint ?? AccessibilityHelpers.formFieldHint(label))
    }
    
    /// Support Dynamic Type
    func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        self.environment(\.dynamicTypeSize, size)
    }
    
    /// Support high contrast mode
    func highContrast() -> some View {
        self.accessibilityIgnoresInvertColors(false)
    }
}

