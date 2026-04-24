import SwiftUI
import UIKit

/// Use with `fullScreenCover(item:)` so each open carries the tapped photo index reliably.
struct PhotoGallerySheetItem: Identifiable {
    let id = UUID()
    let startIndex: Int
}

// MARK: - SwiftUI Entry Point
// Full-screen photo gallery backed entirely by UIKit UIScrollView.
// Zoom is always relative to the exact pinch centre (native UIScrollView behaviour),
// identical to the Working Hours plan preview.
// Supports local UIImages and remote URL strings.

struct NativePhotoGalleryView: UIViewControllerRepresentable {

    private let localImages: [UIImage]?
    private let remoteURLs: [String]?
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss

    init(images: [UIImage], initialIndex: Int = 0) {
        self.localImages = images
        self.remoteURLs = nil
        let n = max(images.count - 1, 0)
        self.initialIndex = min(max(initialIndex, 0), n)
    }

    init(urlStrings: [String], initialIndex: Int = 0) {
        self.localImages = nil
        self.remoteURLs = urlStrings
        let n = max(urlStrings.count - 1, 0)
        self.initialIndex = min(max(initialIndex, 0), n)
    }

    func makeUIViewController(context: Context) -> NativeGalleryVC {
        NativeGalleryVC(
            images: localImages,
            urlStrings: remoteURLs,
            initialIndex: initialIndex,
            onDismiss: { dismiss() }
        )
    }

    func updateUIViewController(_ vc: NativeGalleryVC, context: Context) {
        vc.syncToPageIndex(initialIndex, animated: false)
    }
}

// MARK: - Gallery View Controller

final class NativeGalleryVC: UIViewController {

    private let localImages: [UIImage]?
    private let remoteURLs: [String]?
    private let startIndex: Int
    private let onDismiss: () -> Void

    private var count: Int { localImages?.count ?? remoteURLs?.count ?? 0 }
    private var currentPage: Int

    private let pagingScroll = UIScrollView()
    private var pages: [ZoomPhotoPage] = []
    private var pageControl: UIPageControl?
    /// When layout width was 0, apply scroll after first layout.
    private var pendingScrollIndex: Int?

    init(images: [UIImage]? = nil,
         urlStrings: [String]? = nil,
         initialIndex: Int = 0,
         onDismiss: @escaping () -> Void) {
        self.localImages = images
        self.remoteURLs = urlStrings
        self.startIndex = initialIndex
        self.currentPage = initialIndex
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Use adaptive background so photos don't float on white in light mode.
        view.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark ? .black : UIColor(white: 0.96, alpha: 1)
        }
        setupPagingScroll()
        buildPages()
        buildOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        pagingScroll.frame = view.bounds
        pagingScroll.contentSize = CGSize(width: CGFloat(count) * w, height: h)

        for (i, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            page.resetLayout()
        }

        // Restore correct horizontal offset after layout changes (e.g. rotation)
        let targetX = CGFloat(currentPage) * w
        if abs(pagingScroll.contentOffset.x - targetX) > 1 {
            pagingScroll.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)
        }

        if let p = pendingScrollIndex {
            pendingScrollIndex = nil
            syncToPageIndex(p, animated: false)
        }
    }

    /// Called from SwiftUI when `initialIndex` changes while the gallery is visible.
    func syncToPageIndex(_ index: Int, animated: Bool) {
        guard count > 0 else { return }
        let clamped = min(max(index, 0), count - 1)
        let w = pagingScroll.bounds.width
        if w <= 0 {
            pendingScrollIndex = clamped
            currentPage = clamped
            pageControl?.currentPage = clamped
            return
        }
        if clamped != currentPage, currentPage >= 0, currentPage < pages.count {
            pages[currentPage].resetZoom()
        }
        currentPage = clamped
        pageControl?.currentPage = clamped
        pagingScroll.setContentOffset(CGPoint(x: CGFloat(clamped) * w, y: 0), animated: animated)
    }

    // MARK: - Setup

    private func setupPagingScroll() {
        pagingScroll.isPagingEnabled = true
        pagingScroll.showsHorizontalScrollIndicator = false
        pagingScroll.showsVerticalScrollIndicator = false
        pagingScroll.backgroundColor = .clear
        pagingScroll.bounces = false
        pagingScroll.delegate = self
        view.addSubview(pagingScroll)
    }

    private func buildPages() {
        // Use screen dimensions as fallback if view hasn't been laid out yet
        let w = max(view.bounds.width, UIScreen.main.bounds.width)
        let h = max(view.bounds.height, UIScreen.main.bounds.height)

        for i in 0..<count {
            let page = ZoomPhotoPage(frame: CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h))

            page.onZoomChanged = { [weak self] isZoomed in
                // Disable outer paging while a page is zoomed so the inner pan
                // gesture can scroll the content without triggering page changes.
                self?.pagingScroll.isScrollEnabled = !isZoomed
            }
            page.onSwipeDownDismiss = { [weak self] in
                self?.onDismiss()
            }

            // The inner scroll's pan must yield to the outer paging pan.
            // require(toFail:) ensures the inner pan can only begin AFTER the outer
            // paging pan has failed (e.g. when zoomed and pagingScroll.isScrollEnabled=false).
            // When the outer paging pan succeeds (horizontal swipe), the inner pan
            // immediately fails — giving clean, unambiguous horizontal paging.
            page.panGestureRecognizer.require(toFail: pagingScroll.panGestureRecognizer)

            pagingScroll.addSubview(page)
            pages.append(page)

            if let imgs = localImages {
                page.setImage(imgs[i])
            } else if let urls = remoteURLs {
                page.setURL(urls[i])
            }
        }

        pagingScroll.contentSize = CGSize(width: CGFloat(count) * w, height: h)
        pagingScroll.setContentOffset(CGPoint(x: CGFloat(startIndex) * w, y: 0), animated: false)
    }

    private func buildOverlay() {
        // Close (×) button
        let btn = UIButton(type: .custom)
        let sym = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: sym), for: .normal)
        btn.tintColor = UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.9) : UIColor.black.withAlphaComponent(0.75) }
        btn.backgroundColor = UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.15) : UIColor.black.withAlphaComponent(0.08) }
        btn.layer.cornerRadius = 17
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            btn.widthAnchor.constraint(equalToConstant: 34),
            btn.heightAnchor.constraint(equalToConstant: 34)
        ])

        // Page dots (only shown when there are multiple photos)
        if count > 1 {
            let pc = UIPageControl()
            pc.numberOfPages = count
            pc.currentPage = startIndex
            pc.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pc)
            NSLayoutConstraint.activate([
                pc.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                pc.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
            ])
            pageControl = pc
        }
    }

    @objc private func closeTapped() { onDismiss() }
}

// MARK: - Paging UIScrollViewDelegate

extension NativeGalleryVC: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let w = scrollView.bounds.width
        guard w > 0 else { return }
        let newPage = Int((scrollView.contentOffset.x / w).rounded())
        guard newPage != currentPage, newPage >= 0, newPage < count else { return }
        // Reset zoom on the page the user is leaving
        pages[currentPage].resetZoom()
        currentPage = newPage
        pageControl?.currentPage = newPage
    }
}

// MARK: - ZoomPhotoPage
// One page of the gallery. Wraps a UIScrollView to get truly native pinch-to-zoom
// that always anchors to the pinch centre, identical to WorkTimeZoomableImageView.

final class ZoomPhotoPage: UIScrollView, UIScrollViewDelegate {

    private let imageView = UIImageView()
    private var spinner: UIActivityIndicatorView?
    private var fitZoomScale: CGFloat = 1.0

    /// Called with `true` when the zoom scale rises above 1, `false` when it returns to 1.
    var onZoomChanged: ((Bool) -> Void)?
    /// Called when the user swipes down while not zoomed.
    var onSwipeDownDismiss: (() -> Void)?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark ? .black : UIColor(white: 0.96, alpha: 1)
        }
        delegate = self
        minimumZoomScale = 1.0
        // Some uploads can contain large empty margins; allow deeper zoom so
        // users can still focus details without the "tiny image in canvas" feel.
        maximumZoomScale = 20.0
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        // Double-tap: zoom in to tapped point, or zoom out
        let doubleTap = UITapGestureRecognizer(target: self,
                                               action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // Swipe-down: dismiss when not zoomed
        let swipeDown = UISwipeGestureRecognizer(target: self,
                                                 action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        addGestureRecognizer(swipeDown)
    }

    // MARK: - Public

    func setImage(_ image: UIImage) {
        spinner?.stopAnimating()
        spinner?.removeFromSuperview()
        spinner = nil
        imageView.image = image
        resetZoom()
        resetLayout()
    }

    func setURL(_ urlString: String) {
        showSpinner()
        // StorageImageLoader handles both Firebase Storage paths and HTTPS URLs
        StorageImageLoader.shared.loadImage(from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                if let img = image {
                    self?.setImage(img)
                } else {
                    self?.showError()
                }
            }
        }
    }

    func resetLayout() {
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }
        let imageSize = imageView.image?.size ?? .zero
        if imageSize.width > 0, imageSize.height > 0 {
            let xScale = bounds.width / imageSize.width
            let yScale = bounds.height / imageSize.height
            fitZoomScale = min(xScale, yScale)
        } else {
            fitZoomScale = 1.0
        }
        minimumZoomScale = fitZoomScale
        if zoomScale < fitZoomScale || !zoomScale.isFinite {
            zoomScale = fitZoomScale
        }
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
        centerContent()
    }

    func resetZoom() {
        setZoomScale(fitZoomScale, animated: false)
        contentOffset = .zero
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if zoomScale < fitZoomScale {
            setZoomScale(fitZoomScale, animated: false)
        }
        centerContent()
        onZoomChanged?(zoomScale > fitZoomScale + 0.01)
    }

    // MARK: - Private helpers

    private func centerContent() {
        let offsetX = max((bounds.width  - imageView.frame.width)  / 2, 0)
        let offsetY = max((bounds.height - imageView.frame.height) / 2, 0)
        imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
    }

    private func showSpinner() {
        let sp = UIActivityIndicatorView(style: .large)
        sp.color = .white
        sp.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sp)
        NSLayoutConstraint.activate([
            sp.centerXAnchor.constraint(equalTo: centerXAnchor),
            sp.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        sp.startAnimating()
        spinner = sp
    }

    private func showError() {
        spinner?.stopAnimating()
        spinner?.removeFromSuperview()
        let iv = UIImageView(image: UIImage(systemName: "photo"))
        iv.tintColor = UIColor.white.withAlphaComponent(0.5)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 60),
            iv.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        if zoomScale > fitZoomScale {
            setZoomScale(fitZoomScale, animated: true)
        } else {
            let loc = gr.location(in: imageView)
            let zoomRectSize = min(bounds.width, bounds.height) / 3.2
            let rect = CGRect(
                x: loc.x - zoomRectSize / 2,
                y: loc.y - zoomRectSize / 2,
                width: zoomRectSize,
                height: zoomRectSize
            )
            zoom(to: rect, animated: true)
        }
    }

    @objc private func handleSwipeDown() {
        guard zoomScale <= fitZoomScale + 0.01 else { return }
        onSwipeDownDismiss?()
    }
}
