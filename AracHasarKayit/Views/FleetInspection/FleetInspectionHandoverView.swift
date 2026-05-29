import SwiftUI

/// Premium handover / return inspection dashboard (Switzerland fleet UX).
enum FleetInspectionPresentationMode {
    case fullDashboard
    case overviewOnly
}

struct FleetInspectionHandoverView: View {
    let context: FleetInspectionContext
    var mode: FleetInspectionPresentationMode = .fullDashboard
    var initialTab: FleetInspectionTab = .overview
    var onGeneratePDF: (() -> Void)?
    var onUploadPhotos: (() -> Void)?
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var selectedTab: FleetInspectionTab
    @State private var compareMode = true
    @State private var damageFilter = "All"
    @State private var isGeneratingPDF = false
    @State private var pdfShareURL: URL?
    @State private var showPDFShare = false
    @State private var showAddDamage = false
    @State private var showSavedToast = false

    init(
        context: FleetInspectionContext,
        mode: FleetInspectionPresentationMode = .fullDashboard,
        initialTab: FleetInspectionTab = .overview,
        onGeneratePDF: (() -> Void)? = nil,
        onUploadPhotos: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.context = context
        self.mode = mode
        self.initialTab = initialTab
        self.onGeneratePDF = onGeneratePDF
        self.onUploadPhotos = onUploadPhotos
        self.onSave = onSave
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if mode == .overviewOnly {
                overviewScroll
            } else {
                fullDashboard
            }
        }
    }

    private var overviewScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                reservationCard
                vehicleIdentityCard
                mainComparisonPanels
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(FleetInspectionTheme.background)
    }

    private var fullDashboard: some View {
        NavigationStack {
            ZStack {
                FleetInspectionTheme.background.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        tabBar
                        tabContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FleetInspectionTheme.value)
                    }
                }
            }
            .toolbarBackground(FleetInspectionTheme.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showPDFShare) {
                if let url = pdfShareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showAddDamage) {
                if let arac = context.vehicle {
                    NavigationStack {
                        HasarEkleView(aracId: arac.id) { _ in showAddDamage = false }
                            .environmentObject(viewModel)
                            .environmentObject(authManager)
                    }
                }
            }
            .overlay(alignment: .top) {
                if showSavedToast {
                    Text("fleet_inspection.saved".localized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(FleetInspectionTheme.accent))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("fleet_inspection.title".localized)
                        .font(FleetInspectionTheme.title(22))
                        .foregroundStyle(FleetInspectionTheme.value)
                    Text(context.branchName)
                        .font(FleetInspectionTheme.body(12))
                        .foregroundStyle(FleetInspectionTheme.label)
                }
                Spacer()
                statusBadge(context.reservationStatus)
            }

            HStack(spacing: 8) {
                headerAction("fleet_inspection.action_pdf".localized, icon: "doc.richtext") {
                    if let onGeneratePDF { onGeneratePDF() } else { generateAndSharePDF() }
                }
                headerAction("fleet_inspection.action_upload".localized, icon: "photo.on.rectangle.angled") {
                    if let onUploadPhotos { onUploadPhotos() } else if context.vehicle != nil { showAddDamage = true }
                }
                headerAction("fleet_inspection.action_compare".localized, icon: "arrow.left.arrow.right") { compareMode.toggle() }
                headerAction("fleet_inspection.action_save".localized, icon: "square.and.arrow.down") {
                    if let onSave { onSave() } else { markInspectionSaved() }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                metaLine("fleet_inspection.meta_branch".localized, context.branchName)
                metaLine("fleet_inspection.meta_operator".localized, context.operatorName)
                metaLine("fleet_inspection.meta_id".localized, context.inspectionId, mono: true)
                metaLine("fleet_inspection.meta_time".localized, context.timestampFormatted, mono: true)
            }
            .padding(12)
            .background(cardBackground)
        }
        .padding(.top, 8)
    }

    private func headerAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(FleetInspectionTheme.value)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(FleetInspectionTheme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FleetInspectionTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func metaLine(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(FleetInspectionTheme.body(10))
                .foregroundStyle(FleetInspectionTheme.label)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(mono ? FleetInspectionTheme.mono(10) : FleetInspectionTheme.body(10, weight: .medium))
                .foregroundStyle(FleetInspectionTheme.value)
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FleetInspectionTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        Text(tab.titleKey.localized)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? Color.black : FleetInspectionTheme.label)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selectedTab == tab ? FleetInspectionTheme.accent : FleetInspectionTheme.cardElevated)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            reservationCard
            vehicleIdentityCard
            mainComparisonPanels
        case .photos:
            mainComparisonPanels
            photoGridSection
        case .damage:
            damageComparisonSection
        case .timeline:
            timelineSection
        case .pdf:
            signatureSection
            pdfPreviewSection
        }
    }

    // MARK: - Cards

    private var reservationCard: some View {
        sectionCard(title: "fleet_inspection.reservation_title".localized) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                field("fleet_inspection.res_code".localized, context.reservationCode, mono: true)
                field("fleet_inspection.agreement".localized, context.rentalAgreementNumber, mono: true)
                field("fleet_inspection.customer".localized, context.customerName)
                field("fleet_inspection.email".localized, context.customerEmail)
                field("fleet_inspection.phone".localized, context.customerPhone)
                field("fleet_inspection.rental_status".localized, context.rentalStatus)
                field("fleet_inspection.pickup_branch".localized, context.pickupBranch)
                field("fleet_inspection.return_branch".localized, context.returnBranch)
                field("fleet_inspection.payment".localized, context.paymentStatus)
                field("fleet_inspection.deposit".localized, context.depositStatus)
            }
        }
    }

    private var vehicleIdentityCard: some View {
        sectionCard(title: "fleet_inspection.vehicle_title".localized) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(context.vehicleBrand) \(context.vehicleModel)")
                    .font(FleetInspectionTheme.title(20))
                    .foregroundStyle(FleetInspectionTheme.value)
                Text(context.licensePlate)
                    .font(FleetInspectionTheme.mono(22, weight: .bold))
                    .foregroundStyle(FleetInspectionTheme.accent)
                if !context.vehicleGroup.isEmpty {
                    Text(context.vehicleGroup)
                        .font(FleetInspectionTheme.body(12))
                        .foregroundStyle(FleetInspectionTheme.label)
                }
                Divider().background(FleetInspectionTheme.border)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    field("fleet_inspection.year".localized, context.vehicleYear)
                    field("fleet_inspection.vin".localized, context.vin, mono: true)
                    field("fleet_inspection.fuel".localized, context.fuelType)
                    field("fleet_inspection.transmission".localized, context.transmission)
                    field("fleet_inspection.color".localized, context.color)
                    field("fleet_inspection.km_handover".localized, context.mileageHandover)
                    field("fleet_inspection.km_return".localized, context.mileageReturn)
                    field("fleet_inspection.fuel_handover".localized, context.fuelHandover)
                    field("fleet_inspection.fuel_return".localized, context.fuelReturn)
                }
            }
        }
    }

    private var mainComparisonPanels: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                inspectionPanel(
                    title: "fleet_inspection.handover_title".localized,
                    subtitle: "fleet_inspection.handover_sub".localized,
                    date: context.handoverDate,
                    time: context.handoverTime,
                    operatorName: context.handoverOperator,
                    mileage: context.mileageHandover,
                    fuel: context.fuelHandover,
                    badge: context.handoverStatus,
                    badgeColor: FleetInspectionTheme.clearGreen,
                    overlay: context.handoverOverlayLabel,
                    image: context.handoverHeroImage
                )
                inspectionPanel(
                    title: "fleet_inspection.return_title".localized,
                    subtitle: "fleet_inspection.return_sub".localized,
                    date: context.returnDate,
                    time: context.returnTime,
                    operatorName: context.returnOperator,
                    mileage: context.mileageReturn,
                    fuel: context.fuelReturn,
                    badge: context.returnStatus,
                    badgeColor: context.returnStatusColor,
                    overlay: context.returnOverlayLabel,
                    image: context.returnHeroImage
                )
            }
        }
    }

    private func inspectionPanel(
        title: String,
        subtitle: String,
        date: String,
        time: String,
        operatorName: String,
        mileage: String,
        fuel: String,
        badge: String,
        badgeColor: Color,
        overlay: String,
        image: UIImage?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(FleetInspectionTheme.title(14))
                .foregroundStyle(FleetInspectionTheme.value)
            Text(subtitle)
                .font(FleetInspectionTheme.body(10))
                .foregroundStyle(FleetInspectionTheme.label)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                miniRow("fleet_inspection.date".localized, "\(date) · \(time)")
                miniRow("fleet_inspection.operator".localized, operatorName)
                miniRow("fleet_inspection.mileage".localized, mileage)
                miniRow("fleet_inspection.fuel".localized, fuel)
            }

            statusBadge(badge, color: badgeColor)

            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(FleetInspectionTheme.cardElevated)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(FleetInspectionTheme.label)
                            )
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(overlay)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var photoGridSection: some View {
        sectionCard(title: "fleet_inspection.photo_grid_title".localized) {
            VStack(spacing: 10) {
                ForEach(context.photoSlots) { slot in
                    photoSlotRow(slot)
                }
            }
        }
    }

    private func photoSlotRow(_ slot: FleetInspectionPhotoSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.label)
                    .font(FleetInspectionTheme.body(12, weight: .semibold))
                    .foregroundStyle(FleetInspectionTheme.value)
                Spacer()
                comparisonBadge(slot.comparisonStatus)
            }
            HStack(spacing: 8) {
                photoThumb(slot.handoverImage, label: "HO")
                photoThumb(slot.returnImage, label: "RT")
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.timestamp)
                        .font(FleetInspectionTheme.mono(9))
                        .foregroundStyle(FleetInspectionTheme.label)
                    Text(slot.deviceId)
                        .font(FleetInspectionTheme.mono(8))
                        .foregroundStyle(FleetInspectionTheme.label.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(10)
        .background(FleetInspectionTheme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func photoThumb(_ image: UIImage?, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(width: 72, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
        }
    }

    private var damageComparisonSection: some View {
        let rows = context.damageRows
        return sectionCard(title: "fleet_inspection.damage_title".localized) {
            if rows.isEmpty {
                Text("fleet_inspection.no_damage".localized)
                    .font(FleetInspectionTheme.body(12))
                    .foregroundStyle(FleetInspectionTheme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    damageTableHeader
                    ForEach(rows) { row in
                        damageTableRow(row)
                        Divider().background(FleetInspectionTheme.border)
                    }
                }
            }
        }
    }

    private var damageTableHeader: some View {
        HStack(spacing: 4) {
            ForEach(["Area", "HO", "RT", "Diff", "Sev", "Cost", "", "Decision"], id: \.self) { h in
                Text(h)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(FleetInspectionTheme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    private func damageTableRow(_ row: FleetInspectionDamageRow) -> some View {
        HStack(spacing: 4) {
            Text(row.area).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.handoverStatus).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.returnStatus).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.difference).foregroundStyle(row.differenceColor).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.severity).frame(maxWidth: .infinity, alignment: .leading)
            Text(row.cost).font(FleetInspectionTheme.mono(8)).frame(maxWidth: .infinity, alignment: .leading)
            Text("View").font(.system(size: 8, weight: .semibold)).foregroundStyle(FleetInspectionTheme.accentBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.decision).font(.system(size: 8, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 8))
        .foregroundStyle(FleetInspectionTheme.value.opacity(0.9))
        .padding(.vertical, 8)
    }

    private var timelineSection: some View {
        sectionCard(title: "fleet_inspection.timeline_title".localized) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(context.timelineSteps.enumerated()), id: \.element.id) { index, step in
                    if context.showsRentalFlowAnimation,
                       step.title == "Return inspection",
                       index > 0 {
                        FleetRentalTimelineConnector(isActive: true, axis: .vertical)
                            .padding(.leading, 0)
                            .padding(.vertical, 4)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(step.isComplete ? FleetInspectionTheme.clearGreen : FleetInspectionTheme.cardElevated)
                                .frame(width: 10, height: 10)
                            if index < context.timelineSteps.count - 1 {
                                Rectangle()
                                    .fill(step.isComplete ? FleetInspectionTheme.clearGreen.opacity(0.6) : FleetInspectionTheme.border)
                                    .frame(width: 2, height: 36)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(FleetInspectionTheme.body(12, weight: .semibold))
                                .foregroundStyle(FleetInspectionTheme.value)
                            Text("\(step.date) · \(step.time) · \(step.actor)")
                                .font(FleetInspectionTheme.mono(9))
                                .foregroundStyle(FleetInspectionTheme.label)
                            statusBadge(step.status, color: step.statusColor)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var signatureSection: some View {
        HStack(spacing: 12) {
            signatureCard(
                title: "fleet_inspection.sig_customer".localized,
                name: context.customerName,
                date: context.handoverDate
            )
            signatureCard(
                title: "fleet_inspection.sig_staff".localized,
                name: context.returnOperator,
                date: context.returnDate
            )
        }
    }

    private func signatureCard(title: String, name: String, date: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FleetInspectionTheme.body(11, weight: .bold))
                .foregroundStyle(FleetInspectionTheme.value)
            Text(name)
                .font(FleetInspectionTheme.body(12))
                .foregroundStyle(FleetInspectionTheme.label)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(FleetInspectionTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(height: 56)
                .overlay(
                    Image(systemName: "signature")
                        .foregroundStyle(FleetInspectionTheme.label)
                )
            Text("fleet_inspection.sig_confirm".localized)
                .font(.system(size: 8))
                .foregroundStyle(FleetInspectionTheme.label)
            Text(date)
                .font(FleetInspectionTheme.mono(9))
                .foregroundStyle(FleetInspectionTheme.label)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var pdfPreviewSection: some View {
        sectionCard(title: "fleet_inspection.pdf_preview".localized) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FleetInspectionTheme.cardElevated)
                        .frame(width: 80, height: 110)
                        .overlay(Image(systemName: "doc.fill").foregroundStyle(FleetInspectionTheme.accent))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.licensePlate)
                            .font(FleetInspectionTheme.mono(14, weight: .bold))
                        Text(context.reservationCode)
                            .font(FleetInspectionTheme.mono(11))
                            .foregroundStyle(FleetInspectionTheme.label)
                        Text("fleet_inspection.damage_count".localized + " \(context.vehicleDamages.count)")
                            .font(FleetInspectionTheme.body(11))
                            .foregroundStyle(FleetInspectionTheme.label)
                        Text("fleet_inspection.cloud_id".localized + " " + context.inspectionId)
                            .font(FleetInspectionTheme.mono(9))
                            .foregroundStyle(FleetInspectionTheme.label)
                    }
                    Spacer()
                }
                Button {
                    generateAndSharePDF()
                } label: {
                    HStack {
                        if isGeneratingPDF { ProgressView().tint(.white) }
                        Text("fleet_inspection.generate_pdf".localized)
                            .font(FleetInspectionTheme.body(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(FleetInspectionTheme.accent))
                }
                .disabled(isGeneratingPDF || context.vehicle == nil)
            }
        }
    }

    private func generateAndSharePDF() {
        guard let arac = context.vehicle, !isGeneratingPDF else { return }
        isGeneratingPDF = true
        let damages = context.vehicleDamages
        let ctx = context
        DispatchQueue.global(qos: .userInitiated).async {
            let data = FleetInspectionReportPDF.render(context: ctx, arac: arac, damages: damages)
            DispatchQueue.main.async {
                isGeneratingPDF = false
                guard !data.isEmpty else { return }
                let name = "FleetInspection-\(arac.plaka)-\(ctx.inspectionId).pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: url)
                pdfShareURL = url
                showPDFShare = true
            }
        }
    }

    private func markInspectionSaved() {
        let key = "fleet.inspection.saved.\(context.inspectionId)"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        withAnimation { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedToast = false }
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(FleetInspectionTheme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FleetInspectionTheme.border, lineWidth: 1))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(FleetInspectionTheme.title(16))
                .foregroundStyle(FleetInspectionTheme.value)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func field(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FleetInspectionTheme.body(9))
                .foregroundStyle(FleetInspectionTheme.label)
            Text(value.isEmpty ? "—" : value)
                .font(mono ? FleetInspectionTheme.mono(11, weight: .semibold) : FleetInspectionTheme.body(11, weight: .semibold))
                .foregroundStyle(FleetInspectionTheme.value)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(FleetInspectionTheme.body(9))
                .foregroundStyle(FleetInspectionTheme.label)
            Spacer()
            Text(value)
                .font(FleetInspectionTheme.body(9, weight: .medium))
                .foregroundStyle(FleetInspectionTheme.value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusBadge(_ text: String, color: Color = FleetInspectionTheme.accent) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func comparisonBadge(_ status: FleetPhotoComparisonStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .match: return ("No Change", FleetInspectionTheme.clearGreen)
            case .review: return ("Needs Review", FleetInspectionTheme.reviewAmber)
            case .newDamage: return ("New Damage", FleetInspectionTheme.damageRed)
            case .missing: return ("Missing", FleetInspectionTheme.missingGray)
            }
        }()
        return statusBadge(text, color: color)
    }
}

// MARK: - Models

enum FleetInspectionTab: String, CaseIterable, Identifiable {
    case overview, photos, damage, timeline, pdf
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .overview: return "fleet_inspection.tab_overview"
        case .photos: return "fleet_inspection.tab_photos"
        case .damage: return "fleet_inspection.tab_damage"
        case .timeline: return "fleet_inspection.tab_timeline"
        case .pdf: return "fleet_inspection.tab_pdf"
        }
    }
}

enum FleetPhotoComparisonStatus {
    case match, review, newDamage, missing
}

struct FleetInspectionPhotoSlot: Identifiable {
    let id = UUID()
    let label: String
    let handoverImage: UIImage?
    let returnImage: UIImage?
    let comparisonStatus: FleetPhotoComparisonStatus
    let timestamp: String
    let deviceId: String
}

struct FleetInspectionDamageRow: Identifiable {
    let id = UUID()
    let area: String
    let handoverStatus: String
    let returnStatus: String
    let difference: String
    let differenceColor: Color
    let severity: String
    let cost: String
    let decision: String
}

struct FleetInspectionTimelineStep: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let time: String
    let actor: String
    let status: String
    let statusColor: Color
    let isComplete: Bool
}

struct FleetInspectionContext {
    let branchName: String
    let operatorName: String
    let inspectionId: String
    let timestampFormatted: String
    let reservationStatus: String
    let reservationCode: String
    let rentalAgreementNumber: String
    let customerName: String
    let customerEmail: String
    let customerPhone: String
    let pickupBranch: String
    let returnBranch: String
    let rentalStatus: String
    let paymentStatus: String
    let depositStatus: String
    let vehicleBrand: String
    let vehicleModel: String
    let licensePlate: String
    let vehicleGroup: String
    let vehicleYear: String
    let vin: String
    let fuelType: String
    let transmission: String
    let color: String
    let mileageHandover: String
    let mileageReturn: String
    let fuelHandover: String
    let fuelReturn: String
    let handoverDate: String
    let handoverTime: String
    let handoverOperator: String
    let handoverStatus: String
    let handoverOverlayLabel: String
    let handoverHeroImage: UIImage?
    let returnDate: String
    let returnTime: String
    let returnOperator: String
    let returnStatus: String
    let returnStatusColor: Color
    let returnOverlayLabel: String
    let returnHeroImage: UIImage?
    let photoSlots: [FleetInspectionPhotoSlot]
    let damageRows: [FleetInspectionDamageRow]
    let timelineSteps: [FleetInspectionTimelineStep]
    let vehicle: Arac?
    let vehicleDamages: [HasarKaydi]
    /// When true, animates flow from check-out toward pending return (timeline LED).
    var showsRentalFlowAnimation: Bool = false

    static func fromCheckout(
        arac: Arac,
        resKodu: String,
        customerFirstName: String,
        customerLastName: String,
        customerEmail: String,
        exitDate: Date,
        kmText: String,
        fuelLevel: String,
        pickUpBranch: String,
        dropOffBranch: String,
        handoverPhotos: [UIImage],
        operatorName: String
    ) -> FleetInspectionContext {
        let df = DateFormatter()
        df.dateFormat = "dd MMM yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let dateStr = df.string(from: exitDate)
        let timeStr = tf.string(from: exitDate)
        let hero = handoverPhotos.first
        let slots = FleetInspectionContext.defaultPhotoSlots(handover: handoverPhotos, returnPhotos: [])

        return FleetInspectionContext(
            branchName: pickUpBranch.isEmpty ? "Zürich" : pickUpBranch,
            operatorName: operatorName,
            inspectionId: "INSP-\(UUID().uuidString.prefix(8).uppercased())",
            timestampFormatted: "\(dateStr), \(timeStr)",
            reservationStatus: "Active",
            reservationCode: resKodu.isEmpty ? "RES-—" : resKodu,
            rentalAgreementNumber: "—",
            customerName: [customerFirstName, customerLastName].filter { !$0.isEmpty }.joined(separator: " "),
            customerEmail: customerEmail,
            customerPhone: "—",
            pickupBranch: pickUpBranch,
            returnBranch: dropOffBranch,
            rentalStatus: "On Rent",
            paymentStatus: "—",
            depositStatus: "—",
            vehicleBrand: arac.marka,
            vehicleModel: arac.model,
            licensePlate: arac.plaka,
            vehicleGroup: arac.kategori,
            vehicleYear: "—",
            vin: arac.vin ?? "—",
            fuelType: "—",
            transmission: "—",
            color: "—",
            mileageHandover: kmText.isEmpty ? "—" : "\(kmText) km",
            mileageReturn: "—",
            fuelHandover: fuelLevel,
            fuelReturn: "—",
            handoverDate: dateStr,
            handoverTime: timeStr,
            handoverOperator: operatorName,
            handoverStatus: "Customer Accepted",
            handoverOverlayLabel: "HANDOVER — \(dateStr), \(timeStr)",
            handoverHeroImage: hero,
            returnDate: "—",
            returnTime: "—",
            returnOperator: "—",
            returnStatus: "Pending",
            returnStatusColor: FleetInspectionTheme.reviewAmber,
            returnOverlayLabel: "RETURN — pending",
            returnHeroImage: nil,
            photoSlots: slots,
            damageRows: FleetInspectionContext.damageRows(from: arac.hasarKayitlari),
            timelineSteps: FleetInspectionContext.sampleTimeline(handoverDate: dateStr, handoverTime: timeStr, operatorName: operatorName),
            vehicle: arac,
            vehicleDamages: arac.hasarKayitlari.sorted { $0.tarih > $1.tarih },
            showsRentalFlowAnimation: true
        )
    }

    static func damageRows(from damages: [HasarKaydi]) -> [FleetInspectionDamageRow] {
        damages.sorted { $0.tarih > $1.tarih }.map { d in
            let area = d.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? d.damageZone!
                : (d.notlar.isEmpty ? "General" : String(d.notlar.prefix(28)))
            return FleetInspectionDamageRow(
                area: area,
                handoverStatus: d.durum.displayTitle,
                returnStatus: d.status == .completed ? "Logged" : "Open",
                difference: d.durum == .done ? "Closed" : "Active",
                differenceColor: d.durum == .done ? FleetInspectionTheme.clearGreen : FleetInspectionTheme.accent,
                severity: d.damageSeverity ?? "—",
                cost: "—",
                decision: d.durum == .done ? "Done" : "Review"
            )
        }
    }

    static func defaultPhotoSlots(handover: [UIImage], returnPhotos: [UIImage]) -> [FleetInspectionPhotoSlot] {
        let labels = [
            "Front View", "Rear View", "Left Side", "Right Side",
            "Front Left Corner", "Front Right Corner", "Rear Left Corner", "Rear Right Corner",
            "Roof", "Wheels / Rims", "Interior Front", "Interior Rear",
            "Dashboard / Mileage", "Fuel Level", "Existing Damage", "New Damage"
        ]
        return labels.enumerated().map { i, label in
            FleetInspectionPhotoSlot(
                label: label,
                handoverImage: handover.indices.contains(i) ? handover[i] : nil,
                returnImage: returnPhotos.indices.contains(i) ? returnPhotos[i] : nil,
                comparisonStatus: returnPhotos.isEmpty ? (handover.indices.contains(i) ? .match : .missing) : .review,
                timestamp: "—",
                deviceId: "iOS Camera"
            )
        }
    }

    static var sampleDamageRows: [FleetInspectionDamageRow] {
        [
            .init(area: "Front bumper", handoverStatus: "Clear", returnStatus: "Scratch", difference: "New", differenceColor: FleetInspectionTheme.damageRed, severity: "Medium", cost: "CHF 280", decision: "Charge"),
            .init(area: "Rear right rim", handoverStatus: "Scratch", returnStatus: "Same", difference: "None", differenceColor: FleetInspectionTheme.clearGreen, severity: "Low", cost: "CHF 0", decision: "No action"),
            .init(area: "Roof", handoverStatus: "N/A", returnStatus: "Dent", difference: "Review", differenceColor: FleetInspectionTheme.reviewAmber, severity: "High", cost: "CHF 600", decision: "Manager")
        ]
    }

    static func sampleTimeline(handoverDate: String, handoverTime: String, operatorName: String) -> [FleetInspectionTimelineStep] {
        [
            .init(title: "Reservation created", date: handoverDate, time: "09:00", actor: "System", status: "Done", statusColor: FleetInspectionTheme.clearGreen, isComplete: true),
            .init(title: "Vehicle prepared", date: handoverDate, time: "10:15", actor: "Fleet", status: "Done", statusColor: FleetInspectionTheme.clearGreen, isComplete: true),
            .init(title: "Check-out inspection", date: handoverDate, time: handoverTime, actor: operatorName, status: "Complete", statusColor: FleetInspectionTheme.clearGreen, isComplete: true),
            .init(title: "Customer signature", date: handoverDate, time: handoverTime, actor: operatorName, status: "Signed", statusColor: FleetInspectionTheme.clearGreen, isComplete: true),
            .init(title: "Return inspection", date: "—", time: "—", actor: "—", status: "Pending", statusColor: FleetInspectionTheme.accent, isComplete: false),
            .init(title: "PDF report", date: "—", time: "—", actor: "—", status: "Waiting", statusColor: FleetInspectionTheme.missingGray, isComplete: false)
        ]
    }
}
