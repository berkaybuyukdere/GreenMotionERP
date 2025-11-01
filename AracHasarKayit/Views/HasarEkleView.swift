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
    @State private var notlar = ""
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var existingPhotoURLs: [String] = [] // Existing photo URLs
    @State private var hasUnsavedChanges = false
    @State private var showExitConfirmation = false
    @State private var isSaved = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadedPhotosCount: Int = 0
    @State private var totalPhotosCount: Int = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSaveConfirmation = false
    @State private var showCompleteConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoSaveTimer: Timer?
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var isEditMode: Bool {
        editingHasar != nil
    }
    
    init(aracId: UUID, editingHasar: HasarKaydi? = nil) {
        self.aracId = aracId
        self.editingHasar = editingHasar
        
        if let hasar = editingHasar {
            _tarih = State(initialValue: hasar.tarih)
            _handoverTarihi = State(initialValue: hasar.handoverTarihi)
            _resKodu = State(initialValue: hasar.resKodu)
            _km = State(initialValue: String(hasar.km))
            _durum = State(initialValue: hasar.durum)
            _existingPhotoURLs = State(initialValue: hasar.fotograflar)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                if isUploading && uploadProgress > 0 {
                    Section {
                        UploadProgressView(
                            progress: uploadProgress,
                            currentItem: uploadedPhotosCount,
                            totalItems: totalPhotosCount,
                            message: "Uploading photos..."
                        )
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                damageInfoSection
                photographsSection
                notesSection
                saveSection
                completeSection
            }
        }
        .onChange(of: resKodu) { _ in hasUnsavedChanges = true }
        .onChange(of: km) { _ in hasUnsavedChanges = true }
        .onChange(of: tarih) { _ in hasUnsavedChanges = true }
        .onChange(of: handoverTarihi) { _ in hasUnsavedChanges = true }
        .onChange(of: durum) { _ in hasUnsavedChanges = true }
        .onChange(of: fotograflar) { _ in hasUnsavedChanges = true }
        .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
        .onChange(of: existingPhotoURLs) { _ in hasUnsavedChanges = true }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && hasUnsavedChanges && !isSaved {
                saveDraft()
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges && !isSaved)
        .onAppear {
            // Load existing hasar data if editing
            if let editingHasar = editingHasar {
                resKodu = editingHasar.resKodu
                km = String(editingHasar.km)
                tarih = editingHasar.tarih
                handoverTarihi = editingHasar.handoverTarihi
                durum = editingHasar.durum
                notlar = editingHasar.notlar
                loadExistingPhotos()
            } else {
                // Try to load draft for new records
                loadDraft()
                
                // Auto-fill RES code from previous damage record for the same vehicle
                if let arac = arac {
                    let previousHasar = arac.hasarKayitlari
                        .sorted(by: { $0.tarih > $1.tarih })
                        .first
                    
                    if let previous = previousHasar, resKodu == "RES-" {
                        resKodu = previous.resKodu
                    }
                }
            }
        }
        .onDisappear {
            // Clear draft when view is dismissed
            if isSaved {
                clearDraft()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $fotograflar)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // After camera dismisses, check if we should reopen for more photos
            if let _ = capturedImage {
                // Add captured image to camera photos
                if let newImage = capturedImage {
                    cameraPhotos.append(newImage)
                }
                // Clear the captured image to prepare for next capture
                capturedImage = nil
            }
        }) {
            CameraView(capturedImage: $capturedImage)
        }
        .alert("Unsaved Changes", isPresented: $showExitConfirmation) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to exit without saving or completing this operation?")
        }
        .alert("Confirm Save", isPresented: $showSaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                HapticManager.shared.success()
                kaydet(changeStatus: false)
            }
        } message: {
            Text("Are you sure you have completed all the necessary operations? Click 'Save' to save your progress and continue editing later.")
        }
        .alert("Confirm Complete", isPresented: $showCompleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Complete") {
                HapticManager.shared.success()
                kaydet(changeStatus: true)
            }
        } message: {
            Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this damage record.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var damageInfoSection: some View {
        Section {
            DatePicker("Date", selection: $tarih, displayedComponents: .date)
            DatePicker("Handover Date", selection: $handoverTarihi, displayedComponents: .date)
            
            HStack {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.blue)
                TextField("RES Code (e.g., RES-123)", text: $resKodu)
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
    }
    
    private var photographsSection: some View {
        Section {
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
                                                .frame(width: 120, height: 120)
                                                .cornerRadius(12)
                                                .clipped()
                                        }
                                        
                                        Button {
                                            existingPhotoURLs.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                        .offset(x: 8, y: -8)
                                    }
                                    
                                    Text("Existing \(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            // Display new photos
            let allPhotos = fotograflar + cameraPhotos
            if !allPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(allPhotos.enumerated()), id: \.offset) { index, photo in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .cornerRadius(12)
                                        .clipped()
                                    
                                    Button {
                                        if index < fotograflar.count {
                                            fotograflar.remove(at: index)
                                        } else {
                                            cameraPhotos.remove(at: index - fotograflar.count)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                    }
                                    .offset(x: 8, y: -8)
                                }
                                
                                // First photo is HANDOVER, others are RETURN
                                let photoLabel = index == 0 ? "HANDOVER" : "RETURN"
                                let photoColor = index == 0 ? Color.blue : Color.orange
                                
                                Text(photoLabel)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(photoColor)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    guard !showCamera else { return }
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Gallery")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showCamera)
                
                Button(action: {
                    guard !showImagePicker else { return }
                    showCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                        Text("Take Photo")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showImagePicker)
            }
        }
    }
    
    private var notesSection: some View {
        Section {
            TextEditor(text: $notlar)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                HapticManager.shared.medium()
                showSaveConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                        Text("Saving...")
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save (In Progress)")
                    }
                }
            }
            .buttonStyle(WarningButtonStyle())
            .disabled(resKodu.count <= 4 || km.isEmpty || isUploading)
        } header: {
            Text("Save Current Status")
        } footer: {
            Text("Save the damage record with current status. You can continue editing later.")
        }
    }
    
    private var completeSection: some View {
        Section {
            Button {
                HapticManager.shared.medium()
                showCompleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                        Text("Completing...")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save & Complete")
                    }
                }
            }
            .buttonStyle(SuccessButtonStyle())
            .disabled(resKodu.count <= 4 || km.isEmpty || isUploading)
        } header: {
            Text("Complete Damage Record")
        } footer: {
            Text("Mark the damage record as completed. This action cannot be undone.")
        }
    }
    
    // MARK: - Functions
    
    func saveDraft() {
        let draft = DamageDraft(
            resKodu: resKodu,
            km: km,
            tarih: tarih,
            handoverTarihi: handoverTarihi,
            durum: durum.rawValue,
            notlar: notlar,
            photoCount: fotograflar.count + cameraPhotos.count,
            savedAt: Date()
        )
        DraftManager.shared.saveDamageDraft(for: aracId, draft: draft)
    }
    
    func loadDraft() {
        if let draft = DraftManager.shared.loadDamageDraft(for: aracId) {
            resKodu = draft.resKodu
            km = draft.km
            tarih = draft.tarih
            handoverTarihi = draft.handoverTarihi
            if let status = HasarDurum(rawValue: draft.durum) {
                durum = status
            }
            notlar = draft.notlar
            hasUnsavedChanges = true
        }
    }
    
    func clearDraft() {
        DraftManager.shared.deleteDamageDraft(for: aracId)
    }
    
    func loadExistingPhotos() {
        guard let editingHasar = editingHasar else { return }
        
        // Load existing photos from URLs
        for urlString in editingHasar.fotograflar {
            CachedImageManager.shared.loadImage(urlString) { image in
                DispatchQueue.main.async {
                    if let image = image {
                        self.fotograflar.append(image)
                    }
                }
            }
        }
    }
    
    func kaydet(changeStatus: Bool) {
        // Validate input first
        guard Validators.validateKM(km), Int(km) != nil else {
            errorMessage = "Please enter a valid kilometers (0-999,999)"
            showError = true
            return
        }
        
        // Validate RES code
        guard Validators.validateResCode(resKodu) else {
            errorMessage = "Invalid RES code format. Use RES-XXXX format"
            showError = true
            return
        }
        
        // Validate photos
        let allPhotosToUpload = fotograflar + cameraPhotos
        let photoValidation = Validators.validatePhotos(allPhotosToUpload)
        guard photoValidation.isValid else {
            errorMessage = photoValidation.errorMessage
            showError = true
            return
        }
        
        // Clear any previous errors
        errorMessage = nil
        isUploading = true
        
        // If changeStatus is true, set status to done
        if changeStatus {
            durum = .done
        }
        
        // Compress photos before upload
        let compressedPhotos = ImageManager.shared.processImagesBatch(allPhotosToUpload) { progress in
            DispatchQueue.main.async {
                self.uploadProgress = progress
            }
        }
        
        // IMPORTANT: Combine photos maintaining order - first photo (from any source) is HANDOVER, rest are RETURN
        // Create combined list: gallery photos first, then camera photos (in order they were added)
        let combinedPhotos = compressedPhotos.enumerated().map { (index: $0.offset, photo: $0.element, source: $0.offset < self.fotograflar.count ? "gallery" : "camera") }
        
        // Upload photos with index to maintain order
        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock() // Thread-safe array updates
        
        totalPhotosCount = compressedPhotos.count
        uploadedPhotosCount = 0
        
        // Upload all photos in order: First photo (index 0) is HANDOVER, rest are RETURN
        for item in combinedPhotos {
            group.enter()
            // IMPORTANT: First photo goes to handover folder, rest to return folder
            let photoType = item.index == 0 ? "handover" : "return"
            let path = "hasar_fotograflari/\(photoType)/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(item.photo, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        indexedPhotoURLs.append((index: item.index, url: url))
                        lock.unlock()
                        self.uploadedPhotosCount += 1
                        let progress = Double(self.uploadedPhotosCount) / Double(self.totalPhotosCount)
                        self.uploadProgress = progress
                    } else if let error = error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error at index \(item.index): \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: {
            // Check if there were upload errors
            if !uploadErrors.isEmpty {
                self.isUploading = false
                let failedCount = uploadErrors.count
                let totalCount = compressedPhotos.count
                
                if failedCount == totalCount {
                    // All photos failed
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.")
                } else {
                    // Some photos failed
                    ErrorManager.shared.showError(message: "\(failedCount) out of \(totalCount) photos failed to upload. Damage record will be saved with available photos.")
                }
                return
            }
            
            // Clean RES code to prevent duplication
            var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
            // Ensure only one RES- prefix
            if cleanResKodu.hasPrefix("RES-") {
                let withoutPrefix = cleanResKodu.replacingOccurrences(of: "RES-", with: "")
                cleanResKodu = "RES-\(withoutPrefix)"
            }
            
            // Sort uploaded photos by index (maintains insertion order)
            // IMPORTANT: First photo (index 0) is HANDOVER, all others are RETURN
            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            
            // IMPORTANT: First photo is always HANDOVER (first added photo from any source), rest are RETURN
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
                var updatedHasar = HasarKaydi(
                    aracId: self.aracId,
                    aracPlaka: editingHasar.aracPlaka,
                    tarih: self.tarih,
                    handoverTarihi: self.handoverTarihi,
                    resKodu: cleanResKodu,
                    km: Int(self.km) ?? 0,
                    fotograflar: allPhotos,
                    durum: self.durum,
                    notlar: self.notlar,
                    status: changeStatus ? .completed : .inProgress
                )
                updatedHasar.id = editingHasar.id
                self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)
                
                // 🔔 Send notification for damage record updated
                if let arac = self.arac {
                    let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                    self.notificationManager.sendDamageRecordNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName
                    )
                }
            } else {
                // Yeni hasar ekleme modu
                let newHasar = HasarKaydi(
                    aracId: self.aracId,
                    aracPlaka: self.arac?.plakaFormatli ?? "Unknown",
                    tarih: self.tarih,
                    handoverTarihi: self.handoverTarihi,
                    resKodu: cleanResKodu,
                    km: Int(self.km) ?? 0,
                    fotograflar: allPhotos,
                    durum: self.durum,
                    notlar: self.notlar,
                    status: changeStatus ? .completed : .inProgress
                )
                self.viewModel.hasarEkle(aracId: self.aracId, hasar: newHasar)
                
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
            
            self.isUploading = false
            self.hasUnsavedChanges = false
            
            // Clear draft after successful save
            self.clearDraft()
            
            // Show success toast and dismiss based on action
            if changeStatus {
                // Complete: Show completed toast and dismiss
                self.isSaved = true
                ToastManager.shared.show("✓ Damage Completed", type: .success)
                self.dismiss()
            } else {
                // Save: Show saved toast and let user continue editing
                self.isSaved = false
                if self.isEditMode {
                    ToastManager.shared.show("✓ Damage Saved", type: .success)
                } else {
                    ToastManager.shared.show("✓ Damage Saved (In Progress)", type: .success)
                }
                // Don't dismiss, let user continue editing
                // Keep photos for further editing - don't clear them
            }
        })
    }
}

// MARK: - Supporting Views

struct CameraView: View {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HasarCameraViewController(capturedImage: $capturedImage)
            .ignoresSafeArea()
    }
}

struct HasarCameraViewController: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: HasarCameraViewController
        
        init(_ parent: HasarCameraViewController) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}