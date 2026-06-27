import SwiftUI

/// Static Palantir grid backdrop — rasterized once per layout pass to keep scroll smooth.
struct PalantirWireframeBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                PalantirTheme.background
                wireframeCanvas(size: geo.size)
            }
            .drawingGroup(opaque: true, colorMode: .nonLinear)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
    }

    private func wireframeCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let stroke = StrokeStyle(lineWidth: 1)
            let frame = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 10, dy: 10)
            context.stroke(
                Path(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)),
                with: .color(PalantirTheme.wireframeLine),
                style: stroke
            )

            let stepX = max(72, size.width / 6)
            let stepY = max(64, size.height / 9)

            var x: CGFloat = frame.minX + stepX
            while x < frame.maxX {
                var path = Path()
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))
                context.stroke(path, with: .color(PalantirTheme.wireframeLine.opacity(0.7)), style: stroke)
                x += stepX
            }

            var y: CGFloat = frame.minY + stepY
            while y < frame.maxY {
                var path = Path()
                path.move(to: CGPoint(x: frame.minX, y: y))
                path.addLine(to: CGPoint(x: frame.maxX, y: y))
                context.stroke(path, with: .color(PalantirTheme.wireframeLine.opacity(0.55)), style: stroke)
                y += stepY
            }

            // Lightweight label hints (canvas only — avoids dozens of Text layout during scroll).
            let labels = ["ERPX", "AUTH", "OPS", "CH", "SYNC"]
            let colStep = max(120, size.width / 5)
            let rowStep: CGFloat = 90
            var rowY = frame.minY + 18
            var labelIndex = 0
            while rowY < frame.maxY - 12 {
                var colX = frame.minX + 14
                while colX < frame.maxX - 20 {
                    let text = labels[labelIndex % labels.count]
                    context.draw(
                        Text(text)
                            .font(PalantirTheme.dataFont(8))
                            .foregroundStyle(PalantirTheme.wireframeText.opacity(0.3)),
                        at: CGPoint(x: colX, y: rowY),
                        anchor: .topLeading
                    )
                    labelIndex += 1
                    colX += colStep
                }
                rowY += rowStep
            }
        }
    }
}
