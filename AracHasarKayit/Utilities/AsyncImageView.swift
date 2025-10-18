import SwiftUI

struct AsyncImageView<Content: View>: View {
    let urlString: String
    let content: (Image) -> Content
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else if isLoading {
                ProgressView()
                    .frame(width: 120, height: 120)
            } else {
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
    
    func loadImage() {
        CachedImageManager.shared.loadImage(urlString) { loadedImage in
            DispatchQueue.main.async {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}
