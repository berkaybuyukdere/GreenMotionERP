import SwiftUI
import UIKit
import Kingfisher

struct PhotoGalleryView: View {
    let photoURLs: [String]
    let initialIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    @State private var images: [Int: UIImage] = [:]
    @State private var isLoading: [Int: Bool] = [:]
    
    private var clampedInitialIndex: Int {
        guard !photoURLs.isEmpty else { return 0 }
        return min(max(initialIndex, 0), photoURLs.count - 1)
    }
    
    init(photoURLs: [String], initialIndex: Int = 0) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !photoURLs.isEmpty {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(0..<photoURLs.count, id: \.self) { index in
                            ZoomableImageView(
                                image: images[index],
                                isLoading: isLoading[index] ?? true,
                                isActive: index == currentIndex,
                                onLoad: { image in
                                    images[index] = image
                                    isLoading[index] = false
                                },
                                onLoadStart: {
                                    isLoading[index] = true
                                },
                                onSwipeLeft: {
                                                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        if currentIndex < photoURLs.count - 1 {
                                            currentIndex += 1
                                        } else {
                                            currentIndex = 0
                                        }
                                    }
                                },
                                onSwipeRight: {
                                                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        if currentIndex > 0 {
                                            currentIndex -= 1
                                        } else {
                                            currentIndex = photoURLs.count - 1
                                        }
                                    }
                                },
                                onSwipeDown: {
                                    dismiss()
                                }
                            )
                            .frame(width: geometry.size.width)
                        }
                    }
                    .offset(x: -CGFloat(currentIndex) * geometry.size.width)
                }
                .onAppear {
                    currentIndex = clampedInitialIndex
                    loadImage(at: currentIndex)
                }
                .onChange(of: initialIndex) { _, _ in
                    currentIndex = clampedInitialIndex
                    loadImage(at: currentIndex)
                }
                .onChange(of: photoURLs.count) { _, _ in
                    currentIndex = min(currentIndex, max(photoURLs.count - 1, 0))
                }
                .onChange(of: currentIndex) { oldIndex, newIndex in
                                        loadImage(at: newIndex)
                    if newIndex > 0 {
                        loadImage(at: newIndex - 1)
                    }
                    if newIndex < photoURLs.count - 1 {
                        loadImage(at: newIndex + 1)
                    }
                }
                
                // Page indicator
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<photoURLs.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 30)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No photos available".localized)
                        .foregroundColor(.white)
                }
            }
            
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
            }
            .background(Color.clear)
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        }
    
    private func loadImage(at index: Int) {
        guard index >= 0 && index < photoURLs.count else { return }
        guard images[index] == nil && (isLoading[index] == nil || isLoading[index] == false) else { return }
        
        isLoading[index] = true
        let urlString = photoURLs[index]
        
        guard let url = URL(string: urlString) else {
            isLoading[index] = false
            return
        }
        
        // Use Kingfisher for image loading with automatic caching
        KingfisherManager.shared.retrieveImage(with: url) { result in
            DispatchQueue.main.async {
                self.isLoading[index] = false
                switch result {
                case .success(let value):
                    self.images[index] = value.image
                case .failure(let error):
                    print("❌ Failed to load image at index \(index): \(error.localizedDescription)")
                    self.images[index] = nil
                }
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage?
    let isLoading: Bool
    let isActive: Bool
    let onLoad: (UIImage) -> Void
    let onLoadStart: () -> Void
    let onSwipeLeft: (() -> Void)?
    let onSwipeRight: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(image: UIImage?, isLoading: Bool, isActive: Bool, onLoad: @escaping (UIImage) -> Void, onLoadStart: @escaping () -> Void, onSwipeLeft: (() -> Void)? = nil, onSwipeRight: (() -> Void)? = nil, onSwipeDown: (() -> Void)? = nil) {
        self.image = image
        self.isLoading = isLoading
        self.isActive = isActive
        self.onLoad = onLoad
        self.onLoadStart = onLoadStart
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.onSwipeDown = onSwipeDown
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(x: offset.width, y: offset.height)
                        
                        // UIKit gesture handler for all interactions
                        PhotoGestureHandler(
                            scale: $scale,
                            offset: $offset,
                            lastOffset: $lastOffset,
                            geometry: geometry.size,
                            imageSize: image.size,
                            onSwipeLeft: onSwipeLeft,
                            onSwipeRight: onSwipeRight,
                            onSwipeDown: onSwipeDown,
                            onDoubleTap: { location in
                                handleDoubleTap(at: location, in: geometry.size, imageSize: image.size)
                            }
                        )
                        .allowsHitTesting(true)
                        .contentShape(Rectangle())
                    }
                    .onChange(of: isActive) { active in
                        if !active {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
                } else if isLoading && isActive {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading photo...".localized)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                } else if !isLoading && image == nil && isActive {
                    VStack(spacing: 20) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Failed to load photo".localized)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .onAppear {
            if let image = image {
                onLoad(image)
            } else if isActive {
                onLoadStart()
            }
        }
        .onChange(of: image) { newImage in
            if let image = newImage {
                onLoad(image)
            }
        }
    }
    
    private func handleDoubleTap(at location: CGPoint, in viewSize: CGSize, imageSize: CGSize) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            if scale > 1.0 {
                // Zoom out
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                // Zoom in to tapped point
                let targetScale: CGFloat = 2.5
                
                // Calculate tap position relative to center
                let tapX = location.x - viewSize.width / 2
                let tapY = location.y - viewSize.height / 2
                
                // Calculate image dimensions when fitted to view
                let imageAspectRatio = imageSize.width / imageSize.height
                let viewAspectRatio = viewSize.width / viewSize.height
                
                var fittedWidth: CGFloat
                var fittedHeight: CGFloat
                
                if imageAspectRatio > viewAspectRatio {
                    fittedWidth = viewSize.width
                    fittedHeight = viewSize.width / imageAspectRatio
                } else {
                    fittedHeight = viewSize.height
                    fittedWidth = viewSize.height * imageAspectRatio
                }
                
                // Calculate offset to center the tap point
                let newOffset = CGSize(
                    width: -tapX * (targetScale - 1.0),
                    height: -tapY * (targetScale - 1.0)
                )
                
                // Constrain to bounds
                let scaledWidth = fittedWidth * targetScale
                let scaledHeight = fittedHeight * targetScale
                
                let maxOffsetX = max(0, (scaledWidth - viewSize.width) / 2)
                let maxOffsetY = max(0, (scaledHeight - viewSize.height) / 2)
                
                scale = targetScale
                offset = CGSize(
                    width: max(-maxOffsetX, min(maxOffsetX, newOffset.width)),
                    height: max(-maxOffsetY, min(maxOffsetY, newOffset.height))
                )
                lastOffset = offset
            }
        }
    }
}

// Professional UIKit gesture handler
struct PhotoGestureHandler: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    let geometry: CGSize
    let imageSize: CGSize
    let onSwipeLeft: (() -> Void)?
    let onSwipeRight: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    let onDoubleTap: (CGPoint) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // Pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.delegate = context.coordinator
        view.addGestureRecognizer(pinchGesture)
        
        // Pan gesture for dragging and swiping
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGesture)
        
        // Double tap gesture
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = context.coordinator
        view.addGestureRecognizer(doubleTapGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateParent(self)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PhotoGestureHandler
        var initialScale: CGFloat = 1.0
        var initialOffset: CGSize = .zero
        var initialPinchCenter: CGPoint = .zero
        var panStartOffset: CGSize = .zero
        var isPinching = false
        
        init(_ parent: PhotoGestureHandler) {
            self.parent = parent
        }
        
        func updateParent(_ parent: PhotoGestureHandler) {
            self.parent = parent
        }
        
        // MARK: - Double Tap
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.onDoubleTap(location)
        }
        
        // MARK: - Pinch Gesture (Zoom)
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                isPinching = true
                initialScale = parent.scale
                initialOffset = parent.offset
                initialPinchCenter = gesture.location(in: gesture.view)
                
            case .changed:
                let newScale = initialScale * gesture.scale
                let clampedScale = max(1.0, min(10.0, newScale))
                
                // Calculate the pinch center point relative to view center
                let viewCenterX = parent.geometry.width / 2
                let viewCenterY = parent.geometry.height / 2
                let pinchCenterX = initialPinchCenter.x - viewCenterX
                let pinchCenterY = initialPinchCenter.y - viewCenterY
                
                // Scale factor change
                let scaleRatio = clampedScale / initialScale
                
                // Calculate new offset to keep pinch center fixed
                let newOffsetX = initialOffset.width + pinchCenterX * (1 - scaleRatio)
                let newOffsetY = initialOffset.height + pinchCenterY * (1 - scaleRatio)
                
                // Update without animation for smooth real-time feedback
                parent.scale = clampedScale
                parent.offset = CGSize(width: newOffsetX, height: newOffsetY)
                
            case .ended, .cancelled:
                isPinching = false
                let constrained = constrainOffset(parent.offset, scale: parent.scale)
                
                DispatchQueue.main.async {
                    if self.parent.scale < 1.0 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            self.parent.scale = 1.0
                            self.parent.offset = .zero
                            self.parent.lastOffset = .zero
                        }
                    } else {
                        let needsCorrection = abs(constrained.width - self.parent.offset.width) > 0.5 ||
                                            abs(constrained.height - self.parent.offset.height) > 0.5
                        
                        if needsCorrection {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                self.parent.offset = constrained
                            }
                        } else {
                            self.parent.offset = constrained
                        }
                        self.parent.lastOffset = constrained
                    }
                }
                
            default:
                break
            }
        }
        
        // MARK: - Pan Gesture
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            
            // Don't interfere with pinch
            if isPinching || gesture.numberOfTouches >= 2 {
                return
            }
            
            switch gesture.state {
            case .began:
                panStartOffset = parent.lastOffset
                
            case .changed:
                if parent.scale > 1.0 {
                    // Panning while zoomed
                    let newOffset = CGSize(
                        width: panStartOffset.width + translation.x,
                        height: panStartOffset.height + translation.y
                    )
                    
                    // Add rubber banding effect at edges
                    let constrained = constrainOffsetWithRubberBand(newOffset, scale: parent.scale)
                    parent.offset = constrained
                }
                // Don't show visual feedback during swipe
                
            case .ended:
                if parent.scale > 1.0 {
                    // Snap back to bounds
                    let constrained = constrainOffset(parent.offset, scale: parent.scale)
                    
                    DispatchQueue.main.async {
                        let needsCorrection = abs(constrained.width - self.parent.offset.width) > 0.5 ||
                                            abs(constrained.height - self.parent.offset.height) > 0.5
                        
                        if needsCorrection {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                self.parent.offset = constrained
                            }
                        } else {
                            self.parent.offset = constrained
                        }
                        self.parent.lastOffset = constrained
                    }
                } else {
                    // Handle swipe between photos
                    let velocity = gesture.velocity(in: gesture.view)
                    let swipeThreshold: CGFloat = 60
                    let velocityThreshold: CGFloat = 600
                    
                    let isHorizontalSwipe = abs(translation.x) > abs(translation.y)
                    
                    if isHorizontalSwipe {
                        if abs(translation.x) > swipeThreshold || abs(velocity.x) > velocityThreshold {
                            DispatchQueue.main.async {
                                if translation.x > 0 || velocity.x > velocityThreshold {
                                    self.parent.onSwipeRight?()
                                } else if translation.x < 0 || velocity.x < -velocityThreshold {
                                    self.parent.onSwipeLeft?()
                                }
                            }
                        }
                    } else {
                        let verticalDismissThreshold: CGFloat = 120
                        let verticalVelocityThreshold: CGFloat = 950
                        let isSwipeDown = translation.y > verticalDismissThreshold || velocity.y > verticalVelocityThreshold
                        if isSwipeDown {
                            DispatchQueue.main.async {
                                self.parent.onSwipeDown?()
                            }
                        }
                    }
                }
                
            case .cancelled, .failed:
                if parent.scale > 1.0 {
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            self.parent.offset = self.panStartOffset
                        }
                        self.parent.lastOffset = self.panStartOffset
                    }
                }
                
            default:
                break
            }
        }
        
        // MARK: - Gesture Delegate
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, 
                              shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pinch and pan to work together when zoomed
            let isPinchAndPan = (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer) ||
                               (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
            
            return isPinchAndPan && parent.scale > 1.0
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                              shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Pan should wait for double tap
            if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer {
                return true
            }
            return false
        }
        
        // MARK: - Helper Functions
        private func constrainOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
            let imageAspectRatio = parent.imageSize.width / parent.imageSize.height
            let viewAspectRatio = parent.geometry.width / parent.geometry.height
            
            var fittedWidth: CGFloat
            var fittedHeight: CGFloat
            
            if imageAspectRatio > viewAspectRatio {
                fittedWidth = parent.geometry.width
                fittedHeight = parent.geometry.width / imageAspectRatio
            } else {
                fittedHeight = parent.geometry.height
                fittedWidth = parent.geometry.height * imageAspectRatio
            }
            
            let scaledWidth = fittedWidth * scale
            let scaledHeight = fittedHeight * scale
            
            let maxOffsetX = max(0, (scaledWidth - parent.geometry.width) / 2)
            let maxOffsetY = max(0, (scaledHeight - parent.geometry.height) / 2)
            
            return CGSize(
                width: max(-maxOffsetX, min(maxOffsetX, offset.width)),
                height: max(-maxOffsetY, min(maxOffsetY, offset.height))
            )
        }
        
        private func constrainOffsetWithRubberBand(_ offset: CGSize, scale: CGFloat) -> CGSize {
            let constrained = constrainOffset(offset, scale: scale)
            
            // If already within bounds, return as is
            if abs(offset.width - constrained.width) < 0.1 && 
               abs(offset.height - constrained.height) < 0.1 {
                return offset
            }
            
            // Apply rubber band effect for over-panning
            let rubberBandFactor: CGFloat = 0.3
            
            let newWidth: CGFloat
            if offset.width > constrained.width {
                let excess = offset.width - constrained.width
                newWidth = constrained.width + excess * rubberBandFactor
            } else if offset.width < constrained.width {
                let excess = constrained.width - offset.width
                newWidth = constrained.width - excess * rubberBandFactor
            } else {
                newWidth = offset.width
            }
            
            let newHeight: CGFloat
            if offset.height > constrained.height {
                let excess = offset.height - constrained.height
                newHeight = constrained.height + excess * rubberBandFactor
            } else if offset.height < constrained.height {
                let excess = constrained.height - offset.height
                newHeight = constrained.height - excess * rubberBandFactor
            } else {
                newHeight = offset.height
            }
            
            return CGSize(width: newWidth, height: newHeight)
        }
    }
}