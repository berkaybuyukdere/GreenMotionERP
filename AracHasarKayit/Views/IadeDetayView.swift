import SwiftUI
import Kingfisher
import FirebaseFirestore
import AudioToolbox

struct IadeDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    let iade: IadeIslemi
    @State private var silmeOnayiGoster = false
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var photoGalleryItem: PhotoGallerySheetItem?
    @State private var showEditSheet = false
    @State private var isSendingEmail = false
    @State private var emailProgress: Double = 0
    @State private var emailProgressMessage = "Preparing PDF...".localized
    @State private var showCustomerSheet = false
    @State private var showReturnQRSheet = false
    @Environment(\.dismiss) var dismiss

    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == iade.aracId })
    }

    var liveIade: IadeIslemi {
        viewModel.iadeIslemleri.first(where: { $0.id == iade.id }) ?? iade
    }

    private var hasEmailBeenSentBefore: Bool {
        liveIade.returnEmailSentAt != nil ||
        liveIade.returnEmailLastStatus == "sent" ||
        viewModel.hasEmailSentRecord(for: liveIade.id.uuidString)
    }

    private var pdfFileName: String {
        let plate = liveIade.aracPlaka.replacingOccurrences(of: " ", with: "")
        return "RETURN-\(plate)"
    }

    private var isTurkeyFranchise: Bool {
        String(liveIade.franchiseId).uppercased().hasPrefix("TR")
    }

    /// İade kaydında saklı NAV veya bağlı çıkıştan türetilmiş gösterim (PDF kontrat alanı).
    private func resolvedTurkeyNavContractDisplay() -> String? {
        guard isTurkeyFranchise else { return nil }
        if let stored = liveIade.navKodu?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return Self.normalizedNavDisplay(fromRaw: stored)
        }
        guard let lid = liveIade.linkedExitId,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return nil }
        let raw = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.normalizedNavDisplay(fromRaw: raw)
    }

    private static func normalizedNavDisplay(fromRaw raw: String) -> String? {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while code.uppercased().hasPrefix("NAV-") || code.uppercased().hasPrefix("RES-") || code.uppercased().hasPrefix("RNT-") {
            code = String(code.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if code.isEmpty { return nil }
        return "NAV-\(code)"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                vehicleInfoCard
                customerProfileCard

                if !liveIade.notlar.isEmpty {
                    notesCard
                }
                if !liveIade.fotograflar.isEmpty {
                    photosSection
                }

                // Action buttons
                if liveIade.status == .inProgress {
                    editButton
                } else {
                    pdfButton
                    emailButton
                    if hasEmailBeenSentBefore {
                        emailAlreadySentInfoView
                    }
                    if isSendingEmail || emailProgress > 0 {
                        emailProgressView
                    }
                }

                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Return Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if liveIade.status == .inProgress {
                        Button {
                            HapticManager.shared.light()
                            showReturnQRSheet = true
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.teal)
                        }
                        .accessibilityLabel("Customer Self-Fill".localized)
                    }
                    Button {
                        HapticManager.shared.light()
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
        .fullScreenCover(item: $photoGalleryItem) { item in
            NativePhotoGalleryView(urlStrings: liveIade.fotograflar, initialIndex: item.startIndex)
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL { ActivityViewController(activityItems: [url]) }
        }
        .sheet(isPresented: $showReturnQRSheet) {
            ReturnQRSheet(token: liveIade.qrToken)
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = arac {
                SheetWrapper {
                    NavigationView {
                        IadeIslemView(arac: arac, existingIade: liveIade, onIadeCompleted: { _ in })
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomerSheet) {
            CustomerContextSheet(iade: liveIade)
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

    // MARK: - Status Card

    private var statusCard: some View {
        let isCompleted = liveIade.status == .completed
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: isCompleted ? "checkmark.shield.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(liveIade.aracPlaka)
                    .font(.system(size: 17, weight: .bold))
                Text("Return Details".localized)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(isCompleted ? "Completed".localized : "In Progress".localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isCompleted ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((isCompleted ? Color.green : Color.orange).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Vehicle Info Card

    private var vehicleInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("VEHICLE INFORMATION".localized)
            VStack(spacing: 0) {
                infoRow(icon: "number.square.fill", color: .blue,   label: "Plate".localized,      value: liveIade.aracPlaka)
                Divider().padding(.leading, 50)
                infoRow(icon: "calendar",           color: .orange, label: "Return Date".localized, value: liveIade.iadeTarihi.formatted(date: .long, time: .shortened))
                if let km = liveIade.km {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "gauge.medium", color: .green, label: "KM".localized, value: "\(km) km")
                }
                if let y = liveIade.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "fuelpump.fill", color: .orange, label: "Fuel level".localized, value: y)
                }
                if let pu = liveIade.pickUpBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "arrow.up.circle.fill", color: .teal, label: "operations.pickup_branch".localized, value: pu)
                }
                if let pd = liveIade.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "arrow.down.circle.fill", color: .cyan, label: "operations.dropoff_branch".localized, value: pd)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    // MARK: - Customer Profile Card (tappable → sheet)

    private var customerProfileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CUSTOMER & RETURN CONTEXT".localized)
            Button {
                HapticManager.shared.light()
                showCustomerSheet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(liveIade.customerFullName.isEmpty ? "Customer".localized : liveIade.customerFullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        let email = liveIade.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        Text(email.isEmpty ? "No email provided".localized : email)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if isTurkeyFranchise, !liveIade.testDriverFullName.isEmpty {
                            Text("\("operations.test_driver_label".localized): \(liveIade.testDriverFullName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.95))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Details".localized)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("NOTES".localized)
            Text(liveIade.notlar)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
        }
    }

    // MARK: - Photos Section (Apple Photos-style 3-column grid)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(format: "PHOTOS (%d)".localized, liveIade.fotograflar.count))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                spacing: 3
            ) {
                ForEach(Array(liveIade.fotograflar.enumerated()), id: \.offset) { index, url in
                    DetailPhotoGridCell(
                        urlString:  url,
                        label:      String(format: "Photo %d", index + 1),
                        labelColor: .blue
                    ) {
                        photoGalleryItem = PhotoGallerySheetItem(startIndex: index)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Action Buttons

    private var editButton: some View {
        Button {
            HapticManager.shared.medium()
            showEditSheet = true
        } label: {
            Label("Edit Return".localized, systemImage: "pencil.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding(.vertical, 15)
                .background(Color.orange)
                .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var pdfButton: some View {
        Button {
            HapticManager.shared.medium()
            guard !isSendingEmail else { return }
            generatePDF()
        } label: {
            HStack(spacing: 10) {
                if pdfOlusturuluyor {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("PDF generating...".localized).font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 16, weight: .semibold))
                    Text("Generate Return PDF".localized).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(pdfOlusturuluyor || isSendingEmail)
    }

    private var emailButton: some View {
        Button {
            if hasEmailBeenSentBefore {
                HapticManager.shared.light()
                ToastManager.shared.show("Email already sent to this customer.".localized, type: .info)
                return
            }
            guard !pdfOlusturuluyor else { return }
            HapticManager.shared.medium()
            sendReturnEmail()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold))
                Text(
                    hasEmailBeenSentBefore ? "Email Sent".localized :
                    isSendingEmail ? "Sending Email...".localized : "Send Return Email".localized
                )
                .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(hasEmailBeenSentBefore ? Color(.systemGray3) : Color.green)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSendingEmail || pdfOlusturuluyor)
    }

    private var emailAlreadySentInfoView: some View {
        let recipient = (liveIade.returnEmailRecipient ?? liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trackedDate = liveIade.returnEmailSentAt ?? viewModel.returnEmailSentFallbackByReturnId[liveIade.id.uuidString]
        let dateText = trackedDate?.formatted(date: .abbreviated, time: .shortened) ?? "-"
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Email already sent".localized).font(.caption.weight(.semibold))
                if !recipient.isEmpty { Text(recipient).font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            Text(dateText).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.green.opacity(0.09))
        .cornerRadius(12)
    }

    private var emailProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emailProgressMessage).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(emailProgress * 100))%").font(.caption2.weight(.semibold)).foregroundColor(.green)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.green.opacity(0.15)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color.green.opacity(0.7), .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * emailProgress), height: 8)
                        .animation(.easeInOut(duration: 0.25), value: emailProgress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.medium()
            silmeOnayiGoster = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").font(.system(size: 14, weight: .semibold))
                Text("Delete Return Record".localized).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.red)
            .padding(.vertical, 15)
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.leading, 2)
            .padding(.bottom, 7)
    }

    @ViewBuilder
    private func infoRow(icon: String, color: Color = .secondary, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(.tertiaryLabel))
                .frame(width: 20)
            Text(label).font(.system(size: 15)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - Logic (all functions preserved)

    func generatePDF() {
        generatePDF(language: .automatic)
    }

    func generatePDF(language: PDFContentLanguage) {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        IadePDFGenerator.shared.generateIadePDF(
            iade: liveIade,
            arac: arac,
            franchiseDisplayName: viewModel.franchiseName,
            language: language,
            signatureImageOverride: nil,
            turkeyNavContractDisplay: resolvedTurkeyNavContractDisplay(),
            staffSignerNameFallback: authManager.userProfile?.fullName
        ) { url in
            DispatchQueue.main.async {
                self.pdfOlusturuluyor = false
                if let url = url { self.shareRenamedPDF(url: url, name: self.pdfFileName) }
            }
        }
    }

    private func shareRenamedPDF(url: URL, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        pdfURL = dest
        pdfPaylas = true
    }

    private func sendReturnEmail() {
        guard let arac = arac else { return }
        let recipient = (liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            ToastManager.shared.show("Customer email is required.".localized, type: .error); return
        }
        guard isValidEmail(recipient) else {
            ToastManager.shared.show("Please enter a valid customer email.".localized, type: .error); return
        }

        print("📧 [ReturnEmailUI] start send flow returnId=\(liveIade.id.uuidString) plate=\(liveIade.aracPlaka) to=\(recipient)")

        FirebaseService.shared.loadSMTPConfiguration { config, _ in
            let host = config?.host.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sender = config?.senderEmail.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !host.isEmpty, !sender.isEmpty else {
                DispatchQueue.main.async {
                    ToastManager.shared.show("SMTP is not configured for this franchise yet.".localized, type: .error)
                }
                return
            }
            DispatchQueue.main.async {
                self.isSendingEmail = true
                self.emailProgress = 0.08
                self.emailProgressMessage = "Preparing PDF...".localized
            }

            IadePDFGenerator.shared.generateIadePDF(
            iade: liveIade,
            arac: arac,
            franchiseDisplayName: viewModel.franchiseName,
            language: .automatic,
            signatureImageOverride: nil,
            turkeyNavContractDisplay: resolvedTurkeyNavContractDisplay(),
            staffSignerNameFallback: authManager.userProfile?.fullName
        ) { localURL in
            guard let localURL, let data = try? Data(contentsOf: localURL) else {
                print("❌ [ReturnEmailUI] PDF generation failed returnId=\(liveIade.id.uuidString)")
                self.finishEmailFlow(success: false, message: "PDF generation failed.".localized); return
            }
            print("📄 [ReturnEmailUI] PDF generated bytes=\(data.count) returnId=\(liveIade.id.uuidString)")
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { self.emailProgress = 0.35; self.emailProgressMessage = "Uploading PDF...".localized } }
            let pdfPath = "return_pdfs/\(self.liveIade.id.uuidString).pdf"
            self.uploadReturnPDFWithRetry(data: data, path: pdfPath) { uploadedPDFURL in
                guard let uploadedPDFURL else {
                    print("❌ [ReturnEmailUI] PDF upload failed returnId=\(self.liveIade.id.uuidString)")
                    self.finishEmailFlow(success: false, message: "PDF upload failed.".localized); return
                }
                DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { self.emailProgress = 0.68; self.emailProgressMessage = "Queueing email...".localized } }
                FirebaseService.shared.queueReturnEmail(
                    to: recipient, subject: "Return Confirmation - \(self.liveIade.aracPlaka)",
                    body: IadePDFGenerator.returnConfirmationText(franchiseDisplayName: self.viewModel.franchiseName),
                    pdfURL: uploadedPDFURL,
                    returnId: self.liveIade.id.uuidString, vehiclePlate: self.liveIade.aracPlaka,
                    signerName: self.liveIade.customerFullName, signerEmail: recipient, forceResend: false,
                    pdfURLs: nil,
                    idempotencyKeySuffix: ""
                ) { error, queuedPaths in
                    if let error {
                        print("❌ [ReturnEmailUI] queue error returnId=\(self.liveIade.id.uuidString) err=\(error.localizedDescription)")
                        self.finishEmailFlow(success: false, message: "Email queue failed.".localized); return
                    }
                    guard let documentPath = queuedPaths.first else {
                        print("❌ [ReturnEmailUI] queue path missing returnId=\(self.liveIade.id.uuidString)")
                        self.finishEmailFlow(success: false, message: "Email queue path missing.".localized); return
                    }
                    print("📬 [ReturnEmailUI] queued path=\(documentPath) returnId=\(self.liveIade.id.uuidString)")
                    DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.25)) { self.emailProgress = 0.8; self.emailProgressMessage = "Sending email...".localized } }
                    self.observeQueuedEmailStatus(documentPath: documentPath) { status in
                        print("📨 [ReturnEmailUI] observe completed returnId=\(self.liveIade.id.uuidString) status=\(status)")
                        switch status {
                        case "sent", "duplicate_skipped": self.finishEmailFlow(success: true, message: "Email delivered.".localized)
                        case "failed":                    self.finishEmailFlow(success: false, message: "Email sending failed.".localized)
                        default:                          self.finishEmailFlow(success: false, message: "Email is still processing in background.".localized)
                        }
                    }
                }
            }
        }
        }
    }

    private func uploadReturnPDFWithRetry(data: Data, path: String, attempt: Int = 1, maxAttempts: Int = 4, completion: @escaping (String?) -> Void) {
        FirebaseService.shared.uploadData(data, path: path, contentType: "application/pdf") { uploadedURL, error in
            if let uploadedURL, !uploadedURL.isEmpty { completion(uploadedURL); return }
            if let error { print("⚠️ PDF upload attempt \(attempt) failed: \(error.localizedDescription)") }
            guard attempt < maxAttempts else { completion(nil); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + pow(2.0, Double(attempt - 1))) {
                uploadReturnPDFWithRetry(data: data, path: path, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
            }
        }
    }

    private func observeQueuedEmailStatus(
        documentPath: String,
        timeout: TimeInterval = 95,
        completion: @escaping (String) -> Void
    ) {
        let ref = Firestore.firestore().document(documentPath)
        let terminalStatuses: Set<String> = ["sent", "failed", "duplicate_skipped"]
        var registration: ListenerRegistration?
        var didComplete = false
        var timeoutWorkItem: DispatchWorkItem?
        var pollWorkItem: DispatchWorkItem?

        func finish(_ status: String) {
            guard !didComplete else { return }
            didComplete = true
            print("🏁 [ReturnEmailUI] observe finish path=\(documentPath) status=\(status)")
            registration?.remove()
            registration = nil
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            pollWorkItem?.cancel()
            pollWorkItem = nil
            completion(status)
        }

        func schedulePoll() {
            let workItem = DispatchWorkItem {
                guard !didComplete else { return }
                ref.getDocument { snapshot, error in
                    if let error {
                        print("⚠️ Poll getDocument error: \(error.localizedDescription)")
                    } else if
                        let data = snapshot?.data(),
                        let status = data["status"] as? String,
                        terminalStatuses.contains(status)
                    {
                        let err = String(describing: data["error"] ?? "")
                        print("🔎 [ReturnEmailUI] poll terminal path=\(documentPath) status=\(status) error=\(err)")
                        finish(status)
                        return
                    } else if let data = snapshot?.data() {
                        let status = String(describing: data["status"] ?? "unknown")
                        let err = String(describing: data["error"] ?? "")
                        print("🔎 [ReturnEmailUI] poll path=\(documentPath) status=\(status) error=\(err)")
                    }
                    if !didComplete { schedulePoll() }
                }
            }
            pollWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        }

        registration = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ Listener error: \(error.localizedDescription)")
                // Listener koptuysa da polling devam ederek terminal status yakalanabilir.
                return
            }
            guard let data = snapshot?.data() else { return }
            let status = String(describing: data["status"] ?? "unknown")
            let err = String(describing: data["error"] ?? "")
            print("🛰️ [ReturnEmailUI] listener path=\(documentPath) status=\(status) error=\(err)")
            if terminalStatuses.contains(status) { finish(status) }
        }

        let timeoutItem = DispatchWorkItem {
            print("⏱️ Email status observation timeout for path: \(documentPath)")
            finish("timeout")
        }
        timeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        schedulePoll()
    }

    private func finishEmailFlow(success: Bool, message: String) {
        DispatchQueue.main.async {
            print("📧 [ReturnEmailUI] finish flow returnId=\(liveIade.id.uuidString) success=\(success) message=\(message)")
            if success {
                withAnimation(.easeInOut(duration: 0.25)) { emailProgress = 1; emailProgressMessage = "Completed".localized }
                var u = liveIade; u.returnEmailSentAt = Date(); u.returnEmailLastStatus = "sent"
                u.returnEmailRecipient = (liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.iadeGuncelle(u)
                HapticManager.shared.success(); AudioServicesPlaySystemSound(1005)
                InAppNotificationManager.shared.showAfterDelay(
                    2.0,
                    icon: "paperplane.circle.fill",
                    iconColor: .green,
                    title: "Email Sent".localized,
                    body: message
                )
            } else {
                var u = liveIade; u.returnEmailLastStatus = "failed"; viewModel.iadeGuncelle(u)
                HapticManager.shared.error(); ToastManager.shared.show(message, type: .error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.2 : 0.6)) {
                isSendingEmail = false
                // Always reset UI progress; otherwise failure/timeout appears stuck at 80%.
                emailProgress = 0
                emailProgressMessage = "Preparing PDF...".localized
                print("🧹 [ReturnEmailUI] reset progress returnId=\(liveIade.id.uuidString)")
            }
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$").evaluate(with: email)
    }
}

// MARK: - Customer Context Sheet

private struct CustomerContextSheet: View {
    let iade: IadeIslemi
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Avatar + name header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.1)).frame(width: 80, height: 80)
                            Image(systemName: "person.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        if !iade.customerFullName.isEmpty {
                            Text(iade.customerFullName)
                                .font(.system(size: 20, weight: .bold))
                        }
                        let email = iade.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !email.isEmpty {
                            Text(email).font(.system(size: 14)).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Contact card
                    VStack(spacing: 0) {
                        sheetRow(icon: "person.fill",  color: .blue,  label: "Name".localized,
                                 value: iade.customerFullName.isEmpty ? "Not provided".localized : iade.customerFullName)
                        Divider().padding(.leading, 50)
                        sheetRow(icon: "envelope.fill", color: .blue,  label: "Email".localized,
                                 value: (iade.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                                    ? iade.customerEmail! : "Not provided".localized)
                        Divider().padding(.leading, 50)
                        sheetRow(icon: "signature",     color: .green, label: "Signature".localized,
                                 value: (iade.customerSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                                    ? "Added".localized : "Not added".localized,
                                 valueColor: (iade.customerSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? .green : .secondary)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // Checklist card
                    if let cl = iade.checklist {
                        VStack(spacing: 0) {
                            checklistRow("Customer was present".localized,       isOn: cl.customerPresent)
                            Divider().padding(.leading, 50)
                            checklistRow("Customer had no time".localized,       isOn: cl.customerNoTime)
                            Divider().padding(.leading, 50)
                            checklistRow("Key was taken from keybox".localized,  isOn: cl.keyFromKeybox)
                            Divider().padding(.leading, 50)
                            checklistRow("Customer refused to sign".localized,   isOn: cl.customerRefusedSignature)
                            Divider().padding(.leading, 50)
                            checklistRow("Customer left key at office".localized, isOn: cl.customerLeftKeyAtOffice)
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                    } else {
                        HStack {
                            Image(systemName: "checklist").foregroundColor(.secondary)
                            Text("No checklist selection".localized).foregroundColor(.secondary).font(.system(size: 15))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Customer Profile".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func sheetRow(icon: String, color: Color, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.13)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundColor(color)
            }
            Text(label).font(.system(size: 15)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(valueColor).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    @ViewBuilder
    private func checklistRow(_ label: String, isOn: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isOn ? Color.green : Color.secondary).opacity(0.13))
                    .frame(width: 32, height: 32)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isOn ? .green : .secondary)
            }
            Text(label).font(.system(size: 15)).foregroundColor(.secondary)
            Spacer()
            Text(isOn ? "On".localized : "Off".localized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn ? .green : .secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }
}

// MARK: - IadeFotoButton (preserved for backward compatibility)

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
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 120, height: 120).cornerRadius(12).clipped()
                } else if isLoading {
                    ZStack { Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 120, height: 120).cornerRadius(12); ProgressView() }
                } else {
                    ZStack { Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 120, height: 120).cornerRadius(12); Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray) }
                }
                Text(String(format: "Foto %d".localized, index + 1)).font(.caption2).fontWeight(.bold).foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { StorageImageLoader.shared.loadImage(from: urlString) { self.image = $0; self.isLoading = false } }
    }
}
