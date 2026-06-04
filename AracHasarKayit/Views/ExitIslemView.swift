import SwiftUI
import Kingfisher
import FirebaseFirestore
import CoreImage

struct ExitIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    var existingExit: ExitIslemi? = nil // For editing existing exits
    /// Turkey: prefill from web Front Desk (`checkout_ready`).
    var trHandoverPrefill: TRFrontDeskHandoverPrefill? = nil
    var onExitCompleted: ((ExitIslemi) -> Void)? = nil
    
    @State private var exitTarihi = Date() // Otomatik olarak şu anki tarih ve saat
    /// Persisted as web `plannedCheckinAt` (see `ExitIslemi.encode`).
    @State private var plannedReturnPickerDate = Date()
    @State private var notlar = ""
    @State private var resKodu = ""
    @State private var kmText = ""
    @State private var yakitSeviyesi = "8/8"
    @State private var bayiAdi = ""
    @State private var pickUpBranch = ""
    @State private var dropOffBranch = ""
    @State private var fotograflar: [UIImage] = [] // Photos from gallery
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera
    @State private var existingPhotoURLs: [String] = [] // Existing remote photos (edit mode)
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var serialCaptureBaselinePhotoCount = 0
    @State private var cameraPhotoFingerprintKeys: [String] = []
    @State private var galleryPhotoFingerprintKeys: [String] = []
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
    @State private var completionProgress: Double = 0
    @StateObject private var pendingUploadTracker = PendingPhotoUploadTracker()
    @State private var isVehicleParked = false
    @State private var customerFirstName = ""
    @State private var customerLastName = ""
    @State private var customerEmail = ""
    @State private var customerNationalId = ""
    @State private var testDriverFirstName = ""
    @State private var testDriverLastName = ""
    @State private var customerSignatureImage: UIImage?
    @State private var lastSignatureBase64Digest = 0
    @State private var showSignatureSheet = false
    @State private var signatureWasRemoved = false
    @State private var customerSectionExpanded = false
    @State private var showQRSheet = false
    @State private var showVehicleItemsSheet = false
    @State private var localQRToken: String = UUID().uuidString
    @State private var vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
    @State private var formListener: ListenerRegistration?
    /// After the first save in this session, updates reuse this record (avoids duplicate exits on In Progress re-saves).
    @State private var committedExit: ExitIslemi?
    @State private var didPublishTrHandoverLifecycle = false
    @State private var showQuickDamageSheet = false
    @State private var showConditionFormAfterDamageSheet = false
    /// Save name + email under this franchise for auto-fill on next visit (web / kiosk / iOS).
    @State private var rememberCustomerContact = true
    @State private var rememberLookupTask: Task<Void, Never>?
    @State private var trRentalTermsAcceptedAt: Date?
    @State private var trRentalTermsLanguage: String?
    @State private var trRentalTermsSignatureURL: String?
    @State private var showTurkeyComplianceWizard = false
    @State private var turkeyWizardDamagePhotos: [UIImage] = []
    @State private var turkeyInlineVehiclePdf: Data?
    @State private var turkeyInlineTermsPdf: Data?
    @State private var isLoadingKioskTermsPdf = false
    @State private var showAdditionalDriverOnFile = false
    @State private var grtPdfFullScreenItem: TurkeyPdfPreviewItem?
    /// Front-desk row tied to this checkout (`linkedExitId` query); needed for private GRT signed URLs.
    @State private var linkedFrontDeskCustomerDocId: String?

    // Photo preview state
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }

    private var currentFranchiseId: String { FirebaseService.shared.currentFranchiseId.uppercased() }
    private var isTurkeyFranchise: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var usesSerialPhotoCapture: Bool {
        FranchiseCapabilityMatrix.serialPhotoCaptureEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    private var isSwitzerlandFranchise: Bool {
        FranchiseCapabilityMatrix.isSwitzerlandFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: UserDefaults.standard.selectedCountry.countryCode
        )
    }
    private var isGermanyFranchise: Bool {
        if currentFranchiseId.hasPrefix("DE") { return true }
        let cc = authManager.userProfile?.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return cc == "DE"
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
    private var hasCustomerContactData: Bool {
        !customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !customerLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        customerSignatureImage != nil
    }
    /// Web handover prefill: lock name/email only; national ID stays editable if kiosk/staff added it later.
    private var isHandoverContactReadOnly: Bool {
        trHandoverPrefill != nil
    }
    /// Köşe `franchises` koleksiyonundaki `TR_*` dokümanları (`AracViewModel.loadTurkeyFranchiseLocationBranchesFromCollection`).
    private var turkeyBranches: [FranchiseGarageBranch] {
        let fromFirestore = viewModel.turkeyFranchiseLocationBranches
            .sorted { $0.storageKey.localizedCaseInsensitiveCompare($1.storageKey) == .orderedAscending }
        if !fromFirestore.isEmpty { return fromFirestore }
        return TurkiyeGarajSubeleri.branches.map {
            FranchiseGarageBranch(storageKey: $0.storageKey, displayName: $0.displayName, countryCode: "TR")
        }
    }
    private var pickupBranchDisplayTitle: String {
        branchDisplayTitle(for: pickUpBranch)
    }
    private var dropoffBranchDisplayTitle: String {
        branchDisplayTitle(for: dropOffBranch)
    }

    private var turkeyCommercialTitle: String {
        TurkeyFranchiseMetadata.commercialTitle(
            franchiseDisplayName: viewModel.franchiseName,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches
        )
    }

    private var turkeyBranchDisplayName: String {
        TurkeyFranchiseMetadata.branchDisplayTitle(
            pickUpBranch: pickUpBranch,
            dropOffBranch: dropOffBranch,
            preferDropOffForReturn: false,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
            franchiseGarageBranches: viewModel.franchiseGarageBranches
        )
    }

    private var turkeyTermsGateComplete: Bool {
        !(trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var turkeyComplianceReadyForComplete: Bool {
        guard isTurkeyFranchise else { return true }
        return turkeyTermsGateComplete
            && customerSignatureImage != nil
            && checkoutTotalPhotoCount >= 1
    }
    
    var body: some View {
        configuredBodyView(content: baseBodyView)
    }

    private var baseBodyView: some View {
        ZStack {
            mainForm
                .blur(radius: showCompletionOverlay ? 8 : 0)
                .allowsHitTesting(!showCompletionOverlay)

            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }

        }
    }

    private func configuredBodyView<Content: View>(content: Content) -> some View {
        let navConfigured = AnyView(
            content
            .navigationTitle("Check Out Process".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
        )

        let alertConfigured = AnyView(
            navConfigured
            .alert("Unsaved Changes".localized, isPresented: $showExitConfirmation) {
                Button("Continue Editing".localized, role: .cancel) { }
                Button("Discard Changes".localized, role: .destructive) {
                    pendingUploadTracker.discardSessionUploads()
                    dismiss()
                }
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
        )

        let withFieldChanges = alertConfigured
            .onChange(of: resKodu) { _, _ in hasUnsavedChanges = true }
            .onChange(of: exitTarihi) { _, _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _, _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar.count) { _, newCount in
                guard newCount > galleryPhotoFingerprintKeys.count else { return }
                let start = galleryPhotoFingerprintKeys.count
                let newImages = Array(fotograflar[start...])
                let knownCamera = cameraPhotoFingerprintKeys
                Task {
                    for image in newImages {
                        guard let key = await CheckoutReturnPhotoCapture.fingerprintForNewPhoto(
                            image,
                            existingKeys: galleryPhotoFingerprintKeys,
                            additionalKnownKeys: knownCamera
                        ) else { continue }
                        galleryPhotoFingerprintKeys.append(key)
                        pendingUploadTracker.startUploadIfNeeded(
                            image: image,
                            storagePath: exitDraftPhotoStoragePath(),
                            fingerprintKey: key,
                            trackForSessionDiscard: true
                        )
                    }
                }
            }
            .onChange(of: cameraPhotos) { _, _ in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { _, _ in hasUnsavedChanges = true }
            .onChange(of: kmText) { _, _ in hasUnsavedChanges = true }
            .onChange(of: yakitSeviyesi) { _, _ in hasUnsavedChanges = true }
            .onChange(of: bayiAdi) { _, _ in hasUnsavedChanges = true }
            .onChange(of: pickUpBranch) { _, _ in hasUnsavedChanges = true }
            .onChange(of: dropOffBranch) { _, _ in hasUnsavedChanges = true }
            .onChange(of: plannedReturnPickerDate) { _, _ in hasUnsavedChanges = true }
            .onChange(of: vehicleItemsChecklist) { _, _ in hasUnsavedChanges = true }
        let withCustomerChanges = withFieldChanges
            .onChange(of: customerFirstName) { _, _ in hasUnsavedChanges = true }
            .onChange(of: customerLastName) { _, _ in hasUnsavedChanges = true }
            .onChange(of: customerEmail) { _, newVal in
                hasUnsavedChanges = true
                scheduleRememberAutofill(for: newVal)
            }
            .onChange(of: customerNationalId) { _, _ in hasUnsavedChanges = true }
            .onChange(of: customerSignatureImage) { _, _ in hasUnsavedChanges = true }
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
            .onChange(of: turkeyBranchRegistryIdentity) { _, _ in
                guard existingExit == nil, isTurkeyFranchise else { return }
                applyTurkeyDefaultBranchesForNewCheckout()
            }
            .onChange(of: customerSignatureImage) { _, _ in refreshTurkeyVehicleInlinePreview() }
            .onChange(of: fotograflar) { _, _ in refreshTurkeyVehicleInlinePreview() }
            .onChange(of: cameraPhotos) { _, _ in refreshTurkeyVehicleInlinePreview() }
            .onChange(of: trRentalTermsSignatureURL) { _, _ in refreshTurkeyTermsInlinePreview() }
            .onChange(of: showAdditionalDriverOnFile) { _, isOn in
                if !isOn {
                    testDriverFirstName = ""
                    testDriverLastName = ""
                }
            }
        return AnyView(
            withCustomerChanges
            .fullScreenCover(item: $grtPdfFullScreenItem) { item in
                TurkeyPdfFullScreenPreview(
                    pdfData: item.data,
                    title: item.title,
                    onDismiss: { grtPdfFullScreenItem = nil }
                )
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .sheet(isPresented: $showVehicleItemsSheet) {
                VehicleItemsChecklistSheet(selections: $vehicleItemsChecklist)
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureCaptureView(signatureImage: $customerSignatureImage)
            }
            .fullScreenCover(isPresented: $showTurkeyComplianceWizard) {
                TurkeyCheckoutComplianceWizardView(
                    isPresented: $showTurkeyComplianceWizard,
                    draftExit: draftExitForTurkeyPdf(),
                    arac: arac,
                    vehiclePhotos: allPhotos,
                    damagePhotos: turkeyWizardDamagePhotos,
                    franchiseDisplayName: turkeyCommercialTitle,
                    includeGeneralRentalTerms: false,
                    existingVehicleSignature: customerSignatureImage,
                    commercialTitle: turkeyCommercialTitle,
                    branchDisplayName: turkeyBranchDisplayName,
                    customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines),
                    staffSignerNameFallback: authManager.userProfile?.fullName,
                    existingSignedTermsPdfData: nil,
                    initialTermsPreferredEnglish: trRentalTermsLanguage.map { $0.lowercased() == "en" },
                    onTermsAccepted: { _, _ in },
                    onFinished: { img in
                        if let img {
                            customerSignatureImage = img
                            refreshTurkeyVehicleInlinePreview()
                        }
                    }
                )
            }
            .sheet(isPresented: $showQRSheet) {
                CheckoutQRSheet(token: activeToken)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if !usesSerialPhotoCapture {
                    handleCameraDismiss()
                }
            }) {
                if usesSerialPhotoCapture {
                    TurkeySerialCaptureView(
                        onPhotoCaptured: handleSerialPhotoCaptured,
                        onDone: { showCamera = false },
                        onCancel: {
                            revertSerialCaptureCameraSession()
                            showCamera = false
                        },
                        onPhotoDeletedAtIndex: handleSerialPhotoDeleted
                    )
                } else {
                    CameraView(capturedImage: $capturedImage)
                }
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
            .sheet(isPresented: $showQuickDamageSheet) {
                HasarEkleView(
                    aracId: arac.id,
                    editingHasar: nil,
                    initialZone: nil,
                    onDamageCompleted: { _ in
                        showQuickDamageSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showConditionFormAfterDamageSheet = true
                        }
                    },
                    externalDismiss: { showQuickDamageSheet = false },
                    presentedFromReturnOrExitQuickDamage: true
                )
                .environmentObject(viewModel)
                .environmentObject(notificationManager)
                .environmentObject(authManager)
            }
            .sheet(isPresented: $showConditionFormAfterDamageSheet) {
                if let liveArac = viewModel.araclar.first(where: { $0.id == arac.id }) {
                    NavigationStack {
                        ConditionFormView(arac: liveArac)
                            .environmentObject(viewModel)
                    }
                }
            }
            .onDisappear {
                rememberLookupTask?.cancel()
                rememberLookupTask = nil
                formListener?.remove()
                formListener = nil
            }
        )
    }
    
    private var mainForm: some View {
        ScrollViewReader { proxy in
            Form {
                if isTurkeyFranchise {
                    turkeyDealerInfoSection
                }
                if let identityExit = committedExit ?? existingExit, isSaved {
                    operationIdentitySection(exit: identityExit, plateInteractive: true, codeInteractive: true)
                } else if !isSaved {
                    operationIdentitySection(exit: nil, plateInteractive: false, codeInteractive: false)
                }
                exitBilgileriSection
                    .id("formTop")
                if isTurkeyFranchise {
                    Section {
                        Button {
                            HapticManager.shared.light()
                            showQuickDamageSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                Text("Quick damage".localized)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundColor(.white)
                        }
                        .listRowBackground(Color.orange.opacity(0.88))
                    } footer: {
                        Text("Quick damage footer".localized)
                            .font(.caption)
                    }
                }
                fotografSection
                if isTurkeyFranchise {
                    turkeyGeneralTermsKioskSection
                    turkeyExitVehicleSignSection
                }
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
        if isTurkeyFranchise {
            ToolbarItem(placement: .navigationBarTrailing) {
                TurkeyDocumentationToolbarButton(topic: .checkout)
            }
        }
        if !isSaved {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showQRSheet = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.teal)
                }
                .accessibilityLabel("Customer Self-Fill".localized)
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
    
    private func defaultPlannedReturn(around checkout: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: checkout) ?? checkout
    }

    private func scheduleRememberAutofill(for email: String) {
        rememberLookupTask?.cancel()
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard em.contains("@"), em.contains(".") else { return }
        rememberLookupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            FirebaseService.shared.fetchCustomerContactRemember(email: em) { data, err in
                DispatchQueue.main.async {
                    guard err == nil, let data else { return }
                    applyRememberedContactIfEmpty(data)
                }
            }
        }
    }

    private func applyRememberedContactIfEmpty(_ data: [String: Any]) {
        if customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = data["firstName"] as? String,
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customerFirstName = v
        }
        if customerLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fam = data["familyName"] as? String,
               !fam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customerLastName = fam
            } else if let ln = data["lastName"] as? String,
                      !ln.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customerLastName = ln
            }
        }
    }

    private func handleAppear() {
        if isTurkeyFranchise {
            viewModel.reloadFranchiseGarageMetadataFromFirestore()
        }
        if let existing = existingExit {
            exitTarihi = existing.exitTarihi
            notlar = existing.notlar
            isVehicleParked = existing.status == .parked
            let rk = existing.resKodu
            if rk.hasPrefix("RES-") || rk.hasPrefix("NAV-") || rk.hasPrefix("RNT-") {
                resKodu = String(rk.dropFirst(4))
            } else {
                resKodu = rk
            }
            kmText = existing.km.map(String.init) ?? ""
            yakitSeviyesi = normalizedFuelLevel(existing.yakitSeviyesi)
            if isTurkeyFranchise {
                pickUpBranch = canonicalTurkeyBranchKey(from: existing.pickUpBranch ?? existing.bayiAdi)
                bayiAdi = ""
            } else {
                bayiAdi = existing.bayiAdi ?? ""
                pickUpBranch = existing.pickUpBranch ?? ""
            }
            dropOffBranch = canonicalTurkeyBranchKey(from: existing.dropOffBranch)
            customerFirstName = existing.customerFirstName ?? ""
            customerLastName = existing.customerLastName ?? ""
            customerEmail = existing.customerEmail ?? ""
            customerNationalId = existing.customerNationalId ?? ""
            testDriverFirstName = existing.testDriverFirstName ?? ""
            testDriverLastName = existing.testDriverLastName ?? ""
            showAdditionalDriverOnFile = !testDriverFirstName.isEmpty || !testDriverLastName.isEmpty
            vehicleItemsChecklist = existing.vehicleItemsChecklist ?? VehicleChecklistCatalog.defaultMap()
            existingPhotoURLs = existing.fotograflar
            localQRToken = existing.qrToken
            trRentalTermsAcceptedAt = existing.trRentalTermsAcceptedAt
            trRentalTermsLanguage = existing.trRentalTermsLanguage
            trRentalTermsSignatureURL = existing.trRentalTermsSignatureURL
            if trRentalTermsAcceptedAt == nil,
               !(existing.trRentalTermsSignatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                trRentalTermsAcceptedAt = Date()
            }
            if let signatureURL = existing.customerSignatureURL {
                StorageImageLoader.shared.loadImage(from: signatureURL) { loadedImage in
                    if let loadedImage {
                        self.customerSignatureImage = loadedImage
                        self.refreshTurkeyVehicleInlinePreview()
                    }
                }
            }
            if let pr = existing.plannedReturnAt {
                plannedReturnPickerDate = pr
            } else if let pc = trHandoverPrefill?.plannedCheckin {
                plannedReturnPickerDate = pc
            } else {
                plannedReturnPickerDate = defaultPlannedReturn(around: exitTarihi)
            }
        } else {
            // Yeni exit için otomatik olarak şu anki tarih ve saat
            exitTarihi = Date()
            yakitSeviyesi = "8/8"
            localQRToken = UUID().uuidString
            vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
            if let pre = trHandoverPrefill {
                linkedFrontDeskCustomerDocId = pre.frontDeskDocumentId
                customerFirstName = pre.customerFirstName
                customerLastName = pre.customerLastName
                customerEmail = pre.customerEmail
                resKodu = pre.navDigits
                if let pc = pre.plannedCheckout {
                    exitTarihi = pc
                }
                if let k = pre.km {
                    kmText = String(k)
                }
                if pickUpBranch.isEmpty, let p = pre.pickupBranchName {
                    pickUpBranch = canonicalTurkeyBranchKey(from: p)
                }
                if dropOffBranch.isEmpty, let d = pre.dropoffBranchName {
                    dropOffBranch = canonicalTurkeyBranchKey(from: d)
                }
                // Pre-fill kiosk-signed rental terms PDF so the customer does not
                // need to sign again during checkout.
                if let nid = pre.customerNationalId, !nid.isEmpty {
                    customerNationalId = nid
                }
                if let kioskPdf = pre.kioskRentalTermsPdfUrl, !kioskPdf.isEmpty {
                    trRentalTermsSignatureURL = kioskPdf
                    trRentalTermsAcceptedAt = Date()
                    trRentalTermsLanguage = pre.kioskRentalTermsLanguage ?? "tr"
                }
            }
            if let pc = trHandoverPrefill?.plannedCheckin {
                plannedReturnPickerDate = pc
            } else {
                plannedReturnPickerDate = defaultPlannedReturn(around: exitTarihi)
            }
        }
        if existingExit == nil, isTurkeyFranchise {
            applyTurkeyDefaultBranchesForNewCheckout()
        }
        startFormListener(token: activeToken)
        if isTurkeyFranchise {
            resolveFrontDeskSupplementForTurkeyCheckout()
            refreshTurkeyTermsInlinePreview()
        }
        // Defaults / prefill are not "user edits" — allow cancel with no nag until something changes.
        hasUnsavedChanges = false

    }

    /// Pending checkout from Operations may lack fields saved only on `frontDeskCustomers` (national ID, kiosk GRT).
    private func resolveFrontDeskSupplementForTurkeyCheckout() {
        guard isTurkeyFranchise else { return }
        let exitId = (existingExit ?? committedExit)?.id.uuidString
            ?? trHandoverPrefill?.linkedExitId
        guard let exitId, !exitId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        FirebaseService.shared.fetchFrontDeskCustomerForLinkedExit(exitId: exitId) { snapshot, _ in
            DispatchQueue.main.async {
                guard let doc = snapshot?.documents.first,
                      let pre = TRFrontDeskHandoverPrefill.parseDocument(doc) else { return }
                linkedFrontDeskCustomerDocId = pre.frontDeskDocumentId
                if customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let nid = pre.customerNationalId, !nid.isEmpty {
                    customerNationalId = nid
                }
                if customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !pre.customerFirstName.isEmpty {
                    customerFirstName = pre.customerFirstName
                }
                if customerLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !pre.customerLastName.isEmpty {
                    customerLastName = pre.customerLastName
                }
                if customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !pre.customerEmail.isEmpty {
                    customerEmail = pre.customerEmail
                }
                let termsURL = (trRentalTermsSignatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if termsURL.isEmpty, let pdf = pre.kioskRentalTermsPdfUrl, !pdf.isEmpty {
                    trRentalTermsSignatureURL = pdf
                    trRentalTermsAcceptedAt = Date()
                    trRentalTermsLanguage = pre.kioskRentalTermsLanguage ?? "tr"
                }
                refreshTurkeyTermsInlinePreview()
            }
        }
    }

    private var kioskFrontDeskDocIdForSignedUrl: String? {
        let fromState = linkedFrontDeskCustomerDocId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromState.isEmpty { return fromState }
        let fromPrefill = trHandoverPrefill?.frontDeskDocumentId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromPrefill.isEmpty ? nil : fromPrefill
    }

    private func fetchKioskTermsPdfViaSignedUrl(completion: @escaping (Data?) -> Void) {
        guard let docId = kioskFrontDeskDocIdForSignedUrl else {
            completion(nil)
            return
        }
        FirebaseService.shared.fetchKioskRentalTermsSignedUrl(
            franchiseId: FirebaseService.shared.currentFranchiseId,
            customerDocId: docId
        ) { result in
            switch result {
            case .success(let signed):
                StorageImageLoader.shared.loadData(from: signed, completion: completion)
            case .failure:
                completion(nil)
            }
        }
    }

    /// Türkiye: yeni checkout’ta teslim alınan / iade lokasyonu alanları boşsa, işlemi yapan şubeyi seç.
    private func applyTurkeyDefaultBranchesForNewCheckout() {
        let raw = TurkiyeGarajSubeleri.matchingBranchStorageKey(among: turkeyBranches)
        guard !raw.isEmpty else { return }
        let key = canonicalTurkeyBranchKey(from: raw)
        guard !key.isEmpty else { return }
        if pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pickUpBranch = key
        }
        if dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dropOffBranch = key
        }
    }

    private var turkeyBranchRegistryIdentity: String {
        viewModel.turkeyFranchiseLocationBranches
            .map { $0.storageKey.uppercased() }
            .sorted()
            .joined(separator: ",")
    }
    
    private func exitDraftPhotoStoragePath(fileName: String = "\(UUID().uuidString).jpg") -> String {
        "franchises/\(FirebaseService.shared.currentFranchiseId)/exit_fotograflari/drafts/\(localQRToken)/\(fileName)"
    }

    private var fleetInspectionContext: FleetInspectionContext {
        FleetInspectionContext.fromCheckout(
            arac: arac,
            resKodu: resKodu,
            customerFirstName: customerFirstName,
            customerLastName: customerLastName,
            customerEmail: customerEmail,
            exitDate: exitTarihi,
            kmText: kmText,
            fuelLevel: yakitSeviyesi,
            pickUpBranch: pickUpBranch,
            dropOffBranch: dropOffBranch,
            handoverPhotos: cameraPhotos + fotograflar,
            operatorName: authManager.userProfile?.displayName ?? authManager.userProfile?.email ?? "—"
        )
    }

    private func openCheckoutCamera() {
        guard !showImagePicker else { return }
        if usesSerialPhotoCapture {
            serialCaptureBaselinePhotoCount = cameraPhotos.count
        }
        showCamera = true
    }

    private func handleSerialPhotoCaptured(_ image: UIImage) {
        let knownGallery = galleryPhotoFingerprintKeys
        Task {
            guard let key = await CheckoutReturnPhotoCapture.fingerprintForNewPhoto(
                image,
                existingKeys: cameraPhotoFingerprintKeys,
                additionalKnownKeys: knownGallery
            ) else { return }
            cameraPhotos.append(image)
            cameraPhotoFingerprintKeys.append(key)
            pendingUploadTracker.startUploadIfNeeded(
                image: image,
                storagePath: exitDraftPhotoStoragePath(),
                fingerprintKey: key,
                trackForSessionDiscard: true
            )
        }
    }

    private func handleSerialPhotoDeleted(at index: Int) {
        CheckoutReturnPhotoCapture.removeCameraPhoto(
            at: index,
            cameraPhotos: &cameraPhotos,
            fingerprintKeys: &cameraPhotoFingerprintKeys,
            pendingUploadTracker: pendingUploadTracker
        )
    }

    private func revertSerialCaptureCameraSession() {
        CheckoutReturnPhotoCapture.revertSerialSession(
            from: serialCaptureBaselinePhotoCount,
            cameraPhotos: &cameraPhotos,
            fingerprintKeys: &cameraPhotoFingerprintKeys,
            pendingUploadTracker: pendingUploadTracker
        )
    }

    private func handleCameraDismiss() {
        guard let capturedImage else { return }
        let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/exit_fotograflari/\(UUID().uuidString).jpg"
        let knownGallery = galleryPhotoFingerprintKeys
        self.capturedImage = nil
        Task {
            guard let key = await CheckoutReturnPhotoCapture.fingerprintForNewPhoto(
                capturedImage,
                existingKeys: cameraPhotoFingerprintKeys,
                additionalKnownKeys: knownGallery
            ) else { return }
            cameraPhotos.append(capturedImage)
            cameraPhotoFingerprintKeys.append(key)
            pendingUploadTracker.startUploadIfNeeded(
                image: capturedImage,
                storagePath: path,
                fingerprintKey: key,
                trackForSessionDiscard: false
            )
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var turkeyDealerInfoSection: some View {
        Section {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                Text("tr_terms.field.commercial_title".localized)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(turkeyCommercialTitle)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                Text("tr_terms.field.branch_name".localized)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(turkeyBranchDisplayName)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Label("tr_form.dealer_header".localized, systemImage: "building.2")
        }
    }

    private var turkeyGeneralTermsKioskSection: some View {
        turkeyComplianceActionSection(
            done: turkeyTermsGateComplete,
            doneMessageKey: "tr_compliance.terms_signed_status",
            requiredMessageKey: "tr_checkout.kiosk_terms_pending",
            previewData: turkeyInlineTermsPdf,
            buttonTitleKey: "tr_checkout.general_rental_terms_button",
            usePrimaryWhenDone: true,
            footerKey: "tr_checkout.kiosk_terms_footer",
            action: { openKioskGrtFullScreenPreview() }
        )
    }

    private var turkeyExitVehicleSignSection: some View {
        Section {
            if customerSignatureImage != nil {
                Text("tr_checkout.exit_pdf_signed_status".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let turkeyInlineVehiclePdf {
                    TurkeyReadOnlyPdfRepresentable(pdfData: turkeyInlineVehiclePdf)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text("tr_compliance.redo_terms_prompt".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if customerSignatureImage == nil {
                HStack {
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                    Button {
                        HapticManager.shared.light()
                        openTurkeyCheckoutComplianceWizard()
                    } label: {
                        Text("tr_checkout.sign_exit_pdf".localized)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WarningPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                }
                .listRowBackground(Color.clear)
            }
        } footer: {
            Text("tr_checkout.exit_pdf_footer".localized)
                .font(.caption)
        }
    }

    private func turkeyComplianceActionSection(
        done: Bool,
        doneMessageKey: String,
        requiredMessageKey: String,
        previewData: Data?,
        buttonTitleKey: String,
        usePrimaryWhenDone: Bool,
        footerKey: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Section {
            if done {
                Text(doneMessageKey.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLoadingKioskTermsPdf {
                    ProgressView("tr_checkout.kiosk_terms_loading".localized)
                } else if let previewData {
                    TurkeyReadOnlyPdfRepresentable(pdfData: previewData)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text(requiredMessageKey.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if done {
                HStack {
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                    Group {
                        if usePrimaryWhenDone {
                            Button {
                                HapticManager.shared.light()
                                action()
                            } label: {
                                Text(buttonTitleKey.localized)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button {
                                HapticManager.shared.light()
                                action()
                            } label: {
                                Text(buttonTitleKey.localized)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WarningPrimaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                }
                .listRowBackground(Color.clear)
            }
        } footer: {
            if let footerKey {
                Text(footerKey.localized)
                    .font(.caption)
            }
        }
    }

    private func draftExitForTurkeyPdf() -> ExitIslemi {
        let base = committedExit ?? existingExit
        let pickUpStored = pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let dropOffStored = dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let legacyBayiOptional = bayiAdi.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let bayiForStorage: String? = isTurkeyFranchise ? nil : legacyBayiOptional
        let testDriverFirstStored = testDriverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let testDriverLastStored = testDriverLastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let mergedPlannedReturn: Date? = isTurkeyFranchise ? plannedReturnPickerDate : nil
        var ex = ExitIslemi(
            aracId: arac.id,
            aracPlaka: arac.plakaFormatli,
            exitTarihi: exitTarihi,
            fotograflar: [],
            notlar: notlar,
            resKodu: resKodu.isEmpty ? "" : "\(codePrefix)\(resKodu)",
            navKodu: isTurkeyFranchise && !resKodu.isEmpty ? "\(codePrefix)\(resKodu)" : nil,
            km: Int(kmText),
            yakitSeviyesi: fuelLevelForStorage(),
            bayiAdi: bayiForStorage,
            pickUpBranch: pickUpStored,
            dropOffBranch: dropOffStored,
            plannedReturnAt: mergedPlannedReturn,
            customerFirstName: customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerLastName: customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerEmail: customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
            testDriverFirstName: testDriverFirstStored,
            testDriverLastName: testDriverLastStored,
            customerSignatureURL: nil,
            qrToken: base?.qrToken ?? localQRToken,
            status: .inProgress,
            createdAt: base?.createdAt ?? Date(),
            createdBy: base?.createdBy,
            assistantCompanyName: arac.assistantCompanyName,
            assistantCompanyPhone: arac.assistantCompanyPhone,
            vehicleItemsChecklist: vehicleItemsChecklist,
            trRentalTermsAcceptedAt: trRentalTermsAcceptedAt,
            trRentalTermsLanguage: trRentalTermsLanguage,
            trRentalTermsSignatureURL: trRentalTermsSignatureURL
        )
        ex.id = base?.id ?? UUID()
        ex.franchiseId = FirebaseService.shared.currentFranchiseId
        return ex
    }

    private func loadDamageImagesForTurkeyExitPdf(completion: @escaping ([UIImage]) -> Void) {
        let urls = arac.hasarKayitlari
            .filter { !$0.fotograflar.isEmpty }
            .sorted { ($0.markerNumber ?? 9999) < ($1.markerNumber ?? 9999) }
            .flatMap(\.fotograflar)
        if urls.isEmpty {
            completion([])
            return
        }
        var pairs: [(Int, UIImage)] = []
        let g = DispatchGroup()
        let lock = NSLock()
        for (idx, urlString) in urls.enumerated() {
            g.enter()
            StorageImageLoader.shared.loadImage(from: urlString) { img in
                if let img {
                    lock.lock()
                    pairs.append((idx, img))
                    lock.unlock()
                }
                g.leave()
            }
        }
        g.notify(queue: .main) {
            completion(pairs.sorted { $0.0 < $1.0 }.map { $0.1 })
        }
    }

    private func refreshTurkeyTermsInlinePreview() {
        guard isTurkeyFranchise else { return }
        guard let rawURL = trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            turkeyInlineTermsPdf = nil
            isLoadingKioskTermsPdf = false
            return
        }
        isLoadingKioskTermsPdf = true

        let handleData: (Data?) -> Void = { data in
            DispatchQueue.main.async {
                isLoadingKioskTermsPdf = false
                if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                    turkeyInlineTermsPdf = data
                } else {
                    turkeyInlineTermsPdf = nil
                }
            }
        }

        // gs:// URIs (post-GRT-privatization) cannot be fetched with a plain HTTPS GET.
        // Resolve through the Storage SDK first; fall back to the candidate chain on failure.
        if rawURL.lowercased().hasPrefix("gs://") {
            StorageImageLoader.shared.loadStorageGSData(gsUri: rawURL) { primary in
                if let primary, TurkeyRentalTermsPlaceholders.isPdfDocumentData(primary) {
                    handleData(primary)
                    return
                }
                fetchKioskTermsPdfViaSignedUrl(completion: handleData)
            }
            return
        }

        // Legacy public URL (HTTPS) — direct download; signed URL fallback if link expired.
        StorageImageLoader.shared.loadData(from: rawURL) { data in
            if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                handleData(data)
            } else {
                fetchKioskTermsPdfViaSignedUrl(completion: handleData)
            }
        }
    }

    private func openKioskGrtFullScreenPreview() {
        if let data = turkeyInlineTermsPdf, !data.isEmpty {
            grtPdfFullScreenItem = TurkeyPdfPreviewItem(data: data, title: "tr_checkout.general_rental_terms_button".localized)
            return
        }
        isLoadingKioskTermsPdf = true
        let finish: (Data?) -> Void = { data in
            DispatchQueue.main.async {
                isLoadingKioskTermsPdf = false
                guard let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) else {
                    ToastManager.shared.show("tr_checkout.kiosk_terms_pending".localized, type: .warning)
                    return
                }
                turkeyInlineTermsPdf = data
                grtPdfFullScreenItem = TurkeyPdfPreviewItem(data: data, title: "tr_checkout.general_rental_terms_button".localized)
            }
        }
        guard let rawURL = trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            fetchKioskTermsPdfViaSignedUrl(completion: finish)
            return
        }
        if rawURL.lowercased().hasPrefix("gs://") {
            StorageImageLoader.shared.loadStorageGSData(gsUri: rawURL) { primary in
                if let primary, TurkeyRentalTermsPlaceholders.isPdfDocumentData(primary) {
                    finish(primary)
                } else {
                    fetchKioskTermsPdfViaSignedUrl(completion: finish)
                }
            }
            return
        }
        StorageImageLoader.shared.loadData(from: rawURL) { data in
            if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                finish(data)
            } else {
                fetchKioskTermsPdfViaSignedUrl(completion: finish)
            }
        }
    }

    private func openTurkeyCheckoutComplianceWizard() {
        guard turkeyTermsGateComplete else {
            ToastManager.shared.show("tr_checkout.terms_required_first".localized, type: .warning)
            return
        }
        guard !allPhotos.isEmpty else {
            ToastManager.shared.show("tr_terms.need_photo_first".localized, type: .warning)
            return
        }
        loadDamageImagesForTurkeyExitPdf { damage in
            turkeyWizardDamagePhotos = damage
            showTurkeyComplianceWizard = true
        }
    }

    private func refreshTurkeyVehicleInlinePreview() {
        guard isTurkeyFranchise, let sig = customerSignatureImage, !allPhotos.isEmpty else {
            turkeyInlineVehiclePdf = nil
            return
        }
        loadDamageImagesForTurkeyExitPdf { damage in
            let pdf = ExitPDFGenerator.shared.makeTurkeyCheckoutPdfDataWithCustomerSignature(
                exit: draftExitForTurkeyPdf(),
                arac: arac,
                vehiclePhotos: allPhotos,
                damagePhotos: damage,
                franchiseDisplayName: turkeyCommercialTitle,
                staffSignerNameFallback: authManager.userProfile?.fullName,
                customerSignature: sig
            )
            DispatchQueue.main.async {
                turkeyInlineVehiclePdf = pdf
            }
        }
    }
    
    @ViewBuilder
    private func operationIdentitySection(exit: ExitIslemi?, plateInteractive: Bool, codeInteractive: Bool) -> some View {
        let code: String? = {
            if let exit, !exit.resKodu.isEmpty { return exit.resKodu }
            let digits = resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !digits.isEmpty else { return nil }
            return "\(codePrefix)\(digits)"
        }()
        Section {
            OperationIdentityLinkRow(
                plate: arac.plakaFormatli,
                reservationCode: code,
                reservationLabel: codeFieldLabel.localized,
                vehicle: arac,
                exit: exit,
                plateInteractive: plateInteractive,
                codeInteractive: codeInteractive
            )
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var exitBilgileriSection: some View {
        Section {
                DatePicker("Check Out Date".localized, selection: $exitTarihi, displayedComponents: [.date, .hourAndMinute])

                if isTurkeyFranchise {
                    DatePicker("operations.planned_return".localized, selection: $plannedReturnPickerDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                HStack {
                    Image(systemName: "number.square.fill")
                        .foregroundColor(.blue)
                    Text(codeFieldLabel.localized)
                    Spacer()
                    HStack(spacing: 2) {
                        Text(codePrefix)
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                        TextField("Enter numbers".localized, text: $resKodu)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                }

                TextField("KM (optional)".localized, text: $kmText)
                    .keyboardType(.numberPad)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fuel level".localized)
                        Spacer()
                        Text(yakitSeviyesi)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundColor(fuelTextColor)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(fuelEighthsValue) },
                            set: { newValue in
                                let eighths = min(8, max(0, Int(newValue.rounded())))
                                yakitSeviyesi = "\(eighths)/8"
                            }
                        ),
                        in: 0...8,
                        step: 1
                    )
                    .tint(fuelTextColor)
                }
                if isTurkeyFranchise {
                    turkeyBranchMenuRow(
                        title: "operations.pickup_branch_optional".localized,
                        selection: $pickUpBranch,
                        selectedTitle: pickupBranchDisplayTitle
                    )
                    turkeyBranchMenuRow(
                        title: "operations.dropoff_branch_optional".localized,
                        selection: $dropOffBranch,
                        selectedTitle: dropoffBranchDisplayTitle
                    )
                    Button {
                        showVehicleItemsSheet = true
                    } label: {
                        HStack {
                            Label("operations.items_with_vehicle_yes_no".localized, systemImage: "checklist")
                            Spacer()
                            Text("\(vehicleItemsChecklist.values.filter { $0 }.count)/\(VehicleChecklistCatalog.items.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                customerContactAndSignatureSection
                
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

        } header: {
            Label("Check Out Information".localized, systemImage: "car.circle.fill")
        }
    }

    private var activeToken: String {
        committedExit?.qrToken ?? existingExit?.qrToken ?? localQRToken
    }

    @ViewBuilder
    private var customerContactAndSignatureSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.teal)
                    .font(.system(size: 15, weight: .medium))
                Text(isTurkeyFranchise ? "Customer Information".localized : "Customer Information & Signature".localized)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                if hasCustomerContactData {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                customerTextField("First Name".localized, text: $customerFirstName)
                    .disabled(isHandoverContactReadOnly)
                Divider().padding(.leading, 12)
                customerTextField("Last Name".localized, text: $customerLastName)
                    .disabled(isHandoverContactReadOnly)
                Divider().padding(.leading, 12)
                customerTextField("Email".localized, text: $customerEmail, email: true)
                    .disabled(isHandoverContactReadOnly)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .cornerRadius(10)

            if isTurkeyFranchise {
                Toggle("operations.show_additional_driver".localized, isOn: $showAdditionalDriverOnFile)
                    .padding(.top, 10)
                if showAdditionalDriverOnFile {
                    VStack(spacing: 0) {
                        TextField("operations.additional_driver_first_name".localized, text: $testDriverFirstName)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .textInputAutocapitalization(.words)
                        Divider().padding(.leading, 12)
                        TextField("operations.additional_driver_last_name".localized, text: $testDriverLastName)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .textInputAutocapitalization(.words)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .cornerRadius(10)
                    .padding(.top, 6)
                }
            }

            if !isTurkeyFranchise {
                Button {
                    showSignatureSheet = true
                } label: {
                    HStack {
                        Image(systemName: "signature")
                        Text(customerSignatureImage == nil ? "Add Signature".localized : "Update Signature".localized)
                        Spacer()
                        if customerSignatureImage != nil {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .disabled(isHandoverContactReadOnly)
                Text("operations.signature_official_driver_hint".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if let signature = customerSignatureImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: signature)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            .cornerRadius(8)
                        Button {
                            customerSignatureImage = nil
                            signatureWasRemoved = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .background(Color.white.clipShape(Circle()))
                        }
                        .padding(6)
                        .disabled(isHandoverContactReadOnly)
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("tr_checkout.exit_pdf_footer".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                if customerSignatureImage != nil {
                    Label("tr_terms.customer_vehicle_pdf_sign_ready".localized, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 6)
                }
            }
            Toggle(isOn: $rememberCustomerContact) {
                Text("Remember customer (name + email) for auto-fill next time".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .disabled(isHandoverContactReadOnly)
        }
        .padding(.vertical, 4)
    }

    private func customerTextField(_ title: String, text: Binding<String>, email: Bool = false) -> some View {
        TextField(title, text: text)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .keyboardType(email ? .emailAddress : .default)
            .textInputAutocapitalization(email ? .never : .words)
            .autocorrectionDisabled(email)
    }

    private func turkeyBranchMenuRow(title: String, selection: Binding<String>, selectedTitle: String) -> some View {
        Menu {
            ForEach(turkeyBranches) { branch in
                Button {
                    selection.wrappedValue = branch.storageKey
                } label: {
                    HStack {
                        Text(branch.displayName)
                        if selection.wrappedValue == branch.storageKey {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(selectedTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func canonicalTurkeyBranchKey(from raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        let key = TurkiyeGarajSubeleri.canonicalGarageStorageKey(for: raw)
        if !key.isEmpty { return key }
        let norm = Self.normalizedTurkeyBranchId(trimmed)
        if let m = viewModel.turkeyFranchiseLocationBranches.first(where: {
            Self.normalizedTurkeyBranchId($0.storageKey) == norm
                || $0.storageKey.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return m.storageKey
        }
        return trimmed
    }

    private func branchDisplayTitle(for storedKey: String) -> String {
        let value = storedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Select".localized }
        let norm = Self.normalizedTurkeyBranchId(value)
        if let b = turkeyBranches.first(where: {
            Self.normalizedTurkeyBranchId($0.storageKey) == norm
                || $0.storageKey.caseInsensitiveCompare(value) == .orderedSame
        }) {
            return b.displayName
        }
        return TurkiyeGarajSubeleri.displayTitle(forStoredKey: value)
    }

    private static func normalizedTurkeyBranchId(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private func startFormListener(token: String) {
        formListener?.remove()
        formListener = Firestore.firestore()
            .collection("franchises")
            .document(FirebaseService.shared.currentFranchiseId)
            .collection("checkoutFormData")
            .document(token)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                DispatchQueue.main.async {
                    if let v = data["firstName"] as? String, !v.isEmpty { customerFirstName = v }
                    if let v = data["lastName"]  as? String, !v.isEmpty { customerLastName  = v }
                    if let v = data["email"]     as? String, !v.isEmpty { customerEmail     = v }
                    if let b64 = data["signatureBase64"] as? String {
                        let digest = b64.hashValue
                        guard digest != lastSignatureBase64Digest else { return }
                        lastSignatureBase64Digest = digest
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let imgData = Data(base64Encoded: b64),
                                  let img = UIImage(data: imgData) else { return }
                            DispatchQueue.main.async {
                                customerSignatureImage = img
                            }
                        }
                    }
                }
            }
    }
    
    private static let photoThumbSize: CGFloat = 100
    private static let photoThumbRowHeight: CGFloat = 108

    private var fotografSection: some View {
        Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(existingPhotoURLs.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                KFImage(URL(string: existingPhotoURLs[index]))
                                    .placeholder { Color.gray.opacity(0.15) }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: existingPhotoURLs, startIndex: index)
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
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                        }

                        ForEach(fotograflar.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: fotograflar[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        photoGallerySession = PhotoGalleryFullScreenSession(images: fotograflar + cameraPhotos, startIndex: index)
                                    }

                                VStack(alignment: .trailing, spacing: 2) {
                                    Button {
                                        CheckoutReturnPhotoCapture.removeGalleryPhoto(
                                            at: index,
                                            fotograflar: &fotograflar,
                                            fingerprintKeys: &galleryPhotoFingerprintKeys,
                                            pendingUploadTracker: pendingUploadTracker
                                        )
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
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                        }

                        ForEach(cameraPhotos.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: cameraPhotos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        photoGallerySession = PhotoGalleryFullScreenSession(images: fotograflar + cameraPhotos, startIndex: fotograflar.count + index)
                                    }

                                VStack(alignment: .trailing, spacing: 2) {
                                    Button {
                                        CheckoutReturnPhotoCapture.removeCameraPhoto(
                                            at: index,
                                            cameraPhotos: &cameraPhotos,
                                            fingerprintKeys: &cameraPhotoFingerprintKeys,
                                            pendingUploadTracker: pendingUploadTracker
                                        )
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
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: Self.photoThumbRowHeight)

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
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(showCamera)

                    Button(action: openCheckoutCamera) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Take Photo".localized)
                            Spacer()
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(showImagePicker)
                }
        } header: {
            Label("Photos".localized, systemImage: "camera.fill")
        }
    }
    
    private var completeSection: some View {
        Section {
            if isTurkeyFranchise {
                HStack {
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                    Button {
                        HapticManager.shared.medium()
                        guard checkoutTotalPhotoCount >= 1 else {
                            ToastManager.shared.show("At least one photo is required".localized, type: .error)
                            return
                        }
                        showCompleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            HStack(spacing: 8) {
                                if isUploading {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Uploading Photos...".localized)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Complete Check Out".localized)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SuccessButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(isUploading || !turkeyComplianceReadyForComplete)
                    .opacity(turkeyComplianceReadyForComplete ? 1 : 0.45)
                    Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                }
                .listRowBackground(Color.clear)
            } else {
                Button {
                    HapticManager.shared.medium()
                    guard checkoutTotalPhotoCount >= 1 else {
                        ToastManager.shared.show("At least one photo is required".localized, type: .error)
                        return
                    }
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
                .disabled(isUploading || checkoutTotalPhotoCount < 1)
                .listRowBackground(Color.green.opacity(0.85))
                .foregroundColor(.white)
            }
        } header: {
            Label("Finalize check out".localized, systemImage: "checkmark.seal.fill")
                .textCase(nil)
                .font(.subheadline)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mark this check out as completed and close the form.".localized)
                    .font(.caption)
                if checkoutTotalPhotoCount < 1 {
                    Text("At least one photo is required".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    /// Total photos available for this check-out (saved URLs + not yet uploaded).
    private var checkoutTotalPhotoCount: Int {
        let remote = existingPhotoURLs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return remote + fotograflar.count + cameraPhotos.count
    }

    /// Preserves order, dedupes; always includes Firestore `base.fotograflar` so RES / parked edits never drop photos.
    private func mergedExitPhotoURLs(base: ExitIslemi?, existing: [String], newUploads: [String]) -> [String] {
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
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 7)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: completionProgress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                            .animation(.linear(duration: 0.2), value: completionProgress)
                        Text("\(Int((completionProgress * 100).rounded()))%")
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
    
    private func applyExitSaveAfterUploads(
        status: ExitStatus,
        signatureURL: String?,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        let baseForUpdate = self.committedExit ?? self.existingExit
        let editingExistingSession = self.committedExit != nil || self.existingExit != nil
        let mergedPlannedReturn: Date? = isTurkeyFranchise ? plannedReturnPickerDate : nil
        let pickUpStored = pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let dropOffStored = dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let legacyBayiOptional = bayiAdi.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        /// Turkey uses `pickUpBranch` / `dropOffBranch` only; legacy `bayiAdi` remains for non-TR.
        let bayiForStorage: String? = isTurkeyFranchise ? nil : legacyBayiOptional
        let testDriverFirstStored = isTurkeyFranchise ? testDriverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString : nil
        let testDriverLastStored = isTurkeyFranchise ? testDriverLastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString : nil
        let finalPhotoURLs: [String]
        if editingExistingSession {
            finalPhotoURLs = mergedExitPhotoURLs(
                base: baseForUpdate,
                existing: self.existingPhotoURLs,
                newUploads: sortedNewPhotos
            )
        } else {
            finalPhotoURLs = sortedNewPhotos
        }

        let currentExit: ExitIslemi

        if let base = baseForUpdate {
            var updatedExit = ExitIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                exitTarihi: exitTarihi,
                fotograflar: finalPhotoURLs,
                notlar: notlar,
                resKodu: resKodu.isEmpty ? "" : "\(codePrefix)\(resKodu)",
                navKodu: isTurkeyFranchise && !resKodu.isEmpty ? "\(codePrefix)\(resKodu)" : nil,
                km: Int(kmText),
                yakitSeviyesi: fuelLevelForStorage(),
                bayiAdi: bayiForStorage,
                pickUpBranch: pickUpStored,
                dropOffBranch: dropOffStored,
                plannedReturnAt: mergedPlannedReturn,
                customerFirstName: customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerLastName: customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerEmail: customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
                testDriverFirstName: testDriverFirstStored,
                testDriverLastName: testDriverLastStored,
                customerSignatureURL: signatureURL,
                checkoutEmailSentAt: base.checkoutEmailSentAt,
                checkoutEmailLastStatus: base.checkoutEmailLastStatus,
                checkoutEmailRecipient: base.checkoutEmailRecipient,
                qrToken: base.qrToken,
                status: status,
                createdAt: base.createdAt,
                createdBy: base.createdBy,
                assistantCompanyName: arac.assistantCompanyName,
                assistantCompanyPhone: arac.assistantCompanyPhone,
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil,
                trRentalTermsAcceptedAt: isTurkeyFranchise ? trRentalTermsAcceptedAt : nil,
                trRentalTermsLanguage: isTurkeyFranchise ? trRentalTermsLanguage : nil,
                trRentalTermsSignatureURL: isTurkeyFranchise ? trRentalTermsSignatureURL : nil
            )
            updatedExit.id = base.id
            // Preserve original Firestore path metadata + franchise scope on updates
            // so the write targets the exact same document and never spawns a new row.
            updatedExit.firestoreDocumentId = base.firestoreDocumentId
            updatedExit.firestoreScopedFranchiseId = base.firestoreScopedFranchiseId
            if !base.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedExit.franchiseId = base.franchiseId
            }
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
                resKodu: resKodu.isEmpty ? "" : "\(codePrefix)\(resKodu)",
                navKodu: isTurkeyFranchise && !resKodu.isEmpty ? "\(codePrefix)\(resKodu)" : nil,
                km: Int(kmText),
                yakitSeviyesi: fuelLevelForStorage(),
                bayiAdi: bayiForStorage,
                pickUpBranch: pickUpStored,
                dropOffBranch: dropOffStored,
                plannedReturnAt: mergedPlannedReturn,
                customerFirstName: customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerLastName: customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerEmail: customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
                testDriverFirstName: testDriverFirstStored,
                testDriverLastName: testDriverLastStored,
                customerSignatureURL: signatureURL,
                qrToken: localQRToken,
                status: status,
                createdBy: currentUserId,
                assistantCompanyName: arac.assistantCompanyName,
                assistantCompanyPhone: arac.assistantCompanyPhone,
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil,
                trRentalTermsAcceptedAt: isTurkeyFranchise ? trRentalTermsAcceptedAt : nil,
                trRentalTermsLanguage: isTurkeyFranchise ? trRentalTermsLanguage : nil,
                trRentalTermsSignatureURL: isTurkeyFranchise ? trRentalTermsSignatureURL : nil
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
            galleryPhotoFingerprintKeys = []
            cameraPhotoFingerprintKeys = []
        }

        if !usedOfflineMediaQueue {
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendExitNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
        }

        if rememberCustomerContact, status == .completed || status == .parked {
            let em = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if em.contains("@"), em.contains(".") {
                FirebaseService.shared.upsertCustomerContactRemember(
                    firstName: customerFirstName,
                    lastName: customerLastName,
                    email: em,
                    source: "ios_exit",
                    completion: { _ in }
                )
            }
        }

        if !didPublishTrHandoverLifecycle,
           isTurkeyFranchise,
           status == .completed || status == .parked {
            didPublishTrHandoverLifecycle = true
            let linkedExitIdString = currentExit.id.uuidString
            let franchiseForLifecycle = currentFranchiseId
            // Cloud Function `onExitCompletedEnsureExpectedReturn` also writes this lifecycle
            // (auto-iade id when planned check-in exists); the iOS write is a redundant
            // belt-and-suspenders for cases where the FD doc lookup at CF time misses.
            if let pre = trHandoverPrefill {
                FirebaseService.shared.updateFrontDeskCustomerLifecycleForReturn(
                    franchiseId: franchiseForLifecycle,
                    frontDeskDocId: pre.frontDeskDocumentId,
                    linkedExitId: linkedExitIdString,
                    linkedIadeId: nil,
                    completion: { _ in }
                )
            } else {
                FirebaseService.shared.fetchFrontDeskCustomerForLinkedExit(
                    exitId: linkedExitIdString
                ) { snapshot, _ in
                    guard let docId = snapshot?.documents.first?.documentID,
                          !docId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }
                    FirebaseService.shared.updateFrontDeskCustomerLifecycleForReturn(
                        franchiseId: franchiseForLifecycle,
                        frontDeskDocId: docId,
                        linkedExitId: linkedExitIdString,
                        linkedIadeId: nil,
                        completion: { _ in }
                    )
                }
            }
        }

        isUploading = false
        hasUnsavedChanges = false
        pendingUploadTracker.commitSessionToOperation()

        if status == .completed {
            isSaved = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                completionSucceeded = true
                completionProgress = 1
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendExitNotification
            print("✅ Exit completed - dismissing view")
            LiveActivityTracker.shared.record(
                .checkoutCompleted,
                title: "Check-out completed",
                subtitle: "RES \(currentExit.resKodu) · \(currentExit.km.map { "\($0) km" } ?? "—")",
                plate: arac.plaka,
                recordId: currentExit.id.uuidString,
                userProfile: authManager.userProfile,
                force: true
            )
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
                completionProgress = 1
            }
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos will upload when you are back online.".localized, type: .success)
            }
            LiveActivityTracker.shared.record(
                .checkoutParked,
                title: "Check-out parked",
                subtitle: "RES \(currentExit.resKodu)",
                plate: arac.plaka,
                recordId: currentExit.id.uuidString,
                userProfile: authManager.userProfile,
                force: true
            )
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

    private struct ExitSignatureUploadOutcome {
        var firestoreURL: String?
    }

    private func uploadExitSignatureIfNeeded(completion: @escaping (Result<ExitSignatureUploadOutcome, Error>) -> Void) {
        if signatureWasRemoved && customerSignatureImage == nil {
            completion(.success(ExitSignatureUploadOutcome(firestoreURL: nil)))
            return
        }

        guard let signatureImage = customerSignatureImage, let pngData = signatureImage.pngData() else {
            completion(.success(ExitSignatureUploadOutcome(firestoreURL: existingExit?.customerSignatureURL)))
            return
        }

        let path = "exit_signatures/\(UUID().uuidString).png"
        FirebaseService.shared.uploadData(pngData, path: path, contentType: "image/png") { url, error in
            if let url = url {
                self.signatureWasRemoved = false
                completion(.success(ExitSignatureUploadOutcome(firestoreURL: url)))
                return
            }
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(ExitSignatureUploadOutcome(firestoreURL: self.existingExit?.customerSignatureURL)))
        }
    }

    func kaydet(status: ExitStatus) {
        if status == .completed {
            let n = checkoutTotalPhotoCount
            if n < 1 {
                isUploading = false
                if operationFlowState.canTransition(to: .draft) {
                    operationFlowState = .draft
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionOverlay = false
                }
                ToastManager.shared.show("At least one photo is required".localized, type: .error)
                return
            }
        }
        if isTurkeyFranchise && (status == .completed || status == .parked) && !turkeyComplianceReadyForComplete {
            isUploading = false
            if operationFlowState.canTransition(to: .draft) {
                operationFlowState = .draft
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                showCompletionOverlay = false
            }
            ToastManager.shared.show("tr_terms.required_complete".localized, type: .error)
            openTurkeyCheckoutComplianceWizard()
            return
        }
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        completionProgress = 0.05
        uploadedPhotoURLs = []

        let stableDocumentId = (committedExit ?? existingExit)?.id ?? UUID()
        uploadExitSignatureIfNeeded { signatureResult in
            switch signatureResult {
            case .failure(let error):
                self.isUploading = false
                self.operationFlowState = .failed
                if status == .completed {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionOverlay = false
                    }
                }
                ErrorManager.shared.showError(error, context: "Checkout Save")
            case .success(let signatureOutcome):
                let resolvedSignatureURL = signatureOutcome.firestoreURL

        let allPhotosToUpload = fotograflar + cameraPhotos

        var indexedPhotoURLs: [(index: Int, url: String)] = []
        var uploadErrors: [Error] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for (index, foto) in allPhotosToUpload.enumerated() {
            if let preUploadedURL = self.pendingUploadTracker.uploadedURL(for: foto) {
                indexedPhotoURLs.append((index: index, url: preUploadedURL))
                let totalCount = allPhotosToUpload.count
                if totalCount > 0 {
                    self.completionProgress = min(0.95, 0.1 + (Double(indexedPhotoURLs.count) / Double(totalCount)) * 0.8)
                }
                continue
            }
            group.enter()
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/exit_fotograflari/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        indexedPhotoURLs.append((index: index, url: url))
                        lock.unlock()
                        let totalCount = allPhotosToUpload.count
                        if totalCount > 0 {
                            self.completionProgress = min(0.95, 0.1 + (Double(indexedPhotoURLs.count) / Double(totalCount)) * 0.8)
                        }
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
                } else if status == .completed {
                    // Partial failure during a Complete: block the save so we never persist
                    // a "Completed" exit missing some of the staff's photos. The user gets
                    // a chance to retry — the operation reverts to Draft state.
                    self.isUploading = false
                    self.operationFlowState = .failed
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionOverlay = false
                    }
                    ToastManager.shared.show(
                        String(
                            format: "%d out of %d photos failed to upload. Please retry before completing.".localized,
                            failedCount,
                            totalCount
                        ),
                        type: .error
                    )
                    if self.operationFlowState.canTransition(to: .draft) {
                        self.operationFlowState = .draft
                    }
                    return
                } else {
                    // In Progress / Parked saves stay tolerant of partial failures so staff
                    // do not lose the entire draft because a few uploads timed out.
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
                        signatureURL: resolvedSignatureURL,
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
                signatureURL: resolvedSignatureURL,
                sortedNewPhotos: sortedNewPhotos,
                usedOfflineMediaQueue: false,
                stableNewDocumentId: stableDocumentId
            )
        }
            }
        }
    }
    
    private func resolvedStatusForCompletion() -> ExitStatus {
        let trimmedRes = resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVehicleParked && trimmedRes.isEmpty {
            return .parked
        }
        return .completed
    }
    
    private var fuelEighthsValue: Int {
        let cleaned = yakitSeviyesi.trimmingCharacters(in: .whitespacesAndNewlines)
        let numerator = cleaned.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let parsed = Int(numerator) {
            return min(8, max(0, parsed))
        }
        return 8
    }
    
    private var fuelTextColor: Color {
        fuelEighthsValue >= 8 ? .green : .secondary
    }
    
    private func normalizedFuelLevel(_ raw: String?) -> String {
        guard let raw else { return "8/8" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "8/8" }
        let numerator = trimmed.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        if let parsed = Int(numerator) {
            let clamped = min(8, max(0, parsed))
            return "\(clamped)/8"
        }
        return "8/8"
    }
    
    /// Persist as Wheelsys-compatible 0...8 value while UI shows x/8.
    private func fuelLevelForStorage() -> String? {
        "\(fuelEighthsValue)"
    }
}

private struct VehicleItemsChecklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selections: [String: Bool]

    var body: some View {
        NavigationStack {
            List {
                ForEach(VehicleChecklistCatalog.items, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Button {
                                selections[item.key] = true
                            } label: {
                                Text("Yes".localized)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background((selections[item.key] ?? false) ? Color.green.opacity(0.24) : Color.gray.opacity(0.12))
                                    .foregroundStyle((selections[item.key] ?? false) ? Color.green : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            Button {
                                selections[item.key] = false
                            } label: {
                                Text("No".localized)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background((selections[item.key] ?? false) ? Color.gray.opacity(0.12) : Color.red.opacity(0.22))
                                    .foregroundStyle((selections[item.key] ?? false) ? Color.primary : Color.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Items with Vehicle".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension String {
    var nilIfEmptyString: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct CheckoutQRCodeView: View {
    let url: String

    var body: some View {
        if let img = makeQRImage(from: url) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func makeQRImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(ciImage: scaled)
        }
        return UIImage(cgImage: cgImage)
    }
}

struct CheckoutQRSheet: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var urlString: String {
        let franchiseId = FirebaseService.shared.currentFranchiseId
        return "https://greenmotionapp-33413.web.app/checkout.html?token=\(token)&franchise=\(franchiseId)"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 16)

                    VStack(spacing: 8) {
                        Text("Customer Self-Fill".localized)
                            .font(.system(size: 22, weight: .bold))
                            .tracking(0.3)
                        Text("Ask the customer to scan this code\nto fill in their check-out details.".localized)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 24)

                    let qrSize = min(geo.size.width - 64, 320.0)
                    CheckoutQRCodeView(url: urlString)
                        .frame(width: qrSize, height: qrSize)
                        .padding(20)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 20, x: 0, y: 8)

                    Spacer(minLength: 32)

                    Button {
                        guard let url = URL(string: urlString) else { return }
                        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(av, animated: true)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Share QR Link".localized)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.label), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
    }
}

