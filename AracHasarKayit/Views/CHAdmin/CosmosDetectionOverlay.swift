import SwiftUI

/// Maps normalized content rects onto an aspect-fill camera preview.
struct CosmosAspectFillMapper {
    let viewSize: CGSize
    let contentSize: CGSize

    func mapNormalizedRect(_ normalized: CGRect) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              contentSize.width > 0, contentSize.height > 0 else { return .zero }

        let contentAspect = contentSize.width / contentSize.height
        let viewAspect = viewSize.width / viewSize.height

        let displayW: CGFloat
        let displayH: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if contentAspect > viewAspect {
            displayH = viewSize.height
            displayW = viewSize.height * contentAspect
            offsetX = (viewSize.width - displayW) / 2
            offsetY = 0
        } else {
            displayW = viewSize.width
            displayH = viewSize.width / contentAspect
            offsetX = 0
            offsetY = (viewSize.height - displayH) / 2
        }

        return CGRect(
            x: offsetX + normalized.origin.x * displayW,
            y: offsetY + normalized.origin.y * displayH,
            width: normalized.width * displayW,
            height: normalized.height * displayH
        )
    }
}

struct CosmosDetectionOverlay: View {
    let objects: [CosmosDetectedObject]
    let frameSize: CGSize
    let licensePlate: String?
    let isAnalyzing: Bool

    var body: some View {
        GeometryReader { geo in
            let mapper = CosmosAspectFillMapper(viewSize: geo.size, contentSize: frameSize)

            ZStack {
                if isAnalyzing {
                    ScanPulseReticle()
                }

                ForEach(objects) { obj in
                    let rect = mapper.mapNormalizedRect(obj.rect)
                    if rect.width > 4, rect.height > 4 {
                        detectionBox(obj: obj, rect: rect, highlighted: obj.isPlateLike || isPlateMatch(obj))
                    }
                }

                if licensePlate != nil, let plateObj = objects.first(where: { $0.isPlateLike }) {
                    let rect = mapper.mapNormalizedRect(plateObj.rect)
                    PlateLockBadge(plate: licensePlate ?? "", rect: rect)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func isPlateMatch(_ obj: CosmosDetectedObject) -> Bool {
        guard let plate = licensePlate?.lowercased(), !plate.isEmpty else { return false }
        return obj.label.lowercased().contains(plate) || obj.isPlateLike
    }

    @ViewBuilder
    private func detectionBox(obj: CosmosDetectedObject, rect: CGRect, highlighted: Bool) -> some View {
        let color = highlighted ? Color.green : Color.cyan

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color, lineWidth: highlighted ? 3 : 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Text("\(obj.label) \(obj.confidencePercent)%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(x: rect.midX, y: max(14, rect.minY - 10))
        }
    }
}

private struct PlateLockBadge: View {
    let plate: String
    let rect: CGRect

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
            Text(plate)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green)
        .clipShape(Capsule())
        .shadow(color: .green.opacity(0.5), radius: 8)
        .position(x: rect.midX, y: min(rect.maxY + 18, rect.midY + rect.height * 0.6))
    }
}

private struct ScanPulseReticle: View {
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 48
            let w = geo.size.width - inset * 2
            let h = geo.size.height * 0.38
            let x = inset
            let y = geo.size.height * 0.22

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.green.opacity(pulse ? 0.15 : 0.45), lineWidth: 2)
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)

                ReticleCorners()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ReticleCorners: Shape {
    private let arm: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        return p
    }
}
