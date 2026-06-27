import SwiftUI

/// One step in the checkout / return completion animation — icon cycles as phases advance.
struct PalantirOpsCompletionStep: Equatable {
    let icon: String
    let label: String
}

/// Palantir-styled completion overlay with phase icons, progress ring, and success state.
struct PalantirOpsCompletionOverlay: View {
    let title: String
    let steps: [PalantirOpsCompletionStep]
    let activeStepIndex: Int
    let progress: Double
    let succeeded: Bool
    let successTitle: String
    var microcopy: String? = nil

    @State private var iconSpin = false
    @State private var displayedStepIndex: Int = 0

    private var clampedProgress: Double { min(1, max(0, progress)) }
    private var activeStep: PalantirOpsCompletionStep? {
        guard !steps.isEmpty else { return nil }
        let idx = min(max(0, displayedStepIndex), steps.count - 1)
        return steps[idx]
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(PalantirTheme.background.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if succeeded {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(PalantirTheme.success)
                        .transition(.scale.combined(with: .opacity))
                    Text(successTitle)
                        .font(PalantirTheme.heroFont(15))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .multilineTextAlignment(.center)
                } else {
                    phaseIcon
                    Text(title)
                        .font(PalantirTheme.heroFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    if let step = activeStep {
                        Text(step.label.uppercased())
                            .font(PalantirTheme.labelFont(9))
                            .tracking(0.7)
                            .foregroundStyle(PalantirTheme.accent)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.25), value: displayedStepIndex)
                    }

                    ZStack {
                        Rectangle()
                            .stroke(PalantirTheme.border, lineWidth: 3)
                            .frame(width: 64, height: 64)
                        Rectangle()
                            .trim(from: 0, to: clampedProgress)
                            .stroke(PalantirTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 64, height: 64)
                            .animation(.linear(duration: 0.2), value: clampedProgress)
                        Text("\(Int((clampedProgress * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(PalantirTheme.textPrimary)
                    }

                    if let microcopy, !microcopy.isEmpty {
                        Text(microcopy)
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }

                    if steps.count > 1 {
                        stepDots
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: 300)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
        .onAppear {
            displayedStepIndex = activeStepIndex
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                iconSpin = true
            }
        }
        .onChange(of: activeStepIndex) { _, newIndex in
            withAnimation(.easeInOut(duration: 0.28)) {
                displayedStepIndex = newIndex
            }
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        let symbol = activeStep?.icon ?? "arrow.triangle.2.circlepath"
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(PalantirTheme.accent)
            .rotationEffect(.degrees(iconSpin ? 360 : 0))
            .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: iconSpin)
            .frame(height: 44)
            .id(symbol)
            .transition(.scale.combined(with: .opacity))
    }

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps.count, id: \.self) { index in
                Rectangle()
                    .fill(index <= displayedStepIndex ? PalantirTheme.accent : PalantirTheme.border)
                    .frame(width: index == displayedStepIndex ? 18 : 8, height: 3)
                    .animation(.easeInOut(duration: 0.2), value: displayedStepIndex)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Step builders

enum PalantirCheckoutCompletionSteps {
    static func steps(wheelSysEnabled: Bool) -> [PalantirOpsCompletionStep] {
        if wheelSysEnabled {
            return [
                PalantirOpsCompletionStep(icon: "photo.fill", label: "palantir.completion.upload_photos".localized),
                PalantirOpsCompletionStep(icon: "checkmark.shield.fill", label: "wheelsys.checkout.sync.validating".localized),
                PalantirOpsCompletionStep(icon: "function", label: "wheelsys.checkout.sync.calculating".localized),
                PalantirOpsCompletionStep(icon: "car.fill", label: "wheelsys.checkout.sync.saving".localized),
            ]
        }
        return [
            PalantirOpsCompletionStep(icon: "photo.fill", label: "palantir.completion.upload_photos".localized),
            PalantirOpsCompletionStep(icon: "square.and.arrow.down.fill", label: "palantir.completion.saving".localized),
        ]
    }

    static func activeIndex(
        progress: Double,
        wheelSysEnabled: Bool,
        syncPhase: WheelSysCheckoutAssignmentCoordinator.CompletionSyncPhase
    ) -> Int {
        guard wheelSysEnabled else {
            return progress >= 0.72 ? 1 : 0
        }
        switch syncPhase {
        case .validating: return 1
        case .calculating: return 2
        case .saving, .done: return 3
        case .warning, .idle:
            return progress >= 0.72 ? 1 : 0
        }
    }
}

enum PalantirReturnCompletionSteps {
    static let steps: [PalantirOpsCompletionStep] = [
        PalantirOpsCompletionStep(icon: "photo.fill", label: "palantir.completion.upload_photos".localized),
        PalantirOpsCompletionStep(icon: "doc.text.fill", label: "wheelsys.precheckin.title".localized),
        PalantirOpsCompletionStep(icon: "arrow.down.circle.fill", label: "wheelsys.return.sync.saving_rental".localized),
        PalantirOpsCompletionStep(icon: "car.fill", label: "wheelsys.return.sync.saving_vehicle".localized),
        PalantirOpsCompletionStep(icon: "note.text", label: "wheelsys.return.sync.saving_notes".localized),
    ]

    static func activeIndex(
        progress: Double,
        precheckinBusy: Bool,
        syncPhase: WheelSysReturnCheckinCoordinator.CompletionSyncPhase
    ) -> Int {
        if precheckinBusy { return 1 }
        switch syncPhase {
        case .savingRental: return 2
        case .savingVehicle: return 3
        case .savingNotes, .done: return 4
        case .warning, .idle:
            return progress >= 0.72 ? 2 : 0
        }
    }
}
