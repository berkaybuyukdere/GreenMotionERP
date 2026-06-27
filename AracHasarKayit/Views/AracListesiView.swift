import SwiftUI

private struct ScannedVehicleRoute: Hashable {
    let vehicleId: UUID
    let fromScan: Bool
    let eventId = UUID()

    init(vehicleId: UUID, fromScan: Bool = true) {
        self.vehicleId = vehicleId
        self.fromScan = fromScan
    }
}

private struct FleetOpsVehicleRowCache: Identifiable {
    let vehicle: Arac
    let microLine: String?
    let badge: WheelSysFleetOpsBadge?
    var id: UUID { vehicle.id }
}

struct AracListesiView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var navigateToVehicleId: UUID?
    @State private var yeniAracGoster = false
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var showParkedCheckoutsSheet = false
    @State private var showCategoryManagerSheet = false
    @State private var showFleetImportSheet = false
    @State private var vehiclesByCategoryCache: [String: [Arac]] = [:]
    @State private var lastScannedVehicleId: UUID?
    @State private var lastScannedAt: Date = .distantPast
    @State private var pendingScanVehicleId: UUID?
    @State private var pendingScanAttempts = 0
    @State private var fleetOpsFilter: VehicleFleetOpsFilter = .all
    @State private var cachedOpsFilteredAraclar: [Arac] = []
    @State private var cachedOpsRowMetadata: [UUID: FleetOpsVehicleRowCache] = [:]
    @ObservedObject private var fleetStatusStore = WheelSysVehicleFleetStatusStore.shared

    private var isCHFleetOpsEnabled: Bool {
        FranchiseCapabilityMatrix.wheelSysFleetOpsEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) && garagePortalLinkedCompanyId == nil
    }

    private var parkedVehicleIds: Set<UUID> {
        Set(viewModel.exitIslemleri.filter { $0.status == .parked }.map(\.aracId))
    }

    private var opsFilteredAraclar: [Arac] {
        cachedOpsFilteredAraclar
    }

    /// Cheap: recompute only the *visible subset* for the current filter using the
    /// precomputed id sets from `updateFilterCounts`. Row metadata is cached separately
    /// (full fleet, see `rebuildRowMetadataCache`) so switching filters no longer rebuilds
    /// per-row badges/micro-lines — that was the main source of the chip-tap stutter.
    private func rebuildOpsFilteredCache() {
        if isCHFleetOpsEnabled, fleetOpsFilter != .all {
            cachedOpsFilteredAraclar = fleetStatusStore.filteredAraclar(
                from: listSourceAraclar,
                filter: fleetOpsFilter,
                parkedVehicleIds: parkedVehicleIds,
                openCheckoutVehicleIds: openCheckoutVehicleIds(for: listSourceAraclar),
                inProgressCheckoutVehicleIds: inProgressCheckoutVehicleIds(for: listSourceAraclar)
            )
        } else {
            cachedOpsFilteredAraclar = listSourceAraclar
        }
    }

    /// Precompute per-vehicle row metadata (micro-line + ops badge) ONCE for the full
    /// fleet, keyed by id, and reuse it across every filter switch (metadata is
    /// filter-independent — only the visible subset changes). Open-checkout lookup uses a
    /// single precomputed `Set<UUID>` instead of an O(M) `exitIslemleri(for:)` plate-regex
    /// scan per row, which removes the O(N·M) main-thread cost on first appear / data change.
    private func rebuildRowMetadataCache() {
        guard isCHFleetOpsEnabled else {
            cachedOpsRowMetadata = [:]
            return
        }
        let vehicles = listSourceAraclar
        let inProgressIds = inProgressCheckoutVehicleIds(for: vehicles)
        var metadata: [UUID: FleetOpsVehicleRowCache] = [:]
        metadata.reserveCapacity(vehicles.count)
        for vehicle in vehicles {
            metadata[vehicle.id] = FleetOpsVehicleRowCache(
                vehicle: vehicle,
                microLine: fleetStatusStore.fleetMicroSummary(for: vehicle),
                badge: fleetStatusStore.fleetOpsBadge(
                    for: vehicle,
                    hasActiveCheckout: inProgressIds.contains(vehicle.id)
                )
            )
        }
        cachedOpsRowMetadata = metadata
    }

    /// Build the set of vehicle ids that currently have an open checkout (in-progress or
    /// parked, not deleted) in a single O(M + N) pass — replacing the previous O(N·M)
    /// pattern where each row called `exitIslemleri(for:)` (filter + plate regex + sort).
    private func openCheckoutVehicleIds(for vehicles: [Arac]) -> Set<UUID> {
        let openExits = viewModel.exitIslemleri.filter {
            ($0.status == .inProgress || $0.status == .parked) && !$0.isDeleted
        }
        guard !openExits.isEmpty else { return [] }
        let vehicleIds = Set(vehicles.map(\.id))
        var plateToId: [String: UUID] = [:]
        plateToId.reserveCapacity(vehicles.count)
        for vehicle in vehicles {
            let key = VehicleOperationMatching.normalizedPlateKey(vehicle.plaka)
            if !key.isEmpty { plateToId[key] = vehicle.id }
        }
        var result: Set<UUID> = []
        for exit in openExits {
            if vehicleIds.contains(exit.aracId) {
                result.insert(exit.aracId)
                continue
            }
            // Legacy fallback: rows that used a different vehicle UUID match by plate.
            let key = VehicleOperationMatching.normalizedPlateKey(exit.aracPlaka)
            if !key.isEmpty, let id = plateToId[key] {
                result.insert(id)
            }
        }
        return result
    }

    private func inProgressCheckoutVehicleIds(for vehicles: [Arac]) -> Set<UUID> {
        let inProgress = viewModel.exitIslemleri.filter {
            $0.status == .inProgress && !$0.isDeleted
        }
        guard !inProgress.isEmpty else { return [] }
        let vehicleIds = Set(vehicles.map(\.id))
        var plateToId: [String: UUID] = [:]
        for vehicle in vehicles {
            let key = VehicleOperationMatching.normalizedPlateKey(vehicle.plaka)
            if !key.isEmpty { plateToId[key] = vehicle.id }
        }
        var result: Set<UUID> = []
        for exit in inProgress {
            if vehicleIds.contains(exit.aracId) {
                result.insert(exit.aracId)
                continue
            }
            let key = VehicleOperationMatching.normalizedPlateKey(exit.aracPlaka)
            if !key.isEmpty, let id = plateToId[key] {
                result.insert(id)
            }
        }
        return result
    }

    private func rowMetadata(for vehicle: Arac) -> FleetOpsVehicleRowCache {
        if let cached = cachedOpsRowMetadata[vehicle.id] {
            return cached
        }
        return FleetOpsVehicleRowCache(
            vehicle: vehicle,
            microLine: fleetMicroLine(for: vehicle),
            badge: fleetOpsBadge(for: vehicle)
        )
    }

    private var fleetFilterCounts: [VehicleFleetOpsFilter: Int] {
        fleetStatusStore.filterCounts
    }

    private func refreshFleetFilterCounts() {
        guard isCHFleetOpsEnabled else {
            cachedOpsRowMetadata = [:]
            rebuildOpsFilteredCache()
            return
        }
        // Single pass each: counts/id-sets first, then full-fleet row metadata, then the
        // current visible subset. Previously this rebuilt the filtered cache twice (and
        // rebuilt per-row metadata each time) — the duplicate heavy work is removed.
        fleetStatusStore.updateFilterCounts(
            araclar: listSourceAraclar,
            parkedVehicleIds: parkedVehicleIds,
            openCheckoutVehicleIds: openCheckoutVehicleIds(for: listSourceAraclar),
            inProgressCheckoutVehicleIds: inProgressCheckoutVehicleIds(for: listSourceAraclar)
        )
        rebuildRowMetadataCache()
        rebuildOpsFilteredCache()
    }

    private var hasParkedCheckoutsStrip: Bool {
        viewModel.exitIslemleri.contains { $0.status == .parked }
    }

    private var parkedCheckoutsCount: Int {
        viewModel.exitIslemleri.filter { $0.status == .parked }.count
    }

    /// Marka + model for the most recently created parked checkout (subtitle under the parked strip).
    private var parkedCheckoutsTopVehicleSubtitle: String? {
        let parked = viewModel.exitIslemleri.filter { $0.status == .parked }
        guard let top = parked.max(by: { $0.createdAt < $1.createdAt }),
              let vehicle = viewModel.araclar.first(where: { $0.id == top.aracId }) else { return nil }
        let s = "\(vehicle.marka) \(vehicle.model)".trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func topVehicleMarkaModelLine(for vehicles: [Arac]) -> String? {
        guard let first = vehicles.first else { return nil }
        let s = "\(first.marka) \(first.model)".trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func rebuildCategoryCache() {
        var grouped: [String: [Arac]] = [:]
        for vehicle in listSourceAraclar {
            let normalizedCategory = vehicle.kategori.trimmingCharacters(in: .whitespacesAndNewlines)
            grouped[normalizedCategory, default: []].append(vehicle)
        }
        vehiclesByCategoryCache = grouped
    }

    private var canManageVehicleCategories: Bool {
        authManager.userProfile?.canManageVehicleCategories ?? false
    }

    /// `garage` role: Firestore `linkedGarageId` / `garageId` must match **ServisFirma.id** (same as `GarageServiceJob.targetGarageId` on new jobs).
    private var garagePortalLinkedCompanyId: String? {
        guard authManager.userProfile?.role == .garage else { return nil }
        let s = authManager.userProfile?.linkedGarageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    private var listSourceAraclar: [Arac] {
        guard let gid = garagePortalLinkedCompanyId else {
            return viewModel.araclar
        }
        let gLower = gid.lowercased()
        let matchingIds = Set(viewModel.garageServiceJobs.filter { $0.targetGarageId.lowercased() == gLower }.map(\.vehicleId))
        return viewModel.araclar.filter { matchingIds.contains($0.id) }
    }

    private var orderedCategoriesForList: [String] {
        let allowed = Set(listSourceAraclar.map { $0.kategori.trimmingCharacters(in: .whitespacesAndNewlines) })
        return viewModel.kategoriler.filter { allowed.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func vehiclesForCategory(_ category: String) -> [Arac] {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveFiltered = listSourceAraclar.filter {
            $0.kategori.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedCategory
        }
        guard OptimizationFeatureFlags.detailMemoV2 else {
            return liveFiltered
        }
        // Safety fallback: if cache is stale/empty while live data exists, do not hide vehicles.
        if let cached = vehiclesByCategoryCache[normalizedCategory], !cached.isEmpty {
            return cached
        }
        return liveFiltered
    }

    private func navigateToScannedVehicle(_ vehicleId: UUID?) {
        guard let vehicleId else {
            pendingScanVehicleId = nil
            pendingScanAttempts = 0
            return
        }
        if let _ = garagePortalLinkedCompanyId, !listSourceAraclar.contains(where: { $0.id == vehicleId }) {
            return
        }
        guard let vehicle = viewModel.araclar.first(where: { $0.id == vehicleId }) else {
            pendingScanVehicleId = vehicleId
            pendingScanAttempts += 1
            guard pendingScanAttempts <= 8 else {
                pendingScanVehicleId = nil
                pendingScanAttempts = 0
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                navigateToScannedVehicle(pendingScanVehicleId)
            }
            return
        }
        pendingScanVehicleId = nil
        pendingScanAttempts = 0
        let now = Date()
        if lastScannedVehicleId == vehicleId, now.timeIntervalSince(lastScannedAt) < 0.7 {
            return
        }
        lastScannedVehicleId = vehicleId
        lastScannedAt = now
        DispatchQueue.main.async {
            navigationPath.append(ScannedVehicleRoute(vehicleId: vehicle.id, fromScan: true))
            navigateToVehicleId = nil
        }
    }

    // Filtered vehicles based on search query
    private var filteredAraclar: [Arac] {
        let base = opsFilteredAraclar
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return base
        }
        let q = searchText.lowercased()
        return base.filter {
            $0.plakaFormatli.lowercased().contains(q) ||
            $0.marka.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.kategori.lowercased().contains(q)
        }
    }

    private var isFleetCategoryBrowseMode: Bool {
        !isSearchingVehicles && fleetOpsFilter == .all
    }

    private var isSearchingVehicles: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayedVehicleCount: Int {
        if isSearchingVehicles || (isCHFleetOpsEnabled && fleetOpsFilter != .all) {
            return filteredAraclar.count
        }
        return listSourceAraclar.count
    }

    private func fleetMicroLine(for vehicle: Arac) -> String? {
        guard isCHFleetOpsEnabled else { return nil }
        return fleetStatusStore.fleetMicroSummary(for: vehicle)
    }

    private func fleetOpsBadge(for vehicle: Arac) -> WheelSysFleetOpsBadge? {
        guard isCHFleetOpsEnabled else { return nil }
        let hasOpenCheckout = viewModel.exitIslemleri(for: vehicle).contains {
            ($0.status == .inProgress || $0.status == .parked) && !$0.isDeleted
        }
        return fleetStatusStore.fleetOpsBadge(for: vehicle, hasActiveCheckout: hasOpenCheckout)
    }

    private var fleetOpsFilterBar: some View {
        VehicleFleetOpsFilterBar(selected: $fleetOpsFilter, counts: fleetFilterCounts)
    }

    @ViewBuilder
    private var vehicleTotalHeaderCard: some View {
        if isCHFleetOpsEnabled {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Toplam Araç".localized.uppercased())
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                    Text("\(displayedVehicleCount)")
                        .font(PalantirTheme.dataFont(22))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .monospacedDigit()
                }
                Spacer()
                if isSearchingVehicles {
                    Text(String(format: "vehicles.count.filtered".localized, filteredAraclar.count, listSourceAraclar.count))
                        .font(PalantirTheme.bodyFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toplam Araç".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(displayedVehicleCount)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                if isSearchingVehicles {
                    Text(String(format: "vehicles.count.filtered".localized, filteredAraclar.count, listSourceAraclar.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var vehicleTotalHeader: some View {
        vehicleTotalHeaderCard
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    private static let opsListRowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    var body: some View {
        navigationStackWithScanHandlers
    }

    private var navigationTitleText: String {
        (authManager.userProfile?.role == .garage)
            ? "garage_portal.nav_title".localized
            : "Vehicles".localized
    }

    @ViewBuilder
    private var rootContent: some View {
        if viewModel.araclar.isEmpty {
            BosDurumView(yeniAracGoster: $yeniAracGoster)
        } else if garagePortalLinkedCompanyId != nil && listSourceAraclar.isEmpty {
            ContentUnavailableView(
                "garage_portal.empty_title".localized,
                systemImage: "wrench.and.screwdriver",
                description: Text("garage_portal.empty_detail".localized)
            )
        } else {
            vehicleListView
        }
    }

    private var navigationStackCore: some View {
        NavigationStack(path: $navigationPath) {
            rootContent
                .navigationTitle(navigationTitleText)
                .navigationBarTitleDisplayMode(isCHFleetOpsEnabled ? .inline : .large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by plate, model or category…".localized
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isCHFleetOpsEnabled {
                        fleetOpsFilterBar
                            .background {
                                PalantirTheme.background
                                    .ignoresSafeArea(edges: .horizontal)
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(PalantirTheme.border)
                                    .frame(height: 1)
                            }
                            .zIndex(10)
                    }
                }
                .toolbar { vehicleListToolbarContent }
                .navigationDestination(for: ScannedVehicleRoute.self) { route in
                    scannedVehicleDestination(for: route)
                }
        }
    }

    @ToolbarContentBuilder
    private var vehicleListToolbarContent: some ToolbarContent {
        if authManager.userProfile?.role != .garage {
            if canManageVehicleCategories {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCategoryManagerSheet = true } label: {
                        Image(systemName: "pencil.circle")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFleetImportSheet = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { yeniAracGoster = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
    }

    private var navigationStackWithFleetOps: some View {
        navigationStackCore
            .task(id: isCHFleetOpsEnabled) {
                guard isCHFleetOpsEnabled else { return }
                fleetStatusStore.bootstrapFromDiskIfNeeded()
                await fleetStatusStore.refreshIfNeeded()
                refreshFleetFilterCounts()
            }
            .onChange(of: fleetStatusStore.fleet?.vehiclesCount) { _, _ in
                refreshFleetFilterCounts()
            }
            .onChange(of: fleetStatusStore.loading) { _, loading in
                if !loading { refreshFleetFilterCounts() }
            }
            // NOTE: `viewModel.araclar` content changes are handled by the `.onChange(of:
            // viewModel.araclar)` in `navigationStackWithScanHandlers` (which also calls
            // `refreshFleetFilterCounts()`), so a separate `.count` observer here would be a
            // redundant double-refresh and is intentionally omitted.
            .onChange(of: viewModel.exitIslemleri.count) { _, _ in
                refreshFleetFilterCounts()
            }
            .onChange(of: fleetOpsFilter) { _, _ in
                rebuildOpsFilteredCache()
            }
            .refreshable {
                guard isCHFleetOpsEnabled else { return }
                await fleetStatusStore.refresh(force: true)
                refreshFleetFilterCounts()
            }
    }

    private var navigationStackWithSheets: some View {
        navigationStackWithFleetOps
            .sheet(isPresented: $yeniAracGoster) {
                NavigationView {
                    ManuelAracEkleView()
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
            }
            .sheet(isPresented: $showFleetImportSheet) {
                FleetImportSheetView()
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showCategoryManagerSheet) {
                NavigationView {
                    CategoryManagerView()
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
            }
            .sheet(isPresented: $showParkedCheckoutsSheet) {
                NavigationView {
                    ParkedCheckoutsListView()
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
            }
    }

    @ViewBuilder
    private func scannedVehicleDestination(for route: ScannedVehicleRoute) -> some View {
        if let vehicle = viewModel.araclar.first(where: { $0.id == route.vehicleId }) {
            AracDetayView(arac: vehicle, scannedEntry: route.fromScan)
                .environmentObject(viewModel)
                .environmentObject(authManager)
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(PalantirTheme.accent)
                Text("Vehicle not found".localized)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PalantirTheme.background)
            .onAppear {
                navigateToScannedVehicle(route.vehicleId)
            }
        }
    }

    private var navigationStackWithScanHandlers: some View {
        navigationStackWithSheets
            // iOS 17+: two-parameter onChange — first value is the *previous* binding value.
            .onChange(of: navigateToVehicleId) { _, newVehicleId in
                if let id = newVehicleId {
                    print("🔎 [ScanNav] Binding changed navigateToVehicleId -> \(id.uuidString)")
                } else {
                    print("🔎 [ScanNav] Binding changed navigateToVehicleId -> nil")
                }
                navigateToScannedVehicle(newVehicleId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openVehicleDetailFromScan)) { notification in
                guard let raw = notification.userInfo?["vehicleId"] as? String,
                      let vehicleId = UUID(uuidString: raw) else {
                    print("🔎 [ScanNav] Notification received but vehicleId missing/invalid")
                    return
                }
                let plate = (notification.userInfo?["plate"] as? String) ?? "?"
                print("🔎 [ScanNav] Notification received for plate=\(plate), id=\(vehicleId.uuidString)")
                navigateToScannedVehicle(vehicleId)
            }
            .onReceive(NotificationCenter.default.publisher(for: FleetDeepLink.pendingNotification)) { _ in
                if let filter = FleetDeepLink.consumePendingFleetFilter() {
                    fleetOpsFilter = filter
                }
            }
            .onAppear {
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
                refreshFleetFilterCounts()
                navigateToScannedVehicle(navigateToVehicleId)
            }
            .onChange(of: viewModel.araclar) { _, _ in
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
                refreshFleetFilterCounts()
                navigateToScannedVehicle(navigateToVehicleId)
            }
            .onChange(of: viewModel.garageServiceJobs.count) { _, _ in
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
            }
            .modifier(ConditionalWheelSysCHChrome(enabled: isCHFleetOpsEnabled))
    }

    // MARK: - Vehicle List View
    @ViewBuilder
    private var vehicleListView: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let showFlatOpsList = isCHFleetOpsEnabled && fleetOpsFilter != .all

        if showFlatOpsList || isSearching {
            if filteredAraclar.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        fleetOpsFilter.titleKey.localized,
                        systemImage: "car",
                        description: Text("No vehicles in this filter.".localized)
                    )
                }
            } else {
                List {
                    Section {
                        vehicleTotalHeaderCard
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredAraclar) { vehicle in
                        let row = rowMetadata(for: vehicle)
                        NavigationLink(destination: AracDetayView(arac: vehicle)) {
                            ModernAracSatirView(
                                arac: vehicle,
                                fleetMicroLine: row.microLine,
                                fleetOpsBadge: row.badge
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(Self.opsListRowInsets)
                    }
                }
                .listStyle(.plain)
                .fleetListPalantirChrome(enabled: isCHFleetOpsEnabled)
            }
        } else {
            categoriesFirstView
        }
    }

    // MARK: - Categories First View
    private var categoriesFirstView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                vehicleTotalHeader
                    .padding(.top, 4)

                if hasParkedCheckoutsStrip, garagePortalLinkedCompanyId == nil {
                    parkedCheckoutsStrip
                }

                ForEach(orderedCategoriesForList, id: \.self) { kategori in
                    let list = vehiclesForCategory(kategori)
                    CategoryExpandableCard(
                        name: kategori,
                        topVehicleSubtitle: topVehicleMarkaModelLine(for: list),
                        vehicles: list,
                        // Read from the precomputed full-fleet metadata cache (cheap dict
                        // lookup) rather than recomputing badge/micro-line per expanded row.
                        fleetMicroLine: { isCHFleetOpsEnabled ? rowMetadata(for: $0).microLine : nil },
                        fleetOpsBadge: { isCHFleetOpsEnabled ? rowMetadata(for: $0).badge : nil }
                    )
                }
            }
            .padding(.vertical, isCHFleetOpsEnabled ? 8 : 16)
        }
        .background(isCHFleetOpsEnabled ? PalantirTheme.background : Color.clear)
    }

    @ViewBuilder
    private var parkedCheckoutsStrip: some View {
        Button {
            showParkedCheckoutsSheet = true
        } label: {
            if isCHFleetOpsEnabled {
                HStack(spacing: 12) {
                    PalantirOpsIconTile(systemName: "car.fill", tint: PalantirTheme.purple, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Parked Check Outs Waiting".localized.uppercased())
                            .font(PalantirTheme.labelFont(11))
                            .foregroundStyle(PalantirTheme.purple)
                        Text(String(format: "%d parked vehicles are waiting for completion".localized, parkedCheckoutsCount))
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(2)
                        if let micro = parkedCheckoutsTopVehicleSubtitle {
                            Text(micro)
                                .font(PalantirTheme.dataFont(11))
                                .foregroundStyle(PalantirTheme.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PalantirTheme.purple.opacity(0.85))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(PalantirTheme.purple.opacity(0.08))
                .overlay(Rectangle().stroke(PalantirTheme.purple.opacity(0.35), lineWidth: 1))
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "car.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Parked Check Outs Waiting".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.purple)
                        Text(String(format: "%d parked vehicles are waiting for completion".localized, parkedCheckoutsCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        if let micro = parkedCheckoutsTopVehicleSubtitle {
                            Text(micro)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.92))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.purple.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.purple.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.purple.opacity(0.40), lineWidth: 1.0)
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Satır (Row) Görünümü
struct ModernAracSatirView: View {
    let arac: Arac
    var fleetMicroLine: String? = nil
    var fleetOpsBadge: WheelSysFleetOpsBadge? = nil
    @Environment(\.palantirModeEnabled) private var palantirMode
    
    private var sonHasar: HasarKaydi? {
        arac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }

    private func badgeTone(for kind: WheelSysFleetOpsBadgeKind) -> PalantirOpsBadge.Tone {
        switch kind {
        case .ntr: return .warning
        case .rental: return .accent
        case .available: return .success
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if palantirMode {
                PalantirOpsIconTile(systemName: "car.fill", tint: PalantirTheme.accent, size: 44)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "car.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(arac.plakaFormatli)
                    .font(palantirMode ? PalantirTheme.dataFont(15) : .system(size: 16, weight: .bold))
                    .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : Color.primary)
                    .lineLimit(1)
                
                Text("\(arac.marka) \(arac.model)")
                    .font(palantirMode ? PalantirTheme.bodyFont(12) : .system(size: 13))
                    .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                    .lineLimit(1)

                if let fleetMicroLine, !fleetMicroLine.isEmpty {
                    Text(fleetMicroLine)
                        .font(PalantirTheme.dataFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    if palantirMode {
                        PalantirOpsBadge(text: arac.kategori, tone: .accent)
                        if arac.vignetteVar {
                            PalantirOpsBadge(text: "Vig", tone: .success)
                        }
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill").font(.system(size: 9))
                            Text(arac.kategori).font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)

                        HStack(spacing: 3) {
                            Image(systemName: "key.fill").font(.system(size: 9))
                            Text("\(arac.spareKeyCount)").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(6)

                        if arac.vignetteVar {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                                Text("Vig").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            Spacer()

            if palantirMode, let fleetOpsBadge {
                PalantirOpsBadge(
                    text: fleetOpsBadge.kind.labelKey.localized,
                    tone: badgeTone(for: fleetOpsBadge.kind)
                )
            }
        }
        .padding(.vertical, palantirMode ? 6 : 8)
    }
}

private struct DurumRozeti: View {
    let title: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - Boş Durum
private struct BosDurumView: View {
    @Binding var yeniAracGoster: Bool
    
    var body: some View {
        EmptyStateView(
            icon: "car.circle.fill",
            title: "No Vehicles Yet",
            message: "Start by scanning a vehicle or adding one manually",
            buttonText: "Add Vehicle",
            buttonAction: { yeniAracGoster = true }
        )
    }
}

// MARK: - Category Expandable Card
private struct CategoryExpandableCard: View {
    let name: String
    let topVehicleSubtitle: String?
    let vehicles: [Arac]
    var fleetMicroLine: (Arac) -> String? = { _ in nil }
    var fleetOpsBadge: (Arac) -> WheelSysFleetOpsBadge? = { _ in nil }
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    if palantirMode {
                        PalantirOpsIconTile(systemName: "car.2.fill", tint: PalantirTheme.purple, size: 44)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "car.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(palantirMode ? PalantirTheme.labelFont(13) : .headline)
                            .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : Color.primary)
                        if let topVehicleSubtitle {
                            Text(topVehicleSubtitle)
                                .font(palantirMode ? PalantirTheme.bodyFont(11) : .system(size: 11, weight: .light))
                                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    if palantirMode {
                        PalantirOpsBadge(text: "\(vehicles.count)", tone: .accent)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "car.fill")
                                .font(.caption2)
                            Text("\(vehicles.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(palantirMode ? PalantirTheme.textMuted : Color.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, palantirMode ? 11 : 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            
            // Expanded Content
            if isExpanded {
                if palantirMode {
                    WheelSysPalantirInsetDivider()
                        .padding(.horizontal, 16)
                } else {
                    Divider()
                        .padding(.horizontal, 16)
                }
                
                LazyVStack(spacing: 0) {
                    ForEach(vehicles) { vehicle in
                        NavigationLink(destination: AracDetayView(arac: vehicle)) {
                            ModernAracSatirView(
                                arac: vehicle,
                                fleetMicroLine: fleetMicroLine(vehicle),
                                fleetOpsBadge: fleetOpsBadge(vehicle)
                            )
                                .padding(.leading, 16)
                        }
                        .buttonStyle(.plain)

                        if vehicle.id != vehicles.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
            }
        }
        .background(
            Group {
                if palantirMode {
                    PalantirTheme.surface
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
                }
            }
        )
        .overlay(
            Group {
                if palantirMode {
                    Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2), lineWidth: 1)
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, palantirMode ? 4 : 8)
    }
}

private struct CategoryManagerView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedCategories: Set<String> = []
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showBulkCategoryHardDeleteSheet = false
    @State private var showBulkVehicleSheet = false
    @State private var categoryDeleteConfirm = ""
    @State private var isWorking = false

    private var canManageDestructiveActions: Bool {
        authManager.userProfile?.canManageVehicleCategories ?? false
    }

    private var filteredCategories: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.kategoriler }
        return viewModel.kategoriler.filter { $0.lowercased().contains(q) }
    }

    /// Tek kategori seçiliyse araçları (soft-delete bulk için).
    private var vehiclesInSingleSelection: [Arac] {
        guard selectedCategories.count == 1, let c = selectedCategories.first else { return [] }
        let n = VehicleCategory.normalizeName(c)
        return viewModel.araclar.filter { !$0.isDeleted && VehicleCategory.normalizeName($0.kategori) == n }
    }

    private var categoryList: some View {
        List {
            Section {
                Text("Tap categories to select. Managers can rename one at a time or delete several at once.".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            ForEach(filteredCategories, id: \.self) { category in
                HStack {
                    Text(category)
                    Spacer()
                    if selectedCategories.contains(category) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedCategories.contains(category) {
                        selectedCategories.remove(category)
                    } else {
                        selectedCategories.insert(category)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                categoryActionPillButton(
                    title: "Rename Category".localized,
                    systemImage: "pencil",
                    tint: .blue
                ) {
                    renameText = selectedCategories.count == 1 ? Array(selectedCategories).first ?? "" : ""
                    showRenameAlert = true
                }
                .disabled(!canManageDestructiveActions || selectedCategories.count != 1 || isWorking)
                .frame(maxWidth: .infinity)

                categoryActionPillButton(
                    title: "Delete selected categories".localized,
                    systemImage: "trash.fill",
                    tint: .red
                ) {
                    categoryDeleteConfirm = ""
                    showBulkCategoryHardDeleteSheet = true
                }
                .disabled(!canManageDestructiveActions || selectedCategories.isEmpty || isWorking)
                .frame(maxWidth: .infinity)
            }

            categoryActionPillButton(
                title: "Delete vehicles in category…".localized,
                systemImage: "car.fill",
                tint: .blue
            ) {
                showBulkVehicleSheet = true
            }
            .disabled(!canManageDestructiveActions || selectedCategories.count != 1 || vehiclesInSingleSelection.isEmpty || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Same visual language as gallery / take-photo rows (e.g. `IadeIslemView`).
    private func categoryActionPillButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryList
            actionButtons
        }
        .searchable(text: $query, prompt: "Search by category".localized)
        .navigationTitle("Category Management".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close".localized) { dismiss() }
            }
            if !selectedCategories.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear selection".localized) { selectedCategories = [] }
                }
            }
        }
        .alert("Rename Category".localized, isPresented: $showRenameAlert) {
            TextField("New Category Name".localized, text: $renameText)
            Button("Cancel".localized, role: .cancel) {}
            Button("Save".localized) {
                guard let one = selectedCategories.first, selectedCategories.count == 1 else { return }
                viewModel.kategoriYenidenAdlandir(one, yeniKategori: renameText) { ok in
                    if ok {
                        let renamed = VehicleCategory.normalizeName(renameText)
                        selectedCategories = [renamed]
                    }
                }
            }
        }
        .sheet(isPresented: $showBulkCategoryHardDeleteSheet) {
            NavigationView {
                BulkCategoryHardDeleteFormView(
                    categoryNames: Array(selectedCategories).sorted(),
                    confirmText: $categoryDeleteConfirm,
                    isWorking: $isWorking,
                    onCancel: { showBulkCategoryHardDeleteSheet = false },
                    onConfirm: {
                        isWorking = true
                        let cats = Array(selectedCategories).sorted()
                        viewModel.deleteCategoriesAndVehiclesIfConfirmed(cats, typedConfirmation: categoryDeleteConfirm) { ok in
                            isWorking = false
                            if ok {
                                selectedCategories.removeAll()
                                showBulkCategoryHardDeleteSheet = false
                            }
                        }
                    }
                )
                .environmentObject(viewModel)
                .navigationTitle("Delete Category".localized)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showBulkVehicleSheet) {
            if selectedCategories.count == 1, let cat = selectedCategories.first {
                NavigationView {
                    CategoryBulkVehicleDeleteView(categoryName: cat, vehicles: vehiclesInSingleSelection)
                        .environmentObject(viewModel)
                }
            }
        }
    }
}

// MARK: - Category delete / bulk delete (DELETE confirmation)

private struct BulkCategoryHardDeleteFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let categoryNames: [String]
    @Binding var confirmText: String
    @Binding var isWorking: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var countsRows: [(name: String, count: Int)] {
        categoryNames.map { name in
            let n = VehicleCategory.normalizeName(name)
            let c = viewModel.araclar.filter { !$0.isDeleted && VehicleCategory.normalizeName($0.kategori) == n }.count
            return (name, c)
        }
    }

    private var totalVehicles: Int {
        countsRows.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        Form {
            Section {
                Text("Bulk category delete summary intro".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Category docs removed hint".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(String(format: "Categories selected: %d".localized, categoryNames.count))
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "Vehicles to delete (total): %d".localized, totalVehicles))
                    .font(.headline)
            }

            if !countsRows.isEmpty {
                Section("Per category".localized) {
                    ForEach(countsRows, id: \.name) { row in
                        HStack {
                            Text(row.name)
                            Spacer()
                            Text("\(row.count)")
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                        }
                    }
                }
            }

            Section {
                Text("Category delete warning footer".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("Type DELETE".localized, text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                HStack(spacing: 12) {
                    Button("Cancel".localized) { onCancel() }
                        .frame(maxWidth: .infinity)
                    Button("Delete".localized, role: .destructive) { onConfirm() }
                        .frame(maxWidth: .infinity)
                        .disabled(confirmText != "DELETE" || isWorking)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close".localized) { onCancel() }
            }
        }
    }
}

private struct CategoryBulkVehicleDeleteView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) private var dismiss
    let categoryName: String
    let vehicles: [Arac]
    @State private var selected: Set<UUID> = []
    @State private var confirmText = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Text("Select vehicles to remove from the fleet (permanent delete). Type DELETE to confirm.".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Section(categoryName) {
                ForEach(vehicles) { v in
                    Button {
                        if selected.contains(v.id) { selected.remove(v.id) } else { selected.insert(v.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(v.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.contains(v.id) ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(v.plakaFormatli).font(.headline)
                                Text("\(v.marka) \(v.model)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            Section {
                Button("Select all".localized) {
                    selected = Set(vehicles.map(\.id))
                }
                Button("Clear selection".localized) {
                    selected = []
                }
            }
            Section {
                TextField("Type DELETE".localized, text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Delete selected".localized, role: .destructive) {
                    isWorking = true
                    viewModel.bulkDeleteVehiclesIfConfirmed(ids: Array(selected), typedConfirmation: confirmText) { ok in
                        isWorking = false
                        if ok { dismiss() }
                    }
                }
                .disabled(selected.isEmpty || confirmText != "DELETE" || isWorking)
            }
        }
        .navigationTitle("Bulk delete".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
}

