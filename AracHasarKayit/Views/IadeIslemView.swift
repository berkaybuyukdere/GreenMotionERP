import SwiftUI
import Kingfisher

struct IadeIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    var existingIade: IadeIslemi? = nil // For editing existing returns
    var onIadeCompleted: ((IadeIslemi) -> Void)? = nil
    
    @State private var iadeTarihi = Date()
    @State private var notlar = ""
    @State private var fotograflar: [UIImage] = [] // Photos from gallery
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var hasUnsavedChanges = false
    @State private var showExitConfirmation = false
    @State private var showSaveConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var isSaved = false
    @State private var checklist = ReturnChecklist()
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    private var sectionHeaderFont: Font { .system(size: 12, weight: .semibold, design: .default) }
    
    var body: some View {
        mainForm
            .navigationTitle("Return Process".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .alert("Unsaved Changes".localized, isPresented: $showExitConfirmation) {
                Button("Continue Editing".localized, role: .cancel) { }
                Button("Discard Changes".localized, role: .destructive) { dismiss() }
            } message: {
                Text("Is the operation complete? Changes have not been saved.".localized)
            }
            .alert("Confirm Save".localized, isPresented: $showSaveConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Save".localized) {
                    HapticManager.shared.success()
                    kaydet(status: .inProgress)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Save' to save your progress and continue editing later.".localized)
            }
            .alert("Confirm Complete".localized, isPresented: $showCompleteConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Complete".localized) {
                    HapticManager.shared.success()
                    kaydet(status: .completed)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this return operation.".localized)
            }
            .onChange(of: notlar) { _ in hasUnsavedChanges = true }
            .onChange(of: iadeTarihi) { _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _ in hasUnsavedChanges = true }
            .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
            .onChange(of: checklist) { _ in hasUnsavedChanges = true }
            .onAppear(perform: handleAppear)
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $capturedImage)
            }
    }
    
    private var mainForm: some View {
        Form {
            returnIdentitySection
            iadeBilgileriSection
            checklistSection
            notlarSection
            fotografSection
            saveSection
            completeSection
        }
        .listStyle(.insetGrouped)
        .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
    }
    
    private var returnIdentitySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RETURN")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(1.2)
                    Text(arac.plakaFormatli)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(iadeTarihi.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 6)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel".localized) {
                if hasUnsavedChanges && !isSaved {
                    showExitConfirmation = true
                } else {
                    dismiss()
                }
            }
        }
    }
    
    private func handleAppear() {
        if let existing = existingIade {
            iadeTarihi = existing.iadeTarihi
            notlar = existing.notlar
            checklist = existing.checklist ?? ReturnChecklist()
            loadExistingPhotos()
        }
    }
    
    private func handleCameraDismiss() {
        if let capturedImage = capturedImage {
            cameraPhotos.append(capturedImage)
            self.capturedImage = nil
        }
    }
    
    private var iadeBilgileriSection: some View {
        Section("Return Information".localized) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("Vehicle".localized)
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("Return Date".localized, selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var checklistSection: some View {
        Section {
            Toggle("Customer was present".localized, isOn: $checklist.customerPresent)
            Toggle("Customer had no time".localized, isOn: $checklist.customerNoTime)
            Toggle("Key was taken from keybox".localized, isOn: $checklist.keyFromKeybox)
            Toggle("Customer refused to sign".localized, isOn: $checklist.customerRefusedSignature)
            Toggle("Customer left key at office".localized, isOn: $checklist.customerLeftKeyAtOffice)
        } header: {
            Text("Return Checklist".localized)
                .font(sectionHeaderFont)
        } footer: {
            Text("Optional: You can complete return without selecting these items.".localized)
                .font(.caption)
        }
    }
    
    private var notlarSection: some View {
        Section("Notes".localized) {
            TextEditor(text: $notlar)
                .frame(height: 100)
        }
    }
    
    private var fotografSection: some View {
        Section("Photos".localized) {
                if !allPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // Gallery photos
                            ForEach(fotograflar.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: fotograflar[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            fotograflar.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        
                                        Text("Gallery".localized)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    .padding(4)
                                }
                            }
                            
                            // Camera photos
                            ForEach(cameraPhotos.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: cameraPhotos[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            cameraPhotos.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        
                                        Text("Camera".localized)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        guard !showCamera else { return }
                        showImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Gallery".localized)
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
                            Text("Take Photo".localized)
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
    
    private var saveSection: some View {
        Section {
            // Save button (saves as in-progress)
            Button {
                HapticManager.shared.medium()
                showSaveConfirmation = true
            } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Uploading Photos...".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save (In Progress)".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isUploading)
                .listRowBackground(Color.black)
                .foregroundColor(.white)
            } header: {
                Text("Save without completing".localized)
                    .textCase(nil)
                    .font(.subheadline)
            } footer: {
                Text("Save your progress to continue later. The return will remain 'In Progress'.".localized)
                    .font(.caption)
        }
    }
    
    private var completeSection: some View {
        Section {
            // Complete button
            Button {
                HapticManager.shared.medium()
                showCompleteConfirmation = true
            } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Uploading Photos...".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete Return".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isUploading)
                .listRowBackground(Color(white: 0.22))
                .foregroundColor(.white)
            } header: {
                Text("Finalize return".localized)
                    .textCase(nil)
                    .font(.subheadline)
            } footer: {
                Text("Mark this return as completed and close the form.".localized)
                    .font(.caption)
        }
    }
    
    func loadExistingPhotos() {
        guard let existingIade = existingIade else { return }
        
        // Load existing photos from URLs using Kingfisher
        for urlString in existingIade.fotograflar {
            guard let url = URL(string: urlString) else { continue }
            KingfisherManager.shared.retrieveImage(with: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let value):
                        self.fotograflar.append(value.image)
                    case .failure(let error):
                        print("❌ Failed to load image: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func kaydet(status: IadeStatus) {
        isUploading = true
        uploadedPhotoURLs = []
        
        // Combine all photos: gallery photos first, then camera photos (maintain order)
        let allPhotosToUpload = fotograflar + cameraPhotos
        
        // Upload photos with index to maintain order
        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock() // Thread-safe array updates
        
        // Upload all photos preserving their order
        for (index, foto) in allPhotosToUpload.enumerated() {
            group.enter()
            let path = "iade_fotograflari/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        indexedPhotoURLs.append((index: index, url: url))
                        lock.unlock()
                    } else if let error = error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error at index \(index): \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Check if there were upload errors
            if !uploadErrors.isEmpty {
                self.isUploading = false
                let failedCount = uploadErrors.count
                let totalCount = allPhotosToUpload.count
                
                if failedCount == totalCount {
                    // All photos failed
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                    return
                } else {
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Return record will be saved with available photos.".localized, failedCount, totalCount))
                }
            }
            
            // Sort uploaded photos by index (maintains insertion order)
            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            
            // Combine existing photos (if editing) with new photos in order
            var finalPhotoURLs: [String] = []
            if let existingIade = self.existingIade {
                // Edit mode: Keep existing photos, add new photos
                finalPhotoURLs = existingIade.fotograflar + sortedNewPhotos
            } else {
                // New iade: All new photos in order
                finalPhotoURLs = sortedNewPhotos
            }
            
            let currentIade: IadeIslemi
            
            if let existingIade = self.existingIade {
                // Update existing iade - createdAt'i koru (gerçek işlem tarihi değişmez)
                var updatedIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: finalPhotoURLs,
                    notlar: notlar,
                    status: status,
                    createdAt: existingIade.createdAt, // Mevcut createdAt'i koru
                    checklist: self.checklist.hasAnySelection ? self.checklist : nil
                )
                updatedIade.id = existingIade.id
                currentIade = updatedIade
                
                // Save to Firebase
                viewModel.iadeGuncelle(updatedIade)
                
                print("✅ İade güncellendi - Status: \(status.rawValue), ID: \(updatedIade.id)")
            } else {
                // Create new iade
                let currentUserId = authManager.currentUser?.uid
                let yeniIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: finalPhotoURLs,
                    notlar: notlar,
                    status: status,
                    createdBy: currentUserId,
                    checklist: self.checklist.hasAnySelection ? self.checklist : nil
                )
                currentIade = yeniIade
                
                // Save to Firebase
                viewModel.iadeEkle(yeniIade)
                
                print("✅ Yeni iade eklendi - Status: \(status.rawValue), ID: \(yeniIade.id)")
            }
            
            // 🔔 Send notification for return processed
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendReturnNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
            
            isUploading = false
            hasUnsavedChanges = false
            
            // Show success toast with checkmark icon
            if status == .completed {
                isSaved = true
                ToastManager.shared.show("✓ Return Completed".localized, type: .success)
                print("✅ Return completed - dismissing view")
                // Call the completion callback only when completed
                onIadeCompleted?(currentIade)
                // Small delay to ensure Firebase save completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
                }
            } else {
                // For in-progress saves, keep isSaved = false so user can continue editing
                isSaved = false
                ToastManager.shared.show("✓ Return Saved (In Progress)".localized, type: .success)
                // Don't call completion callback for save, just let user continue editing
                // Keep photos for further editing - don't clear them
            }
        }
    }
}

// MARK: - Camera View (using shared CameraView from HasarEkleView)

// MARK: - Edit View for Existing Return
