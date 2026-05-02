import SwiftUI
import UIKit

/// Use with `fullScreenCover(item:)` so each open carries the tapped photo index reliably.
struct PhotoGallerySheetItem: Identifiable {
    let id = UUID()
    let startIndex: Int
}

/// Single `fullScreenCover(item:)` payload for `NativePhotoGalleryView` (stacking two URL vs image covers can yield a blank screen).
struct PhotoGalleryFullScreenSession: Identifiable {
    let id = UUID()
    let urlStrings: [String]?
    let images: [UIImage]?
    let startIndex: Int

    init(urlStrings: [String], startIndex: Int) {
        self.urlStrings = urlStrings
        self.images = nil
        self.startIndex = startIndex
    }

    init(images: [UIImage], startIndex: Int) {
        self.urlStrings = nil
        self.images = images
        self.startIndex = startIndex
    }
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

    final class Coordinator {
        var lastSyncedIndex: Int
        init(initialIndex: Int) { self.lastSyncedIndex = initialIndex }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(initialIndex: initialIndex)
    }

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
        guard context.coordinator.lastSyncedIndex != initialIndex else { return }
        context.coordinator.lastSyncedIndex = initialIndex
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
    private weak var closeButton: UIButton?
    /// When layout width was 0, apply scroll after first layout.
    private var pendingScrollIndex: Int?
    /// Avoid resetting every ZoomPhotoPage on minor layout passes (was breaking fit zoom / centering).
    private var lastGalleryPageLayoutSize: CGSize = .zero

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
        setupPagingScroll()
        buildPages()
        buildOverlay()
        applyPreviewChrome()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            applyPreviewChrome()
        }
    }

    /// Photo canvas + controls: dark = black canvas, white × and dots; light = white canvas, black × and dots.
    private func applyPreviewChrome() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let canvas: UIColor = dark ? .black : .white
        view.backgroundColor = canvas
        pagingScroll.backgroundColor = canvas
        for p in pages { p.applyPreviewCanvas(dark: dark) }

        if let btn = closeButton {
            btn.tintColor = dark ? .white : .black
            btn.backgroundColor = dark
                ? UIColor.white.withAlphaComponent(0.22)
                : UIColor.black.withAlphaComponent(0.12)
            btn.layer.shadowColor = (dark ? UIColor.black : UIColor.black).cgColor
            btn.layer.shadowOffset = CGSize(width: 0, height: 1)
            btn.layer.shadowRadius = dark ? 5 : 3
            btn.layer.shadowOpacity = dark ? 0.55 : 0.25
        }

        if let pc = pageControl {
            pc.currentPageIndicatorTintColor = dark ? .white : .black
            pc.pageIndicatorTintColor = dark
                ? UIColor.white.withAlphaComponent(0.35)
                : UIColor.black.withAlphaComponent(0.28)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        pagingScroll.frame = view.bounds
        pagingScroll.contentSize = CGSize(width: CGFloat(count) * w, height: h)

        let pageSize = CGSize(width: w, height: h)
        let sizeChanged =
            lastGalleryPageLayoutSize.width < 1
            || lastGalleryPageLayoutSize.height < 1
            || abs(pageSize.width - lastGalleryPageLayoutSize.width) > 0.5
            || abs(pageSize.height - lastGalleryPageLayoutSize.height) > 0.5
        lastGalleryPageLayoutSize = pageSize

        for (i, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            if sizeChanged {
                page.resetLayout()
            } else {
                page.recenterZoomOutLayout()
            }
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

        if let btn = closeButton { view.bringSubviewToFront(btn) }
        if let pc = pageControl { view.bringSubviewToFront(pc) }
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
        pagingScroll.backgroundColor = view.backgroundColor ?? .black
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
        // Close (×) — always on top of photos; colors from `applyPreviewChrome()`.
        let btn = UIButton(type: .custom)
        let sym = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: sym), for: .normal)
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityLabel = "Close"
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        btn.layer.zPosition = 10_000
        view.addSubview(btn)
        closeButton = btn
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            btn.widthAnchor.constraint(equalToConstant: 40),
            btn.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Page dots (only shown when there are multiple photos)
        if count > 1 {
            let pc = UIPageControl()
            pc.numberOfPages = count
            pc.currentPage = startIndex
            pc.translatesAutoresizingMaskIntoConstraints = false
            pc.layer.zPosition = 9_999
            view.addSubview(pc)
            NSLayoutConstraint.activate([
                pc.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                pc.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
            ])
            pageControl = pc
        }

        view.bringSubviewToFront(btn)
        if let pc = pageControl { view.bringSubviewToFront(pc) }
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
// Zooms a tight `zoomingContainer` sized to the aspect-fit image box. Minimum zoom is **horizontal floor**
// (`max(1, bounds.width / fittedWidth)`) so the user cannot zoom out into side letterboxing; panning is clamped
// so content never sits outside the photo + insets.

final class ZoomPhotoPage: UIScrollView, UIScrollViewDelegate {

    private let zoomingContainer = UIView()
    private let imageView = UIImageView()
    private var spinner: UIActivityIndicatorView?
    private var lastLaidBoundsSize: CGSize = .zero

    var onZoomChanged: ((Bool) -> Void)?
    var onSwipeDownDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyPreviewCanvas(dark: Bool) {
        backgroundColor = dark ? .black : .white
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            applyPreviewCanvas(dark: traitCollection.userInterfaceStyle == .dark)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        let bw = bounds.size
        let first = lastLaidBoundsSize.width < 1 || lastLaidBoundsSize.height < 1
        let sizeChanged = abs(bw.width - lastLaidBoundsSize.width) > 0.5 || abs(bw.height - lastLaidBoundsSize.height) > 0.5
        if first || sizeChanged {
            lastLaidBoundsSize = bw
            resetLayout()
        } else {
            recenterZoomOutLayout()
        }
    }

    private func setup() {
        applyPreviewCanvas(dark: traitCollection.userInterfaceStyle == .dark)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        bouncesZoom = true
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 1
        maximumZoomScale = 6

        zoomingContainer.backgroundColor = .clear
        zoomingContainer.clipsToBounds = false
        addSubview(zoomingContainer)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        zoomingContainer.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        addGestureRecognizer(swipeDown)
    }

    func setImage(_ image: UIImage) {
        lastLaidBoundsSize = .zero
        spinner?.stopAnimating()
        spinner?.removeFromSuperview()
        spinner = nil
        imageView.image = image.normalizedImageOrientationForViewer()
        setNeedsLayout()
        layoutIfNeeded()
        resetLayout()
        resetZoom()
    }

    func setURL(_ urlString: String) {
        lastLaidBoundsSize = .zero
        imageView.image = nil
        setNeedsLayout()
        layoutIfNeeded()
        resetLayout()
        StorageImageLoader.shared.loadImage(from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                if let img = image {
                    self.setImage(img)
                } else {
                    self.showError()
                }
            }
        }
    }

    func resetLayout() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let img = imageView.image else {
            zoomingContainer.isHidden = true
            minimumZoomScale = 1
            maximumZoomScale = 6
            setZoomScale(1, animated: false)
            contentInset = .zero
            contentSize = .zero
            return
        }
        zoomingContainer.isHidden = false

        let bw = bounds.width
        let bh = bounds.height
        let iw = max(img.size.width, 1)
        let ih = max(img.size.height, 1)

        let scaleToFit = min(bw / iw, bh / ih)
        let fw = iw * scaleToFit
        let fh = ih * scaleToFit

        let horizontalFloor = fw > 0 ? bw / fw : 1
        let minZ = max(1 as CGFloat, horizontalFloor)
        let maxZ = max(6 as CGFloat, minZ * 1.05)

        minimumZoomScale = minZ
        maximumZoomScale = maxZ

        zoomingContainer.frame = CGRect(x: 0, y: 0, width: fw, height: fh)
        imageView.frame = zoomingContainer.bounds

        layoutIfNeeded()
        setZoomScale(minZ, animated: false)
        layoutIfNeeded()
        updateZoomInsetsAndOffset()
        clampContentOffset()
    }

    func recenterZoomOutLayout() {
        guard imageView.image != nil, bounds.width > 1, bounds.height > 1 else { return }
        updateZoomInsetsAndOffset()
        if zoomScale <= minimumZoomScale + 0.02 {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            clampContentOffset()
        }
    }

    func resetZoom() {
        setZoomScale(minimumZoomScale, animated: false)
        layoutIfNeeded()
        updateZoomInsetsAndOffset()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        clampContentOffset()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomingContainer }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if zoomScale < minimumZoomScale - 0.0001 {
            setZoomScale(minimumZoomScale, animated: false)
        }
        if zoomScale > maximumZoomScale + 0.0001 {
            setZoomScale(maximumZoomScale, animated: false)
        }
        updateZoomInsetsAndOffset()
        clampContentOffset()
        onZoomChanged?(zoomScale > minimumZoomScale + 0.02)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        clampContentOffset()
    }

    private func updateZoomInsetsAndOffset() {
        guard imageView.image != nil, bounds.width > 1, bounds.height > 1 else {
            contentInset = .zero
            return
        }
        let W = zoomingContainer.frame.width
        let H = zoomingContainer.frame.height
        let bw = bounds.width
        let bh = bounds.height
        contentSize = CGSize(width: max(W, 0.5), height: max(H, 0.5))

        let insetX = max(0, (bw - W) * 0.5)
        let insetY = max(0, (bh - H) * 0.5)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func clampContentOffset() {
        guard bounds.width > 0.5, bounds.height > 0.5 else { return }
        let minX = -contentInset.left
        let maxX = max(minX, contentSize.width - bounds.width + contentInset.right)
        let minY = -contentInset.top
        let maxY = max(minY, contentSize.height - bounds.height + contentInset.bottom)
        var o = contentOffset
        o.x = min(max(o.x, minX), maxX)
        o.y = min(max(o.y, minY), maxY)
        if abs(o.x - contentOffset.x) > 0.25 || abs(o.y - contentOffset.y) > 0.25 {
            contentOffset = o
        }
    }

    private func showSpinner() {
        let sp = UIActivityIndicatorView(style: .large)
        sp.color = UIColor { tc in tc.userInterfaceStyle == .dark ? .white : .gray }
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
        iv.tintColor = UIColor.label.withAlphaComponent(0.45)
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
        if zoomScale > minimumZoomScale + 0.02 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let loc = gr.location(in: zoomingContainer)
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
        guard zoomScale <= minimumZoomScale + 0.02 else { return }
        onSwipeDownDismiss?()
    }
}
