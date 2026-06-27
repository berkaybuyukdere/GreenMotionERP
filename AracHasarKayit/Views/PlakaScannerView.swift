import SwiftUI
import Vision
import AVFoundation
import PhotosUI

extension Notification.Name {
    static let openVehicleDetailFromScan = Notification.Name("openVehicleDetailFromScan")
}

struct PlakaScannerView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
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
    @State private var germanyPipelineScanning = false
    @State private var fotografCek = false
    @State private var fotografSec = false
    @State private var secilenFotograf: UIImage?
    @State private var fotografIsliyor = false
    @State private var wheelsysReturnSheet: WheelSysIadeReturnContext?
    @State private var wheelsysReturnPickerCandidates: [WheelSysReturnCandidate]?
    @State private var showWheelSysReturnPicker = false
    @State private var wheelsysPlateLookupBusy = false
    @State private var cameraZoomFactor: CGFloat = 1.0
    @Environment(\.scenePhase) private var scenePhase

    private var isWheelSysCHScan: Bool {
        wheelsysReturnScanEnabled
    }
    
    private var activeCountry: Country {
        SessionCountryResolver.activeCountry(userProfile: authManager.userProfile)
    }
    
    private var activeCountryId: String {
        activeCountry.id
    }
    
    private var activeExamples: [String] {
        CountryManager.plateExamples(for: activeCountryId)
    }

  private var sessionFranchiseId: String {
        FirebaseService.shared.currentFranchiseId
    }

    private var wheelsysReturnScanEnabled: Bool {
        guard let profile = authManager.userProfile else { return false }
        return FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: sessionFranchiseId,
            userProfile: profile
        ) && FranchiseCapabilityMatrix.chOpsJournalTabEnabledForSession(
            serviceFranchiseId: sessionFranchiseId,
            userProfile: profile,
            fallbackCountryCode: activeCountryId.uppercased()
        )
    }
    
    var body: some View {
        ZStack {
            if kameraIzniYok {
                permissionDeniedView
            } else {
                cameraLayer
                scanOverlayChrome
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
                taramaAktif = false
                fotograftanPlakaOku(image: image)
            }
        }
        .sheet(item: $bulunanArac) { arac in
            NavigationView {
                if yeniAracMi {
                    YeniAracFormView(arac: arac) { savedArac in
                        selectedTab = 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigateToVehicleId = savedArac.id
                        }
                    }
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
                } else {
                    AracDetayView(arac: arac, scannedEntry: true)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $fotografCek) {
            CameraPicker(selectedImage: $secilenFotograf)
        }
        .sheet(isPresented: $fotografSec) {
            SingleImagePicker(selectedImage: $secilenFotograf)
        }
        .sheet(isPresented: $showWheelSysReturnPicker) {
            if let candidates = wheelsysReturnPickerCandidates {
                WheelSysReturnCandidatePickerSheet(candidates: candidates) { selected in
                    openScannedReturn(candidate: selected)
                }
            }
        }
        .sheet(item: $wheelsysReturnSheet) { context in
            NavigationStack {
                IadeIslemView(
                    arac: context.arac,
                    wheelSysReturnPrefill: context.prefill
                ) { _ in
                    tarananPlaka = ""
                    if isActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            taramaAktif = true
                        }
                    }
                }
                .environmentObject(viewModel)
                .environmentObject(authManager)
            }
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
                    self.taramaAktif = self.isActive
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
                germanyPipelineScanning = false
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
                germanyPipelineScanning = false
            }
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 80))
                .foregroundStyle(PalantirTheme.critical.opacity(0.6))
            Text("Kamera İzni Gerekli".localized)
                .font(PalantirTheme.heroFont(20))
                .foregroundStyle(PalantirTheme.textPrimary)
            Text("Plaka taramak için kamera iznine ihtiyaç var. Lütfen Ayarlar'dan kamera iznini açın.".localized)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            WheelSysPalantirPrimaryButton(title: "Ayarları Aç".localized, icon: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PalantirTheme.background)
    }

    private var cameraLayer: some View {
        ZStack {
            PlakaScannerRepresentable(
                taramaAktif: $taramaAktif,
                tarananPlaka: $tarananPlaka,
                kameraIzniYok: $kameraIzniYok,
                countryId: activeCountryId,
                germanyScanning: $germanyPipelineScanning,
                zoomFactor: $cameraZoomFactor,
                onZoomFactorChanged: { cameraZoomFactor = $0 }
            )
            .ignoresSafeArea()

            if activeCountryId == "de" {
                DEPlateScannerOverlay(
                    isScanning: germanyPipelineScanning,
                    detectedPlate: tarananPlaka
                )
                .ignoresSafeArea()
            } else {
                PlateScannerFrameOverlay()
                    .ignoresSafeArea()
            }
        }
    }

    private var scanOverlayChrome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            scanInfoPanel
        }
        .safeAreaPadding(.horizontal, 16)
        .padding(.bottom, 72)
    }

    private var scanInfoPanel: some View {
        VStack(spacing: 12) {
            if fotografIsliyor {
                ProgressView().tint(PalantirTheme.accent).scaleEffect(1.3)
                Text("Plaka Okunuyor...".localized)
                    .font(PalantirTheme.labelFont(12))
                    .foregroundStyle(PalantirTheme.accent)
            } else {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                Text("Plaka Tara".localized)
                    .font(PalantirTheme.heroFont(18))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text(String(format: "Scan plate with camera for %@".localized, activeCountry.name))
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(activeExamples, id: \.self) { ornek in
                        PalantirOpsBadge(text: ornek, tone: .accent)
                    }
                }
                if !tarananPlaka.isEmpty {
                    PalantirOpsBadge(text: tarananPlaka, tone: .success)
                }
                HStack(spacing: 12) {
                    WheelSysPalantirSecondaryButton(
                        title: "Fotoğraf Çek".localized,
                        icon: "camera.fill",
                        compact: true,
                        disabled: !isActive || fotografIsliyor
                    ) {
                        guard isActive, !fotografIsliyor else { return }
                        fotografCek = true
                    }
                    .frame(maxWidth: .infinity)
                    WheelSysPalantirSecondaryButton(
                        title: "Galeriden Seç".localized,
                        icon: "photo.fill",
                        tint: PalantirTheme.success,
                        compact: true,
                        disabled: !isActive || fotografIsliyor
                    ) {
                        guard isActive, !fotografIsliyor else { return }
                        fotografSec = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    func plakaTarandi(_ plaka: String) {
        guard !plaka.isEmpty else { return }

        taramaAktif = false
        HapticManager.shared.scanSuccess()

        if let arac = viewModel.findAracByPlate(plaka) {
            ToastManager.shared.show(String(format: "Plate Scanned: %@".localized, plaka), type: .success)
            navigateToFleetVehicle(arac)
            return
        }

        if wheelsysReturnScanEnabled {
            Task { await handleWheelSysPlateScan(plaka) }
            return
        }

        if let arac = viewModel.aracBulPlaka(plaka: plaka) {
            yeniAracMi = !viewModel.araclar.contains(where: { $0.id == arac.id })
            ToastManager.shared.show(String(format: "Plate Scanned: %@".localized, plaka), type: .success)
            if yeniAracMi {
                bulunanArac = arac
            } else {
                navigateToFleetVehicle(arac)
            }
            return
        }

        let examplesText = activeExamples.joined(separator: ", ")
        alertMesaj = String(
            format: "Invalid plate format for %@.\n\nScanned plate: %@\n\nExamples: %@".localized,
            activeCountry.name,
            plaka,
            examplesText
        )
        alertGoster = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if isActive && bulunanArac == nil {
                taramaAktif = true
            }
            tarananPlaka = ""
        }
    }

    private func resumeScanningSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard isActive, bulunanArac == nil else { return }
            wheelsysPlateLookupBusy = false
            taramaAktif = true
            tarananPlaka = ""
        }
    }

    private func navigateToFleetVehicle(_ arac: Arac) {
        yeniAracMi = false
        bulunanArac = nil
        selectedTab = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            navigateToVehicleId = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigateToVehicleId = arac.id
            NotificationCenter.default.post(
                name: .openVehicleDetailFromScan,
                object: nil,
                userInfo: [
                    "vehicleId": arac.id.uuidString,
                    "plate": arac.plakaFormatli
                ]
            )
        }
    }

    @MainActor
    private func handleWheelSysPlateScan(_ plaka: String) async {
        guard !wheelsysPlateLookupBusy else { return }

        if let arac = viewModel.findAracByPlate(plaka) {
            ToastManager.shared.show(String(format: "Plate Scanned: %@".localized, plaka), type: .success)
            navigateToFleetVehicle(arac)
            return
        }

        wheelsysPlateLookupBusy = true
        defer { wheelsysPlateLookupBusy = false }

        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()

        let franchiseId = sessionFranchiseId.uppercased()
        guard !franchiseId.isEmpty,
              FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
                  serviceFranchiseId: franchiseId,
                  userProfile: authManager.userProfile
              ) else {
            resumeScanningSoon()
            return
        }
        let selectedDate = WheelSysJournalService.formatZurichDay(WheelSysJournalService.todayZurich())

        let fleetArac = viewModel.findAracByPlate(plaka)

        let candidates = await WheelSysPlateScannerService.findActiveRentalsForPlate(
            plate: plaka,
            franchiseId: franchiseId,
            selectedDate: selectedDate
        )

        if let arac = fleetArac {
            HapticManager.shared.success()
            ToastManager.shared.show(
                String(format: "Plate Scanned: %@".localized, plaka),
                type: .success
            )
            if !candidates.isEmpty {
                ToastManager.shared.show(
                    "wheelsys.scan.active_rental_open_detail".localized,
                    type: .info
                )
            }
            navigateToFleetVehicle(arac)
            return
        }

        if candidates.isEmpty {
            alertMesaj = "wheelsys.return.no_active_return".localized
            alertGoster = true
            HapticManager.shared.warning()
            resumeScanningSoon()
            return
        }
        HapticManager.shared.success()
        ToastManager.shared.show(
            String(format: "Plate Scanned: %@".localized, plaka),
            type: .success
        )
        if candidates.count == 1, let one = candidates.first {
            openScannedReturn(candidate: one)
        } else {
            wheelsysReturnPickerCandidates = candidates
            showWheelSysReturnPicker = true
        }
    }

    @MainActor
    private func openScannedReturn(candidate: WheelSysReturnCandidate) {
        guard let arac = viewModel.findAracByPlate(candidate.plate) else {
            alertMesaj = String(
                format: "wheelsys.return.vehicle_not_in_fleet".localized,
                candidate.plate
            )
            alertGoster = true
            resumeScanningSoon()
            return
        }
        let prefill = WheelSysJournalService.buildReturnPrefill(
            from: candidate,
            entryPoint: .plateScanReturn
        )
        wheelsysReturnSheet = WheelSysIadeReturnContext(arac: arac, prefill: prefill)
    }
    
    func fotograftanPlakaOku(image: UIImage) {
        // Germany: enterprise multi-pass OCR pipeline (9 image variants, consensus + fleet check)
        if activeCountryId == "de" {
            // Build a fast lookup of all registered plate strings (compact, uppercase)
            let knownPlates = Set(viewModel.araclar.map {
                $0.plaka.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .uppercased()
            })

            GermanPlateOCRService.shared.recognizeTopCandidates(from: image, maxCandidates: 5) { [self] candidates in
                // 1. Try fleet-verified candidates first (eliminates B vs BO ambiguity)
                for candidate in candidates {
                    let compact = candidate.replacingOccurrences(of: " ", with: "").uppercased()
                    if knownPlates.contains(compact) {
                        fotografIsliyor = false
                        secilenFotograf = nil
                        tarananPlaka = candidate
                        plakaTarandi(candidate)
                        return
                    }
                }
                // 2. No fleet match — use the top-ranked candidate if it exists
                if let top = candidates.first {
                    fotografIsliyor = false
                    secilenFotograf = nil
                    tarananPlaka = top
                    plakaTarandi(top)
                } else {
                    // 3. Service inconclusive → standard Vision fallback
                    runVisionPhotoOCR(image: image)
                }
            }
            return
        }
        runVisionPhotoOCR(image: image)
    }

    /// Standard Vision photo OCR pipeline (all countries; Germany fallback).
    private func runVisionPhotoOCR(image: UIImage) {
        guard let optimizedImage = preprocessImage(image) else {
            fotografIsliyor = false
            secilenFotograf = nil
            alertMesaj = "Photo could not be processed. Please try again.".localized
            alertGoster = true
            return
        }

        guard let cgImage = optimizedImage.cgImage else {
            fotografIsliyor = false
            secilenFotograf = nil
            return
        }

        let recognitionLevels: [VNRequestTextRecognitionLevel] = [.accurate, .fast]
        var allCandidates: [String] = []
        let candidateLock = NSLock()
        let group = DispatchGroup()

        for level in recognitionLevels {
            group.enter()

            let request = VNRecognizeTextRequest { request, error in
                defer { group.leave() }
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                for observation in observations {
                    let candidates = observation.topCandidates(5)
                    for candidate in candidates {
                        let text = candidate.string.uppercased()
                        guard CountryManager.ocrTextLooksLikePlate(text, countryId: self.activeCountryId) else { continue }
                        candidateLock.lock()
                        allCandidates.append(text)
                        candidateLock.unlock()
                    }
                }
            }

            request.recognitionLevel = level
            request.recognitionLanguages = {
                switch activeCountryId {
                case "de": return ["de-DE", "en-US"]
                case "tr": return ["tr-TR", "en-US"]
                default: return ["en"]
                }
            }()
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.0
            request.customWords = CountryManager.ocrHints(for: activeCountryId)

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? requestHandler.perform([request])
            }
        }

        group.notify(queue: .main) {
            self.fotografIsliyor = false
            self.secilenFotograf = nil

            let bulunanPlaka = self.findBestPlateCandidate(from: allCandidates)

            if let plaka = bulunanPlaka {
                self.tarananPlaka = plaka
                self.plakaTarandi(plaka)
            } else {
                var debugInfo = "Found texts:\n"
                for (index, text) in allCandidates.prefix(10).enumerated() {
                    debugInfo += "\(index + 1). \(text)\n"
                }
                self.alertMesaj = String(
                    format: "Could not find a valid %@ plate in the photo.\n\nTips:\n• Take a clear photo\n• Good lighting\n• Plate should fit in frame\n\n%@".localized,
                    self.activeCountry.name,
                    debugInfo
                )
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
        CountryManager.bestDetectedPlate(from: candidates, countryId: activeCountryId)
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
                if isValidPlate(plate) {
                    return plate
                }
            }
        }
        
        return nil
    }
    
    func isValidPlate(_ text: String) -> Bool {
        CountryManager.validatePlate(text, forCountry: activeCountryId)
    }
}
