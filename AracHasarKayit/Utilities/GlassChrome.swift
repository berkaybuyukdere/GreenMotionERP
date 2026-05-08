import SwiftUI

/// Liquid Glass–style chrome with a safe fallback until a public `glassEffect` API exists.
enum GlassChrome {
    /// iOS 26+ placeholder: swap implementation when SDK exposes `glassEffect`.
    @ViewBuilder
    static func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Card-style frosted surface behind the view’s current layout (apply after padding / frame).
    func glassChromeSurface(cornerRadius: CGFloat = 16) -> some View {
        background {
            GlassChrome.glassBackground(cornerRadius: cornerRadius)
        }
    }

    /// Alias aligned with the roadmap naming.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        glassChromeSurface(cornerRadius: cornerRadius)
    }
}
