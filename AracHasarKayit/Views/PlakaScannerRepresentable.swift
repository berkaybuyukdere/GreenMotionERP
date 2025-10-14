import SwiftUI
import AVFoundation
import Vision

struct PlakaScannerRepresentable: UIViewControllerRepresentable {
    @Binding var taramaAktif: Bool
    @Binding var tarananPlaka: String
    @Binding var kameraIzniYok: Bool
    
    func makeUIViewController(context: Context) -> PlakaScannerViewController {
        let controller = PlakaScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlakaScannerViewController, context: Context) {
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
    private var lastDetectionTime: Date = Date()
    private let validCantons = ["ZH", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR", "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG", "TI", "VD", "VS", "NE", "GE", "JU"]
    
    // ✅ Eklenen sağlamlaştırmalar
    private let sessionQueue = DispatchQueue(label: "scanner.session.queue")        // Session işleri için seri kuyruk
    private let videoQueue   = DispatchQueue(label: "scanner.sample.queue")         // Örnek buffer’lar için seri kuyruk
    private let videoOutput  = AVCaptureVideoDataOutput()                           // Tek örnek
    private var didConfigure = false                                                // Tek sefer konfigürasyon
    
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
            guard !self.didConfigure else { return } // tekrar kurulumu engelle
            let session = AVCaptureSession()
            session.sessionPreset = .high
            
            session.beginConfiguration()
            
            // Input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video) else {
                print("Kamera bulunamadı")
                session.commitConfiguration()
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    print("Video input eklenemedi")
                    session.commitConfiguration()
                    return
                }
            } catch {
                print("Kamera girişi oluşturulamadı: \(error)")
                session.commitConfiguration()
                return
            }
            
            // Output
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            
            if session.canAddOutput(self.videoOutput) {
                session.addOutput(self.videoOutput)
            } else {
                print("Video output eklenemedi")
                session.commitConfiguration()
                return
            }
            
            // Orientation
            self.videoOutput.connection(with: .video)?.videoOrientation = .portrait
            
            session.commitConfiguration()
            
            // UI: preview layer ana thread’de eklenir/güncellenir
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
        guard Date().timeIntervalSince(lastDetectionTime) > 1.5 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
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
        request.customWords = validCantons
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? requestHandler.perform([request])
    }
    
    func findBestPlate(from texts: [String]) -> String? {
        for text in texts {
            let cleaned = text.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
                .uppercased()
            
            if isValidSwissPlate(cleaned) {
                return cleaned
            }
            
            let variations = generateVariations(cleaned)
            for variation in variations {
                if isValidSwissPlate(variation) {
                    return variation
                }
            }
            
            if let extracted = extractPlate(from: cleaned) {
                return extracted
            }
        }
        
        return nil
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
                if isValidSwissPlate(plate) {
                    return plate
                }
            }
        }
        
        return nil
    }
    
    func isValidSwissPlate(_ text: String) -> Bool {
        guard text.count >= 3 && text.count <= 8 else { return false }
        
        let canton = String(text.prefix(2))
        guard validCantons.contains(canton) else { return false }
        
        let numbers = String(text.dropFirst(2))
        guard !numbers.isEmpty && numbers.allSatisfy({ $0.isNumber }) else { return false }
        
        return true
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}
