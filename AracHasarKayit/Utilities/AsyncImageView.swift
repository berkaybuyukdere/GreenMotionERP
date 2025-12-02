import SwiftUI
import Kingfisher

/// AsyncImageView with Kingfisher integration
/// Maintains backward compatibility with existing API
struct AsyncImageView<Content: View>: View {
    let urlString: String
    let content: (Image) -> Content
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = loadedImage {
                // Image loaded - apply content transformation
                content(Image(uiImage: image))
            } else if isLoading {
                // Loading state
                ProgressView()
                    .frame(width: 120, height: 120)
            } else {
                // Error state
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        // Use Kingfisher to load image with automatic caching
        KingfisherManager.shared.retrieveImage(with: url) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let value):
                    loadedImage = value.image
                case .failure:
                    loadedImage = nil
                }
            }
        }
    }
}
