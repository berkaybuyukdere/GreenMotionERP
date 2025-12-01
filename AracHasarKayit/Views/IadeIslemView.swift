import SwiftUI

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
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    var body: some View {
        mainForm
            .navigationTitle("Return Process")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .alert("Unsaved Changes", isPresented: $showExitConfirmation) {
                Button("Continue Editing", role: .cancel) { }
                Button("Discard Changes", role: .destructive) { dismiss() }
            } message: {
                Text("Is the operation complete? Changes have not been saved.")
            }
            .alert("Confirm Save", isPresented: $showSaveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    HapticManager.shared.success()
                    kaydet(status: .inProgress)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Save' to save your progress and continue editing later.")
            }
            .alert("Confirm Complete", isPresented: $showCompleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Complete") {
                    HapticManager.shared.success()
                    kaydet(status: .completed)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this return operation.")
            }
            .onChange(of: notlar) { _ in hasUnsavedChanges = true }
            .onChange(of: iadeTarihi) { _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _ in hasUnsavedChanges = true }
            .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
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
            iadeBilgileriSection
            notlarSection
            fotografSection
            saveSection
            completeSection
        }
        .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
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
        Section("İade Bilgileri") {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.purple)
                    Text("Araç")
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("İade Tarihi", selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var notlarSection: some View {
        Section("Notlar") {
            TextEditor(text: $notlar)
                .frame(height: 100)
        }
    }
    
    private var fotografSection: some View {
        Section("Fotoğraflar") {
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
                                        
                                        Text("Gallery")
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
                                        
                                        Text("Camera")
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
                            Text("Uploading Photos...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save (In Progress)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isUploading)
                .listRowBackground(Color.blue.opacity(0.8))
                .foregroundColor(.white)
            } header: {
                Text("Save without completing")
                    .textCase(nil)
                    .font(.subheadline)
            } footer: {
                Text("Save your progress to continue later. The return will remain 'In Progress'.")
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
                            Text("Uploading Photos...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete Return")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isUploading)
                .listRowBackground(Color.green.opacity(0.8))
                .foregroundColor(.white)
            } header: {
                Text("Finalize return")
                    .textCase(nil)
                    .font(.subheadline)
            } footer: {
                Text("Mark this return as completed and close the form.")
                    .font(.caption)
        }
    }
    
    func loadExistingPhotos() {
        guard let existingIade = existingIade else { return }
        
        // Load existing photos from URLs
        for urlString in existingIade.fotograflar {
            CachedImageManager.shared.loadImage(urlString) { image in
                DispatchQueue.main.async {
                    if let image = image {
                        self.fotograflar.append(image)
                    }
                }
            }
        }
    }
    
    func kaydet(status: IadeStatus) {
        isUploading = true
        uploadedPhotoURLs = []
        
        // Combine all photos: gallery photos first, then camera photos
        let allPhotosToUpload = fotograflar + cameraPhotos
        
        let group = DispatchGroup()
        var uploadErrors: [Error] = []
        let lock = NSLock()
        
        for foto in allPhotosToUpload {
            group.enter()
            let path = "iade_fotograflari/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        uploadedPhotoURLs.append(url)
                        lock.unlock()
                    } else if let error = error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error: \(error.localizedDescription)")
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
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.")
                    return
                } else {
                    // Some photos failed - continue with available photos
                    ErrorManager.shared.showError(message: "\(failedCount) out of \(totalCount) photos failed to upload. Return record will be saved with available photos.")
                }
            }
            
            let currentIade: IadeIslemi
            
            if let existingIade = self.existingIade {
                // Update existing iade
                var updatedIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: uploadedPhotoURLs,
                    notlar: notlar,
                    status: status
                )
                updatedIade.id = existingIade.id
                currentIade = updatedIade
                
                // Save to Firebase
                viewModel.iadeGuncelle(updatedIade)
                
                print("✅ İade güncellendi - Status: \(status.rawValue), ID: \(updatedIade.id)")
            } else {
                // Create new iade
                let yeniIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: uploadedPhotoURLs,
                    notlar: notlar,
                    status: status
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
                ToastManager.shared.show("✓ Return Completed", type: .success)
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
                ToastManager.shared.show("✓ Return Saved (In Progress)", type: .success)
                // Don't call completion callback for save, just let user continue editing
                // Keep photos for further editing - don't clear them
            }
        }
    }
}

// MARK: - Camera View (using shared CameraView from HasarEkleView)

// MARK: - Edit View for Existing Return
