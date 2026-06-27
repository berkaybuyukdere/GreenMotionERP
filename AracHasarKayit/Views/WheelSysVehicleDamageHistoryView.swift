import SwiftUI

struct WheelSysVehicleDamageHistoryView: View {
    let arac: Arac
    var compact: Bool = false
    var rentalId: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var history: WheelSysVehicleDamageHistoryResponse?
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var loadFailed = false
    @State private var sessionExpiredVisible = false
    @State private var previewImages: [String: UIImage] = [:]
    @State private var previewFailures: Set<String> = []
    @State private var fullScreenImage: WheelSysCHFullScreenImage?

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    /// We have at least one damage record to render (live fetch or disk cache).
    private var hasDamages: Bool {
        (history?.damages.isEmpty == false)
    }

    var body: some View {
        Group {
            if compact {
                content
            } else {
                NavigationStack {
                    content
                        .navigationTitle("wheelsys.damage_history.title".localized)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close".localized) {
                                    HapticManager.shared.selection()
                                    dismiss()
                                }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    HapticManager.shared.selection()
                                    Task { await loadHistory(force: true) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(isLoading || isRefreshing)
                            }
                        }
                }
                .wheelSysCHOpsChrome()
            }
        }
        .task(id: "\(arac.id)-\(rentalId ?? 0)") {
            await loadHistory(force: rentalId != nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelSysSessionRestored)) { _ in
            // Avoid reload loops while damages are already visible or a fetch is in flight.
            guard loadFailed, !isLoading, !isRefreshing, !hasDamages else { return }
            Task { await loadHistory(force: true) }
        }
        .fullScreenCover(item: $fullScreenImage) { item in
            WheelSysCHImageViewer(image: item.image)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WheelSysPalantirOpsHeader(
                    title: compact
                        ? "wheelsys.damage_history.existing_title".localized
                        : "wheelsys.damage_history.title".localized,
                    subtitle: arac.plakaFormatli,
                    badge: history.map { "\($0.damageCount)" }
                )

                if (isLoading || isRefreshing) && history == nil && !loadFailed {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("ch_ops.loading_detail".localized)
                            .font(PalantirTheme.bodyFont(13))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }

                if hasDamages, let history {
                    // Live data or disk-cached damages — always show the list,
                    // even if a background refresh just failed.
                    ForEach(history.damages) { damage in
                        damageCard(damage)
                    }
                    Text("wheelsys.damage_history.synced_at".localized + " \(history.syncedAt)")
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else if loadFailed {
                    // No damages to show and the last fetch errored: never show
                    // the empty state. Distinguish a true session expiry from a
                    // transient failure (still has a usable session → retry).
                    if sessionExpiredVisible {
                        WheelSysPalantirStatusStrip(
                            icon: "exclamationmark.triangle.fill",
                            message: errorMessage ?? "wheelsys_fleet.session_expired".localized,
                            tint: PalantirTheme.critical
                        )
                    } else {
                        WheelSysPalantirStatusStrip(
                            icon: "arrow.clockwise",
                            message: "wheelsys.damage_history.retry".localized,
                            tint: PalantirTheme.warning
                        )
                    }
                    WheelSysPalantirSecondaryButton(
                        title: "wheelsys.damage_history.retry".localized,
                        icon: "arrow.clockwise"
                    ) {
                        Task { await loadHistory(force: true) }
                    }
                } else if history != nil {
                    // Backend returned success with zero damages.
                    WheelSysPalantirStatusStrip(
                        icon: "checkmark.circle",
                        message: "wheelsys.damage_history.empty".localized,
                        tint: PalantirTheme.success
                    )
                    if let history {
                        Text("wheelsys.damage_history.synced_at".localized + " \(history.syncedAt)")
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
            }
            .padding(compact ? 0 : 16)
        }
    }

    private func damageCard(_ damage: WheelSysVehicleDamageRecord) -> some View {
        WheelSysPalantirSectionCard(
            title: damage.displayTitle,
            icon: "exclamationmark.triangle.fill"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let damageType = damage.damageType?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !damageType.isEmpty {
                    metaRow("wheelsys.damage_history.type".localized, damageType)
                }
                if !damage.locationSummary.isEmpty {
                    metaRow("wheelsys.damage_history.location".localized, damage.locationSummary)
                }
                if let rental = damage.relatedRentalNo, !rental.isEmpty {
                    metaRow("RNT / R.A.", rental)
                }
                if let added = damage.addedOn, !added.isEmpty {
                    metaRow("wheelsys.damage_history.added_on".localized, added)
                }
                if let charge = damage.chargeText, !charge.isEmpty {
                    metaRow("wheelsys.damage_history.charge".localized, charge)
                }
                if let memo = damage.memo, !memo.isEmpty {
                    Text(memo)
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textMuted)
                }

                if !damage.previewAttachments.isEmpty {
                    Text("wheelsys.damage_history.tap_photo".localized)
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(damage.previewAttachments) { attachment in
                            attachmentThumbnail(attachment)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
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
    private func attachmentThumbnail(_ attachment: WheelSysVehicleDamageAttachment) -> some View {
        let cacheKey = attachmentCacheKey(attachment)
        let cachedImage = previewImages[cacheKey]
        let failed = previewFailures.contains(cacheKey)
        Button {
            HapticManager.shared.selection()
            if let cachedImage {
                fullScreenImage = WheelSysCHFullScreenImage(image: cachedImage)
            } else if failed {
                Task { await loadPreview(for: attachment, force: true) }
            }
        } label: {
            Group {
                if let cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    ZStack {
                        Rectangle().fill(PalantirTheme.surfaceHigh)
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PalantirTheme.warning)
                            Text("Retry".localized)
                                .font(PalantirTheme.labelFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                    }
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
        .disabled(cachedImage == nil && !failed)
        .task(id: cacheKey) {
            await loadPreview(for: attachment)
        }
    }

    private func attachmentCacheKey(_ attachment: WheelSysVehicleDamageAttachment) -> String {
        let preview = attachment.previewPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preview.isEmpty { return preview }
        return attachment.attachmentId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadHistory(force: Bool) async {
        if isLoading || isRefreshing { return }
        if !force, history != nil { return }

        if history == nil, let cached = WheelSysVehicleDamageDiskCache.load(
            franchiseId: franchiseId,
            plate: arac.plaka
        ) {
            history = cached
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "DamageUI",
                "showing disk cache damageCount=\(cached.damageCount) plate=\(arac.plaka)"
            )
        }

        if history == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        if force {
            errorMessage = nil
        }

        async let sessionReady: Void = WheelSysVehicleDamageService.ensureSessionReady(franchiseId: franchiseId)
        async let fleetReady: Void = WheelSysVehicleDamageService.ensureFleetReady(for: arac)

        do {
            _ = await sessionReady
            _ = await fleetReady
            let fetched = try await WheelSysVehicleDamageService.fetchDamageHistory(
                arac: arac,
                franchiseId: franchiseId,
                rentalId: rentalId,
                allowSessionRecoveryRetry: true
            )
            history = fetched
            errorMessage = nil
            loadFailed = false
            sessionExpiredVisible = false
        } catch {
            let msg = WheelSysUserFacingError.message(for: error)
            // Keep showing cached damages when a background refresh fails.
            if !hasDamages {
                loadFailed = true
            }
            sessionExpiredVisible = WheelSysVehicleDamageService.isSessionExpiryUserVisible(error)
            errorMessage = msg
            WheelSysDebug.warnCH(
                franchiseId: franchiseId,
                "DamageUI",
                "load failed cached=\(hasDamages) sessionExpired=\(sessionExpiredVisible) msg=\(msg)"
            )
            // Only prompt for re-login when the session is genuinely gone.
            if sessionExpiredVisible {
                WheelSysSessionPromptCenter.notifyIfSessionError(error)
            }
        }
    }

    @MainActor
    private func loadPreview(for attachment: WheelSysVehicleDamageAttachment, force: Bool = false) async {
        let cacheKey = attachmentCacheKey(attachment)
        guard !cacheKey.isEmpty, previewImages[cacheKey] == nil else { return }
        if !force, previewFailures.contains(cacheKey) { return }
        do {
            let image = try await withThrowingTaskGroup(of: UIImage.self) { group in
                group.addTask {
                    try await WheelSysVehicleDamageService.loadPreviewImage(previewPath: cacheKey)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 18_000_000_000)
                    throw WheelSysVehicleDamageServiceError.operationFailed("Preview timeout.")
                }
                guard let first = try await group.next() else {
                    throw WheelSysVehicleDamageServiceError.operationFailed("Preview failed.")
                }
                group.cancelAll()
                return first
            }
            previewImages[cacheKey] = image
            previewFailures.remove(cacheKey)
        } catch {
            previewFailures.insert(cacheKey)
            if WheelSysVehicleDamageService.isSessionExpiryUserVisible(error) {
                sessionExpiredVisible = true
                WheelSysSessionPromptCenter.notifyIfSessionError(error)
            }
        }
    }
}

struct WheelSysExistingVehicleDamagesSection: View {
    let arac: Arac
    var rentalId: Int? = nil

    var body: some View {
        WheelSysVehicleDamageHistoryView(arac: arac, compact: true, rentalId: rentalId)
    }
}
