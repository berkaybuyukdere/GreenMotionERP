import SwiftUI

struct HasarDetayView: View {
    let hasar: HasarKaydi
    let aracId: UUID
    let aracPlaka: String
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var photoGalleryItem: PhotoGallerySheetItem?
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var showEditSheet = false
    /// After completing damage from the edit sheet, show a fresh detail preview (same pattern as return → detail).
    @State private var previewDamageId: UUID?
    @State private var showDamagePreviewAfterEdit = false

    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }

    private var isTurkeyFranchise: Bool {
        String(hasar.franchiseId).uppercased().hasPrefix("TR")
    }

    private var isGermanyFranchise: Bool {
        String(hasar.franchiseId).uppercased().hasPrefix("DE")
    }

    private var codeFieldLabel: String {
        if isTurkeyFranchise { return "NAV Code" }
        if isGermanyFranchise { return "RNT Code" }
        return "RES Code"
    }

    private var codePrefix: String {
        if isTurkeyFranchise { return "NAV-" }
        if isGermanyFranchise { return "RNT-" }
        return "RES-"
    }

    private var palantirOps: Bool {
        PalantirProcessDetailSupport.isEnabled(userProfile: authManager.userProfile)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: palantirOps ? 11 : 16) {
                statusCard
                infoCard
                statusToggleButton
                if !hasar.fotograflar.isEmpty {
                    photosSection
                }
                if isTurkeyFranchise {
                    turkishPdfButton
                    englishPdfButton
                } else {
                    pdfButton
                }
            }
            .padding(.horizontal, palantirOps ? 13 : 16)
            .padding(.top, palantirOps ? 11 : 16)
            .padding(.bottom, 44)
        }
        .processDetailScreenBackground(palantirOps)
        .palantirProcessDetailChrome(enabled: palantirOps)
        .navigationTitle("Damage Detail".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.light()
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .fullScreenCover(item: $photoGalleryItem) { item in
            NativePhotoGalleryView(urlStrings: hasar.fotograflar, initialIndex: item.startIndex)
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL { ActivityViewController(activityItems: [url]) }
        }
        .sheet(isPresented: $showEditSheet) {
            if viewModel.araclar.first(where: { $0.id == aracId }) != nil {
                SheetWrapper {
                    NavigationView {
                        HasarEkleView(aracId: aracId, editingHasar: hasar) { completed in
                            previewDamageId = completed.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showDamagePreviewAfterEdit = true
                            }
                        }
                        .environmentObject(viewModel)
                        .environmentObject(notificationManager)
                        .environmentObject(authManager)
                    }
                }
            }
        }
        .sheet(isPresented: $showDamagePreviewAfterEdit) {
            if let damageId = previewDamageId,
               let ar = viewModel.araclar.first(where: { $0.id == aracId }),
               let freshHasar = ar.hasarKayitlari.first(where: { $0.id == damageId }) {
                NavigationView {
                    HasarDetayView(hasar: freshHasar, aracId: aracId, aracPlaka: aracPlaka)
                        .environmentObject(viewModel)
                        .environmentObject(notificationManager)
                        .environmentObject(authManager)
                }
            }
        }
    }

    // MARK: - Status Card (compact Apple-style header)

    @ViewBuilder
    private var statusCard: some View {
        if palantirOps {
            PalantirProcessDetailHero(
                title: hasar.resKodu,
                subtitle: "Damage Report".localized,
                icon: "exclamationmark.triangle.fill",
                tint: PalantirTheme.warning,
                badge: hasar.durum == .done ? "Done".localized : "In Progress".localized,
                badgeTone: hasar.durum == .done ? .success : .warning
            )
        } else {
            legacyStatusCard
        }
    }

    private var legacyStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(hasar.resKodu)
                    .font(.system(size: 17, weight: .bold))
                Text("Damage Report".localized)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(hasar.durum == .done ? "Done".localized : "In Progress".localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(hasar.durum == .done ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((hasar.durum == .done ? Color.green : Color.orange).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Info Card

    @ViewBuilder
    private var infoCard: some View {
        if palantirOps {
            PalantirProcessDetailInfoSection(
                title: "INFORMATION".localized,
                rows: [
                    (codeFieldLabel.localized, hasar.resKodu),
                    ("KM".localized, "\(hasar.km) km"),
                    ("Date".localized, hasar.tarih.formatted(date: .long, time: .omitted)),
                    ("Handover Date".localized, hasar.handoverTarihi.formatted(date: .long, time: .omitted)),
                    ("Status".localized, hasar.durum == .done ? "Done".localized : "In Progress".localized),
                ]
            )
        } else {
            legacyInfoCard
        }
    }

    private var legacyInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("INFORMATION".localized)
            VStack(spacing: 0) {
                infoRow(icon: "number.circle.fill",   color: .blue,   label: codeFieldLabel.localized,      value: hasar.resKodu)
                Divider().padding(.leading, 50)
                infoRow(icon: "gauge.medium",          color: .green,  label: "KM".localized,             value: "\(hasar.km) km")
                Divider().padding(.leading, 50)
                infoRow(icon: "calendar",              color: .orange, label: "Date".localized,           value: hasar.tarih.formatted(date: .long, time: .omitted))
                Divider().padding(.leading, 50)
                infoRow(icon: "calendar.badge.clock",  color: .purple, label: "Handover Date".localized,  value: hasar.handoverTarihi.formatted(date: .long, time: .omitted))
                Divider().padding(.leading, 50)
                infoRow(
                    icon:       hasar.durum == .done ? "checkmark.circle.fill" : "clock.fill",
                    color:      hasar.durum == .done ? .green : .orange,
                    label:      "Status".localized,
                    value:      hasar.durum == .done ? "Done".localized : "In Progress".localized,
                    valueColor: hasar.durum == .done ? .green : .orange
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    // MARK: - Status Toggle Button (only shown when In Progress → allow marking Done)

    @ViewBuilder
    private var statusToggleButton: some View {
        if hasar.durum == .inProgress {
            Button {
                HapticManager.shared.medium()
                toggleDamageStatus()
            } label: {
                Label("Mark as Done".localized, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 15)
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Photos Section (Apple Photos-style grid)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(format: "PHOTOGRAPHS (%d)".localized, hasar.fotograflar.count))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                spacing: 3
            ) {
                ForEach(Array(hasar.fotograflar.enumerated()), id: \.offset) { index, url in
                    let isHandover = index == 0
                    DetailPhotoGridCell(
                        urlString: url,
                        label: isHandover ? "HANDOVER" : "RETURN",
                        dateText: isHandover
                            ? ProcessPhotoStampLabels.formatDisplayDate(hasar.handoverTarihi, includeTime: false)
                            : ProcessPhotoStampLabels.formatDisplayDate(hasar.tarih, includeTime: false),
                        labelColor: isHandover ? .purple : .blue
                    ) {
                        photoGalleryItem = PhotoGallerySheetItem(startIndex: index)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - PDF Button (always blue)

    private var pdfButton: some View {
        Group {
            if palantirOps {
                WheelSysPalantirPrimaryButton(
                    title: pdfOlusturuluyor ? "Generating PDF...".localized : "Generate Damage Report PDF".localized,
                    icon: "doc.text.fill",
                    isLoading: pdfOlusturuluyor
                ) {
                    HapticManager.shared.medium()
                    generatePDF()
                }
            } else {
                legacyPdfButton
            }
        }
    }

    private var legacyPdfButton: some View {
        Button {
            HapticManager.shared.medium()
            generatePDF()
        } label: {
            HStack(spacing: 10) {
                if pdfOlusturuluyor {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("Generating PDF...".localized).font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 16, weight: .semibold))
                    Text("Generate Damage Report PDF".localized).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(pdfOlusturuluyor)
    }

    private var turkishPdfButton: some View {
        languagePdfButton(title: "Generate Damage PDF 🇹🇷".localized, language: .turkish, color: .blue)
    }

    private var englishPdfButton: some View {
        languagePdfButton(title: "Generate Damage PDF 🇬🇧".localized, language: .english, color: .indigo)
    }

    private func languagePdfButton(title: String, language: PDFContentLanguage, color: Color) -> some View {
        Button {
            HapticManager.shared.medium()
            generatePDF(language: language)
        } label: {
            HStack(spacing: 10) {
                if pdfOlusturuluyor {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("Generating PDF...".localized).font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 16, weight: .semibold))
                    Text(title).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(color)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(pdfOlusturuluyor)
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.leading, 2)
            .padding(.bottom, 7)
    }

    // MARK: - Info Row

    @ViewBuilder
    private func infoRow(icon: String, color: Color = .secondary, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(.tertiaryLabel))
                .frame(width: 20)
            Text(label).font(.system(size: 15)).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Logic (unchanged)

    func toggleDamageStatus() {
        var updatedHasar = hasar
        updatedHasar.durum = hasar.durum == .done ? .inProgress : .done
        viewModel.hasarGuncelle(aracId: aracId, hasar: updatedHasar)
        HapticManager.shared.success()
    }

    func generatePDF() {
        generatePDF(language: .automatic)
    }

    func generatePDF(language: PDFContentLanguage) {
        guard let _ = arac else { return }
        pdfOlusturuluyor = true
        PDFGenerator.shared.generateHasarPDF(
            hasar: hasar,
            aracPlaka: aracPlaka,
            aracKM: hasar.km,
            vehicleBrand: arac?.marka ?? "",
            vehicleModel: arac?.model ?? "",
            language: language
        ) { url in
            DispatchQueue.main.async {
                self.pdfOlusturuluyor = false
                if let url = url {
                    let pdfName = Validators.damageReportExportFileBase(
                        resKodu: hasar.resKodu,
                        fallbackDate: hasar.tarih
                    )
                    self.shareRenamedPDF(url: url, name: pdfName)
                }
            }
        }
    }

    private func shareRenamedPDF(url: URL, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        pdfURL = dest
        pdfPaylas = true
    }
}

// MARK: - Shared Photo Grid Cell (used by all 3 detail views)

struct DetailPhotoGridCell: View {
    let urlString: String
    let label: String
    var dateText: String? = nil
    var timeText: String? = nil
    let labelColor: Color
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Button(action: onTap) {
            // Color.clear with .aspectRatio(.fit) is the reliable SwiftUI pattern
            // for square cells in LazyVGrid — the overlay fills the square frame.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    ZStack(alignment: .bottom) {
                        Color(.systemGray5)
                        if let img = image {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .clipped()
                        } else if isLoading {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(Color(.systemGray3))
                        }
                        // Label + date badge at bottom
                        VStack(spacing: 2) {
                            Text(label)
                                .font(.system(size: 9, weight: .bold))
                            if let dateText, !dateText.isEmpty {
                                Text(dateText)
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            if let timeText, !timeText.isEmpty {
                                Text(timeText)
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(4)
                        .padding(.bottom, 5)
                    }
                    .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            StorageImageLoader.shared.loadImage(from: urlString) { loaded in
                self.image = loaded
                self.isLoading = false
            }
        }
    }
}

// MARK: - HasarEkleEditView (editing support, preserved)

private struct HasarEkleEditView: View {
    let aracId: UUID
    let hasar: HasarKaydi
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss

    private var isTurkeyFranchise: Bool {
        String(hasar.franchiseId).uppercased().hasPrefix("TR")
    }

    private var isGermanyFranchise: Bool {
        String(hasar.franchiseId).uppercased().hasPrefix("DE")
    }

    private var codeFieldLabel: String {
        if isTurkeyFranchise { return "NAV Code" }
        if isGermanyFranchise { return "RNT Code" }
        return "RES Code"
    }

    private var codePrefix: String {
        if isTurkeyFranchise { return "NAV-" }
        if isGermanyFranchise { return "RNT-" }
        return "RES-"
    }

    private static func reservationDigits(from raw: String) -> String {
        var c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = c.uppercased()
        for p in ["RES-", "RNT-", "NAV-"] {
            if upper.hasPrefix(p) {
                c = String(c.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return c.filter(\.isNumber)
    }

    @State private var tarih: Date
    @State private var handoverTarihi: Date
    @State private var resKodu: String
    @State private var km: String
    @State private var fotograflar: [UIImage] = []
    @State private var cameraPhotos: [UIImage] = []
    @State private var durum: HasarDurum
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var existingPhotoURLs: [String]

    init(aracId: UUID, hasar: HasarKaydi) {
        self.aracId = aracId
        self.hasar = hasar
        _tarih = State(initialValue: hasar.tarih)
        _handoverTarihi = State(initialValue: hasar.handoverTarihi)
        let resCodeNumbers = Self.reservationDigits(from: hasar.resKodu)
        _resKodu = State(initialValue: resCodeNumbers)
        _km = State(initialValue: "\(hasar.km)")
        _durum = State(initialValue: hasar.durum)
        _existingPhotoURLs = State(initialValue: hasar.fotograflar)
    }

    var arac: Arac? { viewModel.araclar.first(where: { $0.id == aracId }) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                damageInfoSection
                existingPhotosSection
                newPhotosSection
                saveButton
            }
            .padding(.top)
        }
        .navigationTitle("Edit Damage".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) { ImagePicker(selectedImages: $fotograflar) }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let _ = capturedImage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if cameraPhotos.count < 20 && !showImagePicker { showCamera = true }
                }
            }
        }) { CameraPicker(selectedImage: $capturedImage) }
        .onChange(of: capturedImage) { newImage in
            guard let newImage = newImage, !showImagePicker else { return }
            cameraPhotos.append(newImage); capturedImage = nil
        }
    }

    private var damageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Damage Information".localized).font(.headline).padding(.horizontal)
            VStack(spacing: 12) {
                DatePicker("Date".localized, selection: $tarih, displayedComponents: .date)
                DatePicker("Handover Date".localized, selection: $handoverTarihi, displayedComponents: .date)
                HStack {
                    Text(codeFieldLabel.localized); Spacer()
                    HStack(spacing: 0) {
                        Text(codePrefix).foregroundColor(.secondary)
                        TextField("Enter numbers".localized, text: $resKodu)
                            .keyboardType(.numberPad).textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                    }
                }
                .onChange(of: resKodu) { oldValue, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { resKodu = filtered }
                }
                HStack {
                    Text("Kilometer".localized); Spacer()
                    TextField("Enter kilometers".localized, text: $km)
                        .keyboardType(.numberPad).textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                }
                Picker("Status".localized, selection: $durum) {
                    ForEach(HasarDurum.allCases, id: \.self) { Text($0.displayTitle).tag($0) }
                }.pickerStyle(.segmented)
            }
            .padding().background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
        }
    }

    private var existingPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Existing Photos".localized).font(.headline).padding(.horizontal)
            if !existingPhotoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(existingPhotoURLs.enumerated()), id: \.offset) { index, urlString in
                            VStack(spacing: 4) {
                                AsyncImageView(urlString: urlString) { image in
                                    image.resizable().scaledToFill().frame(width: 100, height: 100).cornerRadius(8).clipped()
                                }
                                Text(index == 0 ? "HANDOVER".localized : "RETURN".localized)
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.red)
                                Button { existingPhotoURLs.remove(at: index) } label: {
                                    Image(systemName: "trash.fill").foregroundColor(.red)
                                }
                            }
                        }
                    }.padding()
                }
                .background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
            } else {
                Text("No existing photos".localized).foregroundColor(.secondary)
                    .padding().frame(maxWidth: .infinity)
                    .background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
            }
        }
    }

    private var newPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add New Photos".localized).font(.headline).padding(.horizontal)
            VStack(spacing: 16) {
                Button { showImagePicker = true } label: {
                    HStack { Image(systemName: "photo.on.rectangle.angled"); Text("Select from Gallery (RETURN)".localized); Spacer() }
                        .padding().background(Color.blue.opacity(0.1)).cornerRadius(10)
                }.buttonStyle(PlainButtonStyle())
                Button { showCamera = true } label: {
                    HStack { Image(systemName: "camera.fill"); Text("Take Photo (RETURN)".localized); Spacer() }
                        .padding().background(Color.green.opacity(0.1)).cornerRadius(10)
                }.buttonStyle(PlainButtonStyle())
                if !fotograflar.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(fotograflar.enumerated()), id: \.offset) { index, image in
                                VStack {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 100).cornerRadius(8).clipped()
                                    Button { fotograflar.remove(at: index) } label: { Image(systemName: "trash.fill").foregroundColor(.red) }
                                    Text("RETURN".localized).font(.caption2).fontWeight(.bold).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                if !cameraPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(cameraPhotos.enumerated()), id: \.offset) { index, image in
                                VStack {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 100).cornerRadius(8).clipped()
                                    Button { cameraPhotos.remove(at: index) } label: { Image(systemName: "trash.fill").foregroundColor(.red) }
                                    Text("RETURN".localized).font(.caption2).fontWeight(.bold).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .padding().background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
        }
    }

    private var saveButton: some View {
        Button { Task { await kaydet() } } label: {
            if isUploading { HStack { ProgressView(); Text("Updating...".localized) } }
            else { Text("Update Damage Record".localized).frame(maxWidth: .infinity).fontWeight(.semibold) }
        }
        .buttonStyle(AppTheme.primaryButtonStyle)
        .controlSize(.large)
        .disabled(resKodu.count != 5 || km.isEmpty || isUploading)
        .padding(.horizontal).padding(.bottom, 20)
    }

    private func finishDamageEditSave(sortedNewPhotos: [String], usedOfflineQueue: Bool) {
        let allPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
        var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
        let digits = Self.reservationDigits(from: cleanResKodu)
        cleanResKodu = digits.isEmpty ? "" : "\(codePrefix)\(digits)"
        var updatedHasar = self.hasar
        updatedHasar.tarih = self.tarih; updatedHasar.handoverTarihi = self.handoverTarihi
        updatedHasar.resKodu = cleanResKodu; updatedHasar.km = Int(self.km) ?? 0
        updatedHasar.durum = self.durum; updatedHasar.fotograflar = allPhotoURLs
        self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)
        HapticManager.shared.success(); self.isUploading = false
        ToastManager.shared.show(usedOfflineQueue ? "Saved on this device. Damage photos will upload when you are back online.".localized : "✓ Damage Saved".localized, type: .success)
        self.dismiss()
    }

    private func kaydet() async {
        isUploading = true
        let stableDocumentId = hasar.id
        await withCheckedContinuation { continuation in
            let allPhotosToUpload = fotograflar + cameraPhotos
            var indexedPhotoURLs: [(index: Int, url: String)] = []
            var uploadErrors: [Error] = []
            let group = DispatchGroup(); let lock = NSLock()
            for (index, image) in allPhotosToUpload.enumerated() {
                group.enter()
                CachedImageManager.shared.uploadImage(image, path: "hasar_fotograflari/\(UUID().uuidString).jpg") { url, error in
                    DispatchQueue.main.async {
                        if let url = url { lock.lock(); indexedPhotoURLs.append((index: index, url: url)); lock.unlock() }
                        else if let error = error { lock.lock(); uploadErrors.append(error); lock.unlock() }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let totalCount = allPhotosToUpload.count; let failedCount = uploadErrors.count
                let allFailed = totalCount > 0 && failedCount == totalCount
                let transient = uploadErrors.allSatisfy(OfflineSyncDiagnostics.isLikelyTransientNetworkFailure)
                let canOffline = allFailed && (transient || !OfflineModeManager.shared.isOnline)
                if !uploadErrors.isEmpty {
                    if allFailed && !canOffline {
                        self.isUploading = false
                        ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                        continuation.resume(); return
                    } else if !allFailed {
                        self.isUploading = false
                        ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Damage record will be saved with available photos.".localized, failedCount, totalCount))
                        continuation.resume(); return
                    }
                }
                if canOffline {
                    OfflineMediaSyncCoordinator.shared.enqueueHasarMedia(documentId: stableDocumentId, images: allPhotosToUpload, slotTypes: Array(repeating: "flat", count: allPhotosToUpload.count)) { ok in
                        guard ok else { self.isUploading = false; ErrorManager.shared.showError(message: "Could not save photos on this device for later upload.".localized); continuation.resume(); return }
                        self.finishDamageEditSave(sortedNewPhotos: [], usedOfflineQueue: true); continuation.resume()
                    }
                    return
                }
                self.finishDamageEditSave(sortedNewPhotos: indexedPhotoURLs.sorted { $0.index < $1.index }.map { $0.url }, usedOfflineQueue: false)
                continuation.resume()
            }
        }
    }
}
