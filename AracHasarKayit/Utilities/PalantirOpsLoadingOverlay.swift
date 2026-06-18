import SwiftUI

/// Shared Palantir-style operational loading overlay used across WheelSys tabs
/// (Fleet Chart, Availability) and the return check-in flow. Sharp corners,
/// uppercase microcopy, thin border, and a CPU-friendly segmented step bar — no
/// Lottie, no continuous heavy animation.
struct PalantirOpsLoadingOverlay: View {
    let title: String
    let microcopy: String
    /// 1-based current step for the segmented progress bar (nil hides the bar).
    var step: Int?
    var totalSteps: Int = 4
    /// When true the overlay floats as a centered card over content;
    /// when false it fills the available space (initial empty load).
    var floating: Bool = true

    @State private var pulse = false

    var body: some View {
        let card = VStack(spacing: 12) {
            ProgressView()
                .tint(PalantirTheme.accent)
                .scaleEffect(1.1)

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PalantirTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(microcopy.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)

            if let step {
                stepBar(current: step)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 280)
        .background(
            Rectangle()
                .fill(PalantirTheme.surface)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        )
        .opacity(pulse ? 1.0 : 0.92)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }

        if floating {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                card
            }
        } else {
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PalantirTheme.background)
        }
    }

    private func stepBar(current: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Rectangle()
                    .fill(index < current ? PalantirTheme.accent : PalantirTheme.border)
                    .frame(height: 3)
            }
        }
        .frame(width: 200)
    }
}

/// Canonical phase model for WheelSys data loads so every tab speaks the same
/// language. Titles/microcopy resolve to localized keys.
enum PalantirOpsPhase: Equatable {
    case connecting
    case fetching
    case parsing
    case ready

    var step: Int {
        switch self {
        case .connecting: return 1
        case .fetching: return 2
        case .parsing: return 3
        case .ready: return 4
        }
    }

    var title: String {
        switch self {
        case .connecting: return "wheelsys.fleet.loading.connecting_title".localized
        case .fetching: return "wheelsys.fleet.loading.fetching_title".localized
        case .parsing: return "wheelsys.fleet.loading.parsing_title".localized
        case .ready: return "wheelsys.fleet.loading.ready_title".localized
        }
    }

    var microcopy: String {
        switch self {
        case .connecting: return "wheelsys.fleet.loading.connecting_micro".localized
        case .fetching: return "wheelsys.fleet.loading.fetching_micro".localized
        case .parsing: return "wheelsys.fleet.loading.parsing_micro".localized
        case .ready: return "wheelsys.fleet.loading.ready_micro".localized
        }
    }
}
