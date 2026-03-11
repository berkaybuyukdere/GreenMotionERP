import SwiftUI
import Kingfisher

struct ExitIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    var existingExit: ExitIslemi? = nil // For editing existing exits
    var onExitCompleted: ((ExitIslemi) -> Void)? = nil
    
    @State private var exitTarihi = Date() // Otomatik olarak şu anki tarih ve saat
    @State private var notlar = ""
    @State private var resKodu = ""
    @State private var fotograflar: [UIImage] = [] // Photos from gallery
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera
    @State private var existingPhotoURLs: [String] = [] // Existing remote photos (edit mode)
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var hasUnsavedChanges = false
    @State private var showExitConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var isSaved = false
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var operationFlowState: OperationFlowState = .draft
    @State private var pulseAnimation = false
    @State private var isDoorCustomer = false
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    var body: some View {
        ZStack {
            mainForm
                .blur(radius: showCompletionOverlay ? 8 : 0)
                .allowsHitTesting(!showCompletionOverlay)
            
            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
            .navigationTitle("Check Out Process".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .alert("Unsaved Changes".localized, isPresented: $showExitConfirmation) {
                Button("Continue Editing".localized, role: .cancel) { }
                Button("Discard Changes".localized, role: .destructive) { dismiss() }
            } message: {
                Text("Is the operation complete? Changes have not been saved.".localized)
            }
            .alert("Confirm Complete".localized, isPresented: $showCompleteConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Complete".localized) {
                    guard operationFlowState.canTransition(to: .processing) else {
                        ToastManager.shared.show("Operation is already in progress.".localized, type: .warning)
                        return
                    }
                    operationFlowState = .processing
                    HapticManager.shared.success()
                    completionSucceeded = false
                    pulseAnimation = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = true
                    }
                    kaydet(status: .completed)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this check out operation.".localized)
            }
            .onChange(of: resKodu) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: exitTarihi) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: cameraPhotos) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: isDoorCustomer) { oldValue, newValue in
                hasUnsavedChanges = true
                if newValue {
                    // Door customer flow must be photo-free.
                    fotograflar.removeAll()
                    cameraPhotos.removeAll()
                    existingPhotoURLs.removeAll()
                }
            }
            .onChange(of: showCompletionOverlay) { isVisible in
                if isVisible {
                    dismissKeyboard()
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                } else {
                    pulseAnimation = false
                }
            }
            .onAppear(perform: handleAppear)
            .onDisappear {
                                }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $capturedImage)
            }
    }
    
    private var mainForm: some View {
        Form {
            exitBilgileriSection
            if !isDoorCustomer {
                fotografSection
            }
            completeSection
        }
        .scrollDismissesKeyboard(.immediately)
        .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
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
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body)
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func handleAppear() {
                if let existing = existingExit {
            exitTarihi = existing.exitTarihi
            notlar = existing.notlar
            // RES- prefix'ini kaldır, sadece rakamları göster
            if existing.resKodu.hasPrefix("RES-") {
                resKodu = String(existing.resKodu.dropFirst(4))
            } else {
                resKodu = existing.resKodu
            }
            existingPhotoURLs = existing.fotograflar
        } else {
            // Yeni exit için otomatik olarak şu anki tarih ve saat
            exitTarihi = Date()
        }
    }
    
    private func handleCameraDismiss() {
        if let capturedImage = capturedImage {
            cameraPhotos.append(capturedImage)
            self.capturedImage = nil
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private var exitBilgileriSection: some View {
        Section("Check Out Information".localized) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("Vehicle".localized)
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("Check Out Date".localized, selection: $exitTarihi, displayedComponents: [.date, .hourAndMinute])
            
                Button {
                    isDoorCustomer.toggle()
                } label: {
                    HStack {
                        Image(systemName: isDoorCustomer ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                            .foregroundColor(isDoorCustomer ? .green : .blue)
                        Text("Door Customer".localized)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(isDoorCustomer ? "On".localized : "Off".localized)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isDoorCustomer ? .green : .secondary)
                    }
                }
                
                HStack {
                    Image(systemName: "number.square.fill")
                        .foregroundColor(.blue)
                    Text("RES Code".localized)
                    Spacer()
                    HStack(spacing: 0) {
                        Text("RES-")
                            .foregroundColor(.secondary)
                        TextField("Enter numbers".localized, text: $resKodu)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                }

        }
    }
    
    private var fotografSection: some View {
        Section("Photos".localized) {
                if !existingPhotoURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(existingPhotoURLs.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    KFImage(URL(string: existingPhotoURLs[index]))
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            existingPhotoURLs.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }

                                        Text("Existing".localized)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }

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
                            Text("Complete Check Out".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isUploading)
                .listRowBackground(Color.green.opacity(0.8))
                .foregroundColor(.white)
            } header: {
                Text("Finalize check out".localized)
                    .textCase(nil)
                    .font(.subheadline)
            } footer: {
                Text("Mark this check out as completed and close the form.".localized)
                    .font(.caption)
        }
    }
    
    private var completionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                if completionSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Check Out Completed".localized)
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                    Text("Completing...".localized)
                        .font(.headline)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(18)
            .shadow(radius: 12)
        }
    }
    
    func kaydet(status: ExitStatus) {
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        uploadedPhotoURLs = []
        
        // Combine all photos: gallery photos first, then camera photos (maintain order)
        let allPhotosToUpload = isDoorCustomer ? [] : (fotograflar + cameraPhotos)
        
        // Upload photos with index to maintain order
        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock() // Thread-safe array updates
        
        // Upload all photos preserving their order
        for (index, foto) in allPhotosToUpload.enumerated() {
            group.enter()
            let path = "exit_fotograflari/\(UUID().uuidString).jpg"
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
                    if status == .completed {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.showCompletionOverlay = false
                        }
                    }
                    self.operationFlowState = .failed
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                    return
                } else {
                    // Some photos failed - continue with available photos
                    self.operationFlowState = .failed
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Check out record will be saved with available photos.".localized, failedCount, totalCount))
                }
            }
            
            // Sort uploaded photos by index (maintains insertion order)
            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            
            // Combine existing photos (if editing) with new photos in order
            var finalPhotoURLs: [String] = []
            if self.isDoorCustomer {
                finalPhotoURLs = []
            } else if self.existingExit != nil {
                // Edit mode: Keep remaining existing photos, add new photos
                finalPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
            } else {
                // New exit: All new photos in order
                finalPhotoURLs = sortedNewPhotos
            }
            
            let currentExit: ExitIslemi
            
            if let existingExit = self.existingExit {
                // Update existing exit - createdAt'i koru (gerçek işlem tarihi değişmez)
                var updatedExit = ExitIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    exitTarihi: exitTarihi,
                    fotograflar: finalPhotoURLs,
                    notlar: notlar,
                    resKodu: resKodu.isEmpty ? "" : "RES-\(resKodu)",
                    km: nil,
                    status: status,
                    createdAt: existingExit.createdAt, // Mevcut createdAt'i koru
                    assistantCompanyName: arac.assistantCompanyName,
                    assistantCompanyPhone: arac.assistantCompanyPhone
                )
                updatedExit.id = existingExit.id
                currentExit = updatedExit
                
                // Save to Firebase
                viewModel.exitGuncelle(updatedExit)
                
                print("✅ Exit güncellendi - Status: \(status.rawValue), ID: \(updatedExit.id)")
            } else {
                // Create new exit
                let currentUserId = authManager.currentUser?.uid
                let yeniExit = ExitIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    exitTarihi: exitTarihi,
                    fotograflar: finalPhotoURLs,
                    notlar: notlar,
                    resKodu: resKodu.isEmpty ? "" : "RES-\(resKodu)",
                    km: nil,
                    status: status,
                    createdBy: currentUserId,
                    assistantCompanyName: arac.assistantCompanyName,
                    assistantCompanyPhone: arac.assistantCompanyPhone
                )
                currentExit = yeniExit
                
                // Save to Firebase
                viewModel.exitEkle(yeniExit)
                
                print("✅ Yeni exit eklendi - Status: \(status.rawValue), ID: \(yeniExit.id)")
            }
            
            // 🔔 Send notification for exit processed
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendExitNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
            
            isUploading = false
            hasUnsavedChanges = false
            
            // Show success toast with checkmark icon
            if status == .completed {
                isSaved = true
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    completionSucceeded = true
                }
                ToastManager.shared.show("✓ Check Out Completed".localized, type: .success)
                print("✅ Exit completed - dismissing view")
                // Call the completion callback only when completed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onExitCompleted?(currentExit)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = false
                    }
                    operationFlowState = .completed
                    dismiss()
                }
            } else {
                // For in-progress saves, keep isSaved = false so user can continue editing
                isSaved = false
                ToastManager.shared.show("✓ Check Out Saved (In Progress)".localized, type: .success)
                // Don't call completion callback for save, just let user continue editing
                // Keep photos for further editing - don't clear them
                operationFlowState = .draft
            }
        }
    }
}

