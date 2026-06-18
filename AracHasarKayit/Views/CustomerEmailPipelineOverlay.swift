import SwiftUI

// MARK: - Pipeline kind

enum CustomerEmailPipelineKind: String {
    case returnConfirmation = "return"
    case checkoutConfirmation = "checkout"
}

// MARK: - Pipeline stage

/// Pipeline stage for checkout/return customer email (matches server + PDF flow).
enum CustomerEmailPipelineStage: Equatable {
    case checkingSettings
    case uploadingPhotos
    case creatingPDF
    case uploadingPDF
    case queueing
    case sendingMail
    case completed

    var statusText: String {
        switch self {
        case .checkingSettings:
            return "email.pipeline.checking_settings".localized
        case .uploadingPhotos:
            return "email.pipeline.uploading_photos".localized
        case .creatingPDF:
            return "email.pipeline.creating_pdf".localized
        case .uploadingPDF:
            return "email.pipeline.uploading_pdf".localized
        case .queueing:
            return "email.pipeline.queueing".localized
        case .sendingMail:
            return "email.pipeline.sending_mail".localized
        case .completed:
            return "email.pipeline.completed".localized
        }
    }

    /// Maps live progress messages from Exit/Iade detail send flows.
    static func from(progressMessage: String, progress: Double) -> CustomerEmailPipelineStage {
        if progress >= 1 {
            return .completed
        }
        let m = progressMessage.lowercased()
        if m.contains("smtp") || m.contains("sending via") || m.contains("retrying send") {
            return .sendingMail
        }
        if m.contains("queue") {
            return .queueing
        }
        if m.contains("uploading pdf") || m.contains("upload pdf") {
            return .uploadingPDF
        }
        if m.contains("building pdf") || m.contains("preparing pdf") || m.contains("rental terms") {
            return .creatingPDF
        }
        if m.contains("loading photo") || m.contains("optimizing") {
            return .uploadingPhotos
        }
        if m.contains("checking email") {
            return .checkingSettings
        }
        if progress >= 0.78 { return .sendingMail }
        if progress >= 0.62 { return .queueing }
        if progress >= 0.42 { return .uploadingPDF }
        if progress >= 0.18 { return .creatingPDF }
        return .checkingSettings
    }
}

// MARK: - Mail send icon + button

/// Envelope with a small send plane — reads as “mail” at a glance.
struct CustomerMailSendIcon: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "envelope.fill")
                .font(.system(size: size, weight: .semibold))
            Image(systemName: "paperplane.fill")
                .font(.system(size: size * 0.44, weight: .bold))
                .offset(x: size * 0.2, y: -size * 0.1)
        }
        .frame(width: size * 1.2, height: size)
        .accessibilityHidden(true)
    }
}

struct CustomerEmailSendButton: View {
    let title: String
    let sendingTitle: String
    let accentColor: Color
    let isSending: Bool
    var isExternallyDisabled: Bool = false
    let action: () -> Void

    private var isDisabled: Bool { isExternallyDisabled || isSending }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            HapticManager.shared.medium()
            action()
        } label: {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.88)
                } else {
                    CustomerMailSendIcon(size: 18)
                }
                Text(isSending ? sendingTitle : title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(isDisabled ? Color(.systemGray3) : accentColor)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isExternallyDisabled && !isSending ? 0.6 : 1)
    }
}

// MARK: - Full-screen pipeline overlay

/// Full-screen blue blocker while checkout/return customer email is in flight.
struct CustomerEmailPipelineOverlay: View {
    let progressMessage: String
    let progress: Double
    let photoSummary: String?
    var onContinueInBackground: (() -> Void)?

    @State private var displayedStage: CustomerEmailPipelineStage = .checkingSettings
    @State private var displayedMessage: String = ""
    @State private var appeared = false

    private var stage: CustomerEmailPipelineStage {
        CustomerEmailPipelineStage.from(progressMessage: progressMessage, progress: progress)
    }

    private var microStatusText: String {
        let trimmed = progressMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return displayedStage.statusText
    }

    private var isSuccessful: Bool {
        guard progress >= 0.99 else { return false }
        let combined = "\(progressMessage) \(displayedMessage)".lowercased()
        return combined.contains("delivered")
            || combined.contains("completed")
            || combined.contains("email sent")
    }

    private var headerTitle: String {
        isSuccessful ? "email.pipeline.sent_title".localized : "email.pipeline.title".localized
    }

    var body: some View {
        ZStack {
            pipelineBackground
                .animation(.easeInOut(duration: 0.45), value: isSuccessful)

            VStack(spacing: 28) {
                if isSuccessful {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isSuccessful)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(headerTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.35), value: isSuccessful)

                pipelineIconsRow
                    .frame(maxWidth: 340)

                VStack(spacing: 10) {
                    Text(isSuccessful ? "email.pipeline.sent_subtitle".localized : displayedMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.28), value: displayedMessage)

                    if !isSuccessful, let photoSummary, !photoSummary.isEmpty {
                        Text(photoSummary)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .frame(minHeight: 52)

                if !isSuccessful {
                    VStack(spacing: 10) {
                        Text("email.pipeline.background_hint".localized)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        if let onContinueInBackground {
                            Button(action: onContinueInBackground) {
                                Text("email.pipeline.continue_background".localized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("email.pipeline.title".localized)
        .onAppear {
            displayedStage = stage
            displayedMessage = microStatusText
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
        .onChange(of: stage) { _, newStage in
            withAnimation(.easeInOut(duration: 0.25)) {
                displayedStage = newStage
            }
        }
        .onChange(of: progressMessage) { _, _ in
            let resolved = stage
            let message = microStatusText
            if resolved != displayedStage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    displayedStage = resolved
                }
            }
            if message != displayedMessage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    displayedMessage = message
                }
            }
        }
        .onChange(of: progress) { _, _ in
            let resolved = stage
            if resolved != displayedStage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    displayedStage = resolved
                }
            }
            let message = microStatusText
            if message != displayedMessage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    displayedMessage = message
                }
            }
        }
    }

    private var pipelineBackground: some View {
        ZStack {
            LinearGradient(
                colors: isSuccessful ? [
                    Color(red: 0.12, green: 0.72, blue: 0.38).opacity(0.96),
                    Color(red: 0.05, green: 0.55, blue: 0.28).opacity(0.98),
                    Color(red: 0.02, green: 0.38, blue: 0.2),
                ] : [
                    Color.blue.opacity(0.95),
                    Color(red: 0.06, green: 0.34, blue: 0.78).opacity(0.97),
                    Color(red: 0.04, green: 0.22, blue: 0.58),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(isSuccessful ? 0.1 : 0.06))
                .frame(width: 280, height: 280)
                .offset(x: -120, y: -200)
            Circle()
                .fill(Color.white.opacity(isSuccessful ? 0.08 : 0.05))
                .frame(width: 220, height: 220)
                .offset(x: 140, y: 220)
        }
    }

    private var pipelineIconsRow: some View {
        HStack(alignment: .center, spacing: 20) {
            pipelineEndpointIcon(systemName: "doc.fill", isLit: stage != .checkingSettings || isSuccessful)

            PipelineArrowTrack(isAnimating: !isSuccessful)
                .frame(maxWidth: .infinity)
                .frame(height: 72)

            pipelineEndpointIcon(
                systemName: isSuccessful ? "envelope.badge.fill" : "envelope.fill",
                isLit: stage == .sendingMail || stage == .completed || stage == .queueing || isSuccessful
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func pipelineEndpointIcon(systemName: String, isLit: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isLit ? 0.32 : 0.14))
                .frame(width: 64, height: 64)
            Circle()
                .stroke(Color.white.opacity(isLit ? 0.6 : 0.22), lineWidth: 2)
                .frame(width: 64, height: 64)
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(isLit ? 1 : 0.65))
                .symbolEffect(.bounce, value: isLit)
        }
        .frame(width: 72, height: 72)
    }
}

// MARK: - Arrow track (arrow + glow move together L → R)

private struct PipelineArrowTrack: View {
    let isAnimating: Bool
    private let cycleSeconds: Double = 1.55

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let centerY = proxy.size.height / 2
            let trackHeight: CGFloat = 6
            let arrowSize: CGFloat = 26
            let inset = arrowSize * 0.5
            let travelWidth = max(1, trackWidth - arrowSize)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: trackWidth, height: trackHeight)
                    .position(x: trackWidth / 2, y: centerY)

                if isAnimating {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                        let phase = animationPhase(at: context.date)
                        let arrowX = inset + phase * travelWidth
                        let pulse = 0.5 + 0.5 * sin(Double(phase) * .pi * 4)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.9 * pulse),
                                        Color.white.opacity(0.35 * pulse),
                                        Color.clear,
                                    ],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: 24
                                )
                            )
                            .frame(width: 48, height: 48)
                            .blur(radius: 4)
                            .position(x: arrowX, y: centerY)

                        Capsule()
                            .fill(Color.white.opacity(0.42 * pulse))
                            .frame(width: 40, height: trackHeight)
                            .blur(radius: 1)
                            .position(x: arrowX, y: centerY)

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: arrowSize, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .white.opacity(0.95 * pulse), radius: 10 + CGFloat(8 * pulse), x: 0, y: 0)
                            .shadow(color: Color.cyan.opacity(0.4 * pulse), radius: 5, x: 0, y: 0)
                            .scaleEffect(1.0 + 0.1 * CGFloat(pulse))
                            .position(x: arrowX, y: centerY)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: arrowSize, weight: .bold))
                        .foregroundStyle(.white)
                        .position(x: trackWidth - inset, y: centerY)
                }
            }
        }
    }

    private func animationPhase(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
        let raw = (elapsed.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds
        return CGFloat(raw)
    }
}
