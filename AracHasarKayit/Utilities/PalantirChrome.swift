import SwiftUI

// MARK: - Root / screen chrome

/// Applies Palantir ops canvas + dark scheme when mode is on (TabView root and full-screen flows).
struct PalantirOpsRootModifier: ViewModifier {
    @ObservedObject private var mode = PalantirModeManager.shared

    func body(content: Content) -> some View {
        content
            .background {
                if mode.isEnabled {
                    PalantirTheme.background.ignoresSafeArea()
                }
            }
            // Respect Settings → Appearance (light / dark / system) while Sentinel chrome is on.
            .preferredColorScheme(nil)
            .tint(mode.isEnabled ? PalantirTheme.accent : .blue)
            .environment(\.palantirModeEnabled, mode.isEnabled)
    }
}

/// Per-screen wrapper for sheets and pushed flows (checkout, return, damage, vehicle detail).
struct PalantirOpsScreenModifier: ViewModifier {
    @Environment(\.palantirModeEnabled) private var palantirMode

    func body(content: Content) -> some View {
        content
            .background {
                if palantirMode {
                    PalantirTheme.background.ignoresSafeArea()
                }
            }
            .scrollContentBackground(palantirMode ? .hidden : .automatic)
            .toolbarBackground(palantirMode ? PalantirTheme.surface : Color.clear, for: .navigationBar)
            .toolbarBackground(palantirMode ? .visible : .automatic, for: .navigationBar)
            .toolbarColorScheme(palantirMode ? .dark : nil, for: .navigationBar)
    }
}

extension View {
    func palantirOpsRoot() -> some View {
        modifier(PalantirOpsRootModifier())
    }

    func palantirOpsScreen() -> some View {
        modifier(PalantirOpsScreenModifier())
    }
}

// MARK: - Section / metric styling

struct PalantirSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.accent)
                .tracking(0.6)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

/// Grouped screen background that follows Palantir mode.
struct PalantirGroupedBackground: View {
    @Environment(\.palantirModeEnabled) private var palantirMode

    var body: some View {
        if palantirMode {
            PalantirTheme.background
        } else {
            Color(.systemGroupedBackground)
        }
    }
}

struct PalantirOpsBadge: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, accent, success, warning, critical

        var color: Color {
            switch self {
            case .neutral: return PalantirTheme.textMuted
            case .accent: return PalantirTheme.accent
            case .success: return PalantirTheme.success
            case .warning: return PalantirTheme.warning
            case .critical: return PalantirTheme.critical
            }
        }
    }

    var body: some View {
        Text(text)
            .font(PalantirTheme.labelFont(9))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(tone.color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(tone.color.opacity(0.35), lineWidth: 1)
                    )
            )
    }
}
