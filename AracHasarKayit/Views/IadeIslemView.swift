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
    @State private var customerFirstName = ""
    @State private var customerLastName = ""
    @State private var customerEmail = ""
    @State private var customerSignatureImage: UIImage?
    @State private var showSignatureSheet = false
    @State private var signatureWasRemoved = false
    /// After first save in this session, further saves update this return (avoids duplicate returns on In Progress re-saves).
    @State private var committedIade: IadeIslemi?
    @State private var formListener: ListenerRegistration?
    @State private var showQRSheet = false
    /// Stable token for this return session — used even before first save
    @State private var localQRToken: String = UUID().uuidString

    // Photo preview state
    @State private var urlPreviewURLs: [String] = []
    @State private var urlPreviewIndex: Int = 0
    @State private var showURLPreview = false
    @State private var localPreviewImages: [UIImage] = []
    @State private var localPreviewIndex: Int = 0
    @State private var showLocalPreview = false
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var toastManager = ToastManager.shared
    
    private var allPhotos: [UIImage] {
        fotograflar + cameraPhotos
    }
    
    private var sectionHeaderFont: Font { .system(size: 12, weight: .semibold, design: .default) }
    
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
            .navigationTitle("Return Process".localized)
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
            .onChange(of: iadeTarihi) { _ in hasUnsavedChanges = true }
            .onChange(of: fotograflar) { _ in hasUnsavedChanges = true }
            .onChange(of: cameraPhotos) { _ in hasUnsavedChanges = true }
            .onChange(of: existingPhotoURLs) { _ in hasUnsavedChanges = true }
            .onChange(of: checklist) { _ in hasUnsavedChanges = true }
            .onChange(of: customerFirstName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerLastName) { _ in hasUnsavedChanges = true }
            .onChange(of: customerEmail) { _ in hasUnsavedChanges = true }
            .onChange(of: customerSignatureImage) { _ in hasUnsavedChanges = true }
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
                formListener?.remove()
                formListener = nil
            }
            .sheet(isPresented: $showQRSheet) {
                ReturnQRSheet(token: activeToken)
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
            .fullScreenCover(isPresented: $showURLPreview) {
                NativePhotoGalleryView(urlStrings: urlPreviewURLs, initialIndex: urlPreviewIndex)
            }
            .fullScreenCover(isPresented: $showLocalPreview) {
                NativePhotoGalleryView(images: localPreviewImages, initialIndex: localPreviewIndex)
            }
    }
    
    private var mainForm: some View {
        ScrollViewReader { proxy in
            Form {
                Color.clear
                    .frame(height: 1)
                    .id("formTop")
                returnIdentitySection
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
                    Text("RETURN")
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
        if let existing = existingIade {
            iadeTarihi = existing.iadeTarihi
            notlar = existing.notlar
            checklist = existing.checklist ?? ReturnChecklist()
            customerFirstName = existing.customerFirstName ?? ""
            customerLastName = existing.customerLastName ?? ""
            customerEmail = existing.customerEmail ?? ""
            existingPhotoURLs = existing.fotograflar
            loadExistingSignatureImage()
        }
        // Start QR listener immediately — works even before first save
        startFormListener(token: activeToken)
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
        } header: {
            Text("Return Information".localized)
        } footer: {
            Text("Complete vehicle check-in (km and fuel) before return photos.".localized)
                .font(.caption)
        }
    }
    
    // MARK: - QR Self-Fill Section

    private var activeToken: String {
        committedIade?.qrToken ?? existingIade?.qrToken ?? localQRToken
    }

    private var qrSelfFillSection: some View {
        let token = activeToken
        let url = "https://greenmotionapp-33413.web.app/return.html?token=\(token)"
        return Section {
            VStack(alignment: .center, spacing: 14) {
                HStack {
                    Text("Scan to fill your details".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        guard let shareURL = URL(string: url) else { return }
                        let av = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(av, animated: true)
                        }
                    } label: {
                        Label("Share QR Link".localized, systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.teal)
                }
                HStack {
                    Spacer()
                    QRCodeView(url: url)
                        .frame(width: 180, height: 180)
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    Spacer()
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Customer Self-Fill".localized)
        }
    }

    private func startFormListener(token: String) {
        formListener?.remove()
        formListener = Firestore.firestore()
            .collection("returnFormData")
            .document(token)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                DispatchQueue.main.async {
                    if let v = data["firstName"] as? String, !v.isEmpty { customerFirstName = v }
                    if let v = data["lastName"]  as? String, !v.isEmpty { customerLastName  = v }
                    if let v = data["email"]     as? String, !v.isEmpty { customerEmail     = v }
                    if let b64 = data["signatureBase64"] as? String,
                       let imgData = Data(base64Encoded: b64),
                       let img = UIImage(data: imgData) {
                        customerSignatureImage = img
                    }
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
            TextField("First Name".localized, text: $customerFirstName)
            TextField("Last Name".localized, text: $customerLastName)
            TextField("Email".localized, text: $customerEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            
            Button {
                showSignatureSheet = true
            } label: {
                HStack {
                    Image(systemName: "signature")
                    Text(customerSignatureImage == nil ? "Add Signature".localized : "Update Signature".localized)
                    Spacer()
                    if customerSignatureImage != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if let signature = customerSignatureImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: signature)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                        )
                    
                    Button {
                        customerSignatureImage = nil
                        signatureWasRemoved = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .background(Color.white.clipShape(Circle()))
                    }
                    .padding(6)
                }
            }
        } header: {
            Text("Customer Signature".localized)
        } footer: {
            Text("Name, email and signature are used in Return PDF and email delivery.".localized)
                .font(.caption)
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
                                            urlPreviewIndex = index
                                            showURLPreview = true
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
                                            localPreviewIndex = index
                                            showLocalPreview = true
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
                                            localPreviewIndex = fotograflar.count + index
                                            showLocalPreview = true
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
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
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

        let path = "iade_signatures/\(UUID().uuidString).png"
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

    private func applyIadeSaveAfterUploads(
        status: IadeStatus,
        signatureURL: String?,
        sortedNewPhotos: [String],
        usedOfflineMediaQueue: Bool,
        stableNewDocumentId: UUID
    ) {
        var finalPhotoURLs: [String] = []
        let editingExistingSession = self.committedIade != nil || self.existingIade != nil
        if editingExistingSession {
            finalPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
        } else {
            finalPhotoURLs = sortedNewPhotos
        }

        let currentIade: IadeIslemi
        let baseForUpdate = self.committedIade ?? self.existingIade

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
                customerSignatureURL: signatureURL,
                returnEmailSentAt: base.returnEmailSentAt,
                returnEmailLastStatus: base.returnEmailLastStatus,
                returnEmailRecipient: base.returnEmailRecipient,
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
                customerSignatureURL: signatureURL,
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

        let userName = authManager.userProfile?.fullName ?? "Unknown User"
        notificationManager.sendReturnNotification(
            carPlate: arac.plakaFormatli,
            userName: userName
        )

        isUploading = false
        hasUnsavedChanges = false

        if status == .completed {
            isSaved = true
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Photos and signature will upload when you are back online.".localized, type: .success)
            } else {
                ToastManager.shared.show("✓ Return Completed".localized, type: .success)
            }
            print("✅ Return completed - dismissing view")
            operationFlowState = .completed
            finalizeCompletedFlow(with: currentIade)
        } else {
            isSaved = false
            if usedOfflineMediaQueue {
                ToastManager.shared.show("Saved on this device. Remaining media will upload when you are back online.".localized, type: .success)
            } else {
                ToastManager.shared.show("✓ Return Saved (In Progress)".localized, type: .success)
            }
            operationFlowState = .draft
        }
    }
    
    private func finalizeCompletedFlow(with iade: IadeIslemi) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            completionPhase = .completed
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
                    group.enter()
                    let path = "iade_fotograflari/\(UUID().uuidString).jpg"
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
        "https://greenmotionapp-33413.web.app/return.html?token=\(token)"
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
