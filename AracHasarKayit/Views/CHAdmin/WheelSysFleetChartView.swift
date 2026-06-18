import SwiftUI

/// Read-only Fleet Chart view — vehicles, statuses, and linked events from WheelSys.
/// Fleet data is fetched via JavaScript inside the authenticated WKWebView context,
/// because WheelSys binds sessions to the originating browser/IP (cookie alone is insufficient).
struct WheelSysFleetChartView: View {
    let sessionValid: Bool
    var fleetChartAccessValid: Bool = true
    var reloadTrigger: Int = 0
    var onSessionExpired: (() -> Void)? = nil

    @EnvironmentObject var viewModel: AracViewModel

    @State private var fleet: WheelSysFleetChartResult?
    @State private var loading = false
    @State private var loadingPhase: PalantirOpsPhase = .connecting
    @State private var debugInfo: String?
    @State private var sessionExpired = false
    @State private var searchText = ""
    @State private var statusFilter: FleetStatusFilter = .all
    @State private var expandedVehicleIds: Set<String> = []
    @State private var syncing = false
    @State private var syncSummary: String?

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    private var filteredVehicles: [WheelSysFleetVehicle] {
        guard let fleet else { return [] }
        var rows = fleet.vehicles
        if statusFilter != .all {
            rows = rows.filter { statusFilter.matches(vehicle: $0) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.plate.lowercased().contains(q)
            || $0.model.lowercased().contains(q)
            || $0.group.lowercased().contains(q)
            || $0.vehicleId.contains(q)
        }
    }

    var body: some View {
        ZStack {
            Group {
                if !sessionValid {
                    sessionRequiredPlaceholder
                } else if loading && fleet == nil {
                    loadingPlaceholder
                } else if let fleet {
                    fleetContent(fleet)
                } else {
                    emptyPlaceholder
                }
            }

            if loading && fleet != nil {
                PalantirOpsLoadingOverlay(
                    title: loadingPhase.title,
                    microcopy: loadingPhase.microcopy,
                    step: loadingPhase.step
                )
            }
        }
        .onChange(of: sessionValid) { _, valid in
            if valid {
                Task { await loadFleet(force: true) }
            } else {
                fleet = nil
                sessionExpired = false
            }
        }
        .onChange(of: reloadTrigger) { _, _ in
            guard sessionValid else { return }
            Task { await loadFleet(force: true) }
        }
        .task {
            guard sessionValid else { return }
            await loadFleet(force: false)
        }
    }

    // MARK: Content

    private func fleetContent(_ fleet: WheelSysFleetChartResult) -> some View {
        VStack(spacing: 0) {
            summaryBar(fleet)
            if let debug = debugInfo {
                debugBanner(debug)
            }
            filterBar
            if sessionExpired {
                sessionExpiredBanner
            }
            if !fleetChartAccessValid && !sessionExpired {
                accessBlockedBanner
            }
            List {
                if filteredVehicles.isEmpty {
                    Text("wheelsys_fleet.no_matches".localized)
                        .foregroundStyle(PalantirTheme.textMuted)
                        .listRowBackground(PalantirTheme.background)
                } else {
                    ForEach(filteredVehicles) { vehicle in
                        vehicleSection(vehicle)
                            .listRowBackground(PalantirTheme.background)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await loadFleet(force: true)
            }
        }
    }

    private func summaryBar(_ fleet: WheelSysFleetChartResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(format: "wheelsys_fleet.summary".localized,
                            fleet.vehiclesCount, fleet.eventsCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer()
                Text(String(format: "wheelsys_fleet.rentals_count".localized,
                            fleet.rentalEventsCount))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)

                Button {
                    Task { await syncEntities(fleet: fleet, manual: true) }
                } label: {
                    if syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "link")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(PalantirTheme.accent)
                .disabled(syncing)
                .accessibilityLabel("wheelsys_fleet.sync_entities".localized)
            }
            Text(String(format: "wheelsys_fleet.date_range".localized,
                        fleet.startDate, fleet.endDate, fleet.station))
                .font(.caption)
                .foregroundStyle(PalantirTheme.textMuted)
            if let syncSummary {
                Text(syncSummary)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PalantirTheme.textMuted)
                TextField("wheelsys_fleet.search_placeholder".localized, text: $searchText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .padding(10)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FleetStatusFilter.allCases) { filter in
                        Button {
                            statusFilter = filter
                        } label: {
                            Text(filter.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(statusFilter == filter
                                            ? filter.tint.opacity(0.2)
                                            : PalantirTheme.surface)
                                .foregroundStyle(statusFilter == filter ? filter.tint : PalantirTheme.textMuted)
                                .overlay(Rectangle().stroke(
                                    statusFilter == filter ? filter.tint : PalantirTheme.border,
                                    lineWidth: 1
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func vehicleSection(_ vehicle: WheelSysFleetVehicle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleExpanded(vehicle.vehicleId)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.plate.isEmpty ? "—" : vehicle.plate)
                            .font(.headline)
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Text(vehicle.model.isEmpty ? "wheelsys_fleet.unknown_model".localized : vehicle.model)
                            .font(.subheadline)
                            .foregroundStyle(PalantirTheme.textMuted)
                        HStack(spacing: 8) {
                            metaChip(vehicle.group)
                            metaChip(vehicle.station)
                            if vehicle.mileage > 0 {
                                metaChip("\(vehicle.mileage) km")
                            }
                            if let color = vehicle.color, !color.isEmpty {
                                metaChip(color)
                            }
                            if !vehicle.fuelType.isEmpty {
                                metaChip(vehicle.fuelType)
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        statusBadge(vehicle.status)
                        if !vehicle.events.isEmpty {
                            Text(String(format: "wheelsys_fleet.events_count".localized, vehicle.events.count))
                                .font(.caption2)
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                        Image(systemName: expandedVehicleIds.contains(vehicle.vehicleId)
                              ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expandedVehicleIds.contains(vehicle.vehicleId) {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("wheelsys_fleet.vehicle_id".localized, vehicle.vehicleId)
                    if vehicle.events.isEmpty {
                        Text("wheelsys_fleet.no_events".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(vehicle.events) { event in
                            eventRow(event)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        .padding(.vertical, 4)
    }

    private func eventRow(_ event: WheelSysFleetEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.type.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(eventTypeColor(event.type))
                Text(event.status.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PalantirTheme.surfaceHigh)
                    .foregroundStyle(PalantirTheme.textMuted)
                Spacer()
                if let rentalId = event.rentalEntityId {
                    Text("#\(rentalId)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            if !event.driverName.isEmpty {
                Text(event.driverName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            HStack(spacing: 8) {
                if !event.startTimeText.isEmpty || !event.endTimeText.isEmpty {
                    Text("\(event.startTimeText) → \(event.endTimeText)")
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                if !event.stationFrom.isEmpty {
                    Text(String(format: "wheelsys_fleet.event_station_from".localized + ": %@", event.stationFrom))
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            HStack(spacing: 8) {
                if !event.initialCarGroup.isEmpty {
                    Text(String(format: "wheelsys_fleet.event_car_group".localized + ": %@", event.initialCarGroup))
                        .font(.caption2)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                if event.domain > 0 {
                    Text(String(format: "wheelsys_fleet.event_domain".localized + ": %d", event.domain))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PalantirTheme.surfaceHigh.opacity(0.5))
        .padding(.horizontal, 12)
    }

    // MARK: Placeholders

    private var sessionRequiredPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(PalantirTheme.textMuted)
            Text("wheelsys_fleet.session_required".localized)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(PalantirTheme.textMuted)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingPlaceholder: some View {
        PalantirOpsLoadingOverlay(
            title: loadingPhase.title,
            microcopy: loadingPhase.microcopy,
            step: loadingPhase.step,
            floating: false
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            if let debug = debugInfo {
                debugBanner(debug)
                    .padding(.horizontal, 16)
            }
            Text("wheelsys_fleet.empty".localized)
                .font(.subheadline)
                .foregroundStyle(PalantirTheme.textMuted)
            Button("wheelsys_fleet.reload".localized) {
                Task { await loadFleet(force: true) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
    }

    private func debugBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ladybug.fill")
                    .foregroundStyle(.orange)
                Text("wheelsys_fleet.debug_title".localized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(PalantirTheme.textMuted)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(Rectangle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var accessBlockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            Text("wheelsys_fleet.access_blocked".localized)
                .font(.caption.weight(.medium))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .padding(.horizontal, 16)
    }

    private var sessionExpiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("wheelsys_fleet.session_expired".localized)
                .font(.caption.weight(.medium))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .padding(.horizontal, 16)
    }

    // MARK: UI Helpers

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PalantirTheme.surfaceHigh)
            .foregroundStyle(PalantirTheme.textMuted)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(statusLabel(status))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.18))
            .foregroundStyle(statusColor(status))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(PalantirTheme.textMuted)
            Spacer()
            Text(value).foregroundStyle(PalantirTheme.textPrimary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
    }

    private func statusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "available": return "wheelsys_fleet.status_available".localized
        case "on_rental", "rental": return "wheelsys_fleet.status_on_rental".localized
        case "non_revenue": return "wheelsys_fleet.status_non_revenue".localized
        case "booking": return "wheelsys_fleet.status_booking".localized
        case "insurance": return "wheelsys_fleet.status_insurance".localized
        default: return status.capitalized
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "available": return .green
        case "on_rental", "rental": return .blue
        case "non_revenue": return .orange
        case "booking": return .purple
        case "insurance": return .gray
        default: return PalantirTheme.textMuted
        }
    }

    private func eventTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "rental": return .blue
        case "booking": return .purple
        case "non_revenue", "non-revenue": return .orange
        case "insurance": return .gray
        default: return PalantirTheme.textMuted
        }
    }

    @MainActor
    private func syncEntities(fleet: WheelSysFleetChartResult, manual: Bool) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let result = await viewModel.syncWheelSysEntities(from: fleet)
        if manual || result.written > 0 {
            syncSummary = String(format: "wheelsys.entity.sync.matched".localized, result.matched)
        }
    }

    private func toggleExpanded(_ vehicleId: String) {
        if expandedVehicleIds.contains(vehicleId) {
            expandedVehicleIds.remove(vehicleId)
        } else {
            expandedVehicleIds.insert(vehicleId)
        }
    }

    // MARK: Load

    @MainActor
    private func loadFleet(force: Bool) async {
        guard sessionValid else { return }
        if loading && !force { return }
        loading = true
        loadingPhase = .connecting
        defer {
            loading = false
            loadingPhase = .ready
        }
        sessionExpired = false
        debugInfo = nil
        do {
            loadingPhase = .fetching
            let result = try await WheelSysCheckinService.loadFleetChart(franchiseId: franchiseId)
            loadingPhase = .parsing
            fleet = result
            // Clear debug banner on success so it doesn't clutter the view.
            debugInfo = nil
            WheelSysDebug.log("FleetChart", "loaded vehicles=\(result.vehiclesCount) events=\(result.eventsCount) rentals=\(result.rentalEventsCount)")
            print("[WheelSysFleet] loaded \(result.vehiclesCount) vehicles, \(result.eventsCount) events")
            // Background entity sync — never blocks UI.
            Task { await syncEntities(fleet: result, manual: false) }
        } catch {
            let msg: String
            var expired = false
            switch error {
            case WheelSysFleetFetchError.sessionExpired:
                msg = "wheelsys_fleet.session_expired".localized
                expired = true
            case WheelSysFleetFetchError.httpError(let code, let preview):
                msg = "Fleet Chart HTTP \(code)\n\(String(preview.prefix(400)))"
            case WheelSysFleetFetchError.parseFailure(let detail):
                msg = "Parse error: \(detail)"
            case WheelSysFleetFetchError.jsTypeError:
                msg = "JS returned unexpected type."
            default:
                msg = error.localizedDescription
                if msg.lowercased().contains("session expired") { expired = true }
            }
            sessionExpired = expired
            debugInfo = msg
            print("[WheelSysFleet] error: \(msg)")
            if expired { onSessionExpired?() }
        }
    }
}

// MARK: - Status Filter

private enum FleetStatusFilter: String, CaseIterable, Identifiable {
    case all
    case available
    case onRental
    case booking
    case nonRevenue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "wheelsys_fleet.filter_all".localized
        case .available: return "wheelsys_fleet.status_available".localized
        case .onRental: return "wheelsys_fleet.status_on_rental".localized
        case .booking: return "wheelsys_fleet.status_booking".localized
        case .nonRevenue: return "wheelsys_fleet.status_non_revenue".localized
        }
    }

    var tint: Color {
        switch self {
        case .all: return PalantirTheme.textPrimary
        case .available: return .green
        case .onRental: return .blue
        case .booking: return .purple
        case .nonRevenue: return .orange
        }
    }

    func matches(vehicle: WheelSysFleetVehicle) -> Bool {
        let s = vehicle.status.lowercased()
        switch self {
        case .all: return true
        case .available: return s == "available"
        case .onRental: return s == "on_rental" || s == "rental"
        case .booking: return s == "booking" || vehicle.events.contains { $0.type.lowercased() == "booking" }
        case .nonRevenue: return s == "non_revenue" || vehicle.events.contains { $0.type.lowercased().contains("non") }
        }
    }
}
