import SwiftUI
import AVFoundation

/// NVIDIA LocateAnything-3B camera — parallel box decoding for object + plate localization.
struct CosmosVisionCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AracViewModel

    @State private var taramaAktif = true
    @State private var kameraIzniYok = false
    @State private var isAnalyzing = false
    @State private var liveScan = true
    @State private var lastResult: CosmosVisionAnalysisResult = .empty
    @State private var errorMessage: String?
    @State private var lastCapture: UIImage?
    @State private var matchedVehicle: Arac?
    @State private var lastAnalysisAt: Date = .distantPast
    @State private var analysisGeneration = 0

    private let liveInterval: TimeInterval = 1.8

    var body: some View {
        NavigationStack {
            ZStack {
                if kameraIzniYok {
                    permissionDenied
                } else {
                    CosmosVisionCameraRepresentable(
                        taramaAktif: $taramaAktif,
                        kameraIzniYok: $kameraIzniYok,
                        onFrame: { image in
                            lastCapture = image
                            guard liveScan, !isAnalyzing else { return }
                            let now = Date()
                            guard now.timeIntervalSince(lastAnalysisAt) >= liveInterval else { return }
                            Task { await runAnalysis(image) }
                        }
                    )
                    .ignoresSafeArea()

                    CosmosDetectionOverlay(
                        objects: lastResult.objects,
                        frameSize: overlayFrameSize,
                        licensePlate: lastResult.licensePlate,
                        isAnalyzing: isAnalyzing
                    )
                    .ignoresSafeArea()

                    VStack {
                        headerBadge
                        Spacer()
                        resultsPanel
                    }
                }
            }
            .navigationTitle("cosmos.camera.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        liveScan.toggle()
                        if liveScan, let img = lastCapture {
                            Task { await runAnalysis(img) }
                        }
                    } label: {
                        Image(systemName: liveScan ? "dot.radiowaves.left.and.right" : "dot.radiowaves.right")
                            .symbolEffect(.pulse, isActive: liveScan && isAnalyzing)
                    }
                    .accessibilityLabel("cosmos.camera.live".localized)
                }
            }
            .onAppear {
                taramaAktif = true
                if liveScan {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if let img = lastCapture {
                            Task { await runAnalysis(img) }
                        }
                    }
                }
            }
            .onDisappear { taramaAktif = false }
        }
    }

    private var overlayFrameSize: CGSize {
        if lastResult.frameSize.width > 0 { return lastResult.frameSize }
        guard let img = lastCapture else { return CGSize(width: 3, height: 4) }
        return img.size
    }

    private var headerBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(Color.green)
            Text(LocateAnythingVisionService.shared.activeBackendLabel)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(.white)
            Spacer()
            if liveScan {
                Text("LIVE")
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            if isAnalyzing {
                ProgressView().tint(.white).scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plate = lastResult.licensePlate, !plate.isEmpty {
                HStack {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .foregroundStyle(PalantirTheme.success)
                    Text(plate)
                        .font(PalantirTheme.dataFont(18))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    if let conf = lastResult.plateConfidence {
                        Text("\(Int(conf * 100))%")
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                if let vehicle = matchedVehicle {
                    NavigationLink {
                        AracDetayView(arac: vehicle)
                            .environmentObject(viewModel)
                    } label: {
                        Label("cosmos.camera.open_vehicle".localized, systemImage: "car.fill")
                            .font(PalantirTheme.bodyFont(13))
                    }
                }
            }

            if !lastResult.objects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(lastResult.objects.prefix(8)) { obj in
                            Text("\(obj.label) \(obj.confidencePercent)%")
                                .font(PalantirTheme.labelFont(9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(obj.isPlateLike ? Color.green.opacity(0.25) : PalantirTheme.surfaceHigh)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if !lastResult.summary.isEmpty {
                Text(lastResult.summary)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
            }

            if let err = errorMessage {
                Text(err)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.critical)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await captureAndAnalyze() }
                } label: {
                    Label("cosmos.camera.scan_now".localized, systemImage: "camera.viewfinder")
                        .font(PalantirTheme.heroFont(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(PalantirTheme.accent)
                .disabled(isAnalyzing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private var permissionDenied: some View {
        ContentUnavailableView(
            "cosmos.camera.permission_title".localized,
            systemImage: "camera.fill",
            description: Text("cosmos.camera.permission_body".localized)
        )
    }

    private func captureAndAnalyze() async {
        guard let image = lastCapture else {
            errorMessage = "cosmos.camera.wait_frame".localized
            return
        }
        await runAnalysis(image)
    }

    private func runAnalysis(_ image: UIImage) async {
        let generation = analysisGeneration + 1
        analysisGeneration = generation
        lastCapture = image
        isAnalyzing = true
        errorMessage = nil
        lastAnalysisAt = Date()

        let fid = FirebaseService.shared.currentFranchiseId.uppercased()
        let hint = fid.hasPrefix("DE") ? "DE" : (fid.hasPrefix("CH") ? "CH" : "EU")

        defer {
            if analysisGeneration == generation {
                isAnalyzing = false
            }
        }

        do {
            let result = try await LocateAnythingVisionService.shared.analyzeFrame(image, countryHint: hint)
            guard analysisGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                lastResult = result
                matchedVehicle = matchFleet(plate: result.licensePlate)
            }
        } catch {
            guard analysisGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func matchFleet(plate: String?) -> Arac? {
        guard let plate, !plate.isEmpty else { return nil }
        let norm = plate.uppercased().replacingOccurrences(of: " ", with: "")
        return viewModel.araclar.first {
            $0.plaka.uppercased().replacingOccurrences(of: " ", with: "") == norm
        }
    }
}

// MARK: - Camera capture

struct CosmosVisionCameraRepresentable: UIViewControllerRepresentable {
    @Binding var taramaAktif: Bool
    @Binding var kameraIzniYok: Bool
    var onFrame: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CosmosVisionCameraViewController {
        let vc = CosmosVisionCameraViewController()
        vc.onFrame = onFrame
        vc.onPermissionDenied = { DispatchQueue.main.async { kameraIzniYok = true } }
        return vc
    }

    func updateUIViewController(_ uiViewController: CosmosVisionCameraViewController, context: Context) {
        if taramaAktif { uiViewController.start() } else { uiViewController.stop() }
    }
}

final class CosmosVisionCameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((UIImage) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cosmos.camera.queue", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastFrameTime = Date.distantPast
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    ok ? self?.configureSession() : self?.onPermissionDenied?()
                }
            }
        default: onPermissionDenied?()
        }
    }

    private func configureSession() {
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.onPermissionDenied?() }
                return
            }
            session.addInput(input)

            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            session.commitConfiguration()
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= 0.2 else { return }
        lastFrameTime = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = Self.ciContext.createCGImage(ci, from: ci.extent) else { return }
        let image = UIImage(cgImage: cg, scale: 1, orientation: .right)
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(image)
        }
    }
}

// MARK: - Panel launcher card

struct CHPanelCosmosCameraCard: View {
    let onOpen: () -> Void

    private var hasKey: Bool { LocateAnythingVisionService.shared.hasAPIKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOCATE ANYTHING")
                        .font(PalantirTheme.labelFont(12))
                        .foregroundStyle(Color.green)
                        .tracking(1.2)
                    Text("cosmos.panel.subtitle".localized)
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer()
                if !hasKey {
                    Text("API")
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PalantirTheme.warning.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("cosmos.panel.body".localized)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpen) {
                HStack {
                    Text("cosmos.panel.open".localized)
                        .font(PalantirTheme.heroFont(14))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(PalantirTheme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(hasKey ? Color.green : PalantirTheme.accent.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .palantirCard()
    }
}
