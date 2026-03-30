import SwiftUI
import Kingfisher

struct HasarEkleView: View {
    private static let checkoutDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let aracId: UUID
    let editingHasar: HasarKaydi? // nil = yeni hasar, dolu = düzenleme modu
    
    @State private var tarih = Date()
    @State private var handoverTarihi = Date()
    @State private var resKodu = "" // Only numbers, RES- prefix shown in UI
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
    @State private var showCompleteConfirmation = false
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var operationFlowState: OperationFlowState = .draft
    @State private var pulseAnimation = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoSaveTimer: Timer?
    /// After first in-session save (new damage, In Progress), further saves update this record instead of appending another.
    @State private var committedHasar: HasarKaydi?
    
    // Exit/Check out photo selection states
    @State private var selectedExitPhotoURL: String? // Selected photo from exit
    @State private var selectedExitPhotoImage: UIImage? // Downloaded image
    @State private var showExitPhotoSelector = false // Sheet to show photo selector
    @State private var selectedCheckoutId: UUID? // Selected check out record for handover defaults
    @State private var isCheckoutListExpanded = false

    // Photo preview state
    @State private var urlPreviewURLs: [String] = []
    @State private var urlPreviewIndex: Int = 0
    @State private var showURLPreview = false
    @State private var localPreviewImages: [UIImage] = []
    @State private var localPreviewIndex: Int = 0
    @State private var showLocalPreview = false
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var isEditMode: Bool {
        editingHasar != nil
    }
    
    private var sessionHasPersistedDamage: Bool {
        committedHasar != nil || editingHasar != nil
    }
    
    var latestExit: ExitIslemi? {
        let exits = viewModel.exitIslemleri.filter { $0.aracId == aracId }
        let drafts = exits.filter { $0.status != .completed }
        if let bestDraft = drafts.max(by: { $0.createdAt > $1.createdAt }) {
            return bestDraft
        }
        let completed = exits.filter { $0.status == .completed }
        return completed.max(by: { $0.createdAt > $1.createdAt })
    }
    
    var availableCheckouts: [ExitIslemi] {
        viewModel.exitIslemleri
            .filter { $0.aracId == aracId }
            .sorted { $0.exitTarihi > $1.exitTarihi }
    }
    
    var selectedCheckout: ExitIslemi? {
        guard let selectedCheckoutId else { return nil }
        return availableCheckouts.first(where: { $0.id == selectedCheckoutId })
    }
    
    init(aracId: UUID, editingHasar: HasarKaydi? = nil) {
        self.aracId = aracId
        self.editingHasar = editingHasar
        
        if let hasar = editingHasar {
            _tarih = State(initialValue: hasar.tarih)
            _handoverTarihi = State(initialValue: hasar.handoverTarihi)
            // Extract numbers from RES code (remove RES- prefix)
            let resCodeNumbers = hasar.resKodu.replacingOccurrences(of: "RES-", with: "")
            _resKodu = State(initialValue: resCodeNumbers)
            _km = State(initialValue: String(hasar.km))
            _durum = State(initialValue: hasar.durum)
            _existingPhotoURLs = State(initialValue: hasar.fotograflar)
        }
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                ScrollViewReader { proxy in
                    Form {
                        Color.clear
                            .frame(height: 1)
                            .id("formTop")
                        if isUploading && uploadProgress > 0 {
                            Section {
                                UploadProgressView(
                                    progress: uploadProgress,
                                    currentItem: uploadedPhotosCount,
                                    totalItems: totalPhotosCount,
                                    message: "Uploading photos...".localized
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
                        completeSection
                    }
                    .onChange(of: errorMessage) { message in
                        if message != nil {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("formTop", anchor: .top)
                            }
                        }
                    }
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
                .navigationTitle(isEditMode ? "Edit Damage".localized : "")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            }
            .blur(radius: showCompletionOverlay ? 8 : 0)
            .allowsHitTesting(!showCompletionOverlay)
            
            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
        .onChange(of: resKodu) { oldValue, newValue in
            hasUnsavedChanges = true
            // Ensure only numbers are entered (no RES- prefix in state)
            let filtered = newValue.filter { $0.isNumber }
            // Limit to maximum 8 digits
            let limited = String(filtered.prefix(8))
            if limited != resKodu {
                resKodu = limited
            }
        }
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
        .onAppear {
                        // Load existing hasar data if editing
            if let editingHasar = editingHasar {
                // Extract numbers from RES code (remove RES- prefix)
                let resCodeNumbers = editingHasar.resKodu.replacingOccurrences(of: "RES-", with: "")
                resKodu = resCodeNumbers
                km = String(editingHasar.km)
                tarih = editingHasar.tarih
                handoverTarihi = editingHasar.handoverTarihi
                durum = editingHasar.durum
                notlar = editingHasar.notlar
                existingPhotoURLs = editingHasar.fotograflar
            } else {
                // Try to load draft for new records
                loadDraft()
                if !hasUnsavedChanges {
                    applyLatestExitDefaultsIfNeeded()
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
        .sheet(isPresented: $showExitPhotoSelector) {
            ExitPhotoSelectorView(
                exitPhotos: selectedCheckout?.fotograflar ?? [],
                selectedPhotoURL: $selectedExitPhotoURL,
                selectedPhotoImage: $selectedExitPhotoImage
            )
        }
        .fullScreenCover(isPresented: $showURLPreview) {
            NativePhotoGalleryView(urlStrings: urlPreviewURLs, initialIndex: urlPreviewIndex)
        }
        .fullScreenCover(isPresented: $showLocalPreview) {
            NativePhotoGalleryView(images: localPreviewImages, initialIndex: localPreviewIndex)
        }
        .alert("Unsaved Changes".localized, isPresented: $showExitConfirmation) {
            Button("Discard Changes".localized, role: .destructive) {
                dismiss()
            }
            Button("Continue Editing".localized, role: .cancel) { }
        } message: {
            Text("Is the operation complete? Changes have not been saved.".localized)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) {
                                        if hasUnsavedChanges || isUploading {
                        showExitConfirmation = true
                    } else {
                        dismiss()
                    }
                }
            }
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
                kaydet(changeStatus: true)
            }
        } message: {
            Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this damage record.".localized)
        }
    }
    
    // MARK: - Computed Properties
    
    private var damageInfoSection: some View {
        Section {
            if !isEditMode, !availableCheckouts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCheckoutListExpanded.toggle()
                        }
                        HapticManager.shared.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 20, weight: .semibold))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check Out".localized)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text(selectedCheckout.map(checkoutLabel(for:)) ?? "Select Check Out".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(availableCheckouts.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                            
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isCheckoutListExpanded ? 180 : 0))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if isCheckoutListExpanded {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                            ForEach(availableCheckouts) { checkout in
                                Button {
                                    selectedCheckoutId = checkout.id
                                    applySelectedCheckoutDefaults()
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isCheckoutListExpanded = false
                                    }
                                    HapticManager.shared.selection()
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(selectedCheckoutId == checkout.id ? Color.blue : Color.secondary.opacity(0.28))
                                            .frame(width: 9, height: 9)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(checkout.resKodu.isEmpty ? "RES-".localized : checkout.resKodu)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            Text(checkoutDateText(for: checkout))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("\(checkout.fotograflar.count)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        if selectedCheckoutId == checkout.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedCheckoutId == checkout.id ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                        }
                        .frame(maxHeight: 220)
                        .scrollIndicators(.hidden)
                        .transition(.opacity)
                    }
                }
            }
            
            DatePicker("Date".localized, selection: $tarih, displayedComponents: .date)
            DatePicker("Handover Date".localized, selection: $handoverTarihi, displayedComponents: .date)
            
            HStack {
                Image(systemName: "number.circle.fill")
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
            
            HStack {
                Image(systemName: "gauge.medium.badge.plus")
                    .foregroundColor(.blue)
                Text("Kilometer".localized)
                Spacer()
                TextField("Enter kilometers".localized, text: $km)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.secondary)
            }
            
            Picker("Status".localized, selection: $durum) {
                ForEach(HasarDurum.allCases, id: \.self) { status in
                    Text(status.displayTitle).tag(status)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func removeSelectedCheckoutPhoto() {
        selectedExitPhotoURL = nil
        selectedExitPhotoImage = nil
        hasUnsavedChanges = true
        HapticManager.shared.selection()
    }
    
    private func removeExistingPhoto(at index: Int) {
        guard existingPhotoURLs.indices.contains(index) else { return }
        existingPhotoURLs.remove(at: index)
        hasUnsavedChanges = true
        HapticManager.shared.selection()
    }
    
    private func removeNewPhoto(at combinedIndex: Int) {
        if fotograflar.indices.contains(combinedIndex) {
            fotograflar.remove(at: combinedIndex)
            hasUnsavedChanges = true
            HapticManager.shared.selection()
            return
        }
        
        let cameraIndex = combinedIndex - fotograflar.count
        guard cameraPhotos.indices.contains(cameraIndex) else { return }
        cameraPhotos.remove(at: cameraIndex)
        hasUnsavedChanges = true
        HapticManager.shared.selection()
    }
    
    private var photographsSection: some View {
        Section {
            if !isEditMode, let checkoutForPhotos = (selectedCheckout ?? latestExit), !checkoutForPhotos.fotograflar.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        showExitPhotoSelector = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.stack")
                            Text("Select from selected check out photos".localized)
                            Spacer()
                            Text("\(checkoutForPhotos.fotograflar.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    if let selectedImage = selectedExitPhotoImage {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .cornerRadius(12)
                                    .clipped()
                                
                                Button {
                                    removeSelectedCheckoutPhoto()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                }
                                .offset(x: 8, y: -8)
                            }
                            
                            Text("Selected from check out (will be HANDOVER)".localized)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            // Display existing photos (in edit mode)
            if !existingPhotoURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Existing Photos".localized)
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
                                        .onTapGesture {
                                            urlPreviewURLs = existingPhotoURLs
                                            urlPreviewIndex = index
                                            showURLPreview = true
                                        }
                                        
                                        Button {
                                            removeExistingPhoto(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                        .offset(x: 8, y: -8)
                                    }
                                    
                                    Text(String(format: "Existing %d".localized, index + 1))
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
                                        .onTapGesture {
                                            localPreviewImages = allPhotos
                                            localPreviewIndex = index
                                            showLocalPreview = true
                                        }
                                    
                                    Button {
                                        removeNewPhoto(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                    }
                                    .offset(x: 8, y: -8)
                                }
                                
                                // If a check out photo is selected, that photo is always HANDOVER.
                                // Therefore all newly added photos are RETURN.
                                let isCheckoutHandoverSelected = selectedExitPhotoImage != nil
                                let isHandoverLabel = !isCheckoutHandoverSelected && index == 0
                                let photoLabel = isHandoverLabel ? "HANDOVER".localized : "RETURN".localized
                                let photoColor = isHandoverLabel ? Color.blue : Color.orange
                                
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
                
                Text("Note: The first uploaded photo will be handover, others will be return.".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
    
    private var completeSection: some View {
        Section {
            // RES code: 1-8 digits, KM: not empty
            let isResCodeValid = !resKodu.isEmpty && resKodu.count >= 1 && resKodu.count <= 8
            let allPhotos = fotograflar + cameraPhotos
            let selectedExitCount = selectedExitPhotoImage == nil ? 0 : 1
            let hasEnoughPhotos = (allPhotos.count + selectedExitCount) >= 2
            let isDisabled = !isResCodeValid || km.isEmpty || !hasEnoughPhotos || isUploading
            Button {
                guard !isDisabled else { return }
                HapticManager.shared.medium()
                showCompleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                        Text("Completing...".localized)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save & Complete".localized)
                    }
                }
            }
            .buttonStyle(SuccessButtonStyle())
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1.0)
        } header: {
            Text("Complete Damage Record".localized)
        } footer: {
            Text("Mark the damage record as completed. Requires at least 2 photos (1 handover + 1 return). This action cannot be undone.".localized)
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
                    Text("Damage Completed".localized)
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

    private func applyLatestExitDefaultsIfNeeded() {
        guard let latestExit = latestExit else { return }
        if selectedCheckoutId == nil {
            selectedCheckoutId = latestExit.id
        }
        applySelectedCheckoutDefaults()
    }
    
    private func applySelectedCheckoutDefaults() {
        guard let checkout = selectedCheckout ?? latestExit else { return }
        
        handoverTarihi = checkout.exitTarihi
        
        let rawRes = checkout.resKodu.hasPrefix("RES-")
            ? String(checkout.resKodu.dropFirst(4))
            : checkout.resKodu
        let cleanedRes = rawRes.filter { $0.isNumber }
        if !cleanedRes.isEmpty {
            resKodu = cleanedRes
        }
        
        if km.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let checkoutKM = checkout.km {
            km = String(checkoutKM)
        }
        
        selectedExitPhotoURL = nil
        selectedExitPhotoImage = nil
    }
    
    private func checkoutLabel(for checkout: ExitIslemi) -> String {
        let dateText = checkoutDateText(for: checkout)
        let resText = checkout.resKodu.isEmpty ? "-" : checkout.resKodu
        return "\(resText) • \(dateText)"
    }
    
    private func checkoutDateText(for checkout: ExitIslemi) -> String {
        Self.checkoutDateFormatter.string(from: checkout.exitTarihi)
    }

    private func preloadExitPhoto(url: String) {
        StorageImageLoader.shared.loadImage(from: url) { loadedImage in
            if let loadedImage {
                self.selectedExitPhotoImage = loadedImage
            } else {
                print("❌ Failed to preload latest exit photo")
            }
        }
    }

    private func applyHasarSaveAfterUploads(
        changeStatus: Bool,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        let hadPersistedDamageBeforeSave = self.committedHasar != nil || self.editingHasar != nil

        var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
        if cleanResKodu.hasPrefix("RES-") {
            let withoutPrefix = cleanResKodu.replacingOccurrences(of: "RES-", with: "")
            cleanResKodu = "RES-\(withoutPrefix)"
        }

        var allPhotos: [String] = []
        if self.sessionHasPersistedDamage {
            allPhotos = self.existingPhotoURLs + sortedNewPhotos
        } else {
            allPhotos = sortedNewPhotos
        }

        let baseHasar = self.committedHasar ?? self.editingHasar
        let savedHasar: HasarKaydi

        if let base = baseHasar {
            var updatedHasar = HasarKaydi(
                aracId: self.aracId,
                aracPlaka: self.arac?.plakaFormatli ?? base.aracPlaka,
                tarih: self.tarih,
                handoverTarihi: self.handoverTarihi,
                resKodu: cleanResKodu,
                km: Int(self.km) ?? 0,
                fotograflar: allPhotos,
                durum: self.durum,
                notlar: self.notlar,
                status: changeStatus ? .completed : .inProgress,
                createdBy: base.createdBy
            )
            updatedHasar.id = base.id
            savedHasar = updatedHasar

            self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)

            print("✅ Hasar güncellendi - Status: \(updatedHasar.status.rawValue), RES: \(cleanResKodu)")

            if let arac = self.arac {
                let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                self.notificationManager.sendDamageRecordNotification(
                    carPlate: arac.plaka,
                    resCode: cleanResKodu,
                    userName: userName
                )
            }
        } else {
            let currentUserId = self.authManager.currentUser?.uid
            var newHasar = HasarKaydi(
                aracId: self.aracId,
                aracPlaka: self.arac?.plakaFormatli ?? "Unknown",
                tarih: self.tarih,
                handoverTarihi: self.handoverTarihi,
                resKodu: cleanResKodu,
                km: Int(self.km) ?? 0,
                fotograflar: allPhotos,
                durum: self.durum,
                notlar: self.notlar,
                status: changeStatus ? .completed : .inProgress,
                createdBy: currentUserId
            )
            newHasar.id = stableNewDocumentId
            savedHasar = newHasar

            self.viewModel.hasarEkle(aracId: self.aracId, hasar: newHasar)

            print("✅ Yeni hasar eklendi - Status: \(newHasar.status.rawValue), RES: \(cleanResKodu)")

            if let arac = self.arac {
                let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                self.notificationManager.sendDamageRecordNotification(
                    carPlate: arac.plaka,
                    resCode: cleanResKodu,
                    userName: userName
                )
            }
        }

        if !changeStatus {
            committedHasar = savedHasar
            existingPhotoURLs = allPhotos
            fotograflar = []
            cameraPhotos = []
            selectedExitPhotoImage = nil
            selectedExitPhotoURL = nil
        }

        HapticManager.shared.success()

        self.isUploading = false
        self.hasUnsavedChanges = false

        self.clearDraft()

        if changeStatus {
            self.isSaved = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                self.completionSucceeded = true
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Damage photos will upload when you are back online.".localized, type: .success)
            } else {
                ToastManager.shared.show("✓ Damage Completed".localized, type: .success)
            }
            print("✅ Damage completed - dismissing view")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                self.operationFlowState = .completed
                self.dismiss()
            }
        } else {
            self.isSaved = false
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Remaining damage photos will upload when you are back online.".localized, type: .success)
            } else if hadPersistedDamageBeforeSave {
                ToastManager.shared.show("✓ Damage Saved".localized, type: .success)
            } else {
                ToastManager.shared.show("✓ Damage Saved (In Progress)".localized, type: .success)
            }
            self.operationFlowState = .draft
        }
    }
    
    func kaydet(changeStatus: Bool) {
        // Validate input first
        guard Validators.validateKM(km), Int(km) != nil else {
            if changeStatus {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
            }
            errorMessage = "Please enter a valid kilometers (0-999,999)".localized
            showError = true
            return
        }
        
        // Validate RES code (1-8 digits, maximum 8)
        guard Validators.validateResCode(resKodu) else {
            if changeStatus {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
            }
            errorMessage = "RES code must be 1-8 digits (maximum 8)".localized
            showError = true
            return
        }
        
        // For complete: require at least 2 photos (1 handover + at least 1 return)
        if changeStatus {
            let allPhotosToCheck = fotograflar + cameraPhotos
            let selectedExitCount = selectedExitPhotoURL == nil ? 0 : 1
            let existingCount = existingPhotoURLs.count
            let totalAvailableCount = existingCount + allPhotosToCheck.count + selectedExitCount
            let hasEnoughPhotos = totalAvailableCount >= 2
            
            guard hasEnoughPhotos else {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
                errorMessage = "Complete requires at least 2 photos (1 handover + 1 return)".localized
                showError = true
                return
            }
        }
        
        // Ensure selected checkout photo is fully resolved before upload.
        if selectedExitPhotoURL != nil && selectedExitPhotoImage == nil {
            loadSelectedExitPhotoAndRetrySave(changeStatus: changeStatus)
            return
        }
        
        // Prepare all photos to upload
        var allPhotosToUpload: [UIImage] = []
        if let selectedExitPhotoImage {
            // Keep selected latest check out photo first so it is treated as handover.
            allPhotosToUpload.append(selectedExitPhotoImage)
        }
        allPhotosToUpload.append(contentsOf: fotograflar)
        allPhotosToUpload.append(contentsOf: cameraPhotos)
        
        // Validate photos
        let photoValidation = Validators.validatePhotos(allPhotosToUpload)
        guard photoValidation.isValid else {
            if changeStatus {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
            }
            errorMessage = photoValidation.errorMessage
            showError = true
            return
        }
        
        // Clear any previous errors
        errorMessage = nil
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        let stableDocumentId = (committedHasar ?? editingHasar)?.id ?? UUID()

        // If changeStatus is true, set status to done
        if changeStatus {
            durum = .done
        }
        
        // Optimize photos with high quality before upload
        var optimizedPhotos: [UIImage] = []
        for (index, photo) in allPhotosToUpload.enumerated() {
            let optimized = ImageOptimizationManager.shared.optimizeForStorage(photo, model: .highQuality)
            optimizedPhotos.append(optimized)
            let progress = Double(index + 1) / Double(allPhotosToUpload.count)
            DispatchQueue.main.async {
                self.uploadProgress = progress
            }
        }
        let compressedPhotos = optimizedPhotos
        
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
            let totalCount = compressedPhotos.count
            let failedCount = uploadErrors.count
            let allPhotosFailed = totalCount > 0 && failedCount == totalCount
            let errorsLookTransient = uploadErrors.allSatisfy(OfflineSyncDiagnostics.isLikelyTransientNetworkFailure)
            let canOfflineSinkPhotos = allPhotosFailed && (errorsLookTransient || !OfflineModeManager.shared.isOnline)

            if !uploadErrors.isEmpty {
                if allPhotosFailed {
                    if !canOfflineSinkPhotos {
                        self.isUploading = false
                        if changeStatus {
                            withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                        }
                        self.operationFlowState = .failed
                        ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                        return
                    }
                } else {
                    self.isUploading = false
                    self.operationFlowState = .failed
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Damage record will be saved with available photos.".localized, failedCount, totalCount))
                    return
                }
            }

            if canOfflineSinkPhotos {
                let slotTypes = (0 ..< compressedPhotos.count).map { $0 == 0 ? "handover" : "return" }
                OfflineMediaSyncCoordinator.shared.enqueueHasarMedia(
                    documentId: stableDocumentId,
                    images: compressedPhotos,
                    slotTypes: slotTypes
                ) { ok in
                    guard ok else {
                        self.isUploading = false
                        self.operationFlowState = .failed
                        ErrorManager.shared.showError(message: "Could not save photos on this device for later upload.".localized)
                        return
                    }
                    self.applyHasarSaveAfterUploads(
                        changeStatus: changeStatus,
                        sortedNewPhotos: [],
                        usedOfflineMediaQueue: true,
                        stableNewDocumentId: stableDocumentId
                    )
                }
                return
            }

            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            self.applyHasarSaveAfterUploads(
                changeStatus: changeStatus,
                sortedNewPhotos: sortedNewPhotos,
                usedOfflineMediaQueue: false,
                stableNewDocumentId: stableDocumentId
            )
        })
    }
    
    private func loadSelectedExitPhotoAndRetrySave(changeStatus: Bool) {
        guard let selectedExitPhotoURL else {
            if changeStatus {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
            }
            errorMessage = "Selected check out photo is invalid. Please select again.".localized
            showError = true
            return
        }
        
        print("🔄 Loading selected check out photo before save...")
        StorageImageLoader.shared.loadImage(from: selectedExitPhotoURL) { loadedImage in
            if let loadedImage {
                self.selectedExitPhotoImage = loadedImage
                self.kaydet(changeStatus: changeStatus)
            } else {
                if changeStatus {
                    withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                }
                self.errorMessage = "Failed to load selected check out photo. Please reselect it.".localized
                self.showError = true
                print("❌ Failed to load selected check out photo before save")
            }
        }
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

// MARK: - Exit Photo Selector View

struct ExitPhotoSelectorView: View {
    let exitPhotos: [String]
    @Binding var selectedPhotoURL: String?
    @Binding var selectedPhotoImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(exitPhotos.enumerated()), id: \.offset) { index, photoURL in
                        Button {
                            selectPhoto(url: photoURL)
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImageView(urlString: photoURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(12)
                                        .clipped()
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selectedPhotoURL == photoURL ? Color.orange : Color.clear, lineWidth: 3)
                                        )
                                }
                                
                                Text(String(format: "Photo %d".localized, index + 1))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if selectedPhotoURL == photoURL {
                                    Text("Selected".localized)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Exit Photo".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized) {
                        selectedPhotoURL = nil
                        selectedPhotoImage = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        finalizeSelection()
                    } label: {
                        Text("Done".localized)
                    }
                    .disabled(selectedPhotoURL == nil)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func selectPhoto(url: String) {
        selectedPhotoURL = url
        selectedPhotoImage = nil
        // Download image for upload later with storage fallback/auth.
        StorageImageLoader.shared.loadImage(from: url) { loadedImage in
            if let loadedImage {
                selectedPhotoImage = loadedImage
                HapticManager.shared.selection()
                print("✅ Exit photo selected and downloaded for handover")
            } else {
                print("❌ Failed to download exit photo")
            }
        }
    }
    
    private func finalizeSelection() {
        guard selectedPhotoURL != nil else { return }
        // Close immediately after selection; parent save flow guarantees image resolve before upload.
        dismiss()
    }
}