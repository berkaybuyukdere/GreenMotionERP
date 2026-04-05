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
    @State private var isVehicleParked = false
    /// After the first save in this session, updates reuse this record (avoids duplicate exits on In Progress re-saves).
    @State private var committedExit: ExitIslemi?

    // Photo preview state
    @State private var urlPreviewURLs: [String] = []
    @State private var urlPreviewSheet: PhotoGallerySheetItem?
    @State private var localPreviewImages: [UIImage] = []
    @State private var localPreviewSheet: PhotoGallerySheetItem?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
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
                    let targetStatus = resolvedStatusForCompletion()
                    operationFlowState = .processing
                    HapticManager.shared.success()
                    completionSucceeded = false
                    pulseAnimation = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = true
                    }
                    kaydet(status: targetStatus)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this check out operation.".localized)
            }
            .onChange(of: resKodu) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: exitTarihi) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: cameraPhotos) { oldValue, newValue in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { oldValue, newValue in hasUnsavedChanges = true }
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
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $capturedImage)
            }
            .fullScreenCover(item: $urlPreviewSheet) { item in
                NativePhotoGalleryView(urlStrings: urlPreviewURLs, initialIndex: item.startIndex)
            }
            .fullScreenCover(item: $localPreviewSheet) { item in
                NativePhotoGalleryView(images: localPreviewImages, initialIndex: item.startIndex)
            }
    }
    
    private var mainForm: some View {
        ScrollViewReader { proxy in
            Form {
                exitBilgileriSection
                    .id("formTop")
                fotografSection
                completeSection
            }
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .onChange(of: errorManager.currentError != nil) { hasError in
                if hasError {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("formTop", anchor: .top)
                    }
                }
            }
            .onChange(of: toastManager.toast?.id) { _ in
                if toastManager.toast?.type == .error || toastManager.toast?.type == .warning {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("formTop", anchor: .top)
                    }
                }
            }
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
            isVehicleParked = existing.status == .parked
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
                
                Button {
                    isVehicleParked.toggle()
                    hasUnsavedChanges = true
                } label: {
                    HStack {
                        Image(systemName: isVehicleParked ? "car.fill" : "car")
                            .foregroundColor(isVehicleParked ? .white : .purple)
                        Text("Vehicle Parked".localized)
                            .foregroundColor(isVehicleParked ? .white : .purple)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: isVehicleParked ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isVehicleParked ? .white : .purple)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(isVehicleParked ? Color.purple : Color.purple.opacity(0.12))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

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
                                        .onTapGesture {
                                            urlPreviewURLs = existingPhotoURLs
                                            urlPreviewSheet = PhotoGallerySheetItem(startIndex: index)
                                        }

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
                                        .onTapGesture {
                                            localPreviewImages = fotograflar + cameraPhotos
                                            localPreviewSheet = PhotoGallerySheetItem(startIndex: index)
                                        }
                                    
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
                                        .onTapGesture {
                                            localPreviewImages = fotograflar + cameraPhotos
                                            localPreviewSheet = PhotoGallerySheetItem(startIndex: fotograflar.count + index)
                                        }
                                    
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
    
    private func applyExitSaveAfterUploads(
        status: ExitStatus,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        var finalPhotoURLs: [String] = []
        let editingExistingSession = self.committedExit != nil || self.existingExit != nil
        if editingExistingSession {
            finalPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
        } else {
            finalPhotoURLs = sortedNewPhotos
        }

        let currentExit: ExitIslemi
        let baseForUpdate = self.committedExit ?? self.existingExit

        if let base = baseForUpdate {
            var updatedExit = ExitIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                exitTarihi: exitTarihi,
                fotograflar: finalPhotoURLs,
                notlar: notlar,
                resKodu: resKodu.isEmpty ? "" : "RES-\(resKodu)",
                km: nil,
                status: status,
                createdAt: base.createdAt,
                createdBy: base.createdBy,
                assistantCompanyName: arac.assistantCompanyName,
                assistantCompanyPhone: arac.assistantCompanyPhone
            )
            updatedExit.id = base.id
            currentExit = updatedExit

            viewModel.exitGuncelle(updatedExit)

            print("✅ Exit güncellendi - Status: \(status.rawValue), ID: \(updatedExit.id)")
        } else {
            let currentUserId = authManager.currentUser?.uid
            var yeniExit = ExitIslemi(
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
            yeniExit.id = stableNewDocumentId
            currentExit = yeniExit

            viewModel.exitEkle(yeniExit)

            print("✅ Yeni exit eklendi - Status: \(status.rawValue), ID: \(yeniExit.id)")
        }

        if status == .inProgress {
            committedExit = currentExit
            existingPhotoURLs = finalPhotoURLs
            fotograflar = []
            cameraPhotos = []
        }

        if !usedOfflineMediaQueue {
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendExitNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
        }

        isUploading = false
        hasUnsavedChanges = false

        if status == .completed {
            isSaved = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                completionSucceeded = true
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendExitNotification
            print("✅ Exit completed - dismissing view")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                onExitCompleted?(currentExit)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionOverlay = false
                }
                operationFlowState = .completed
                dismiss()
            }
        } else if status == .parked {
            isSaved = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                completionSucceeded = true
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendExitNotification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                onExitCompleted?(currentExit)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionOverlay = false
                }
                operationFlowState = .completed
                dismiss()
            }
        } else {
            isSaved = false
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Remaining photos will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendExitNotification
            operationFlowState = .draft
        }
    }

    func kaydet(status: ExitStatus) {
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        uploadedPhotoURLs = []

        let stableDocumentId = (committedExit ?? existingExit)?.id ?? UUID()

        let allPhotosToUpload = fotograflar + cameraPhotos

        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock()

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
            let totalCount = allPhotosToUpload.count
            let failedCount = uploadErrors.count
            let allPhotosFailed = totalCount > 0 && failedCount == totalCount
            let errorsLookTransient = uploadErrors.allSatisfy(OfflineSyncDiagnostics.isLikelyTransientNetworkFailure)
            let canOfflineSinkPhotos = allPhotosFailed && (errorsLookTransient || !OfflineModeManager.shared.isOnline)

            if !uploadErrors.isEmpty {
                if allPhotosFailed {
                    if !canOfflineSinkPhotos {
                        self.isUploading = false
                        if status == .completed {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.showCompletionOverlay = false
                            }
                        }
                        self.operationFlowState = .failed
                        ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                        return
                    }
                } else {
                    self.isUploading = false
                    self.operationFlowState = .failed
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Check out record will be saved with available photos.".localized, failedCount, totalCount))
                }
            }

            if canOfflineSinkPhotos {
                OfflineMediaSyncCoordinator.shared.enqueueExitMedia(documentId: stableDocumentId, images: allPhotosToUpload) { ok in
                    guard ok else {
                        self.isUploading = false
                        self.operationFlowState = .failed
                        ErrorManager.shared.showError(message: "Could not save photos on this device for later upload.".localized)
                        return
                    }
                    self.applyExitSaveAfterUploads(
                        status: status,
                        sortedNewPhotos: [],
                        usedOfflineMediaQueue: true,
                        stableNewDocumentId: stableDocumentId
                    )
                }
                return
            }

            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            self.applyExitSaveAfterUploads(
                status: status,
                sortedNewPhotos: sortedNewPhotos,
                usedOfflineMediaQueue: false,
                stableNewDocumentId: stableDocumentId
            )
        }
    }
    
    private func resolvedStatusForCompletion() -> ExitStatus {
        let trimmedRes = resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVehicleParked && trimmedRes.isEmpty {
            return .parked
        }
        return .completed
    }
}

