import SwiftUI

// MARK: - Analytics engine

enum OfficeAnalyticsPeriod: String, CaseIterable, Identifiable {
    case threeMonths
    case sixMonths
    case twelveMonths

    var id: String { rawValue }

    var monthCount: Int {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .twelveMonths: return 12
        }
    }

    var titleKey: String {
        switch self {
        case .threeMonths: return "office.analytics.period_3m"
        case .sixMonths: return "office.analytics.period_6m"
        case .twelveMonths: return "office.analytics.period_12m"
        }
    }
}

struct OfficeAnalyticsMonthBucket: Identifiable, Hashable {
    let id: String
    let start: Date
    let label: String
}

struct OfficeAnalyticsTypeMonthRow: Identifiable {
    let id: String
    let type: OfficeOperationType
    let monthLabel: String
    let count: Int
    let amount: Double
}

struct OfficeAnalyticsVehicleDamageRow: Identifiable {
    let id: String
    let plate: String
    let monthLabel: String
    let count: Int
    let openCount: Int
}

enum OfficeOperationsAnalyticsEngine {
    static func monthBuckets(endingAt end: Date, count: Int, calendar: Calendar = .current) -> [OfficeAnalyticsMonthBucket] {
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
        var buckets: [OfficeAnalyticsMonthBucket] = []
        for offset in (0..<count).reversed() {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: endMonth) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthStart)
            let label = monthStart.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
            let id = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            buckets.append(OfficeAnalyticsMonthBucket(id: id, start: monthStart, label: label))
        }
        return buckets
    }

    static func monthRange(for bucket: OfficeAnalyticsMonthBucket, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = bucket.start
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return (start, end)
    }

    static func officeRows(
        operations: [OfficeOperation],
        buckets: [OfficeAnalyticsMonthBucket],
        types: [OfficeOperationType],
        calendar: Calendar = .current
    ) -> [OfficeAnalyticsTypeMonthRow] {
        var rows: [OfficeAnalyticsTypeMonthRow] = []
        for bucket in buckets {
            let range = monthRange(for: bucket, calendar: calendar)
            for type in types {
                let slice = operations.filter {
                    $0.type == type && $0.date >= range.start && $0.date <= range.end
                }
                guard !slice.isEmpty else { continue }
                rows.append(OfficeAnalyticsTypeMonthRow(
                    id: "\(bucket.id)|\(type.rawValue)",
                    type: type,
                    monthLabel: bucket.label,
                    count: slice.count,
                    amount: slice.reduce(0) { $0 + $1.amount }
                ))
            }
        }
        return rows
    }

    static func damageRows(
        damages: [HasarKaydi],
        buckets: [OfficeAnalyticsMonthBucket],
        calendar: Calendar = .current,
        topPlates: Int = 12
    ) -> [OfficeAnalyticsVehicleDamageRow] {
        let plateKeys = Dictionary(grouping: damages) { plateKey($0.aracPlaka) }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(topPlates)
            .map(\.key)

        var rows: [OfficeAnalyticsVehicleDamageRow] = []
        for bucket in buckets {
            let range = monthRange(for: bucket, calendar: calendar)
            for plate in plateKeys {
                let slice = damages.filter {
                    plateKey($0.aracPlaka) == plate
                        && $0.tarih >= range.start
                        && $0.tarih <= range.end
                }
                guard !slice.isEmpty else { continue }
                let open = slice.filter { $0.durum != .done }.count
                rows.append(OfficeAnalyticsVehicleDamageRow(
                    id: "\(bucket.id)|\(plate)",
                    plate: displayPlate(plate),
                    monthLabel: bucket.label,
                    count: slice.count,
                    openCount: open
                ))
            }
        }
        return rows
    }

    static func plateKey(_ raw: String) -> String {
        WheelSysPlateNormalizer.canonical(raw)
    }

    static func displayPlate(_ canonical: String) -> String {
        WheelSysPlateNormalizer.display(canonical)
    }
}

// MARK: - View

struct OfficeOperationsAnalyticsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var period: OfficeAnalyticsPeriod = .sixMonths
    @State private var selectedMonthAnchor = Date()

    private var canViewTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
    }

    private var buckets: [OfficeAnalyticsMonthBucket] {
        OfficeOperationsAnalyticsEngine.monthBuckets(
            endingAt: selectedMonthAnchor,
            count: period.monthCount
        )
    }

    private var officeTypes: [OfficeOperationType] {
        var types = OfficeOperationType.allCases
        if FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) {
            types.removeAll { $0 == .banking }
        }
        return types
    }

    private var officeRows: [OfficeAnalyticsTypeMonthRow] {
        OfficeOperationsAnalyticsEngine.officeRows(
            operations: viewModel.officeOperations,
            buckets: buckets,
            types: officeTypes
        )
    }

    private var damageRows: [OfficeAnalyticsVehicleDamageRow] {
        OfficeOperationsAnalyticsEngine.damageRows(
            damages: viewModel.allHasarKayitlariForReporting,
            buckets: buckets
        )
    }

    private var periodOfficeTotal: Double {
        officeRows.reduce(0) { $0 + $1.amount }
    }

    private var periodDamageTotal: Int {
        let rangeStart = buckets.first.map(\.start) ?? Date()
        let rangeEnd = buckets.last.map {
            OfficeOperationsAnalyticsEngine.monthRange(for: $0).end
        } ?? Date()
        return viewModel.allHasarKayitlariForReporting.filter {
            $0.tarih >= rangeStart && $0.tarih <= rangeEnd
        }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                periodPicker
                summaryHero
                officeSection
                damageSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(PalantirTheme.background)
        .navigationTitle("office.analytics.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(PalantirTheme.labelFont(12))
                        .foregroundStyle(PalantirTheme.accent)
                }
            }
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: true))
        .environment(\.palantirModeEnabled, true)
    }

    private var periodPicker: some View {
        WheelSysPalantirSectionCard(title: "office.analytics.period".localized.uppercased(), icon: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $period) {
                    ForEach(OfficeAnalyticsPeriod.allCases) { p in
                        Text(p.titleKey.localized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker(
                    "office.analytics.anchor_month".localized,
                    selection: $selectedMonthAnchor,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .font(PalantirTheme.bodyFont(12))
            }
        }
    }

    private var summaryHero: some View {
        HStack(spacing: 11) {
            summaryTile(
                icon: "chart.bar.fill",
                label: "office.analytics.ops_entries".localized,
                value: "\(officeRows.reduce(0) { $0 + $1.count })",
                tint: PalantirTheme.accent
            )
            if canViewTotals {
                summaryTile(
                    icon: "banknote.fill",
                    label: "office.analytics.ops_amount".localized,
                    value: AppCurrency.amountWithCode(periodOfficeTotal),
                    tint: PalantirTheme.success
                )
            }
            summaryTile(
                icon: "exclamationmark.triangle.fill",
                label: "office.analytics.damage_reports".localized,
                value: "\(periodDamageTotal)",
                tint: PalantirTheme.warning
            )
        }
    }

    private func summaryTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(PalantirTheme.dataFont(16))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private var officeSection: some View {
        WheelSysPalantirSectionCard(
            title: "office.analytics.office_by_month".localized.uppercased(),
            icon: "building.2.fill"
        ) {
            if officeRows.isEmpty {
                emptyStrip("office.analytics.no_office_data".localized)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(groupedOfficeByMonth(), id: \.month) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.month)
                                .font(PalantirTheme.labelFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                            ForEach(group.rows) { row in
                                officeRowView(row)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }

    private func groupedOfficeByMonth() -> [(month: String, rows: [OfficeAnalyticsTypeMonthRow])] {
        let grouped = Dictionary(grouping: officeRows, by: \.monthLabel)
        return buckets.compactMap { bucket in
            guard let rows = grouped[bucket.label], !rows.isEmpty else { return nil }
            return (bucket.label, rows.sorted { $0.type.hubTitleLocalized < $1.type.hubTitleLocalized })
        }
    }

    private func officeRowView(_ row: OfficeAnalyticsTypeMonthRow) -> some View {
        HStack(spacing: 10) {
            PalantirOpsIconTile(systemName: row.type.icon, tint: palantirTint(for: row.type), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.type.hubTitleLocalized)
                    .font(PalantirTheme.bodyFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text(String(format: "office.analytics.entry_count".localized, row.count))
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer(minLength: 0)
            if canViewTotals {
                Text(AppCurrency.amountWithCode(row.amount))
                    .font(PalantirTheme.dataFont(12))
                    .foregroundStyle(PalantirTheme.accent)
            }
        }
        .padding(10)
        .background(PalantirTheme.surfaceHigh.opacity(0.55))
        .overlay(Rectangle().stroke(PalantirTheme.border.opacity(0.7), lineWidth: 1))
    }

    private var damageSection: some View {
        WheelSysPalantirSectionCard(
            title: "office.analytics.damage_by_vehicle".localized.uppercased(),
            icon: "car.side.fill"
        ) {
            if damageRows.isEmpty {
                emptyStrip("office.analytics.no_damage_data".localized)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(groupedDamageByMonth(), id: \.month) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.month)
                                .font(PalantirTheme.labelFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                            ForEach(group.rows) { row in
                                damageRowView(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupedDamageByMonth() -> [(month: String, rows: [OfficeAnalyticsVehicleDamageRow])] {
        let grouped = Dictionary(grouping: damageRows, by: \.monthLabel)
        return buckets.compactMap { bucket in
            guard let rows = grouped[bucket.label], !rows.isEmpty else { return nil }
            return (bucket.label, rows.sorted { $0.count > $1.count })
        }
    }

    private func damageRowView(_ row: OfficeAnalyticsVehicleDamageRow) -> some View {
        HStack(spacing: 10) {
            Text(row.plate)
                .font(PalantirTheme.dataFont(14))
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer(minLength: 0)
            PalantirOpsBadge(text: "\(row.count)", tone: .accent)
            if row.openCount > 0 {
                PalantirOpsBadge(
                    text: String(format: "office.analytics.open_damage".localized, row.openCount),
                    tone: .warning
                )
            }
        }
        .padding(10)
        .background(PalantirTheme.surfaceHigh.opacity(0.55))
        .overlay(Rectangle().stroke(PalantirTheme.border.opacity(0.7), lineWidth: 1))
    }

    private func emptyStrip(_ message: String) -> some View {
        WheelSysPalantirStatusStrip(icon: "chart.xyaxis.line", message: message, tint: PalantirTheme.textMuted)
    }

    private func palantirTint(for type: OfficeOperationType) -> Color {
        switch type.color {
        case "blue": return PalantirTheme.accent
        case "green": return PalantirTheme.success
        case "orange": return PalantirTheme.warning
        case "red": return PalantirTheme.critical
        default: return PalantirTheme.textMuted
        }
    }
}

struct OfficeAnalyticsHubCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title2)
                    .foregroundStyle(PalantirTheme.accent)
                Spacer()
                PalantirOpsBadge(text: "ADMIN".localized, tone: .accent)
            }
            Text("office.analytics.title".localized)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textPrimary)
                .multilineTextAlignment(.leading)
            Text("office.analytics.hub_subtitle".localized)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(PalantirTheme.accent.opacity(0.08))
        .overlay(Rectangle().stroke(PalantirTheme.accent.opacity(0.28), lineWidth: 1))
    }
}
