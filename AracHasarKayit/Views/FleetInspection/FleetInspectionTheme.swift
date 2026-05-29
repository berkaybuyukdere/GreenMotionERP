import SwiftUI
import UIKit

enum FleetInspectionTheme {
    static let background = Color.adaptive(
        light: UIColor(red: 0.965, green: 0.973, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
    )
    static let card = Color.adaptive(
        light: .secondarySystemBackground,
        dark: UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    )
    static let cardElevated = Color.adaptive(
        light: UIColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1)
    )
    static let border = Color.adaptive(
        light: UIColor(red: 0.82, green: 0.85, blue: 0.88, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let label = Color.adaptive(
        light: UIColor(red: 0.40, green: 0.44, blue: 0.48, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.55)
    )
    static let value = Color.adaptive(
        light: UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.95)
    )
    /// Primary accent — operational green (replaces legacy orange).
    static let accent = Color.adaptive(
        light: UIColor(red: 0.09, green: 0.53, blue: 0.24, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.78, blue: 0.45, alpha: 1)
    )
    static let accentBlue = Color.adaptive(
        light: UIColor(red: 0.04, green: 0.41, blue: 0.85, alpha: 1),
        dark: UIColor(red: 0.35, green: 0.62, blue: 1.0, alpha: 1)
    )
    static let clearGreen = accent
    static let reviewAmber = accent.opacity(0.85)
    static let damageRed = Color.adaptive(
        light: UIColor(red: 0.78, green: 0.15, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.32, blue: 0.32, alpha: 1)
    )
    static let missingGray = Color.adaptive(
        light: UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.35)
    )

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

private extension Color {
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
