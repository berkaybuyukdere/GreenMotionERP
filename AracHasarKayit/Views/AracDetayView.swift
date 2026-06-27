import SwiftUI

// MARK: - Sheet Wrapper to prevent swipe-to-dismiss
struct SheetWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(true)
    }
}

struct AracDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var serviceFlagStore = VehicleServiceFlagStore.shared
    @ObservedObject private var fleetStatusStore = WheelSysVehicleFleetStatusStore.shared
    @State var arac: Arac
    var scannedEntry: Bool = false
    @State private var duzenlemeGoster = false
    @State private var hasarEkleGoster = false
    @State private var checkInGoster = false
    @State private var iadeIslemGoster = false
    @State private var exitIslemGoster = false
    @State private var showQuickFuelOfficeSheet = false
    @State private var showQuickWashingOfficeSheet = false
    @State private var silmeOnayiGoster = false
    @State private var showHeadDocument = false
    @State private var headDocumentImage: UIImage?
    @State private var isLoadingHeadDoc = false
    @State private var selectedIade: IadeIslemi?
    @State private var showIadeDetay = false
    @State private var selectedExitPreviewId: UUID?
    @State private var showExitDetay = false
    @State private var selectedDamagePreviewId: UUID?
    @State private var showHasarDetay = false
    @State private var isDamageExpanded = false
    @State private var isReturnExpanded = false
    @State private var isExitExpanded = false
    @State private var showCompanyPicker = false
    @State private var selectedExitForEditing: ExitIslemi?
    @State private var checkInSilmeOnayi: LastCheckInSnapshot?
    @State private var showConditionForm = false
    @State private var showWheelSysDamageHistory = false
    @State private var trCheckoutHandover: TRFrontDeskHandoverPrefill?
    @State private var wheelSysCheckoutPrefill: WheelSysCheckoutPrefill?
    @State private var wheelSysReturnPrefill: WheelSysReturnOperationPrefill?
    @State private var trReturnHandover: TRFrontDeskHandoverPrefill?
    @State private var trExitSheetHandover: TRFrontDeskHandoverPrefill?
    @State private var iadeSheetHandover: TRFrontDeskHandoverPrefill?
    @State private var lastAutoOpenedHandoverDocId: String?
    @State private var cachedAracServisleri: [Servis] = []
    @State private var cachedAracIadeleri: [IadeIslemi] = []
    @State private var cachedAracExitleri: [ExitIslemi] = []
    @State private var cachedVehicleLikelyOut = false
    @State private var cachedIsVehicleInNTR = false
    @State private var cachedIsWheelSysOnRental = false

    private var isWheelSysCHEnabled: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    @State private var damageRecordPendingDelete: HasarKaydi?
    @State private var showGarageServiceHub = false
    @State private var showVehicleServiceStatus = false
    @State private var showScanServiceAlert = false
    @EnvironmentObject private var wheelSysSession: WheelSysSessionCoordinator
    @State private var showWheelSysLogin = false
    @State private var wheelSysLoginResume: WheelSysLoginResumeAction?
    @State private var showWheelSysNTR = false
    @State private var wheelSysResolvedRentalEntityId: Int?

    private enum WheelSysLoginResumeAction {
        case checkoutFlow
        case returnFlow
        case ntr
    }
    @State private var showNTRBlockedAlert = false
    @State private var ntrBlockedActionKey = ""
    @State private var showDuplicateCheckoutConfirm = false
    @State private var duplicateCheckoutForConfirm: ExitIslemi?

    var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }

    private var activeServiceFlag: VehicleServiceFlag? {
        serviceFlagStore.flag(forVehicleId: guncelArac.id)
    }

    private var serviceStatusAccentColor: Color {
        if let flag = activeServiceFlag {
            return flag.kind == .needsService ? .red : .orange
        }
        return .orange
    }

    @ViewBuilder
    private var serviceStatusStatisticsRow: some View {
        if isWheelSysCHEnabled {
            HStack(spacing: 12) {
                PalantirOpsIconTile(
                    systemName: activeServiceFlag?.kind.icon ?? "wrench.and.screwdriver",
                    tint: activeServiceFlag?.kind == .needsService ? PalantirTheme.critical : PalantirTheme.warning,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("vehicle_service_flag.sheet_title".localized.uppercased())
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                    if let flag = activeServiceFlag {
                        Text(flag.kind.localizedTitle)
                            .font(PalantirTheme.bodyFont(13))
                            .foregroundStyle(flag.kind == .needsService ? PalantirTheme.critical : PalantirTheme.warning)
                        if !flag.note.isEmpty {
                            Text(flag.note)
                                .font(PalantirTheme.bodyFont(11))
                                .foregroundStyle(PalantirTheme.textMuted)
                                .lineLimit(1)
                        }
                    } else {
                        Text("vehicle_service_flag.status_section".localized)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                if activeServiceFlag != nil {
                    Circle()
                        .fill(activeServiceFlag?.kind == .needsService ? PalantirTheme.critical : PalantirTheme.warning)
                        .frame(width: 7, height: 7)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(serviceStatusAccentColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: activeServiceFlag?.kind.icon ?? "car.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(serviceStatusAccentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("vehicle_service_flag.sheet_title".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let flag = activeServiceFlag {
                        Text(flag.kind.localizedTitle)
                            .font(.caption)
                            .foregroundStyle(serviceStatusAccentColor)
                        if !flag.note.isEmpty {
                            Text(flag.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("vehicle_service_flag.status_section".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if activeServiceFlag != nil {
                    Circle()
                        .fill(serviceStatusAccentColor)
                        .frame(width: 8, height: 8)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
    }

    private var officeQuickActionsVisible: Bool {
        FranchiseCapabilityMatrix.officeOperationsProductEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var isGaragePortalViewer: Bool {
        authManager.userProfile?.role == .garage
    }

    /// TR-only: condition form, Front Desk handover, parked checkout ribbon (not vehicle id / country picker heuristics).
    private var isTurkeyFranchiseForConditionFeatures: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    
    var selectedCompany: AssistantCompany? {
        guard let companyName = guncelArac.assistantCompanyName,
              let companyPhone = guncelArac.assistantCompanyPhone else {
            return nil
        }
        return AssistantCompany(name: companyName, phoneNumber: companyPhone)
    }
    
    var aracHasarKayitlari: [HasarKaydi] {
        viewModel.damagesForVehicleDisplay(guncelArac)
    }

    /// Bumps when franchise return/checkout/damage listeners refresh vehicle-scoped lists.
    private var vehicleOperationsCacheToken: String {
        "\(guncelArac.id.uuidString)|\(viewModel.iadeIslemleri.count)|\(viewModel.exitIslemleri.count)|\(viewModel.topLevelHasarKayitlari.count)"
    }

    var latestDamage: HasarKaydi? {
        aracHasarKayitlari.first
    }
    
    var aracServiste: Bool {
        viewModel.servisler.contains(where: { $0.aracId == guncelArac.id && $0.durum == .serviste })
    }
    
    var aracServisleri: [Servis] {
        if OptimizationFeatureFlags.detailMemoV2 {
            return cachedAracServisleri
        }
        return viewModel.servisler.filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.gonderilmeTarihi > $1.gonderilmeTarihi })
    }
    
    var aktifServis: Servis? {
        // Önce serviste olan varsa onu göster, yoksa en son servis kaydını göster
        let servisler = aracServisleri
        if let servisteOlan = servisler.first(where: { $0.durum == .serviste }) {
            return servisteOlan
        }
        if let sonServis = servisler.first {
            return sonServis
        }
        return nil
    }
    
    var aracIadeleri: [IadeIslemi] {
        if OptimizationFeatureFlags.detailMemoV2 {
            return cachedAracIadeleri
        }
        return viewModel.iadeIslemleri(for: guncelArac)
    }
    
    var aracYikamaKayitlari: [VehicleWashingRecord] {
        guncelArac.washingRecords.sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    var aracExitleri: [ExitIslemi] {
        if OptimizationFeatureFlags.detailMemoV2 {
            return cachedAracExitleri
        }
        return viewModel.exitIslemleri(for: guncelArac)
    }

    /// Latest km from check-out or return operations (by operation date).
    private var lastRecordedKm: Int? {
        var best: (date: Date, km: Int)?
        for exit in aracExitleri {
            guard let km = exit.km else { continue }
            let d = max(exit.createdAt, exit.exitTarihi)
            if best == nil || d > best!.date { best = (d, km) }
        }
        for iade in aracIadeleri {
            guard let km = iade.km else { continue }
            let d = max(iade.createdAt, iade.iadeTarihi)
            if best == nil || d > best!.date { best = (d, km) }
        }
        return best?.km
    }

    private var wheelSysDisplayKm: Int? {
        lastRecordedKm ?? fleetStatusStore.fleetMileage(for: guncelArac)
    }

    private var wheelSysDisplayFuel: Int? {
        fleetStatusStore.fleetFuelEighths(for: guncelArac) ?? guncelArac.lastCheckIn.map(\.fuelEighths)
    }

    private func rebuildDerivedCaches() {
        cachedAracServisleri = viewModel.servisler
            .filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.gonderilmeTarihi > $1.gonderilmeTarihi })
        cachedAracIadeleri = viewModel.iadeIslemleri(for: guncelArac)
        cachedAracExitleri = viewModel.exitIslemleri(for: guncelArac)
        rebuildWheelSysActionCaches()
    }

    private func rebuildWheelSysActionCaches() {
        cachedVehicleLikelyOut = computeVehicleLikelyOut()
        cachedIsVehicleInNTR = computeIsVehicleInNTR()
        cachedIsWheelSysOnRental = isWheelSysCHEnabled
            && fleetStatusStore.isVehicleOnRental(guncelArac)
    }

    private func computeIsVehicleInNTR() -> Bool {
        if guncelArac.wheelsysNtrStatus == WheelSysNTRStatus.active.rawValue { return true }
        return fleetStatusStore.isFleetNonRevenue(guncelArac)
    }

    /// Orange parked-checkout ribbon (all franchises). Shown collapsed + expanded.
    @ViewBuilder
    private func parkedCheckoutCalloutLink(exit: ExitIslemi) -> some View {
        NavigationLink(destination: ExitDetayView(exit: exit)) {
            VStack(alignment: .leading, spacing: 10) {
                WheelSysPalantirStatusStrip(
                    icon: "parkingsign.circle.fill",
                    message: "This vehicle is parked".localized,
                    tint: PalantirTheme.warning
                )
                Text("Check out is saved as parked. Tap to continue and complete.".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Resume parked check-out".localized)
                        .font(PalantirTheme.labelFont(11))
                        .foregroundStyle(PalantirTheme.warning)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PalantirTheme.warning.opacity(0.12))
                .overlay(Rectangle().stroke(PalantirTheme.warning.opacity(0.35), lineWidth: 1))
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PalantirTheme.warning)
                }
            }
            .padding(12)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.warning.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func showWarningFeedback(_ message: String) {
        ToastManager.shared.show(message, type: .warning)
    }

    @MainActor
    private func showSuccessFeedback(_ message: String) {
        ToastManager.shared.show(message, type: .success)
    }

    @MainActor
    private func openWheelSysDamageHistorySheet() {
        HapticManager.shared.selection()
        Task {
            await WheelSysVehicleDamageService.ensureFleetReady(for: guncelArac)
            await MainActor.run {
                showWheelSysDamageHistory = true
            }
        }
    }

    @MainActor
    private func openConditionFormSheet() {
        HapticManager.shared.selection()
        showConditionForm = true
    }

    @MainActor
    private func openQuickFuelSheet() {
        HapticManager.shared.selection()
        showQuickFuelOfficeSheet = true
    }

    @MainActor
    private func openQuickWashingSheet() {
        HapticManager.shared.selection()
        showQuickWashingOfficeSheet = true
    }

    @MainActor
    private func announceActionOpened(_ action: String) {
        showSuccessFeedback("\(action) \("opened".localized)".trimmingCharacters(in: .whitespaces))
    }

    @MainActor
    private func beginCheckoutFlow(forceNewCheckout: Bool = false) async {
        if isVehicleInNTR {
            ntrBlockedActionKey = "checkout"
            showNTRBlockedAlert = true
            showWarningFeedback(ntrBlockedMessage)
            return
        }
        HapticManager.shared.medium()
        if isWheelSysCHEnabled {
            WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
            Task(priority: .utility) {
                await ensureCHFleetReady(skipRentalResolve: true)
            }
        }
        if !forceNewCheckout, let resumable = latestResumableCheckout {
            if isWheelSysCHEnabled, resumable.status == .parked {
                wheelSysCheckoutPrefill = await WheelSysCheckoutPrefillResolver.resolveForParkedExit(
                    exit: resumable,
                    arac: guncelArac,
                    franchiseId: FirebaseService.shared.currentFranchiseId
                )
            } else {
                wheelSysCheckoutPrefill = nil
            }
            presentCheckoutSheet(resuming: resumable)
            return
        }
        if !forceNewCheckout, let completed = completedOpenOutboundCheckout {
            duplicateCheckoutForConfirm = completed
            showDuplicateCheckoutConfirm = true
            return
        }
        wheelSysCheckoutPrefill = nil
        presentCheckoutSheet(resuming: nil)
    }

    @MainActor
    private func presentCheckoutSheet(resuming exit: ExitIslemi?) {
        selectedExitForEditing = exit
        trExitSheetHandover = exit == nil ? trCheckoutHandover : nil
        exitIslemGoster = true
        announceActionOpened("Check-out".localized)
    }

    private func duplicateCheckoutConfirmMessage(for exit: ExitIslemi) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale.current

        let resRaw = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        let resLine = resRaw.isEmpty ? "—" : resRaw
        let dateLine = df.string(from: checkoutRecency(exit))
        let customer = [exit.customerFirstName, exit.customerLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let customerLine = customer.isEmpty ? "—" : customer
        let kmFuelLine: String = {
            guard let km = exit.km else { return "—" }
            let fuel = exit.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "—"
            return "\(km) km · \(fuel)"
        }()

        let summary = String(
            format: "checkout.duplicate_confirm.summary".localized,
            resLine,
            dateLine,
            customerLine,
            kmFuelLine
        )
        return String(format: "checkout.duplicate_confirm.message".localized, summary)
    }

    @MainActor
    private func beginReturnFlow() async {
        if isVehicleInNTR {
            ntrBlockedActionKey = "return"
            showNTRBlockedAlert = true
            showWarningFeedback(ntrBlockedMessage)
            return
        }
        if isWheelSysCHEnabled {
            let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
            WheelSysCookieCache.restorePersistedSession(franchiseId: franchiseId)
            WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()

            let cachedSessionUsable = wheelSysSession.sessionValid || WheelSysCookieCache.hasUsableSession
            if !cachedSessionUsable {
                await wheelSysSession.refreshSessionStatus()
                if !wheelSysSession.sessionValid && !WheelSysCookieCache.hasUsableSession {
                    wheelSysLoginResume = .returnFlow
                    showWheelSysLogin = true
                    showWarningFeedback("wheelsys_fleet.session_expired".localized)
                    return
                }
            }

            // Instant open — IadeIslemView loads preview / pre-check-in in the background.
            wheelSysReturnPrefill = buildWheelSysReturnPrefillSync()

            if cachedSessionUsable {
                Task(priority: .utility) {
                    await wheelSysSession.refreshSessionStatus()
                }
            }
        }
        iadeSheetHandover = trReturnHandover
        iadeIslemGoster = true
        announceActionOpened("RETURN".localized)
    }

    @MainActor
    private func beginDamageFlow() {
        if isVehicleInNTR {
            ntrBlockedActionKey = "damage"
            showNTRBlockedAlert = true
            showWarningFeedback(ntrBlockedMessage)
            return
        }
        hasarEkleGoster = true
        announceActionOpened("Damage".localized)
    }

    private var latestCheckoutOverall: ExitIslemi? {
        aracExitleri.max { a, b in
            let ra = checkoutRecency(a)
            let rb = checkoutRecency(b)
            if ra != rb { return ra < rb }
            return a.createdAt < b.createdAt
        }
    }

    /// Reopen only when the latest checkout is parked.
    private var latestReopenableCheckout: ExitIslemi? {
        guard let latest = latestCheckoutOverall else { return nil }
        return latest.status == .parked ? latest : nil
    }

    /// Parked or in-progress checkout after the last return — resume without duplicate prompt.
    private var latestResumableCheckout: ExitIslemi? {
        if let parked = latestReopenableCheckout { return parked }
        let inProgress = aracExitleri.filter { $0.status == .inProgress && !$0.isDeleted }
        guard !inProgress.isEmpty else { return nil }
        if let cutoff = lastReturnRecency {
            let active = inProgress.filter { checkoutRecency($0) > cutoff }
            return active.max { checkoutRecency($0) < checkoutRecency($1) }
        }
        return inProgress.max { checkoutRecency($0) < checkoutRecency($1) }
    }

    /// Completed handover still open (no return after it) — confirm before starting another checkout.
    private var completedOpenOutboundCheckout: ExitIslemi? {
        guard let exit = latestOpenOutboundExit, exit.status == .completed else { return nil }
        return exit
    }
    
    private var wheelSysFleetDisplayToken: String {
        guard let v = fleetStatusStore.fleetVehicle(for: guncelArac) else { return "missing" }
        return "\(v.status)|\(v.mileage)|\(v.plate)"
    }

    /// End of the last completed return cycle (createdAt vs iadeTarihi — whichever is later).
    private var lastReturnRecency: Date? {
        aracIadeleri
            .filter { $0.status == .completed }
            .map { max($0.createdAt, $0.iadeTarihi) }
            .max()
    }
    
    /// Handover time for a checkout row (aligns with detail screen / PDF).
    private func checkoutRecency(_ exit: ExitIslemi) -> Date {
        max(exit.createdAt, exit.exitTarihi)
    }
    
    /// Outbound checkouts (handover done): completed or parked — **excluding** cycles already closed by a later return.
    private var openOutboundExits: [ExitIslemi] {
        let outbound = aracExitleri.filter { $0.status == .completed || $0.status == .parked }
        guard let cutoff = lastReturnRecency else { return outbound }
        return outbound.filter { checkoutRecency($0) > cutoff }
    }
    
    /// The **current** open checkout for check-in / RETURN (must match the latest row the user sees for an active rental).
    private var latestOpenOutboundExit: ExitIslemi? {
        openOutboundExits.max { a, b in
            let ra = checkoutRecency(a)
            let rb = checkoutRecency(b)
            if ra != rb { return ra < rb }
            return a.createdAt < b.createdAt
        }
    }
    
    /// True when there is at least one checkout after the last return (vehicle out on an open cycle).
    private var vehicleLikelyOut: Bool {
        OptimizationFeatureFlags.detailMemoV2 ? cachedVehicleLikelyOut : computeVehicleLikelyOut()
    }

    private func computeVehicleLikelyOut() -> Bool {
        latestOpenOutboundExit != nil
    }
    
    private func normalizedResToken(_ raw: String) -> String {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while code.uppercased().hasPrefix("NAV-") || code.uppercased().hasPrefix("RES-") || code.uppercased().hasPrefix("RNT-") {
            code = String(code.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return code.filter { $0.isNumber }
    }
    
    /// Latest check-in snapshot tied to the current open checkout (exit id or matching RES digits).
    private var checkInSnapshotForCurrentExit: LastCheckInSnapshot? {
        guard let exit = latestOpenOutboundExit else { return nil }
        let targetId = exit.id
        let resNum = normalizedResToken(exit.resKodu)
        let matches = guncelArac.checkInKayitlari.filter { snap in
            if let lid = snap.linkedExitId, lid == targetId { return true }
            if !resNum.isEmpty, normalizedResToken(snap.reservationNumber) == resNum { return true }
            return false
        }
        return matches.max { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.id.uuidString < b.id.uuidString
        }
    }
    
    /// True when there is a check-in row for the **current** latest open checkout (by exit id or matching RES digits).
    private var hasCheckInForCurrentExit: Bool {
        checkInSnapshotForCurrentExit != nil
    }
    
    private var checkInActionSubtitle: String {
        if latestOpenOutboundExit == nil {
            return "After CHECK OUT when vehicle returns".localized
        }
        if let snap = checkInSnapshotForCurrentExit {
            if isTurkeyFranchiseForConditionFeatures {
                return String(format: "Latest NAV check-in on file: %lld km · fuel %lld/8".localized, snap.km, snap.fuelEighths)
            }
            return String(format: "Latest RES check-in on file: %lld km · fuel %lld/8".localized, snap.km, snap.fuelEighths)
        }
        if isTurkeyFranchiseForConditionFeatures {
            return "Open NAV: enter km & fuel (8 = full)".localized
        }
        return "Open RES: enter km & fuel (8 = full)".localized
    }
    
    private var isVehicleInNTR: Bool {
        OptimizationFeatureFlags.detailMemoV2 ? cachedIsVehicleInNTR : computeIsVehicleInNTR()
    }

    private var wheelSysNtrButtonTitle: String {
        let key = WheelSysNTRService.resolveContext(arac: guncelArac).isCloseMode
            ? "wheelsys_ntr.button_close"
            : "wheelsys_ntr.button_open"
        return key.localized
    }

    private var isWheelSysOnRental: Bool {
        OptimizationFeatureFlags.detailMemoV2 ? cachedIsWheelSysOnRental : (
            isWheelSysCHEnabled && fleetStatusStore.isVehicleOnRental(guncelArac)
        )
    }

      /// Ensures WheelSys session + fleet chart are loaded and linked to Firebase vehicles (CH).
    @MainActor
    private func ensureCHFleetReady(
        force: Bool = false,
        syncEntities: Bool = false,
        skipRentalResolve: Bool = false
    ) async {
        guard isWheelSysCHEnabled else { return }
        await wheelSysSession.refreshSessionStatus()
        guard wheelSysSession.sessionValid || WheelSysCookieCache.hasUsableSession else {
            WheelSysDebug.logCH(
                franchiseId: FirebaseService.shared.currentFranchiseId,
                "Detail",
                "fleet ready skipped — no WheelSys session"
            )
            return
        }
        let store = WheelSysVehicleFleetStatusStore.shared
        store.bootstrapFromDiskIfNeeded()
        rebuildWheelSysActionCaches()
        if force {
            await store.refresh(force: true)
        } else {
            await store.refreshIfNeeded()
        }
        if let fleet = store.fleet {
            applyLocalWheelSysLinkFromFleet(fleet)
            rebuildWheelSysActionCaches()
            if syncEntities {
                Task(priority: .utility) {
                    _ = await viewModel.syncWheelSysEntities(from: fleet)
                }
            }
        }
        if !skipRentalResolve {
            await resolveWheelSysRentalFromOps()
        }
    }

    private var wheelSysEffectiveRentalEntityId: Int? {
        if let id = wheelSysResolvedRentalEntityId, id > 0 { return id }
        if let stored = guncelArac.wheelsysRentalEntityId, stored > 0 { return stored }
        return nil
    }

    /// Journal / daily view fallback when fleet chart has no active rental entity for this plate.
    @MainActor
    private func resolveWheelSysRentalFromOps() async {
        guard isWheelSysCHEnabled else { return }
        let exit = latestOpenOutboundExit
        let resNo = formattedWheelSysResNo(from: exit)
        let resolved = await WheelSysCheckinService.resolveRentalEntityIdForVehicle(
            arac: guncelArac,
            resNo: resNo.isEmpty ? nil : resNo,
            franchiseId: FirebaseService.shared.currentFranchiseId
        )
        guard let rentalId = Int(resolved.entityId ?? ""), rentalId > 0 else { return }
        wheelSysResolvedRentalEntityId = rentalId
        viewModel.applyLocalWheelSysEntityLink(
            aracId: guncelArac.id,
            vehicleId: resolved.vehicleId,
            rentalEntityId: rentalId,
            plateCanonical: WheelSysPlateNormalizer.canonical(guncelArac.plaka)
        )
    }

    /// Patch in-memory `araclar` immediately after fleet load (Firestore listener may lag).
    @MainActor
    private func applyLocalWheelSysLinkFromFleet(_ fleet: WheelSysFleetChartResult) {
        let key = WheelSysPlateNormalizer.canonical(guncelArac.plaka)
        guard !key.isEmpty else { return }
        let matches = fleet.vehicles.filter {
            WheelSysPlateNormalizer.canonical($0.plate) == key
        }
        guard matches.count == 1, let vehicle = matches.first else { return }
        let rentalId = WheelSysCheckinService.resolveRentalEntityId(from: vehicle)
        viewModel.applyLocalWheelSysEntityLink(
            aracId: guncelArac.id,
            vehicleId: vehicle.vehicleId,
            rentalEntityId: rentalId,
            plateCanonical: key,
            syncStatus: "matched"
        )
    }


    /// Instant prefill from local exit + fleet disk cache (no network wait).
    private func buildWheelSysReturnPrefillSync() -> WheelSysReturnOperationPrefill? {
        guard isWheelSysCHEnabled else { return nil }
        let exit = latestOpenOutboundExit
        let resNo = formattedWheelSysResNo(from: exit)
        let rentalEntityId = guncelArac.wheelsysRentalEntityId ?? 0
        guard rentalEntityId > 0 || !resNo.isEmpty || exit != nil else { return nil }

        let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: guncelArac)

        let fleetDriver = WheelSysVehicleFleetStatusStore.shared
            .fleetDriverName(forRentalEntityId: rentalEntityId, plate: guncelArac.plaka)
        let exitDriverParts = [exit?.customerFirstName, exit?.customerLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let driverName = fleetDriver
            ?? exitDriverParts.joined(separator: " ")

        let fleetKm = fleetVehicle?.mileage
        let checkoutKm = exit?.km ?? fleetKm.flatMap { $0 > 0 ? $0 : nil }
        let checkoutFuel = exit?.yakitSeviyesi.flatMap { Int($0.components(separatedBy: "/").first ?? "") }
            ?? 8

        return WheelSysReturnOperationPrefill(
            rentalEntityId: rentalEntityId,
            resNo: resNo,
            raNo: nil,
            confirmationNo: nil,
            driverName: driverName,
            customerEmail: exit?.customerEmail,
            vehicleEntityId: guncelArac.wheelsysVehicleId ?? fleetVehicle?.vehicleId,
            checkoutMileage: checkoutKm,
            checkoutFuel: checkoutFuel,
            checkinMileageHint: fleetKm,
            checkinFuelHint: checkoutFuel,
            dateFrom: exit?.exitTarihi,
            dateTo: exit?.plannedReturnAt ?? exit?.exitTarihi,
            entryPoint: .plateScanReturn
        )
    }

    private var ntrBlockedMessage: String {
        switch ntrBlockedActionKey {
        case "return":
            return "wheelsys_ntr.blocked_return".localized
        case "checkout":
            return "wheelsys_ntr.blocked_checkout".localized
        default:
            return "wheelsys_ntr.blocked_damage".localized
        }
    }

    @MainActor
    private func beginWheelSysNTRFlow() async {
        HapticManager.shared.medium()
        await wheelSysSession.refreshSessionStatus()
        if WheelSysCookieCache.isValid {
            WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
            await WheelSysVehicleFleetStatusStore.shared.refreshIfNeeded()
            await WheelSysNTRService.syncActiveNTRFromFleetIfNeeded(arac: guncelArac)
            showWheelSysNTR = true
        } else {
            wheelSysLoginResume = .ntr
            showWheelSysLogin = true
        }
    }

    private func buildWheelSysReturnPrefillForOpenReturn() async -> WheelSysReturnOperationPrefill? {
        guard isWheelSysCHEnabled else { return nil }
        let exit = latestOpenOutboundExit
        let resNo = formattedWheelSysResNo(from: exit)

        let fleetStore = WheelSysVehicleFleetStatusStore.shared
        let fleetVehicle = fleetStore.fleetVehicle(for: guncelArac)
        let franchiseId = FirebaseService.shared.currentFranchiseId

        let resolved = await WheelSysCheckinService.resolveRentalEntityIdForVehicle(
            arac: guncelArac,
            resNo: resNo.isEmpty ? nil : resNo,
            franchiseId: franchiseId
        )
        let driverParts = [exit?.customerFirstName, exit?.customerLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var rentalEntityId = Int(resolved.entityId ?? "") ?? guncelArac.wheelsysRentalEntityId ?? 0
        var effectiveResNo = resNo
        var effectiveRaNo: String?
        var effectiveDriver = WheelSysVehicleFleetStatusStore.shared
            .fleetDriverName(forRentalEntityId: rentalEntityId, plate: guncelArac.plaka)
            ?? driverParts.joined(separator: " ")

        if rentalEntityId <= 0,
           let candidate = try? await WheelSysPlateScannerService.findActiveRentalForPlate(
            plate: guncelArac.plaka,
            franchiseId: franchiseId,
            selectedDate: WheelSysJournalService.formatZurichDay(WheelSysJournalService.todayZurich())
           ) {
            rentalEntityId = candidate.rentalEntityId
            if effectiveResNo.isEmpty { effectiveResNo = candidate.resNo }
            effectiveRaNo = candidate.raNo
            if effectiveDriver.isEmpty { effectiveDriver = candidate.driverName }
        }

        if effectiveDriver.isEmpty,
           rentalEntityId > 0,
           let fleetDriver = WheelSysVehicleFleetStatusStore.shared
            .fleetDriverName(forRentalEntityId: rentalEntityId, plate: guncelArac.plaka) {
            effectiveDriver = fleetDriver
        }

        guard rentalEntityId > 0 || !effectiveResNo.isEmpty else { return nil }

        let fleetKm = resolved.fleetVehicle?.mileage ?? fleetVehicle?.mileage
        let checkoutKm = exit?.km ?? fleetKm.flatMap { $0 > 0 ? $0 : nil }
        let checkoutFuel = exit?.yakitSeviyesi.flatMap { Int($0.components(separatedBy: "/").first ?? "") }
            ?? 8

        return WheelSysReturnOperationPrefill(
            rentalEntityId: rentalEntityId,
            resNo: effectiveResNo,
            raNo: effectiveRaNo,
            confirmationNo: nil,
            driverName: effectiveDriver,
            customerEmail: exit?.customerEmail,
            vehicleEntityId: resolved.vehicleId
                ?? guncelArac.wheelsysVehicleId
                ?? fleetVehicle?.vehicleId,
            checkoutMileage: checkoutKm,
            checkoutFuel: checkoutFuel,
            checkinMileageHint: fleetKm,
            checkinFuelHint: checkoutFuel,
            dateFrom: exit?.exitTarihi,
            dateTo: exit?.plannedReturnAt ?? exit?.exitTarihi,
            entryPoint: .plateScanReturn
        )
    }

    private func formattedWheelSysResNo(from exit: ExitIslemi?) -> String {
        let raw = (exit?.resKodu ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.uppercased().hasPrefix("RES-") || raw.uppercased().hasPrefix("RNT-") {
            return raw.uppercased()
        }
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? raw : "RES-\(digits)"
    }

    private func refreshTurkeyHandoverPrefills() {
        guard isTurkeyFranchiseForConditionFeatures else {
            trCheckoutHandover = nil
            trReturnHandover = nil
            return
        }
        FirebaseService.shared.fetchFrontDeskHandoverDocuments(forVehicleId: guncelArac.id) { snap, _ in
            DispatchQueue.main.async {
                guard let docs = snap?.documents else {
                    trCheckoutHandover = nil
                    trReturnHandover = nil
                    return
                }
                trCheckoutHandover = TRFrontDeskHandoverPrefill.pickCheckout(from: docs)
                if let ex = latestOpenOutboundExit {
                    trReturnHandover = TRFrontDeskHandoverPrefill.pickReturn(from: docs, linkedExitId: ex.id)
                } else {
                    trReturnHandover = nil
                }
            }
        }
    }

    private var shouldShowWebHandoverBanner: Bool {
        isTurkeyFranchiseForConditionFeatures
            && trCheckoutHandover != nil
            && latestReopenableCheckout == nil
            && !vehicleLikelyOut
    }

    /// WheelSys fleet chart only — avoids false positives from stale local checkout rows.
    private var isVehicleOnRental: Bool {
        guard isWheelSysCHEnabled else { return false }
        return cachedIsWheelSysOnRental
    }

    private var wheelSysFleetStatusLabel: String {
        fleetStatusStore.displayStatusLabel(for: guncelArac)
    }

    private var wheelSysFleetOpsBadge: WheelSysFleetOpsBadge {
        fleetStatusStore.fleetOpsBadge(
            for: guncelArac,
            hasActiveCheckout: hasActiveFleetOpenCheckout
        )
    }

    /// Matches Vehicles list badge: in-progress or parked checkout only (not completed handovers).
    private var hasActiveFleetOpenCheckout: Bool {
        aracExitleri.contains {
            ($0.status == .inProgress || $0.status == .parked) && !$0.isDeleted
        }
    }

    private func fleetOpsBadgeTone(for kind: WheelSysFleetOpsBadgeKind) -> PalantirOpsBadge.Tone {
        switch kind {
        case .ntr: return .warning
        case .rental: return .accent
        case .available: return .success
        }
    }

    private var wheelSysOperationalMessage: (icon: String, message: String, tint: Color) {
        if isVehicleOnRental {
            return ("car.fill", "wheelsys.detail.on_rental_banner".localized, PalantirTheme.warning)
        }
        if vehicleLikelyOut {
            return (
                "arrow.right.circle.fill",
                "Check-out exists after last return. Vehicle may still be given out.".localized,
                PalantirTheme.warning
            )
        }
        return (
            "checkmark.circle.fill",
            "Vehicle is operationally available for a new checkout.".localized,
            PalantirTheme.success
        )
    }

    @ViewBuilder
    private var wheelSysRentalContextCard: some View {
        if let active = fleetStatusStore.activeRentalEvent(for: guncelArac) {
            VStack(alignment: .leading, spacing: 6) {
                Text("wheelsys.detail.active_rental".localized)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.warning)
                if !active.recordId.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.rental_no".localized,
                        value: active.recordId,
                        monospace: true
                    )
                }
                if !active.driverName.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.col_driver".localized,
                        value: active.driverName,
                        monospace: false
                    )
                }
                if !active.startTimeText.isEmpty || !active.endTimeText.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.section_schedule".localized,
                        value: [active.startTimeText, active.endTimeText]
                            .filter { !$0.isEmpty }
                            .joined(separator: " → "),
                        monospace: false
                    )
                }
                if let rentalId = active.rentalEntityId, rentalId > 0 {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.entity_id".localized,
                        value: String(rentalId),
                        monospace: true
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PalantirTheme.warning.opacity(0.08))
            .overlay(Rectangle().stroke(PalantirTheme.warning.opacity(0.35), lineWidth: 1))
        } else if let last = fleetStatusStore.lastClosedRentalEvent(for: guncelArac) {
            VStack(alignment: .leading, spacing: 6) {
                Text("wheelsys.detail.last_rental".localized)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
                if !last.recordId.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.rental_no".localized,
                        value: last.recordId,
                        monospace: true
                    )
                }
                if !last.driverName.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys_journal.col_driver".localized,
                        value: last.driverName,
                        monospace: false
                    )
                }
                if !last.endTimeText.isEmpty {
                    WheelSysPalantirDataRow(
                        label: "wheelsys.detail.last_return".localized,
                        value: last.endTimeText,
                        monospace: false
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PalantirTheme.surfaceHigh)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var vehicleDetailRoot: some View {
        if isWheelSysCHEnabled {
            wheelSysPalantirVehicleDetail
                .wheelSysCHOpsChrome()
        } else {
            vehicleDetailList
        }
    }

    private var wheelSysPalantirVehicleDetail: some View {
        ScrollView {
            LazyVStack(spacing: 15) {
                WheelSysPalantirSectionCard(title: guncelArac.plakaFormatli, icon: "car.side.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(guncelArac.plakaFormatli)
                                .font(PalantirTheme.heroFont(28))
                                .foregroundStyle(latestReopenableCheckout != nil ? PalantirTheme.warning : PalantirTheme.textPrimary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            if latestReopenableCheckout != nil {
                                PalantirOpsBadge(text: "PARKING".localized, tone: .warning)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .center, spacing: 8) {
                            Text("\(guncelArac.marka) \(guncelArac.model)")
                                .font(PalantirTheme.bodyFont(15))
                                .foregroundStyle(PalantirTheme.textMuted)
                            Spacer(minLength: 0)
                            PalantirOpsBadge(
                                text: wheelSysFleetOpsBadge.kind.labelKey.localized,
                                tone: fleetOpsBadgeTone(for: wheelSysFleetOpsBadge.kind)
                            )
                        }
                        WheelSysPalantirDataRow(
                            label: "wheelsys.fleet_status".localized,
                            value: wheelSysFleetStatusLabel,
                            monospace: false
                        )
                        WheelSysPalantirStatusStrip(
                            icon: wheelSysOperationalMessage.icon,
                            message: wheelSysOperationalMessage.message,
                            tint: wheelSysOperationalMessage.tint
                        )
                        if isWheelSysCHEnabled {
                            wheelSysRentalContextCard
                        }
                        if let vin = guncelArac.vin, !vin.isEmpty {
                            WheelSysPalantirDataRow(label: "VIN", value: vin)
                        }
                        HStack(spacing: 8) {
                            wheelSysVehicleMetricCell(
                                icon: "tag.fill",
                                label: "Category".localized,
                                value: guncelArac.kategori,
                                tint: PalantirTheme.accent
                            )
                            wheelSysVehicleMetricCell(
                                icon: "gauge.with.dots.needle.67percent",
                                label: "KM",
                                value: wheelSysDisplayKm.map { "\($0) km" } ?? "—",
                                tint: PalantirTheme.accent
                            )
                            wheelSysVehicleMetricCell(
                                icon: "fuelpump.fill",
                                label: "Fuel".localized,
                                value: wheelSysDisplayFuel.map { String(format: "wheelsys_ntr.fuel_step".localized, $0) } ?? "—",
                                tint: PalantirTheme.warning
                            )
                        }
                    }
                }
                if !isGaragePortalViewer {
                    WheelSysPalantirSectionCard(title: "Operations".localized, icon: "arrow.triangle.branch") {
                        VStack(spacing: 11) {
                            HStack(spacing: 11) {
                                PalantirOpsActionButton(
                                    title: "RETURN".localized,
                                    icon: "checkmark.shield.fill",
                                    style: .accent,
                                    titleScale: .large
                                ) {
                                    Task { await beginReturnFlow() }
                                }
                                PalantirOpsActionButton(
                                    title: "CHECK OUT".localized,
                                    icon: "arrow.right.circle.fill",
                                    style: latestResumableCheckout != nil ? .warning : .accent,
                                    titleScale: .large
                                ) {
                                    Task { await beginCheckoutFlow() }
                                }
                            }
                            PalantirOpsActionButton(
                                title: wheelSysNtrButtonTitle.uppercased(),
                                icon: "wrench.and.screwdriver",
                                style: .warning,
                                titleScale: .large
                            ) {
                                Task { await beginWheelSysNTRFlow() }
                            }

                            PalantirOpsActionButton(
                                title: "Damage".localized,
                                icon: "exclamationmark.triangle.fill",
                                style: .destructive,
                                titleScale: .large
                            ) {
                                beginDamageFlow()
                            }

                            if officeQuickActionsVisible {
                                HStack(spacing: 10) {
                                    Button {
                                        openQuickFuelSheet()
                                    } label: {
                                        PalantirOpsIconTile(
                                            systemName: "fuelpump.fill",
                                            tint: PalantirTheme.warning,
                                            size: 48
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("office_quick.fuel".localized)

                                    Button {
                                        openQuickWashingSheet()
                                    } label: {
                                        PalantirOpsIconTile(
                                            systemName: "drop.circle.fill",
                                            tint: PalantirTheme.accent,
                                            size: 48
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Washing".localized)

                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                wheelSysPalantirConditionFormCard
                wheelSysPalantirHistorySections
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .background(PalantirTheme.background)
    }

    private func palantirOpsButton(title: String, icon: String, tint: Color, disabled: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(PalantirTheme.labelFont(11))
        }
        .foregroundStyle(disabled ? PalantirTheme.textMuted : PalantirTheme.onAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(disabled ? PalantirTheme.border.opacity(0.35) : tint)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        .opacity(disabled ? 0.55 : 1)
    }

    private func wheelSysVehicleMetricCell(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PalantirOpsIconTile(systemName: icon, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                Text(value.isEmpty ? "—" : value)
                    .font(PalantirTheme.dataFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PalantirTheme.background.opacity(0.55))
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var wheelSysPalantirConditionFormCard: some View {
        WheelSysPalantirSectionCard(title: "Condition Form".localized, icon: "scribble.variable") {
            WheelSysPalantirStatusStrip(
                icon: "clock.arrow.circlepath",
                message: "wheelsys.damage_history.title".localized,
                tint: PalantirTheme.warning
            )
            WheelSysPalantirSecondaryButton(
                title: "Open Damage Records".localized,
                icon: "arrow.up.right.square"
            ) {
                openWheelSysDamageHistorySheet()
            }
        }
    }

    @ViewBuilder
    private var wheelSysPalantirHistorySections: some View {
        WheelSysPalantirSectionCard(title: "Damage Records".localized, icon: "exclamationmark.triangle.fill") {
            palantirHistoryHeader(
                title: "Damage Records".localized,
                icon: "exclamationmark.triangle.fill",
                count: aracHasarKayitlari.count,
                expanded: isDamageExpanded
            ) { isDamageExpanded.toggle() }
            if isDamageExpanded {
                if aracHasarKayitlari.isEmpty {
                    Text("No Damage Records".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(aracHasarKayitlari) { hasar in
                            damageRecordRow(hasar)
                        }
                    }
                }
            }
        }
        WheelSysPalantirSectionCard(title: "Return Processes".localized, icon: "arrow.uturn.backward.circle.fill") {
            palantirHistoryHeader(
                title: "Return Processes".localized,
                icon: "arrow.uturn.backward.circle.fill",
                count: aracIadeleri.count,
                expanded: isReturnExpanded
            ) { isReturnExpanded.toggle() }
            if isReturnExpanded {
                if aracIadeleri.isEmpty {
                    Text("No Return Operations".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(aracIadeleri) { iade in
                            NavigationLink(destination: IadeDetayView(iade: iade)) {
                                IadeSatirView(iade: iade)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        WheelSysPalantirSectionCard(title: "Check Out Operations".localized, icon: "arrow.right.circle.fill") {
            palantirHistoryHeader(
                title: "Check Out Operations".localized,
                icon: "arrow.right.circle.fill",
                count: aracExitleri.count,
                expanded: isExitExpanded
            ) { isExitExpanded.toggle() }
            if let parkedExit = latestReopenableCheckout {
                parkedCheckoutCalloutLink(exit: parkedExit)
            }
            if isExitExpanded {
                if aracExitleri.isEmpty {
                    Text("No Check Out Operations".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(aracExitleri) { exit in
                            NavigationLink(destination: ExitDetayView(exit: exit)) {
                                ExitSatirView(exit: exit, showKmFuelLine: false, emphasizePendingOutline: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func damageRecordRow(_ hasar: HasarKaydi) -> some View {
        HStack(alignment: .center, spacing: 8) {
            NavigationLink(
                destination: HasarDetayView(
                    hasar: hasar,
                    aracId: guncelArac.id,
                    aracPlaka: guncelArac.plakaFormatli
                )
            ) {
                HasarSatirView(hasar: hasar)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.light()
                damageRecordPendingDelete = hasar
            } label: {
                Group {
                    if isWheelSysCHEnabled {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PalantirTheme.critical)
                            .frame(width: 36, height: 36)
                            .background(PalantirTheme.critical.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete".localized)
        }
    }

    private func palantirHistoryHeader(
        title: String,
        icon: String,
        count: Int,
        expanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textPrimary)
                if count > 0 {
                    PalantirOpsBadge(text: "\(count)", tone: .accent)
                }
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(PalantirTheme.background.opacity(0.55))
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private var vehicleDetailList: some View {
        List {
            if let flag = activeServiceFlag {
                Section {
                    VehicleServiceFlagBanner(flag: flag, emphasize: scannedEntry) {
                        showVehicleServiceStatus = true
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.72)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(guncelArac.plakaFormatli)
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(latestReopenableCheckout != nil ? .orange : .primary)
                                    if latestReopenableCheckout != nil {
                                        Text("PARKING".localized)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }

                                Text("\(guncelArac.marka) \(guncelArac.model)")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let vin = guncelArac.vin, !vin.isEmpty {
                            Text("VIN: \(vin)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.caption)
                                Text(guncelArac.kategori)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: guncelArac.vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(guncelArac.vignetteVar ? .green : .orange)
                                Text("Vignette".localized)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((guncelArac.vignetteVar ? Color.green : Color.orange).opacity(0.15))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.caption)
                                Text("\(guncelArac.spareKeyCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)

                            if isTurkeyFranchiseForConditionFeatures {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption)
                                    Text(TurkiyeGarajSubeleri.displayTitle(forStoredKey: guncelArac.garageBranchId))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Kayıt Tarihi".localized, systemImage: "calendar")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(guncelArac.kayitTarihi, style: .date)
                            .fontWeight(.semibold)
                    }

                    if let km = lastRecordedKm {
                        HStack {
                            Label("vehicle_detail.last_recorded_km".localized, systemImage: "gauge.with.dots.needle.67percent")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(km) km")
                                .fontWeight(.semibold)
                                .foregroundStyle(FleetInspectionTheme.accent)
                        }
                    }
                    
                            if !isGaragePortalViewer {
                                VStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        Button {
                                            Task { await beginReturnFlow() }
                                        } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: "checkmark.shield.fill")
                                                    .font(.title2)
                                                Text("RETURN".localized)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.blue)
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        Button {
                                            Task { await beginCheckoutFlow() }
                                        } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: "arrow.right.circle.fill")
                                                    .font(.title2)
                                                Text("CHECK OUT".localized)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(latestResumableCheckout != nil ? Color.orange : Color.blue)
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }

                            if officeQuickActionsVisible {
                                HStack(spacing: 10) {
                                    Button {
                                        openQuickFuelSheet()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "fuelpump.fill")
                                            Text("office_quick.fuel".localized)
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.orange.opacity(0.9))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    Button {
                                        openQuickWashingSheet()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "drop.circle.fill")
                                            Text("Washing".localized)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.cyan.opacity(0.85))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }

                            if !isWheelSysCHEnabled {
                                Button {
                                    showGarageServiceHub = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "wrench.and.screwdriver.fill")
                                            .font(.title3)
                                        Text("garage_service.hub_entry".localized)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    // Assistant Company Section
                    VStack(spacing: 8) {
                        Divider()
                        
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                            Text("Assistant Company".localized)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                showCompanyPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    if let company = selectedCompany {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(company.name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            Text(company.phoneNumber)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text("Select".localized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }

                    if isWheelSysCHEnabled && !isGaragePortalViewer {
                        VStack(spacing: 8) {
                            Divider()
                            Button {
                                Task { await beginWheelSysNTRFlow() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .font(.subheadline.weight(.semibold))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(wheelSysNtrButtonTitle)
                                            .font(.subheadline.weight(.semibold))
                                        if isVehicleInNTR,
                                           let doc = guncelArac.wheelsysNtrDocNo, !doc.isEmpty {
                                            Text(doc)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                                .foregroundColor(.orange)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Servis Durumu Alanı (Eğer servis kaydı varsa göster)
                    if let servis = aktifServis {
                        VStack(spacing: 12) {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Servis Durumu".localized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: servis.durum.icon)
                                            .font(.title3)
                                            .foregroundColor(Color(servis.durum.renk))
                                        
                                        Text(servis.durum.displayTitle)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if !servis.servisFirmaAdi.isEmpty {
                                            Text("• \(servis.servisFirmaAdi)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Menu {
                                    ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                                        Button {
                                            servisDurumGuncelle(servis: servis, yeniDurum: durum)
                                        } label: {
                                            HStack {
                                                Text(durum.displayTitle)
                                                if servis.durum == durum {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("İstatistikler".localized) {
                if !isGaragePortalViewer {
                    Button {
                        showVehicleServiceStatus = true
                    } label: {
                        serviceStatusStatisticsRow
                    }
                    .buttonStyle(.plain)
                }

                if isWheelSysCHEnabled {
                    Button {
                        openWheelSysDamageHistorySheet()
                    } label: {
                        HStack {
                            Label("wheelsys.damage_history.title".localized, systemImage: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        openConditionFormSheet()
                    } label: {
                        HStack {
                            Label("Condition Form".localized, systemImage: "scribble.variable")
                                .foregroundColor(.orange)
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Label("Toplam Hasar".localized, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(aracHasarKayitlari.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("garage_service.stats_row_title".localized, systemImage: "wrench.and.screwdriver.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(viewModel.garageServiceJobs(forVehicleId: guncelArac.id).count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Washing Records".localized, systemImage: "drop.fill")
                        .foregroundColor(.teal)
                    Spacer()
                    Text("\(aracYikamaKayitlari.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Spare Keys".localized, systemImage: "key.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(guncelArac.spareKeyCount)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("İade İşlemleri".localized, systemImage: "checkmark.shield.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(aracIadeleri.count)")
                        .fontWeight(.semibold)
                }
                
                if let headDocURL = guncelArac.headDocumentURL, !headDocURL.isEmpty {
                    Button {
                        loadAndShowHeadDocument(url: headDocURL)
                    } label: {
                        HStack {
                            Label("View Head Document".localized, systemImage: "doc.text.image")
                            Spacer()
                            if isLoadingHeadDoc {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Damage Records - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isDamageExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                        
                        Text("Damage Records".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if !aracHasarKayitlari.isEmpty {
                            Text("(\(aracHasarKayitlari.count))")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isDamageExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    beginDamageFlow()
                } label: {
                    Label(aracHasarKayitlari.isEmpty ? "Add First Damage Record" : "Add Damage Record", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                
                if isDamageExpanded {
                if aracHasarKayitlari.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                                .foregroundColor(.gray)
                        Text("No Damage Records".localized)
                            .font(.headline)
                        Text("This vehicle has no recorded damages.".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(aracHasarKayitlari) { hasar in
                        damageRecordRow(hasar)
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    damageRecordPendingDelete = hasar
                                } label: {
                                    Label("Delete".localized, systemImage: "trash")
                                }
                            }
                    }
                }
                }
            }
            
            // Return Processes - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isReturnExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                        
                        Text("Return Processes".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if !aracIadeleri.isEmpty {
                            Text("(\(aracIadeleri.count))")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isReturnExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if isReturnExpanded {
                    if aracIadeleri.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 40))
                                .foregroundColor(.gray)
                        Text("No Return Operations".localized)
                            .font(.headline)
                        Text("This vehicle has no recorded return operations.".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    } else {
                        ForEach(aracIadeleri) { iade in
                            NavigationLink(destination: IadeDetayView(iade: iade)) {
                                IadeSatirView(iade: iade)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        }
                    }
                }
            }

            if shouldShowWebHandoverBanner {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "ipad.and.arrow.forward")
                                .foregroundColor(.orange)
                            Text("Web handover ready".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                        Text("Customer & NAV are prefilled from Front Desk — add checkout photos to finish.".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            selectedExitForEditing = nil
                            trExitSheetHandover = trCheckoutHandover
                            exitIslemGoster = true
                        } label: {
                            Text("Open check-out".localized)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.orange.opacity(0.12))
            }
            
            // Check Out Processes - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExitExpanded.toggle()
                    }
                } label: {
                    let parked = latestReopenableCheckout != nil
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.body)
                            .foregroundColor(parked ? .orange : .blue)
                        
                        Text("Check Out Processes".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(parked ? .orange : .blue)
                        
                        if !aracExitleri.isEmpty {
                            Text("(\(aracExitleri.count))")
                                .font(.caption)
                                .foregroundColor((parked ? Color.orange : Color.blue).opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExitExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(parked ? .orange : .blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(parked ? Color.orange.opacity(0.14) : Color(.systemGray5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(parked ? Color.orange.opacity(0.38) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                if !isExitExpanded, let parkedExit = latestReopenableCheckout {
                    parkedCheckoutCalloutLink(exit: parkedExit)
                }
                
                if isExitExpanded {
                    if let parkedExit = latestReopenableCheckout {
                        parkedCheckoutCalloutLink(exit: parkedExit)
                    }
                    if aracExitleri.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No Check Out Operations".localized)
                                .font(.headline)
                            Text("This vehicle has no recorded check out operations.".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(aracExitleri) { exit in
                            NavigationLink(destination: ExitDetayView(exit: exit)) {
                                ExitSatirView(exit: exit, showKmFuelLine: false, emphasizePendingOutline: true)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Aracı Sil".localized, systemImage: "trash.fill")
                }
            }
        }
    }

    var body: some View {
        vehicleDetailAlertLayer
    }

    private var vehicleDetailLifecycleChrome: some View {
        vehicleDetailRoot
        .onAppear {
            viewModel.attachIadeHistoryListenerIfNeeded()
            viewModel.attachExitHistoryListenerIfNeeded()
            serviceFlagStore.startListening()
            if isWheelSysCHEnabled {
                fleetStatusStore.bootstrapFromDiskIfNeeded()
            }
            if OptimizationFeatureFlags.detailMemoV2 {
                rebuildDerivedCaches()
            } else {
                rebuildWheelSysActionCaches()
            }
            refreshTurkeyHandoverPrefills()
            if scannedEntry, activeServiceFlag != nil {
                HapticManager.shared.error()
                showScanServiceAlert = true
            }
            if isWheelSysCHEnabled {
                Task(priority: .utility) {
                    await wheelSysSession.refreshSessionStatus()
                    await ensureCHFleetReady(syncEntities: false)
                }
            }
        }
        .onChange(of: wheelSysFleetDisplayToken) { _, _ in
            rebuildWheelSysActionCaches()
        }
        .onChange(of: guncelArac.id) { _, _ in
            if OptimizationFeatureFlags.detailMemoV2 {
                rebuildDerivedCaches()
            }
            refreshTurkeyHandoverPrefills()
        }
        .onChange(of: vehicleOperationsCacheToken) { _, _ in
            if OptimizationFeatureFlags.detailMemoV2 {
                rebuildDerivedCaches()
            }
        }
        .onChange(of: trCheckoutHandover?.frontDeskDocumentId) { _, newId in
            guard let newId else { return }
            guard latestReopenableCheckout == nil, !vehicleLikelyOut else { return }
            guard lastAutoOpenedHandoverDocId != newId else { return }
            lastAutoOpenedHandoverDocId = newId
            selectedExitForEditing = nil
            trExitSheetHandover = trCheckoutHandover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                exitIslemGoster = true
            }
        }
        .navigationTitle("Araç Detayları".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isGaragePortalViewer {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        duzenlemeGoster = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                    }
                }
            }
        }
        .background {
            JarvisLearningBeacon(screen: "VehicleDetail", action: guncelArac.plaka)
        }
        .onDisappear {
            serviceFlagStore.stopListening()
        }
    }

    private var vehicleDetailBasicSheets: some View {
        vehicleDetailLifecycleChrome
        .sheet(isPresented: $showGarageServiceHub) {
            NavigationStack {
                VehicleGarageServiceHubView(arac: guncelArac)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showVehicleServiceStatus) {
            VehicleServiceStatusSheet(arac: guncelArac)
                .environmentObject(viewModel)
                .environmentObject(authManager)
        }
        .alert("vehicle_service_flag.scan_alert_title".localized, isPresented: $showScanServiceAlert) {
            Button("OK".localized, role: .cancel) {}
            Button("vehicle_service_flag.manage_entry".localized) {
                showVehicleServiceStatus = true
            }
        } message: {
            if let flag = activeServiceFlag {
                Text("\(flag.kind.localizedTitle)\n\(flag.note)")
            }
        }
        .sheet(isPresented: $duzenlemeGoster) {
            NavigationView {
                AracDuzenleView(arac: guncelArac)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $hasarEkleGoster) {
            SheetWrapper {
                NavigationView {
                    HasarEkleView(aracId: guncelArac.id) { completedHasar in
                        selectedDamagePreviewId = completedHasar.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showHasarDetay = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $checkInGoster) {
            if let exit = latestOpenOutboundExit {
                SheetWrapper {
                    NavigationView {
                        CheckInView(aracId: guncelArac.id, linkedExit: exit)
                    }
                }
            }
        }
        .sheet(isPresented: $exitIslemGoster, onDismiss: {
            trExitSheetHandover = nil
            wheelSysCheckoutPrefill = nil
        }) {
            SheetWrapper {
                NavigationView {
                    ExitIslemView(
                        arac: guncelArac,
                        existingExit: selectedExitForEditing,
                        trHandoverPrefill: trExitSheetHandover,
                        wheelSysCheckoutPrefill: wheelSysCheckoutPrefill,
                        unparkOnWheelSysJournalResume: selectedExitForEditing?.status == .parked
                    ) { completedExit in
                        selectedExitPreviewId = completedExit.id
                        refreshTurkeyHandoverPrefills()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showExitDetay = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $iadeIslemGoster, onDismiss: {
            iadeSheetHandover = nil
            wheelSysReturnPrefill = nil
        }) {
            SheetWrapper {
                NavigationView {
                    IadeIslemView(
                        arac: guncelArac,
                        trReturnHandoverPrefill: iadeSheetHandover,
                        wheelSysReturnPrefill: wheelSysReturnPrefill
                    ) { completedIade in
                        selectedIade = completedIade
                        refreshTurkeyHandoverPrefills()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showIadeDetay = true
                        }
                    }
                }
            }
        }
    }

    private var vehicleDetailOperationSheets: some View {
        vehicleDetailBasicSheets
        .sheet(isPresented: $showQuickFuelOfficeSheet) {
            NavigationView {
                VehicleQuickOfficeOperationSheet(kind: .fuel, arac: guncelArac)
                    .environmentObject(viewModel)
            }
            .wheelSysCHOpsChrome()
        }
        .sheet(isPresented: $showQuickWashingOfficeSheet) {
            NavigationView {
                VehicleQuickOfficeOperationSheet(kind: .washing, arac: guncelArac)
                    .environmentObject(viewModel)
            }
            .wheelSysCHOpsChrome()
        }
        .sheet(isPresented: $showHeadDocument) {
            NavigationView {
                HeadDocumentPreviewView(image: headDocumentImage)
            }
        }
        .sheet(isPresented: $showIadeDetay) {
            if let iade = selectedIade {
                NavigationView {
                    IadeDetayView(iade: iade)
                }
            }
        }
        .sheet(isPresented: $showExitDetay) {
            if let exitId = selectedExitPreviewId,
               let exit = viewModel.exitIslemleri.first(where: { $0.id == exitId }) {
                NavigationView {
                    ExitDetayView(exit: exit)
                }
            }
        }
        .sheet(isPresented: $showHasarDetay) {
            if let damageId = selectedDamagePreviewId,
               let hasar = aracHasarKayitlari.first(where: { $0.id == damageId }) {
                NavigationView {
                    HasarDetayView(hasar: hasar, aracId: guncelArac.id, aracPlaka: guncelArac.plakaFormatli)
                }
            }
        }
        .sheet(isPresented: $showCompanyPicker) {
            CompanyPickerView(
                selectedCompany: Binding(
                    get: { selectedCompany },
                    set: { newCompany in
                        var updatedArac = guncelArac
                        updatedArac.assistantCompanyName = newCompany?.name
                        updatedArac.assistantCompanyPhone = newCompany?.phoneNumber
                        viewModel.aracGuncelle(updatedArac)
                        arac = updatedArac
                    }
                )
            )
            .environmentObject(viewModel)
        }
    }

    private var vehicleDetailWheelSysSheets: some View {
        vehicleDetailOperationSheets
        .sheet(isPresented: $showWheelSysLogin) {
            WheelSysLoginSheet(
                isSaving: wheelSysSession.loginSaving,
                requireFreshLogin: wheelSysSession.requiresFreshLogin,
                onSessionCaptured: { cookie in
                    Task {
                        await wheelSysSession.saveCapturedSession(cookie)
                        if wheelSysSession.sessionValid {
                            showWheelSysLogin = false
                            let resume = wheelSysLoginResume
                            wheelSysLoginResume = nil
                            switch resume {
                            case .checkoutFlow:
                                await ensureCHFleetReady(force: true, syncEntities: true)
                                await beginCheckoutFlow()
                            case .returnFlow:
                                await beginReturnFlow()
                            case .ntr:
                                showWheelSysNTR = true
                            case nil:
                                break
                            }
                        }
                    }
                },
                onCancel: {
                    wheelSysLoginResume = nil
                    showWheelSysLogin = false
                }
            )
        }
        .sheet(isPresented: $showWheelSysNTR) {
            WheelSysNTRActionSheet(
                arac: guncelArac,
                fleetVehicle: fleetStatusStore.fleetVehicle(for: guncelArac),
                onComplete: {
                    showWheelSysNTR = false
                    Task(priority: .utility) {
                        await fleetStatusStore.refresh(force: true)
                        rebuildWheelSysActionCaches()
                    }
                },
                onCancel: { showWheelSysNTR = false }
            )
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $showConditionForm) {
            NavigationStack {
                ConditionFormView(arac: guncelArac)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showWheelSysDamageHistory) {
            WheelSysVehicleDamageHistoryView(arac: guncelArac)
        }
    }

    private var vehicleDetailAlertLayer: some View {
        vehicleDetailWheelSysSheets
        .alert("wheelsys_ntr.blocked_title".localized, isPresented: $showNTRBlockedAlert) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(ntrBlockedMessage)
        }
        .alert("checkout.duplicate_confirm.title".localized, isPresented: $showDuplicateCheckoutConfirm) {
            Button("Cancel".localized, role: .cancel) {
                duplicateCheckoutForConfirm = nil
            }
            Button("checkout.duplicate_confirm.start_new".localized) {
                duplicateCheckoutForConfirm = nil
                Task { await beginCheckoutFlow(forceNewCheckout: true) }
            }
        } message: {
            if let exit = duplicateCheckoutForConfirm {
                Text(duplicateCheckoutConfirmMessage(for: exit))
            }
        }
        .alert("Delete check-in?".localized, isPresented: Binding(
            get: { checkInSilmeOnayi != nil },
            set: { if !$0 { checkInSilmeOnayi = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { checkInSilmeOnayi = nil }
            Button("Delete".localized, role: .destructive) {
                if let snap = checkInSilmeOnayi {
                    viewModel.aracCheckInKaydiSil(aracId: guncelArac.id, checkInId: snap.id) { ok in
                        if ok {
                            ToastManager.shared.show("Check-in removed".localized, type: .info)
                        }
                    }
                }
                checkInSilmeOnayi = nil
            }
        } message: {
            Text("This removes only this check-in record from the vehicle.".localized)
        }
        .alert("Delete damage record?".localized, isPresented: Binding(
            get: { damageRecordPendingDelete != nil },
            set: { if !$0 { damageRecordPendingDelete = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { damageRecordPendingDelete = nil }
            Button("Delete".localized, role: .destructive) {
                if let h = damageRecordPendingDelete {
                    viewModel.hasarSil(aracId: guncelArac.id, hasarId: h.id)
                    HapticManager.shared.success()
                    damageRecordPendingDelete = nil
                }
            }
        } message: {
            Text("This removes only this damage record from the vehicle.".localized)
        }
        .alert("Aracı Sil".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Sil".localized, role: .destructive) {
                viewModel.aracSil(guncelArac) { ok in
                    if ok {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            dismiss()
                        }
                    }
                }
            }
        } message: {
            Text("Bu aracı ve tüm hasar kayıtlarını silmek istediğinizden emin misiniz?".localized)
        }
        .onAppear {
            arac = guncelArac
        }
    }
    
    func servisDurumGuncelle(servis: Servis, yeniDurum: Servis.ServisDurum) {
        guard servis.durum != yeniDurum else { return }
        
        var guncellenmisServis = servis
        guncellenmisServis.durum = yeniDurum
        
        // Eğer tamamlandı ise teslim tarihini ayarla
        if yeniDurum == .tamamlandi && guncellenmisServis.teslimTarihi == nil {
            guncellenmisServis.teslimTarihi = Date()
        }
        
        viewModel.servisGuncelle(guncellenmisServis)
        
        // Show success toast
        ToastManager.shared.show("✓ Service Status Updated", type: .success)
    }
    
    func loadAndShowHeadDocument(url: String) {
        isLoadingHeadDoc = true
        
        guard let imageURL = URL(string: url) else {
            isLoadingHeadDoc = false
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                isLoadingHeadDoc = false
                
                if let data = data, let image = UIImage(data: data) {
                    headDocumentImage = image
                    showHeadDocument = true
                } else {
                    print("❌ Failed to load head document image")
                }
            }
        }.resume()
    }
}

struct HeadDocumentPreviewView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage?
    
    var body: some View {
        VStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(Color.gray)
                    Text("Image not available".localized)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Head Document".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
}

struct HasarSatirView: View {
    let hasar: HasarKaydi
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode
    
    var body: some View {
        HStack(spacing: 12) {
            if palantirMode {
                PalantirOpsIconTile(systemName: statusIcon, tint: statusColor, size: 38)
            } else {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: statusIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(statusColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasar.resKodu)
                            .font(palantirMode ? PalantirTheme.dataFont(14) : .system(size: 15, weight: .semibold))
                            .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : Color.primary)
                        
                        if !hasar.notlar.isEmpty {
                            Text(hasar.notlar)
                                .font(palantirMode ? PalantirTheme.bodyFont(11) : .system(size: 12, weight: .medium))
                                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    statusBadge
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                        Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                            .font(palantirMode ? PalantirTheme.dataFont(11) : .system(size: 12))
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 11))
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                        Text("\(hasar.km) km")
                            .font(palantirMode ? PalantirTheme.dataFont(11) : .system(size: 12, weight: .medium))
                            .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                    }
                    
                    if !hasar.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.gray)
                            Text("\(hasar.fotograflar.count)")
                                .font(palantirMode ? PalantirTheme.dataFont(11) : .system(size: 12, weight: .medium))
                                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(palantirMode ? 0 : 12)
        .background {
            if !palantirMode {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                    )
            }
        }
        .modifier(ConditionalPalantirRowSurface(enabled: palantirMode))
        .shadow(color: palantirMode ? .clear : .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 2, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        hasar.durum == .done ? .green : .orange
    }
    
    private var statusIcon: String {
        hasar.durum == .done ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(hasar.durum == .done ? "Done" : "In Progress")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}

struct AddWashingForVehicleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    
    @State private var price: String = ""
    @State private var notes: String = ""
    @State private var selectedImages: [UIImage] = []
    @State private var isSaving = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    
    var body: some View {
        Form {
            Section("Vehicle".localized) {
                HStack {
                    Label(arac.plakaFormatli, systemImage: "car.fill")
                    Spacer()
                    Text("\(arac.marka) \(arac.model)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Washing Price (\(AppCurrency.code))*".localized) {
                HStack {
                    Image(systemName: "eurosign.circle.fill")
                        .foregroundColor(.teal)
                    TextField("0.00", text: $price)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Photos (optional)".localized) {
                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedImages.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 92, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Button {
                                        selectedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                
                Button {
                    guard !showCamera else { return }
                    showImagePicker = true
                } label: {
                    Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
                }
                
                Button {
                    guard !showImagePicker else { return }
                    showCamera = true
                } label: {
                    Label("Take Photo".localized, systemImage: "camera")
                }
            }
            
            Section("Notes".localized) {
                TextEditor(text: $notes)
                    .frame(height: 90)
            }
            
            Section {
                HStack(spacing: 12) {
                    Button("Cancel".localized) { dismiss() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    
                    Button {
                        saveWashing()
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView()
                                Text("Saving...".localized)
                            }
                        } else {
                            Text("Add Washing".localized)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving || !isValid)
                    .tint(Color.teal.opacity(0.85))
                }
            }
        }
        .navigationTitle("Add Washing".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let image = capturedImage {
                selectedImages.append(image)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
        .onAppear {
            if let remembered = viewModel.lastWashingPriceForCurrentFranchise() {
                price = String(format: "%.2f", remembered)
            }
        }
    }
    
    private var isValid: Bool {
        guard let amount = Double(price), amount > 0 else { return false }
        return true
    }
    
    private func saveWashing() {
        guard let amount = Double(price), amount > 0 else { return }
        isSaving = true
        
        let group = DispatchGroup()
        let lock = NSLock()
        var photoURLs: [String] = []
        
        for image in selectedImages {
            group.enter()
            let path = "washing_records/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, _ in
                if let url {
                    lock.lock()
                    photoURLs.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            viewModel.addWashingRecord(
                aracId: arac.id,
                price: amount,
                photoURLs: photoURLs,
                notes: notes
            ) { success in
                isSaving = false
                if success {
                    ToastManager.shared.show("✓ Washing record saved", type: .success)
                    dismiss()
                }
            }
        }
    }
}

struct WashingRecordDetailSheetView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let aracId: UUID
    let record: VehicleWashingRecord
    let onClose: () -> Void
    
    @State private var priceText: String = ""
    @State private var notesText: String = ""
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var selectedPhotoIndex = 0
    @State private var showPhotoGallery = false
    
    private var isValid: Bool {
        guard let value = Double(priceText), value > 0 else { return false }
        return true
    }
    
    var body: some View {
        Form {
            Section("Details".localized) {
                HStack {
                    Label("Created By".localized, systemImage: "person.fill")
                    Spacer()
                    Text(record.createdBy)
                }
                
                HStack {
                    Label("Created At".localized, systemImage: "clock")
                    Spacer()
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            
            Section("Washing Price (\(AppCurrency.code))".localized) {
                HStack {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code)
                        .foregroundColor(.secondary)
                }
            }
            
            if !record.photoURLs.isEmpty {
                Section(String(format: "Photos (%d)".localized, record.photoURLs.count)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(record.photoURLs.enumerated()), id: \.offset) { index, url in
                                Button {
                                    selectedPhotoIndex = index
                                    showPhotoGallery = true
                                } label: {
                                    AsyncImageView(urlString: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 92, height: 92)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            
            Section("Notes".localized) {
                TextEditor(text: $notesText)
                    .frame(height: 100)
            }
            
            Section {
                Button {
                    updateRecord()
                } label: {
                    if isSaving {
                        HStack {
                            ProgressView()
                            Text("Saving...".localized)
                        }
                    } else {
                        Label("Save Changes".localized, systemImage: "checkmark.circle.fill")
                    }
                }
                .disabled(isSaving || !isValid)
                
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Washing Record".localized, systemImage: "trash.fill")
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Washing Record".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close".localized) {
                    dismiss()
                    onClose()
                }
            }
        }
        .fullScreenCover(isPresented: $showPhotoGallery) {
            NativePhotoGalleryView(urlStrings: record.photoURLs, initialIndex: selectedPhotoIndex)
        }
        .alert("Delete Washing Record".localized, isPresented: $showDeleteConfirm) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Delete".localized, role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text("This action cannot be undone.".localized)
        }
        .onAppear {
            priceText = String(format: "%.2f", record.price)
            notesText = record.notes ?? ""
        }
    }
    
    private func updateRecord() {
        guard let price = Double(priceText), price > 0 else { return }
        isSaving = true
        viewModel.updateWashingRecord(
            aracId: aracId,
            recordId: record.id,
            price: price,
            notes: notesText
        ) { success in
            isSaving = false
            guard success else { return }
            dismiss()
            onClose()
        }
    }
    
    private func deleteRecord() {
        isSaving = true
        viewModel.deleteWashingRecord(
            aracId: aracId,
            recordId: record.id
        ) { success in
            isSaving = false
            guard success else { return }
            dismiss()
            onClose()
        }
    }
}

