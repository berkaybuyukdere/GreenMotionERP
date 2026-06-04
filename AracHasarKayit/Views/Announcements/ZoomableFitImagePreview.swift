import SwiftUI
import UIKit

/// Pinch-to-zoom image preview that starts fit-to-screen.
struct ZoomableFitImagePreview: UIViewRepresentable {
    let url: URL
    let remoteURL: URL?

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.backgroundColor = .black
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tag = 100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.imageView = imageView
        context.coordinator.load(url: url, remoteURL: remoteURL)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func load(url: URL, remoteURL: URL?) {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                imageView?.image = image
                return
            }
            guard let remoteURL else { return }
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: remoteURL),
                   let image = UIImage(data: data) {
                    await MainActor.run { self.imageView?.image = image }
                }
            }
        }
    }
}
