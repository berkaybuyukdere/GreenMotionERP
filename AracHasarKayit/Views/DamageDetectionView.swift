import SwiftUI
import AVFoundation
import CoreImage
import Photos

struct DamageDetectionView: View {
    @State private var showCamera = true
    @State private var capturedImage: UIImage?
    @State private var selectedFilter: DamageFilter = .none
    @State private var isProcessing = false
    @Environment(\.dismiss) var dismiss
    
    enum DamageFilter: String, CaseIterable {
        case none = "Normal"
        case highContrast = "High Contrast"
        case edgeDetection = "Edge Detection"
        case grayscale = "Black & White"
        case infrared = "Infrared"
        case uv = "UV Detection"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
    var body: some View {
        ZStack {
            if showCamera {
                DamageDetectionCameraView(
                    selectedFilter: $selectedFilter,
                    capturedImage: $capturedImage,
                    onDismiss: {
                        if capturedImage == nil {
                            // User cancelled, exit completely
                            dismiss()
                        } else {
                            // Photo was taken, show preview
                            showCamera = false
                        }
                    }
                )
                .ignoresSafeArea()
            } else {
                if let image = capturedImage {
                    ImagePreviewWithFilters(
                        image: image,
                        selectedFilter: $selectedFilter,
                        onRetake: {
                            capturedImage = nil
                            showCamera = true
                        },
                        onClose: {
                            dismiss()
                        }
                    )
                }
            }
        }
        .onAppear {
            showCamera = true
        }
    }
}

struct ImagePreviewWithFilters: View {
    let image: UIImage
    @Binding var selectedFilter: DamageDetectionView.DamageFilter
    let onRetake: () -> Void
    let onClose: () -> Void
    @State private var filteredImage: UIImage?
    @State private var showSaveSuccess = false
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filtered Image Display
                if let filteredImage = filteredImage {
                    Image(uiImage: filteredImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Filter Selection
                VStack(spacing: 16) {
                    Text("Select Filter")
                        .font(.headline)
                        .padding(.top)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(DamageDetectionView.DamageFilter.allCases, id: \.self) { filter in
                                FilterButton(
                                    filter: filter,
                                    isSelected: selectedFilter == filter,
                                    action: {
                                        selectedFilter = filter
                                        applyFilter()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    HStack(spacing: 20) {
                        Button("Retake") {
                            onRetake()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Save to Phone") {
                            saveToPhotoLibrary()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Damage Detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onClose()
                    }
                }
            }
            .alert("Saved", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Photo has been saved to your photo library.")
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: [filteredImage ?? image])
            }
        }
        .onAppear {
            applyFilter()
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            applyFilter()
        }
    }
    
    private func applyFilter() {
        filteredImage = DamageFilterProcessor.applyFilter(to: image, filter: selectedFilter)
    }
    
    private func saveToPhotoLibrary() {
        let imageToSave = filteredImage ?? image
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    // Show error or open settings
                    print("Photo library access denied")
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: imageToSave)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        showSaveSuccess = true
                    } else if let error = error {
                        print("Error saving photo: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

struct FilterButton: View {
    let filter: DamageDetectionView.DamageFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: filterIcon(for: filter))
                    .font(.title2)
                Text(filter.displayName)
                    .font(.caption)
            }
            .padding()
            .frame(width: 100)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
        }
    }
    
    private func filterIcon(for filter: DamageDetectionView.DamageFilter) -> String {
        switch filter {
        case .none: return "camera.fill"
        case .highContrast: return "sun.max.fill"
        case .edgeDetection: return "square.stack.3d.up.fill"
        case .grayscale: return "circle.lefthalf.filled"
        case .infrared: return "flame.fill"
        case .uv: return "sparkles"
        }
    }
}

// MARK: - Camera View with Live Filters
struct DamageDetectionCameraView: UIViewControllerRepresentable {
    @Binding var selectedFilter: DamageDetectionView.DamageFilter
    @Binding var capturedImage: UIImage?
    var onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> DamageDetectionCameraViewController {
        let controller = DamageDetectionCameraViewController()
        controller.delegate = context.coordinator
        controller.selectedFilter = selectedFilter
        return controller
    }
    
    func updateUIViewController(_ uiViewController: DamageDetectionCameraViewController, context: Context) {
        uiViewController.selectedFilter = selectedFilter
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, DamageDetectionCameraDelegate {
        let parent: DamageDetectionCameraView
        
        init(_ parent: DamageDetectionCameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.capturedImage = image
            parent.onDismiss()
        }
        
        func didCancel() {
            parent.onDismiss()
        }
    }
}

protocol DamageDetectionCameraDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didCancel()
}

class DamageDetectionCameraViewController: UIViewController {
    weak var delegate: DamageDetectionCameraDelegate?
    var selectedFilter: DamageDetectionView.DamageFilter = .none {
        didSet {
            updateFilter()
        }
    }
    
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var photoOutput: AVCapturePhotoOutput!
    private var filteredPreviewLayer: CALayer!
    private var captureButton: UIButton!
    private var cancelButton: UIButton!
    private var filterButton: UIButton!
    private var filterSelectionView: UIView!
    private var filterStackView: UIStackView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
        updateVideoOrientation()
        
        // Listen for device orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        filteredPreviewLayer?.frame = view.bounds
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Unable to access back camera")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // Video output for live filter preview
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Set video orientation for video output connection
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = getVideoOrientation()
            }
            
            // Photo output for capture
            photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.connection?.videoOrientation = getVideoOrientation()
            view.layer.addSublayer(previewLayer)
            
            // Filtered preview layer for live filter display
            filteredPreviewLayer = CALayer()
            filteredPreviewLayer.frame = view.bounds
            filteredPreviewLayer.contentsGravity = .resizeAspectFill
            filteredPreviewLayer.isHidden = true // Initially hidden, shown when filter is applied
            view.layer.addSublayer(filteredPreviewLayer)
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        // Filter selection button
        filterButton = UIButton(type: .system)
        filterButton.setTitle("Filters", for: .normal)
        filterButton.setTitleColor(.white, for: .normal)
        filterButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        filterButton.addTarget(self, action: #selector(showFilterSelection), for: .touchUpInside)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterButton)
        
        // Filter selection view
        filterSelectionView = UIView()
        filterSelectionView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        filterSelectionView.isHidden = true
        filterSelectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterSelectionView)
        
        filterStackView = UIStackView()
        filterStackView.axis = .horizontal
        filterStackView.distribution = .fillEqually
        filterStackView.spacing = 12
        filterStackView.translatesAutoresizingMaskIntoConstraints = false
        filterSelectionView.addSubview(filterStackView)
        
        // Create filter buttons
        for (index, filter) in DamageDetectionView.DamageFilter.allCases.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(filter.displayName, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            button.backgroundColor = selectedFilter == filter ? .systemBlue : .darkGray
            button.layer.cornerRadius = 8
            button.tag = index
            button.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            filterStackView.addArrangedSubview(button)
        }
        
        // Capture button
        captureButton = UIButton(type: .system)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.lightGray.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureButton)
        
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            filterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            filterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            filterSelectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterSelectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterSelectionView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            filterSelectionView.heightAnchor.constraint(equalToConstant: 80),
            
            filterStackView.leadingAnchor.constraint(equalTo: filterSelectionView.leadingAnchor, constant: 20),
            filterStackView.trailingAnchor.constraint(equalTo: filterSelectionView.trailingAnchor, constant: -20),
            filterStackView.centerYAnchor.constraint(equalTo: filterSelectionView.centerYAnchor),
            
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    @objc private func cancelTapped() {
        delegate?.didCancel()
    }
    
    @objc private func showFilterSelection() {
        filterSelectionView.isHidden.toggle()
    }
    
    @objc private func filterTapped(_ sender: UIButton) {
        let index = sender.tag
        if index < DamageDetectionView.DamageFilter.allCases.count {
            selectedFilter = DamageDetectionView.DamageFilter.allCases[index]
            updateFilterButtons()
            filterSelectionView.isHidden = true
        }
    }
    
    private func updateFilterButtons() {
        for (index, button) in filterStackView.arrangedSubviews.enumerated() {
            if let btn = button as? UIButton {
                let filter = DamageDetectionView.DamageFilter.allCases[index]
                btn.backgroundColor = selectedFilter == filter ? .systemBlue : .darkGray
            }
        }
    }
    
    private func updateFilter() {
        // Filter will be applied in video output delegate
    }
    
    private func getVideoOrientation() -> AVCaptureVideoOrientation {
        let deviceOrientation = UIDevice.current.orientation
        let statusBarOrientation = UIApplication.shared.statusBarOrientation
        
        // Use device orientation if valid, otherwise use status bar orientation
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            // Fallback to status bar orientation
            switch statusBarOrientation {
            case .portrait:
                return .portrait
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                return .portrait
            }
        }
    }
    
    @objc private func deviceOrientationDidChange() {
        updateVideoOrientation()
    }
    
    private func updateVideoOrientation() {
        let orientation = getVideoOrientation()
        
        // Update preview layer orientation
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        
        // Update video output connection orientation
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        
        // Update photo output connection orientation
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }
    
    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func startSession() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    private func stopSession() {
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.stopRunning()
            }
        }
    }
}

extension DamageDetectionCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process if filter is not "none" for performance
        guard selectedFilter != .none else {
            DispatchQueue.main.async {
                self.previewLayer.isHidden = false
                self.filteredPreviewLayer.isHidden = true
            }
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create CIImage - orientation is handled by connection.videoOrientation
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let filteredImage = DamageFilterProcessor.applyFilter(to: ciImage, filter: selectedFilter)
        
        // Use hardware-accelerated rendering for better performance
        let context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
        
        // Get the extent from the filtered image
        let extent = filteredImage.extent
        guard let cgImage = context.createCGImage(filteredImage, from: extent) else { return }
        
        DispatchQueue.main.async {
            // Update filtered preview layer
            CATransaction.begin()
            CATransaction.setDisableActions(true) // Disable animations for smooth video
            self.filteredPreviewLayer.contents = cgImage
            self.previewLayer.isHidden = true
            self.filteredPreviewLayer.isHidden = false
            CATransaction.commit()
        }
    }
    
}

extension DamageDetectionCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        // Apply selected filter to captured image
        if let filteredImage = DamageFilterProcessor.applyFilter(to: image, filter: selectedFilter) {
            delegate?.didCaptureImage(filteredImage)
        } else {
            delegate?.didCaptureImage(image)
        }
    }
}

// MARK: - Filter Processor
class DamageFilterProcessor {
    static func applyFilter(to image: UIImage, filter: DamageDetectionView.DamageFilter) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        let filteredCIImage = applyFilter(to: ciImage, filter: filter)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(filteredCIImage, from: filteredCIImage.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }
    
    static func applyFilter(to ciImage: CIImage, filter: DamageDetectionView.DamageFilter) -> CIImage {
        switch filter {
        case .none:
            return ciImage
            
        case .highContrast:
            // High contrast filter for damage detection - enhances scratches and dents
            // Increases contrast significantly to make damage more visible
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return ciImage }
            contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.5, forKey: kCIInputContrastKey) // High contrast
            contrastFilter.setValue(0.1, forKey: kCIInputBrightnessKey) // Slight brightness increase
            contrastFilter.setValue(1.2, forKey: kCIInputSaturationKey) // Slight saturation increase
            let result = contrastFilter.outputImage ?? ciImage
            
            // Add unsharp mask for edge enhancement
            guard let unsharpFilter = CIFilter(name: "CIUnsharpMask") else { return result }
            unsharpFilter.setValue(result, forKey: kCIInputImageKey)
            unsharpFilter.setValue(0.5, forKey: kCIInputIntensityKey) // Intensity
            unsharpFilter.setValue(1.0, forKey: kCIInputRadiusKey) // Radius
            return unsharpFilter.outputImage ?? result
            
        case .edgeDetection:
            // Edge detection filter - highlights scratches, cracks, and dents
            // First convert to grayscale for better edge detection
            guard let grayFilter = CIFilter(name: "CIColorMonochrome") else { return ciImage }
            grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
            grayFilter.setValue(CIColor.gray, forKey: kCIInputColorKey)
            grayFilter.setValue(1.0, forKey: kCIInputIntensityKey)
            let grayImage = grayFilter.outputImage ?? ciImage
            
            // Apply edge detection
            guard let edgeFilter = CIFilter(name: "CIEdges") else { return grayImage }
            edgeFilter.setValue(grayImage, forKey: kCIInputImageKey)
            edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey) // Edge intensity
            let edgeResult = edgeFilter.outputImage ?? grayImage
            
            // Invert to show edges as dark lines (better for damage visibility)
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return edgeResult }
            invertFilter.setValue(edgeResult, forKey: kCIInputImageKey)
            return invertFilter.outputImage ?? edgeResult
            
        case .grayscale:
            // High contrast grayscale for damage visibility
            guard let monoFilter = CIFilter(name: "CIColorMonochrome") else { return ciImage }
            monoFilter.setValue(ciImage, forKey: kCIInputImageKey)
            monoFilter.setValue(CIColor.gray, forKey: kCIInputColorKey)
            monoFilter.setValue(1.0, forKey: kCIInputIntensityKey)
            let grayResult = monoFilter.outputImage ?? ciImage
            
            // Enhance contrast in grayscale
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return grayResult }
            contrastFilter.setValue(grayResult, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.3, forKey: kCIInputContrastKey)
            return contrastFilter.outputImage ?? grayResult
            
        case .infrared:
            // Infrared-like filter - enhances red/orange tones (rust, heat damage)
            // Optimized for car damage detection
            guard let colorFilter = CIFilter(name: "CIColorMatrix") else { return ciImage }
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            // Enhance red channel significantly (2.5x) for rust and heat damage
            colorFilter.setValue(CIVector(x: 2.5, y: 0, z: 0, w: 0), forKey: "inputRVector")
            // Reduce green channel (0.4x)
            colorFilter.setValue(CIVector(x: 0, y: 0.4, z: 0, w: 0), forKey: "inputGVector")
            // Reduce blue channel (0.3x)
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0.3, w: 0), forKey: "inputBVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            let infraredResult = colorFilter.outputImage ?? ciImage
            
            // Add contrast for better visibility
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return infraredResult }
            contrastFilter.setValue(infraredResult, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.2, forKey: kCIInputContrastKey)
            return contrastFilter.outputImage ?? infraredResult
            
        case .uv:
            // UV-like filter - enhances blue/purple tones (paint damage, scratches)
            // Optimized for detecting paint scratches and surface imperfections
            guard let colorFilter = CIFilter(name: "CIColorMatrix") else { return ciImage }
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            // Reduce red channel (0.6x)
            colorFilter.setValue(CIVector(x: 0.6, y: 0, z: 0, w: 0), forKey: "inputRVector")
            // Enhance green channel (1.3x)
            colorFilter.setValue(CIVector(x: 0, y: 1.3, z: 0, w: 0), forKey: "inputGVector")
            // Enhance blue channel significantly (2.0x) for UV detection
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 2.0, w: 0), forKey: "inputBVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            let uvResult = colorFilter.outputImage ?? ciImage
            
            // Add high contrast and brightness for scratch visibility
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return uvResult }
            contrastFilter.setValue(uvResult, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.4, forKey: kCIInputContrastKey) // High contrast
            contrastFilter.setValue(0.15, forKey: kCIInputBrightnessKey) // Slight brightness
            return contrastFilter.outputImage ?? uvResult
        }
    }
}

