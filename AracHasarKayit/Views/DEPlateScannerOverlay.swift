import SwiftUI

/// Professional ANPR-style viewfinder overlay for Germany DE plate scanning.
/// - Darkens the areas outside the plate frame
/// - Shows corner brackets with an optional scanning pulse animation
/// - Displays the last recognized plate text below the frame
struct DEPlateScannerOverlay: View {
    var isScanning: Bool
    var detectedPlate: String

    @State private var pulse = false

    // Plate frame dimensions: German plate ratio is roughly 4.7 : 1
    // We use a fraction of the screen width and derive height.
    private let frameWidthFraction: CGFloat = 0.88
    private let plateAspect: CGFloat = 4.7
    private let cornerLength: CGFloat = 22
    private let cornerThickness: CGFloat = 3.5

    var body: some View {
        GeometryReader { geo in
            let frameW = geo.size.width * frameWidthFraction
            let frameH = frameW / plateAspect
            let frameX = (geo.size.width - frameW) / 2
            let frameY = geo.size.height * 0.38 - frameH / 2
            let frameRect = CGRect(x: frameX, y: frameY, width: frameW, height: frameH)

            ZStack {
                // Dimming mask with a clear cutout for the plate area
                CutoutMask(rect: frameRect)
                    .fill(Color.black.opacity(0.52))
                    .ignoresSafeArea()

                // Corner brackets
                CornerBrackets(rect: frameRect,
                               cornerLength: cornerLength,
                               thickness: cornerThickness,
                               color: isScanning ? .green : .white)
                    .scaleEffect(pulse ? 1.015 : 1.0)
                    .animation(
                        isScanning
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )

                // Scanning line (only when active)
                if isScanning {
                    ScanLine(rect: frameRect)
                }

                // Status label
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: frameY + frameH + 14)

                    HStack(spacing: 8) {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.white)
                        }
                        Text(isScanning
                             ? "DE plate scanning".localized
                             : "DE plate scanning hint".localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.60))
                    )

                    if !detectedPlate.isEmpty {
                        Text(detectedPlate)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                                    )
                            )
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    Spacer()
                }
                .frame(width: geo.size.width)
                .animation(.easeInOut(duration: 0.25), value: detectedPlate)
            }
            .onChange(of: isScanning) { scanning in
                pulse = scanning
            }
            .onAppear {
                pulse = isScanning
            }
        }
    }
}

// MARK: - Cutout mask

private struct CutoutMask: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        var p = Path()
        p.addRect(bounds)
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
        return p
    }

    var fillStyle: FillStyle { FillStyle(eoFill: true) }
}

// MARK: - Corner brackets

private struct CornerBrackets: View {
    let rect: CGRect
    let cornerLength: CGFloat
    let thickness: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, _ in
            let corners: [(CGPoint, Bool, Bool)] = [
                (CGPoint(x: rect.minX, y: rect.minY), true,  true),
                (CGPoint(x: rect.maxX, y: rect.minY), false, true),
                (CGPoint(x: rect.maxX, y: rect.maxY), false, false),
                (CGPoint(x: rect.minX, y: rect.maxY), true,  false),
            ]

            for (origin, isLeft, isTop) in corners {
                var h = Path()
                let hEnd = CGPoint(
                    x: origin.x + (isLeft ? cornerLength : -cornerLength),
                    y: origin.y
                )
                h.move(to: origin)
                h.addLine(to: hEnd)

                var v = Path()
                let vEnd = CGPoint(
                    x: origin.x,
                    y: origin.y + (isTop ? cornerLength : -cornerLength)
                )
                v.move(to: origin)
                v.addLine(to: vEnd)

                ctx.stroke(h, with: .color(color), lineWidth: thickness)
                ctx.stroke(v, with: .color(color), lineWidth: thickness)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Animated scan line

private struct ScanLine: View {
    let rect: CGRect
    @State private var offset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.green.opacity(0.7), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: rect.width, height: 2)
            .position(x: rect.midX, y: rect.minY + offset)
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
                    offset = rect.height
                }
            }
            .clipped()
    }
}
