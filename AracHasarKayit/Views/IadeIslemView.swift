import SwiftUI
import Kingfisher
import FirebaseFirestore

struct IadeIslemView: View {
    private enum ReturnCompletionPhase {
        case processingReturn
        case sendingEmail
        case emailSent
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
    @State private var pulseAnimation = false
    @State private var customerFirstName = ""
    @State private var customerLastName = ""
    @State private var customerEmail = ""
    @State private var customerSignatureImage: UIImage?
    @State private var showSignatureSheet = false
    @State private var signatureWasRemoved = false
    
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
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $fotograflar)
            }
            .sheet(isPresented: $showSignatureSheet) {
                SignatureCaptureView(signatureImage: $customerSignatureImage)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraView(capturedImage: $capturedImage)
            }
    }
    
    private var mainForm: some View {
        Form {
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
        Section("Return Information".localized) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("Vehicle".localized)
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("Return Date".localized, selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
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
                } else if completionPhase == .emailSent {
                    Image(systemName: "envelope.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                    Text("Email Delivered".localized)
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                    Text(completionPhase == .sendingEmail ? "Sending Email...".localized : "Completing Return...".localized)
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
    
    private func isValidEmail(_ email: String) -> Bool {
        let regex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }
    
    private func uploadSignatureIfNeeded(completion: @escaping (String?) -> Void) {
        if signatureWasRemoved && customerSignatureImage == nil {
            completion(nil)
            return
        }
        
        guard let signatureImage = customerSignatureImage, let pngData = signatureImage.pngData() else {
            completion(existingIade?.customerSignatureURL)
            return
        }
        
        let path = "iade_signatures/\(UUID().uuidString).png"
        FirebaseService.shared.uploadData(pngData, path: path, contentType: "image/png") { url, error in
            if let error = error {
                print("❌ Signature upload error: \(error.localizedDescription)")
            }
            self.signatureWasRemoved = false
            completion(url ?? self.existingIade?.customerSignatureURL)
        }
    }
    
    private func processCompletionAndEmail(for iade: IadeIslemi) {
        let recipient = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📧 [ReturnEmailDebug] process start returnId=\(iade.id.uuidString)")
        guard !recipient.isEmpty else {
            print("ℹ️ Customer email empty, skipping return email.")
            finalizeCompletedFlow(with: iade)
            return
        }
        guard isValidEmail(recipient) else {
            print("ℹ️ Customer email invalid, skipping return email.")
            finalizeCompletedFlow(with: iade)
            return
        }
        
        completionPhase = .sendingEmail
        
        IadePDFGenerator.shared.generateIadePDF(iade: iade, arac: arac, signatureImageOverride: customerSignatureImage) { localURL in
            guard
                let localURL = localURL,
                let data = try? Data(contentsOf: localURL)
            else {
                print("❌ [ReturnEmailDebug] PDF generation failed, skipping email")
                self.finalizeCompletedFlow(with: iade)
                return
            }
            
            let pdfPath = "return_pdfs/\(iade.id.uuidString).pdf"
            self.uploadReturnPDFWithRetry(data: data, path: pdfPath) { uploadedPDFURL in
                guard let uploadedPDFURL else {
                    print("❌ [ReturnEmailDebug] PDF upload failed after retries, skipping queue")
                    ToastManager.shared.show("Email could not be sent because PDF upload failed.".localized, type: .error)
                    self.finalizeCompletedFlow(with: iade)
                    return
                }
                
                print("📄 [ReturnEmailDebug] PDF uploaded path=\(pdfPath), urlExists=true")
                let fullName = "\(self.customerFirstName) \(self.customerLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = "Return Confirmation - \(iade.aracPlaka)"
                let body = IadePDFGenerator.returnConfirmationText
                let shouldForceResend =
                    self.existingIade?.status == .completed
                if shouldForceResend {
                    print("🔁 [ReturnEmailDebug] manual resend mode active for existing completed return")
                }
                
                FirebaseService.shared.queueReturnEmail(
                    to: recipient,
                    subject: subject,
                    body: body,
                    pdfURL: uploadedPDFURL,
                    returnId: iade.id.uuidString,
                    vehiclePlate: iade.aracPlaka,
                    signerName: fullName,
                    signerEmail: recipient,
                    forceResend: shouldForceResend
                ) { error, queuedPaths in
                    if let error = error {
                        print("❌ Queue return email error: \(error.localizedDescription)")
                        ToastManager.shared.show("Email queue failed.".localized, type: .error)
                        self.finalizeCompletedFlow(with: iade)
                    } else {
                        print("✅ Return email queued for \(recipient)")
                        if queuedPaths.isEmpty {
                            print("⚠️ [ReturnEmailDebug] no queued path captured")
                            self.finalizeCompletedFlow(with: iade)
                            return
                        }
                        
                        let primaryPath = queuedPaths[0]
                        print("📨 [ReturnEmailDebug] queued docs: \(queuedPaths.joined(separator: ", "))")
                        self.observeQueuedEmailStatus(documentPath: primaryPath) { finalStatus in
                            switch finalStatus {
                            case "sent", "duplicate_skipped":
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    self.completionPhase = .emailSent
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                                    self.finalizeCompletedFlow(with: iade)
                                }
                            case "failed":
                                ToastManager.shared.show("Email sending failed.".localized, type: .error)
                                self.finalizeCompletedFlow(with: iade)
                            default:
                                // Timeout/unknown status: close flow, email may still process.
                                ToastManager.shared.show("Email is still processing in background.".localized, type: .warning)
                                self.finalizeCompletedFlow(with: iade)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func uploadReturnPDFWithRetry(
        data: Data,
        path: String,
        attempt: Int = 1,
        maxAttempts: Int = 3,
        completion: @escaping (String?) -> Void
    ) {
        FirebaseService.shared.uploadData(data, path: path, contentType: "application/pdf") { uploadedURL, error in
            if let uploadedURL, !uploadedURL.isEmpty {
                completion(uploadedURL)
                return
            }
            
            if let error {
                print("⚠️ [ReturnEmailDebug] PDF upload attempt \(attempt) failed: \(error.localizedDescription)")
            } else {
                print("⚠️ [ReturnEmailDebug] PDF upload attempt \(attempt) returned empty URL")
            }
            
            guard attempt < maxAttempts else {
                completion(nil)
                return
            }
            
            let delay = pow(2.0, Double(attempt - 1))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.uploadReturnPDFWithRetry(
                    data: data,
                    path: path,
                    attempt: attempt + 1,
                    maxAttempts: maxAttempts,
                    completion: completion
                )
            }
        }
    }
    
    private func observeQueuedEmailStatus(
        documentPath: String,
        timeout: TimeInterval = 40,
        completion: @escaping (String) -> Void
    ) {
        let ref = Firestore.firestore().document(documentPath)
        var registration: ListenerRegistration?
        var didComplete = false
        
        func finish(with status: String) {
            guard !didComplete else { return }
            didComplete = true
            registration?.remove()
            registration = nil
            completion(status)
        }
        
        registration = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ [ReturnEmailDebug] queue status listener error: \(error.localizedDescription)")
                finish(with: "listener_error")
                return
            }
            
            guard let data = snapshot?.data() else {
                return
            }
            
            let status = String(describing: data["status"] ?? "unknown")
            print("📨 [ReturnEmailDebug] observed queue status=\(status) path=\(documentPath)")
            if status == "sent" || status == "failed" || status == "duplicate_skipped" {
                finish(with: status)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(with: "timeout")
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
        isUploading = true
        uploadedPhotoURLs = []
        
        uploadSignatureIfNeeded { signatureURL in
            // Combine all photos: gallery photos first, then camera photos (maintain order)
            let allPhotosToUpload = self.fotograflar + self.cameraPhotos
            
            // Upload photos with index to maintain order
            var indexedPhotoURLs: [(index: Int, url: String)] = []
            var uploadErrors: [Error] = []
            let group = DispatchGroup()
            let lock = NSLock() // Thread-safe array updates
            
            // Upload all photos preserving their order
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
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                    return
                } else {
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Return record will be saved with available photos.".localized, failedCount, totalCount))
                }
            }
            
            // Sort uploaded photos by index (maintains insertion order)
            let sortedNewPhotos = indexedPhotoURLs.sorted(by: { $0.index < $1.index }).map { $0.url }
            
            // Combine existing photos (if editing) with new photos in order
            var finalPhotoURLs: [String] = []
            if self.existingIade != nil {
                // Edit mode: Keep remaining existing photos, add new photos
                finalPhotoURLs = self.existingPhotoURLs + sortedNewPhotos
            } else {
                // New iade: All new photos in order
                finalPhotoURLs = sortedNewPhotos
            }
            
            let currentIade: IadeIslemi
            
            if let existingIade = self.existingIade {
                // Update existing iade - createdAt'i koru (gerçek işlem tarihi değişmez)
                var updatedIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: finalPhotoURLs,
                    notlar: notlar,
                    status: status,
                    createdAt: existingIade.createdAt, // Mevcut createdAt'i koru
                    checklist: self.checklist.hasAnySelection ? self.checklist : nil,
                    customerFirstName: self.customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    customerLastName: self.customerLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    customerEmail: self.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    customerSignatureURL: signatureURL
                )
                updatedIade.id = existingIade.id
                currentIade = updatedIade
                
                // Save to Firebase
                viewModel.iadeGuncelle(updatedIade)
                
                print("✅ İade güncellendi - Status: \(status.rawValue), ID: \(updatedIade.id)")
            } else {
                // Create new iade
                let currentUserId = authManager.currentUser?.uid
                let yeniIade = IadeIslemi(
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
                    customerSignatureURL: signatureURL
                )
                currentIade = yeniIade
                
                // Save to Firebase
                viewModel.iadeEkle(yeniIade)
                
                print("✅ Yeni iade eklendi - Status: \(status.rawValue), ID: \(yeniIade.id)")
            }
            
            // 🔔 Send notification for return processed
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendReturnNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
            
            isUploading = false
            hasUnsavedChanges = false
            
            // Show success toast with checkmark icon
            if status == .completed {
                isSaved = true
                ToastManager.shared.show("✓ Return Completed".localized, type: .success)
                print("✅ Return completed - dismissing view")
                processCompletionAndEmail(for: currentIade)
            } else {
                // For in-progress saves, keep isSaved = false so user can continue editing
                isSaved = false
                ToastManager.shared.show("✓ Return Saved (In Progress)".localized, type: .success)
                // Don't call completion callback for save, just let user continue editing
                // Keep photos for further editing - don't clear them
            }
        }
    }
}

}

// MARK: - Camera View (using shared CameraView from HasarEkleView)

// MARK: - Edit View for Existing Return
