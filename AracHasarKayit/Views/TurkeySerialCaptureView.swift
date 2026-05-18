import SwiftUI
import AVFoundation
import CoreMotion
import UIKit

// MARK: - Design tokens

private enum SC {
    static let yellow    = Color(red: 1.0, green: 0.84, blue: 0.04)
    static let gridC     = Color.white.opacity(0.22)
    static let dimWhite  = Color.white.opacity(0.55)
    static let pillBG    = Color.black.opacity(0.52)
    static let vfAspect: CGFloat = 3.0 / 4.0     // portrait 3:4 (iPhone Photo mode)
}

// MARK: - Zoom level definitions

private struct ZoomDef: Identifiable {
    let value: CGFloat          // factor: 0.5 / 1 / 2 / 4 / 8
    var id: CGFloat { value }
    var label: String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private let kAllZooms: [ZoomDef] = [
    .init(value: 0.5), .init(value: 1), .init(value: 2),
    .init(value: 4),   .init(value: 8),
]

// MARK: - Main view ───────────────────────────────────────────────────────

struct TurkeySerialCaptureView: View {

    let onPhotoCaptured: (UIImage) -> Void
    let onDone:          () -> Void
    let onCancel:        () -> Void

    @StateObject private var cam = TurkeySerialCameraSession()

    @State private var thumbs:        [UIImage] = []
    @State private var showGallery    = false
    @State private var galleryStart   = 0
    @State private var showGrid       = true
    @State private var showExitAlert  = false

    // zoom slider state
    @State private var sliderDragX:   CGFloat = 0
    @State private var sliderBaseX:   CGFloat = 0
    @State private var isDraggingSlider = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                cameraStack(geo: geo)
                if cam.permissionDenied { permissionOverlay }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            cam.onPhotoCaptured = { img, orientation in
                let n = TurkeyCaptureImageOrientation.preparedForStorage(
                    deviceOrientation: orientation,
                    image: img
                )
                thumbs.append(n)
                galleryStart = thumbs.count - 1
                onPhotoCaptured(n)
                HapticManager.shared.light()
            }
        }
        .alert("tr_serial.discard_title".localized, isPresented: $showExitAlert) {
            Button("Discard".localized, role: .destructive) { onCancel() }
            Button("Keep shooting".localized, role: .cancel) { }
        } message: {
            Text("tr_serial.exit_warning".localized)
        }
        .fullScreenCover(isPresented: $showGallery) {
            TurkeySerialFilmstripView(images: thumbs, initialIndex: galleryStart) {
                showGallery = false
            }
        }
    }

    // MARK: - Main stack

    @ViewBuilder
    private func cameraStack(geo: GeometryProxy) -> some View {
        let vfW  = geo.size.width
        let vfH  = vfW / SC.vfAspect
        let topH = max(geo.safeAreaInsets.top + 8, (geo.size.height - vfH) / 2)
        let botH = max(geo.size.height - topH - vfH, 150)

        VStack(spacing: 0) {
            topBar(safeTop: geo.safeAreaInsets.top).frame(height: topH)

            // viewfinder
            ZStack {
                TurkeySerialCameraRepresentable(session: cam)
                if showGrid { gridOverlay }
                focusReticle
                // floating zoom slider at bottom of viewfinder
                VStack { Spacer(); zoomSlider.padding(.bottom, 12) }
            }
            .frame(width: vfW, height: vfH)
            .clipped()
            .contentShape(Rectangle())
            .gesture(pinchGesture)

            bottomBar(botH: botH)
        }
    }

    // MARK: - Top bar

    private func topBar(safeTop: CGFloat) -> some View {
        ZStack {
            Color.black
            HStack {
                // JPEG 24 badge
                HStack(spacing: 3) {
                    Text("JPEG").font(.system(size: 16, weight: .semibold))
                    Text("24").font(.system(size: 11, weight: .regular)).baselineOffset(-3)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(SC.pillBG))

                Spacer()

                // Flash
                topIconButton(
                    sf: cam.flashOn ? "bolt.fill" : "bolt.slash.fill",
                    tint: cam.flashOn ? SC.yellow : .white
                ) { cam.toggleFlash() }

                // Done ✓
                topIconButton(sf: "checkmark", tint: SC.yellow) { onDone() }
            }
            .padding(.horizontal, 16)
            .padding(.top, max(safeTop, 8))
        }
    }

    private func topIconButton(sf: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(SC.pillBG).frame(width: 44, height: 44)
                Image(systemName: sf).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var gridOverlay: some View {
        GeometryReader { g in
            Path { p in
                let w = g.size.width, h = g.size.height
                p.move(to: .init(x: w/3, y: 0));   p.addLine(to: .init(x: w/3,   y: h))
                p.move(to: .init(x: 2*w/3, y: 0)); p.addLine(to: .init(x: 2*w/3, y: h))
                p.move(to: .init(x: 0, y: h/3));   p.addLine(to: .init(x: w,     y: h/3))
                p.move(to: .init(x: 0, y: 2*h/3)); p.addLine(to: .init(x: w,     y: 2*h/3))
            }
            .stroke(SC.gridC, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Focus reticle

    private var focusReticle: some View {
        let s: CGFloat = 88, gap: CGFloat = 22
        return ZStack {
            Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                .frame(width: s, height: s * 0.68)
            GeometryReader { g in
                let cx = g.size.width/2, cy = g.size.height/2
                Path { p in
                    p.move(to: .init(x: cx-s/2-gap, y: cy)); p.addLine(to: .init(x: cx-gap, y: cy))
                    p.move(to: .init(x: cx+gap, y: cy));     p.addLine(to: .init(x: cx+s/2+gap, y: cy))
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 1.3)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Zoom slider (native iOS style) ─────────────────────────────

    /// Displays the available presets as a draggable horizontal slider.
    /// • Active level shown in yellow filled pill with "x" suffix.
    /// • Dragging left/right transitions between levels with haptic snap.
    /// • Tap on any level jumps directly.
    private var zoomSlider: some View {
        let presets = cam.availableZoomPresets.sorted()
        return ZStack {
            // track background
            Capsule().fill(Color.black.opacity(0.48))

            HStack(spacing: 0) {
                ForEach(presets, id: \.self) { v in
                    zoomSliderItem(v, allPresets: presets)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .gesture(zoomSliderDrag(presets: presets))
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: cam.activeZoomPreset)
    }

    @ViewBuilder
    private func zoomSliderItem(_ v: CGFloat, allPresets: [CGFloat]) -> some View {
        let active = abs(cam.activeZoomPreset - v) < 0.12
        let lbl: String = {
            let base = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
            return active ? "\(base)x" : base
        }()

        Button {
            HapticManager.shared.light()
            cam.selectZoomPreset(v)
        } label: {
            Text(lbl)
                .font(.system(size: active ? 16 : 14,
                              weight: active ? .bold : .semibold,
                              design: .rounded))
                .foregroundStyle(active ? Color.black : SC.dimWhite)
                .frame(minWidth: active ? 52 : 40, minHeight: 36)
                .padding(.horizontal, active ? 2 : 0)
                .background(active ? Capsule().fill(SC.yellow) : nil)
        }
        .buttonStyle(.plain)
    }

    private func zoomSliderDrag(presets: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { val in
                if !isDraggingSlider {
                    isDraggingSlider = true
                    sliderBaseX = 0
                }
                let dx = val.translation.width
                let stepW: CGFloat = 56          // px per preset step
                let rawIdx = -(dx / stepW)
                let curIdx = presets.firstIndex(where: { abs($0 - cam.activeZoomPreset) < 0.12 }) ?? 0
                let newIdx = (curIdx + Int(rawIdx.rounded())).clamped(to: 0..<presets.count)
                let newPreset = presets[newIdx]
                if abs(newPreset - cam.activeZoomPreset) > 0.05 {
                    HapticManager.shared.light()
                    cam.selectZoomPreset(newPreset)
                }
            }
            .onEnded { _ in isDraggingSlider = false }
    }

    // MARK: - Pinch to zoom

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { s in cam.applyPinchScale(s) }
            .onEnded   { s in cam.applyPinchScale(s, commit: true) }
    }

    // MARK: - Bottom bar

    private func bottomBar(botH: CGFloat) -> some View {
        ZStack {
            Color.black
            HStack(alignment: .center) {
                thumbnailView.padding(.leading, 24)
                Spacer()
                VStack(spacing: 10) {
                    modeCapsule
                    shutterButton
                }
                Spacer()
                iconCircleButton(sf: "arrow.triangle.2.circlepath.camera", size: 22) {
                    cam.flipCamera()
                }
                .padding(.trailing, 24)
            }
        }
        .frame(height: botH)
    }

    private var modeCapsule: some View {
        HStack(spacing: 0) {
            Text("VIDEO")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SC.dimWhite)
                .padding(.horizontal, 14).padding(.vertical, 8)
            Text("PHOTO")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(SC.yellow))
        }
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }

    private var shutterButton: some View {
        Button {
            guard cam.isReady else { return }
            HapticManager.shared.medium()
            cam.capturePhoto()
        } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(0.38), lineWidth: 3).frame(width: 82, height: 82)
                Circle().fill(Color.white).frame(width: 70, height: 70)
            }
        }
        .buttonStyle(SC_ShutterStyle())
        .disabled(!cam.isReady)
        .opacity(cam.isReady ? 1 : 0.4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let last = thumbs.last {
            Button {
                galleryStart = thumbs.count - 1
                showGallery = true
            } label: {
                Image(uiImage: last)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "photo").font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private func iconCircleButton(sf: String, size: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.14)).frame(width: 52, height: 52)
                Image(systemName: sf).font(.system(size: size, weight: .medium)).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission overlay

    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text("Camera access is required to take photos.".localized)
                .multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal, 32)
            Button("Cancel".localized) { onCancel() }.foregroundStyle(SC.yellow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.94))
    }

    // MARK: - Close

    private func handleClose() {
        thumbs.isEmpty ? onCancel() : (showExitAlert = true)
    }
}

// MARK: - Shutter press style

private struct SC_ShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Int clamped helper

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}

// MARK: - Filmstrip (with pinch-to-zoom per photo) ───────────────────────

private struct TurkeySerialFilmstripView: View {
    let images: [UIImage]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss

    init(images: [UIImage], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.images = images
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _selection = State(initialValue: min(max(0, initialIndex), max(0, images.count - 1)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { i in
                    SCZoomableImageView(image: images[i])
                        .tag(i)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))

            HStack {
                Button {
                    dismiss(); onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                Spacer()
                Text("\(selection + 1) / \(images.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
        }
    }
}

// MARK: - Pinch-to-zoom image viewer

// SCZoomableImageView wraps a custom UIView that owns its own UIScrollView so
// layout always happens in layoutSubviews – guaranteeing correct bounds even
// on the first pass, and properly handling landscape photos in portrait screen.
private struct SCZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> SCZoomContainer {
        let v = SCZoomContainer()
        v.setImage(image)
        return v
    }

    func updateUIView(_ v: SCZoomContainer, context: Context) {
        v.setImage(image)
    }
}

final class SCZoomContainer: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let iv     = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        scroll.backgroundColor = .black
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 6.0
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator   = false
        scroll.delegate = self
        addSubview(scroll)
        iv.contentMode  = .scaleAspectFit
        iv.backgroundColor = .black
        scroll.addSubview(iv)

        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ img: UIImage) {
        iv.image = img
        // reset zoom whenever image changes
        scroll.setZoomScale(1, animated: false)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let imgSize = iv.image?.size ?? CGSize(width: 1, height: 1)
        let aspect  = imgSize.width / max(imgSize.height, 1)

        // Fit the image inside the view (letterboxed) — works for both landscape & portrait photos
        let fitW: CGFloat
        let fitH: CGFloat
        if aspect > bounds.width / bounds.height {
            // image is wider than the container → fit by width
            fitW = bounds.width
            fitH = fitW / aspect
        } else {
            // image is taller (or equal) → fit by height
            fitH = bounds.height
            fitW = fitH * aspect
        }

        iv.frame = CGRect(x: (bounds.width  - fitW) / 2,
                          y: (bounds.height - fitH) / 2,
                          width: fitW, height: fitH)
        scroll.contentSize = iv.frame.size
    }

    // MARK: UIScrollViewDelegate
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { iv }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // keep image centred while zooming
        let b = scrollView.bounds.size
        var f = iv.frame
        f.origin.x = f.width  < b.width  ? (b.width  - f.width)  / 2 : 0
        f.origin.y = f.height < b.height ? (b.height - f.height) / 2 : 0
        iv.frame = f
    }

    @objc private func doubleTap(_ g: UITapGestureRecognizer) {
        scroll.setZoomScale(scroll.zoomScale > 1.05 ? 1 : 2.5, animated: true)
    }
}

// MARK: - Camera session ───────────────────────────────────────────────────

final class TurkeySerialCameraSession: ObservableObject {
    @Published var isReady              = false
    @Published var permissionDenied     = false
    @Published var activeZoomPreset: CGFloat = 1.0
    @Published var availableZoomPresets: [CGFloat] = [1, 2, 4]
    @Published var flashOn              = false

    fileprivate weak var viewController: TurkeySerialCameraViewController?
    var onPhotoCaptured: ((UIImage, UIDeviceOrientation) -> Void)?

    private var pinchBase: CGFloat = 1.0

    func capturePhoto() { viewController?.capturePhoto() }
    func toggleFlash()  { viewController?.toggleFlash() }
    func flipCamera()   { viewController?.flipCamera() }

    func selectZoomPreset(_ v: CGFloat) {
        activeZoomPreset = v
        viewController?.applyZoom(v)
    }

    func applyPinchScale(_ scale: CGFloat, commit: Bool = false) {
        if scale == 1 && !commit {
            pinchBase = viewController?.currentZoom ?? activeZoomPreset
        }
        let factor = (pinchBase * scale)
        viewController?.setZoom(factor)
        let snapped = availableZoomPresets.min(by: { abs($0 - factor) < abs($1 - factor) }) ?? 1
        if abs(snapped - activeZoomPreset) > 0.05 { activeZoomPreset = snapped }
    }

    fileprivate func setPresets(_ p: [CGFloat], active: CGFloat) {
        availableZoomPresets = p
        activeZoomPreset = active
    }
}

// MARK: - UIViewControllerRepresentable ────────────────────────────────────

private struct TurkeySerialCameraRepresentable: UIViewControllerRepresentable {
    @ObservedObject var session: TurkeySerialCameraSession

    func makeUIViewController(context: Context) -> TurkeySerialCameraViewController {
        let vc = TurkeySerialCameraViewController()
        wire(vc); context.coordinator.vc = vc
        return vc
    }

    func updateUIViewController(_ vc: TurkeySerialCameraViewController, context: Context) {
        wire(vc); context.coordinator.vc = vc
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func wire(_ vc: TurkeySerialCameraViewController) {
        session.viewController = vc
        vc.onPhotoCaptured = { [weak session] img, orientation in
            session?.onPhotoCaptured?(img, orientation)
        }
        vc.onReadyChanged     = { [weak session] r  in DispatchQueue.main.async { session?.isReady = r } }
        vc.onPermissionDenied = { [weak session]    in DispatchQueue.main.async { session?.permissionDenied = true } }
        vc.onPresetsChanged   = { [weak session] p, a in DispatchQueue.main.async { session?.setPresets(p, active: a) } }
        vc.onFlashChanged     = { [weak session] on in DispatchQueue.main.async { session?.flashOn = on } }
    }

    final class Coordinator { weak var vc: TurkeySerialCameraViewController? }
}

// MARK: - Camera view controller ───────────────────────────────────────────

fileprivate final class TurkeySerialCameraViewController: UIViewController,
                                                           AVCapturePhotoCaptureDelegate {
    var onPhotoCaptured:    ((UIImage, UIDeviceOrientation) -> Void)?
    var onReadyChanged:     ((Bool) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onPresetsChanged:   (([CGFloat], CGFloat) -> Void)?
    var onFlashChanged:     ((Bool) -> Void)?

    private let q         = DispatchQueue(label: "turkey.cam", qos: .userInitiated)
    private var session:    AVCaptureSession?
    private let output    = AVCapturePhotoOutput()
    private var preview:    AVCaptureVideoPreviewLayer?
    private let container = UIView()
    private var configured = false

    private var ultraWide: AVCaptureDevice?
    private var wide:      AVCaptureDevice?
    private var tele:      AVCaptureDevice?
    private var activeIn:  AVCaptureDeviceInput?
    private var pos: AVCaptureDevice.Position = .back

    private(set) var currentZoom: CGFloat = 1.0
    private var activePreset: CGFloat = 1.0
    private var flashOn = false

    /// Last non-ambiguous physical orientation (excludes faceUp/faceDown/unknown).
    private var lastKnownOrientation: UIDeviceOrientation = .portrait
    private var captureOrientationAtShutter: UIDeviceOrientation = .portrait
    private let motionManager = CMMotionManager()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        container.backgroundColor = .black
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.12
            motionManager.startAccelerometerUpdates()
        }
        checkAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = container.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        q.async { self.session?.stopRunning() }
        motionManager.stopAccelerometerUpdates()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self,
            name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc private func deviceOrientationChanged() {
        let o = UIDevice.current.orientation
        // Only cache orientations that unambiguously describe how the device is held.
        switch o {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            lastKnownOrientation = o
        default:
            break   // faceUp / faceDown / unknown: keep last good value
        }
    }

    // MARK: Public interface

    /// Physical tilt via accelerometer (works when system rotation lock is on).
    private func physicalCaptureOrientation() -> UIDeviceOrientation {
        if let accel = motionManager.accelerometerData?.acceleration {
            let x = accel.x
            let y = accel.y
            let threshold: Double = 0.62
            if abs(y) >= abs(x) {
                if y < -threshold { return .portrait }
                if y > threshold { return .portraitUpsideDown }
            } else {
                if x < -threshold { return .landscapeRight }
                if x > threshold { return .landscapeLeft }
            }
        }
        return lastKnownOrientation
    }

    func capturePhoto() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let devOri = self.physicalCaptureOrientation()
            self.captureOrientationAtShutter = devOri
            self.q.async {
                guard let conn = self.output.connection(with: .video) else { return }
                // Map physical device orientation → AVFoundation rotation angle.
                // This is independent of the UI orientation lock.
                let angle: CGFloat
                switch devOri {
                case .landscapeLeft:      angle = 0    // power/home button on right
                case .landscapeRight:     angle = 180  // power/home button on left
                case .portraitUpsideDown: angle = 270
                default:                  angle = 90   // portrait (upright) — safe default
                }
                if conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                } else {
                    switch devOri {
                    case .landscapeLeft:  conn.videoOrientation = .landscapeRight
                    case .landscapeRight: conn.videoOrientation = .landscapeLeft
                    default:              conn.videoOrientation = .portrait
                    }
                }
                let s = self.makeHighQualityPhotoSettings()
                s.flashMode = self.flashOn ? .auto : .off
                self.output.capturePhoto(with: s, delegate: self)
            }
        }
    }

    func toggleFlash() {
        flashOn.toggle(); let v = flashOn
        DispatchQueue.main.async { self.onFlashChanged?(v) }
    }

    func flipCamera() {
        q.async { [weak self] in
            guard let self else { return }
            self.pos = self.pos == .back ? .front : .back
            self.discoverDevices()
            let dev: AVCaptureDevice? = self.pos == .back
                ? self.wide
                : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            guard let dev else { return }
            self.switchTo(dev, zoom: 1)
            self.activePreset = 1
            self.publishPresets()
        }
    }

    func applyZoom(_ preset: CGFloat) {
        q.async { [weak self] in self?.applyPreset(preset) }
    }

    func setZoom(_ factor: CGFloat) {
        q.async { [weak self] in
            guard let d = self?.activeIn?.device else { return }
            self?.digital(factor, on: d)
        }
    }

    // MARK: Delegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return }
        let img: UIImage?
        if let cg = photo.cgImageRepresentation() {
            img = UIImage(cgImage: cg, scale: 1, orientation: .up)
        } else if let data = photo.fileDataRepresentation() {
            img = UIImage(data: data)
        } else {
            img = nil
        }
        guard let img else { return }
        let orientation = self.captureOrientationAtShutter
        DispatchQueue.main.async { self.onPhotoCaptured?(img, orientation) }
    }

    // MARK: Private

    private func checkAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { ok ? self?.configure() : self?.onPermissionDenied?() }
            }
        default: onPermissionDenied?()
        }
    }

    private func discoverDevices() {
        ultraWide = nil; wide = nil; tele = nil
        let disc = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: pos)
        for d in disc.devices {
            switch d.deviceType {
            case .builtInUltraWideCamera: ultraWide = d
            case .builtInTelephotoCamera: tele = d
            case .builtInWideAngleCamera: wide = d
            default: if wide == nil { wide = d }
            }
        }
        if wide == nil {
            wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
                ?? AVCaptureDevice.default(for: .video)
        }
    }

    private func configure() {
        q.async { [weak self] in
            guard let self, !self.configured else { return }
            self.discoverDevices()
            guard let dev = self.wide else {
                DispatchQueue.main.async { self.onPermissionDenied?() }; return
            }
            self.applyBestPhotoFormat(to: dev)

            let s = AVCaptureSession()
            s.beginConfiguration()
            if s.canSetSessionPreset(.photo) {
                s.sessionPreset = .photo
            } else if s.canSetSessionPreset(.high) {
                s.sessionPreset = .high
            }
            guard let inp = try? AVCaptureDeviceInput(device: dev), s.canAddInput(inp) else {
                s.commitConfiguration()
                DispatchQueue.main.async { self.onPermissionDenied?() }; return
            }
            s.addInput(inp); self.activeIn = inp
            guard s.canAddOutput(self.output) else {
                s.commitConfiguration()
                DispatchQueue.main.async { self.onPermissionDenied?() }; return
            }
            s.addOutput(self.output)
            if #available(iOS 16.0, *) {
                self.output.maxPhotoQualityPrioritization = .quality
            }
            self.applyNoMirrorToVideoConnection(self.output.connection(with: .video))
            if let conn = self.output.connection(with: .video) {
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                } else {
                    conn.videoOrientation = .portrait
                }
            }
            s.commitConfiguration(); self.session = s; self.configured = true
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: s)
                layer.videoGravity = .resizeAspect
                layer.frame = self.container.bounds
                self.preview?.removeFromSuperlayer()
                self.container.layer.insertSublayer(layer, at: 0)
                self.preview = layer
                self.onReadyChanged?(true)
                self.publishPresets()
            }
            if !s.isRunning { s.startRunning() }
        }
    }

    private func publishPresets() {
        var p: [CGFloat] = []
        if pos == .back {
            if ultraWide != nil { p.append(0.5) }
            p.append(1)
            if tele != nil || (wide?.activeFormat.videoMaxZoomFactor ?? 1) >= 2 { p.append(2) }
            if tele != nil || (wide?.activeFormat.videoMaxZoomFactor ?? 1) >= 4 { p.append(4) }
            if (wide?.activeFormat.videoMaxZoomFactor ?? 1) >= 8                { p.append(8) }
        } else { p = [1] }
        DispatchQueue.main.async { self.onPresetsChanged?(p, self.activePreset) }
    }

    private func applyPreset(_ preset: CGFloat) {
        activePreset = preset
        guard pos == .back else { return }
        if preset < 0.75, let u = ultraWide { switchTo(u, zoom: 1); publishPresets(); return }
        guard let w = wide else { publishPresets(); return }
        if preset >= 5, let t = tele       { switchTo(t, zoom: min(2, t.activeFormat.videoMaxZoomFactor)) }
        else if preset >= 3, let t = tele  { switchTo(t, zoom: 1) }
        else                               { switchTo(w, zoom: max(1, preset)) }
        publishPresets()
    }

    private func digital(_ factor: CGFloat, on dev: AVCaptureDevice) {
        let v = max(1, min(factor, min(dev.activeFormat.videoMaxZoomFactor, 8)))
        do {
            try dev.lockForConfiguration()
            dev.videoZoomFactor = v
            dev.unlockForConfiguration()
            currentZoom = v
        } catch {}
    }

    private func switchTo(_ device: AVCaptureDevice, zoom: CGFloat) {
        guard let s = session else { return }
        s.beginConfiguration()
        if let ai = activeIn { s.removeInput(ai) }
        guard let ni = try? AVCaptureDeviceInput(device: device), s.canAddInput(ni) else {
            if let ai = activeIn { s.addInput(ai) }
            s.commitConfiguration(); return
        }
        s.addInput(ni); activeIn = ni
        applyBestPhotoFormat(to: device)
        applyNoMirrorToVideoConnection(output.connection(with: .video))
        s.commitConfiguration()
        digital(zoom, on: device)
        currentZoom = zoom
    }

    private func applyBestPhotoFormat(to device: AVCaptureDevice) {
        guard let best = Self.highestResolutionFormat(for: device) else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private static func highestResolutionFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.max { a, b in
            let da = a.formatDescription.dimensions
            let db = b.formatDescription.dimensions
            let pa = Int(da.width) * Int(da.height)
            let pb = Int(db.width) * Int(db.height)
            return pa < pb
        }
    }

    private func applyNoMirrorToVideoConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    private func makeHighQualityPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = output.maxPhotoDimensions
        } else {
            settings.isHighResolutionPhotoEnabled = true
        }
        if #available(iOS 13.0, *) {
            settings.photoQualityPrioritization = .quality
        }
        return settings
    }
}

// MARK: - Portrait-locked presenter (camera UI never rotates)

struct TurkeySerialCapturePresenter: UIViewControllerRepresentable {
    let onPhotoCaptured: (UIImage) -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PortraitLockedHostingController<TurkeySerialCaptureView> {
        let root = TurkeySerialCaptureView(
            onPhotoCaptured: onPhotoCaptured,
            onDone: onDone,
            onCancel: onCancel
        )
        return PortraitLockedHostingController(rootView: root)
    }

    func updateUIViewController(
        _ uiViewController: PortraitLockedHostingController<TurkeySerialCaptureView>,
        context: Context
    ) {}
}

/// Keeps the serial camera UI in portrait even when the device is turned sideways.
final class PortraitLockedHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
}
