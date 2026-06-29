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
    let initialZone: CarDamageZone?
    /// Called when damage is marked **completed** (after success overlay), so parent can open detail preview.
    var onDamageCompleted: ((HasarKaydi) -> Void)? = nil
    /// Üst barı host yönetirken (ör. iade hızlı hasar): yalnızca tek **Done**; `nil` ise sol **Cancel** + `dismiss`.
    var externalDismiss: (() -> Void)? = nil
    /// İade akışı: bağlı çıkışı seç ve varsayılanları uygula.
    var returnFlowCheckoutId: UUID? = nil
    /// RES alanına yazılacak rakamlar (NAV/RES önekleri çıkarılmış).
    var returnFlowNavDigits: String? = nil
    /// İade / çıkış hızlı hasar: harita yalnızca "Durum formu" düğmesinden açılır; host ekranda gömülü harita yok.
    var presentedFromReturnOrExitQuickDamage: Bool = false

    @State private var selectedZone: CarDamageZone?
    /// Kullanıcı "Durum formu"na girdiğinde `true`; kayıtta `isConditionForm` olarak yansır (şema: ConditionFormViewModel.registerRecord).
    @State private var includeInConditionFormFlow = false
    @State private var showConditionFormFlowSheet = false

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
    @State private var showPhotoNamingInfo = false
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var operationFlowState: OperationFlowState = .draft
    @State private var pulseAnimation = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoSaveTimer: Timer?
    /// After first in-session save (new damage, In Progress), further saves update this record instead of appending another.
    @State private var committedHasar: HasarKaydi?
    @StateObject private var pendingUploadTracker = PendingPhotoUploadTracker()
    
    // Exit/Check out photo selection states
    @State private var selectedExitPhotoURL: String? // Selected photo from exit
    @State private var selectedExitPhotoImage: UIImage? // Downloaded image
    @State private var showExitPhotoSelector = false // Sheet to show photo selector
    @State private var selectedCheckoutId: UUID? // Selected check out record for handover defaults
    @State private var isCheckoutListExpanded = false

    // Photo preview state
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var isEditMode: Bool {
        editingHasar != nil
    }

    private var formNavigationTitle: String {
        if isEditMode { return "Edit Damage".localized }
        if externalDismiss != nil { return "Damage".localized }
        return ""
    }
    
    private var isSabihaGokcenFranchise: Bool {
        let fid = FirebaseService.shared.currentFranchiseId.uppercased()
        return fid.contains("SABIHA") || fid.contains("SAW")
    }

    private var isTurkeyFranchise: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: arac?.franchiseId ?? FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var isGermanyFranchise: Bool {
        FranchiseCapabilityMatrix.isGermanyFranchiseContext(
            serviceFranchiseId: arac?.franchiseId ?? FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var wheelSysCHOpsEnabled: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: arac?.franchiseId ?? FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var usesCHPalantirDamageChrome: Bool {
        wheelSysCHOpsEnabled && !isTurkeyFranchise
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
    
    private var sessionHasPersistedDamage: Bool {
        committedHasar != nil || editingHasar != nil
    }
    
    /// Default check-out for new damage: same ordering as the picker — latest **handover date** (`exitTarihi`), not RES number or `createdAt`.
    /// Parked rows are excluded (matches `availableCheckouts`).
    var latestExit: ExitIslemi? {
        availableCheckouts.first
    }
    
    var availableCheckouts: [ExitIslemi] {
        viewModel.exitIslemleri
            .filter { $0.aracId == aracId && $0.status != .parked }
            .sorted { a, b in
                if a.exitTarihi != b.exitTarihi {
                    return a.exitTarihi > b.exitTarihi
                }
                // Tie-break: newer record wins so choice is stable when handover matches
                return a.createdAt > b.createdAt
            }
    }
    
    var selectedCheckout: ExitIslemi? {
        guard let selectedCheckoutId else { return nil }
        return availableCheckouts.first(where: { $0.id == selectedCheckoutId })
    }
    
    init(
        aracId: UUID,
        editingHasar: HasarKaydi? = nil,
        initialZone: CarDamageZone? = nil,
        onDamageCompleted: ((HasarKaydi) -> Void)? = nil,
        externalDismiss: (() -> Void)? = nil,
        returnFlowCheckoutId: UUID? = nil,
        returnFlowNavDigits: String? = nil,
        presentedFromReturnOrExitQuickDamage: Bool = false
    ) {
        self.aracId = aracId
        self.editingHasar = editingHasar
        self.initialZone = initialZone
        self.onDamageCompleted = onDamageCompleted
        self.externalDismiss = externalDismiss
        self.returnFlowCheckoutId = returnFlowCheckoutId
        self.returnFlowNavDigits = returnFlowNavDigits
        self.presentedFromReturnOrExitQuickDamage = presentedFromReturnOrExitQuickDamage

        if let hasar = editingHasar {
            _tarih = State(initialValue: hasar.tarih)
            _handoverTarihi = State(initialValue: hasar.handoverTarihi)
            let resCodeNumbers = Self.reservationDigits(from: hasar.resKodu)
            _resKodu = State(initialValue: resCodeNumbers)
            _km = State(initialValue: String(hasar.km))
            _durum = State(initialValue: hasar.durum)
            _existingPhotoURLs = State(initialValue: hasar.fotograflar)
            _includeInConditionFormFlow = State(initialValue: hasar.isConditionForm == true)
            if let zoneRaw = hasar.damageZone, let zone = CarDamageZone(rawValue: zoneRaw) {
                _selectedZone = State(initialValue: zone)
            } else {
                _selectedZone = State(initialValue: initialZone)
            }
        } else {
            _selectedZone = State(initialValue: initialZone)
        }
    }
    
    private var damageEntryFormZStack: some View {
        ZStack {
            NavigationView {
                Group {
                    if usesCHPalantirDamageChrome {
                        wheelSysPalantirDamageForm
                    } else {
                        legacyDamageEntryForm
                    }
                }
                .navigationTitle(formNavigationTitle)
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
    }

    private var legacyDamageEntryForm: some View {
        ScrollViewReader { proxy in
            Form {
                if isUploading && uploadProgress > 0 {
                    Section {
                        UploadProgressView(
                            progress: uploadProgress,
                            currentItem: uploadedPhotosCount,
                            totalItems: totalPhotosCount,
                            message: "Uploading photos...".localized
                        )
                    }
                    .id("formTop")
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
                    .id(isUploading ? nil : "formTop")
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
    }

    private var wheelSysPalantirDamageForm: some View {
        ScrollViewReader { proxy in
            WheelSysPalantirFormScroll {
                if isUploading && uploadProgress > 0 {
                    WheelSysPalantirSectionCard(title: "Uploading photos...".localized, icon: "arrow.up.circle") {
                        UploadProgressView(
                            progress: uploadProgress,
                            currentItem: uploadedPhotosCount,
                            totalItems: totalPhotosCount,
                            message: "Uploading photos...".localized
                        )
                    }
                    .id("formTop")
                }
                if let error = errorMessage {
                    WheelSysPalantirStatusStrip(
                        icon: "exclamationmark.triangle",
                        message: error,
                        tint: PalantirTheme.critical
                    )
                }
                WheelSysPalantirSectionCard(
                    title: "Damage Information".localized,
                    icon: "exclamationmark.triangle.fill"
                ) {
                    wheelSysPalantirDamageInfoFields
                }
                .id(isUploading ? nil : "formTop")
                WheelSysPalantirSectionCard(title: "Photos".localized, icon: "camera.fill") {
                    photographFieldsContent
                }
                WheelSysPalantirSectionCard(
                    title: "Complete Damage Record".localized,
                    icon: "checkmark.seal.fill",
                    footer: "Mark the damage record as completed. Requires at least 2 photos (1 handover + 1 return). This action cannot be undone.".localized
                ) {
                    wheelSysPalantirCompleteButton
                }
            }
            .wheelSysCHOpsChrome()
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
    }

    @ViewBuilder
    private var wheelSysPalantirDamageInfoFields: some View {
        if !isEditMode, !availableCheckouts.isEmpty {
            wheelSysPalantirCheckoutPicker
        } else if !isEditMode, externalDismiss != nil {
            WheelSysPalantirStatusStrip(
                icon: "arrow.right.circle",
                message: "No Check Out Operations".localized,
                tint: PalantirTheme.textMuted
            )
        }
        WheelSysPalantirDateInput(label: "Date".localized, date: $tarih, components: [.date])
        WheelSysPalantirDateInput(label: "Handover Date".localized, date: $handoverTarihi, components: [.date])
        WheelSysPalantirResCodeInput(
            label: codeFieldLabel.localized,
            prefix: codePrefix,
            digits: $resKodu
        )
        WheelSysPalantirTextInput(
            label: "Kilometer".localized,
            text: $km,
            placeholder: "Enter kilometers".localized,
            keyboard: .numberPad
        )
        WheelSysPalantirSecondaryButton(
            title: "Condition Form".localized,
            icon: "scribble.variable"
        ) {
            HapticManager.shared.light()
            guard arac != nil else { return }
            includeInConditionFormFlow = true
            hasUnsavedChanges = true
            showConditionFormFlowSheet = true
        }
        WheelSysPalantirField(label: "Status".localized) {
            Picker("", selection: $durum) {
                ForEach(HasarDurum.allCases, id: \.self) { status in
                    Text(status.displayTitle).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var wheelSysPalantirCheckoutPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCheckoutListExpanded.toggle()
                }
                HapticManager.shared.selection()
            } label: {
                HStack(spacing: 10) {
                    PalantirOpsIconTile(systemName: "arrow.right.circle.fill", tint: PalantirTheme.accent, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Check Out".localized)
                            .font(PalantirTheme.labelFont(11))
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text(selectedCheckout.map(checkoutLabel(for:)) ?? "Select Check Out".localized)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    Spacer(minLength: 0)
                    PalantirOpsBadge(text: "\(availableCheckouts.count)", tone: .accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .rotationEffect(.degrees(isCheckoutListExpanded ? 180 : 0))
                }
                .padding(11)
                .background(PalantirTheme.background.opacity(0.55))
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isCheckoutListExpanded {
                VStack(spacing: 0) {
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(checkout.resKodu.isEmpty ? "RES-".localized : checkout.resKodu)
                                        .font(PalantirTheme.dataFont(12))
                                        .foregroundStyle(PalantirTheme.textPrimary)
                                    Text(checkoutDateText(for: checkout))
                                        .font(PalantirTheme.bodyFont(11))
                                        .foregroundStyle(PalantirTheme.textMuted)
                                }
                                Spacer(minLength: 0)
                                if selectedCheckoutId == checkout.id {
                                    PalantirOpsBadge(text: "OK".localized, tone: .success)
                                }
                            }
                            .padding(11)
                        }
                        .buttonStyle(.plain)
                        .background(selectedCheckoutId == checkout.id ? PalantirTheme.surfaceHigh : PalantirTheme.background.opacity(0.55))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(PalantirTheme.border).frame(height: 1)
                        }
                    }
                }
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
        }
    }

    private var wheelSysPalantirCompleteButton: some View {
        let isResCodeValid = !resKodu.isEmpty && resKodu.count >= 1 && resKodu.count <= 8
        let allPhotos = fotograflar + cameraPhotos
        let selectedExitCount = selectedExitPhotoImage == nil ? 0 : 1
        let totalAvailableCount = existingPhotoURLs.count + allPhotos.count + selectedExitCount
        let hasEnoughPhotos = totalAvailableCount >= 2
        let isDisabled = !isResCodeValid || km.isEmpty || !hasEnoughPhotos || isUploading
        return WheelSysPalantirPrimaryButton(
            title: isUploading ? "Completing...".localized : "Save & Complete".localized,
            icon: "checkmark.circle.fill",
            isLoading: isUploading,
            disabled: isDisabled
        ) {
            guard !isDisabled else { return }
            HapticManager.shared.medium()
            showCompleteConfirmation = true
        }
    }

    private var damageEntryFormWithLifecycle: some View {
        damageEntryFormZStack
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .onChange(of: resKodu) { oldValue, newValue in
                hasUnsavedChanges = true
                let filtered = newValue.filter { $0.isNumber }
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
                if let editingHasar = editingHasar {
                    let resCodeNumbers = Self.reservationDigits(from: editingHasar.resKodu)
                    resKodu = resCodeNumbers
                    km = String(editingHasar.km)
                    tarih = editingHasar.tarih
                    handoverTarihi = editingHasar.handoverTarihi
                    durum = editingHasar.durum
                    notlar = editingHasar.notlar
                    existingPhotoURLs = editingHasar.fotograflar
                    includeInConditionFormFlow = editingHasar.isConditionForm == true
                } else {
                    loadDraft()
                    applyReturnFlowCheckoutPrefill()
                    applyLatestExitDefaultsIfNeeded()
                }
            }
            .onDisappear {
                if isSaved {
                    clearDraft()
                }
            }
    }

    var body: some View {
        damageEntryFormWithLifecycle
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $fotograflar)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // After camera dismisses, check if we should reopen for more photos
            if let _ = capturedImage {
                // Add captured image to camera photos
                if let newImage = capturedImage {
                    let key = pendingUploadTracker.photoKey(for: newImage)
                    let duplicateExists = (fotograflar + cameraPhotos).contains {
                        pendingUploadTracker.photoKey(for: $0) == key
                    }
                    if !duplicateExists {
                        cameraPhotos.append(newImage)
                        let path = "hasar_fotograflari/return/\(UUID().uuidString).jpg"
                        pendingUploadTracker.startUploadIfNeeded(image: newImage, storagePath: path)
                    }
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
        .fullScreenCover(item: $photoGallerySession) { session in
            Group {
                if let urls = session.urlStrings {
                    NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
                } else if let imgs = session.images {
                    NativePhotoGalleryView(images: imgs, initialIndex: session.startIndex)
                }
            }
        }
        .sheet(isPresented: $showConditionFormFlowSheet) {
            if let liveArac = viewModel.araclar.first(where: { $0.id == aracId }) {
                NavigationStack {
                    ConditionFormView(arac: liveArac)
                        .environmentObject(viewModel)
                }
            }
        }
        .alert("Unsaved Changes".localized, isPresented: $showExitConfirmation) {
            Button("Discard Changes".localized, role: .destructive) {
                if let externalDismiss {
                    externalDismiss()
                } else {
                    dismiss()
                }
            }
            Button("Continue Editing".localized, role: .cancel) { }
        } message: {
            Text("Is the operation complete? Changes have not been saved.".localized)
        }
        .toolbar {
            if isTurkeyFranchise {
                ToolbarItem(placement: .navigationBarTrailing) {
                    TurkeyDocumentationToolbarButton(topic: .damage)
                }
            }
            if externalDismiss != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if hasUnsavedChanges || isUploading {
                            showExitConfirmation = true
                        } else {
                            externalDismiss?()
                        }
                    } label: {
                        Label("Back".localized, systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) {
                        if hasUnsavedChanges || isUploading {
                            showExitConfirmation = true
                        } else {
                            externalDismiss?()
                        }
                    }
                }
            } else {
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
        .alert("damage.photo.naming.info.title".localized, isPresented: $showPhotoNamingInfo) {
            Button("OK".localized, role: .cancel) { }
        } message: {
            Text("damage.photo.naming.info.message".localized)
        }
    }
    
    // MARK: - Computed Properties
    
    private var damageInfoSection: some View {
        Section {
            if isSabihaGokcenFranchise {
                HStack {
                    Spacer()
                    USaveMiniLogoView(size: CGSize(width: 96, height: 34))
                }
            }
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
            } else if !isEditMode, externalDismiss != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 20, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check Out".localized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("No Check Out Operations".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
            
            DatePicker("Date".localized, selection: $tarih, displayedComponents: .date)
            DatePicker("Handover Date".localized, selection: $handoverTarihi, displayedComponents: .date)
            
            HStack {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.blue)
                Text(codeFieldLabel.localized)
                Spacer()
                HStack(spacing: 0) {
                    Text(codePrefix)
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
            
            Button {
                HapticManager.shared.light()
                guard arac != nil else { return }
                includeInConditionFormFlow = true
                hasUnsavedChanges = true
                showConditionFormFlowSheet = true
            } label: {
                HStack {
                    Label("Condition Form".localized, systemImage: "scribble.variable")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

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
            pendingUploadTracker.markRemoved(image: fotograflar[combinedIndex])
            fotograflar.remove(at: combinedIndex)
            hasUnsavedChanges = true
            HapticManager.shared.selection()
            return
        }
        
        let cameraIndex = combinedIndex - fotograflar.count
        guard cameraPhotos.indices.contains(cameraIndex) else { return }
        pendingUploadTracker.markRemoved(image: cameraPhotos[cameraIndex])
        cameraPhotos.remove(at: cameraIndex)
        hasUnsavedChanges = true
        HapticManager.shared.selection()
    }
    
    private var photographsSection: some View {
        Section {
            photographFieldsContent
        }
    }

    @ViewBuilder
    private var photographFieldsContent: some View {
            if !isEditMode, let checkoutForPhotos = (selectedCheckout ?? latestExit), !checkoutForPhotos.fotograflar.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if usesCHPalantirDamageChrome {
                        WheelSysPalantirSecondaryButton(
                            title: "Select from selected check out photos".localized,
                            icon: "photo.stack",
                            tint: PalantirTheme.warning
                        ) {
                            showExitPhotoSelector = true
                        }
                    } else {
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
                    }
                    
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
                                            photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: existingPhotoURLs, startIndex: index)
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
                                            photoGallerySession = PhotoGalleryFullScreenSession(images: allPhotos, startIndex: index)
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
            
            if usesCHPalantirDamageChrome {
                HStack(spacing: 8) {
                    WheelSysPalantirSecondaryButton(
                        title: "Choose from Gallery".localized,
                        icon: "photo.on.rectangle",
                        compact: true,
                        disabled: showCamera
                    ) {
                        guard !showCamera else { return }
                        showImagePicker = true
                    }
                    WheelSysPalantirSecondaryButton(
                        title: "Take Photo".localized,
                        icon: "camera",
                        tint: PalantirTheme.success,
                        compact: true,
                        disabled: showImagePicker
                    ) {
                        guard !showImagePicker else { return }
                        showCamera = true
                    }
                }
                Text("Note: The first uploaded photo will be handover, others will be return.".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .padding(.top, 4)
                WheelSysPalantirSecondaryButton(
                    title: "damage.photo.naming.info.short".localized,
                    icon: "questionmark.circle"
                ) {
                    showPhotoNamingInfo = true
                }
            } else {
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
                    Button {
                        showPhotoNamingInfo = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.caption.weight(.semibold))
                            Text("damage.photo.naming.info.short".localized)
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
    }
    
    private var completeSection: some View {
        Section {
            // RES code: 1-8 digits, KM: not empty
            let isResCodeValid = !resKodu.isEmpty && resKodu.count >= 1 && resKodu.count <= 8
            let allPhotos = fotograflar + cameraPhotos
            let selectedExitCount = selectedExitPhotoImage == nil ? 0 : 1
            // Edit senaryosunda mevcut fotoğraflar zaten existingPhotoURLs içinde.
            // Complete için toplam (mevcut + yeni + seçili checkout) fotoğraf ≥ 2 olmalı.
            let totalAvailableCount = existingPhotoURLs.count + allPhotos.count + selectedExitCount
            let hasEnoughPhotos = totalAvailableCount >= 2
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
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 7)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: max(0.05, min(uploadProgress, 1)))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                            .animation(.linear(duration: 0.2), value: uploadProgress)
                        Text("\(Int((max(0.05, min(uploadProgress, 1)) * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
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
        guard selectedCheckoutId == nil else { return }
        selectedCheckoutId = latestExit.id
        applySelectedCheckoutDefaults()
    }

    private func applyReturnFlowCheckoutPrefill() {
        guard let rid = returnFlowCheckoutId,
              availableCheckouts.contains(where: { $0.id == rid }) else {
            if let rawNav = returnFlowNavDigits?.trimmingCharacters(in: .whitespacesAndNewlines), !rawNav.isEmpty {
                let digits = rawNav.filter(\.isNumber)
                if !digits.isEmpty, resKodu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resKodu = String(digits.prefix(8))
                }
            }
            return
        }
        selectedCheckoutId = rid
        applySelectedCheckoutDefaults()
        if let rawNav = returnFlowNavDigits?.trimmingCharacters(in: .whitespacesAndNewlines), !rawNav.isEmpty {
            let digits = rawNav.filter(\.isNumber)
            if !digits.isEmpty, resKodu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resKodu = String(digits.prefix(8))
            }
        }
    }
    
    private func applySelectedCheckoutDefaults() {
        guard let checkout = selectedCheckout ?? latestExit else { return }
        
        handoverTarihi = checkout.exitTarihi
        
        let rawRes = checkout.navKodu ?? checkout.resKodu
        var codeBody = rawRes.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = codeBody.uppercased()
        for p in ["RES-", "RNT-", "NAV-"] {
            if upper.hasPrefix(p) {
                codeBody = String(codeBody.dropFirst(4))
                break
            }
        }
        let cleanedRes = codeBody.filter { $0.isNumber }
        if !cleanedRes.isEmpty {
            resKodu = cleanedRes
        }
        
        if km.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let checkoutKM = checkout.km {
            km = String(checkoutKM)
        }
        if km.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let vehicle = arac, let vehicleKm = vehicle.lastCheckIn?.km, vehicleKm > 0 {
                km = String(vehicleKm)
            } else if wheelSysCHOpsEnabled,
                      let plate = arac?.plaka,
                      let fleetKm = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate)?.mileage,
                      fleetKm > 0 {
                km = String(fleetKm)
            }
        }
        // Checkout handover photo is chosen only via "Select from selected check out photos" — never auto-pick.
        if let url = selectedExitPhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            let urls = checkout.fotograflar.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !urls.contains(url) {
                selectedExitPhotoURL = nil
                selectedExitPhotoImage = nil
            }
        }
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

    private func mergedDamagePhotoURLs(base: HasarKaydi?, existing: [String], newUploads: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        func append(_ urls: [String]) {
            for raw in urls {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, !seen.contains(t) else { continue }
                seen.insert(t)
                ordered.append(t)
            }
        }
        if let base { append(base.fotograflar) }
        append(existing)
        append(newUploads)
        return ordered
    }

    private func applyHasarSaveAfterUploads(
        changeStatus: Bool,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        var cleanResKodu = self.resKodu.trimmingCharacters(in: .whitespaces)
        let digits = Self.reservationDigits(from: cleanResKodu)
        cleanResKodu = digits.isEmpty ? "" : "\(codePrefix)\(digits)"

        let baseHasar = self.committedHasar ?? self.editingHasar
        let allPhotos: [String]
        if self.sessionHasPersistedDamage {
            allPhotos = mergedDamagePhotoURLs(
                base: baseHasar,
                existing: self.existingPhotoURLs,
                newUploads: sortedNewPhotos
            )
        } else {
            allPhotos = sortedNewPhotos
        }

        let savedDamageZoneRawValue: String? = presentedFromReturnOrExitQuickDamage ? nil : self.selectedZone?.rawValue
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
                createdBy: base.createdBy,
                damageZone: savedDamageZoneRawValue,
                isConditionForm: self.includeInConditionFormFlow ? true : nil
            )
            updatedHasar.id = base.id
            updatedHasar.conditionRegionId = base.conditionRegionId
            updatedHasar.conditionPointX = base.conditionPointX
            updatedHasar.conditionPointY = base.conditionPointY
            updatedHasar.conditionViewBlockId = base.conditionViewBlockId
            updatedHasar.markerNumber = base.markerNumber
            updatedHasar.damageType = base.damageType
            updatedHasar.damageSeverity = base.damageSeverity
            savedHasar = updatedHasar

            self.viewModel.hasarGuncelle(aracId: self.aracId, hasar: updatedHasar)

            print("✅ Hasar güncellendi - Status: \(updatedHasar.status.rawValue), RES: \(cleanResKodu)")

            LiveActivityTracker.shared.record(
                changeStatus ? .damageCompleted : .damageUpdated,
                title: changeStatus ? "Damage record completed" : "Damage record updated",
                subtitle: "RES \(cleanResKodu) · \(savedDamageZoneRawValue ?? "zone")",
                plate: self.arac?.plaka,
                recordId: updatedHasar.id.uuidString,
                userProfile: self.authManager.userProfile,
                force: changeStatus
            )

            if let arac = self.arac {
                let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                if changeStatus {
                    self.notificationManager.sendDamageCompletedNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName,
                        recordId: savedHasar.id
                    )
                } else {
                    self.notificationManager.sendDamageRecordNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName,
                        recordId: savedHasar.id
                    )
                }
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
                createdBy: currentUserId,
                damageZone: savedDamageZoneRawValue,
                isConditionForm: self.includeInConditionFormFlow ? true : nil
            )
            newHasar.id = stableNewDocumentId
            savedHasar = newHasar

            self.viewModel.hasarEkle(aracId: self.aracId, hasar: newHasar)

            print("✅ Yeni hasar eklendi - Status: \(newHasar.status.rawValue), RES: \(cleanResKodu)")

            LiveActivityTracker.shared.record(
                changeStatus ? .damageCompleted : .damageCreated,
                title: changeStatus ? "Damage record completed" : "Damage record created",
                subtitle: "RES \(cleanResKodu) · \(savedDamageZoneRawValue ?? "zone")",
                plate: self.arac?.plaka,
                recordId: newHasar.id.uuidString,
                userProfile: self.authManager.userProfile,
                force: changeStatus
            )

            if let arac = self.arac {
                let userName = self.authManager.userProfile?.fullName ?? "Unknown User"
                if changeStatus {
                    self.notificationManager.sendDamageCompletedNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName,
                        recordId: savedHasar.id
                    )
                } else {
                    self.notificationManager.sendDamageRecordNotification(
                        carPlate: arac.plaka,
                        resCode: cleanResKodu,
                        userName: userName,
                        recordId: savedHasar.id
                    )
                }
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
            self.uploadProgress = 1
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                self.completionSucceeded = true
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Damage photos will upload when you are back online.".localized, type: .success)
            }
            // Online: success feedback is the in-app banner from NotificationManager (no duplicate Toast).
            print("✅ Damage completed - dismissing view")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                self.operationFlowState = .completed
                self.dismiss()
                self.onDamageCompleted?(savedHasar)
            }
        } else {
            self.isSaved = false
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Remaining damage photos will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendDamageRecordNotification (no duplicate Toast).
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
        
        // Clear any previous errors
        errorMessage = nil
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        uploadProgress = 0
        let stableDocumentId = (committedHasar ?? editingHasar)?.id ?? UUID()

        if changeStatus {
            durum = .done
        }

        // Photo validation can encode full JPEGs — keep it off the main thread.
        // Upload path already optimizes via CachedImageManager (no duplicate pre-pass here).
        let photosForPipeline = allPhotosToUpload
        DispatchQueue.global(qos: .userInitiated).async {
            if !photosForPipeline.isEmpty {
                let photoValidation = Validators.validatePhotos(photosForPipeline)
                guard photoValidation.isValid else {
                    DispatchQueue.main.async {
                        self.isUploading = false
                        if changeStatus {
                            withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                        }
                        self.operationFlowState = .failed
                        self.errorMessage = photoValidation.errorMessage
                        self.showError = true
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                self.performDamagePhotoUploads(
                    photos: photosForPipeline,
                    changeStatus: changeStatus,
                    stableDocumentId: stableDocumentId
                )
            }
        }
    }

    private func performDamagePhotoUploads(
        photos: [UIImage],
        changeStatus: Bool,
        stableDocumentId: UUID
    ) {
        let combinedPhotos = photos.enumerated().map { (index: $0.offset, photo: $0.element) }

        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock()

        totalPhotosCount = photos.count
        uploadedPhotosCount = 0

        for item in combinedPhotos {
            if let preUploadedURL = pendingUploadTracker.uploadedURL(for: item.photo) {
                indexedPhotoURLs.append((index: item.index, url: preUploadedURL))
                uploadedPhotosCount += 1
                uploadProgress = Double(uploadedPhotosCount) / Double(max(totalPhotosCount, 1))
                continue
            }
            group.enter()
            let photoType = item.index == 0 ? "handover" : "return"
            let path = "hasar_fotograflari/\(photoType)/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(item.photo, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url {
                        lock.lock()
                        indexedPhotoURLs.append((index: item.index, url: url))
                        lock.unlock()
                        self.uploadedPhotosCount += 1
                        self.uploadProgress = Double(self.uploadedPhotosCount) / Double(max(self.totalPhotosCount, 1))
                    } else if let error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error at index \(item.index): \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let totalCount = photos.count
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
                let slotTypes = (0 ..< photos.count).map { $0 == 0 ? "handover" : "return" }
                OfflineMediaSyncCoordinator.shared.enqueueHasarMedia(
                    documentId: stableDocumentId,
                    images: photos,
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

            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map(\.url)
            self.applyHasarSaveAfterUploads(
                changeStatus: changeStatus,
                sortedNewPhotos: sortedNewPhotos,
                usedOfflineMediaQueue: false,
                stableNewDocumentId: stableDocumentId
            )
        }
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