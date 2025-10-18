import SwiftUI

/// Shuttle system theme colors - supports dark/light mode
struct ShuttleTheme {
    // Primary Colors
    static let primary = Color("ShuttlePrimary", bundle: .main, fallback: Color.cyan)
    static let secondary = Color("ShuttleSecondary", bundle: .main, fallback: Color.blue)
    static let accent = Color("ShuttleAccent", bundle: .main, fallback: Color.purple)
    
    // Status Colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // Gradients
    static let primaryGradient = LinearGradient(
        gradient: Gradient(colors: [Color.cyan, Color.blue]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let successGradient = LinearGradient(
        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color.cyan.opacity(0.1),
            Color.blue.opacity(0.05)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Card Backgrounds (adapts to color scheme)
    static var cardBackground: Color {
        Color(.systemBackground)
    }
    
    static var secondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
    
    static var tertiaryBackground: Color {
        Color(.tertiarySystemBackground)
    }
    
    // Text Colors
    static var primaryText: Color {
        Color.primary
    }
    
    static var secondaryText: Color {
        Color.secondary
    }
    
    // Shadow
    static var cardShadow: Color {
        Color.black.opacity(0.08)
    }
}

// MARK: - Color Extensions

extension Color {
    init(_ name: String, bundle: Bundle?, fallback: Color) {
        if let color = UIColor(named: name) {
            self.init(uiColor: color)
        } else {
            self = fallback
        }
    }
}

