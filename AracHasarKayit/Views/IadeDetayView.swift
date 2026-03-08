import SwiftUI
import Kingfisher
import FirebaseFirestore
import UserNotifications
import AudioToolbox

struct IadeDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let iade: IadeIslemi
    @State private var silmeOnayiGoster = false
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var fotografGoster = false
    @State private var seciliFotografIndex: Int = 0
    @State private var showEditSheet = false
    @State private var isSendingEmail = false
    @State private var emailProgress: Double = 0
    @State private var emailProgressMessage = "Preparing PDF...".localized
    @Environment(\.dismiss) var dismiss
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == iade.aracId })
    }
    
    var liveIade: IadeIslemi {
        viewModel.iadeIslemleri.first(where: { $0.id == iade.id }) ?? iade
    }
    
    var body: some View {
        ZStack {
            List {
                headerSection
                aracBilgileriSection
                returnContextSection
                
                if !liveIade.notlar.isEmpty {
                    notlarSection
                }
                
                if !liveIade.fotograflar.isEmpty {
                    fotograflarSection
                }
                
                silmeSection
            }
            .blur(radius: fotografGoster ? 10 : 0)
            .allowsHitTesting(!fotografGoster)
            
            if fotografGoster && !liveIade.fotograflar.isEmpty {
                ZStack {
                    PhotoGalleryView(
                        photoURLs: liveIade.fotograflar,
                        initialIndex: seciliFotografIndex,
                        style: .floatingTransparent,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                fotografGoster = false
                            }
                        },
                        headerTitle: liveIade.aracPlaka,
                        headerSubtitle: arac.map { "\($0.marka) \($0.model)" } ?? ""
                    )
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .navigationTitle("Return Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(fotografGoster ? .hidden : .visible, for: .navigationBar)
        .toolbar(fotografGoster ? .hidden : .visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = arac {
                SheetWrapper {
                    NavigationView {
                        IadeIslemView(
                            arac: arac,
                            existingIade: liveIade, // Pass existing iade for editing
                            onIadeCompleted: { updatedIade in
                                // Update is handled by viewModel
                                // Just dismiss the sheet
                            }
                        )
                    }
                }
            }
        }
        .alert("Delete Return Record".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.iadeSil(liveIade)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this return record?".localized)
        }
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                if liveIade.status == .inProgress {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Return Saved (In Progress)".localized)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Return Completed".localized)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    private var aracBilgileriSection: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Label("Plate".localized, systemImage: "number.square.fill")
                    .foregroundColor(.secondary)
                Spacer()
                Text(liveIade.aracPlaka)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Label("Return Date".localized, systemImage: "calendar")
                    .foregroundColor(.secondary)
                Spacer()
                Text(liveIade.iadeTarihi.formatted(date: .long, time: .shortened))
                    .fontWeight(.semibold)
            }
        }
    }

    private var returnContextSection: some View {
        Section("Customer & Return Context".localized) {
            detailRow(
                title: "Customer".localized,
                value: liveIade.customerFullName.isEmpty ? "Not provided".localized : liveIade.customerFullName
            )

            detailRow(
                title: "Email".localized,
                value: (liveIade.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? (liveIade.customerEmail ?? "")
                    : "Not provided".localized
            )

            detailRow(
                title: "Signature".localized,
                value: (liveIade.customerSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? "Added".localized
                    : "Not added".localized
            )

            if let checklist = liveIade.checklist {
                Divider()
                toggleStateRow("Customer was present".localized, isOn: checklist.customerPresent)
                toggleStateRow("Customer had no time".localized, isOn: checklist.customerNoTime)
                toggleStateRow("Key was taken from keybox".localized, isOn: checklist.keyFromKeybox)
                toggleStateRow("Customer refused to sign".localized, isOn: checklist.customerRefusedSignature)
                toggleStateRow("Customer left key at office".localized, isOn: checklist.customerLeftKeyAtOffice)
            } else {
                detailRow(title: "Return Checklist".localized, value: "No selection".localized)
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func toggleStateRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(isOn ? "On".localized : "Off".localized)
                .fontWeight(.semibold)
                .foregroundColor(isOn ? .green : .secondary)
        }
    }
    
    private var notlarSection: some View {
        Section("Notes".localized) {
            Text(liveIade.notlar)
                .font(.body)
        }
    }
    
    private var fotograflarSection: some View {
        Section(String(format: "Photos (%d)".localized, liveIade.fotograflar.count)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(liveIade.fotograflar.enumerated()), id: \.offset) { index, urlString in
                        IadeFotoButton(
                            urlString: urlString,
                            index: index,
                            onTap: {
                                seciliFotografIndex = index
                                fotografGoster = true
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Show edit button for in-progress returns, PDF button for completed
            if liveIade.status == .inProgress {
                editButton
            } else {
                pdfButton
                emailButton
                if isSendingEmail || emailProgress > 0 {
                    emailProgressView
                }
            }
        }
    }
    
    private var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack {
                Image(systemName: "pencil.circle.fill")
                Text("Edit Return".localized)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(Color.orange)
            .cornerRadius(12)
        }
    }
    
    private var pdfButton: some View {
        Button {
            guard !isSendingEmail else { return }
            generatePDF()
        } label: {
            HStack {
                if pdfOlusturuluyor {
                    ProgressView()
                        .tint(.white)
                    Text("PDF generating...".localized)
                } else {
                    Image(systemName: "doc.fill")
                    Text("Generate Return PDF".localized)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.borderless)
        .disabled(pdfOlusturuluyor || isSendingEmail)
    }
    
    private var emailButton: some View {
        Button {
            guard !pdfOlusturuluyor else { return }
            sendReturnEmail()
        } label: {
            HStack {
                Image(systemName: "paperplane.fill")
                Text(isSendingEmail ? "Sending Email...".localized : "Send Return Email".localized)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(isSendingEmail ? Color.gray : Color.green)
            .cornerRadius(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.borderless)
        .disabled(isSendingEmail || pdfOlusturuluyor)
    }
    
    private var emailProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emailProgressMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(emailProgress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.green)
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.green.opacity(0.15))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.7), Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * emailProgress), height: 10)
                        .animation(.easeInOut(duration: 0.25), value: emailProgress)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    private var silmeSection: some View {
        Section {
            Button(role: .destructive) {
                silmeOnayiGoster = true
            } label: {
                Label("Delete Return Record".localized, systemImage: "trash.fill")
            }
        }
    }
    
    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        
        IadePDFGenerator.shared.generateIadePDF(
            iade: liveIade,
            arac: arac
        ) { url in
            DispatchQueue.main.async {
                pdfOlusturuluyor = false
                if let url = url {
                    pdfURL = url
                    pdfPaylas = true
                }
            }
        }
    }
    
    private func sendReturnEmail() {
        guard let arac = arac else { return }
        
        let recipient = (liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            ToastManager.shared.show("Customer email is required.".localized, type: .error)
            return
        }
        guard isValidEmail(recipient) else {
            ToastManager.shared.show("Please enter a valid customer email.".localized, type: .error)
            return
        }
        
        isSendingEmail = true
        emailProgress = 0.08
        emailProgressMessage = "Preparing PDF...".localized
        
        IadePDFGenerator.shared.generateIadePDF(iade: liveIade, arac: arac) { localURL in
            guard
                let localURL,
                let data = try? Data(contentsOf: localURL)
            else {
                finishEmailFlow(success: false, message: "PDF generation failed.".localized)
                return
            }
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    emailProgress = 0.35
                    emailProgressMessage = "Uploading PDF...".localized
                }
            }
            
            let pdfPath = "return_pdfs/\(liveIade.id.uuidString).pdf"
            uploadReturnPDFWithRetry(data: data, path: pdfPath) { uploadedPDFURL in
                guard let uploadedPDFURL else {
                    finishEmailFlow(success: false, message: "PDF upload failed.".localized)
                    return
                }
                
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        emailProgress = 0.68
                        emailProgressMessage = "Queueing email...".localized
                    }
                }
                
                let fullName = liveIade.customerFullName
                FirebaseService.shared.queueReturnEmail(
                    to: recipient,
                    subject: "Return Confirmation - \(liveIade.aracPlaka)",
                    body: IadePDFGenerator.returnConfirmationText,
                    pdfURL: uploadedPDFURL,
                    returnId: liveIade.id.uuidString,
                    vehiclePlate: liveIade.aracPlaka,
                    signerName: fullName,
                    signerEmail: recipient,
                    forceResend: true
                ) { error, queuedPaths in
                    if let error {
                        print("❌ Queue return email error: \(error.localizedDescription)")
                        finishEmailFlow(success: false, message: "Email queue failed.".localized)
                        return
                    }
                    
                    guard let documentPath = queuedPaths.first else {
                        finishEmailFlow(success: false, message: "Email queue path missing.".localized)
                        return
                    }
                    
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            emailProgress = 0.8
                            emailProgressMessage = "Sending email...".localized
                        }
                    }
                    
                    observeQueuedEmailStatus(documentPath: documentPath) { status in
                        switch status {
                        case "sent", "duplicate_skipped":
                            finishEmailFlow(success: true, message: "Email delivered.".localized)
                        case "failed":
                            finishEmailFlow(success: false, message: "Email sending failed.".localized)
                        default:
                            finishEmailFlow(success: false, message: "Email is still processing in background.".localized)
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
        maxAttempts: Int = 4,
        completion: @escaping (String?) -> Void
    ) {
        FirebaseService.shared.uploadData(data, path: path, contentType: "application/pdf") { uploadedURL, error in
            if let uploadedURL, !uploadedURL.isEmpty {
                completion(uploadedURL)
                return
            }
            
            if let error {
                print("⚠️ [ReturnEmailDebug] detail PDF upload attempt \(attempt) failed: \(error.localizedDescription)")
            }
            
            guard attempt < maxAttempts else {
                completion(nil)
                return
            }
            
            let delay = pow(2.0, Double(attempt - 1))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                uploadReturnPDFWithRetry(
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
        timeout: TimeInterval = 45,
        completion: @escaping (String) -> Void
    ) {
        let ref = Firestore.firestore().document(documentPath)
        var registration: ListenerRegistration?
        var didComplete = false
        
        func finish(_ status: String) {
            guard !didComplete else { return }
            didComplete = true
            registration?.remove()
            registration = nil
            completion(status)
        }
        
        registration = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ [ReturnEmailDebug] detail listener error: \(error.localizedDescription)")
                finish("listener_error")
                return
            }
            
            guard let data = snapshot?.data() else { return }
            let status = String(describing: data["status"] ?? "unknown")
            if status == "sent" || status == "failed" || status == "duplicate_skipped" {
                finish(status)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish("timeout")
        }
    }
    
    private func finishEmailFlow(success: Bool, message: String) {
        DispatchQueue.main.async {
            if success {
                withAnimation(.easeInOut(duration: 0.25)) {
                    emailProgress = 1
                    emailProgressMessage = "Completed".localized
                }
                HapticManager.shared.success()
                AudioServicesPlaySystemSound(1005)
                showMailSentNotification()
                ToastManager.shared.show("✓ \(message)", type: .success)
            } else {
                HapticManager.shared.error()
                ToastManager.shared.show(message, type: .error)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.2 : 0.6)) {
                isSendingEmail = false
                if success {
                    emailProgress = 0
                    emailProgressMessage = "Preparing PDF...".localized
                }
            }
        }
    }
    
    private func showMailSentNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Email Sent".localized
        content.body = "Return email was delivered successfully.".localized
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "return-email-sent-\(liveIade.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let regex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }
}

struct IadeFotoButton: View {
    let urlString: String
    let index: Int
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .clipped()
                } else if isLoading {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                        
                        ProgressView()
                    }
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                        
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
                }
                
                Text(String(format: "Foto %d".localized, index + 1))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    func loadImage() {
        StorageImageLoader.shared.loadImage(from: urlString) { loadedImage in
            if loadedImage == nil {
                print("❌ Failed to load image from all candidates")
            }
            self.image = loadedImage
            self.isLoading = false
        }
    }
}
