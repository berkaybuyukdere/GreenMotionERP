import SwiftUI

/// Centralized app theme for consistent design across the entire application
/// All buttons, text styles, and UI components should use this theme for consistency
struct AppTheme {
    
    // MARK: - Colors (Adaptive for Dark Mode)
    
    static var primary: Color { Color.blue }
    static var secondary: Color { Color.orange }
    static var success: Color { Color.green }
    static var danger: Color { Color.red }
    static var warning: Color { Color.orange }
    static var info: Color { Color.blue }
    static var purple: Color { Color.purple }
    static var cyan: Color { Color.cyan }
    static var teal: Color { Color.teal }
    
    // Dark mode adaptive colors
    static func adaptiveColor(light: Color, dark: Color, for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
    
    static func backgroundColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    static func cardBackgroundColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground)
    }
    
    static func textColor(for colorScheme: ColorScheme) -> Color {
        Color(.label)
    }
    
    // MARK: - Button Styles
    
    /// Standard primary button style - Use for main actions
    static var primaryButtonStyle: some ButtonStyle {
        PrimaryButtonStyle()
    }
    
    /// Standard secondary button style - Use for secondary actions
    static var secondaryButtonStyle: some ButtonStyle {
        SecondaryButtonStyle()
    }
    
    /// Success button style - Use for positive actions (save, confirm, etc.)
    static var successButtonStyle: some ButtonStyle {
        SuccessButtonStyle()
    }
    
    /// Danger button style - Use for destructive actions (delete, remove, etc.)
    static var dangerButtonStyle: some ButtonStyle {
        DangerButtonStyle()
    }
    
    /// Warning button style - Use for warning actions
    static var warningButtonStyle: some ButtonStyle {
        WarningButtonStyle()
    }
    
    /// Outline button style - Use for outlined buttons
    static var outlineButtonStyle: some ButtonStyle {
        OutlineButtonStyle()
    }
    
    /// Ghost button style - Use for minimal buttons
    static var ghostButtonStyle: some ButtonStyle {
        GhostButtonStyle()
    }
    
    /// Compact button style - Use for smaller buttons
    static var compactButtonStyle: some ButtonStyle {
        CompactButtonStyle()
    }
    
    /// Link button style - Use for text-like buttons
    static var linkButtonStyle: some ButtonStyle {
        LinkButtonStyle()
    }
    
    // MARK: - Spacing
    
    static let padding: CGFloat = 16
    static let paddingSmall: CGFloat = 8
    static let paddingLarge: CGFloat = 24
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16
    static let buttonHeight: CGFloat = 50
    static let buttonHeightCompact: CGFloat = 36
    static let buttonHeightLarge: CGFloat = 56
    
    // MARK: - Typography
    
    /// Large title font - Use for main titles
    static var largeTitleFont: Font {
        .system(.largeTitle, design: .rounded, weight: .bold)
    }
    
    /// Title font - Use for section titles
    static var titleFont: Font {
        .system(.title2, design: .rounded, weight: .bold)
    }
    
    /// Title 3 font - Use for card titles
    static var title3Font: Font {
        .system(.title3, design: .rounded, weight: .semibold)
    }
    
    /// Headline font - Use for important text
    static var headlineFont: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }
    
    /// Body font - Use for regular text
    static var bodyFont: Font {
        .system(.body, design: .default, weight: .regular)
    }
    
    /// Body font bold - Use for emphasized body text
    static var bodyBoldFont: Font {
        .system(.body, design: .default, weight: .semibold)
    }
    
    /// Subheadline font - Use for secondary text
    static var subheadlineFont: Font {
        .system(.subheadline, design: .default, weight: .regular)
    }
    
    /// Caption font - Use for small text
    static var captionFont: Font {
        .system(.caption, design: .default, weight: .regular)
    }
    
    /// Caption 2 font - Use for very small text
    static var caption2Font: Font {
        .system(.caption2, design: .default, weight: .regular)
    }
    
    /// Button font - Use for button text
    static var buttonFont: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }
    
    // MARK: - Shadows
    
    static func shadow(for colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        let opacity = colorScheme == .dark ? 0.3 : 0.1
        return (Color.black.opacity(opacity), 8, 0, 4)
    }
    
    static func cardShadow(for colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        let opacity = colorScheme == .dark ? 0.3 : 0.1
        return (Color.black.opacity(opacity), 8, 0, 4)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.buttonFont)
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
            .font(AppTheme.buttonFont)
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
            .font(AppTheme.buttonFont)
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
            .font(AppTheme.buttonFont)
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
            .font(AppTheme.buttonFont)
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

struct OutlineButtonStyle: ButtonStyle {
    var color: Color = AppTheme.primary
    var height: CGFloat = AppTheme.buttonHeight
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.buttonFont)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(color, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var color: Color = AppTheme.primary
    var height: CGFloat = AppTheme.buttonHeight
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.buttonFont)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(color.opacity(0.1))
            .cornerRadius(AppTheme.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CompactButtonStyle: ButtonStyle {
    var color: Color = AppTheme.primary
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.buttonFont)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.padding)
            .padding(.vertical, AppTheme.paddingSmall)
            .frame(height: AppTheme.buttonHeightCompact)
            .background(color)
            .cornerRadius(AppTheme.cornerRadiusSmall)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct LinkButtonStyle: ButtonStyle {
    var color: Color = AppTheme.primary
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.bodyFont)
            .foregroundColor(color)
            .underline(configuration.isPressed)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Text Style Modifiers

struct TitleTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.titleFont)
            .foregroundColor(Color(.label))
    }
}

struct HeadlineTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.headlineFont)
            .foregroundColor(Color(.label))
    }
}

struct BodyTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.bodyFont)
            .foregroundColor(Color(.label))
    }
}

struct CaptionTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.captionFont)
            .foregroundColor(Color(.secondaryLabel))
    }
}

struct SecondaryTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTheme.subheadlineFont)
            .foregroundColor(Color(.secondaryLabel))
    }
}

// MARK: - Consistent Card Style

struct AppCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppTheme.cornerRadius
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.cardBackgroundColor(for: colorScheme))
            .cornerRadius(cornerRadius)
            .shadow(
                color: AppTheme.cardShadow(for: colorScheme).color,
                radius: AppTheme.cardShadow(for: colorScheme).radius,
                x: AppTheme.cardShadow(for: colorScheme).x,
                y: AppTheme.cardShadow(for: colorScheme).y
            )
    }
}

// MARK: - View Extensions for Easy Usage

extension View {
    /// Apply card style to any view
    func appCardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = AppTheme.cornerRadius) -> some View {
        modifier(AppCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
    
    /// Apply title text style
    func titleStyle() -> some View {
        modifier(TitleTextStyle())
    }
    
    /// Apply headline text style
    func headlineStyle() -> some View {
        modifier(HeadlineTextStyle())
    }
    
    /// Apply body text style
    func bodyStyle() -> some View {
        modifier(BodyTextStyle())
    }
    
    /// Apply caption text style
    func captionStyle() -> some View {
        modifier(CaptionTextStyle())
    }
    
    /// Apply secondary text style
    func secondaryStyle() -> some View {
        modifier(SecondaryTextStyle())
    }
}

