import SwiftUI

struct VehicleSerialPhotoGuideStep: Identifiable {
    let id: Int
    let titleKey: String
}

enum VehicleSerialPhotoGuide {
    static let steps: [VehicleSerialPhotoGuideStep] = [
        .init(id: 1, titleKey: "serial_photo.step_01"),
        .init(id: 2, titleKey: "serial_photo.step_02"),
        .init(id: 3, titleKey: "serial_photo.step_03"),
        .init(id: 4, titleKey: "serial_photo.step_04"),
        .init(id: 5, titleKey: "serial_photo.step_05"),
        .init(id: 6, titleKey: "serial_photo.step_06"),
        .init(id: 7, titleKey: "serial_photo.step_07"),
        .init(id: 8, titleKey: "serial_photo.step_08"),
        .init(id: 9, titleKey: "serial_photo.step_09"),
        .init(id: 10, titleKey: "serial_photo.step_10"),
        .init(id: 11, titleKey: "serial_photo.step_11"),
        .init(id: 12, titleKey: "serial_photo.step_12"),
        .init(id: 13, titleKey: "serial_photo.step_13"),
        .init(id: 14, titleKey: "serial_photo.step_14"),
        .init(id: 15, titleKey: "serial_photo.step_15"),
        .init(id: 16, titleKey: "serial_photo.step_16"),
        .init(id: 17, titleKey: "serial_photo.step_17"),
        .init(id: 18, titleKey: "serial_photo.step_18"),
        .init(id: 19, titleKey: "serial_photo.step_19"),
        .init(id: 20, titleKey: "serial_photo.step_20"),
        .init(id: 21, titleKey: "serial_photo.step_21"),
        .init(id: 22, titleKey: "serial_photo.step_22"),
        .init(id: 23, titleKey: "serial_photo.step_23"),
        .init(id: 24, titleKey: "serial_photo.step_24"),
        .init(id: 25, titleKey: "serial_photo.step_25"),
        .init(id: 26, titleKey: "serial_photo.step_26"),
        .init(id: 27, titleKey: "serial_photo.step_27"),
        .init(id: 28, titleKey: "serial_photo.step_28"),
    ]
}

struct VehicleSerialPhotoGuideOverlay: View {
    let capturedCount: Int

    private let totalSteps = VehicleSerialPhotoGuide.steps.count

    private var normalizedCapturedCount: Int {
        capturedCount.clamped(to: 0...totalSteps)
    }

    private var currentStepIndex: Int {
        capturedCount.clamped(to: 0...(totalSteps - 1))
    }

    private var isComplete: Bool {
        normalizedCapturedCount >= totalSteps
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(normalizedCapturedCount) / Double(totalSteps)
    }

    private var currentStep: VehicleSerialPhotoGuideStep {
        VehicleSerialPhotoGuide.steps[currentStepIndex]
    }

    private var upcomingSteps: [VehicleSerialPhotoGuideStep] {
        guard !isComplete else { return [] }
        let start = currentStepIndex + 1
        let end = min(totalSteps, start + 3)
        guard start < end else { return [] }
        return Array(VehicleSerialPhotoGuide.steps[start..<end])
    }

    var body: some View {
        VStack {
            guideCard
            Spacer()
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("serial_photo.guide_title".localized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Text(String(format: "serial_photo.step_of".localized, normalizedCapturedCount, totalSteps))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, proxy.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isComplete ? "\(totalSteps)" : "\(currentStep.id)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(minWidth: 28)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.yellow))

                Text(isComplete ? "serial_photo.all_done".localized : currentStep.titleKey.localized)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }

            if !upcomingSteps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(upcomingSteps) { step in
                            Text(step.titleKey.localized)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.12))
                                )
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
