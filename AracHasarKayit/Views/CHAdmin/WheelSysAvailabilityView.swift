import SwiftUI

/// WheelSys Availability — performant day-window grid, collapsed classes by default.
struct WheelSysAvailabilityView: View {
    private static let stationCode = "ZRH"

    let sessionValid: Bool
    var reloadTrigger: Int = 0
    var onSessionExpired: (() -> Void)?

    @State private var result: WheelSysAvailabilityResult?
    @State private var loading = false
    @State private var loadingPhase: AvailabilityLoadingPhase = .idle
    @State private var loadingMicrocopyTask: Task<Void, Never>?
    @State private var debugInfo: String?
    @State private var dateFrom = WheelSysAvailabilityDateRange.defaultFrom
    @State private var dateTo = WheelSysAvailabilityDateRange.defaultTo
    @State private var selectedDayIndex = 0
    @State private var expandedClasses: Set<String> = []

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    private static let hourHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    private let labelWidth: CGFloat = 120
    private let cellWidth: CGFloat = 44
    private let rowHeight: CGFloat = 34
    private let headerHeight: CGFloat = 36

    var body: some View {
        ZStack {
            Group {
                if !sessionValid {
                    sessionRequiredPlaceholder
                } else if result == nil && !loading {
                    emptyPlaceholder
                } else if let result {
                    availabilityContent(result)
                } else {
                    loadingPlaceholder
                }
            }

            if loading {
                loadingOverlay
            }
        }
        .onChange(of: sessionValid) { _, valid in
            if valid {
                Task { await loadAvailability(force: true) }
            } else {
                result = nil
                expandedClasses = []
                selectedDayIndex = 0
            }
        }
        .onChange(of: reloadTrigger) { _, _ in
            guard sessionValid else { return }
            Task { await loadAvailability(force: true) }
        }
        .task {
            guard sessionValid else { return }
            await loadAvailability(force: false)
        }
        .onDisappear {
            loadingMicrocopyTask?.cancel()
        }
    }

    // MARK: Content

    private func availabilityContent(_ data: WheelSysAvailabilityResult) -> some View {
        VStack(spacing: 0) {
            summaryBar(data)
            if let debug = debugInfo {
                debugBanner(debug)
            }
            filterBar
            dayNavigator(data)
            availabilityGrid(data)
        }
    }

    private func summaryBar(_ data: WheelSysAvailabilityResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "wheelsys_availability.summary".localized, data.rowsCount))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Self.stationCode)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PalantirTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(PalantirTheme.border))
            }
            Text(String(format: "wheelsys_availability.classes_count".localized, data.classSections.count))
                .font(.caption)
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .foregroundStyle(PalantirTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("wheelsys_availability.date_from".localized)
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textMuted)
                DatePicker("", selection: $dateFrom, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("wheelsys_availability.date_to".localized)
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textMuted)
                DatePicker("", selection: $dateTo, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await loadAvailability(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.427, green: 0.365, blue: 0.988))
            .disabled(loading || dateTo < dateFrom)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PalantirTheme.background)
    }

    private func dayNavigator(_ data: WheelSysAvailabilityResult) -> some View {
        let days = data.calendarDays
        let canPrev = selectedDayIndex > 0
        let canNext = selectedDayIndex < days.count - 1
        let label = days.indices.contains(selectedDayIndex)
            ? Self.dayFormatter.string(from: days[selectedDayIndex])
            : "—"

        return HStack {
            Button {
                selectedDayIndex -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canPrev)

            Spacer()
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                if !days.isEmpty {
                    Text(String(format: "wheelsys_availability.day_progress".localized,
                                selectedDayIndex + 1, days.count))
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            Spacer()

            Button {
                selectedDayIndex += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canNext)
        }
        .foregroundStyle(PalantirTheme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PalantirTheme.surface.opacity(0.6))
    }

    private func availabilityGrid(_ data: WheelSysAvailabilityResult) -> some View {
        let days = data.calendarDays
        let day = days.indices.contains(selectedDayIndex) ? days[selectedDayIndex] : nil
        let hours = day.map { data.hours(on: $0) } ?? []

        return ScrollView(.vertical) {
            if hours.isEmpty {
                Text("wheelsys_availability.no_hours".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .padding()
            } else {
                HStack(alignment: .top, spacing: 0) {
                    labelColumn(data: data, hours: hours)
                    ScrollView(.horizontal, showsIndicators: true) {
                        valuesColumn(data: data, hours: hours)
                    }
                }
            }
        }
        .refreshable {
            await loadAvailability(force: true)
        }
    }

    private func labelColumn(data: WheelSysAvailabilityResult, hours: [Date]) -> some View {
        LazyVStack(spacing: 0) {
            Text("wheelsys_availability.col_class".localized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: labelWidth, height: headerHeight, alignment: .leading)
                .padding(.leading, 8)
                .background(PalantirTheme.surface)

            ForEach(data.classSections) { section in
                classLabelBlock(section)
            }

            Text("wheelsys_availability.grand_total".localized)
                .font(.caption.weight(.bold))
                .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                .padding(.leading, 8)
                .background(Color.blue.opacity(0.12))
        }
        .frame(width: labelWidth)
        .overlay(alignment: .trailing) {
            Rectangle().fill(PalantirTheme.border).frame(width: 1)
        }
    }

    private func classLabelBlock(_ section: WheelSysAvailabilityClassSection) -> some View {
        let isExpanded = expandedClasses.contains(section.vehicleClass)
        return VStack(spacing: 0) {
            Button { toggleClass(section.vehicleClass) } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .frame(width: 12)
                    Text("\(section.vehicleClass) (\(section.groupCount))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                .padding(.leading, 8)
                .background(PalantirTheme.surface.opacity(0.85))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(section.sortedGroups) { group in
                    Text(group.carGroup)
                        .font(.caption)
                        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                        .padding(.leading, 28)
                        .background(PalantirTheme.background)
                }
                Text(String(format: "wheelsys_availability.class_total".localized, section.vehicleClass))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                    .padding(.leading, 8)
                    .background(Color.blue.opacity(0.06))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border.opacity(0.35)).frame(height: 0.5)
        }
    }

    private func valuesColumn(data: WheelSysAvailabilityResult, hours: [Date]) -> some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(hours, id: \.self) { date in
                    Text(Self.hourHeaderFormatter.string(from: date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .frame(width: cellWidth, height: headerHeight)
                }
            }
            .background(PalantirTheme.surface)

            ForEach(data.classSections) { section in
                classValuesBlock(section, hours: hours)
            }

            valueCells(values: data.totalHourlyValues, hours: hours, background: Color.blue.opacity(0.12))
        }
    }

    private func classValuesBlock(_ section: WheelSysAvailabilityClassSection, hours: [Date]) -> some View {
        let isExpanded = expandedClasses.contains(section.vehicleClass)
        return VStack(spacing: 0) {
            valueCells(values: section.classTotals, hours: hours, background: PalantirTheme.surface.opacity(0.85))

            if isExpanded {
                ForEach(section.sortedGroups) { group in
                    valueCells(values: group.hourlyValues, hours: hours, background: PalantirTheme.background)
                }
                valueCells(values: section.classTotals, hours: hours, background: Color.blue.opacity(0.06))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border.opacity(0.35)).frame(height: 0.5)
        }
    }

    private func valueCells(values: [Date: Int], hours: [Date], background: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(hours, id: \.self) { date in
                let value = values[date] ?? 0
                Text("\(value)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(valueColor(value))
                    .frame(width: cellWidth, height: rowHeight)
            }
        }
        .background(background)
    }

    private func toggleClass(_ name: String) {
        if expandedClasses.contains(name) {
            expandedClasses.remove(name)
        } else {
            expandedClasses.insert(name)
        }
    }

    private func valueColor(_ value: Int) -> Color {
        if value < 0 { return .red }
        if value == 0 { return .orange }
        return PalantirTheme.textPrimary
    }

    private func debugBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.12))
    }

    private var loadingOverlay: some View {
        PalantirOpsLoadingOverlay(
            title: loadingPhase.title,
            microcopy: loadingPhase.microcopy,
            step: loadingPhase.step
        )
    }

    private var sessionRequiredPlaceholder: some View {
        ContentUnavailableView(
            "wheelsys_availability.session_required".localized,
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("wheelsys_checkin.session_required_hint".localized)
        )
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
        ContentUnavailableView(
            "wheelsys_availability.empty".localized,
            systemImage: "calendar.badge.clock",
            description: Text("wheelsys_availability.empty_hint".localized)
        )
    }

    // MARK: Load

    @MainActor
    private func loadAvailability(force: Bool) async {
        guard sessionValid else { return }
        if loading && !force { return }
        guard dateTo >= dateFrom else {
            debugInfo = "wheelsys_availability.invalid_range".localized
            return
        }

        loadingMicrocopyTask?.cancel()
        loading = true
        loadingPhase = .openingPage
        startLoadingMicrocopyAnimation()

        defer {
            loading = false
            loadingPhase = .idle
            loadingMicrocopyTask?.cancel()
        }

        debugInfo = nil
        let fromISO = WheelSysAvailabilityDateRange.isoStart(dateFrom)
        let toISO = WheelSysAvailabilityDateRange.isoEnd(dateTo)

        do {
            loadingPhase = .getData
            let loaded = try await WheelSysCheckinService.loadAvailability(
                franchiseId: franchiseId,
                station: Self.stationCode,
                dateFromISO: fromISO,
                dateToISO: toISO
            )
            loadingPhase = .parsing
            result = loaded
            expandedClasses = []
            selectedDayIndex = 0
            print("[WheelSysAvailability] loaded \(loaded.rowsCount) rows, \(loaded.calendarDays.count) days")
        } catch {
            handleLoadError(error)
        }
    }

    @MainActor
    private func handleLoadError(_ error: Error) {
        let msg: String
        var expired = false
        switch error {
        case WheelSysAvailabilityFetchError.sessionExpired:
            msg = "wheelsys_availability.session_expired".localized
            expired = true
        case WheelSysAvailabilityFetchError.stepFailed(let step, let status, let preview):
            msg = "\(step) HTTP \(status)\n\(String(preview.prefix(400)))"
        case WheelSysAvailabilityFetchError.notReady(let detail):
            msg = detail
        case WheelSysAvailabilityFetchError.parseFailure(let detail):
            msg = detail
        default:
            msg = error.localizedDescription
        }
        if expired { onSessionExpired?() }
        debugInfo = msg
        print("[WheelSysAvailability] error: \(msg)")
    }

    private func startLoadingMicrocopyAnimation() {
        loadingMicrocopyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, loading else { return }
            loadingPhase = .getData
            for attempt in 1...10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, loading else { return }
                loadingPhase = .pollingCache(attempt: attempt)
            }
        }
    }
}

// MARK: - Loading phases

private enum AvailabilityLoadingPhase: Equatable {
    case idle
    case openingPage
    case getData
    case pollingCache(attempt: Int)
    case parsing

    var step: Int {
        switch self {
        case .idle: return 1
        case .openingPage: return 1
        case .getData: return 2
        case .pollingCache: return 3
        case .parsing: return 4
        }
    }

    var title: String {
        switch self {
        case .idle: return ""
        case .openingPage: return "wheelsys_availability.loading_title_page".localized
        case .getData: return "wheelsys_availability.loading_title_getdata".localized
        case .pollingCache: return "wheelsys_availability.loading_title_cache".localized
        case .parsing: return "wheelsys_availability.loading_title_parse".localized
        }
    }

    var microcopy: String {
        switch self {
        case .idle: return ""
        case .openingPage: return "wheelsys_availability.loading_micro_page".localized
        case .getData: return "wheelsys_availability.loading_micro_getdata".localized
        case .pollingCache(let attempt):
            return String(format: "wheelsys_availability.loading_micro_cache".localized, attempt)
        case .parsing: return "wheelsys_availability.loading_micro_parse".localized
        }
    }
}
