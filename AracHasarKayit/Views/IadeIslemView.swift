import SwiftUI
import Kingfisher
import FirebaseFirestore
import CoreImage.CIFilterBuiltins

struct IadeIslemView: View {
    private enum ReturnCompletionPhase {
        case processingReturn
        case completed
    }
    
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    var existingIade: IadeIslemi? = nil // For editing existing returns
    /// Turkey: prefill from web Front Desk after checkout (`return_ready`).
    var trReturnHandoverPrefill: TRFrontDeskHandoverPrefill? = nil
    /// CH: WheelSys journal / plate-scan return prefill.
    var wheelSysReturnPrefill: WheelSysReturnOperationPrefill? = nil
    var onIadeCompleted: ((IadeIslemi) -> Void)? = nil
    
    @State private var iadeTarihi = Date()
    @State private var notlar = ""
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
    @State private var checklist = ReturnChecklist()
    @State private var showCompletionOverlay = false
    @State private var completionPhase: ReturnCompletionPhase = .processingReturn
    @State private var operationFlowState: OperationFlowState = .draft
    @State private var pulseAnimation = false
    @State private var completionProgress: Double = 0
    @StateObject private var pendingUploadTracker = PendingPhotoUploadTracker()
    @State private var customerFirstName = ""
    @State private var customerLastName = ""
    @State private var customerEmail = ""
    @State private var customerNationalId = ""
    @State private var testDriverFirstName = ""
    @State private var showAdditionalDriverFields = false
    @State private var testDriverLastName = ""
    @State private var kmText = ""
    @State private var yakitSeviyesi = "8/8"
    @State private var pickUpBranch = ""
    @State private var dropOffBranch = ""
    @State private var customerSignatureImage: UIImage?
    @State private var lastSignatureBase64Digest = 0
    @State private var showSignatureSheet = false
    @State private var signatureWasRemoved = false
    /// After first save in this session, further saves update this return (avoids duplicate returns on In Progress re-saves).
    @State private var committedIade: IadeIslemi?
    @State private var formListener: ListenerRegistration?
    @State private var showQRSheet = false
    @State private var showVehicleItemsSheet = false
    /// Stable token for this return session — used even before first save
    @State private var localQRToken: String = UUID().uuidString
    @State private var vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
    @State private var didPublishTrReturnHandoverLifecycle = false
    @State private var showQuickDamageSheet = false
    @State private var showConditionFormAfterDamageSheet = false
    @State private var rememberCustomerContact = true
    @State private var rememberLookupTask: Task<Void, Never>?
    @State private var trRentalTermsAcceptedAt: Date?
    @State private var trRentalTermsLanguage: String?
    @State private var trRentalTermsSignatureURL: String?
    @State private var showTurkeyTermsWizard = false
    @State private var showTurkeyVehicleWizard = false
    @State private var turkeyWizardDamagePhotos: [UIImage] = []
    @State private var turkeyWizardPrefilledTermsPdfData: Data?
    @State private var turkeyInlineTermsPdf: Data?
    @State private var turkeyInlineVehiclePdf: Data?
    // WheelSys return pre-check-in (CH only).
    @StateObject private var wheelsysCheckin = WheelSysReturnCheckinCoordinator()
    @State private var wheelsysPreviewLoaded = false
    @State private var wheelsysPreviewEntityKey = ""
    @State private var wheelsysNewNoteText = ""
    @State private var showWheelSysNotesSidebar = false
    @State private var wheelsysNoteDeleting = false
    @State private var wheelsysNoteSaving = false
    @State private var wheelsysNoteStatus: String?
    @State private var wheelsysNoteStatusIsError = false
    @State private var wheelSysNavKodu = ""
    @State private var wheelsysPrecheckinStatus: String?
    @State private var wheelsysPrecheckinIsError = false
    @State private var wheelsysPrecheckinBusy = false
    @State private var wheelsysPrecheckinSucceeded = false
    @State private var wheelsysPrecheckinContext: WheelSysPrecheckinContext?
    @State private var wheelsysPrecheckinContextLoading = false
    @State private var wheelsysPrecheckinContextTask: Task<Void, Never>?
    @State private var showWheelSysDamageHistory = false

    // Photo preview state (one fullScreen session — avoids stacked covers / blank preview)
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    private var sectionHeaderFont: Font { .system(size: 12, weight: .semibold, design: .default) }
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

    /// WheelSys return/check-in — CH franchise id only (not country fallback).
    private var wheelSysCHOpsEnabled: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    private var shouldSkipKioskFormListener: Bool {
        wheelSysCHOpsEnabled && wheelSysReturnPrefill != nil
    }
    private var usesCHPalantirReturnChrome: Bool {
        wheelSysCHOpsEnabled && !isTurkeyFranchise
    }
    private var isGermanyFranchise: Bool {
        FranchiseCapabilityMatrix.isGermanyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    private var processDatePickerComponents: DatePicker.Components {
        isGermanyFranchise ? [.date, .hourAndMinute] : [.date]
    }
    private var returnPhotoHandoverDate: Date {
        if let lid = linkedExitIdForReturn,
           let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) {
            return ex.exitTarihi
        }
        return iadeTarihi
    }
    private var returnPhotoReturnDate: Date { iadeTarihi }
    private var isCustomerInfoReadOnlyFromOperation: Bool {
        trReturnHandoverPrefill != nil || isWheelSysCustomerPrefilled
    }
    private var isWheelSysCustomerPrefilled: Bool {
        guard wheelSysCHOpsEnabled else { return false }
        if let prefill = wheelSysReturnPrefill,
           !prefill.driverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let preview = wheelsysCheckin.preview {
            let combined = preview.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty { return true }
            let parts = [preview.customerFirstName, preview.customerLastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return true }
        }
        return false
    }
    private var wheelSysCustomerNameBinding: Binding<String> {
        Binding(
            get: {
                let first = customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let last = customerLastName.trimmingCharacters(in: .whitespacesAndNewlines)
                if last.isEmpty { return first }
                return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                customerFirstName = trimmed
                customerLastName = ""
            }
        )
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
            preferDropOffForReturn: true,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
            franchiseGarageBranches: viewModel.franchiseGarageBranches
        )
    }

    private var turkeyTermsGateComplete: Bool {
        trRentalTermsAcceptedAt != nil
            && !(trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Turkey iade: araç iade formu imzası + en az bir fotoğraf (GRT checkout’ta alındı).
    private var turkeyComplianceReadyForComplete: Bool {
        guard isTurkeyFranchise else { return true }
        if checklist.customerRefusedSignature { return !allPhotos.isEmpty }
        return customerSignatureImage != nil && !allPhotos.isEmpty
    }

    /// Quick damage: bağlı çıkış (kayıtlı veya Front Desk ön dolum).
    private var quickDamageLinkedExitId: UUID? {
        committedIade?.linkedExitId
            ?? existingIade?.linkedExitId
            ?? trReturnHandoverPrefill?.linkedExitId.flatMap { UUID(uuidString: $0) }
    }

    /// RES alanı için rakamlar (önce Front Desk `navDigits`, yoksa çıkış kaydından).
    private var quickDamageReturnNavDigits: String? {
        if let pre = trReturnHandoverPrefill,
           let linked = pre.linkedExitId,
           let u = UUID(uuidString: linked),
           u == quickDamageLinkedExitId {
            let d = pre.navDigits.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { return d }
        }
        guard let lid = quickDamageLinkedExitId,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return nil }
        var code = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        while code.uppercased().hasPrefix("NAV-") || code.uppercased().hasPrefix("RES-") || code.uppercased().hasPrefix("RNT-") {
            code = String(code.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let digits = code.filter { $0.isNumber }
        return digits.isEmpty ? nil : digits
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
            .navigationTitle("Return Process".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .modifier(ConditionalWheelSysCHChrome(enabled: usesCHPalantirReturnChrome))
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
                    operationFlowState = .processing
                    HapticManager.shared.success()
                    completionPhase = .processingReturn
                    pulseAnimation = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = true
                    }
                    kaydet(status: .completed)
                }
            } message: {
                Text("Are you sure you have completed all the necessary operations? Click 'Complete' to finalize this return operation.".localized)
            }
        )

        let withFormChanges = alertConfigured
            .onChange(of: pickUpBranch) { _, _ in hasUnsavedChanges = true }
            .onChange(of: dropOffBranch) { _, _ in hasUnsavedChanges = true }
            .onChange(of: iadeTarihi) { _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _ in hasUnsavedChanges = true }
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
                            storagePath: iadeDraftPhotoStoragePath(),
                            fingerprintKey: key,
                            trackForSessionDiscard: true
                        )
                    }
                }
            }
            .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { _ in hasUnsavedChanges = true }
            .onChange(of: checklist) { _, newValue in
                hasUnsavedChanges = true
                if newValue.customerPresent {
                    autofillCustomerFromLinkedExitKeepingNamesEmpty()
                }
            }
            .onChange(of: customerNationalId) { _, _ in hasUnsavedChanges = true }
            .onChange(of: customerFirstName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerLastName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerEmail) { _, newVal in
                hasUnsavedChanges = true
                scheduleRememberAutofill(for: newVal)
            }
            .onChange(of: customerSignatureImage) { _ in hasUnsavedChanges = true }
            .onChange(of: showAdditionalDriverFields) { _, isOn in
                if !isOn {
                    testDriverFirstName = ""
                    testDriverLastName = ""
                }
            }
            .onChange(of: vehicleItemsChecklist) { _, _ in hasUnsavedChanges = true }
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

        let withWheelSysSync = withFormChanges
            .onAppear(perform: handleAppear)
            .task(priority: .utility) { await loadWheelSysPreviewIfNeeded() }
            .onReceive(NotificationCenter.default.publisher(for: .wheelSysReturnPreviewUpdated)) { _ in
                applyWheelSysCustomerFromResolvedSources()
                applyWheelSysMileageFromResolvedSources()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wheelSysSessionRestored)) { _ in
                wheelsysPreviewLoaded = false
                Task(priority: .utility) { await loadWheelSysPreviewIfNeeded() }
            }
            .onChange(of: wheelSysReturnPrefill) { _, newPrefill in
                guard wheelSysCHOpsEnabled, let pre = newPrefill else { return }
                wheelsysPreviewLoaded = false
                wheelsysPreviewEntityKey = ""
                wheelsysPrecheckinContext = nil
                wheelsysCheckin.reset()
                applyWheelSysReturnPrefill(pre)
                wheelsysCheckin.prepareFromPrefill(pre, arac: arac)
                Task(priority: .utility) {
                    await loadWheelSysPreviewIfNeeded()
                    await loadWheelSysPrecheckinContextIfNeeded()
                }
            }
            .onChange(of: wheelsysPrecheckinContext?.rental.rentalId) { _, _ in
                applyWheelSysCustomerFromResolvedSources()
                applyWheelSysMileageFromResolvedSources()
            }

        let withChanges = withWheelSysSync
            .onChange(of: turkeyBranchRegistryIdentity) { _, _ in
                guard existingIade == nil, isTurkeyFranchise else { return }
                applyTurkeyDefaultBranchesForNewReturn()
            }
            .onChange(of: showTurkeyTermsWizard) { _, visible in
                if !visible { turkeyWizardPrefilledTermsPdfData = nil }
            }
            .onChange(of: trRentalTermsSignatureURL) { _, _ in refreshTurkeyTermsInlinePreview() }
            .onChange(of: customerSignatureImage) { _, _ in refreshTurkeyVehicleInlinePreview() }
            .onChange(of: fotograflar) { _, _ in refreshTurkeyVehicleInlinePreview() }
            .onChange(of: cameraPhotos) { _, _ in refreshTurkeyVehicleInlinePreview() }

        return AnyView(
            withChanges
            .onDisappear {
                rememberLookupTask?.cancel()
                rememberLookupTask = nil
                formListener?.remove()
                formListener = nil
            }
            .sheet(isPresented: $showQRSheet) {
                ReturnQRSheet(token: activeToken)
            }
            .sheet(isPresented: $showVehicleItemsSheet) {
                ReturnVehicleItemsChecklistSheet(selections: $vehicleItemsChecklist)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureCaptureView(signatureImage: $customerSignatureImage)
            }
            .sheet(isPresented: $showWheelSysNotesSidebar) {
                WheelSysPalantirNotesSidebar(
                    rentalNotes: wheelsysCheckin.preview?.rentalNotes ?? [],
                    vehicleNotes: wheelsysCheckin.preview?.vehicleNotes ?? [],
                    newNoteText: $wheelsysNewNoteText,
                    isSaving: wheelsysNoteSaving,
                    isDeleting: wheelsysNoteDeleting,
                    statusMessage: wheelsysNoteStatus,
                    statusIsError: wheelsysNoteStatusIsError,
                    canAddNote: wheelsysCheckin.entityId != nil,
                    onSave: { Task { await saveWheelSysRentalNote() } },
                    onDelete: { note in Task { await deleteWheelSysNote(note) } }
                )
            }
            .sheet(isPresented: $showWheelSysDamageHistory) {
                WheelSysVehicleDamageHistoryView(
                    arac: arac,
                    rentalId: wheelSysEffectiveEntityId.flatMap { Int($0) }
                )
            }
            .fullScreenCover(isPresented: $showTurkeyTermsWizard) {
                TurkeyReturnComplianceWizardView(
                    isPresented: $showTurkeyTermsWizard,
                    draftIade: draftIadeForTurkeyPdf(),
                    arac: arac,
                    vehiclePhotos: allPhotos,
                    damagePhotos: turkeyWizardDamagePhotos,
                    franchiseDisplayName: turkeyCommercialTitle,
                    includeGeneralRentalTerms: true,
                    termsOnlyMode: true,
                    commercialTitle: turkeyCommercialTitle,
                    branchDisplayName: turkeyBranchDisplayName,
                    customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines),
                    staffSignerNameFallback: authManager.userProfile?.fullName,
                    existingSignedTermsPdfData: turkeyWizardPrefilledTermsPdfData,
                    initialTermsPreferredEnglish: trRentalTermsLanguage.map { $0.lowercased() == "en" },
                    onTermsAccepted: { lang, signedDoc in
                        uploadTrRentalTermsSignature(signedDocumentData: signedDoc, languageCode: lang)
                    },
                    onFinished: { _ in }
                )
            }
            .fullScreenCover(isPresented: $showTurkeyVehicleWizard) {
                TurkeyReturnComplianceWizardView(
                    isPresented: $showTurkeyVehicleWizard,
                    draftIade: draftIadeForTurkeyPdf(),
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
                    returnFlowCheckoutId: quickDamageLinkedExitId,
                    returnFlowNavDigits: quickDamageReturnNavDigits,
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
        )
    }
    
    private var mainForm: some View {
        Group {
            if usesCHPalantirReturnChrome {
                wheelSysPalantirReturnForm
            } else {
                legacyMainForm
            }
        }
    }

    private var legacyMainForm: some View {
        ScrollViewReader { proxy in
            Form {
                if isTurkeyFranchise {
                    turkeyDealerInfoSection
                }
                returnIdentitySection
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
                if wheelSysReturnPrefill != nil {
                    wheelSysReturnSection
                    wheelSysInsuranceSection
                    wheelSysNotesSection
                }
                iadeBilgileriSection
                if wheelSysReturnPrefill != nil {
                    wheelSysPrecheckinLegacySection
                }
                checklistSection
                signatureAndContactSection
                fotografSection
                if isTurkeyFranchise {
                    turkeyReturnVehicleSignSection
                }
                completeSection
            }
            .scrollDismissesKeyboard(.immediately)
            .listStyle(.insetGrouped)
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

    private var wheelSysPalantirReturnForm: some View {
        ScrollViewReader { proxy in
            WheelSysPalantirFormScroll {
                wheelSysPalantirReturnIdentityCard
                    .id("formTop")
                if wheelSysReturnPrefill != nil {
                    WheelSysPalantirSectionCard(
                        title: "wheelsys.return.section_title".localized,
                        icon: "point.3.connected.trianglepath.dotted"
                    ) {
                        wheelSysReturnCardContent
                    }
                    WheelSysPalantirSectionCard(
                        title: "wheelsys.return.notes_header".localized,
                        icon: "note.text"
                    ) {
                        wheelSysNotesSidebarEntry
                    }
                }
                WheelSysPalantirSectionCard(
                    title: "Return Information".localized,
                    icon: "arrow.uturn.down.circle",
                    footer: "Complete vehicle check-in (km and fuel) before return photos.".localized
                ) {
                    wheelSysPalantirReturnInfoFields
                }
                if wheelSysReturnPrefill != nil, wheelsysCheckin.preview?.insurance != nil {
                    WheelSysPalantirSectionCard(
                        title: "wheelsys.return.insurance_header".localized,
                        icon: "shield.lefthalf.filled"
                    ) {
                        wheelSysInsuranceCardContent
                    }
                }
                WheelSysPalantirSectionCard(
                    title: "wheelsys.damage_history.existing_title".localized,
                    icon: "exclamationmark.triangle.fill"
                ) {
                    WheelSysPalantirSecondaryButton(
                        title: "Open Damage Records".localized,
                        icon: "arrow.up.right.square"
                    ) {
                        HapticManager.shared.light()
                        showWheelSysDamageHistory = true
                    }
                }
                if wheelSysReturnPrefill != nil {
                    WheelSysPalantirSectionCard(
                        title: "wheelsys.precheckin.title".localized,
                        icon: "checkmark.seal.fill",
                        footer: "wheelsys.precheckin.complete_footer".localized
                    ) {
                        wheelSysPrecheckinInlineContent
                    }
                }
                WheelSysPalantirSectionCard(
                    title: "Customer Information & Signature".localized,
                    icon: "person.text.rectangle",
                    footer: "Name, email and signature are used in Return PDF and email delivery.".localized
                ) {
                    wheelSysPalantirReturnCustomerBlock
                }
                if !wheelSysCHOpsEnabled {
                    WheelSysPalantirSectionCard(title: "Return Checklist".localized, icon: "checklist") {
                        wheelSysPalantirChecklistFields
                    }
                }
                WheelSysPalantirSectionCard(title: "Photos".localized, icon: "camera.fill") {
                    returnPhotoGalleryContent
                    returnPhotoActionsContent
                }
                WheelSysPalantirSectionCard(
                    title: "Finalize return".localized,
                    icon: "checkmark.seal.fill",
                    footer: "Mark this return as completed and close the form.".localized
                ) {
                    wheelSysPalantirCompleteReturnButton
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(hasUnsavedChanges || isUploading)
            .task(id: wheelSysEffectiveEntityId) {
                wheelsysPrecheckinContext = nil
                await loadWheelSysPrecheckinContextIfNeeded()
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
    private var wheelSysPalantirReturnIdentityCard: some View {
        WheelSysPalantirSectionCard(title: "RETURN".localized, icon: "arrow.uturn.down.circle.fill") {
            if isSaved, let savedIade = committedIade ?? existingIade {
                OperationIdentityLinkRow(
                    plate: arac.plakaFormatli,
                    reservationCode: savedIade.navKodu ?? linkedExitReservationCode,
                    reservationLabel: "RES Code".localized,
                    vehicle: arac,
                    iade: savedIade,
                    plateInteractive: true,
                    codeInteractive: true
                )
            } else {
                HStack(spacing: 8) {
                    Text(ProcessPhotoStampLabels.formatDisplayDate(iadeTarihi, includeTime: isGermanyFranchise))
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                    Spacer(minLength: 0)
                    PalantirOpsBadge(text: arac.plakaFormatli, tone: .accent)
                }
                OperationIdentityLinkRow(
                    plate: arac.plakaFormatli,
                    reservationCode: linkedExitReservationCode,
                    reservationLabel: "RES Code".localized,
                    vehicle: arac,
                    plateInteractive: false,
                    codeInteractive: false
                )
            }
        }
    }

    @ViewBuilder
    private var wheelSysPalantirReturnInfoFields: some View {
        WheelSysPalantirDateInput(
            label: "Return Date".localized,
            date: $iadeTarihi,
            components: processDatePickerComponents
        )
        WheelSysPalantirTextInput(label: "KM (optional)".localized, text: $kmText, keyboard: .numberPad)
        if let deltaLine = wheelSysKmDeltaLine {
            WheelSysPalantirStatusStrip(
                icon: wheelSysKmDeltaIsValid ? "road.lanes" : "exclamationmark.triangle",
                message: deltaLine,
                tint: wheelSysKmDeltaIsValid ? PalantirTheme.accent : PalantirTheme.warning
            )
        }
        WheelSysPalantirFuelSlider(
            label: "Fuel level".localized,
            eighths: Binding(
                get: { fuelEighthsValue },
                set: { yakitSeviyesi = "\($0)/8" }
            ),
            tint: fuelTextColor
        )
    }

    @ViewBuilder
    private var wheelSysPalantirChecklistFields: some View {
        WheelSysPalantirToggleRow(label: "Customer was present".localized, isOn: $checklist.customerPresent, tint: PalantirTheme.purple)
        WheelSysPalantirToggleRow(label: "Customer had no time".localized, isOn: $checklist.customerNoTime, tint: PalantirTheme.textMuted)
        WheelSysPalantirToggleRow(label: "Key was taken from keybox".localized, isOn: $checklist.keyFromKeybox, tint: PalantirTheme.purple)
        WheelSysPalantirToggleRow(label: "Customer refused to sign".localized, isOn: $checklist.customerRefusedSignature, tint: PalantirTheme.warning)
        WheelSysPalantirToggleRow(label: "Customer left key at office".localized, isOn: $checklist.customerLeftKeyAtOffice, tint: PalantirTheme.textMuted)
    }

    @ViewBuilder
    private var wheelSysPalantirReturnCustomerBlock: some View {
        WheelSysPalantirTextInput(
            label: "Customer Name".localized,
            text: wheelSysCustomerNameBinding,
            disabled: isCustomerInfoReadOnlyFromOperation
        )
        WheelSysPalantirTextInput(
            label: "Email".localized,
            text: $customerEmail,
            keyboard: .emailAddress,
            disabled: isCustomerInfoReadOnlyFromOperation
        )
        WheelSysPalantirSecondaryButton(
            title: customerSignatureImage == nil ? "Add Signature".localized : "Update Signature".localized,
            icon: "signature"
        ) {
            showSignatureSheet = true
        }
        if customerSignatureImage != nil {
            CustomerSignatureFormBlock(
                image: customerSignatureImage!,
                onUpdate: { showSignatureSheet = true },
                onRemove: isCustomerInfoReadOnlyFromOperation ? nil : {
                    customerSignatureImage = nil
                    signatureWasRemoved = true
                }
            )
        }
    }

    private var wheelSysPalantirCompleteReturnButton: some View {
        WheelSysPalantirPrimaryButton(
            title: isUploading ? "Uploading Photos...".localized : "Complete Return".localized,
            isLoading: isUploading,
            disabled: isUploading
        ) {
            dismissKeyboard()
            HapticManager.shared.medium()
            showCompleteConfirmation = true
        }
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

    private var turkeyGeneralTermsSignSection: some View {
        turkeyComplianceActionSection(
            done: turkeyTermsGateComplete,
            doneMessageKey: "tr_compliance.terms_signed_status",
            requiredMessageKey: "tr_return.compliance_required",
            previewData: turkeyInlineTermsPdf,
            buttonTitleKey: "tr_return.general_rental_terms_button",
            usePrimaryWhenDone: true,
            action: { openTurkeyTermsWizard() }
        )
    }

    private var turkeyReturnVehicleSignSection: some View {
        turkeyComplianceActionSection(
            done: customerSignatureImage != nil,
            doneMessageKey: "tr_return.vehicle_pdf_signed_status",
            requiredMessageKey: "tr_return.vehicle_pdf_required",
            previewData: turkeyInlineVehiclePdf,
            buttonTitleKey: "tr_return.sign_vehicle_pdf",
            usePrimaryWhenDone: true,
            action: { openTurkeyVehicleWizard() }
        )
    }

    private func turkeyComplianceActionSection(
        done: Bool,
        doneMessageKey: String,
        requiredMessageKey: String,
        previewData: Data?,
        buttonTitleKey: String,
        usePrimaryWhenDone: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Section {
            if done {
                Text(doneMessageKey.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let previewData {
                    TurkeyReadOnlyPdfRepresentable(pdfData: previewData)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text("tr_compliance.redo_terms_prompt".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer(minLength: AppTheme.turkeyFormPrimaryButtonHorizontalInset)
                Group {
                    if done && usePrimaryWhenDone {
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
    }

    private var returnIdentitySection: some View {
        Section {
            if isSaved, let savedIade = committedIade ?? existingIade {
                OperationIdentityLinkRow(
                    plate: arac.plakaFormatli,
                    reservationCode: savedIade.navKodu ?? linkedExitReservationCode,
                    reservationLabel: isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
                    vehicle: arac,
                    iade: savedIade,
                    plateInteractive: true,
                    codeInteractive: true
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                        Text("RETURN".localized)
                            .font(.system(size: 22, weight: .bold))
                            .tracking(0.8)
                        Spacer()
                        Text(ProcessPhotoStampLabels.formatDisplayDate(iadeTarihi, includeTime: isGermanyFranchise))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    OperationIdentityLinkRow(
                        plate: arac.plakaFormatli,
                        reservationCode: linkedExitReservationCode,
                        reservationLabel: isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
                        vehicle: arac,
                        plateInteractive: false,
                        codeInteractive: false
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var linkedExitReservationCode: String? {
        guard let lid = quickDamageLinkedExitId ?? linkedExitIdForReturn,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return nil }
        let raw = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private var linkedExitIdForReturn: UUID? {
        committedIade?.linkedExitId ?? existingIade?.linkedExitId
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
                TurkeyDocumentationToolbarButton(topic: .returnProcess)
            }
        }
        if usesCHPalantirReturnChrome, wheelSysReturnPrefill != nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showWheelSysNotesSidebar = true
                } label: {
                    Image(systemName: "note.text")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("wheelsys.return.notes_header".localized)
            }
        }
        // QR button only shown while the return is not yet completed
        if !isSaved {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showQRSheet = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
        }
        
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body)
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func handleAppear() {
        if wheelSysCHOpsEnabled {
            WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        }
        if isTurkeyFranchise {
            viewModel.reloadFranchiseGarageMetadataFromFirestore()
        }
        if let existing = existingIade {
            iadeTarihi = existing.iadeTarihi
            notlar = existing.notlar
            checklist = existing.checklist ?? ReturnChecklist()
            customerFirstName = existing.customerFirstName ?? ""
            customerLastName = existing.customerLastName ?? ""
            customerEmail = existing.customerEmail ?? ""
            customerNationalId = existing.customerNationalId ?? ""
            testDriverFirstName = existing.testDriverFirstName ?? ""
            testDriverLastName = existing.testDriverLastName ?? ""
            showAdditionalDriverFields = !(existing.testDriverFirstName ?? "").isEmpty
                || !(existing.testDriverLastName ?? "").isEmpty
            kmText = existing.km.map(String.init) ?? ""
            yakitSeviyesi = normalizedFuelLevel(existing.yakitSeviyesi)
            pickUpBranch = canonicalTurkeyBranchKey(from: existing.pickUpBranch)
            dropOffBranch = canonicalTurkeyBranchKey(from: existing.dropOffBranch)
            vehicleItemsChecklist = existing.vehicleItemsChecklist ?? VehicleChecklistCatalog.defaultMap()
            existingPhotoURLs = existing.fotograflar
            trRentalTermsAcceptedAt = existing.trRentalTermsAcceptedAt
            trRentalTermsLanguage = existing.trRentalTermsLanguage
            trRentalTermsSignatureURL = existing.trRentalTermsSignatureURL
            loadExistingSignatureImage()
            refreshTurkeyTermsInlinePreview()
            refreshTurkeyVehicleInlinePreview()
        } else if let pre = trReturnHandoverPrefill {
            customerFirstName = pre.customerFirstName
            customerLastName = pre.customerLastName
            customerEmail = pre.customerEmail
            if let pi = pre.plannedCheckin {
                iadeTarihi = pi
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
            vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
            hasUnsavedChanges = true
        } else if let ws = wheelSysReturnPrefill {
            applyWheelSysReturnPrefill(ws)
            wheelsysCheckin.prepareFromPrefill(ws, arac: arac)
        } else {
            vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
        }
        if existingIade == nil, isTurkeyFranchise {
            applyTurkeyDefaultBranchesForNewReturn()
        }
        // Start QR listener immediately — works even before first save
        startFormListener(token: activeToken)
        supplementCustomerFieldsFromLinkedExitIfNeeded()
    }

    private func applyWheelSysReturnPrefill(_ pre: WheelSysReturnOperationPrefill) {
        applyWheelSysCustomerFromResolvedSources(prefill: pre)
        // Default to Zurich now — never pre-fill from planned reservation return date.
        iadeTarihi = WheelSysZurichDateTime.now()
        wheelSysNavKodu = pre.resNo
        if kmText.isEmpty {
            if let km = WheelSysReturnMileageFuel.effectiveCheckinMileage(pre.checkinMileageHint) {
                kmText = String(km)
            } else if let checkout = pre.checkoutMileage, checkout > 0 {
                kmText = String(checkout)
            } else if let fleetKm = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)?.mileage
                ?? WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka)?.mileage,
                      fleetKm > 0 {
                kmText = String(fleetKm)
            }
        }
        let defaultFuel = WheelSysReturnMileageFuel.defaultReturnFuel(
            checkin: pre.checkinFuelHint,
            checkout: pre.checkoutFuel
        )
        yakitSeviyesi = "\(defaultFuel)/8"
        vehicleItemsChecklist = VehicleChecklistCatalog.defaultMap()
        hasUnsavedChanges = true
    }

    /// Fills customer name/email from WheelSys preview, pre-check-in context, or prefill.
    /// WheelSys sources always win over stale local exit / QR autofill.
    private func applyWheelSysCustomerFromResolvedSources(prefill: WheelSysReturnOperationPrefill? = nil) {
        guard wheelSysCHOpsEnabled else { return }

        if let authoritative = authoritativeWheelSysCustomerFields(prefill: prefill) {
            customerFirstName = authoritative.name
            customerLastName = ""
            if !authoritative.email.isEmpty {
                customerEmail = authoritative.email
            }
            return
        }

        let pre = prefill ?? wheelSysReturnPrefill
        let name = pre.map { resolvedWheelSysDriverName(prefill: $0) } ?? ""
        let email = pre.map { resolvedWheelSysCustomerEmail(prefill: $0) } ?? ""
        if customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.isEmpty {
            customerFirstName = name
            customerLastName = ""
        }
        if customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !email.isEmpty {
            customerEmail = email
        }
    }

    private func authoritativeWheelSysCustomerFields(
        prefill: WheelSysReturnOperationPrefill? = nil
    ) -> (name: String, email: String)? {
        if let ctx = wheelsysPrecheckinContext {
            let fromContext = resolvedWheelSysCustomerName(
                fullName: ctx.customer.fullName,
                firstName: ctx.customer.firstName,
                lastName: ctx.customer.lastName
            )
            if !fromContext.isEmpty {
                let email = ctx.customer.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (fromContext, email)
            }
        }
        if let preview = wheelsysCheckin.preview {
            let fromPreview = resolvedWheelSysCustomerName(
                fullName: preview.customerName,
                firstName: preview.customerFirstName,
                lastName: preview.customerLastName
            )
            if !fromPreview.isEmpty {
                let email = preview.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                return (fromPreview, email)
            }
        }
        let pre = prefill ?? wheelSysReturnPrefill
        if let pre {
            let fromPrefill = pre.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fromPrefill.isEmpty,
               pre.entryPoint == .journalReturn || pre.entryPoint == .plateScanReturn {
                let email = pre.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (fromPrefill, email)
            }
        }
        return nil
    }

    private func resolvedWheelSysCustomerName(
        fullName: String,
        firstName: String?,
        lastName: String?
    ) -> String {
        let combined = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        return [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Sync km/fuel from live pre-check-in context when preview callable is degraded.
    private func applyWheelSysOperationalFieldsFromPrecheckinContext() {
        applyWheelSysMileageFromResolvedSources()
        guard wheelSysCHOpsEnabled, let ctx = wheelsysPrecheckinContext else { return }
        let fuel = WheelSysReturnMileageFuel.effectiveCheckinFuel(
            ctx.mileageFuel.currentReturnFuel,
            checkout: ctx.mileageFuel.checkoutFuel
        )
        if let fuel {
            let trimmed = yakitSeviyesi.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("0/") {
                yakitSeviyesi = "\(fuel)/8"
            }
        }
    }

    /// Prefill return km when the field is still empty — uses check-in hint, checkout km, preview, or fleet master.
    private func applyWheelSysMileageFromResolvedSources() {
        guard wheelSysCHOpsEnabled else { return }
        let trimmedKm = kmText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentKm = Int(trimmedKm) ?? 0
        guard currentKm <= 0 else { return }

        let checkinCandidates: [Int?] = [
            wheelsysPrecheckinContext.map {
                WheelSysReturnMileageFuel.effectiveCheckinMileage($0.mileageFuel.currentReturnMileage)
            } ?? nil,
            wheelSysReturnPrefill.flatMap {
                WheelSysReturnMileageFuel.effectiveCheckinMileage($0.checkinMileageHint)
            },
            wheelsysCheckin.preview.flatMap {
                WheelSysReturnMileageFuel.effectiveCheckinMileage($0.mileageTo > 0 ? $0.mileageTo : nil)
            },
        ]
        if let km = checkinCandidates.compactMap({ $0 }).first {
            kmText = String(km)
            return
        }
        if let checkout = wheelSysCheckoutKm {
            kmText = String(checkout)
            return
        }
        if let master = wheelsysCheckin.preview?.vehicleMasterMileage, master > 0 {
            kmText = String(master)
            return
        }
        if let fleetKm = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)?.mileage
            ?? WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka)?.mileage,
           fleetKm > 0 {
            kmText = String(fleetKm)
        }
    }

    /// Planned return rows may lack national ID until checkout fields are copied from the linked exit.
    private func supplementCustomerFieldsFromLinkedExitIfNeeded() {
        guard isTurkeyFranchise else { return }
        let exitId = (existingIade?.linkedExitId ?? committedIade?.linkedExitId)
            ?? trReturnHandoverPrefill?.linkedExitId.flatMap { UUID(uuidString: $0) }
        guard let exitId else { return }
        let needsFirst = customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsLast = customerLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsEmail = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsFirst || needsLast || needsEmail else { return }

        if let cached = viewModel.exitIslemleri.first(where: { $0.id == exitId }) {
            applyLinkedExitCustomerFields(cached)
            return
        }
        FirebaseService.shared.fetchExitIslemi(id: exitId) { exit, _ in
            DispatchQueue.main.async {
                guard let exit else { return }
                applyLinkedExitCustomerFields(exit)
            }
        }
    }

    private func applyLinkedExitCustomerFields(_ exit: ExitIslemi) {
        if customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = exit.customerFirstName, !v.isEmpty {
            customerFirstName = v
        }
        if customerLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = exit.customerLastName, !v.isEmpty {
            customerLastName = v
        }
        if customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = exit.customerEmail, !v.isEmpty {
            customerEmail = v
        }
    }

    /// Türkiye: yeni iadede drop-off boşsa işlemi yapan şube; pick-up boşsa son çıkış kaydındaki teslim şubesi (yoksa aynı şube).
    private func applyTurkeyDefaultBranchesForNewReturn() {
        let raw = TurkiyeGarajSubeleri.matchingBranchStorageKey(among: turkeyBranches)
        if !raw.isEmpty {
            let op = canonicalTurkeyBranchKey(from: raw)
            if !op.isEmpty, dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dropOffBranch = op
            }
        }
        if pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let ex = latestOutboundExitForPickupPrefill() {
                let pu = canonicalTurkeyBranchKey(from: ex.pickUpBranch ?? ex.bayiAdi)
                if !pu.isEmpty { pickUpBranch = pu }
            }
            if pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !raw.isEmpty {
                let op = canonicalTurkeyBranchKey(from: raw)
                if !op.isEmpty { pickUpBranch = op }
            }
        }
    }

    private func latestOutboundExitForPickupPrefill() -> ExitIslemi? {
        viewModel.exitIslemleri
            .filter { $0.aracId == arac.id && !$0.isDeleted }
            .filter { $0.status == .completed || $0.status == .parked }
            .max(by: { $0.exitTarihi < $1.exitTarihi })
    }

    private var turkeyBranchRegistryIdentity: String {
        viewModel.turkeyFranchiseLocationBranches
            .map { $0.storageKey.uppercased() }
            .sorted()
            .joined(separator: ",")
    }
    
    private func iadeDraftPhotoStoragePath(fileName: String = "\(UUID().uuidString).jpg") -> String {
        "franchises/\(FirebaseService.shared.currentFranchiseId)/iade_fotograflari/drafts/\(localQRToken)/\(fileName)"
    }

    private func openReturnCamera() {
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
                storagePath: iadeDraftPhotoStoragePath(),
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
        let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/iade_fotograflari/\(UUID().uuidString).jpg"
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
    
    // MARK: WheelSys return check-in (CH)

    private var returnResNo: String {
        let ws = wheelSysNavKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ws.isEmpty { return ws }
        if let n = committedIade?.navKodu, !n.isEmpty { return n }
        if let n = existingIade?.navKodu, !n.isEmpty { return n }
        if let pre = trReturnHandoverPrefill {
            let digits = pre.navDigits.trimmingCharacters(in: .whitespacesAndNewlines)
            if !digits.isEmpty { return digits }
        }
        return linkedExitReservationCode ?? ""
    }

    @ViewBuilder
    private var wheelSysReturnCardContent: some View {
        switch wheelsysCheckin.phase {
        case .idle, .loadingPreview:
            if wheelSysReturnPrefill != nil || wheelsysCheckin.preview != nil {
                wheelSysPalantirReadOnlyPanel
            }
            if case .loadingPreview = wheelsysCheckin.phase {
                WheelSysPalantirStatusStrip(
                    icon: "arrow.triangle.2.circlepath",
                    message: "wheelsys.return.loading_preview".localized,
                    tint: PalantirTheme.accent,
                    showsSpinner: true
                )
            }
        case .noEntity:
            if wheelSysReturnPrefill != nil || wheelsysCheckin.preview != nil {
                wheelSysPalantirReadOnlyPanel
            }
            if !wheelSysHasResolvedWheelSysRental {
                WheelSysPalantirStatusStrip(
                    icon: "questionmark.circle",
                    message: "wheelsys.return.no_entity".localized,
                    tint: .orange
                )
            }
        case .ready:
            wheelSysPalantirReadOnlyPanel
        case .failed(let msg):
            wheelSysPalantirReadOnlyPanel
            WheelSysPalantirStatusStrip(icon: "exclamationmark.triangle", message: msg, tint: .orange)
            WheelSysPalantirSecondaryButton(title: "wheelsys_fleet.reload".localized, icon: "arrow.clockwise") {
                wheelsysPreviewLoaded = false
                wheelsysCheckin.reset()
                Task { await loadWheelSysPreviewIfNeeded() }
            }
        }
    }

    private var wheelSysReturnSection: some View {
        Section {
            wheelSysReturnCardContent
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            Label("wheelsys.return.section_title".localized, systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func wheelSysPalantirStatusBanner(
        icon: String,
        text: String,
        tint: Color,
        showsSpinner: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    @ViewBuilder
    private var wheelSysPalantirReadOnlyPanel: some View {
        let pre = wheelSysReturnPrefill
        let preview = wheelsysCheckin.preview
        VStack(alignment: .leading, spacing: 8) {
            if pre != nil || preview != nil {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    if let res = pre?.resNo, !res.isEmpty {
                        palantirWheelSysTile(icon: "number", title: "wheelsys.return.res".localized, value: res)
                    } else if let preview, !preview.resNo.isEmpty {
                        palantirWheelSysTile(icon: "number", title: "wheelsys.return.res".localized, value: preview.resNo)
                    }
                    if let from = pre?.dateFrom {
                        palantirWheelSysTile(
                            icon: "arrow.up.right.circle",
                            title: "wheelsys.return.checkout_date".localized,
                            value: formatWheelSysDate(from)
                        )
                    } else if let preview, !preview.dateFrom.isEmpty || !preview.timeFrom.isEmpty {
                        palantirWheelSysTile(
                            icon: "arrow.up.right.circle",
                            title: "wheelsys.return.checkout_date".localized,
                            value: "\(preview.dateFrom) \(preview.timeFrom)".trimmingCharacters(in: .whitespaces)
                        )
                    }
                    if let to = pre?.dateTo {
                        palantirWheelSysTile(
                            icon: "arrow.down.left.circle",
                            title: "wheelsys.return.checkin_date".localized,
                            value: formatWheelSysDate(to)
                        )
                    } else if let preview, !preview.dateTo.isEmpty || !preview.timeTo.isEmpty {
                        palantirWheelSysTile(
                            icon: "arrow.down.left.circle",
                            title: "wheelsys.return.checkin_date".localized,
                            value: "\(preview.dateTo) \(preview.timeTo)".trimmingCharacters(in: .whitespaces)
                        )
                    }
                }
            }
            if let preview {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    palantirWheelSysTile(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "wheelsys.return.checkout_km".localized,
                        value: preview.checkoutMileageText.isEmpty
                            ? (preview.mileageFrom > 0 ? "\(preview.mileageFrom)" : "—")
                            : preview.checkoutMileageText
                    )
                    palantirWheelSysTile(
                        icon: "fuelpump.fill",
                        title: "wheelsys.return.checkout_fuel".localized,
                        value: preview.fuelFrom > 0 ? "\(preview.fuelFrom)/8" : "—",
                        tint: .orange
                    )
                    palantirWheelSysTile(
                        icon: "speedometer",
                        title: "wheelsys.return.checkin_km".localized,
                        value: preview.checkinMileageText.isEmpty
                            ? (preview.mileageTo > 0 ? "\(preview.mileageTo)" : "—")
                            : preview.checkinMileageText
                    )
                    if let driven = wheelSysComputedMilesDriven(fromCheckout: preview.mileageFrom, returnKm: wheelSysCheckInKm) {
                        palantirWheelSysTile(
                            icon: "road.lanes",
                            title: "wheelsys.return.km_driven".localized,
                            value: "+\(driven) km",
                            tint: PalantirTheme.accent
                        )
                    }
                    palantirWheelSysTile(
                        icon: "drop.fill",
                        title: "wheelsys.return.checkin_fuel".localized,
                        value: preview.fuelTo > 0 ? "\(preview.fuelTo)/8" : "—",
                        tint: PalantirTheme.success
                    )
                    if let masterKm = preview.vehicleMasterMileage {
                        palantirWheelSysTile(
                            icon: "car.fill",
                            title: "wheelsys.return.master_km".localized,
                            value: "\(masterKm)"
                        )
                    }
                    if let masterFuel = preview.vehicleMasterFuel {
                        palantirWheelSysTile(
                            icon: "fuelpump.fill",
                            title: "wheelsys.return.master_fuel".localized,
                            value: "\(masterFuel)/8"
                        )
                    }
                    palantirWheelSysTile(
                        icon: "link",
                        title: "wheelsys.return.entity_id".localized,
                        value: wheelsysCheckin.entityId ?? preview.entityId
                    )
                    if !preview.vehicleEntityId.isEmpty {
                        palantirWheelSysTile(
                            icon: "car.side.fill",
                            title: "wheelsys.return.vehicle_entity_id".localized,
                            value: preview.vehicleEntityId
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PalantirTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PalantirTheme.border, lineWidth: 1)
                )
        )
    }

    private func palantirWheelSysTile(
        icon: String,
        title: String,
        value: String,
        tint: Color = PalantirTheme.accent
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(value)
                .font(PalantirTheme.dataFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PalantirTheme.background.opacity(0.55))
        )
    }

    @ViewBuilder
    private var wheelSysReadOnlyContent: some View {
        wheelSysPalantirReadOnlyPanel
    }

    private func resolvedWheelSysDriverName(prefill: WheelSysReturnOperationPrefill) -> String {
        if let preview = wheelsysCheckin.preview {
            let fromPreview = resolvedWheelSysCustomerName(
                fullName: preview.customerName,
                firstName: preview.customerFirstName,
                lastName: preview.customerLastName
            )
            if !fromPreview.isEmpty { return fromPreview }
        }
        return prefill.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedWheelSysCustomerEmail(prefill: WheelSysReturnOperationPrefill) -> String {
        if let preview = wheelsysCheckin.preview {
            let email = preview.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { return email }
        }
        return prefill.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @ViewBuilder
    private var wheelSysPrecheckinInlineContent: some View {
        if wheelSysEffectiveEntityId == nil, case .loadingPreview = wheelsysCheckin.phase {
            WheelSysPalantirStatusStrip(
                icon: "arrow.triangle.2.circlepath",
                message: "wheelsys.return.loading_preview".localized,
                showsSpinner: true
            )
        }
        if wheelsysPrecheckinSucceeded {
            WheelSysPalantirStatusStrip(
                icon: "checkmark.circle",
                message: "wheelsys.precheckin.submit_success".localized,
                tint: PalantirTheme.success
            )
        } else if wheelsysPrecheckinBusy {
            WheelSysPalantirStatusStrip(
                icon: "arrow.triangle.2.circlepath",
                message: "wheelsys.precheckin.title".localized,
                showsSpinner: true
            )
        }
        if wheelSysCheckInKm == nil {
            WheelSysPalantirStatusStrip(
                icon: "info.circle",
                message: "wheelsys.precheckin.km_required".localized,
                tint: PalantirTheme.textMuted
            )
        } else if !wheelSysReturnKmValidForSubmit {
            WheelSysPalantirStatusStrip(
                icon: "exclamationmark.triangle",
                message: wheelSysReturnKmValidationMessage,
                tint: PalantirTheme.warning
            )
        } else if let ineligible = wheelsysPrecheckinContext?.statusIneligibleMessage {
            WheelSysPalantirStatusStrip(
                icon: "exclamationmark.triangle",
                message: ineligible,
                tint: PalantirTheme.critical
            )
        } else if let preview = wheelSysPrecheckinKmFuelPreview {
            WheelSysPalantirStatusStrip(
                icon: "arrow.triangle.2.circlepath",
                message: preview,
                tint: PalantirTheme.purple
            )
        }
        if let status = wheelsysPrecheckinStatus {
            WheelSysPalantirStatusStrip(
                icon: wheelsysPrecheckinIsError ? "exclamationmark.triangle" : "checkmark.circle",
                message: status,
                tint: wheelsysPrecheckinIsError ? PalantirTheme.critical : PalantirTheme.success
            )
        }
    }

    private var wheelSysPrecheckinLegacySection: some View {
        Section {
            wheelSysPrecheckinInlineContent
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
        } header: {
            Label("wheelsys.precheckin.title".localized, systemImage: "checkmark.seal.fill")
        } footer: {
            Text("wheelsys.precheckin.inline_footer".localized)
                .font(.caption)
        }
    }

    @MainActor
    @discardableResult
    private func submitWheelSysPrecheckin(silent: Bool = false) async -> Bool {
        guard wheelSysReturnPrefill != nil else { return false }
        guard let rentalId = wheelSysEffectiveEntityId.flatMap({ Int($0) }), rentalId > 0 else {
            if !silent {
                wheelsysPrecheckinStatus = "wheelsys.return.no_entity".localized
                wheelsysPrecheckinIsError = true
                HapticManager.shared.error()
                ToastManager.shared.show("wheelsys.return.no_entity".localized, type: .error)
            }
            return false
        }
        guard wheelSysPrecheckinSubmitReady else {
            if !silent {
                wheelsysPrecheckinStatus = wheelSysReturnKmValidationMessage
                wheelsysPrecheckinIsError = true
                HapticManager.shared.error()
                ToastManager.shared.show(wheelSysReturnKmValidationMessage, type: .error)
            }
            return false
        }
        guard wheelsysPrecheckinContext?.canSubmit ?? true else {
            let display = wheelsysPrecheckinContext?.statusIneligibleMessage
                ?? "wheelsys.precheckin.status_not_eligible".localized
            if !silent {
                wheelsysPrecheckinStatus = display
                wheelsysPrecheckinIsError = true
                HapticManager.shared.error()
                ToastManager.shared.show(display, type: .error)
            }
            return false
        }
        guard wheelSysCheckInKm != nil else {
            if !silent {
                wheelsysPrecheckinStatus = "wheelsys.precheckin.km_required".localized
                wheelsysPrecheckinIsError = true
                HapticManager.shared.error()
                ToastManager.shared.show("wheelsys.precheckin.km_required".localized, type: .error)
            }
            return false
        }

        if wheelsysPrecheckinSucceeded { return true }

        let latestReturnKm = wheelSysCheckInKm!
        let latestReturnFuel = fuelEighthsValue
        let checkoutKm = wheelSysCheckoutKm ?? 0
        let checkoutFuel = wheelSysCheckoutFuel ?? fuelEighthsValue
        let contextKmBefore = wheelsysPrecheckinContext?.mileageFuel.currentReturnMileage ?? 0
        let contextFuelBefore = wheelsysPrecheckinContext?.mileageFuel.currentReturnFuel ?? 0

        wheelsysPrecheckinBusy = true
        wheelsysPrecheckinStatus = nil
        wheelsysPrecheckinIsError = false
        defer { wheelsysPrecheckinBusy = false }

        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "PrecheckinUI",
            "submit payload rentalId=\(rentalId) rnt=\(wheelSysReturnPrefill?.raNo ?? "nil") " +
            "res=\(wheelSysReturnPrefill?.resNo ?? "nil") plate=\(arac.plaka) " +
            "checkoutKm=\(checkoutKm) latestReturnKm=\(latestReturnKm) " +
            "checkoutFuel=\(checkoutFuel) latestReturnFuel=\(latestReturnFuel) " +
            "contextKmBefore=\(contextKmBefore) contextKmAfter=\(latestReturnKm) " +
            "contextFuelBefore=\(contextFuelBefore) contextFuelAfter=\(latestReturnFuel)",
            cid: WheelSysDebug.newCorrelationId()
        )
        await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: franchiseId)
        _ = await WheelSysVehicleDamageService.syncClientCookieToServerIfNeeded(franchiseId: franchiseId)
        do {
            let result = try await WheelSysPrecheckinService.submit(
                franchiseId: franchiseId,
                rentalId: rentalId,
                confirmCustomer: true,
                confirmVehicle: true,
                confirmDamagesReviewed: true,
                confirmInsuranceReviewed: true,
                checkInMileage: latestReturnKm,
                checkInFuel: latestReturnFuel,
                checkInUserId: WheelSysCheckinService.resolvedCheckInUserId(from: wheelsysCheckin.preview),
                checkInDate: WheelSysZurichDateTime.formatDate(iadeTarihi),
                checkInTime: WheelSysZurichDateTime.formatTime(WheelSysZurichDateTime.now()),
                notes: nil
            )
            if result.success {
                wheelsysPrecheckinSucceeded = true
                wheelsysPrecheckinStatus = "wheelsys.precheckin.submit_success".localized
                wheelsysPrecheckinIsError = false
                if !silent {
                    HapticManager.shared.scanSuccess()
                    ToastManager.shared.show(
                        "wheelsys.precheckin.submit_success".localized,
                        type: .success,
                        duration: 3.5,
                        playHaptic: false
                    )
                }
                WheelSysActivityReporter.record(
                    .precheckin(
                        plate: arac.plakaFormatli,
                        rntNo: wheelSysReturnPrefill?.raNo,
                        resNo: wheelSysReturnPrefill?.resNo,
                        rentalId: result.rentalId > 0 ? result.rentalId : rentalId
                    ),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
                WheelSysDebug.logCH(
                    franchiseId: franchiseId,
                    "PrecheckinUI",
                    silent ? "completed via Complete Return." : "completed. Final check-in is disabled for return flow.",
                    cid: WheelSysDebug.newCorrelationId()
                )
                let lockedRentalId = result.rentalId > 0 ? result.rentalId : rentalId
                let lockedVehicleId = wheelsysCheckin.preview?.vehicleEntityId
                    ?? wheelSysReturnPrefill?.vehicleEntityId
                    ?? arac.wheelsysVehicleId
                wheelsysCheckin.lockRentalAfterPrecheckin(WheelSysLockedRentalContext(
                    rentalId: lockedRentalId,
                    vehicleId: lockedVehicleId,
                    plate: arac.plaka,
                    resNo: result.resNo ?? wheelsysCheckin.resolvedResNo,
                    rntNo: result.rntNo ?? wheelsysCheckin.preview?.raNo
                ))
                wheelsysPrecheckinContext = nil
                wheelsysPreviewLoaded = false
                await loadWheelSysPrecheckinContextIfNeeded()
                await wheelsysCheckin.reloadPreview()
                return true
            } else {
                let msg = result.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = (msg?.isEmpty == false) ? msg! : "wheelsys.precheckin.submit_failed".localized
                wheelsysPrecheckinStatus = display
                wheelsysPrecheckinIsError = true
                if !silent {
                    HapticManager.shared.error()
                    ToastManager.shared.show(display, type: .error)
                }
                return false
            }
        } catch {
            let display = WheelSysUserFacingError.message(for: error)
            wheelsysPrecheckinStatus = display
            wheelsysPrecheckinIsError = true
            if !silent {
                HapticManager.shared.error()
                ToastManager.shared.show(display, type: .error)
            }
            if WheelSysSessionPromptCenter.isSessionError(error) {
                WheelSysSessionPromptCenter.notifyIfSessionError(error)
            }
            return false
        }
    }

    private var wheelSysEffectiveEntityId: String? {
        if let id = wheelsysCheckin.entityId, !id.isEmpty { return id }
        if let pre = wheelSysReturnPrefill, pre.rentalEntityId > 0 {
            return String(pre.rentalEntityId)
        }
        return nil
    }

    /// True when WheelSys rental context is present (prefill, preview, or locked entity) — suppresses false "no match" warnings.
    private var wheelSysHasResolvedWheelSysRental: Bool {
        if wheelSysEffectiveEntityId != nil { return true }
        if wheelsysCheckin.preview != nil { return true }
        if let pre = wheelSysReturnPrefill, pre.rentalEntityId > 0 { return true }
        if wheelsysPrecheckinContext != nil { return true }
        return false
    }

    private var wheelSysPrecheckinKmFuelPreview: String? {
        guard let returnKm = wheelSysCheckInKm else { return nil }
        let checkoutKm = wheelsysPrecheckinContext?.mileageFuel.checkoutMileage
            ?? wheelsysCheckin.preview?.mileageFrom
            ?? wheelSysReturnPrefill?.checkoutMileage
        let checkoutFuel = wheelsysPrecheckinContext?.mileageFuel.checkoutFuel
            ?? wheelsysCheckin.preview?.fuelFrom
        let checkoutKmText = checkoutKm.map { "\($0)" } ?? "—"
        let checkoutFuelText = checkoutFuel.map { "\($0)/8" } ?? "—"
        return String(
            format: "wheelsys.precheckin.km_preview".localized,
            checkoutKmText,
            checkoutFuelText,
            returnKm,
            fuelEighthsValue
        )
    }

    @MainActor
    private func loadWheelSysPrecheckinContextIfNeeded(force: Bool = false) async {
        guard wheelSysReturnPrefill != nil else { return }
        guard let rentalId = wheelSysEffectiveEntityId.flatMap({ Int($0) }), rentalId > 0 else { return }
        if !force, wheelsysPrecheckinContext != nil { return }
        if let existing = wheelsysPrecheckinContextTask {
            await existing.value
            if !force { return }
        }
        if force { wheelsysPrecheckinContext = nil }
        let task = Task { @MainActor in
            wheelsysPrecheckinContextLoading = true
            defer {
                wheelsysPrecheckinContextLoading = false
                wheelsysPrecheckinContextTask = nil
            }
            let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
            do {
                wheelsysPrecheckinContext = try await WheelSysPrecheckinService.fetchContext(
                    franchiseId: franchiseId,
                    rentalId: rentalId,
                    resNo: wheelSysReturnPrefill?.resNo,
                    rntNo: wheelSysReturnPrefill?.raNo,
                    plateNo: arac.plaka
                )
                applyWheelSysCustomerFromResolvedSources()
                applyWheelSysOperationalFieldsFromPrecheckinContext()
            } catch {
                WheelSysDebug.warnCH(
                    franchiseId: franchiseId,
                    "PrecheckinUI",
                    "context prefetch failed: \(error.localizedDescription)"
                )
            }
        }
        wheelsysPrecheckinContextTask = task
        await task.value
    }

    private var wheelSysCheckoutKm: Int? {
        let candidates = [
            wheelsysPrecheckinContext?.mileageFuel.checkoutMileage,
            wheelsysCheckin.preview?.mileageFrom,
            wheelSysReturnPrefill?.checkoutMileage,
        ]
        return candidates.compactMap { $0 }.first(where: { $0 > 0 })
    }

    private func wheelSysComputedMilesDriven(fromCheckout checkout: Int, returnKm: Int?) -> Int? {
        guard checkout > 0, let returnKm, returnKm > checkout else { return nil }
        return returnKm - checkout
    }

    private var wheelSysKmDeltaIsValid: Bool {
        guard let checkout = wheelSysCheckoutKm, checkout > 0,
              let returnKm = wheelSysCheckInKm else { return false }
        return returnKm > checkout
    }

    private var wheelSysKmDeltaLine: String? {
        guard let checkout = wheelSysCheckoutKm, checkout > 0 else { return nil }
        guard let returnKm = wheelSysCheckInKm, returnKm > 0 else {
            return String(format: "wheelsys.return.km_checkout_baseline".localized, checkout)
        }
        let delta = returnKm - checkout
        if delta > 0 {
            return String(format: "wheelsys.return.km_delta".localized, checkout, returnKm, delta)
        }
        if delta == 0 {
            return String(format: "wheelsys.return.km_no_travel".localized, checkout)
        }
        return String(format: "wheelsys.return.km_below_checkout".localized, checkout, returnKm)
    }

    private var wheelSysCheckoutFuel: Int? {
        let candidates = [
            wheelsysPrecheckinContext?.mileageFuel.checkoutFuel,
            wheelsysCheckin.preview?.fuelFrom,
            wheelSysReturnPrefill?.checkoutFuel,
        ]
        return candidates.compactMap { $0 }.first(where: { $0 > 0 })
    }

    private var wheelSysReturnKmValidForSubmit: Bool {
        guard let returnKm = wheelSysCheckInKm,
              let checkoutKm = wheelSysCheckoutKm,
              checkoutKm > 0 else { return false }
        return returnKm > checkoutKm
    }

    private var wheelSysPrecheckinSubmitReady: Bool {
        wheelSysCheckInKm != nil && wheelSysReturnKmValidForSubmit
    }

    private var wheelSysReturnKmValidationMessage: String {
        guard let returnKm = wheelSysCheckInKm else {
            return "wheelsys.precheckin.km_required".localized
        }
        guard let checkoutKm = wheelSysCheckoutKm, checkoutKm > 0 else {
            return "wheelsys.precheckin.checkout_km_unknown".localized
        }
        if returnKm <= checkoutKm {
            return String(
                format: "wheelsys.precheckin.km_must_exceed_checkout".localized,
                checkoutKm
            )
        }
        return ""
    }

    private var wheelSysCheckInKm: Int? {
        let trimmed = kmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let km = Int(trimmed), km > 0 else { return nil }
        return km
    }

    private var wheelSysInsuranceCdpLabel: String? {
        if let cdp = wheelsysPrecheckinContext?.insurance?.cdp?
            .trimmingCharacters(in: .whitespacesAndNewlines), !cdp.isEmpty {
            return cdp
        }
        let products = wheelsysCheckin.preview?.insurance?.insuranceTypes ?? []
        let joined = products
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    @ViewBuilder
    private var wheelSysInsuranceCardContent: some View {
        if let insurance = wheelsysCheckin.preview?.insurance {
            WheelSysPalantirOpsHeader(
                title: "wheelsys.return.insurance_title".localized,
                badge: insurance.hasInsuranceCharge ? "wheelsys.return.insurance_charged".localized : nil
            )
            if let cdp = wheelSysInsuranceCdpLabel, !cdp.isEmpty {
                WheelSysPalantirDataRow(
                    label: "wheelsys.return.insurance_cdp".localized,
                    value: cdp
                )
            }
            if !insurance.insuranceChargeAmount.isEmpty {
                WheelSysPalantirDataRow(
                    label: "wheelsys.return.insurance_charge".localized,
                    value: insurance.insuranceChargeAmount
                )
            }
            if !insurance.excessAmount.isEmpty {
                WheelSysPalantirDataRow(
                    label: "wheelsys.return.insurance_excess".localized,
                    value: insurance.excessAmount
                )
            }
            if !insurance.damageExcessAmount.isEmpty {
                WheelSysPalantirDataRow(
                    label: "wheelsys.return.insurance_damage_excess".localized,
                    value: insurance.damageExcessAmount
                )
            }
            if !insurance.insuranceTypes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("wheelsys.return.insurance_products".localized)
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                    ForEach(insurance.insuranceTypes, id: \.self) { product in
                        Text("• \(product)")
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textPrimary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var wheelSysInsuranceSection: some View {
        if wheelsysCheckin.preview?.insurance != nil {
            Section {
                wheelSysInsuranceCardContent
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Label("wheelsys.return.insurance_header".localized, systemImage: "shield.lefthalf.filled")
            }
        }
    }

    @ViewBuilder
    private var wheelSysNotesSidebarEntry: some View {
        let rentalCount = wheelsysCheckin.preview?.rentalNotes.count ?? 0
        let vehicleCount = wheelsysCheckin.preview?.vehicleNotes.count ?? 0
        let total = rentalCount + vehicleCount
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(total == 0
                     ? "wheelsys.return.notes_empty".localized
                     : String(format: "wheelsys.return.notes_count".localized, total))
                    .font(PalantirTheme.bodyFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text("wheelsys.return.notes_sidebar_hint".localized)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer(minLength: 0)
            WheelSysPalantirSecondaryButton(
                title: "wheelsys.return.open_notes".localized,
                icon: "sidebar.right"
            ) {
                showWheelSysNotesSidebar = true
            }
        }
    }

    @ViewBuilder
    private var wheelSysNotesCardContent: some View {
        if let preview = wheelsysCheckin.preview {
            let allNotes = preview.rentalNotes + preview.vehicleNotes
            if allNotes.isEmpty {
                WheelSysPalantirStatusStrip(
                    icon: "note.text",
                    message: "wheelsys.return.notes_empty".localized,
                    tint: PalantirTheme.textMuted
                )
            } else {
                WheelSysPalantirNotesPreview(
                    notes: Array(allNotes.prefix(3)),
                    onShowAll: allNotes.count > 3 ? { showWheelSysNotesSidebar = true } : nil
                )
            }
        } else if wheelsysCheckin.entityId != nil {
            WheelSysPalantirStatusStrip(
                icon: "note.text",
                message: "wheelsys.return.notes_empty".localized,
                tint: PalantirTheme.textMuted
            )
        } else if case .loadingPreview = wheelsysCheckin.phase {
            WheelSysPalantirStatusStrip(
                icon: "arrow.triangle.2.circlepath",
                message: "wheelsys.return.loading_preview".localized,
                showsSpinner: true
            )
        }

        if wheelsysCheckin.entityId != nil {
            if let entityId = wheelsysCheckin.entityId {
                Text(String(format: "wheelsys.return.note_entity_hint".localized, entityId))
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            WheelSysPalantirTextInput(
                label: "wheelsys.return.note_placeholder".localized,
                text: $wheelsysNewNoteText
            )
            WheelSysPalantirPrimaryButton(
                title: "wheelsys.return.save_note".localized,
                icon: "square.and.pencil",
                isLoading: wheelsysNoteSaving,
                disabled: wheelsysNoteSaving
                    || wheelsysNewNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { await saveWheelSysRentalNote() }
            }
            if let status = wheelsysNoteStatus {
                WheelSysPalantirStatusStrip(
                    icon: wheelsysNoteStatusIsError ? "exclamationmark.triangle" : "checkmark.circle",
                    message: status,
                    tint: wheelsysNoteStatusIsError ? PalantirTheme.critical : PalantirTheme.success
                )
            }
        }
    }

    private var wheelSysNotesSection: some View {
        Section {
            wheelSysNotesCardContent
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
        } header: {
            Label("wheelsys.return.notes_header".localized, systemImage: "note.text")
        }
    }

    private func wheelSysNoteRow(_ note: WheelSysEntityNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                if !note.createdBy.isEmpty {
                    Text(note.createdBy)
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer(minLength: 0)
                if !note.createdAt.isEmpty {
                    Text(note.createdAt)
                        .font(PalantirTheme.dataFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            Text(note.text)
                .font(PalantirTheme.bodyFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PalantirTheme.background.opacity(0.55))
        )
    }

    private func formatWheelSysDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df.string(from: date)
    }

    private func wheelSysReadOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(PalantirTheme.textMuted)
            Spacer()
            Text(value)
                .font(PalantirTheme.dataFont(11))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
    }

    @MainActor
    private func loadWheelSysPreviewIfNeeded() async {
        guard wheelSysReturnPrefill != nil || wheelSysCHOpsEnabled else { return }
        let entityKey = wheelSysPreviewCacheKey()
        if wheelsysPreviewLoaded, wheelsysPreviewEntityKey == entityKey, wheelsysCheckin.preview != nil {
            return
        }
        wheelsysPreviewLoaded = true
        wheelsysPreviewEntityKey = entityKey

        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let store = WheelSysVehicleFleetStatusStore.shared
        if wheelSysCHOpsEnabled {
            store.bootstrapFromDiskIfNeeded()
            if let pre = wheelSysReturnPrefill {
                wheelsysCheckin.prepareFromPrefill(pre, arac: arac)
                if kmText.isEmpty {
                    applyWheelSysReturnPrefill(pre)
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: franchiseId)
                _ = await WheelSysVehicleDamageService.syncClientCookieToServerIfNeeded(franchiseId: franchiseId)
            }
            if wheelSysCHOpsEnabled, store.fleetVehicle(for: arac) == nil {
                group.addTask { await store.refreshIfNeeded() }
            }
            if let pre = wheelSysReturnPrefill {
                group.addTask { @MainActor in
                    if pre.rentalEntityId > 0 {
                        await wheelsysCheckin.loadPreviewWithKnownEntity(
                            franchiseId: FirebaseService.shared.currentFranchiseId,
                            entityId: String(pre.rentalEntityId),
                            resNo: pre.resNo,
                            arac: arac,
                            fleetCarId: pre.vehicleEntityId,
                            prefill: pre
                        )
                    } else if !pre.resNo.isEmpty {
                        await wheelsysCheckin.resolveAndLoadPreview(
                            arac: arac,
                            resNo: pre.resNo,
                            franchiseId: FirebaseService.shared.currentFranchiseId,
                            prefill: pre
                        )
                    } else {
                        wheelsysCheckin.phase = .noEntity
                    }
                }
            }
        }

        if wheelSysCHOpsEnabled, let pre = wheelSysReturnPrefill, kmText.isEmpty {
            applyWheelSysReturnPrefill(pre)
        }
        applyWheelSysCustomerFromResolvedSources()
        applyWheelSysMileageFromResolvedSources()
    }

    private func wheelSysPreviewCacheKey() -> String {
        let pre = wheelSysReturnPrefill
        let rentalId = pre?.rentalEntityId ?? 0
        let res = pre?.resNo ?? ""
        return "\(rentalId)|\(res)|\(arac.id.uuidString)"
    }

    @MainActor
    private func deleteWheelSysNote(_ note: WheelSysEntityNote) async {
        guard wheelsysCheckin.entityId != nil else { return }
        wheelsysNoteDeleting = true
        wheelsysNoteStatus = nil
        defer { wheelsysNoteDeleting = false }
        let domain = note.source == "vehicle" ? 1 : 5
        let entityKey: String
        if note.source == "vehicle" {
            entityKey = wheelsysCheckin.preview?.vehicleEntityId
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            entityKey = wheelsysCheckin.entityId ?? ""
        }
        guard !entityKey.isEmpty else {
            wheelsysNoteStatus = "wheelsys.return.no_entity".localized
            wheelsysNoteStatusIsError = true
            return
        }
        do {
            try await WheelSysCheckinService.deleteNote(
                franchiseId: FirebaseService.shared.currentFranchiseId,
                entityKey: entityKey,
                domain: domain,
                noteId: note.id
            )
            await wheelsysCheckin.reloadPreview()
            wheelsysNoteStatus = "wheelsys.return.note_deleted".localized
            wheelsysNoteStatusIsError = false
            HapticManager.shared.success()
            WheelSysActivityReporter.record(
                .noteDeleted(plate: arac.plakaFormatli, entityId: entityKey),
                viewModel: viewModel,
                userProfile: authManager.userProfile
            )
        } catch {
            wheelsysNoteStatus = error.localizedDescription
            wheelsysNoteStatusIsError = true
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func saveWheelSysRentalNote() async {
        guard let entityId = wheelsysCheckin.entityId else {
            wheelsysNoteStatus = "wheelsys.return.no_entity".localized
            wheelsysNoteStatusIsError = true
            return
        }
        let text = wheelsysNewNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        wheelsysNoteSaving = true
        wheelsysNoteStatus = nil
        defer { wheelsysNoteSaving = false }
        let vehicleEntityId = wheelsysCheckin.preview?.vehicleEntityId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let creatorId = wheelsysCheckin.preview?.checkInUserId
        do {
            try await WheelSysCheckinService.saveReturnNotes(
                franchiseId: FirebaseService.shared.currentFranchiseId,
                rentalEntityId: entityId,
                vehicleEntityId: vehicleEntityId?.isEmpty == false ? vehicleEntityId : nil,
                noteText: text,
                creatorId: creatorId?.isEmpty == false ? creatorId : nil
            )
            wheelsysNewNoteText = ""
            await wheelsysCheckin.reloadPreview()
            wheelsysNoteStatus = "wheelsys.return.note_saved".localized
            wheelsysNoteStatusIsError = false
            HapticManager.shared.success()
            ToastManager.shared.show("wheelsys.return.note_saved".localized, type: .success)
            WheelSysActivityReporter.record(
                .noteSaved(plate: arac.plakaFormatli, entityId: entityId),
                viewModel: viewModel,
                userProfile: authManager.userProfile
            )
        } catch {
            wheelsysNoteStatus = error.localizedDescription
            wheelsysNoteStatusIsError = true
            HapticManager.shared.error()
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    private var iadeBilgileriSection: some View {
        Section {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("Vehicle".localized)
                    Spacer()
                    Text(arac.plakaFormatli)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                
                DatePicker("Return Date".localized, selection: $iadeTarihi, displayedComponents: processDatePickerComponents)
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
        } header: {
            Label("Return Information".localized, systemImage: "arrow.uturn.down.circle")
        } footer: {
            Text("Complete vehicle check-in (km and fuel) before return photos.".localized)
                .font(.caption)
        }
    }
    
    private var activeToken: String {
        committedIade?.qrToken ?? existingIade?.qrToken ?? localQRToken
    }

    private func startFormListener(token: String) {
        guard !shouldSkipKioskFormListener else { return }
        formListener?.remove()
        formListener = Firestore.firestore()
            .collection("franchises")
            .document(FirebaseService.shared.currentFranchiseId)
            .collection("returnFormData")
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

    private func autofillCustomerFromLinkedExitKeepingNamesEmpty() {
        guard let lid = quickDamageLinkedExitId,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return }
        if customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customerEmail = ex.customerEmail ?? ""
        }
        if customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customerNationalId = ex.customerNationalId ?? ""
        }
        if testDriverFirstName.isEmpty, testDriverLastName.isEmpty {
            testDriverFirstName = ex.testDriverFirstName ?? ""
            testDriverLastName = ex.testDriverLastName ?? ""
            if !(ex.testDriverFirstName ?? "").isEmpty || !(ex.testDriverLastName ?? "").isEmpty {
                showAdditionalDriverFields = true
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

    @ViewBuilder
    private var checklistSection: some View {
        if !wheelSysCHOpsEnabled {
        Section {
            Toggle("Customer was present".localized, isOn: $checklist.customerPresent)
            Toggle("Customer had no time".localized, isOn: $checklist.customerNoTime)
            Toggle("Key was taken from keybox".localized, isOn: $checklist.keyFromKeybox)
            Toggle("Customer refused to sign".localized, isOn: $checklist.customerRefusedSignature)
            Toggle("Customer left key at office".localized, isOn: $checklist.customerLeftKeyAtOffice)
        } header: {
            Label("Return Checklist".localized, systemImage: "checklist")
        } footer: {
            Text("Optional: You can complete return without selecting these items.".localized)
                .font(.caption)
        }
        }
    }
    
    private var signatureAndContactSection: some View {
        Section {
            customerContactAndSignatureBlock
        } header: {
            Label(
                isTurkeyFranchise ? "Customer Information".localized : "Customer Information & Signature".localized,
                systemImage: "person.text.rectangle"
            )
        } footer: {
            Text(isTurkeyFranchise ? "tr_terms.customer_sign_via_wizard_footer".localized : "Name, email and signature are used in Return PDF and email delivery.".localized)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var customerContactAndSignatureBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.teal)
                    .font(.system(size: 15, weight: .medium))
                Text(isTurkeyFranchise ? "Customer Information".localized : "Customer Information & Signature".localized)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                if customerSignatureImage != nil || !customerFirstName.isEmpty || !customerLastName.isEmpty || !customerEmail.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                TextField("First Name".localized, text: $customerFirstName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .textInputAutocapitalization(.words)
                Divider().padding(.leading, 12)
                TextField("Last Name".localized, text: $customerLastName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .textInputAutocapitalization(.words)
                Divider().padding(.leading, 12)
                TextField("Email".localized, text: $customerEmail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .cornerRadius(10)
            .disabled(isCustomerInfoReadOnlyFromOperation)

            if isTurkeyFranchise {
                Toggle("operations.show_additional_driver".localized, isOn: $showAdditionalDriverFields)
                    .font(.caption)
                    .padding(.top, 10)
                if showAdditionalDriverFields {
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
                .disabled(isCustomerInfoReadOnlyFromOperation)
                Text("operations.signature_official_driver_hint".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if customerSignatureImage != nil {
                    CustomerSignatureFormBlock(
                        image: customerSignatureImage!,
                        onUpdate: { showSignatureSheet = true },
                        onRemove: isCustomerInfoReadOnlyFromOperation ? nil : {
                            customerSignatureImage = nil
                            signatureWasRemoved = true
                        }
                    )
                    .padding(.top, 6)
                }
            } else {
                Text("tr_return.vehicle_pdf_footer".localized)
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
            .disabled(isCustomerInfoReadOnlyFromOperation)
        }
        .padding(.vertical, 4)
    }
    
    private func photoStampBadge(globalIndex: Int) -> some View {
        processPhotoIndexBadge(globalIndex: globalIndex, processDate: returnPhotoReturnDate)
    }

    private func processPhotoIndexBadge(globalIndex: Int, processDate: Date) -> some View {
        let stampColor: Color = isGermanyFranchise ? .blue : .secondary
        return VStack(alignment: .trailing, spacing: 2) {
            Text(ProcessPhotoStampLabels.processPhotoIndexLabel(globalIndex))
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(stampColor)
            if isGermanyFranchise {
                Text(ProcessPhotoStampLabels.formatDisplayDate(processDate, includeTime: false))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(stampColor)
                Text(ProcessPhotoStampLabels.formatPDFTime(processDate))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(stampColor)
            } else {
                Text(ProcessPhotoStampLabels.processPhotoDateCaption(processDate, includeTime: false))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(stampColor)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background((isGermanyFranchise ? Color.blue : Color.secondary).opacity(0.12))
        .cornerRadius(4)
    }

    private static let photoThumbSize: CGFloat = 100
    private static let photoThumbRowHeight: CGFloat = 108

    @ViewBuilder
    private var returnPhotoGalleryContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(existingPhotoURLs.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        KFImage(URL(string: existingPhotoURLs[index]))
                            .placeholder { PalantirTheme.surfaceHigh }
                            .resizable()
                            .scaledToFill()
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                            .clipped()
                            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                            .onTapGesture {
                                photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: existingPhotoURLs, startIndex: index)
                            }
                        VStack(alignment: .trailing, spacing: 2) {
                            Button { existingPhotoURLs.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(PalantirTheme.critical)
                            }
                            photoStampBadge(globalIndex: index)
                        }
                        .padding(4)
                    }
                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                }
                ForEach(fotograflar.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: fotograflar[index])
                            .resizable().scaledToFill()
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                            .clipped()
                            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                            .onTapGesture {
                                photoGallerySession = PhotoGalleryFullScreenSession(images: fotograflar + cameraPhotos, startIndex: index)
                            }
                        VStack(alignment: .trailing, spacing: 2) {
                            Button {
                                CheckoutReturnPhotoCapture.removeGalleryPhoto(
                                    at: index, fotograflar: &fotograflar,
                                    fingerprintKeys: &galleryPhotoFingerprintKeys,
                                    pendingUploadTracker: pendingUploadTracker
                                )
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(PalantirTheme.critical)
                            }
                            photoStampBadge(globalIndex: existingPhotoURLs.count + index)
                        }
                        .padding(4)
                    }
                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                }
                ForEach(cameraPhotos.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: cameraPhotos[index])
                            .resizable().scaledToFill()
                            .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                            .clipped()
                            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                            .onTapGesture {
                                photoGallerySession = PhotoGalleryFullScreenSession(
                                    images: fotograflar + cameraPhotos,
                                    startIndex: fotograflar.count + index
                                )
                            }
                        VStack(alignment: .trailing, spacing: 2) {
                            Button {
                                CheckoutReturnPhotoCapture.removeCameraPhoto(
                                    at: index, cameraPhotos: &cameraPhotos,
                                    fingerprintKeys: &cameraPhotoFingerprintKeys,
                                    pendingUploadTracker: pendingUploadTracker
                                )
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(PalantirTheme.critical)
                            }
                            photoStampBadge(globalIndex: existingPhotoURLs.count + fotograflar.count + index)
                        }
                        .padding(4)
                    }
                    .frame(width: Self.photoThumbSize, height: Self.photoThumbSize)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: Self.photoThumbRowHeight)
    }

    @ViewBuilder
    private var returnPhotoActionsContent: some View {
        if usesCHPalantirReturnChrome {
            HStack(spacing: 12) {
                WheelSysPalantirSecondaryButton(
                    title: "Choose from Gallery".localized,
                    icon: "photo.on.rectangle",
                    disabled: showCamera
                ) {
                    guard !showCamera else { return }
                    showImagePicker = true
                }
                .frame(maxWidth: .infinity)
                WheelSysPalantirSecondaryButton(
                    title: "Take Photo".localized,
                    icon: "camera",
                    tint: PalantirTheme.success,
                    disabled: showImagePicker
                ) {
                    openReturnCamera()
                }
                .frame(maxWidth: .infinity)
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
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showCamera)
                Button(action: openReturnCamera) {
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
        }
    }

    private var fotografSection: some View {
        Section {
            returnPhotoGalleryContent
            returnPhotoActionsContent
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
                        dismissKeyboard()
                        HapticManager.shared.medium()
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
                                    Text("Complete Return".localized)
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
                    dismissKeyboard()
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
                .listRowBackground(Color.green.opacity(0.85))
                .foregroundColor(.white)
            }
        } header: {
            Label("Finalize return".localized, systemImage: "checkmark.seal.fill")
                .textCase(nil)
                .font(.subheadline)
        } footer: {
            Text("Mark this return as completed and close the form.".localized)
                .font(.caption)
        }
    }
    
    private var completionOverlay: some View {
        PalantirOpsCompletionOverlay(
            title: "Completing Return...".localized,
            steps: PalantirReturnCompletionSteps.steps,
            activeStepIndex: PalantirReturnCompletionSteps.activeIndex(
                progress: completionProgress,
                precheckinBusy: wheelsysPrecheckinBusy,
                syncPhase: wheelsysCheckin.completionSyncPhase
            ),
            progress: completionProgress,
            succeeded: completionPhase == .completed,
            successTitle: "Return Completed".localized,
            microcopy: completionOverlayMicrocopy
        )
    }

    private var completionOverlayMicrocopy: String? {
        if wheelsysPrecheckinBusy {
            return "wheelsys.precheckin.title".localized
        }
        if let status = wheelsysPrecheckinStatus, wheelsysPrecheckinIsError {
            return status
        }
        let sync = wheelsysCheckin.completionMicrocopy
        if wheelsysCheckin.completionSyncPhase != .idle {
            return sync
        }
        return nil
    }

    private func uploadTrRentalTermsSignature(signedDocumentData: Data, languageCode: String) {
        let isPdf = TurkeyRentalTermsPlaceholders.isPdfDocumentData(signedDocumentData)
        let ext = isPdf ? "pdf" : "png"
        let contentType = isPdf ? "application/pdf" : "image/png"
        let folder = isPdf ? "tr_rental_terms_signed" : "tr_rental_terms_signatures"
        let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/\(folder)/\(UUID().uuidString).\(ext)"
        FirebaseService.shared.uploadData(signedDocumentData, path: path, contentType: contentType) { url, error in
            DispatchQueue.main.async {
                if let url {
                    self.trRentalTermsLanguage = languageCode
                    self.trRentalTermsSignatureURL = url
                    self.trRentalTermsAcceptedAt = Date()
                    self.hasUnsavedChanges = true
                    self.refreshTurkeyTermsInlinePreview()
                    ToastManager.shared.show("tr_terms.saved".localized, type: .success)
                    return
                }
                let err = error ?? NSError(domain: "ReturnTerms", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
                ErrorManager.shared.showError(err, context: "Terms")
            }
        }
    }

    private func draftIadeForTurkeyPdf() -> IadeIslemi {
        let base = committedIade ?? existingIade
        let pickUpStored = pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let dropOffStored = dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let testDriverFirstStored = testDriverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let testDriverLastStored = testDriverLastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let linkedExitResolved: UUID? = {
            if let x = base?.linkedExitId { return x }
            if let s = trReturnHandoverPrefill?.linkedExitId, let u = UUID(uuidString: s) { return u }
            return nil
        }()
        var i = IadeIslemi(
            aracId: arac.id,
            aracPlaka: arac.plakaFormatli,
            iadeTarihi: iadeTarihi,
            fotograflar: [],
            notlar: notlar,
            status: .inProgress,
            createdAt: base?.createdAt ?? Date(),
            createdBy: base?.createdBy,
            checklist: checklist.hasAnySelection ? checklist : nil,
            customerFirstName: customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerLastName: customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerEmail: customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            customerNationalId: customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
            testDriverFirstName: testDriverFirstStored,
            testDriverLastName: testDriverLastStored,
            customerSignatureURL: nil,
            km: Int(kmText),
            yakitSeviyesi: fuelLevelForStorage(),
            bayiAdi: nil,
            pickUpBranch: pickUpStored,
            dropOffBranch: dropOffStored,
            linkedExitId: linkedExitResolved,
            navKodu: resolvedNavKoduForSave(base: base, linkedExitId: linkedExitResolved),
            vehicleItemsChecklist: vehicleItemsChecklist,
            qrToken: base?.qrToken ?? localQRToken,
            expectedReturnPlanned: base?.expectedReturnPlanned ?? false,
            trRentalTermsAcceptedAt: trRentalTermsAcceptedAt,
            trRentalTermsLanguage: trRentalTermsLanguage,
            trRentalTermsSignatureURL: trRentalTermsSignatureURL
        )
        i.id = base?.id ?? UUID()
        i.franchiseId = FirebaseService.shared.currentFranchiseId
        return i
    }

    private func loadDamageImagesForTurkeyPdf(completion: @escaping ([UIImage]) -> Void) {
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

    private func openTurkeyTermsWizard() {
        loadDamageImagesForTurkeyPdf { damage in
            turkeyWizardDamagePhotos = damage
            if let url = trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                StorageImageLoader.shared.loadData(from: url) { data in
                    DispatchQueue.main.async {
                        if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                            turkeyWizardPrefilledTermsPdfData = data
                        } else {
                            turkeyWizardPrefilledTermsPdfData = nil
                        }
                        showTurkeyTermsWizard = true
                    }
                }
            } else {
                turkeyWizardPrefilledTermsPdfData = nil
                showTurkeyTermsWizard = true
            }
        }
    }

    private func openTurkeyVehicleWizard() {
        guard !allPhotos.isEmpty else {
            ToastManager.shared.show("tr_terms.need_photo_first".localized, type: .warning)
            return
        }
        loadDamageImagesForTurkeyPdf { damage in
            turkeyWizardDamagePhotos = damage
            showTurkeyVehicleWizard = true
        }
    }

    private func refreshTurkeyTermsInlinePreview() {
        guard isTurkeyFranchise else { return }
        guard let url = trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            turkeyInlineTermsPdf = nil
            return
        }
        StorageImageLoader.shared.loadData(from: url) { data in
            DispatchQueue.main.async {
                if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                    turkeyInlineTermsPdf = data
                } else {
                    turkeyInlineTermsPdf = nil
                }
            }
        }
    }

    private func refreshTurkeyVehicleInlinePreview() {
        guard isTurkeyFranchise, let sig = customerSignatureImage, !allPhotos.isEmpty else {
            turkeyInlineVehiclePdf = nil
            return
        }
        loadDamageImagesForTurkeyPdf { damage in
            let pdf = IadePDFGenerator.shared.makeTurkeyReturnPdfDataWithCustomerSignature(
                iade: draftIadeForTurkeyPdf(),
                arac: arac,
                vehiclePhotos: allPhotos,
                damagePhotos: damage,
                franchiseDisplayName: turkeyCommercialTitle,
                turkeyNavContractDisplay: nil,
                staffSignerNameFallback: authManager.userProfile?.fullName,
                customerSignature: sig
            )
            DispatchQueue.main.async {
                turkeyInlineVehiclePdf = pdf
            }
        }
    }
    
    func loadExistingSignatureImage() {
        guard
            let signatureURL = existingIade?.customerSignatureURL
        else { return }
        
        StorageImageLoader.shared.loadImage(from: signatureURL) { loadedImage in
            if let loadedImage {
                self.customerSignatureImage = loadedImage
                self.signatureWasRemoved = false
            }
        }
    }
    
    private struct SignatureUploadOutcome {
        var firestoreURL: String?
        var pngDataToQueue: Data?
    }

    private func uploadSignatureIfNeeded(completion: @escaping (Result<SignatureUploadOutcome, Error>) -> Void) {
        if signatureWasRemoved && customerSignatureImage == nil {
            completion(.success(SignatureUploadOutcome(firestoreURL: nil, pngDataToQueue: nil)))
            return
        }

        guard let signatureImage = customerSignatureImage, let pngData = signatureImage.pngData() else {
            completion(.success(SignatureUploadOutcome(firestoreURL: existingIade?.customerSignatureURL, pngDataToQueue: nil)))
            return
        }

        let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/iade_signatures/\(UUID().uuidString).png"
        FirebaseService.shared.uploadData(pngData, path: path, contentType: "image/png") { url, error in
            if let url = url {
                self.signatureWasRemoved = false
                completion(.success(SignatureUploadOutcome(firestoreURL: url, pngDataToQueue: nil)))
                return
            }
            guard let error = error else {
                completion(.success(SignatureUploadOutcome(firestoreURL: self.existingIade?.customerSignatureURL, pngDataToQueue: nil)))
                return
            }
            print("❌ Signature upload error: \(error.localizedDescription)")
            if OfflineSyncDiagnostics.isLikelyTransientNetworkFailure(error) {
                completion(.success(SignatureUploadOutcome(firestoreURL: self.existingIade?.customerSignatureURL, pngDataToQueue: pngData)))
            } else {
                completion(.failure(error))
            }
        }
    }

    private func resolvedNavKoduForSave(base: IadeIslemi?, linkedExitId: UUID?) -> String? {
        let ws = wheelSysNavKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ws.isEmpty { return ws }
        if let n = base?.navKodu?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        let lid = linkedExitId ?? base?.linkedExitId
        guard let lid,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return nil }
        let code = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    private func mergedIadePhotoURLs(base: IadeIslemi?, existing: [String], newUploads: [String]) -> [String] {
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

    private func applyIadeSaveAfterUploads(
        status: IadeStatus,
        signatureURL: String?,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        let baseForUpdate = self.committedIade ?? self.existingIade
        let editingExistingSession = self.committedIade != nil || self.existingIade != nil
        let pickUpStored = pickUpBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let dropOffStored = dropOffBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString
        let testDriverFirstStored = isTurkeyFranchise ? testDriverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString : nil
        let testDriverLastStored = isTurkeyFranchise ? testDriverLastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString : nil
        let linkedExitResolved: UUID? = {
            if let x = baseForUpdate?.linkedExitId { return x }
            if let s = trReturnHandoverPrefill?.linkedExitId, let u = UUID(uuidString: s) { return u }
            return nil
        }()
        let finalPhotoURLs: [String]
        if editingExistingSession {
            finalPhotoURLs = mergedIadePhotoURLs(
                base: baseForUpdate,
                existing: self.existingPhotoURLs,
                newUploads: sortedNewPhotos
            )
        } else {
            finalPhotoURLs = sortedNewPhotos
        }

        let currentIade: IadeIslemi

        if let base = baseForUpdate {
            var updatedIade = IadeIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                iadeTarihi: iadeTarihi,
                fotograflar: finalPhotoURLs,
                notlar: notlar,
                status: status,
                createdAt: base.createdAt,
                createdBy: base.createdBy,
                checklist: self.checklist.hasAnySelection ? self.checklist : nil,
                customerFirstName: self.customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerLastName: self.customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerEmail: self.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                customerNationalId: self.customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
                testDriverFirstName: testDriverFirstStored,
                testDriverLastName: testDriverLastStored,
                customerSignatureURL: signatureURL,
                km: Int(self.kmText),
                yakitSeviyesi: self.fuelLevelForStorage(),
                bayiAdi: nil,
                pickUpBranch: pickUpStored,
                dropOffBranch: dropOffStored,
                linkedExitId: linkedExitResolved,
                navKodu: resolvedNavKoduForSave(base: baseForUpdate, linkedExitId: linkedExitResolved),
                returnEmailSentAt: base.returnEmailSentAt,
                returnEmailLastStatus: base.returnEmailLastStatus,
                returnEmailRecipient: base.returnEmailRecipient,
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil,
                qrToken: base.qrToken,
                trRentalTermsAcceptedAt: isTurkeyFranchise ? trRentalTermsAcceptedAt : nil,
                trRentalTermsLanguage: isTurkeyFranchise ? trRentalTermsLanguage : nil,
                trRentalTermsSignatureURL: isTurkeyFranchise ? trRentalTermsSignatureURL : nil
            )
            updatedIade.id = base.id
            // Preserve original Firestore path metadata + franchise scope on updates so the
            // write targets the exact same document and never spawns a new row.
            updatedIade.firestoreDocumentId = base.firestoreDocumentId
            updatedIade.firestoreScopedFranchiseId = base.firestoreScopedFranchiseId
            if !base.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedIade.franchiseId = base.franchiseId
            }
            currentIade = updatedIade

            viewModel.iadeGuncelle(updatedIade)

            print("✅ İade güncellendi - Status: \(status.rawValue), ID: \(updatedIade.id)")
        } else {
            let currentUserId = authManager.currentUser?.uid
            var yeniIade = IadeIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                iadeTarihi: iadeTarihi,
                fotograflar: finalPhotoURLs,
                notlar: notlar,
                status: status,
                createdBy: currentUserId,
                checklist: self.checklist.hasAnySelection ? self.checklist : nil,
                customerFirstName: self.customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerLastName: self.customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                customerEmail: self.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                customerNationalId: self.customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyString,
                testDriverFirstName: testDriverFirstStored,
                testDriverLastName: testDriverLastStored,
                customerSignatureURL: signatureURL,
                km: Int(self.kmText),
                yakitSeviyesi: self.fuelLevelForStorage(),
                bayiAdi: nil,
                pickUpBranch: pickUpStored,
                dropOffBranch: dropOffStored,
                linkedExitId: linkedExitResolved,
                navKodu: resolvedNavKoduForSave(base: nil, linkedExitId: linkedExitResolved),
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil,
                qrToken: self.localQRToken,
                trRentalTermsAcceptedAt: isTurkeyFranchise ? trRentalTermsAcceptedAt : nil,
                trRentalTermsLanguage: isTurkeyFranchise ? trRentalTermsLanguage : nil,
                trRentalTermsSignatureURL: isTurkeyFranchise ? trRentalTermsSignatureURL : nil
            )
            yeniIade.id = stableNewDocumentId
            currentIade = yeniIade

            viewModel.iadeEkle(yeniIade)

            print("✅ Yeni iade eklendi - Status: \(status.rawValue), ID: \(yeniIade.id)")
        }

        if status == .inProgress {
            committedIade = currentIade
            existingPhotoURLs = finalPhotoURLs
            fotograflar = []
            cameraPhotos = []
            galleryPhotoFingerprintKeys = []
            cameraPhotoFingerprintKeys = []
        }

        if !usedOfflineMediaQueue {
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendReturnNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
        }

        if rememberCustomerContact, status == .completed {
            let em = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if em.contains("@"), em.contains(".") {
                FirebaseService.shared.upsertCustomerContactRemember(
                    firstName: customerFirstName,
                    lastName: customerLastName,
                    email: em,
                    source: "ios_return",
                    completion: { _ in }
                )
            }
        }

        if !didPublishTrReturnHandoverLifecycle,
           let pre = trReturnHandoverPrefill,
           !pre.frontDeskDocumentId.isEmpty,
           status == .completed {
            didPublishTrReturnHandoverLifecycle = true
            FirebaseService.shared.updateFrontDeskCustomerHandoverLifecycle(
                documentId: pre.frontDeskDocumentId,
                iosPrefillStatus: "completed",
                linkedExitId: pre.linkedExitId,
                linkedIadeId: currentIade.id.uuidString,
                completion: { _ in }
            )
        }

        isUploading = false
        hasUnsavedChanges = false
        pendingUploadTracker.commitSessionToOperation()

        if status == .completed {
            isSaved = true
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos and signature will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendReturnNotification
            print("✅ Return completed - dismissing view")
            LiveActivityTracker.shared.record(
                .returnCompleted,
                title: "Return completed",
                subtitle: currentIade.km.map { "\($0) km · fuel \(currentIade.yakitSeviyesi ?? "—")" } ?? (currentIade.yakitSeviyesi ?? ""),
                plate: arac.plaka,
                recordId: currentIade.id.uuidString,
                userProfile: authManager.userProfile,
                force: true
            )
            operationFlowState = .completed
            finalizeCompletedFlow(with: currentIade)
        } else {
            isSaved = false
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Remaining media will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendReturnNotification
            operationFlowState = .draft
        }
    }
    
    private func finalizeCompletedFlow(with iade: IadeIslemi) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            completionPhase = .completed
            completionProgress = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onIadeCompleted?(iade)
            withAnimation(.easeInOut(duration: 0.2)) {
                showCompletionOverlay = false
            }
            dismiss()
        }
    }
    
    func kaydet(status: IadeStatus) {
        if isTurkeyFranchise, status == .completed, !turkeyComplianceReadyForComplete {
            ToastManager.shared.show("tr_return.compliance_incomplete".localized, type: .error)
            if customerSignatureImage == nil {
                openTurkeyVehicleWizard()
            }
            isUploading = false
            if operationFlowState.canTransition(to: .draft) {
                operationFlowState = .draft
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                showCompletionOverlay = false
            }
            return
        }
        if operationFlowState.canTransition(to: .uploadingMedia) {
            operationFlowState = .uploadingMedia
        }
        isUploading = true
        completionProgress = 0.05
        wheelsysCheckin.resetCompletionSync()
        uploadedPhotoURLs = []

        let stableDocumentId = (committedIade ?? existingIade)?.id ?? UUID()

        uploadSignatureIfNeeded { result in
            switch result {
            case .failure(let error):
                self.isUploading = false
                self.operationFlowState = .failed
                if status == .completed {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionOverlay = false
                    }
                }
                ErrorManager.shared.showError(error, context: "Return Save")
            case .success(let sig):
                let signatureURL = sig.firestoreURL
                let signaturePNGToQueue = sig.pngDataToQueue

                let allPhotosToUpload = self.fotograflar + self.cameraPhotos

                var indexedPhotoURLs: [(index: Int, url: String)] = []
                var uploadErrors: [Error] = []
                let group = DispatchGroup()
                let lock = NSLock()

                for (index, foto) in allPhotosToUpload.enumerated() {
                    if let preUploadedURL = self.pendingUploadTracker.uploadedURL(for: foto) {
                        indexedPhotoURLs.append((index: index, url: preUploadedURL))
                        let totalCount = allPhotosToUpload.count
                        if totalCount > 0 {
                            self.completionProgress = min(0.70, 0.05 + (Double(indexedPhotoURLs.count) / Double(totalCount)) * 0.65)
                        }
                        continue
                    }
                    group.enter()
                    let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/iade_fotograflari/\(UUID().uuidString).jpg"
                    CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                        DispatchQueue.main.async {
                            if let url = url {
                                lock.lock()
                                indexedPhotoURLs.append((index: index, url: url))
                                lock.unlock()
                                let totalCount = allPhotosToUpload.count
                                if totalCount > 0 {
                                    self.completionProgress = min(0.70, 0.05 + (Double(indexedPhotoURLs.count) / Double(totalCount)) * 0.65)
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
                    let shouldQueuePhotos = canOfflineSinkPhotos
                    let shouldQueueSignature = signaturePNGToQueue != nil

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
                            ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Return record will be saved with available photos.".localized, failedCount, totalCount))
                        }
                    }

                    if shouldQueuePhotos || shouldQueueSignature {
                        let imagesToQueue = shouldQueuePhotos ? allPhotosToUpload : []
                        OfflineMediaSyncCoordinator.shared.enqueueIadeMedia(
                            documentId: stableDocumentId,
                            images: imagesToQueue,
                            signaturePNG: shouldQueueSignature ? signaturePNGToQueue : nil
                        ) { ok in
                            guard ok else {
                                self.isUploading = false
                                self.operationFlowState = .failed
                                ErrorManager.shared.showError(message: "Could not save photos on this device for later upload.".localized)
                                return
                            }
                            self.runWheelSysSyncIfNeededThenSave(
                                status: status,
                                signatureURL: signatureURL,
                                sortedNewPhotos: [],
                                usedOfflineMediaQueue: true,
                                stableNewDocumentId: stableDocumentId
                            )
                        }
                        return
                    }

                    let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
                    self.runWheelSysSyncIfNeededThenSave(
                        status: status,
                        signatureURL: signatureURL,
                        sortedNewPhotos: sortedNewPhotos,
                        usedOfflineMediaQueue: false,
                        stableNewDocumentId: stableDocumentId
                    )
                }
            }
        }
    }
    
    @MainActor
    private func runWheelSysSyncIfNeededThenSave(
        status: IadeStatus,
        signatureURL: String?,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        let save = {
            self.applyIadeSaveAfterUploads(
                status: status,
                signatureURL: signatureURL,
                sortedNewPhotos: sortedNewPhotos,
                usedOfflineMediaQueue: usedOfflineMediaQueue,
                stableNewDocumentId: stableNewDocumentId
            )
        }

        guard status == .completed, wheelSysCHOpsEnabled, wheelSysReturnPrefill != nil else {
            save()
            return
        }

        Task { @MainActor in
            if !wheelsysPrecheckinSucceeded {
                completionProgress = max(completionProgress, 0.72)
                await loadWheelSysPrecheckinContextIfNeeded(force: true)
                let precheckOk = await submitWheelSysPrecheckin(silent: false)
                if !precheckOk {
                    isUploading = false
                    operationFlowState = .failed
                    HapticManager.shared.error()
                    return
                }
                await WheelSysVehicleFleetStatusStore.shared.refresh(force: true)
                NotificationCenter.default.post(name: .wheelSysFleetStatusDidRefresh, object: nil)
            }
            save()
        }
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
}

private struct ReturnVehicleItemsChecklistSheet: View {
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

// MARK: - Camera View (using shared CameraView from HasarEkleView)

// MARK: - Edit View for Existing Return

// MARK: - QR Code View (CoreImage, no external dependency)

struct QRCodeView: View {
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
struct ReturnQRSheet: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var urlString: String {
        CustomerFormWebLinks.returnFormURL(
            token: token,
            franchiseId: FirebaseService.shared.currentFranchiseId
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 16)

                    // Instruction
                    VStack(spacing: 8) {
                        Text("Customer Self-Fill".localized)
                            .font(.system(size: 22, weight: .bold))
                            .tracking(0.3)
                        Text("Ask the customer to scan this code\nto fill in their details.".localized)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 24)

                    // QR Code — fills available width
                    let qrSize = min(geo.size.width - 64, 320.0)
                    QRCodeView(url: urlString)
                        .frame(width: qrSize, height: qrSize)
                        .padding(20)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 20, x: 0, y: 8)

                    Spacer(minLength: 32)

                    // Share button
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

private extension String {
    var nilIfEmptyString: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
