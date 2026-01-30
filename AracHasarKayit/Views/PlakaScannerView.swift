import SwiftUI
import Vision
import AVFoundation
import PhotosUI

struct PlakaScannerView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Binding var isActive: Bool  // YENÄ°: Tab aktif mi kontrol iÃ§in
    @Binding var selectedTab: Int
    @Binding var navigateToVehicleId: UUID?
    @State private var tarananPlaka: String = ""
    @State private var taramaAktif = false  // YENÄ°: false olarak baÅŸlÄ±yor
    @State private var bulunanArac: Arac?
    @State private var yeniAracMi = false
    @State private var alertGoster = false
    @State private var alertMesaj = ""
    @State private var kameraIzniYok = false
    @State private var fotografCek = false
    @State private var fotografSec = false
    @State private var secilenFotograf: UIImage?
    @State private var fotografIsliyor = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            if kameraIzniYok {
                // Kamera izni yoksa
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill.badge.ellipsis")
                        .font(.system(size: 80))
                        .foregroundColor(.red.opacity(0.5))
                    
                    Text("Kamera İzni Gerekli".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Plaka taramak için kamera iznine ihtiyaç var. Lütfen Ayarlar'dan kamera iznini açın.".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Ayarları Aç".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding()
            } else {
                // Plaka Scanner
                PlakaScannerRepresentable(
                    taramaAktif: $taramaAktif,
                    tarananPlaka: $tarananPlaka,
                    kameraIzniYok: $kameraIzniYok
                )
                .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    
                    // Bilgi kartÄ±
                    VStack(spacing: 16) {
                        if fotografIsliyor {
                            ProgressView()
                                .tint(.green)
                                .scaleEffect(1.5)
                            Text("Plaka Okunuyor...".localized)
                                .font(.headline)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Plaka Tara".localized)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("İsviçre plakasını kamera ile okutun".localized)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Example format
                            VStack(spacing: 4) {
                                Text("Geçerli format örnekleri:".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(["ZH 123456", "ZG 98765", "BS 555"], id: \.self) { ornek in
                                        Text(ornek)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            
                            if !tarananPlaka.isEmpty {
                                VStack(spacing: 8) {
                                    Text("Taranan plaka:".localized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(tarananPlaka)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            
                            // Buttons
                            HStack(spacing: 16) {
                                // Camera button
                                Button {
                                                                        fotografCek = true
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.title2)
                                        Text("Fotoğraf Çek".localized)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                                }
                                
                                // Gallery button
                                Button {
                                                                        fotografSec = true
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.fill")
                                            .font(.title2)
                                        Text("Galeriden Seç".localized)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding()
                }
            }
        }
        .onDisappear {
                        }
        .onChange(of: tarananPlaka) { newValue in
            plakaTarandi(newValue)
        }
        .onChange(of: secilenFotograf) { image in
            if let image = image {
                fotografIsliyor = true
                fotograftanPlakaOku(image: image)
            }
        }
        .sheet(item: $bulunanArac) { arac in
            NavigationView {
                if yeniAracMi {
                    YeniAracFormView(arac: arac) { savedArac in
                        // After saving new vehicle, switch to vehicles tab first
                        selectedTab = 1
                        // Wait for tab switch, then navigate to detail
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigateToVehicleId = savedArac.id
                        }
                    }
                } else {
                    AracDetayView(arac: arac)
                }
            }
        }
        .sheet(isPresented: $fotografCek) {
            CameraPicker(selectedImage: $secilenFotograf)
        }
        .sheet(isPresented: $fotografSec) {
            SingleImagePicker(selectedImage: $secilenFotograf)
        }
        .alert("Warning".localized, isPresented: $alertGoster) {
            Button("OK".localized, role: .cancel) { }
        } message: {
            Text(alertMesaj)
        }
        .onAppear {
                        // ✅ GÜNCEL: İlk açılışta izin iste ve taramayı güvenli başlat
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.kameraIzniYok = !granted
                    guard granted else { return }
                    // Tab aktifliği geldiyse veya gelmeden önce de taramayı aç
                    self.taramaAktif = self.isActive || true
                }
            }
        }
        .onChange(of: isActive) { newValue in
            // Tab deÄŸiÅŸtiÄŸinde kamera durumunu gÃ¼ncelle
            if newValue && bulunanArac == nil {
                taramaAktif = true
            } else {
                taramaAktif = false
            }
            if !newValue {
                tarananPlaka = "" // Clear plate info when leaving tab
            }
        }
        .onChange(of: bulunanArac) { newValue in
            // When sheet is dismissed (only used for new vehicles now)
            if newValue == nil && isActive {
                // Resume scanning after sheet dismissal
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    taramaAktif = true
                    tarananPlaka = ""
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            // ✅ GÜNCEL: Ön/arka plan durumuna göre oturumu yönet
            switch phase {
            case .active:
                if isActive && !kameraIzniYok {
                    taramaAktif = true
                }
            default:
                taramaAktif = false
            }
        }
    }
    
    func plakaTarandi(_ plaka: String) {
        guard !plaka.isEmpty else { return }
        
        // Stop scanning immediately
        taramaAktif = false
        HapticManager.shared.scanSuccess()
        
        if let arac = viewModel.aracBulPlaka(plaka: plaka) {
            yeniAracMi = !viewModel.araclar.contains(where: {
                $0.plaka.replacingOccurrences(of: " ", with: "").uppercased() ==
                arac.plaka.replacingOccurrences(of: " ", with: "").uppercased()
            })
            
            // Show success toast
            ToastManager.shared.show(String(format: "Plate Scanned: %@".localized, plaka), type: .success)
            
                if yeniAracMi {
                    // New vehicle - show form to enter details
                    bulunanArac = arac
                } else {
                    // Existing vehicle - navigate directly to vehicle detail
                    // Switch to Vehicles tab first
                    selectedTab = 1
                    // Wait for tab switch animation, then navigate to detail
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        navigateToVehicleId = arac.id
                    }
                }
        } else {
            alertMesaj = """
            Invalid Plate Format
            
            Scanned plate: \(plaka)
            
            Please scan in valid Swiss plate format.
            
            Example: ZH 123456, ZG 98765, BS 555
            """
            alertGoster = true
            
            // Resume scanning after error alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if isActive && bulunanArac == nil {
                    taramaAktif = true
                }
                tarananPlaka = ""
            }
        }
    }
    
    func fotograftanPlakaOku(image: UIImage) {
        // Optimize image
        guard let optimizedImage = preprocessImage(image) else {
            fotografIsliyor = false
            alertMesaj = "Photo could not be processed. Please try again.".localized
            alertGoster = true
            return
        }
        
        guard let cgImage = optimizedImage.cgImage else {
            fotografIsliyor = false
            return
        }
        
        // Try multiple recognition levels
        let recognitionLevels: [VNRequestTextRecognitionLevel] = [.accurate, .fast]
        var allCandidates: [String] = []
        
        let group = DispatchGroup()
        
        for level in recognitionLevels {
            group.enter()
            
            let request = VNRecognizeTextRequest { request, error in
                defer { group.leave() }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                
                // Collect all candidates (not just first one)
                for observation in observations {
                    let candidates = observation.topCandidates(5) // Top 5 candidates
                    for candidate in candidates {
                        let text = candidate.string.uppercased()
                        allCandidates.append(text)
                    }
                }
            }
            
            request.recognitionLevel = level
            request.recognitionLanguages = ["en"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.0
            request.customWords = ["ZH", "ZG", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR", "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG", "TI", "VD", "VS", "NE", "GE", "JU"]
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? requestHandler.perform([request])
            }
        }
        
        group.notify(queue: .main) {
            self.fotografIsliyor = false
            
            // Analyze all candidates
            let bulunanPlaka = self.findBestPlateCandidate(from: allCandidates)
            
            if let plaka = bulunanPlaka {
                self.tarananPlaka = plaka
                self.plakaTarandi(plaka)
            } else {
                var debugInfo = "Found texts:\n"
                for (index, text) in allCandidates.prefix(10).enumerated() {
                    debugInfo += "\(index + 1). \(text)\n"
                }
                
                self.alertMesaj = "Could not find a valid Swiss plate in the photo.\n\nTips:\n• Take a clear photo\n• Good lighting\n• Plate should fit in frame\n\n\(debugInfo)"
                self.alertGoster = true
            }
        }
    }
    
    func preprocessImage(_ image: UIImage) -> UIImage? {
        guard let inputImage = CIImage(image: image) else { return nil }
        
        // Increase contrast and brightness
        let parameters: [String: Any] = [
            kCIInputImageKey: inputImage,
            kCIInputContrastKey: 1.5,
            kCIInputBrightnessKey: 0.1
        ]
        
        guard let filter = CIFilter(name: "CIColorControls", parameters: parameters),
              let outputImage = filter.outputImage else {
            return image
        }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func findBestPlateCandidate(from candidates: [String]) -> String? {
        // Check all possible plate combinations
        for candidate in candidates {
            // Clean spaces and convert to uppercase
            let cleaned = candidate.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
                .uppercased()
            
            // Direct exact match
            if isValidSwissPlate(cleaned) {
                return cleaned
            }
            
            // Try O/0, I/1, S/5 variations that can be confused
            let variations = generateVariations(cleaned)
            for variation in variations {
                if isValidSwissPlate(variation) {
                    return variation
                }
            }
            
            // Search for plate in text
            if let extracted = extractPlateFromText(cleaned) {
                return extracted
            }
        }
        
        return nil
    }
    
    func generateVariations(_ text: String) -> [String] {
        var variations: [String] = [text]
        
        // Variations for common OCR errors
        let replacements: [(String, String)] = [
            ("O", "0"), ("0", "O"),
            ("I", "1"), ("1", "I"),
            ("S", "5"), ("5", "S"),
            ("Z", "2"), ("2", "Z"),
            ("B", "8"), ("8", "B")
        ]
        
        for (from, to) in replacements {
            if text.contains(from) {
                variations.append(text.replacingOccurrences(of: from, with: to))
            }
        }
        
        return variations
    }
    
    func extractPlateFromText(_ text: String) -> String? {
        // Search for plate pattern in text
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
        // Ä°sviÃ§re kantonu kodlarÄ±
        let validCantons = ["ZH", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR", "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG", "TI", "VD", "VS", "NE", "GE", "JU"]
        
        // Minimum 3 karakter (2 harf + 1 rakam)
        guard text.count >= 3 && text.count <= 8 else { return false }
        
        // Ä°lk 2 karakter geÃ§erli bir kanton kodu mu?
        let canton = String(text.prefix(2))
        guard validCantons.contains(canton) else { return false }
        
        // Geri kalanlar sadece rakam olmalÄ±
        let numbers = String(text.dropFirst(2))
        guard numbers.allSatisfy({ $0.isNumber }) else { return false }
        
        // En az 1 rakam olmalÄ±
        guard !numbers.isEmpty else { return false }
        
        return true
    }
}
