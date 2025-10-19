import SwiftUI
import UIKit
import AVFoundation

struct LandscapeCameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: LandscapeCameraView
        
        init(_ parent: LandscapeCameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.selectedImage = image
            parent.dismiss()
        }
        
        func didCancel() {
            parent.dismiss()
        }
    }
}

protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didCancel()
}

class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?
    
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!
    private var captureButton: UIButton!
    private var cancelButton: UIButton!
    private var flashButton: UIButton!
    private var isFlashOn = false
    
    // ✅ FIX: Store device orientation at capture time
    private var captureDeviceOrientation: UIDeviceOrientation = .portrait
    
    // Zoom and Focus properties
    private var captureDevice: AVCaptureDevice?
    private var currentZoom: CGFloat = 1.0
    private var zoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 5.0]
    private var currentZoomIndex: Int = 1 // Start with 1x
    private var focusIndicator: UIView!
    private var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    // Camera lens options
    private var wideCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var macroCamera: AVCaptureDevice?
    private var currentCameraType: CameraType = .wide
    private var zoomButton: UIButton!
    
    enum CameraType {
        case ultraWide  // 0.5x
        case wide       // 1x
        case macro      // 2x
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        
        // Force portrait orientation - UI stays locked
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewLayerFrame()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Keep UI locked - no rotation
        // UI will stay in portrait mode regardless of device rotation
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        // Setup different camera types
        setupCameraDevices()
        
        // Start with wide camera
        switchToCamera(.wide)
        
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Set up gestures
        setupGestures()
    }
    
    private func setupCameraDevices() {
        // Ultra wide camera (0.5x)
        ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        
        // Wide camera (1x)
        wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        
        // Macro camera (2x) - if available
        macroCamera = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        
        // Set initial camera
        captureDevice = wideCamera
    }
    
    private func switchToCamera(_ cameraType: CameraType) {
        guard let newDevice = getCameraForType(cameraType) else { return }
        
        // Remove current input
        if let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput {
            captureSession.removeInput(currentInput)
        }
        
        // Add new input
        do {
            let input = try AVCaptureDeviceInput(device: newDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                captureDevice = newDevice
                currentCameraType = cameraType
                
                // Set up zoom for new camera
                try newDevice.lockForConfiguration()
                newDevice.videoZoomFactor = currentZoom
                newDevice.unlockForConfiguration()
            }
        } catch {
            print("Error switching camera: \(error)")
        }
    }
    
    private func getCameraForType(_ cameraType: CameraType) -> AVCaptureDevice? {
        switch cameraType {
        case .ultraWide:
            return ultraWideCamera
        case .wide:
            return wideCamera
        case .macro:
            return macroCamera
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Cancel button - Apple style
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // Flash button - Apple style
        flashButton = UIButton(type: .system)
        flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        flashButton.layer.cornerRadius = 20
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        view.addSubview(flashButton)
        
        // Capture button - Apple style
        captureButton = UIButton(type: .custom)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 40
        captureButton.layer.borderWidth = 6
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Zoom button - Apple style
        zoomButton = UIButton(type: .system)
        zoomButton.setTitle("1x", for: .normal)
        zoomButton.setTitleColor(.white, for: .normal)
        zoomButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        zoomButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        zoomButton.layer.cornerRadius = 22
        zoomButton.addTarget(self, action: #selector(zoomButtonTapped), for: .touchUpInside)
        view.addSubview(zoomButton)
        
        // Focus indicator
        focusIndicator = UIView()
        focusIndicator.layer.borderColor = UIColor.yellow.cgColor
        focusIndicator.layer.borderWidth = 2
        focusIndicator.backgroundColor = UIColor.clear
        focusIndicator.isHidden = true
        view.addSubview(focusIndicator)
        
        setupConstraints()
    }
    
    
    private func setupGestures() {
        // Pinch gesture for zoom
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // Tap gesture for focus
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupConstraints() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        focusIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Cancel button - Apple style positioning
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            // Flash button - Apple style positioning
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
            flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Zoom button - Apple style positioning
            zoomButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
            zoomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomButton.widthAnchor.constraint(equalToConstant: 60),
            zoomButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Focus indicator - Apple style
            focusIndicator.widthAnchor.constraint(equalToConstant: 80),
            focusIndicator.heightAnchor.constraint(equalToConstant: 80),
            focusIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            focusIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Capture button - Apple style positioning
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            captureButton.widthAnchor.constraint(equalToConstant: 80),
            captureButton.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    
    private func updatePreviewLayerFrame() {
        // Make camera preview cover entire screen
        previewLayer.frame = view.bounds
        previewLayer.connection?.videoOrientation = .portrait
    }
    
    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    private func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    @objc private func cancelTapped() {
        delegate?.didCancel()
    }
    
    @objc private func flashTapped() {
        isFlashOn.toggle()
        let imageName = isFlashOn ? "bolt.fill" : "bolt.slash"
        flashButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func zoomButtonTapped() {
        // Cycle through zoom levels
        currentZoomIndex = (currentZoomIndex + 1) % zoomLevels.count
        let selectedZoom = zoomLevels[currentZoomIndex]
        
        // Switch camera if needed
        switch selectedZoom {
        case 0.5:
            if ultraWideCamera != nil {
                switchToCamera(.ultraWide)
            }
        case 1.0:
            switchToCamera(.wide)
        case 2.0:
            if macroCamera != nil {
                switchToCamera(.macro)
            }
        default:
            // Use current camera with zoom
            break
        }
        
        currentZoom = selectedZoom
        updateZoomButtonTitle()
        
        // Apply zoom
        applyZoom(selectedZoom)
    }
    
    private func updateZoomButtonTitle() {
        let zoomText = zoomLevels[currentZoomIndex] == 1.0 ? "1x" : "\(Int(zoomLevels[currentZoomIndex]))x"
        zoomButton.setTitle(zoomText, for: .normal)
    }
    
    private func applyZoom(_ zoom: CGFloat) {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            // Clamp zoom to device's supported range
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = device.maxAvailableVideoZoomFactor
            let clampedZoom = max(minZoom, min(zoom, maxZoom))
            
            device.videoZoomFactor = clampedZoom
            currentZoom = clampedZoom
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error)")
        }
    }
    
    
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }
        
        switch gesture.state {
        case .began:
            // Store initial zoom for pinch calculation
            break
        case .changed:
            let zoomFactor = currentZoom * gesture.scale
            let clampedZoom = max(0.5, min(zoomFactor, 5.0))
            
            currentZoom = clampedZoom
            applyZoom(clampedZoom)
            
            // Update zoom button to show current zoom level
            let closestIndex = findClosestZoomIndex(for: clampedZoom)
            if closestIndex != currentZoomIndex {
                currentZoomIndex = closestIndex
                updateZoomButtonTitle()
            }
        default:
            break
        }
    }
    
    private func findClosestZoomIndex(for zoom: CGFloat) -> Int {
        var closestIndex = 0
        var minDifference = abs(zoomLevels[0] - zoom)
        
        for (index, level) in zoomLevels.enumerated() {
            let difference = abs(level - zoom)
            if difference < minDifference {
                minDifference = difference
                closestIndex = index
            }
        }
        
        return closestIndex
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        let tapPoint = gesture.location(in: view)
        let focusPoint = CGPoint(x: tapPoint.x / view.bounds.width, y: tapPoint.y / view.bounds.height)
        
        focus(at: focusPoint)
    }
    
    private func focus(at point: CGPoint) {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            
            // Show focus indicator
            showFocusIndicator(at: point)
            
        } catch {
            print("Error setting focus: \(error)")
        }
    }
    
    private func showFocusIndicator(at point: CGPoint) {
        focusIndicator.center = point
        focusIndicator.isHidden = false
        focusIndicator.alpha = 1.0
        
        UIView.animate(withDuration: 0.3, animations: {
            self.focusIndicator.alpha = 0.0
        }) { _ in
            self.focusIndicator.isHidden = true
        }
    }
    
    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        
        // Configure flash
        if isFlashOn {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        
        // ✅ FIX: Store current device orientation for later use
        captureDeviceOrientation = UIDevice.current.orientation
        
        // Set photo orientation based on device orientation
        if let connection = photoOutput.connection(with: .video) {
            let deviceOrientation = UIDevice.current.orientation
            
            switch deviceOrientation {
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                connection.videoOrientation = .portrait
            }
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else {
            print("Error capturing photo - no data")
            return
        }
        
        // ✅ FIX: Create CGImage from data first
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            print("Error creating CGImage")
            return
        }
        
        // ✅ FIX: Determine correct UIImage.Orientation based on device orientation at capture time
        // This ensures landscape photos are created with landscape orientation
        let imageOrientation: UIImage.Orientation
        switch captureDeviceOrientation {
        case .landscapeLeft:
            // Device tilted left -> image should be oriented right
            imageOrientation = .right
        case .landscapeRight:
            // Device tilted right -> image should be oriented left
            imageOrientation = .left
        case .portraitUpsideDown:
            imageOrientation = .down
        default:
            // Portrait or unknown
            imageOrientation = .up
        }
        
        // ✅ FIX: Create UIImage with correct orientation metadata
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
        
        // ✅ FIX: Normalize orientation - bakes orientation into pixel data
        // This ensures orientation is preserved after upload/download
        let normalizedImage = image.normalizeOrientation()
        
        delegate?.didCaptureImage(normalizedImage)
    }
}

// MARK: - UIImage Extension for Orientation Fix
extension UIImage {
    /// Normalizes image orientation by redrawing it
    /// This ensures the orientation metadata is "baked" into the pixel data
    /// Prevents landscape photos from appearing as portrait after upload
    func normalizeOrientation() -> UIImage {
        // If already up orientation, no need to redraw
        if imageOrientation == .up {
            return self
        }
        
        // Create a new image context and redraw the image
        // This applies the orientation transform to the actual pixel data
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}
