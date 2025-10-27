import SwiftUI

struct HasarDetayView: View {
    let hasar: HasarKaydi
    let aracId: UUID
    let aracPlaka: String
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var fotografGoster = false
    @State private var seciliFotografURL: String?
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var showEditSheet = false
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var body: some View {
        List {
            headerSection
            infoSection
            statusToggleSection
            
            if !hasar.fotograflar.isEmpty {
                photographsSection
            }
        }
        .navigationTitle("Damage Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                editButton
            }
        }
        .sheet(isPresented: $fotografGoster) {
            if let urlString = seciliFotografURL {
                FotografPreviewView(urlString: urlString)
            }
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = viewModel.araclar.first(where: { $0.id == aracId }) {
                NavigationView {
                    HasarEkleView(
                        aracId: aracId,
                        editingHasar: hasar // Pass existing hasar for editing
                    )
                    .environmentObject(viewModel)
                    .environmentObject(notificationManager)
                    .environmentObject(authManager)
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text(hasar.resKodu)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    private var infoSection: some View {
        Section("Information") {
            InfoRow(icon: "number.circle.fill", label: "RES Code", value: hasar.resKodu)
            InfoRow(icon: "gauge.medium", label: "KM", value: "\(hasar.km) km")
            InfoRow(icon: "calendar", label: "Date", value: hasar.tarih.formatted(date: .long, time: .omitted))
            InfoRow(icon: "calendar.badge.clock", label: "Handover Date", value: hasar.handoverTarihi.formatted(date: .long, time: .omitted))
            
            HStack {
                Label("Status", systemImage: statusIcon)
                    .foregroundColor(.secondary)
                Spacer()
                Text(hasar.durum.rawValue)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
        }
    }
    
    private var statusIcon: String {
        hasar.durum == .done ? "checkmark.circle.fill" : "clock.fill"
    }
    
    private var statusColor: Color {
        hasar.durum == .done ? .green : .orange
    }
    
    private var statusToggleSection: some View {
        Section {
            Button {
                toggleDamageStatus()
            } label: {
                HStack {
                    Image(systemName: hasar.durum == .done ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                    Text(hasar.durum == .done ? "Mark as In Progress" : "Mark as Done")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasar.durum == .done ? Color.orange : Color.green)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var photographsSection: some View {
        Section("Photographs (\(hasar.fotograflar.count))") {
            photographsScrollView
            pdfGeneratorButton
        }
    }
    
    private var photographsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(hasar.fotograflar.enumerated()), id: \.offset) { index, urlString in
                    PhotoThumbnail(
                        urlString: urlString,
                        index: index,
                        onTap: {
                            seciliFotografURL = urlString
                            fotografGoster = true
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var pdfGeneratorButton: some View {
        Button {
            generatePDF()
        } label: {
            HStack {
                if pdfOlusturuluyor {
                    ProgressView()
                        .tint(.white)
                    Text("Generating PDF...")
                } else {
                    Image(systemName: "doc.fill")
                    Text("Generate Damage Report PDF")
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(Color.red)
            .cornerRadius(12)
        }
        .disabled(pdfOlusturuluyor)
    }
    
    private var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pencil.circle.fill")
                Text("Edit")
            }
            .foregroundColor(.blue)
        }
    }
    
    func toggleDamageStatus() {
        var updatedHasar = hasar
        updatedHasar.durum = hasar.durum == .done ? .inProgress : .done
        viewModel.hasarGuncelle(aracId: aracId, hasar: updatedHasar)
        HapticManager.shared.success()
        
        // 🔔 Send notification when damage is marked as done
        if updatedHasar.durum == .done {
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendDamageCompletedNotification(
                carPlate: aracPlaka,
                resCode: hasar.resKodu,
                userName: userName
            )
        }
    }
    
    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        
        PDFGenerator.shared.generateHasarPDF(
            hasar: hasar,
            aracPlaka: aracPlaka,
            aracKM: hasar.km
        ) { url in
            DispatchQueue.main.async {
                pdfOlusturuluyor = false
                if let url = url {
                    pdfURL = url
                    pdfPaylas = true
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

private struct PhotoThumbnail: View {
    let urlString: String
    let index: Int
    let onTap: () -> Void
    
    var body: some View {
        AsyncImageView(urlString: urlString) { image in
            Button(action: onTap) {
                VStack(spacing: 4) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .clipped()
                    
                    Text(index == 0 ? "HANDOVER" : "RETURN")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

private struct HasarEkleEditView: View {
    let aracId: UUID
    let hasar: HasarKaydi
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var tarih: Date
    @State private var handoverTarihi: Date
    @State private var resKodu: String
    @State private var km: String
    @State private var fotograflar: [UIImage] = [] // Photos from gallery
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera (all RETURN)
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
        // Ensure RES- prefix is present but not duplicated
        let cleanResCode = hasar.resKodu.replacingOccurrences(of: "RES-", with: "")
        _resKodu = State(initialValue: "RES-\(cleanResCode)")
        _km = State(initialValue: "\(hasar.km)")
        _durum = State(initialValue: hasar.durum)
        _existingPhotoURLs = State(initialValue: hasar.fotograflar)
    }
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
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
        .navigationTitle("Edit Damage")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $fotograflar)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // After camera dismisses, check if we should reopen for more photos
            if let _ = capturedImage {
                // Photo was taken, reopen camera if under limit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if cameraPhotos.count < 20 && !showImagePicker {
                        showCamera = true
                    }
                }
            }
        }) {
            CameraPicker(selectedImage: $capturedImage)
        }
        .onChange(of: capturedImage) { newImage in
            // Only process camera photos, not gallery photos
            guard let newImage = newImage, !showImagePicker else { return }
            
            cameraPhotos.append(newImage)
            capturedImage = nil
        }
    }
    
    private var damageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Damage Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                DatePicker("Date", selection: $tarih, displayedComponents: .date)
                DatePicker("Handover Date", selection: $handoverTarihi, displayedComponents: .date)
                TextField("RES Code (e.g., RES-123)", text: $resKodu)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: resKodu) { newValue in
                        // Ensure RES- prefix is always present
                        if !newValue.hasPrefix("RES-") {
                            resKodu = "RES-"
                        }
                    }
                TextField("Kilometer", text: $km)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Status", selection: $durum) {
                    ForEach(HasarDurum.allCases, id: \.self) { status in
                        Text(status.displayTitle).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    private var existingPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Existing Photos")
                .font(.headline)
                .padding(.horizontal)
            
            if !existingPhotoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(existingPhotoURLs.enumerated()), id: \.offset) { index, urlString in
                            VStack(spacing: 4) {
                                AsyncImageView(urlString: urlString) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(8)
                                        .clipped()
                                }
                                Text(index == 0 ? "HANDOVER" : "RETURN")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.red)
                                Button {
                                    existingPhotoURLs.remove(at: index)
                                } label: {
                                    Image(systemName: "trash.fill").foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Text("No existing photos")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
        }
    }
    
    private var newPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add New Photos")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                // Gallery button
                Button {
                    showImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Select from Gallery (RETURN)")
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Camera button
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo (RETURN)")
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Gallery photos
                if !fotograflar.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gallery Photos (RETURN)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(fotograflar.enumerated()), id: \.offset) { index, image in
                                    VStack {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .clipped()
                                        Button {
                                            fotograflar.remove(at: index)
                                        } label: {
                                            Image(systemName: "trash.fill").foregroundColor(.red)
                                        }
                                        Text("RETURN")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Camera photos
                if !cameraPhotos.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera Photos (RETURN) - \(cameraPhotos.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(cameraPhotos.enumerated()), id: \.offset) { index, image in
                                    VStack {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .clipped()
                                        Button {
                                            cameraPhotos.remove(at: index)
                                        } label: {
                                            Image(systemName: "trash.fill").foregroundColor(.red)
                                        }
                                        Text("RETURN")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    private var saveButton: some View {
        Button {
            Task { await kaydet() }
        } label: {
            if isUploading {
                HStack { ProgressView(); Text("Updating...") }
            } else {
                Text("Update Damage Record")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(resKodu.count <= 4 || km.isEmpty || isUploading)
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    private func kaydet() async {
        isUploading = true
        
        await withCheckedContinuation { continuation in
            // Combine all photos: gallery photos first, then camera photos (all RETURN)
            let allPhotosToUpload = fotograflar + cameraPhotos
            
            // Upload photos with index to maintain order
            var indexedPhotoURLs: [(index: Int, url: String)] = []
            let group = DispatchGroup()
            let lock = NSLock() // Thread-safe array updates
            
            // Upload all new photos preserving their order
            for (index, image) in allPhotosToUpload.enumerated() {
                group.enter()
                let path = "hasar_fotograflari/\(UUID().uuidString).jpg"
                CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                    if let url = url {
                        lock.lock()
                        indexedPhotoURLs.append((index: index, url: url))
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Sort uploaded photos by index (maintains order: gallery first, then camera)
                let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
                
                // IMPORTANT: First photo (HANDOVER) must always be first
                // Keep existing photos, append new photos (gallery + camera)
                let allPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
                
                // Clean RES code to prevent duplication
                var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
                // Ensure only one RES- prefix
                if cleanResKodu.hasPrefix("RES-") {
                    let withoutPrefix = cleanResKodu.replacingOccurrences(of: "RES-", with: "")
                    cleanResKodu = "RES-\(withoutPrefix)"
                }
                
                var updatedHasar = self.hasar
                updatedHasar.tarih = self.tarih
                updatedHasar.handoverTarihi = self.handoverTarihi
                updatedHasar.resKodu = cleanResKodu
                updatedHasar.km = Int(self.km) ?? 0
                updatedHasar.durum = self.durum
                updatedHasar.fotograflar = allPhotoURLs
                
                self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)
                
                HapticManager.shared.success()
                self.isUploading = false
                self.dismiss()
                
                continuation.resume()
            }
        }
    }
}
