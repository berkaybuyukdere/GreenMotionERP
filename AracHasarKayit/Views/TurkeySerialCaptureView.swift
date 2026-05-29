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

// MARK: - Main view ───────────────────────────────────────────────────────

struct TurkeySerialCaptureView: View {

    let onPhotoCaptured: (UIImage) -> Void
    let onDone:          () -> Void
    let onCancel:        () -> Void
    var onPhotoDeletedAtIndex: ((Int) -> Void)? = nil

    @StateObject private var cam = TurkeySerialCameraSession()

    @State private var thumbs:        [UIImage] = []
    @State private var showGallery    = false
    @State private var galleryStart   = 0
    @State private var showGrid       = true
    @State private var showExitAlert  = false
    @State private var captureFlashOpacity: Double = 0

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
        .onAppear {
            cam.onPhotoCaptured = { img, orientation in
                let n = TurkeyCaptureImageOrientation.preparedForStorage(
                    deviceOrientation: orientation,
                    image: img
                )
                thumbs.append(n)
                galleryStart = thumbs.count - 1
                onPhotoCaptured(n)
                HapticManager.shared.success()
                triggerCaptureFlash()
            }
        }
        .alert("tr_serial.discard_title".localized, isPresented: $showExitAlert) {
            Button("Discard".localized, role: .destructive) { onCancel() }
            Button("Keep shooting".localized, role: .cancel) { }
        } message: {
            Text("tr_serial.exit_warning".localized)
        }
        .fullScreenCover(isPresented: $showGallery) {
            TurkeySerialFilmstripView(images: thumbs, initialIndex: galleryStart, onDismiss: {
                showGallery = false
            }, onDeleteAtIndex: { index in
                guard thumbs.indices.contains(index) else { return }
                thumbs.remove(at: index)
                onPhotoDeletedAtIndex?(index)
                if thumbs.isEmpty {
                    showGallery = false
                } else if galleryStart >= thumbs.count {
                    galleryStart = thumbs.count - 1
                }
            })
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
                Color.white
                    .opacity(captureFlashOpacity)
                    .allowsHitTesting(false)
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

                topIconButton(
                    sf: showGrid ? "square.grid.3x3.fill" : "square.grid.3x3",
                    tint: showGrid ? SC.yellow : .white
                ) { showGrid.toggle() }

                Spacer()

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

    // MARK: - Pinch to zoom (continuous; iOS virtual camera handles lens switching)

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in cam.applyPinchScale(scale) }
            .onEnded { scale in cam.applyPinchScale(scale, commit: true) }
    }

    // MARK: - Bottom bar

    private func bottomBar(botH: CGFloat) -> some View {
        ZStack {
            Color.black
            HStack(alignment: .center) {
                thumbnailView.padding(.leading, 24)
                Spacer()
                shutterButton
                Spacer()
                iconCircleButton(sf: "arrow.triangle.2.circlepath.camera", size: 22) {
                    cam.flipCamera()
                }
                .padding(.trailing, 24)
            }
        }
        .frame(height: botH)
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
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: last)
                        .resizable().scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
                    Text("\(thumbs.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(SC.yellow))
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                        .offset(x: 8, y: -8)
                }
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

    private func triggerCaptureFlash() {
        captureFlashOpacity = 0.92
        withAnimation(.easeOut(duration: 0.28)) {
            captureFlashOpacity = 0
        }
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
    var onDeleteAtIndex: ((Int) -> Void)?

    @State private var selection: Int
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    init(
        images: [UIImage],
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        onDeleteAtIndex: ((Int) -> Void)? = nil
    ) {
        self.images = images
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.onDeleteAtIndex = onDeleteAtIndex
        _selection = State(initialValue: min(max(0, initialIndex), max(0, images.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 52)

                    TabView(selection: $selection) {
                        ForEach(images.indices, id: \.self) { i in
                            SCZoomableImageView(image: images[i])
                                .tag(i)
                                .frame(minHeight: 420)
                                .padding(.horizontal, 4)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
                    .frame(height: UIScreen.main.bounds.height * 0.52)

                    Text("\(selection + 1) / \(images.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(images.indices, id: \.self) { i in
                                Button { selection = i } label: {
                                    Image(uiImage: images[i])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    selection == i ? SC.yellow : Color.white.opacity(0.25),
                                                    lineWidth: selection == i ? 2.5 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }

                    if onDeleteAtIndex != nil {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("tr_serial.delete_photo".localized, systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 48)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    galleryCloseButton
                        .padding(.top, 52)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .alert("tr_serial.delete_photo_title".localized, isPresented: $showDeleteAlert) {
            Button("Delete".localized, role: .destructive) { deleteCurrentPhoto() }
            Button("Cancel".localized, role: .cancel) { }
        } message: {
            Text("tr_serial.delete_photo_message".localized)
        }
        .onChange(of: images.count) { _, count in
            if count == 0 {
                dismiss()
                onDismiss()
            } else if selection >= count {
                selection = count - 1
            }
        }
    }

    private func deleteCurrentPhoto() {
        guard images.indices.contains(selection) else { return }
        let idx = selection
        onDeleteAtIndex?(idx)
        let remaining = images.count - 1
        if remaining <= 0 {
            dismiss()
            onDismiss()
        } else {
            selection = min(idx, remaining - 1)
        }
    }

    private var galleryCloseButton: some View {
        Button {
            dismiss()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("tr_serial.close".localized)
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
    @Published var isReady = false
    @Published var permissionDenied = false

    fileprivate weak var viewController: TurkeySerialCameraViewController?
    var onPhotoCaptured: ((UIImage, UIDeviceOrientation) -> Void)?

    private var pinchBase: CGFloat = 1.0

    func capturePhoto() { viewController?.capturePhoto() }
    func flipCamera() { viewController?.flipCamera() }

    /// Pinch zoom only — `AVCaptureDevice.videoZoomFactor` on a virtual multi-camera device (Apple-recommended).
    func applyPinchScale(_ scale: CGFloat, commit: Bool = false) {
        if !commit && abs(scale - 1.0) < 0.02 {
            pinchBase = viewController?.displayZoomFactor ?? 1.0
        }
        let factor = pinchBase * scale
        viewController?.setVideoZoomFactor(factor, ramp: commit)
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
    }

    final class Coordinator { weak var vc: TurkeySerialCameraViewController? }
}

// MARK: - Camera view controller ───────────────────────────────────────────

fileprivate final class TurkeySerialCameraViewController: UIViewController,
                                                           AVCapturePhotoCaptureDelegate {
    var onPhotoCaptured:    ((UIImage, UIDeviceOrientation) -> Void)?
    var onReadyChanged:     ((Bool) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let q         = DispatchQueue(label: "turkey.cam", qos: .userInitiated)
    private let photoQ    = DispatchQueue(label: "turkey.cam.photo", qos: .userInitiated)
    private var session:    AVCaptureSession?
    private let output    = AVCapturePhotoOutput()
    private var preview:    AVCaptureVideoPreviewLayer?
    private let container = UIView()
    private var configured = false
    private var isCapturing = false

    private var activeIn:  AVCaptureDeviceInput?
    private var pos: AVCaptureDevice.Position = .back

    private(set) var displayZoomFactor: CGFloat = 1.0

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
        q.async { [weak self] in
            guard let self else { return }
            guard self.configured, !self.isCapturing else { return }
            self.isCapturing = true

            let devOri = self.physicalCaptureOrientation()
            self.captureOrientationAtShutter = devOri

            guard let conn = self.output.connection(with: .video) else {
                self.isCapturing = false
                return
            }
            let angle: CGFloat
            switch devOri {
            case .landscapeLeft:      angle = 0
            case .landscapeRight:     angle = 180
            case .portraitUpsideDown: angle = 270
            default:                  angle = 90
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
            s.flashMode = .off
            if let device = self.activeIn?.device, device.hasTorch {
                try? device.lockForConfiguration()
                if device.isTorchModeSupported(.off) { device.torchMode = .off }
                device.unlockForConfiguration()
            }
            self.output.capturePhoto(with: s, delegate: self)
        }
    }

    func flipCamera() {
        q.async { [weak self] in
            guard let self else { return }
            self.pos = self.pos == .back ? .front : .back
            guard let dev = Self.preferredDevice(for: self.pos) else { return }
            self.replaceActiveDevice(with: dev, initialZoom: 1.0)
        }
    }

    /// Continuous pinch zoom; virtual camera switches lenses automatically (see AVCaptureDevice virtual devices).
    func setVideoZoomFactor(_ factor: CGFloat, ramp: Bool) {
        q.async { [weak self] in
            guard let self, let device = self.activeIn?.device else { return }
            let clamped = Self.clampedZoom(factor, on: device)
            do {
                try device.lockForConfiguration()
                if ramp {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 6.0)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
                self.displayZoomFactor = clamped
            } catch {}
        }
    }

    // MARK: Delegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let orientation = captureOrientationAtShutter
        photoQ.async { [weak self] in
            defer {
                self?.q.async { self?.isCapturing = false }
            }
            guard let self else { return }
            guard error == nil else { return }

            let img: UIImage? = autoreleasepool {
                if let cg = photo.cgImageRepresentation() {
                    return UIImage(cgImage: cg, scale: 1, orientation: .up)
                }
                if let data = photo.fileDataRepresentation() {
                    return UIImage(data: data)
                }
                return nil
            }
            guard let img else { return }

            DispatchQueue.main.async { [weak self] in
                self?.onPhotoCaptured?(img, orientation)
            }
        }
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

    /// Prefer Apple virtual multi-camera devices so lens switching stays seamless during pinch zoom.
    private static func preferredDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let virtualTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            for type in virtualTypes {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return device
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }

    private static func clampedZoom(_ factor: CGFloat, on device: AVCaptureDevice) -> CGFloat {
        let minZ: CGFloat
        let maxZ: CGFloat
        if #available(iOS 15.0, *) {
            minZ = device.minAvailableVideoZoomFactor
            maxZ = device.maxAvailableVideoZoomFactor
        } else {
            minZ = 1.0
            maxZ = device.activeFormat.videoMaxZoomFactor
        }
        return min(max(factor, minZ), maxZ)
    }

    private func configure() {
        q.async { [weak self] in
            guard let self, !self.configured else { return }
            guard let dev = Self.preferredDevice(for: self.pos) else {
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
                self.setVideoZoomFactor(1.0, ramp: false)
                self.onReadyChanged?(true)
            }
            if !s.isRunning { s.startRunning() }
        }
    }

    private func replaceActiveDevice(with device: AVCaptureDevice, initialZoom: CGFloat) {
        guard let s = session else { return }
        s.beginConfiguration()
        if let ai = activeIn { s.removeInput(ai) }
        guard let ni = try? AVCaptureDeviceInput(device: device), s.canAddInput(ni) else {
            if let ai = activeIn { s.addInput(ai) }
            s.commitConfiguration()
            return
        }
        s.addInput(ni)
        activeIn = ni
        applyBestPhotoFormat(to: device)
        applyNoMirrorToVideoConnection(output.connection(with: .video))
        s.commitConfiguration()
        setVideoZoomFactor(initialZoom, ramp: false)
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
            if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
            if device.isFlashModeSupported(.off) {
                device.flashMode = .off
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
