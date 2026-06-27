import SwiftUI

/// WheelSys "Pre-check-in" review + submit screen. Loads the rental context
/// (customer / vehicle / mileage / insurance / body diagram / existing damages),
/// lets staff confirm the review, then submits the pre-check-in.
///
/// Presented as a sheet from the return flow. Resolution prefers `rentalId`;
/// when absent the backend resolves via `resNo` / `rntNo` / `plateNo`.
struct WheelSysPrecheckinView: View {
    let rentalId: Int?
    let resNo: String?
    let rntNo: String?
    let plateNo: String?
    let date: String?
    var compact: Bool

    init(
        rentalId: Int? = nil,
        resNo: String? = nil,
        rntNo: String? = nil,
        plateNo: String? = nil,
        date: String? = nil,
        compact: Bool = false
    ) {
        self.rentalId = rentalId
        self.resNo = resNo
        self.rntNo = rntNo
        self.plateNo = plateNo
        self.date = date
        self.compact = compact
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var context: WheelSysPrecheckinContext?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewImages: [String: UIImage] = [:]
    @State private var bodyDiagramImage: UIImage?
    @State private var bodyDiagramLoadFailed = false
    @State private var fullScreenImage: WheelSysCHFullScreenImage?

    @State private var confirmCustomer = false
    @State private var confirmVehicle = false
    @State private var confirmDamages = false
    @State private var confirmInsurance = false
    @State private var notes = ""

    @State private var isSubmitting = false
    @State private var submitStatus: String?
    @State private var submitIsError = false
    @State private var submitRetryable = false
    @State private var submitSucceeded = false

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    private var allReviewsConfirmed: Bool {
        confirmCustomer && confirmVehicle && confirmDamages && confirmInsurance
    }

    private var canSubmit: Bool {
        guard let context else { return false }
        return context.canSubmit && allReviewsConfirmed && !isSubmitting && !submitSucceeded
    }

    var body: some View {
        Group {
            if compact {
                content
            } else {
                NavigationStack {
                    content
                        .navigationTitle("wheelsys.precheckin.title".localized)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close".localized) { dismiss() }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    Task { await loadContext(force: true) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(isLoading || isSubmitting)
                            }
                        }
                }
                .wheelSysCHOpsChrome()
            }
        }
        .task {
            await loadContext(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelSysSessionRestored)) { _ in
            Task { await loadContext(force: true) }
        }
        .fullScreenCover(item: $fullScreenImage) { item in
            WheelSysCHImageViewer(image: item.image)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let context {
                    headerSection(context)
                    warningsAndBlockers(context)
                    customerCard(context.customer)
                    vehicleCard(context.vehicle)
                    mileageFuelCard(context.mileageFuel)
                    if let insurance = context.insurance {
                        insuranceCard(insurance)
                    }
                    bodyDiagramCard(context)
                    existingDamagesCard(context)
                    reviewCard(context)
                    Text("wheelsys.damage_history.synced_at".localized + " \(context.syncedAt)")
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else if isLoading {
                    loadingStrip
                } else if let errorMessage {
                    errorStrip(errorMessage)
                }
            }
            .padding(compact ? 0 : 16)
        }
    }

    private func headerSection(_ context: WheelSysPrecheckinContext) -> some View {
        let rental = context.rental
        let rnt = rental.rntNo ?? rental.resNo ?? "#\(rental.rentalId)"
        return WheelSysPalantirOpsHeader(
            title: "wheelsys.precheckin.title".localized,
            subtitle: context.vehicle.plateNo,
            badge: rnt
        )
    }

    private var loadingStrip: some View {
        WheelSysPalantirStatusStrip(
            icon: "arrow.triangle.2.circlepath",
            message: "ch_ops.loading_detail".localized,
            showsSpinner: true
        )
    }

    private func errorStrip(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WheelSysPalantirStatusStrip(
                icon: "exclamationmark.triangle.fill",
                message: message,
                tint: PalantirTheme.critical
            )
            WheelSysPalantirSecondaryButton(
                title: "wheelsys.damage_history.retry".localized,
                icon: "arrow.clockwise"
            ) {
                Task { await loadContext(force: true) }
            }
        }
    }

    // MARK: - Warnings / blockers

    @ViewBuilder
    private func warningsAndBlockers(_ context: WheelSysPrecheckinContext) -> some View {
        let blockers = context.blockers
        let warnings = context.combinedWarnings
        if !blockers.isEmpty || !warnings.isEmpty {
            WheelSysPalantirSectionCard(
                title: "wheelsys.precheckin.warnings_title".localized,
                icon: "exclamationmark.triangle.fill"
            ) {
                ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                    WheelSysPalantirStatusStrip(
                        icon: "xmark.octagon.fill",
                        message: blocker,
                        tint: PalantirTheme.critical
                    )
                }
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    WheelSysPalantirStatusStrip(
                        icon: "exclamationmark.triangle",
                        message: warning,
                        tint: PalantirTheme.warning
                    )
                }
                if let usable = context.carUsability, !usable.isUsable {
                    WheelSysPalantirStatusStrip(
                        icon: "car.fill",
                        message: "wheelsys.precheckin.blocked".localized,
                        tint: PalantirTheme.critical
                    )
                }
            }
        }
    }

    // MARK: - Cards

    private func customerCard(_ customer: WheelSysPrecheckinCustomer) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.customer".localized,
            icon: "person.fill"
        ) {
            WheelSysPalantirDataRow(
                label: "Customer".localized,
                value: customer.fullName,
                monospace: false
            )
            if let email = customer.email, !email.isEmpty {
                WheelSysPalantirDataRow(label: "Email".localized, value: email, monospace: false)
            }
        }
    }

    private func vehicleCard(_ vehicle: WheelSysPrecheckinVehicle) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.vehicle".localized,
            icon: "car.fill"
        ) {
            WheelSysPalantirDataRow(label: "Plate".localized, value: vehicle.plateNo)
            if let model = vehicle.model, !model.isEmpty {
                WheelSysPalantirDataRow(label: "Model".localized, value: model, monospace: false)
            }
            if let booked = vehicle.bookedGroup, !booked.isEmpty {
                WheelSysPalantirDataRow(label: "Booked".localized, value: booked)
            }
            if let charged = vehicle.chargedGroup, !charged.isEmpty {
                WheelSysPalantirDataRow(label: "Charged".localized, value: charged)
            }
        }
    }

    private func mileageFuelCard(_ mf: WheelSysPrecheckinMileageFuel) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.mileage_fuel".localized,
            icon: "gauge.with.dots.needle.50percent"
        ) {
            WheelSysPalantirDataRow(
                label: "wheelsys.return.checkin_km".localized,
                value: mileageText(checkout: mf.checkoutMileage, current: mf.currentReturnMileage)
            )
            WheelSysPalantirDataRow(
                label: "wheelsys.return.checkin_fuel".localized,
                value: fuelText(checkout: mf.checkoutFuel, current: mf.currentReturnFuel)
            )
            if let miles = mf.milesDriven {
                WheelSysPalantirDataRow(label: "Miles".localized, value: "\(miles)")
            }
        }
    }

    private func mileageText(checkout: Int?, current: Int?) -> String {
        let out = checkout.map { "\($0)" } ?? "—"
        let cur = current.map { "\($0)" } ?? "—"
        return "\(out) → \(cur)"
    }

    private func fuelText(checkout: Int?, current: Int?) -> String {
        let out = checkout.map { "\($0)/8" } ?? "—"
        let cur = current.map { "\($0)/8" } ?? "—"
        return "\(out) → \(cur)"
    }

    private func insuranceCard(_ insurance: WheelSysPrecheckinInsurance) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.insurance".localized,
            icon: "shield.lefthalf.filled"
        ) {
            if let excess = insurance.excessAmount {
                WheelSysPalantirDataRow(label: "Excess".localized, value: currencyText(excess, insurance.currency))
            }
            if let cdp = insurance.cdp, !cdp.isEmpty {
                WheelSysPalantirDataRow(label: "CDP", value: cdp)
            }
            if let charge = insurance.insuranceCharge {
                WheelSysPalantirDataRow(label: "Insurance".localized, value: currencyText(charge, insurance.currency))
            }
            if let dmgCharge = insurance.damageCharge {
                WheelSysPalantirDataRow(label: "Damage".localized, value: currencyText(dmgCharge, insurance.currency))
            }
            if let dmgExcess = insurance.damageExcess {
                WheelSysPalantirDataRow(label: "Dmg Excess".localized, value: currencyText(dmgExcess, insurance.currency))
            }
        }
    }

    private func currencyText(_ value: Double, _ currency: String) -> String {
        let rounded = (value * 100).rounded() / 100
        let number: String
        if rounded == rounded.rounded() {
            number = String(format: "%.0f", rounded)
        } else {
            number = String(format: "%.2f", rounded)
        }
        return "\(currency) \(number)"
    }

    // MARK: - Body diagram

    @ViewBuilder
    private func bodyDiagramCard(_ context: WheelSysPrecheckinContext) -> some View {
        if let diagram = context.bodyDiagram, diagram.hasResolvableImage {
            WheelSysPalantirSectionCard(
                title: "wheelsys.precheckin.body_diagram".localized,
                icon: "car.side"
            ) {
                bodyDiagramImageView(diagram, damages: context.existingDamages)
                    .task(id: diagram.imageUrl) {
                        await loadBodyDiagram(diagram)
                    }
            }
        }
    }

    @ViewBuilder
    private func bodyDiagramImageView(
        _ diagram: WheelSysPrecheckinBodyDiagram,
        damages: [WheelSysPrecheckinDamage]
    ) -> some View {
        if let image = bodyDiagramImage {
            GeometryReader { geo in
                let displayWidth = geo.size.width
                let aspect = image.size.height / max(image.size.width, 1)
                let displayHeight = displayWidth * aspect
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displayWidth, height: displayHeight)
                    if let baseW = diagram.width, let baseH = diagram.height,
                       baseW > 0, baseH > 0 {
                        ForEach(damages.filter { $0.position?.hasCoordinates == true }) { damage in
                            if let pos = damage.position, let x = pos.x, let y = pos.y {
                                let mx = CGFloat(x / Double(baseW)) * displayWidth
                                let my = CGFloat(y / Double(baseH)) * displayHeight
                                Circle()
                                    .fill(PalantirTheme.critical.opacity(0.85))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    .position(x: mx, y: my)
                            }
                        }
                    }
                }
                .frame(width: displayWidth, height: displayHeight)
            }
            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        } else if bodyDiagramLoadFailed {
            WheelSysPalantirStatusStrip(
                icon: "photo",
                message: "wheelsys.return.preview_timeout".localized,
                tint: PalantirTheme.textMuted
            )
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: 120)
        }
    }

    // MARK: - Existing damages

    private func existingDamagesCard(_ context: WheelSysPrecheckinContext) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.existing_damages_title".localized,
            icon: "exclamationmark.triangle.fill"
        ) {
            if context.existingDamages.isEmpty {
                WheelSysPalantirStatusStrip(
                    icon: "checkmark.circle",
                    message: "wheelsys.damage_history.empty".localized,
                    tint: PalantirTheme.success
                )
            } else {
                ForEach(context.existingDamages) { damage in
                    damageRow(damage)
                    if damage.id != context.existingDamages.last?.id {
                        WheelSysPalantirInsetDivider()
                    }
                }
            }
        }
    }

    private func damageRow(_ damage: WheelSysPrecheckinDamage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(damage.displayTitle)
                    .font(PalantirTheme.bodyFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer(minLength: 8)
                if let charge = damage.netCharge {
                    Text(currencyText(charge, "CHF"))
                        .font(PalantirTheme.dataFont(12))
                        .foregroundStyle(PalantirTheme.warning)
                }
            }
            if !damage.areaElementText.isEmpty {
                metaRow("Area".localized, damage.areaElementText)
            }
            if let action = damage.actionName, !action.isEmpty {
                metaRow("Action".localized, action)
            }
            if let rental = damage.relatedRentalNo, !rental.isEmpty {
                metaRow("RNT / R.A.", rental)
            }
            if let added = damage.addedByName, !added.isEmpty {
                metaRow("wheelsys.damage_history.added_on".localized, added)
            }
            if let entry = damage.entryDate, !entry.isEmpty {
                metaRow("Date".localized, entry)
            }
            if let memo = damage.memo, !memo.isEmpty {
                Text(memo)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if let attachment = damage.attachment, attachment.canPreview {
                attachmentThumbnail(attachment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(PalantirTheme.bodyFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func attachmentThumbnail(_ attachment: WheelSysPrecheckinDamageAttachment) -> some View {
        Button {
            if let path = attachment.previewPath, let image = previewImages[path] {
                fullScreenImage = WheelSysCHFullScreenImage(image: image)
            }
        } label: {
            Group {
                if let path = attachment.previewPath, let cached = previewImages[path] {
                    Image(uiImage: cached)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(PalantirTheme.surfaceHigh)
                        ProgressView()
                    }
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PalantirTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(attachment.previewPath.flatMap { previewImages[$0] } == nil)
        .padding(.top, 4)
        .task(id: attachment.previewPath) {
            await loadPreview(for: attachment)
        }
    }

    // MARK: - Review + submit

    private func reviewCard(_ context: WheelSysPrecheckinContext) -> some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.precheckin.title".localized,
            icon: "checkmark.seal.fill"
        ) {
            Text("wheelsys.precheckin.review_confirm".localized)
                .font(PalantirTheme.bodyFont(12))
                .foregroundStyle(PalantirTheme.textMuted)

            WheelSysPalantirToggleRow(
                label: "wheelsys.precheckin.customer".localized,
                isOn: $confirmCustomer
            )
            WheelSysPalantirToggleRow(
                label: "wheelsys.precheckin.vehicle".localized,
                isOn: $confirmVehicle
            )
            WheelSysPalantirToggleRow(
                label: "wheelsys.precheckin.existing_damages_title".localized,
                isOn: $confirmDamages
            )
            WheelSysPalantirToggleRow(
                label: "wheelsys.precheckin.insurance".localized,
                isOn: $confirmInsurance
            )

            WheelSysPalantirTextInput(
                label: "wheelsys.return.note_placeholder".localized,
                text: $notes
            )

            if context.canSubmit {
                WheelSysPalantirStatusStrip(
                    icon: "checkmark.circle",
                    message: "wheelsys.precheckin.ready".localized,
                    tint: PalantirTheme.success
                )
            } else {
                WheelSysPalantirStatusStrip(
                    icon: "exclamationmark.triangle",
                    message: context.statusIneligibleMessage
                        ?? "wheelsys.precheckin.blocked".localized,
                    tint: PalantirTheme.warning
                )
            }

            WheelSysPalantirPrimaryButton(
                title: "wheelsys.precheckin.submit_button".localized,
                icon: "checkmark.seal.fill",
                isLoading: isSubmitting,
                disabled: !canSubmit
            ) {
                Task { await submit(context) }
            }

            if let status = submitStatus {
                WheelSysPalantirStatusStrip(
                    icon: submitIsError ? "exclamationmark.triangle" : "checkmark.circle",
                    message: status,
                    tint: submitIsError ? PalantirTheme.critical : PalantirTheme.success
                )
                if submitIsError, submitRetryable, !submitSucceeded {
                    WheelSysPalantirSecondaryButton(
                        title: "wheelsys.precheckin.retry".localized,
                        icon: "arrow.clockwise"
                    ) {
                        Task { await submit(context) }
                    }
                }
            }
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadContext(force: Bool) async {
        if isLoading { return }
        if !force, context != nil { return }
        isLoading = true
        defer { isLoading = false }
        if force { errorMessage = nil }

        do {
            let fetched = try await WheelSysPrecheckinService.fetchContext(
                franchiseId: franchiseId,
                rentalId: rentalId,
                resNo: resNo,
                rntNo: rntNo,
                plateNo: plateNo,
                date: date
            )
            context = fetched
            errorMessage = nil
        } catch {
            let msg = WheelSysUserFacingError.message(for: error)
            if context == nil {
                errorMessage = msg
            }
            WheelSysDebug.warnCH(
                franchiseId: franchiseId,
                "PrecheckinUI",
                "load failed cached=\(context != nil) msg=\(msg)"
            )
            if WheelSysSessionPromptCenter.isSessionError(error) {
                WheelSysSessionPromptCenter.notifyIfSessionError(error)
            }
        }
    }

    @MainActor
    private func loadBodyDiagram(_ diagram: WheelSysPrecheckinBodyDiagram) async {
        guard bodyDiagramImage == nil, !bodyDiagramLoadFailed else { return }
        guard let path = diagram.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return }
        do {
            let image = try await WheelSysVehicleDamageService.loadPreviewImage(previewPath: path)
            bodyDiagramImage = image
        } catch {
            bodyDiagramLoadFailed = true
        }
    }

    @MainActor
    private func loadPreview(for attachment: WheelSysPrecheckinDamageAttachment) async {
        guard let path = attachment.previewPath, previewImages[path] == nil else { return }
        do {
            let image = try await WheelSysVehicleDamageService.loadPreviewImage(previewPath: path)
            previewImages[path] = image
        } catch {
            // Keep placeholder — preview may expire or session may be stale.
        }
    }

    @MainActor
    private func submit(_ context: WheelSysPrecheckinContext) async {
        guard !isSubmitting else { return }
        guard allReviewsConfirmed else {
            submitStatus = "wheelsys.precheckin.review_confirm".localized
            submitIsError = true
            submitRetryable = false
            return
        }
        isSubmitting = true
        submitStatus = nil
        submitIsError = false
        submitRetryable = false
        defer { isSubmitting = false }

        do {
            let mf = context.mileageFuel
            let checkoutKm = mf.checkoutMileage ?? 0
            let returnKm = mf.currentReturnMileage ?? 0
            // HAR: mileageTo must be > mileageFrom (at least +1). Fall back to checkoutKm+1
            // when currentReturnMileage is absent or equal to/less than checkout.
            let submitKm: Int? = returnKm > checkoutKm
                ? returnKm
                : (checkoutKm > 0 ? checkoutKm + 1 : nil)
            let submitFuel = mf.currentReturnFuel ?? mf.checkoutFuel ?? 8
            let result = try await WheelSysPrecheckinService.submit(
                franchiseId: franchiseId,
                rentalId: context.rental.rentalId,
                confirmCustomer: confirmCustomer,
                confirmVehicle: confirmVehicle,
                confirmDamagesReviewed: confirmDamages,
                confirmInsuranceReviewed: confirmInsurance,
                checkInMileage: submitKm,
                checkInFuel: submitFuel,
                checkInUserId: WheelSysCookieCache.wheelSysOperatorId,
                notes: notes.isEmpty ? nil : notes
            )
            if result.success {
                submitSucceeded = true
                submitIsError = false
                submitRetryable = false
                submitStatus = result.message?.isEmpty == false
                    ? result.message
                    : "wheelsys.precheckin.submit_success".localized
                HapticManager.shared.success()
                let plate = context.vehicle.plateNo.isEmpty ? (plateNo ?? "") : context.vehicle.plateNo
                WheelSysActivityReporter.record(
                    .precheckin(
                        plate: plate,
                        rntNo: context.rental.rntNo ?? rntNo,
                        resNo: context.rental.resNo ?? resNo,
                        rentalId: context.rental.rentalId
                    ),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
            } else {
                submitIsError = true
                submitRetryable = result.retryable
                submitStatus = result.message?.isEmpty == false
                    ? result.message
                    : "wheelsys.precheckin.submit_failed".localized
                WheelSysSessionPromptCenter.notifyIfSessionMessage(result.message ?? "")
                HapticManager.shared.error()
            }
        } catch {
            let msg = WheelSysUserFacingError.message(for: error)
            submitIsError = true
            submitRetryable = WheelSysUserFacingError.isSessionExpiredRaw(msg)
                || msg.localizedCaseInsensitiveContains("record")
            submitStatus = msg
            WheelSysSessionPromptCenter.notifyIfSessionError(error)
            HapticManager.shared.error()
        }
    }
}

// MARK: - Full screen image viewer (shared with damage history)

struct WheelSysCHFullScreenImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct WheelSysCHImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in withAnimation { scale = max(1, scale) } }
                )
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}
