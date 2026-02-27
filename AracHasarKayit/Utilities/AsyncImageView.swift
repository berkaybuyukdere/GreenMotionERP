import SwiftUI

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
        StorageImageLoader.shared.loadImage(from: urlString) { image in
            isLoading = false
            loadedImage = image
        }
    }
}
