import SwiftUI
import AVFoundation
import Vision

struct PlakaScannerRepresentable: UIViewControllerRepresentable {
    @Binding var taramaAktif: Bool
    @Binding var tarananPlaka: String
    @Binding var kameraIzniYok: Bool
    var countryId: String
    var germanyScanning: Binding<Bool> = .constant(false)
    
    func makeUIViewController(context: Context) -> PlakaScannerViewController {
        let controller = PlakaScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlakaScannerViewController, context: Context) {
        uiViewController.currentCountryId = countryId
        let scanBinding = germanyScanning
        uiViewController.onGermanyScanningChanged = { active in
            DispatchQueue.main.async { scanBinding.wrappedValue = active }
        }
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
    private var lastDetectionTime: Date = Date()
    var currentCountryId: String = "ch"
    
    private let sessionQueue = DispatchQueue(label: "scanner.session.queue")
    private let videoQueue   = DispatchQueue(label: "scanner.sample.queue")
    private let videoOutput  = AVCaptureVideoDataOutput()
    private var didConfigure = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermission()
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

        // Germany: clean YOLO → crop → OCR pipeline
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

        // Other countries: standard Vision pipeline
        guard Date().timeIntervalSince(lastDetectionTime) > 1.5 else { return }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            var allTexts: [String] = []
            for observation in observations {
                let candidates = observation.topCandidates(5)
                for candidate in candidates {
                    allTexts.append(candidate.string.uppercased())
                }
            }

            if let plaka = self.findBestPlate(from: allTexts) {
                self.lastDetectionTime = Date()
                DispatchQueue.main.async {
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    self.delegate?.plakaDetected(plaka)
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.0
        request.customWords = CountryManager.ocrHints(for: currentCountryId)

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? requestHandler.perform([request])
    }
    
    func findBestPlate(from texts: [String]) -> String? {
        CountryManager.bestDetectedPlate(from: texts, countryId: currentCountryId)
    }
    
    func generateVariations(_ text: String) -> [String] {
        var variations: [String] = []
        let replacements: [(String, String)] = [
            ("O", "0"), ("0", "O"),
            ("I", "1"), ("1", "I"),
            ("S", "5"), ("5", "S"),
            ("Z", "2"), ("2","Z"),
            ("B", "8"), ("8", "B")
        ]
        for (from, to) in replacements {
            if text.contains(from) {
                variations.append(text.replacingOccurrences(of: from, with: to))
            }
        }
        return variations
    }
    
    func extractPlate(from text: String) -> String? {
        let pattern = "[A-Z]{2}[0-9]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        if let match = regex?.firstMatch(in: text, range: range) {
            let matchRange = match.range
            if let swiftRange = Range(matchRange, in: text) {
                let plate = String(text[swiftRange])
                if isValidPlate(plate) {
                    return plate
                }
            }
        }
        return nil
    }
    
    func isValidPlate(_ text: String) -> Bool {
        CountryManager.validatePlate(text, forCountry: currentCountryId)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}
