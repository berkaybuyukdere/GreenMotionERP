import SwiftUI
import UIKit

/// Palantir Foundry–inspired operational UI. Adapts to app appearance (Settings / system).
enum PalantirTheme {
    static let background = Color.adaptive(
        light: UIColor(red: 0.965, green: 0.973, blue: 0.98, alpha: 1),   // #F6F8FA
        dark: UIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1)       // #0A0C10
    )
    static let surface = Color.adaptive(
        light: .systemBackground,
        dark: UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)        // #161B22
    )
    static let surfaceHigh = Color.adaptive(
        light: UIColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.14, green: 0.16, blue: 0.19, alpha: 1)
    )
    static let border = Color.adaptive(
        light: UIColor(red: 0.82, green: 0.85, blue: 0.88, alpha: 1),      // #D0D7DE
        dark: UIColor(red: 0.19, green: 0.21, blue: 0.24, alpha: 1)        // #30363D
    )
    static let textPrimary = Color.adaptive(
        light: UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1),      // #1F2328
        dark: UIColor(red: 0.79, green: 0.82, blue: 0.85, alpha: 1)       // #C9D1D9
    )
    static let textMuted = Color.adaptive(
        light: UIColor(red: 0.40, green: 0.44, blue: 0.48, alpha: 1),      // #656D76
        dark: UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)       // #8B949E
    )
    static let accent = Color.adaptive(
        light: UIColor(red: 0.04, green: 0.41, blue: 0.85, alpha: 1),     // #0969DA
        dark: UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1)         // #58A6FF
    )
    static let onAccent = Color.white
    static let success = Color.adaptive(
        light: UIColor(red: 0.09, green: 0.53, blue: 0.24, alpha: 1),
        dark: UIColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1)
    )
    static let warning = Color.adaptive(
        light: UIColor(red: 0.65, green: 0.45, blue: 0.05, alpha: 1),
        dark: UIColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 1)
    )
    static let critical = Color.adaptive(
        light: UIColor(red: 0.78, green: 0.15, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1)
    )

    static func labelFont(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func bodyFont(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func dataFont(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func heroFont(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
}

private extension Color {
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct PalantirPanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(PalantirTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(PalantirTheme.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func palantirCard() -> some View {
        modifier(PalantirPanelCard())
    }
}
