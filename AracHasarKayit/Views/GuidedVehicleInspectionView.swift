import SwiftUI

/// MVP guided exterior checklist (four sides) with optional quality warning after each capture.
enum VehicleInspectionAngle: Int, CaseIterable, Identifiable {
    case front = 0
    case rear
    case left
    case right

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .front: return "Front".localized
        case .rear: return "Rear".localized
        case .left: return "Left side".localized
        case .right: return "Right side".localized
        }
    }

    var symbolName: String {
        switch self {
        case .front: return "arrow.up.circle"
        case .rear: return "arrow.down.circle"
        case .left: return "arrow.left.circle"
        case .right: return "arrow.right.circle"
        }
    }
}

struct GuidedVehicleInspectionView: View {
    let plateDisplay: String
    let vehicleSubtitle: String
    var onFinished: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var captures: [VehicleInspectionAngle: UIImage] = [:]
    @State private var showCamera = false
    @State private var pendingImage: UIImage?
    @State private var qualityWarning: String?
    @State private var showQualityAlert = false

    private var orderedAngles: [VehicleInspectionAngle] {
        VehicleInspectionAngle.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    private var currentAngle: VehicleInspectionAngle {
        orderedAngles[min(currentIndex, orderedAngles.count - 1)]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                GlassVehicleInfoCard(
                    plate: plateDisplay,
                    subtitle: vehicleSubtitle,
                    statusLine: String(format: "Step %d of %d".localized, currentIndex + 1, orderedAngles.count)
                )
                .padding(.horizontal)

                GlassInspectionProgressBar(
                    total: orderedAngles.count,
                    completed: captures.count
                )
                .padding(.horizontal)

                VStack(spacing: 14) {
                    Image(systemName: currentAngle.symbolName)
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(currentAngle.title)
                        .font(.title2.weight(.semibold))
                    Text("Align the vehicle in the frame, then use the camera shutter.".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassChromeSurface(cornerRadius: 18)
                .padding(.horizontal)

                Spacer(minLength: 0)

                GlassDamageActionBar(leading: {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }, trailing: {
                    Button(captures[currentAngle] != nil ? "Retake".localized : "Capture".localized) {
                        showCamera = true
                    }
                    .buttonStyle(.borderedProminent)
                })
                .padding(.horizontal)
                .padding(.bottom, 8)

                if captures.count == orderedAngles.count {
                    Button("Add photos to damage".localized) {
                        let images = orderedAngles.compactMap { captures[$0] }
                        onFinished(images)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Guided capture".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $pendingImage)
            }
            .alert("Photo quality".localized, isPresented: $showQualityAlert) {
                Button("Retake".localized, role: .cancel) {
                    pendingImage = nil
                    showCamera = true
                }
                Button("Use anyway".localized) {
                    acceptPending(andAdvance: true)
                }
            } message: {
                Text(qualityWarning ?? "")
            }
        }
    }

    private func handleCameraDismiss() {
        guard let img = pendingImage else { return }
        if ImageInspectionQuality.isAcceptable(img) {
            captures[currentAngle] = img
            pendingImage = nil
            advanceIfPossible()
        } else {
            qualityWarning = "This photo looks soft or dark. Retake or use it anyway.".localized
            showQualityAlert = true
        }
    }

    private func acceptPending(andAdvance: Bool) {
        if let img = pendingImage {
            captures[currentAngle] = img
            pendingImage = nil
        }
        if andAdvance {
            advanceIfPossible()
        }
    }

    private func advanceIfPossible() {
        if currentIndex + 1 < orderedAngles.count {
            currentIndex += 1
        }
    }
}

struct GlassInspectionProgressBar: View {
    let total: Int
    let completed: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < completed ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassChromeSurface(cornerRadius: 12)
    }
}
