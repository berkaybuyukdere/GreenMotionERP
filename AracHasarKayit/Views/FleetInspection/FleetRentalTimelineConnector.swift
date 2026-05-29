import SwiftUI

/// Animated flow indicator from check-out toward pending return (LED-style pulse).
struct FleetRentalTimelineConnector: View {
    enum Axis { case horizontal, vertical }
    var isActive: Bool
    var axis: Axis = .horizontal

    @State private var pulsePhase: CGFloat = 0

    private var arrowIcon: String {
        axis == .vertical ? "arrow.down" : "arrow.right"
    }

    var body: some View {
        Group {
            if axis == .vertical {
                verticalBody
            } else {
                horizontalBody
            }
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsePhase = 1
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                pulsePhase = 0
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsePhase = 1
                }
            } else {
                pulsePhase = 0
            }
        }
    }

    private var horizontalBody: some View {
        VStack(spacing: 6) {
            arrowStack
                .frame(width: 36)
            if isActive {
                Capsule()
                    .fill(FleetInspectionTheme.accent.opacity(0.25))
                    .frame(width: 4, height: 28)
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(FleetInspectionTheme.accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: FleetInspectionTheme.accent.opacity(0.9), radius: 6)
                            .offset(y: pulsePhase * 20)
                    }
            }
        }
        .frame(width: 40)
    }

    private var verticalBody: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                if isActive {
                    Capsule()
                        .fill(FleetInspectionTheme.accent.opacity(0.25))
                        .frame(width: 4, height: 32)
                        .overlay(alignment: .top) {
                            Circle()
                                .fill(FleetInspectionTheme.accent)
                                .frame(width: 8, height: 8)
                                .shadow(color: FleetInspectionTheme.accent.opacity(0.9), radius: 6)
                                .offset(y: pulsePhase * 24)
                        }
                }
                arrowStack
            }
            .frame(width: 28)
        }
        .padding(.leading, 2)
    }

    private var arrowStack: some View {
        ZStack {
            Image(systemName: arrowIcon)
                .font(.system(size: axis == .vertical ? 18 : 22, weight: .bold))
                .foregroundStyle(FleetInspectionTheme.label.opacity(0.35))
            if isActive {
                Image(systemName: arrowIcon)
                    .font(.system(size: axis == .vertical ? 18 : 22, weight: .bold))
                    .foregroundStyle(FleetInspectionTheme.accent)
                    .mask(arrowPulseMask)
            }
        }
    }

    private var arrowPulseMask: some View {
        GeometryReader { geo in
            if axis == .vertical {
                LinearGradient(
                    colors: [.clear, FleetInspectionTheme.accent, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.45)
                .offset(y: -geo.size.height * 0.25 + pulsePhase * geo.size.height * 0.9)
            } else {
                LinearGradient(
                    colors: [.clear, FleetInspectionTheme.accent, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.45)
                .offset(x: -geo.size.width * 0.25 + pulsePhase * geo.size.width * 0.9)
            }
        }
    }
}
