import SwiftUI
import Kingfisher

struct FotografPreviewView: View {
    let urlString: String
    @Environment(\.dismiss) var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadAttempted = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    GeometryReader { geometry in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            // Hard-clamp: minimum 1.0 (fit-to-screen), maximum 10.0
                                            scale = max(1.0, min(10.0, scale * delta))
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                            if scale < 1.0 {
                                                withAnimation {
                                                    scale = 1.0
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            } else if scale > 10.0 {
                                                withAnimation { scale = 10.0 }
                                            }
                                            // Clamp offset to visible bounds after zoom ends
                                            let constrained = constrainedOffset(offset, scale: scale, imageSize: image.size, viewSize: geometry.size)
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                                offset = constrained
                                                lastOffset = constrained
                                            }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                let newOffset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                                offset = constrainedOffset(newOffset, scale: scale, imageSize: image.size, viewSize: geometry.size)
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2, perform: { location in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if scale > 1.0 {
                                        // Zoom back to fit
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        // Zoom in centred on tap point, constrained to bounds
                                        let targetScale: CGFloat = 2.5
                                        let tapX = location.x - geometry.size.width / 2
                                        let tapY = location.y - geometry.size.height / 2
                                        let rawOffset = CGSize(
                                            width: -tapX * (targetScale - 1.0),
                                            height: -tapY * (targetScale - 1.0)
                                        )
                                        let constrained = constrainedOffset(rawOffset, scale: targetScale, imageSize: image.size, viewSize: geometry.size)
                                        scale = targetScale
                                        offset = constrained
                                        lastOffset = constrained
                                    }
                                }
                            })
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                } else if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Fotoğraf yükleniyor...".localized)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Fotoğraf yüklenemedi".localized)
                            .foregroundColor(.white)
                        
                        Button {
                            loadImage()
                        } label: {
                            Text("Tekrar Dene".localized)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                            Text("Kapat".localized)
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            // Only load once
            if !loadAttempted {
                loadAttempted = true
                loadImage()
            }
        }
        .task {
            // Alternative loading using task (more reliable)
            await loadImageAsync()
        }
    }
    
    /// Returns an offset clamped so the scaled image never leaves the visible area.
    private func constrainedOffset(_ offset: CGSize, scale: CGFloat, imageSize: CGSize, viewSize: CGSize) -> CGSize {
        guard scale > 1.0 else { return .zero }
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        let fittedWidth: CGFloat
        let fittedHeight: CGFloat
        if imageAspect > viewAspect {
            fittedWidth = viewSize.width
            fittedHeight = viewSize.width / imageAspect
        } else {
            fittedHeight = viewSize.height
            fittedWidth = viewSize.height * imageAspect
        }
        let maxX = max(0, (fittedWidth * scale - viewSize.width) / 2)
        let maxY = max(0, (fittedHeight * scale - viewSize.height) / 2)
        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    func loadImage() {
        isLoading = true
        StorageImageLoader.shared.loadImage(from: urlString) { [self] loadedImage in
            if let loadedImage {
                self.image = loadedImage
                print("✅ Image loaded successfully")
            } else {
                print("❌ Failed to load image from all candidates")
            }
            self.isLoading = false
        }
    }
    
    func loadImageAsync() async {
        // Ensure we're on main thread
        await MainActor.run {
            if image == nil && !isLoading {
                loadImage()
            }
        }
    }
}
