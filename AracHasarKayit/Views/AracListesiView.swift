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
        guard let vehicleId else { return }
        if let _ = garagePortalLinkedCompanyId, !listSourceAraclar.contains(where: { $0.id == vehicleId }) {
            print("🔎 [ScanNav] Garage portal: vehicle not in scoped list")
            return
        }
        guard let vehicle = viewModel.araclar.first(where: { $0.id == vehicleId }) else {
            print("🔎 [ScanNav] Vehicle id \(vehicleId.uuidString) not found in current list yet")
            return
        }
        let now = Date()
        if lastScannedVehicleId == vehicleId, now.timeIntervalSince(lastScannedAt) < 0.7 {
            print("🔎 [ScanNav] Skipping duplicate route for \(vehicle.plakaFormatli)")
            return
        }
        lastScannedVehicleId = vehicleId
        lastScannedAt = now
        DispatchQueue.main.async {
            // Stack scanned vehicles: each scan pushes a fresh route.
            print("🔎 [ScanNav] Navigating to vehicle detail: \(vehicle.plakaFormatli) id=\(vehicle.id.uuidString)")
            navigationPath.append(ScannedVehicleRoute(vehicleId: vehicle.id, fromScan: true))
            navigateToVehicleId = nil
        }
    }

    // Filtered vehicles based on search query
    private var filteredAraclar: [Arac] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return listSourceAraclar
        }
        let q = searchText.lowercased()
        return listSourceAraclar.filter {
            $0.plakaFormatli.lowercased().contains(q) ||
            $0.marka.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.kategori.lowercased().contains(q)
        }
    }

    private var isSearchingVehicles: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayedVehicleCount: Int {
        isSearchingVehicles ? filteredAraclar.count : listSourceAraclar.count
    }

    private var vehicleTotalHeader: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
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
            .navigationTitle((authManager.userProfile?.role == .garage) ? "garage_portal.nav_title".localized : "Vehicles".localized)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by plate, model or category…".localized)
            .toolbar {
                if authManager.userProfile?.role != .garage {
                    if canManageVehicleCategories {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showCategoryManagerSheet = true
                            } label: {
                                Image(systemName: "pencil.circle")
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showFleetImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            yeniAracGoster = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
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
            .navigationDestination(for: ScannedVehicleRoute.self) { route in
                if let vehicle = viewModel.araclar.first(where: { $0.id == route.vehicleId }) {
                    AracDetayView(arac: vehicle, scannedEntry: route.fromScan)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Vehicle not found".localized)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // iOS 17+: two-parameter onChange — first value is the *previous* binding value.
            // Using the old one-parameter form made `vehicleId` the previous UUID, so
            // nil → id transitions never navigated after the first scan.
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
            .onAppear {
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
                navigateToScannedVehicle(navigateToVehicleId)
            }
            .onChange(of: viewModel.araclar) { _, _ in
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
                // If scan arrived while list data was still loading, consume it here.
                navigateToScannedVehicle(navigateToVehicleId)
            }
            .onChange(of: viewModel.garageServiceJobs.count) { _, _ in
                if OptimizationFeatureFlags.detailMemoV2 {
                    rebuildCategoryCache()
                }
            }
        }
    }

    // MARK: - Vehicle List View
    @ViewBuilder
    private var vehicleListView: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty

        if isSearching {
            // Flat search results
            if filteredAraclar.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        vehicleTotalHeader
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredAraclar) { vehicle in
                        NavigationLink(destination: AracDetayView(arac: vehicle)) {
                            ModernAracSatirView(arac: vehicle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
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
                    Button {
                        showParkedCheckoutsSheet = true
                    } label: {
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
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }

                ForEach(orderedCategoriesForList, id: \.self) { kategori in
                    let list = vehiclesForCategory(kategori)
                    CategoryExpandableCard(
                        name: kategori,
                        topVehicleSubtitle: topVehicleMarkaModelLine(for: list),
                        vehicles: list
                    )
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Satır (Row) Görünümü
struct ModernAracSatirView: View {
    let arac: Arac
    
    private var sonHasar: HasarKaydi? {
        arac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(arac.plakaFormatli)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(arac.marka) \(arac.model)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Responsive badges with wrapping
                HStack(spacing: 6) {
                    // Category badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "tag.fill").font(.system(size: 9))
                        Text(arac.kategori).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)

                    // Spare key badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill").font(.system(size: 9))
                        Text("\(arac.spareKeyCount)").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)

                    // Vignette badge (compact)
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
            
            Spacer()
            
            // Requested: hide right-side Done/Progress indicator from Vehicles list UI.
        }
        .padding(.vertical, 6)
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
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "car.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    // Category name + top-vehicle micro line (matches first row when expanded)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        if let topVehicleSubtitle {
                            Text(topVehicleSubtitle)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Count Badge
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
                    
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            
            // Expanded Content
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                ForEach(vehicles) { vehicle in
                    NavigationLink(destination: AracDetayView(arac: vehicle)) {
                        ModernAracSatirView(arac: vehicle)
                            .padding(.leading, 16)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                                                        }
                    )
                    
                    if vehicle.id != vehicles.last?.id {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

