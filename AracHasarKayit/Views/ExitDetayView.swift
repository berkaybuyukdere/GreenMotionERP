import SwiftUI
import Kingfisher
import FirebaseFirestore

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
    @ObservedObject private var emailSend = CustomerEmailSendCoordinator.shared
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
        liveExit.checkoutEmailLastStatus == "sent" || liveExit.checkoutEmailSentAt != nil
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

    private func checkoutEmailSubject() -> String {
        if isTurkeyFranchise { return turkeyCheckoutEmailSubject() }
        return "Checkout Confirmation - \(liveExit.aracPlaka)"
    }

    private var isGermanyFranchise: Bool {
        FranchiseCapabilityMatrix.isGermany(franchiseId: liveExit.franchiseId)
    }

    /// "Waiting checkout" copy is TR-only; CH/DE see neutral parked label.
    private var useWaitingCheckoutLabel: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var palantirOps: Bool {
        PalantirProcessDetailSupport.isEnabled(userProfile: authManager.userProfile)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: palantirOps ? 11 : 16) {
                statusCard
                if rentalContextCardVisible {
                    rentalContextCard
                }
                if let arac, liveExit.status == .completed {
                    operationIdentityBanner(arac: arac)
                }
                vehicleInfoCard
                customerProfileCard

                if shouldShowUserNotes, rentalContextNotes == nil {
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
                        if !emailSend.isActive && emailSend.progress > 0 { emailProgressView }
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
                .disabled(emailSend.isActive)
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
                viewModel.exitSil(liveExit) { success in
                    if success { dismiss() }
                }
            }
        } message: {
            Text("Are you sure you want to delete this check out record?".localized)
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        if palantirOps {
            PalantirProcessDetailHero(
                title: liveExit.aracPlaka,
                subtitle: "Check Out".localized,
                icon: statusIcon,
                tint: statusAccentColor,
                badge: statusLabel,
                badgeTone: liveExit.status == .completed ? .accent : .warning
            )
        } else {
            legacyStatusCard
        }
    }

    private var legacyStatusCard: some View {
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

    private var statusLabel: String {
        switch liveExit.status {
        case .inProgress: return "In Progress".localized
        case .parked:     return useWaitingCheckoutLabel ? "Waiting checkout".localized : "Parked".localized
        case .completed:  return "Completed".localized
        }
    }

    private var linkedReturn: IadeIslemi? {
        viewModel.iadeIslemleri.first {
            $0.linkedExitId == liveExit.id && !$0.isDeleted
        }
    }

    private var rentalSnapshot: ExitWheelSysSnapshot? {
        liveExit.wheelSysSnapshot
    }

    private var computedRentalDays: Int? {
        if let days = rentalSnapshot?.rentalDays, days > 0 { return days }
        guard let end = liveExit.plannedReturnAt else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: liveExit.exitTarihi)
        let finish = cal.startOfDay(for: end)
        let days = cal.dateComponents([.day], from: start, to: finish).day ?? 0
        return max(1, days)
    }

    private var rentalContextNotes: String? {
        if let snapNotes = rentalSnapshot?.rentalNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !snapNotes.isEmpty {
            return snapNotes
        }
        if shouldShowUserNotes {
            return liveExit.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private var checkinStatusLabel: String {
        if let linked = linkedReturn {
            switch linked.status {
            case .completed:
                return "checkout.detail.checkin_completed".localized
            case .inProgress:
                return "checkout.detail.checkin_in_progress".localized
            }
        }
        if liveExit.status == .parked {
            return "checkout.detail.awaiting_checkout_complete".localized
        }
        return "checkout.detail.awaiting_checkin".localized
    }

    private var rentalContextCardVisible: Bool {
        !liveExit.customerFullName.isEmpty
            || !(liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || rentalContextNotes != nil
            || computedRentalDays != nil
            || rentalSnapshot?.hasDisplayContent == true
            || liveExit.plannedReturnAt != nil
    }

    private var rentalContextRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let customer = liveExit.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customer.isEmpty {
            rows.append(("Customer".localized, customer))
        }
        let email = (liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            rows.append(("Email".localized, email))
        }
        if let days = computedRentalDays {
            rows.append((
                "wheelsys.checkout.rental_days".localized,
                String(format: "wheelsys.return.rental_days_value".localized, days)
            ))
        }
        if let label = rentalSnapshot?.insuranceLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            rows.append(("wheelsys.return.insurance_title".localized, label))
        }
        if let charge = rentalSnapshot?.insuranceCharge?.trimmingCharacters(in: .whitespacesAndNewlines),
           !charge.isEmpty {
            rows.append(("wheelsys.return.insurance_charge".localized, charge))
        }
        if let excess = rentalSnapshot?.insuranceExcess?.trimmingCharacters(in: .whitespacesAndNewlines),
           !excess.isEmpty {
            rows.append(("wheelsys.return.insurance_excess".localized, excess))
        }
        let checkoutText = rentalSnapshot?.checkoutAtText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? liveExit.exitTarihi.formatted(date: .abbreviated, time: .shortened)
        rows.append(("checkout.detail.checkout_at".localized, checkoutText))
        if let planned = rentalSnapshot?.plannedCheckinText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !planned.isEmpty {
            rows.append(("checkout.detail.planned_checkin".localized, planned))
        } else if let pr = liveExit.plannedReturnAt {
            rows.append((
                "checkout.detail.planned_checkin".localized,
                pr.formatted(date: .abbreviated, time: .shortened)
            ))
        }
        rows.append(("checkout.detail.checkin_status".localized, checkinStatusLabel))
        rows.append(("checkout.detail.checkout_status".localized, statusLabel))
        return rows
    }

    @ViewBuilder
    private var rentalContextCard: some View {
        if palantirOps {
            PalantirProcessDetailInfoSection(
                title: "checkout.detail.rental_context".localized,
                icon: "doc.text.magnifyingglass",
                rows: rentalContextRows
            )
        } else {
            legacyRentalContextCard
        }
        if let notes = rentalContextNotes {
            if palantirOps {
                PalantirProcessDetailInfoSection(
                    title: "Notes".localized,
                    icon: "note.text",
                    rows: [(label: "", value: notes)]
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Notes".localized)
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                }
            }
        }
    }

    private var legacyRentalContextCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("checkout.detail.rental_context".localized)
            VStack(spacing: 0) {
                ForEach(Array(rentalContextRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().padding(.leading, 50)
                    }
                    infoRow(
                        icon: rentalContextIcon(for: row.label),
                        color: rentalContextColor(for: row.label),
                        label: row.label,
                        value: row.value
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    private func rentalContextIcon(for label: String) -> String {
        if label == "Customer".localized { return "person.fill" }
        if label == "Email".localized { return "envelope.fill" }
        if label == "wheelsys.checkout.rental_days".localized { return "calendar" }
        if label == "wheelsys.return.insurance_title".localized { return "shield.fill" }
        if label == "checkout.detail.checkout_at".localized { return "arrow.right.circle.fill" }
        if label == "checkout.detail.planned_checkin".localized { return "arrow.down.circle.fill" }
        if label == "checkout.detail.checkin_status".localized { return "checkmark.circle" }
        return "info.circle.fill"
    }

    private func rentalContextColor(for label: String) -> Color {
        if label == "wheelsys.return.insurance_title".localized { return .indigo }
        if label == "checkout.detail.checkout_at".localized { return .blue }
        if label == "checkout.detail.planned_checkin".localized { return .teal }
        if label == "checkout.detail.checkin_status".localized { return .orange }
        return .secondary
    }

    private func operationIdentityBanner(arac: Arac) -> some View {
        OperationIdentityLinkRow(
            plate: liveExit.aracPlaka,
            reservationCode: liveExit.resKodu.isEmpty ? nil : liveExit.resKodu,
            reservationLabel: isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
            vehicle: arac,
            exit: liveExit,
            plateInteractive: true,
            codeInteractive: false
        )
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
            ("Plate".localized, liveExit.aracPlaka),
            ("Process Date".localized, liveExit.exitTarihi.formatted(date: .long, time: .shortened)),
        ]
        if !liveExit.resKodu.isEmpty {
            rows.append((
                isTurkeyFranchise ? "NAV Code".localized : "RES Code".localized,
                liveExit.resKodu
            ))
        }
        if let km = liveExit.km {
            rows.append(("KM".localized, "\(km) km"))
        }
        if let y = liveExit.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
            rows.append(("Fuel level".localized, y))
        }
        if let pu = (liveExit.pickUpBranch ?? liveExit.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
            rows.append(("operations.pickup_branch".localized, pu))
        }
        if let pd = liveExit.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
            rows.append(("operations.dropoff_branch".localized, pd))
        }
        if let pr = liveExit.plannedReturnAt {
            rows.append(("operations.planned_return".localized, pr.formatted(date: .abbreviated, time: .shortened)))
        }
        return rows
    }

    private var legacyVehicleInfoCard: some View {
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
            title: "CUSTOMER & CHECK OUT CONTEXT".localized,
            icon: "person.text.rectangle"
        ) {
            Button {
                HapticManager.shared.light()
                showCustomerSheet = true
            } label: {
                HStack(spacing: 12) {
                    PalantirOpsIconTile(systemName: "person.fill", tint: PalantirTheme.accent, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveExit.customerFullName.isEmpty ? "Customer".localized : liveExit.customerFullName)
                            .font(PalantirTheme.bodyFont(14))
                            .foregroundStyle(PalantirTheme.textPrimary)
                            .lineLimit(2)
                        let email = (liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(email.isEmpty ? "No email provided".localized : email)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(1)
                        if isTurkeyFranchise, !liveExit.testDriverFullName.isEmpty {
                            Text("\("operations.test_driver_label".localized): \(liveExit.testDriverFullName)")
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
                        urlString: url,
                        label: ProcessPhotoStampLabels.processPhotoIndexLabel(index),
                        dateText: ProcessPhotoStampLabels.formatDisplayDate(
                            liveExit.exitTarihi,
                            includeTime: false
                        ),
                        timeText: isGermanyFranchise
                            ? ProcessPhotoStampLabels.formatPDFTime(liveExit.exitTarihi)
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

    // MARK: - PDF Button (blue)

    @ViewBuilder
    private var pdfButton: some View {
        if palantirOps {
            WheelSysPalantirPrimaryButton(
                title: pdfOlusturuluyor ? "Generating PDF...".localized : "Generate PDF".localized,
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
        .disabled(pdfOlusturuluyor || emailSend.isActive)
        .opacity(emailSend.isActive ? 0.6 : 1)
    }

    private var emailButton: some View {
        CustomerEmailSendButton(
            title: hasEmailBeenSentBefore ? "Resend Check Out Email".localized : "Send Check Out Email".localized,
            sendingTitle: "Sending Email...".localized,
            accentColor: .blue,
            isSending: emailSend.isActive,
            isExternallyDisabled: pdfOlusturuluyor
        ) {
            sendCheckoutEmail(forceResend: hasEmailBeenSentBefore)
        }
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

    // MARK: - Delete Button

    @ViewBuilder
    private var deleteButton: some View {
        if palantirOps {
            PalantirOpsActionButton(
                title: "Delete Check Out Record".localized,
                icon: "trash.fill",
                style: .destructive,
                disabled: emailSend.isActive
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
                Text("Delete Check Out Record".localized).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.red)
            .padding(.vertical, 15)
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(emailSend.isActive)
        .opacity(emailSend.isActive ? 0.5 : 1)
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

    private func sendCheckoutEmail(forceResend: Bool = false) {
        guard !emailSend.isActive else { return }
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

        let photoCount = PdfEmailImageCompressor.cappedPhotoURLs(liveExit.fotograflar).count
        emailSend.beginSending(photoSummary: String(
            format: NSLocalizedString("%d photos in report", comment: "email checkout"),
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
                        emailKind: .checkoutConfirmation,
                        vehiclePlate: self.liveExit.aracPlaka,
                        recipient: recipient
                    )
                }
                return
            }

            ExitPDFGenerator.shared.generateExitPDF(
                exit: self.liveExit,
                arac: arac,
                franchiseDisplayName: TurkeyFranchiseMetadata.commercialTitle(
                    franchiseDisplayName: self.viewModel.franchiseName,
                    turkeyLocationBranches: self.viewModel.turkeyFranchiseLocationBranches
                ),
                staffSignerNameFallback: self.authManager.userProfile?.fullName,
                language: .automatic,
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
                    self.finishEmailFlow(success: false, message: "PDF generation failed.".localized)
                    return
                }
                    DispatchQueue.main.async {
                        self.emailSend.updateProgress(0.42, message: "Uploading PDF to server…".localized)
                    }
                let franchiseId = self.resolvedEmailFranchiseId()
                let fileName = "\(self.liveExit.id.uuidString).pdf"
                self.uploadCheckoutPDFWithRetry(data: data, franchiseId: franchiseId, fileName: fileName) { uploadedPDFURL in
                    let pdfRef = uploadedPDFURL ?? ""
                    guard !pdfRef.isEmpty else {
                        self.finishEmailFlow(success: false, message: "PDF upload failed.".localized)
                        return
                    }
                    DispatchQueue.main.async {
                        self.emailSend.updateProgress(0.62, message: "Queueing email…".localized)
                    }
                    let subject = self.checkoutEmailSubject()
                    let body = ExitPDFGenerator.checkoutConfirmationText(
                        franchiseId: self.liveExit.franchiseId,
                        franchiseDisplayName: self.isGermanyFranchise
                            ? SwissReportPDFTemplate.germanyDisplayName(
                                franchiseId: self.liveExit.franchiseId,
                                explicit: nil
                            )
                            : self.viewModel.franchiseName
                    )

                    if self.isTurkeyFranchise {
                        let rawTermsURL = (self.liveExit.trRentalTermsSignatureURL ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let termsURLForQueue: String? = !rawTermsURL.isEmpty ? rawTermsURL : nil
                        let termsLangForQueue: String? = self.liveExit.trRentalTermsLanguage?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if termsURLForQueue == nil {
                            ToastManager.shared.show(
                                "GRT PDF not on file — sending checkout PDF only.".localized,
                                type: .warning
                            )
                        }
                        FirebaseService.shared.queueReturnEmail(
                            to: recipient,
                            subject: subject,
                            body: body,
                            pdfURL: pdfRef,
                            returnId: self.liveExit.id.uuidString,
                            vehiclePlate: self.liveExit.aracPlaka,
                            signerName: self.liveExit.customerFullName,
                            signerEmail: recipient,
                            forceResend: forceResend,
                            pdfURLs: nil,
                            vehiclePdfURL: pdfRef,
                            rentalTermsPdfURL: termsURLForQueue,
                            rentalTermsLanguageCode: termsLangForQueue,
                            emailSubjectBranchName: self.turkeyEmailSubjectBranchName(),
                            idempotencyKeySuffix: "|checkout",
                            franchiseId: franchiseId
                        ) { error, queuedPaths in
                            self.handleCheckoutEmailQueued(
                                error: error,
                                queuedPaths: queuedPaths,
                                forceResend: forceResend,
                                recipient: recipient,
                                franchiseId: franchiseId,
                                pdfRef: pdfRef,
                                subject: subject,
                                body: body
                            )
                        }
                        return
                    }

                    FirebaseService.shared.queueCheckoutEmail(
                        to: recipient,
                        subject: subject,
                        body: body,
                        pdfURL: pdfRef,
                        checkoutId: self.liveExit.id.uuidString,
                        vehiclePlate: self.liveExit.aracPlaka,
                        signerName: self.liveExit.customerFullName,
                        signerEmail: recipient,
                        forceResend: true,
                        emailSubjectBranchName: nil,
                        idempotencyKeySuffix: "",
                        franchiseId: franchiseId
                    ) { error, queuedPaths in
                        self.handleCheckoutEmailQueued(
                            error: error,
                            queuedPaths: queuedPaths,
                            forceResend: true,
                            recipient: recipient,
                            franchiseId: franchiseId,
                            pdfRef: pdfRef,
                            subject: subject,
                            body: body
                        )
                    }
                }
            }
        }
    }

    private func handleCheckoutEmailQueued(
        error: Error?,
        queuedPaths: [String],
        forceResend: Bool,
        recipient: String,
        franchiseId: String,
        pdfRef: String,
        subject: String,
        body: String,
        didRetryDuplicate: Bool = false
    ) {
        if let error {
            print("❌ Queue error: \(error.localizedDescription)")
            finishEmailFlow(success: false, message: "Email queue failed.".localized)
            return
        }
        guard let documentPath = queuedPaths.first else {
            finishEmailFlow(success: false, message: "Email queue path missing.".localized)
            return
        }
        DispatchQueue.main.async {
            self.emailSend.updateProgress(0.78, message: "Sending via SMTP…".localized)
            self.emailSend.observeQueuedEmailStatus(documentPath: documentPath, timeout: 120, usePolling: false) { status in
            switch status {
            case "sent":
                finishEmailFlow(success: true, message: "Email delivered.".localized)
            case "duplicate_skipped":
                if !didRetryDuplicate {
                    DispatchQueue.main.async {
                        self.emailSend.updateProgress(self.emailSend.progress, message: "Retrying send…".localized)
                    }
                    if isTurkeyFranchise {
                        FirebaseService.shared.queueReturnEmail(
                            to: recipient,
                            subject: subject,
                            body: body,
                            pdfURL: pdfRef,
                            returnId: liveExit.id.uuidString,
                            vehiclePlate: liveExit.aracPlaka,
                            signerName: liveExit.customerFullName,
                            signerEmail: recipient,
                            forceResend: true,
                            pdfURLs: nil,
                            vehiclePdfURL: pdfRef,
                            rentalTermsPdfURL: nil,
                            rentalTermsLanguageCode: nil,
                            emailSubjectBranchName: turkeyEmailSubjectBranchName(),
                            idempotencyKeySuffix: "|checkout|retry",
                            franchiseId: franchiseId
                        ) { err, paths in
                            handleCheckoutEmailQueued(
                                error: err,
                                queuedPaths: paths,
                                forceResend: true,
                                recipient: recipient,
                                franchiseId: franchiseId,
                                pdfRef: pdfRef,
                                subject: subject,
                                body: body,
                                didRetryDuplicate: true
                            )
                        }
                    } else {
                        FirebaseService.shared.queueCheckoutEmail(
                            to: recipient,
                            subject: subject,
                            body: body,
                            pdfURL: pdfRef,
                            checkoutId: liveExit.id.uuidString,
                            vehiclePlate: liveExit.aracPlaka,
                            signerName: liveExit.customerFullName,
                            signerEmail: recipient,
                            forceResend: true,
                            emailSubjectBranchName: nil,
                            idempotencyKeySuffix: "|retry",
                            franchiseId: franchiseId
                        ) { err, paths in
                            handleCheckoutEmailQueued(
                                error: err,
                                queuedPaths: paths,
                                forceResend: true,
                                recipient: recipient,
                                franchiseId: franchiseId,
                                pdfRef: pdfRef,
                                subject: subject,
                                body: body,
                                didRetryDuplicate: true
                            )
                        }
                    }
                } else {
                    finishEmailFlow(
                        success: false,
                        message: "Email was skipped as duplicate. Tap Resend to try again.".localized
                    )
                }
            case "failed":
                finishEmailFlow(success: false, message: "Email sending failed.".localized)
            default:
                finishEmailFlow(success: false, message: "Email is still processing in background.".localized)
            }
            }
        }
    }

    private func resolvedEmailFranchiseId() -> String {
        let fromExit = liveExit.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !fromExit.isEmpty, fromExit.hasPrefix("DE") || fromExit.hasPrefix("TR") || fromExit.hasPrefix("CH") {
            return fromExit
        }
        return FirebaseService.shared.currentFranchiseId
    }

    private func uploadCheckoutPDFWithRetry(
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
            subfolder: "checkout_pdfs",
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
                self.uploadCheckoutPDFWithRetry(
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
            if success {
                var updated = self.liveExit
                updated.checkoutEmailSentAt = Date()
                updated.checkoutEmailLastStatus = "sent"
                updated.checkoutEmailRecipient = (self.liveExit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.viewModel.exitGuncelle(updated)
            } else {
                var updated = self.liveExit
                updated.checkoutEmailLastStatus = "failed"
                self.viewModel.exitGuncelle(updated)
            }
            self.emailSend.completeSending(
                success: success,
                message: success ? "Email delivered.".localized : message,
                failureToast: success ? nil : message,
                emailKind: .checkoutConfirmation,
                vehiclePlate: self.liveExit.aracPlaka,
                recipient: self.liveExit.customerEmail
            )
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
