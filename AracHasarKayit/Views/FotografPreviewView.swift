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
                                            scale *= delta
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                            if scale < 1.0 {
                                                withAnimation {
                                                    scale = 1.0
                                                    offset = .zero
                                                }
                                            } else if scale > 4.0 {
                                                withAnimation {
                                                    scale = 4.0
                                                }
                                            }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
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
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.0
                                        // Calculate offset to focus on tap location
                                        let tapX = location.x - geometry.size.width / 2
                                        let tapY = location.y - geometry.size.height / 2
                                        offset = CGSize(width: -tapX, height: -tapY)
                                        lastOffset = offset
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
                        
                        Text("Fotoğraf yükleniyor...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Fotoğraf yüklenemedi")
                            .foregroundColor(.white)
                        
                        Button {
                            loadImage()
                        } label: {
                            Text("Tekrar Dene")
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
                            Text("Kapat")
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
    
    func loadImage() {
        isLoading = true
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isLoading = false
                print("❌ Failed to load image: Invalid URL")
            }
            return
        }
        
        KingfisherManager.shared.retrieveImage(with: url) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    self.image = value.image
                    print("✅ Image loaded successfully")
                case .failure(let error):
                    print("❌ Failed to load image: \(error.localizedDescription)")
                }
                self.isLoading = false
            }
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
