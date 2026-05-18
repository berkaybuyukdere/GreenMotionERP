import SwiftUI
import Kingfisher
import FirebaseFirestore
import AudioToolbox

struct ExitDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    let exit: ExitIslemi
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
    @Environment(\.dismiss) var dismiss

    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == exit.aracId })
    }

    var liveExit: ExitIslemi {
        viewModel.exitIslemleri.first(where: { $0.id == exit.id }) ?? exit
    }

    /// Hide automated front-desk intake lines; staff can still use real notes.
    private var shouldShowUserNotes: Bool {
        let n = liveExit.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return false }
        if n.hasPrefix("Front desk intake:") { return false }
        return true
    }

    private var hasEmailBeenSentBefore: Bool {
        liveExit.checkoutEmailSentAt != nil || liveExit.checkoutEmailLastStatus == "sent"
    }

    private var pdfFileName: String {
        let resStr  = liveExit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate   = liveExit.aracPlaka.replacingOccurrences(of: " ", with: "")
        if resStr.isEmpty {
            return "CHECKOUT-\(plate)"
        } else {
            let safeRes = resStr.replacingOccurrences(of: " ", with: "")
            return "CHECKOUT-\(safeRes)-\(plate)"
        }
    }

    private var isTurkeyFranchise: Bool {
        String(liveExit.franchiseId).uppercased().hasPrefix("TR")
    }

    private func turkeyEmailSubjectBranchName() -> String? {
        guard isTurkeyFranchise,
              TurkeyFranchiseMetadata.isTrialGmailFranchise(liveExit.franchiseId) else { return nil }
        return TurkeyFranchiseMetadata.branchDisplayTitle(
            pickUpBranch: liveExit.pickUpBranch,
            dropOffBranch: liveExit.dropOffBranch,
            preferDropOffForReturn: false,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
            franchiseGarageBranches: viewModel.franchiseGarageBranches
        )
    }

    private func turkeyCheckoutEmailSubject() -> String {
        if let custom = TurkeyFranchiseMetadata.trialEmailSubject(
            franchiseId: liveExit.franchiseId,
            pickUpBranch: liveExit.pickUpBranch,
            dropOffBranch: liveExit.dropOffBranch,
            isReturn: false,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
            franchiseGarageBranches: viewModel.franchiseGarageBranches
        ) {
            return custom
        }
        return "Check Out Confirmation - \(liveExit.aracPlaka)"
    }

    /// "Waiting checkout" copy is TR-only; CH/DE see neutral parked label.
    private var useWaitingCheckoutLabel: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                vehicleInfoCard
                customerProfileCard

                if shouldShowUserNotes {
                    notesCard
                }
                if !liveExit.fotograflar.isEmpty {
                    photosSection
                }
                if liveExit.status == .completed {
                    pdfButton
                    if FranchiseCapabilityMatrix.checkoutCustomerEmailEnabledForSession(
                        serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
                        userProfile: authManager.userProfile
                    ) {
                        emailButton
                        if hasEmailBeenSentBefore { emailAlreadySentInfoView }
                        if isSendingEmail || emailProgress > 0 { emailProgressView }
                    }
                }

                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Check Out Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.light()
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .fullScreenCover(item: $photoGalleryItem) { item in
            NativePhotoGalleryView(urlStrings: liveExit.fotograflar, initialIndex: item.startIndex)
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL { ActivityViewController(activityItems: [url]) }
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = arac {
                SheetWrapper {
                    NavigationView {
                        ExitIslemView(arac: arac, existingExit: liveExit, onExitCompleted: { _ in })
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomerSheet) {
            CheckoutCustomerContextSheet(exit: liveExit)
        }
        .alert("Delete Check Out Record".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.exitSil(liveExit)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this check out record?".localized)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(statusAccentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(statusAccentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(liveExit.aracPlaka)
                    .font(.system(size: 17, weight: .bold))
                Text("Check Out".localized)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(statusAccentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusAccentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private var statusAccentColor: Color {
        switch liveExit.status {
        case .inProgress: return .orange
        case .parked:     return .orange
        case .completed:  return .blue
        }
    }

    private var statusIcon: String {
        switch liveExit.status {
        case .inProgress: return "clock.arrow.circlepath"
        case .parked:     return "car.fill"
        case .completed:  return "arrow.right.circle.fill"
        }
    }

    private var statusLabel: String {
        switch liveExit.status {
        case .inProgress: return "In Progress".localized
        case .parked:     return useWaitingCheckoutLabel ? "Waiting checkout".localized : "Parked".localized
        case .completed:  return "Completed".localized
        }
    }

    // MARK: - Vehicle Info Card

    private var vehicleInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("VEHICLE INFORMATION".localized)
            VStack(spacing: 0) {
                infoRow(icon: "number.square.fill",    color: .blue,   label: "Plate".localized,        value: liveExit.aracPlaka)
                Divider().padding(.leading, 50)
                infoRow(icon: "calendar",              color: .orange, label: "Process Date".localized,  value: liveExit.exitTarihi.formatted(date: .long, time: .shortened))
                if !liveExit.resKodu.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(
                        icon: "number.circle.fill",
                        color: .purple,
                        label: isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
                        value: liveExit.resKodu
                    )
                }
                if let km = liveExit.km {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "gauge.medium",      color: .green,  label: "KM".localized,            value: "\(km) km")
                }
                if let y = liveExit.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "fuelpump.fill",       color: .orange, label: "Fuel level".localized,    value: y)
                }
                if let pu = (liveExit.pickUpBranch ?? liveExit.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "arrow.up.circle.fill", color: .teal, label: "operations.pickup_branch".localized, value: pu)
                }
                if let pd = liveExit.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "arrow.down.circle.fill", color: .cyan, label: "operations.dropoff_branch".localized, value: pd)
                }
                if let pr = liveExit.plannedReturnAt {
                    Divider().padding(.leading, 50)
                    infoRow(
                        icon: "calendar.badge.clock",
                        color: .mint,
                        label: "operations.planned_return".localized,
                        value: pr.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    private var customerProfileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CUSTOMER & CHECK OUT CONTEXT".localized)
            Button {
                HapticManager.shared.light()
                showCustomerSheet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.teal.opacity(0.12)).frame(width: 44, height: 44)
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.teal)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(liveExit.customerFullName.isEmpty ? "Customer".localized : liveExit.customerFullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        let email = (liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(email.isEmpty ? "No email provided".localized : email)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if isTurkeyFranchise, !liveExit.testDriverFullName.isEmpty {
                            Text("\("operations.test_driver_label".localized): \(liveExit.testDriverFullName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.95))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
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
            Text(liveExit.notlar)
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
            sectionLabel(String(format: "PHOTOS (%d)".localized, liveExit.fotograflar.count))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                spacing: 3
            ) {
                ForEach(Array(liveExit.fotograflar.enumerated()), id: \.offset) { index, url in
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

    // MARK: - PDF Button (blue)

    private var pdfButton: some View {
        Button {
            HapticManager.shared.medium()
            guard !isSendingEmail else { return }
            generatePDF()
        } label: {
            HStack(spacing: 10) {
                if pdfOlusturuluyor {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("Generating PDF...".localized).font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 16, weight: .semibold))
                    Text("Generate PDF".localized).font(.system(size: 16, weight: .semibold))
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
                ToastManager.shared.show("Email already sent to this customer.".localized, type: .info)
                return
            }
            guard !pdfOlusturuluyor else { return }
            HapticManager.shared.medium()
            sendCheckoutEmail()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold))
                Text(
                    hasEmailBeenSentBefore ? "Email Sent".localized :
                    isSendingEmail ? "Sending Email...".localized : "Send Check Out Email".localized
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
        let recipient = (liveExit.checkoutEmailRecipient ?? liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dateText = liveExit.checkoutEmailSentAt?.formatted(date: .abbreviated, time: .shortened) ?? "-"
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

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.medium()
            silmeOnayiGoster = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").font(.system(size: 14, weight: .semibold))
                Text("Delete Check Out Record".localized).font(.system(size: 16, weight: .semibold))
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

    // MARK: - Logic (unchanged)

    func generatePDF() {
        generatePDF(language: .automatic)
    }

    func generatePDF(language: PDFContentLanguage) {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        ExitPDFGenerator.shared.generateExitPDF(
            exit: liveExit,
            arac: arac,
            franchiseDisplayName: viewModel.franchiseName,
            staffSignerNameFallback: authManager.userProfile?.fullName,
            language: language
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

    private func sendCheckoutEmail() {
        guard FranchiseCapabilityMatrix.checkoutCustomerEmailEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) else { return }
        guard let arac = arac else { return }
        let recipient = (liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            ToastManager.shared.show("Customer email is required.".localized, type: .error)
            return
        }
        guard isValidEmail(recipient) else {
            ToastManager.shared.show("Please enter a valid customer email.".localized, type: .error)
            return
        }

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

            ExitPDFGenerator.shared.generateExitPDF(
                exit: self.liveExit,
                arac: arac,
                franchiseDisplayName: TurkeyFranchiseMetadata.commercialTitle(
                    franchiseDisplayName: self.viewModel.franchiseName,
                    turkeyLocationBranches: self.viewModel.turkeyFranchiseLocationBranches
                ),
                staffSignerNameFallback: self.authManager.userProfile?.fullName,
                language: .automatic
            ) { localURL in
                guard let localURL, let data = try? Data(contentsOf: localURL) else {
                    self.finishEmailFlow(success: false, message: "PDF generation failed.".localized)
                    return
                }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.emailProgress = 0.35
                        self.emailProgressMessage = "Uploading PDF...".localized
                    }
                }
                let path = "checkout_pdfs/\(self.liveExit.id.uuidString).pdf"
                self.uploadCheckoutPDFWithRetry(data: data, path: path) { uploadedPDFURL in
                    guard let uploadedPDFURL else {
                        self.finishEmailFlow(success: false, message: "PDF upload failed.".localized)
                        return
                    }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            self.emailProgress = 0.68
                            self.emailProgressMessage = "Queueing email...".localized
                        }
                    }
                    let subject = self.turkeyCheckoutEmailSubject()
                    FirebaseService.shared.queueReturnEmail(
                        to: recipient,
                        subject: subject,
                        body: ExitPDFGenerator.checkoutConfirmationText(
                            franchiseId: self.liveExit.franchiseId,
                            franchiseDisplayName: self.viewModel.franchiseName
                        ),
                        pdfURL: uploadedPDFURL,
                        returnId: self.liveExit.id.uuidString,
                        vehiclePlate: self.liveExit.aracPlaka,
                        signerName: self.liveExit.customerFullName,
                        signerEmail: recipient,
                        forceResend: false,
                        pdfURLs: nil,
                        vehiclePdfURL: uploadedPDFURL,
                        rentalTermsPdfURL: nil,
                        rentalTermsLanguageCode: nil,
                        emailSubjectBranchName: self.turkeyEmailSubjectBranchName(),
                        idempotencyKeySuffix: ""
                    ) { error, queuedPaths in
                        if let error {
                            print("❌ Queue error: \(error.localizedDescription)")
                            self.finishEmailFlow(success: false, message: "Email queue failed.".localized)
                            return
                        }
                        guard let documentPath = queuedPaths.first else {
                            self.finishEmailFlow(success: false, message: "Email queue path missing.".localized)
                            return
                        }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.emailProgress = 0.8
                                self.emailProgressMessage = "Sending email...".localized
                            }
                        }
                        self.observeQueuedEmailStatus(documentPath: documentPath) { status in
                            switch status {
                            case "sent", "duplicate_skipped":
                                self.finishEmailFlow(success: true, message: "Email delivered.".localized)
                            case "failed":
                                self.finishEmailFlow(success: false, message: "Email sending failed.".localized)
                            default:
                                self.finishEmailFlow(success: false, message: "Email is still processing in background.".localized)
                            }
                        }
                    }
                }
            }
        }
    }

    private func uploadCheckoutPDFWithRetry(data: Data, path: String, attempt: Int = 1, maxAttempts: Int = 4, completion: @escaping (String?) -> Void) {
        FirebaseService.shared.uploadData(data, path: path, contentType: "application/pdf") { uploadedURL, error in
            if let uploadedURL, !uploadedURL.isEmpty { completion(uploadedURL); return }
            if let error { print("⚠️ PDF upload attempt \(attempt) failed: \(error.localizedDescription)") }
            guard attempt < maxAttempts else { completion(nil); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + pow(2.0, Double(attempt - 1))) {
                uploadCheckoutPDFWithRetry(data: data, path: path, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
            }
        }
    }

    private func observeQueuedEmailStatus(documentPath: String, timeout: TimeInterval = 45, completion: @escaping (String) -> Void) {
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
                print("❌ Listener error: \(error.localizedDescription)")
                finish("listener_error")
                return
            }
            guard let data = snapshot?.data() else { return }
            let status = String(describing: data["status"] ?? "unknown")
            if ["sent", "failed", "duplicate_skipped"].contains(status) { finish(status) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish("timeout") }
    }

    private func finishEmailFlow(success: Bool, message: String) {
        DispatchQueue.main.async {
            if success {
                withAnimation(.easeInOut(duration: 0.25)) {
                    emailProgress = 1
                    emailProgressMessage = "Completed".localized
                }
                var updated = liveExit
                updated.checkoutEmailSentAt = Date()
                updated.checkoutEmailLastStatus = "sent"
                updated.checkoutEmailRecipient = (liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.exitGuncelle(updated)
                HapticManager.shared.success()
                AudioServicesPlaySystemSound(1005)
                InAppNotificationManager.shared.showAfterDelay(
                    2.0,
                    icon: "paperplane.circle.fill",
                    iconColor: .green,
                    title: "Email Sent".localized,
                    body: message
                )
            } else {
                var updated = liveExit
                updated.checkoutEmailLastStatus = "failed"
                viewModel.exitGuncelle(updated)
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

    private func isValidEmail(_ email: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$").evaluate(with: email)
    }
}

private struct CheckoutCustomerContextSheet: View {
    let exit: ExitIslemi
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                HStack {
                    Text("Name".localized)
                    Spacer()
                    Text(exit.customerFullName.isEmpty ? "Not provided".localized : exit.customerFullName)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Email".localized)
                    Spacer()
                    Text((exit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not provided".localized : (exit.customerEmail ?? ""))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Signature".localized)
                    Spacer()
                    Text((exit.customerSignatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added".localized : "Added".localized)
                        .foregroundColor((exit.customerSignatureURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .green)
                }
            }
            .navigationTitle("Customer Profile".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - ExitFotoButton (preserved for backward compatibility)

struct ExitFotoButton: View {
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
