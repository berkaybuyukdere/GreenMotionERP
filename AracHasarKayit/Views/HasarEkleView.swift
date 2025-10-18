import SwiftUI

struct HasarEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let aracId: UUID
    let editingHasar: HasarKaydi? // nil = yeni hasar, dolu = düzenleme modu
    
    @State private var tarih = Date()
    @State private var handoverTarihi = Date()
    @State private var resKodu = "RES-"
    @State private var km = ""
    @State private var fotograflar: [UIImage] = [] // Photos from gallery (HANDOVER will be first)
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera (all RETURN)
    @State private var durum: HasarDurum = .inProgress
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var existingPhotoURLs: [String] = [] // Existing photo URLs
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var isEditMode: Bool {
        editingHasar != nil
    }
    
    init(aracId: UUID, editingHasar: HasarKaydi? = nil) {
        self.aracId = aracId
        self.editingHasar = editingHasar
        
        // Load existing values in edit mode
        if let hasar = editingHasar {
            _tarih = State(initialValue: hasar.tarih)
            _handoverTarihi = State(initialValue: hasar.handoverTarihi)
            // Ensure RES- prefix is present but not duplicated
            let cleanResCode = hasar.resKodu.replacingOccurrences(of: "RES-", with: "")
            _resKodu = State(initialValue: "RES-\(cleanResCode)")
            _km = State(initialValue: "\(hasar.km)")
            _durum = State(initialValue: hasar.durum)
            _existingPhotoURLs = State(initialValue: hasar.fotograflar)
        }
    }
    
    var body: some View {
        Form {
            Section("Damage Information") {
                DatePicker("Date", selection: $tarih, displayedComponents: .date)
                DatePicker("Handover Date", selection: $handoverTarihi, displayedComponents: .date)
                
                HStack {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(.blue)
                    TextField("RES Code (e.g., RES-123)", text: $resKodu)
                        .onChange(of: resKodu) { newValue in
                            // Ensure RES- prefix is always present
                            if !newValue.hasPrefix("RES-") {
                                resKodu = "RES-"
                            }
                        }
                }
                
                HStack {
                    Image(systemName: "gauge.medium.badge.plus")
                        .foregroundColor(.blue)
                    TextField("Kilometer", text: $km)
                        .keyboardType(.numberPad)
                }
                
                Picker("Status", selection: $durum) {
                    ForEach(HasarDurum.allCases, id: \.self) { status in
                        Text(status.displayTitle).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Photographs") {
                // Display existing photos (in edit mode)
                if !existingPhotoURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Existing Photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(existingPhotoURLs.indices, id: \.self) { index in
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            AsyncImageView(urlString: existingPhotoURLs[index]) { image in
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            
                                            Button {
                                                // Don't delete HANDOVER photo if it's the last one
                                                if index == 0 && existingPhotoURLs.count == 1 {
                                                    return
                                                }
                                                existingPhotoURLs.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white.clipShape(Circle()))
                                            }
                                            .padding(4)
                                        }
                                        
                                        Text(index == 0 ? "HANDOVER" : "RETURN")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Gallery photos (first one is HANDOVER if new damage)
                if !fotograflar.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gallery Photos (HANDOVER)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(fotograflar.indices, id: \.self) { index in
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: fotograflar[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Button {
                                                fotograflar.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white.clipShape(Circle()))
                                            }
                                            .padding(4)
                                        }
                                        
                                        let labelText = !isEditMode && index == 0 && existingPhotoURLs.isEmpty ? "HANDOVER" : "RETURN"
                                        Text(labelText)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Camera photos (all RETURN)
                if !cameraPhotos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Camera Photos (RETURN) - \(cameraPhotos.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(cameraPhotos.indices, id: \.self) { index in
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: cameraPhotos[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Button {
                                                cameraPhotos.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white.clipShape(Circle()))
                                            }
                                            .padding(4)
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
                
                // Gallery Button (HANDOVER)
                Button {
                    showImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Select from Gallery (HANDOVER)")
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 4)
                
                // Camera Button (RETURN)
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
                .padding(.vertical, 4)
            }
            
            Section {
                Button {
                    kaydet()
                } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                            Text("Uploading...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(isEditMode ? "Update" : "Save")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(resKodu.count <= 4 || km.isEmpty || isUploading)
            }
        }
        .navigationTitle(isEditMode ? "Edit Damage" : "Add Damage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
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
    
    func kaydet() {
        guard let kmValue = Int(km) else { return }
        
        isUploading = true
        
        // Combine all photos: gallery photos first (HANDOVER first), then camera photos (all RETURN)
        let allPhotosToUpload = fotograflar + cameraPhotos
        
        // Upload photos with index to maintain order
        var indexedPhotoURLs: [(index: Int, url: String)] = []
        let group = DispatchGroup()
        let lock = NSLock() // Thread-safe array updates
        
        // Upload all photos in order
        for (index, foto) in allPhotosToUpload.enumerated() {
            group.enter()
            let path = "hasar_fotograflari/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                if let url = url {
                    lock.lock()
                    indexedPhotoURLs.append((index: index, url: url))
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Clean RES code to prevent duplication
            var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
            // Ensure only one RES- prefix
            if cleanResKodu.hasPrefix("RES-") {
                let withoutPrefix = cleanResKodu.replacingOccurrences(of: "RES-", with: "")
                cleanResKodu = "RES-\(withoutPrefix)"
            }
            
            // Sort uploaded photos by index (maintains order: gallery first, then camera)
            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            
            // IMPORTANT: First photo is always HANDOVER (from gallery), rest are RETURN
            var allPhotos: [String] = []
            
            if self.isEditMode {
                // Edit mode: Keep existing photos, add new photos
                // First photo (HANDOVER) always stays first
                allPhotos = self.existingPhotoURLs + sortedNewPhotos
            } else {
                // New damage: All new photos, first one is HANDOVER
                allPhotos = sortedNewPhotos
            }
            
            if self.isEditMode, let editingHasar = self.editingHasar {
                // Düzenleme modu: Mevcut hasarı güncelle
                var updatedHasar = editingHasar
                updatedHasar.tarih = self.tarih
                updatedHasar.handoverTarihi = self.handoverTarihi
                updatedHasar.resKodu = cleanResKodu
                updatedHasar.km = kmValue
                updatedHasar.fotograflar = allPhotos
                updatedHasar.durum = self.durum
                
                self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)
            } else {
                // Yeni hasar ekleme
                let yeniHasar = HasarKaydi(
                    tarih: self.tarih,
                    handoverTarihi: self.handoverTarihi,
                    resKodu: cleanResKodu,
                    km: kmValue,
                    fotograflar: allPhotos,
                    durum: self.durum
                )
                
                self.viewModel.hasarEkle(aracId: self.aracId, hasar: yeniHasar)
                
                // 🔔 Send notification for new damage record
                if let arac = self.arac {
                    let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                    self.notificationManager.sendDamageRecordNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName
                    )
                }
            }
            
            HapticManager.shared.success()
            
            // Show success toast
            if self.isEditMode {
                ToastManager.shared.show("✓ Damage Updated", type: .success)
            } else {
                ToastManager.shared.show("✓ Damage Record Added", type: .success)
            }
            
            self.isUploading = false
            self.dismiss()
        }
    }
}
