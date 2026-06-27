import SwiftUI
import AVFoundation
import Vision

struct PlakaScannerRepresentable: UIViewControllerRepresentable {
    @Binding var taramaAktif: Bool
    @Binding var tarananPlaka: String
    @Binding var kameraIzniYok: Bool
    var countryId: String
    var germanyScanning: Binding<Bool> = .constant(false)
    @Binding var zoomFactor: CGFloat
    var onZoomFactorChanged: ((CGFloat) -> Void)?

    func makeUIViewController(context: Context) -> PlakaScannerViewController {
        let controller = PlakaScannerViewController()
        controller.delegate = context.coordinator
        controller.onZoomFactorChanged = { factor in
            DispatchQueue.main.async {
                onZoomFactorChanged?(factor)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: PlakaScannerViewController, context: Context) {
        uiViewController.currentCountryId = countryId
        uiViewController.onZoomFactorChanged = { factor in
            DispatchQueue.main.async {
                onZoomFactorChanged?(factor)
            }
        }
        let scanBinding = germanyScanning
        uiViewController.onGermanyScanningChanged = { active in
            DispatchQueue.main.async { scanBinding.wrappedValue = active }
        }
        uiViewController.setZoomFactor(zoomFactor)
        if taramaAktif {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PlakaScannerDelegate {
        let parent: PlakaScannerRepresentable

        init(_ parent: PlakaScannerRepresentable) {
            self.parent = parent
        }

        func plakaDetected(_ plaka: String) {
            parent.tarananPlaka = plaka
        }

        func kameraIzniReddedildi() {
            parent.kameraIzniYok = true
        }
    }
}

protocol PlakaScannerDelegate: AnyObject {
    func plakaDetected(_ plaka: String)
    func kameraIzniReddedildi()
}

class PlakaScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: PlakaScannerDelegate?
    var onGermanyScanningChanged: ((Bool) -> Void)?
    var onZoomFactorChanged: ((CGFloat) -> Void)?
    private var lastDetectionTime: Date = Date()
    var currentCountryId: String = "ch"

    private let sessionQueue = DispatchQueue(label: "scanner.session.queue")
    private let videoQueue = DispatchQueue(label: "scanner.sample.queue")
    private let visionQueue = DispatchQueue(label: "scanner.vision.queue", qos: .userInitiated)
    private var isProcessingVisionFrame = false
    private let videoOutput = AVCaptureVideoDataOutput()
    private var didConfigure = false
    private weak var captureDevice: AVCaptureDevice?
    private var currentZoomFactor: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        checkCameraPermission()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .changed || recognizer.state == .ended else { return }
        let proposed = currentZoomFactor * recognizer.scale
        recognizer.scale = 1.0
        let clamped = min(max(proposed, 1.0), maxZoomFactor())
        currentZoomFactor = clamped
        setZoomFactor(clamped)
        onZoomFactorChanged?(clamped)
    }

    func setZoomFactor(_ factor: CGFloat) {
        let clamped = min(max(factor, 1.0), maxZoomFactor())
        currentZoomFactor = clamped
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // Best-effort zoom
            }
        }
    }

    private func maxZoomFactor() -> CGFloat {
        min(captureDevice?.activeFormat.videoMaxZoomFactor ?? 4.0, 6.0)
    }

    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.delegate?.kameraIzniReddedildi()
                    }
                }
            }
        case .denied, .restricted:
            delegate?.kameraIzniReddedildi()
        @unknown default:
            delegate?.kameraIzniReddedildi()
        }
    }

    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.didConfigure else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .high

            session.beginConfiguration()

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video) else {
                session.commitConfiguration()
                return
            }
            self.captureDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    session.commitConfiguration()
                    return
                }
            } catch {
                session.commitConfiguration()
                return
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)

            if session.canAddOutput(self.videoOutput) {
                session.addOutput(self.videoOutput)
            } else {
                session.commitConfiguration()
                return
            }

            self.videoOutput.connection(with: .video)?.videoOrientation = .portrait

            session.commitConfiguration()

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.frame = self.view.layer.bounds
                previewLayer.videoGravity = .resizeAspectFill
                if let old = self.previewLayer {
                    old.removeFromSuperlayer()
                }
                self.view.layer.addSublayer(previewLayer)
                self.previewLayer = previewLayer
            }

            self.captureSession = session
            self.didConfigure = true
            self.setZoomFactor(self.currentZoomFactor)
            self.startScanning()
        }
    }

    func startScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if currentCountryId == "de" {
            guard Date().timeIntervalSince(lastDetectionTime) > 0.35 else { return }
            lastDetectionTime = Date()
            PlateScanCoordinator.shared.scanGermanPlate(from: pixelBuffer, scanningChanged: { [weak self] active in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.onGermanyScanningChanged?(active)
                }
            }, completion: { [weak self] plate in
                guard let self, let plaka = plate else { return }
                DispatchQueue.main.async {
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    self.delegate?.plakaDetected(plaka)
                }
            })
            return
        }

        guard Date().timeIntervalSince(lastDetectionTime) > 1.5 else { return }
        guard !isProcessingVisionFrame else { return }
        isProcessingVisionFrame = true

        let countryId = currentCountryId
        visionQueue.async { [weak self] in
            defer {
                self?.videoQueue.async {
                    self?.isProcessingVisionFrame = false
                }
            }
            guard let self else { return }

            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

                var plateCandidates: [String] = []
                for observation in observations {
                    let box = observation.boundingBox
                    guard box.midY < 0.72 else { continue }
                    guard box.height <= 0.22 else { continue }

                    for candidate in observation.topCandidates(3) {
                        let raw = candidate.string.uppercased()
                        guard CountryManager.ocrTextLooksLikePlate(raw, countryId: countryId) else { continue }
                        plateCandidates.append(raw)
                    }
                }

                if let plaka = self.findBestPlate(from: plateCandidates) {
                    self.lastDetectionTime = Date()
                    DispatchQueue.main.async {
                        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                        self.delegate?.plakaDetected(plaka)
                    }
                }
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = countryId == "tr" ? ["tr-TR", "en-US"] : ["en"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.02
            request.customWords = CountryManager.ocrHints(for: countryId)

            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? requestHandler.perform([request])
        }
    }

    func findBestPlate(from texts: [String]) -> String? {
        CountryManager.bestDetectedPlate(from: texts, countryId: currentCountryId)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}
