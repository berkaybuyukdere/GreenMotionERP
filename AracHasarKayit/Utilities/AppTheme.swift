import SwiftUI

/// Centralized app theme for consistent design
struct AppTheme {
    
    // MARK: - Colors
    
    static let primary = Color.blue
    static let secondary = Color.orange
    static let success = Color.green
    static let danger = Color.red
    static let warning = Color.orange
    static let info = Color.blue
    static let purple = Color.purple
    
    // MARK: - Button Styles
    
    /// Standard primary button style
    static var primaryButtonStyle: some ButtonStyle {
        PrimaryButtonStyle()
    }
    
    /// Standard secondary button style
    static var secondaryButtonStyle: some ButtonStyle {
        SecondaryButtonStyle()
    }
    
    /// Success button style
    static var successButtonStyle: some ButtonStyle {
        SuccessButtonStyle()
    }
    
    /// Danger button style
    static var dangerButtonStyle: some ButtonStyle {
        DangerButtonStyle()
    }
    
    // MARK: - Spacing
    
    static let padding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 50
    
    // MARK: - Typography
    
    static var titleFont: Font {
        .system(.title2, design: .rounded, weight: .bold)
    }
    
    static var headlineFont: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }
    
    static var bodyFont: Font {
        .system(.body, design: .default, weight: .regular)
    }
    
    static var captionFont: Font {
        .system(.caption, design: .default, weight: .regular)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.buttonHeight)
            .background(AppTheme.primary)
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.buttonHeight)
            .background(AppTheme.secondary.opacity(0.1))
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.buttonHeight)
            .background(AppTheme.success)
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.buttonHeight)
            .background(AppTheme.danger)
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct WarningButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.buttonHeight)
            .background(AppTheme.warning)
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Consistent Card Style

struct AppCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppTheme.cornerRadius
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(.systemBackground))
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func appCardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = AppTheme.cornerRadius) -> some View {
        modifier(AppCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

