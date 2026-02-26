import SwiftUI
import UIKit

struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var signatureImage: UIImage?
    @State private var points: [CGPoint] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Text("Customer Signature".localized)
                    .font(.headline)
                
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
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
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                points.append(value.location)
                            }
                    )
                    .onAppear {
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
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            guard points.count > 1 else { return }
            let path = UIBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            let scaleX = size.width / 360.0
            let scaleY = size.height / 260.0
            
            let start = CGPoint(x: points[0].x * scaleX, y: points[0].y * scaleY)
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
            }
            UIColor.black.setStroke()
            path.stroke()
        }
        signatureImage = image
    }
}

