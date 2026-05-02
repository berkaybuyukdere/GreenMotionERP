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
    /// Save name + email under this franchise for auto-fill on next visit (web / kiosk / iOS).
    @State private var rememberCustomerContact = true
    @State private var rememberLookupTask: Task<Void, Never>?

    // Photo preview state
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }

    private var currentFranchiseId: String { FirebaseService.shared.currentFranchiseId.uppercased() }
    private var isTurkeyFranchise: Bool {
        if currentFranchiseId.hasPrefix("TR") { return true }
        let userCountryCode = authManager.userProfile?.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return userCountryCode == "TR"
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
    private var isCustomerInfoReadOnlyFromOperation: Bool {
        trHandoverPrefill != nil
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
        )

        let withFieldChanges = alertConfigured
            .onChange(of: resKodu) { _, _ in hasUnsavedChanges = true }
            .onChange(of: exitTarihi) { _, _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _, _ in hasUnsavedChanges = true }
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
        return AnyView(
            withCustomerChanges
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .sheet(isPresented: $showVehicleItemsSheet) {
                VehicleItemsChecklistSheet(selections: $vehicleItemsChecklist)
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureCaptureView(signatureImage: $customerSignatureImage)
            }
            .sheet(isPresented: $showQRSheet) {
                CheckoutQRSheet(token: activeToken)
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
                    onDamageCompleted: { _ in showQuickDamageSheet = false },
                    externalDismiss: { showQuickDamageSheet = false }
                )
                .environmentObject(viewModel)
                .environmentObject(notificationManager)
                .environmentObject(authManager)
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
                pickUpBranch = existing.pickUpBranch ?? existing.bayiAdi ?? ""
                bayiAdi = ""
            } else {
                bayiAdi = existing.bayiAdi ?? ""
                pickUpBranch = existing.pickUpBranch ?? ""
            }
            dropOffBranch = existing.dropOffBranch ?? ""
            customerFirstName = existing.customerFirstName ?? ""
            customerLastName = existing.customerLastName ?? ""
            customerEmail = existing.customerEmail ?? ""
            testDriverFirstName = existing.testDriverFirstName ?? ""
            testDriverLastName = existing.testDriverLastName ?? ""
            vehicleItemsChecklist = existing.vehicleItemsChecklist ?? VehicleChecklistCatalog.defaultMap()
            existingPhotoURLs = existing.fotograflar
            localQRToken = existing.qrToken
            if let signatureURL = existing.customerSignatureURL {
                StorageImageLoader.shared.loadImage(from: signatureURL) { loadedImage in
                    if let loadedImage { self.customerSignatureImage = loadedImage }
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
                    pickUpBranch = p
                }
                if dropOffBranch.isEmpty, let d = pre.dropoffBranchName {
                    dropOffBranch = d
                }
                hasUnsavedChanges = true
            }
            if let pc = trHandoverPrefill?.plannedCheckin {
                plannedReturnPickerDate = pc
            } else {
                plannedReturnPickerDate = defaultPlannedReturn(around: exitTarihi)
            }
        }
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
                let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/exit_fotograflari/\(UUID().uuidString).jpg"
                pendingUploadTracker.startUploadIfNeeded(image: capturedImage, storagePath: path)
            }
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

                if isTurkeyFranchise {
                    DatePicker("operations.planned_return".localized, selection: $plannedReturnPickerDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                HStack {
                    Image(systemName: "number.square.fill")
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
                    TextField("operations.pickup_branch_optional".localized, text: $pickUpBranch)
                    TextField("operations.dropoff_branch_optional".localized, text: $dropOffBranch)
                    Button {
                        showVehicleItemsSheet = true
                    } label: {
                        HStack {
                            Label("Items with vehicle (Yes/No)".localized, systemImage: "checklist")
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
                Text("Customer Information & Signature".localized)
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
                Divider().padding(.leading, 12)
                customerTextField("Last Name".localized, text: $customerLastName)
                Divider().padding(.leading, 12)
                customerTextField("Email".localized, text: $customerEmail, email: true)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .cornerRadius(10)
            .disabled(isCustomerInfoReadOnlyFromOperation)

            Toggle(isOn: $rememberCustomerContact) {
                Text("Remember customer (name + email) for auto-fill next time".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .disabled(isCustomerInfoReadOnlyFromOperation)

            if isTurkeyFranchise {
                VStack(spacing: 0) {
                    TextField("operations.test_driver_first_name".localized, text: $testDriverFirstName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .textInputAutocapitalization(.words)
                    Divider().padding(.leading, 12)
                    TextField("operations.test_driver_last_name".localized, text: $testDriverLastName)
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
                .listRowBackground(Color.green.opacity(0.8))
                .foregroundColor(.white)
            } header: {
                Text("Finalize check out".localized)
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
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil
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
                testDriverFirstName: testDriverFirstStored,
                testDriverLastName: testDriverLastStored,
                customerSignatureURL: signatureURL,
                qrToken: localQRToken,
                status: status,
                createdBy: currentUserId,
                assistantCompanyName: arac.assistantCompanyName,
                assistantCompanyPhone: arac.assistantCompanyPhone,
                vehicleItemsChecklist: isTurkeyFranchise ? vehicleItemsChecklist : nil
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
           let pre = trHandoverPrefill,
           status == .completed || status == .parked {
            didPublishTrHandoverLifecycle = true
            FirebaseService.shared.updateFrontDeskCustomerHandoverLifecycle(
                documentId: pre.frontDeskDocumentId,
                iosPrefillStatus: "return_ready",
                linkedExitId: currentExit.id.uuidString,
                linkedIadeId: nil,
                completion: { _ in }
            )
        }

        isUploading = false
        hasUnsavedChanges = false

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

