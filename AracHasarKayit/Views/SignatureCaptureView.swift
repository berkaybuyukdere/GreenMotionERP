import SwiftUI
import UIKit

/// Compact customer signature thumbnail for checkout/return forms.
/// Uses SwiftUI `Image` with a fixed height so large exported bitmaps (1200×500) do not blow up layout.
struct CustomerSignaturePreview: View {
    let image: UIImage
    var height: CGFloat = 80

    var body: some View {
        Image(uiImage: image)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .environment(\.colorScheme, .light)
    }
}

/// Signature preview + update/remove actions (DE/CH/UK checkout & return forms).
struct CustomerSignatureFormBlock: View {
    let image: UIImage
    var previewHeight: CGFloat = 80
    var onUpdate: () -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomerSignaturePreview(image: image, height: previewHeight)
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(PalantirTheme.success)
                Text("operations.signature_captured".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer(minLength: 0)
                Button("Update Signature".localized, action: onUpdate)
                    .font(PalantirTheme.labelFont(11))
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(PalantirTheme.surfaceHigh)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
    }
}

/// Signature stored for PDF — no bitmap preview (avoids layout jank).
struct CustomerSignatureCapturedIndicator: View {
    var onUpdate: () -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PalantirTheme.success)
            Text("operations.signature_captured".localized)
                .font(PalantirTheme.bodyFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer(minLength: 0)
            Button("Update Signature".localized, action: onUpdate)
                .font(PalantirTheme.labelFont(11))
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.surfaceHigh)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var signatureImage: UIImage?
    @State private var points: [CGPoint] = []
    @State private var canvasSize: CGSize = CGSize(width: 360, height: 260)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Text("Customer Signature".localized)
                    .font(.headline)
                
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                            )
                        
                        Path { path in
                            guard let firstPoint = points.first else { return }
                            path.move(to: firstPoint)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                points.append(value.location)
                            }
                    )
                    .onAppear {
                        canvasSize = geometry.size
                        if let existing = signatureImage {
                            // Keep previous signature as-is; drawing starts fresh unless cleared
                            if points.isEmpty {
                                points = []
                            }
                            _ = existing
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("Sign inside this area".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                }
                .frame(height: 260)
                
                HStack(spacing: 12) {
                    Button("Clear".localized) {
                        points.removeAll()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save Signature".localized) {
                        saveSignature()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(points.count < 3)
                }
            }
            .padding()
            .navigationTitle("Signature".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized) { dismiss() }
                }
            }
        }
    }
    
    private func saveSignature() {
        let size = CGSize(width: 1200, height: 500)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            guard points.count > 1 else { return }
            let path = UIBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            let sourceWidth = max(canvasSize.width, 1)
            let sourceHeight = max(canvasSize.height, 1)
            let scaleX = size.width / sourceWidth
            let scaleY = size.height / sourceHeight
            
            let start = CGPoint(x: points[0].x * scaleX, y: points[0].y * scaleY)
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
            }
            UIColor.black.setStroke()
            path.stroke()
        }
        signatureImage = image.withRenderingMode(.alwaysOriginal)
    }
}
