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
    @State private var testDriverFirstName = ""
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

    // Photo preview state (one fullScreen session — avoids stacked covers / blank preview)
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    private var sectionHeaderFont: Font { .system(size: 12, weight: .semibold, design: .default) }
    private var isTurkeyFranchise: Bool {
        if FirebaseService.shared.currentFranchiseId.uppercased().hasPrefix("TR") { return true }
        let cc = authManager.userProfile?.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return cc == "TR"
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
            .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { _ in hasUnsavedChanges = true }
            .onChange(of: checklist) { _ in hasUnsavedChanges = true }
            .onChange(of: customerFirstName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerLastName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerEmail) { _, newVal in
                hasUnsavedChanges = true
                scheduleRememberAutofill(for: newVal)
            }
            .onChange(of: customerSignatureImage) { _ in hasUnsavedChanges = true }
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
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $capturedImage)
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
    
    private var returnIdentitySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RETURN".localized)
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
            testDriverFirstName = existing.testDriverFirstName ?? ""
            testDriverLastName = existing.testDriverLastName ?? ""
            kmText = existing.km.map(String.init) ?? ""
            yakitSeviyesi = normalizedFuelLevel(existing.yakitSeviyesi)
            pickUpBranch = canonicalTurkeyBranchKey(from: existing.pickUpBranch)
            dropOffBranch = canonicalTurkeyBranchKey(from: existing.dropOffBranch)
            vehicleItemsChecklist = existing.vehicleItemsChecklist ?? VehicleChecklistCatalog.defaultMap()
            existingPhotoURLs = existing.fotograflar
            loadExistingSignatureImage()
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
        // Start QR listener immediately — works even before first save
        startFormListener(token: activeToken)
    }
    
    private func handleCameraDismiss() {
        if let capturedImage = capturedImage {
            let key = pendingUploadTracker.photoKey(for: capturedImage)
            let duplicateExists = (fotograflar + cameraPhotos).contains {
                pendingUploadTracker.photoKey(for: $0) == key
            }
            if !duplicateExists {
                cameraPhotos.append(capturedImage)
                let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/iade_fotograflari/\(UUID().uuidString).jpg"
                pendingUploadTracker.startUploadIfNeeded(image: capturedImage, storagePath: path)
            }
            self.capturedImage = nil
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
                        .foregroundColor(.secondary)
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
            Text("Return Information".localized)
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
            Text("Return Checklist".localized)
                .font(sectionHeaderFont)
        } footer: {
            Text("Optional: You can complete return without selecting these items.".localized)
                .font(.caption)
        }
    }
    
    private var signatureAndContactSection: some View {
        Section {
            customerContactAndSignatureBlock
        } header: {
            Text("Customer Signature".localized)
        } footer: {
            Text("Name, email and signature are used in Return PDF and email delivery.".localized)
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
                Text("Customer Information & Signature".localized)
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
                .padding(.top, 10)
            }

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
                                            photoGallerySession = PhotoGalleryFullScreenSession(images: fotograflar + cameraPhotos, startIndex: index)
                                        }
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            pendingUploadTracker.markRemoved(image: fotograflar[index])
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
                                            photoGallerySession = PhotoGalleryFullScreenSession(images: fotograflar + cameraPhotos, startIndex: fotograflar.count + index)
                                        }
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            pendingUploadTracker.markRemoved(image: cameraPhotos[index])
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
            } header: {
                Text("Finalize return".localized)
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
                qrToken: base.qrToken
            )
            updatedIade.id = base.id
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
                qrToken: self.localQRToken
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

        if status == .completed {
            isSaved = true
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos and signature will upload when you are back online.".localized, type: .success)
            }
            // Online: in-app banner from sendReturnNotification
            print("✅ Return completed - dismissing view")
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
            HStack {
                Text(title)
                Spacer()
                Text(selectedTitle)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
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
