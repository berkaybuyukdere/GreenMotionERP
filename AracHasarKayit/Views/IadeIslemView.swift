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
    private var isSwitzerlandFranchise: Bool {
        FranchiseCapabilityMatrix.isSwitzerlandFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: UserDefaults.standard.selectedCountry.countryCode
        )
    }
    private var isCustomerInfoReadOnlyFromOperation: Bool {
        trReturnHandoverPrefill != nil
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

        let withChanges = alertConfigured
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
            .onAppear(perform: handleAppear)
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
                iadeBilgileriSection
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
                        Text(iadeTarihi.formatted(date: .abbreviated, time: .shortened))
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
                
                DatePicker("Return Date".localized, selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
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

    private var checklistSection: some View {
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
                        .disabled(isCustomerInfoReadOnlyFromOperation)
                    }
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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                if completionPhase == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                    Text("Return Completed".localized)
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
                    Text("Completing Return...".localized)
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
                            self.completionProgress = min(0.95, 0.1 + (Double(indexedPhotoURLs.count) / Double(totalCount)) * 0.8)
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
                            self.applyIadeSaveAfterUploads(
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
                    self.applyIadeSaveAfterUploads(
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
        let franchiseId = FirebaseService.shared.currentFranchiseId
        return "https://greenmotionapp-33413.web.app/return.html?token=\(token)&franchise=\(franchiseId)"
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
