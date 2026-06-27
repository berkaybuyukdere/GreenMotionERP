import SwiftUI
import Kingfisher
import FirebaseFirestore

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
    @ObservedObject private var emailSend = CustomerEmailSendCoordinator.shared
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

    private var isGermanyFranchise: Bool {
        FranchiseCapabilityMatrix.isGermany(franchiseId: liveIade.franchiseId)
    }

    private var palantirOps: Bool {
        PalantirProcessDetailSupport.isEnabled(userProfile: authManager.userProfile)
    }

    private var linkedCheckoutHandoverDate: Date? {
        guard let lid = liveIade.linkedExitId,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return nil }
        return ex.exitTarihi
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

    private func iadeForReturnEmailTermsAttachment() -> IadeIslemi {
        var copy = liveIade
        let hasTerms = (copy.trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        guard !hasTerms, let lid = copy.linkedExitId,
              let ex = viewModel.exitIslemleri.first(where: { $0.id == lid }) else { return copy }
        if copy.trRentalTermsSignatureURL == nil || copy.trRentalTermsSignatureURL?.isEmpty == true {
            copy.trRentalTermsSignatureURL = ex.trRentalTermsSignatureURL
        }
        if copy.trRentalTermsLanguage == nil {
            copy.trRentalTermsLanguage = ex.trRentalTermsLanguage
        }
        if copy.trRentalTermsAcceptedAt == nil {
            copy.trRentalTermsAcceptedAt = ex.trRentalTermsAcceptedAt
        }
        return copy
    }

    private func turkeyEmailSubjectBranchName() -> String? {
        guard isTurkeyFranchise,
              TurkeyFranchiseMetadata.isTrialGmailFranchise(liveIade.franchiseId) else { return nil }
        return TurkeyFranchiseMetadata.branchDisplayTitle(
            pickUpBranch: liveIade.pickUpBranch,
            dropOffBranch: liveIade.dropOffBranch,
            preferDropOffForReturn: true,
            turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
            franchiseGarageBranches: viewModel.franchiseGarageBranches
        )
    }

    private func turkeyReturnEmailSubject() -> String {
        if let branch = turkeyEmailSubjectBranchName() {
            return TurkeyFranchiseMetadata.trialEmailSubject(
                franchiseId: liveIade.franchiseId,
                pickUpBranch: liveIade.pickUpBranch,
                dropOffBranch: liveIade.dropOffBranch,
                isReturn: true,
                turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches,
                franchiseGarageBranches: viewModel.franchiseGarageBranches
            ) ?? "Return Confirmation - \(liveIade.aracPlaka)"
        }
        return "Return Confirmation - \(liveIade.aracPlaka)"
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
            VStack(spacing: palantirOps ? 11 : 16) {
                statusCard
                if let arac, liveIade.status == .completed {
                    operationIdentityBanner(arac: arac)
                }
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
                    if FranchiseCapabilityMatrix.returnCustomerEmailEnabledForSession(
                        serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
                        userProfile: authManager.userProfile
                    ) {
                        emailButton
                    }
                    if hasEmailBeenSentBefore {
                        emailAlreadySentInfoView
                    }
                    if !emailSend.isActive && emailSend.progress > 0 {
                        emailProgressView
                    }
                }

                deleteButton
            }
            .padding(.horizontal, palantirOps ? 13 : 16)
            .padding(.top, palantirOps ? 11 : 16)
            .padding(.bottom, 44)
        }
        .processDetailScreenBackground(palantirOps)
        .palantirProcessDetailChrome(enabled: palantirOps)
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
                        .disabled(emailSend.isActive)
                    }
                    Button {
                        HapticManager.shared.light()
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .disabled(emailSend.isActive)
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

    @ViewBuilder
    private var statusCard: some View {
        let isCompleted = liveIade.status == .completed
        if palantirOps {
            PalantirProcessDetailHero(
                title: liveIade.aracPlaka,
                subtitle: "Return Details".localized,
                icon: isCompleted ? "checkmark.shield.fill" : "clock.arrow.circlepath",
                tint: PalantirTheme.accent,
                badge: isCompleted ? "Completed".localized : "In Progress".localized,
                badgeTone: isCompleted ? .success : .warning
            )
        } else {
            legacyStatusCard(isCompleted: isCompleted)
        }
    }

    private func legacyStatusCard(isCompleted: Bool) -> some View {
        HStack(spacing: 14) {
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

    private func operationIdentityBanner(arac: Arac) -> some View {
        OperationIdentityLinkRow(
            plate: liveIade.aracPlaka,
            reservationCode: resolvedReturnReservationCode,
            reservationLabel: isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
            vehicle: arac,
            iade: liveIade,
            plateInteractive: true,
            codeInteractive: false
        )
    }

    private var resolvedReturnReservationCode: String? {
        if let nav = liveIade.navKodu?.trimmingCharacters(in: .whitespacesAndNewlines), !nav.isEmpty {
            return nav
        }
        if let linked = liveIade.linkedExitId,
           let ex = viewModel.exitIslemleri.first(where: { $0.id == linked }) {
            let raw = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : raw
        }
        return nil
    }

    // MARK: - Vehicle Info Card

    @ViewBuilder
    private var vehicleInfoCard: some View {
        if palantirOps {
            PalantirProcessDetailInfoSection(
                title: "VEHICLE INFORMATION".localized,
                icon: "car.fill",
                rows: vehicleInfoRows
            )
        } else {
            legacyVehicleInfoCard
        }
    }

    private var vehicleInfoRows: [(label: String, value: String)] {
        var rows: [(String, String)] = [
            ("Plate".localized, liveIade.aracPlaka),
            ("Return Date".localized, liveIade.iadeTarihi.formatted(date: .long, time: .shortened)),
        ]
        if let km = liveIade.km {
            rows.append(("KM".localized, "\(km) km"))
        }
        if let y = liveIade.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
            rows.append(("Fuel level".localized, y))
        }
        if let pu = liveIade.pickUpBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
            rows.append(("operations.pickup_branch".localized, pu))
        }
        if let pd = liveIade.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
            rows.append(("operations.dropoff_branch".localized, pd))
        }
        if let status = liveIade.wheelsysSyncStatus?.lowercased(), status == "success" || status == "synced" {
            rows.append(("WheelSys", "wheelsys.return.success".localized))
        }
        return rows
    }

    private var legacyVehicleInfoCard: some View {
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
                if let status = liveIade.wheelsysSyncStatus?.lowercased(), status == "success" || status == "synced" {
                    Divider().padding(.leading, 50)
                    infoRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        label: "WheelSys",
                        value: "wheelsys.return.success".localized
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    // MARK: - Customer Profile Card (tappable → sheet)

    @ViewBuilder
    private var customerProfileCard: some View {
        if palantirOps {
            palantirCustomerProfileCard
        } else {
            legacyCustomerProfileCard
        }
    }

    private var palantirCustomerProfileCard: some View {
        WheelSysPalantirSectionCard(
            title: "CUSTOMER & RETURN CONTEXT".localized,
            icon: "person.text.rectangle"
        ) {
            Button {
                HapticManager.shared.light()
                showCustomerSheet = true
            } label: {
                HStack(spacing: 12) {
                    PalantirOpsIconTile(systemName: "person.fill", tint: PalantirTheme.accent, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveIade.customerFullName.isEmpty ? "Customer".localized : liveIade.customerFullName)
                            .font(PalantirTheme.bodyFont(14))
                            .foregroundStyle(PalantirTheme.textPrimary)
                            .lineLimit(2)
                        let email = liveIade.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        Text(email.isEmpty ? "No email provided".localized : email)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(1)
                        if isTurkeyFranchise, !liveIade.testDriverFullName.isEmpty {
                            Text("\("operations.test_driver_label".localized): \(liveIade.testDriverFullName)")
                                .font(PalantirTheme.labelFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    PalantirOpsBadge(text: "Details".localized, tone: .accent)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var legacyCustomerProfileCard: some View {
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
                        urlString: url,
                        label: ProcessPhotoStampLabels.processPhotoIndexLabel(index),
                        dateText: ProcessPhotoStampLabels.formatDisplayDate(
                            liveIade.iadeTarihi,
                            includeTime: false
                        ),
                        timeText: isGermanyFranchise
                            ? ProcessPhotoStampLabels.formatPDFTime(liveIade.iadeTarihi)
                            : nil,
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

    @ViewBuilder
    private var editButton: some View {
        if palantirOps {
            PalantirOpsActionButton(
                title: "Edit Return".localized,
                icon: "pencil",
                style: .warning
            ) {
                HapticManager.shared.medium()
                showEditSheet = true
            }
        } else {
            legacyEditButton
        }
    }

    private var legacyEditButton: some View {
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

    @ViewBuilder
    private var pdfButton: some View {
        if palantirOps {
            WheelSysPalantirPrimaryButton(
                title: pdfOlusturuluyor ? "PDF generating...".localized : "Generate Return PDF".localized,
                icon: "doc.text.fill",
                isLoading: pdfOlusturuluyor,
                disabled: pdfOlusturuluyor || emailSend.isActive
            ) {
                HapticManager.shared.medium()
                guard !emailSend.isActive else { return }
                generatePDF()
            }
        } else {
            legacyPdfButton
        }
    }

    private var legacyPdfButton: some View {
        Button {
            HapticManager.shared.medium()
            guard !emailSend.isActive else { return }
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
        .disabled(pdfOlusturuluyor || emailSend.isActive)
    }

    private var emailButton: some View {
        CustomerEmailSendButton(
            title: hasEmailBeenSentBefore ? "Resend Return Email".localized : "Send Return Email".localized,
            sendingTitle: "Sending Email...".localized,
            accentColor: .green,
            isSending: emailSend.isActive,
            isExternallyDisabled: pdfOlusturuluyor
        ) {
            sendReturnEmail(forceResend: hasEmailBeenSentBefore)
        }
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
                Text(emailSend.progressMessage).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(emailSend.progress * 100))%").font(.caption2.weight(.semibold)).foregroundColor(.green)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.green.opacity(0.15)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color.green.opacity(0.7), .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * emailSend.progress), height: 8)
                        .animation(.easeInOut(duration: 0.25), value: emailSend.progress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var deleteButton: some View {
        if palantirOps {
            PalantirOpsActionButton(
                title: "Delete Return Record".localized,
                icon: "trash.fill",
                style: .destructive
            ) {
                HapticManager.shared.medium()
                silmeOnayiGoster = true
            }
        } else {
            legacyDeleteButton
        }
    }

    private var legacyDeleteButton: some View {
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
            franchiseDisplayName: TurkeyFranchiseMetadata.commercialTitle(
                franchiseDisplayName: viewModel.franchiseName,
                turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches
            ),
            language: language,
            signatureImageOverride: nil,
            turkeyNavContractDisplay: resolvedTurkeyNavContractDisplay(),
            staffSignerNameFallback: authManager.userProfile?.fullName,
            handoverDateForPhotos: linkedCheckoutHandoverDate
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

    private func sendReturnEmail(forceResend: Bool = false) {
        guard !emailSend.isActive else { return }
        guard let arac = arac else { return }
        let recipient = (liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            ToastManager.shared.show("Customer email is required.".localized, type: .error); return
        }
        guard isValidEmail(recipient) else {
            ToastManager.shared.show("Please enter a valid customer email.".localized, type: .error); return
        }

        print("📧 [ReturnEmailUI] start send flow returnId=\(liveIade.id.uuidString) plate=\(liveIade.aracPlaka) to=\(recipient)")

        let photoCount = PdfEmailImageCompressor.cappedPhotoURLs(liveIade.fotograflar).count
        emailSend.beginSending(photoSummary: String(
            format: NSLocalizedString("%d photos in report", comment: "email return"),
            photoCount
        ))

        FirebaseService.shared.loadSMTPConfiguration { config, _ in
            let host = config?.host.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sender = config?.senderEmail.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let username = config?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !host.isEmpty, !sender.isEmpty, !username.isEmpty else {
                DispatchQueue.main.async {
                    self.emailSend.completeSending(
                        success: false,
                        message: "SMTP is not configured for this franchise yet.".localized,
                        emailKind: .returnConfirmation,
                        vehiclePlate: self.liveIade.aracPlaka,
                        recipient: recipient
                    )
                }
                return
            }

            IadePDFGenerator.shared.generateIadePDF(
            iade: liveIade,
            arac: arac,
            franchiseDisplayName: TurkeyFranchiseMetadata.commercialTitle(
                franchiseDisplayName: viewModel.franchiseName,
                turkeyLocationBranches: viewModel.turkeyFranchiseLocationBranches
            ),
            language: .automatic,
            signatureImageOverride: nil,
            turkeyNavContractDisplay: resolvedTurkeyNavContractDisplay(),
            staffSignerNameFallback: authManager.userProfile?.fullName,
            handoverDateForPhotos: linkedCheckoutHandoverDate,
            forCustomerEmail: true,
            onProgress: { message in
                DispatchQueue.main.async {
                    var value = self.emailSend.progress
                    if message.contains("Loading photos") {
                        value = 0.18
                    } else if message.contains("Optimizing") {
                        value = 0.28
                    } else if message.contains("Building") {
                        value = 0.32
                    }
                    self.emailSend.updateProgress(value, message: message, animated: true)
                }
            }
        ) { localURL in
            guard let localURL, let data = try? Data(contentsOf: localURL) else {
                print("❌ [ReturnEmailUI] PDF generation failed returnId=\(liveIade.id.uuidString)")
                self.finishEmailFlow(success: false, message: "PDF generation failed.".localized); return
            }
            print("📄 [ReturnEmailUI] PDF generated bytes=\(data.count) returnId=\(liveIade.id.uuidString)")
            DispatchQueue.main.async {
                self.emailSend.updateProgress(0.42, message: "Uploading PDF to server…".localized)
            }
            let franchiseId = self.resolvedEmailFranchiseId()
            let fileName = "\(self.liveIade.id.uuidString).pdf"
            self.uploadReturnPDFWithRetry(data: data, franchiseId: franchiseId, fileName: fileName) { uploadedPDFURL in
                let pdfRef = uploadedPDFURL ?? ""
                guard !pdfRef.isEmpty else {
                    print("❌ [ReturnEmailUI] PDF upload failed returnId=\(self.liveIade.id.uuidString)")
                    self.finishEmailFlow(success: false, message: "PDF upload failed.".localized); return
                }
                func queueReturnEmailAfterUpload(
                    mainURL: String,
                    extraTermsURL: String?,
                    termsLanguageCode: String?
                ) {
                    DispatchQueue.main.async {
                        self.emailSend.updateProgress(0.62, message: "Queueing email…".localized)
                    }
                    let termsURL = extraTermsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let subject = self.turkeyReturnEmailSubject()
                    FirebaseService.shared.queueReturnEmail(
                        to: recipient, subject: subject,
                        body: IadePDFGenerator.returnConfirmationText(
                            franchiseId: self.liveIade.franchiseId,
                            franchiseDisplayName: FranchiseCapabilityMatrix.isGermany(franchiseId: self.liveIade.franchiseId)
                                ? SwissReportPDFTemplate.germanyDisplayName(
                                    franchiseId: self.liveIade.franchiseId,
                                    explicit: nil
                                )
                                : self.viewModel.franchiseName
                        ),
                        pdfURL: mainURL,
                        returnId: self.liveIade.id.uuidString, vehiclePlate: self.liveIade.aracPlaka,
                        signerName: self.liveIade.customerFullName, signerEmail: recipient, forceResend: forceResend,
                        pdfURLs: {
                            guard self.isTurkeyFranchise, let t = termsURL, !t.isEmpty else { return nil }
                            return [mainURL, t]
                        }(),
                        vehiclePdfURL: mainURL,
                        rentalTermsPdfURL: self.isTurkeyFranchise && termsURL?.isEmpty == false ? termsURL : nil,
                        rentalTermsLanguageCode: self.isTurkeyFranchise ? termsLanguageCode : nil,
                        emailSubjectBranchName: self.turkeyEmailSubjectBranchName(),
                        idempotencyKeySuffix: "",
                        franchiseId: franchiseId
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
                        DispatchQueue.main.async {
                            self.emailSend.updateProgress(0.78, message: "Sending via SMTP…".localized)
                            self.emailSend.observeQueuedEmailStatus(documentPath: documentPath, timeout: 120, usePolling: true) { status in
                                print("📨 [ReturnEmailUI] observe completed returnId=\(self.liveIade.id.uuidString) status=\(status)")
                                switch status {
                                case "sent":
                                    self.finishEmailFlow(success: true, message: "Email delivered.".localized)
                                case "duplicate_skipped":
                                    self.finishEmailFlow(
                                        success: false,
                                        message: "Email was skipped as duplicate. Tap Resend to try again.".localized
                                    )
                                case "failed":
                                    self.finishEmailFlow(success: false, message: "Email sending failed.".localized)
                                default:
                                    self.finishEmailFlow(success: false, message: "Email is still processing in background.".localized)
                                }
                            }
                        }
                    }
                }

                guard self.isTurkeyFranchise else {
                    queueReturnEmailAfterUpload(mainURL: pdfRef, extraTermsURL: nil, termsLanguageCode: nil)
                    return
                }
                DispatchQueue.main.async {
                    self.emailSend.updateProgress(0.55, message: "Preparing rental terms PDF...".localized)
                }
                let termsSourceIade = self.iadeForReturnEmailTermsAttachment()
                TurkeyRentalTermsEmailAttachmentBuilder.makePdfDataForIade(termsSourceIade) { termsData in
                    guard let td = termsData, !td.isEmpty else {
                        queueReturnEmailAfterUpload(
                            mainURL: pdfRef,
                            extraTermsURL: nil,
                            termsLanguageCode: termsSourceIade.trRentalTermsLanguage
                        )
                        return
                    }
                    let termsFileName = "\(self.liveIade.id.uuidString)_rental_terms.pdf"
                    self.uploadReturnPDFWithRetry(
                        data: td,
                        franchiseId: franchiseId,
                        fileName: termsFileName
                    ) { termsURL in
                        queueReturnEmailAfterUpload(
                            mainURL: pdfRef,
                            extraTermsURL: termsURL,
                            termsLanguageCode: termsSourceIade.trRentalTermsLanguage
                        )
                    }
                }
            }
        }
        }
    }

    private func resolvedEmailFranchiseId() -> String {
        let fromIade = liveIade.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !fromIade.isEmpty, fromIade.hasPrefix("DE") || fromIade.hasPrefix("TR") || fromIade.hasPrefix("CH") {
            return fromIade
        }
        return FirebaseService.shared.currentFranchiseId
    }

    private func uploadReturnPDFWithRetry(
        data: Data,
        franchiseId: String,
        fileName: String,
        attempt: Int = 1,
        maxAttempts: Int = 2,
        completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.main.async {
            let message = attempt > 1
                ? String(format: NSLocalizedString("Uploading PDF (attempt %d)…", comment: ""), attempt)
                : "Uploading PDF...".localized
            self.emailSend.updateProgress(self.emailSend.progress, message: message, animated: false)
        }
        FirebaseService.shared.uploadOperationPdfForEmail(
            data: data,
            franchiseId: franchiseId,
            subfolder: "return_pdfs",
            fileName: fileName
        ) { uploadedURL in
            if let uploadedURL, !uploadedURL.isEmpty {
                completion(uploadedURL)
                return
            }
            guard attempt < maxAttempts else {
                completion(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pow(2.0, Double(attempt))) {
                self.uploadReturnPDFWithRetry(
                    data: data,
                    franchiseId: franchiseId,
                    fileName: fileName,
                    attempt: attempt + 1,
                    maxAttempts: maxAttempts,
                    completion: completion
                )
            }
        }
    }

    private func finishEmailFlow(success: Bool, message: String) {
        DispatchQueue.main.async {
            print("📧 [ReturnEmailUI] finish flow returnId=\(self.liveIade.id.uuidString) success=\(success) message=\(message)")
            if success {
                var u = self.liveIade
                u.returnEmailSentAt = Date()
                u.returnEmailLastStatus = "sent"
                u.returnEmailRecipient = (self.liveIade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.viewModel.iadeGuncelle(u)
            } else {
                var u = self.liveIade
                u.returnEmailLastStatus = "failed"
                self.viewModel.iadeGuncelle(u)
            }
            self.emailSend.completeSending(
                success: success,
                message: success ? "Email delivered.".localized : message,
                failureToast: success ? nil : message,
                emailKind: .returnConfirmation,
                vehiclePlate: self.liveIade.aracPlaka,
                recipient: self.liveIade.customerEmail
            )
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
