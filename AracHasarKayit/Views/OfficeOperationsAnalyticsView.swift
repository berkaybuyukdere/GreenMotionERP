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
    let fullLabel: String
}

struct OfficeAnalyticsMonthSummary: Identifiable {
    let bucket: OfficeAnalyticsMonthBucket
    let officeEntryCount: Int
    let officeAmount: Double
    let damageCount: Int
    let openDamageCount: Int
    let byType: [(type: OfficeOperationType, count: Int, amount: Double)]
    let topPlates: [(plate: String, count: Int, open: Int)]

    var id: String { bucket.id }
}

enum OfficeOperationsAnalyticsEngine {
    private static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return cal
    }

    static func monthBuckets(endingAt end: Date, count: Int) -> [OfficeAnalyticsMonthBucket] {
        let cal = zurichCalendar
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) ?? end
        var buckets: [OfficeAnalyticsMonthBucket] = []
        for offset in (0..<count).reversed() {
            guard let monthStart = cal.date(byAdding: .month, value: -offset, to: endMonth) else { continue }
            let comps = cal.dateComponents([.year, .month], from: monthStart)
            let short = monthStart.formatted(.dateTime.month(.wide).year(.defaultDigits))
            let id = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            buckets.append(OfficeAnalyticsMonthBucket(
                id: id,
                start: monthStart,
                label: monthStart.formatted(.dateTime.month(.abbreviated).year(.twoDigits)),
                fullLabel: short
            ))
        }
        return buckets
    }

    static func monthRange(for bucket: OfficeAnalyticsMonthBucket) -> (start: Date, end: Date) {
        let cal = zurichCalendar
        let start = bucket.start
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: start),
              let end = cal.date(byAdding: .second, value: -1, to: nextMonth) else {
            return (start, start)
        }
        return (start, end)
    }

    static func monthSummaries(
        operations: [OfficeOperation],
        damages: [HasarKaydi],
        buckets: [OfficeAnalyticsMonthBucket],
        types: [OfficeOperationType]
    ) -> [OfficeAnalyticsMonthSummary] {
        buckets.map { bucket in
            let range = monthRange(for: bucket)
            let monthOps = operations.filter { $0.date >= range.start && $0.date <= range.end }
            let monthDamages = damages.filter { $0.tarih >= range.start && $0.tarih <= range.end }
            let byType: [(OfficeOperationType, Int, Double)] = types.compactMap { type in
                let slice = monthOps.filter { $0.type == type }
                guard !slice.isEmpty else { return nil }
                return (type, slice.count, slice.reduce(0) { $0 + $1.amount })
            }.sorted { $0.2 > $1.2 }
            let plateGrouped = Dictionary(grouping: monthDamages) { plateKey($0.aracPlaka) }
                .filter { !$0.key.isEmpty }
            let topPlates = plateGrouped
                .map { key, rows -> (String, Int, Int) in
                    (displayPlate(key), rows.count, rows.filter { $0.durum != .done }.count)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(6)
                .map { ($0.0, $0.1, $0.2) }
            return OfficeAnalyticsMonthSummary(
                bucket: bucket,
                officeEntryCount: monthOps.count,
                officeAmount: monthOps.reduce(0) { $0 + $1.amount },
                damageCount: monthDamages.count,
                openDamageCount: monthDamages.filter { $0.durum != .done }.count,
                byType: byType,
                topPlates: topPlates
            )
        }
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

    private var monthSummaries: [OfficeAnalyticsMonthSummary] {
        OfficeOperationsAnalyticsEngine.monthSummaries(
            operations: viewModel.officeOperations,
            damages: viewModel.allHasarKayitlariForReporting,
            buckets: buckets,
            types: officeTypes
        )
    }

    private var periodTotals: (entries: Int, amount: Double, damages: Int) {
        monthSummaries.reduce((0, 0, 0)) { acc, month in
            (acc.0 + month.officeEntryCount, acc.1 + month.officeAmount, acc.2 + month.damageCount)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                periodPicker
                periodSummaryStrip
                ForEach(monthSummaries.reversed()) { month in
                    monthCard(month)
                }
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
        .onAppear { normalizeAnchorMonth() }
        .onChange(of: selectedMonthAnchor) { _, _ in normalizeAnchorMonth() }
    }

    private func normalizeAnchorMonth() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedMonthAnchor)
        if let normalized = cal.date(from: comps), normalized != selectedMonthAnchor {
            selectedMonthAnchor = normalized
        }
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
                Text(periodRangeCaption)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
    }

    private var periodRangeCaption: String {
        guard let first = buckets.first?.fullLabel, let last = buckets.last?.fullLabel else { return "" }
        return String(format: "office.analytics.range_caption".localized, first, last)
    }

    private var periodSummaryStrip: some View {
        HStack(spacing: 10) {
            summaryPill(
                icon: "doc.text.fill",
                title: "office.analytics.ops_entries".localized,
                value: "\(periodTotals.entries)",
                tint: PalantirTheme.accent
            )
            if canViewTotals {
                summaryPill(
                    icon: "banknote.fill",
                    title: AppCurrency.code,
                    value: AppCurrency.format(periodTotals.amount),
                    tint: PalantirTheme.success
                )
            }
            summaryPill(
                icon: "exclamationmark.triangle.fill",
                title: "office.analytics.damage_reports".localized,
                value: "\(periodTotals.damages)",
                tint: PalantirTheme.warning
            )
        }
    }

    private func summaryPill(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(PalantirTheme.labelFont(8))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(1)
            }
            Text(value)
                .font(PalantirTheme.dataFont(15))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func monthCard(_ month: OfficeAnalyticsMonthSummary) -> some View {
        WheelSysPalantirSectionCard(
            title: month.bucket.fullLabel.uppercased(),
            icon: "calendar.badge.clock"
        ) {
            HStack(spacing: 10) {
                monthMetric(
                    label: "office.analytics.ops_entries".localized,
                    value: "\(month.officeEntryCount)",
                    tint: PalantirTheme.accent
                )
                if canViewTotals {
                    monthMetric(
                        label: AppCurrency.code,
                        value: AppCurrency.format(month.officeAmount),
                        tint: PalantirTheme.success
                    )
                }
                monthMetric(
                    label: "office.analytics.damage_short".localized,
                    value: "\(month.damageCount)",
                    tint: PalantirTheme.warning
                )
            }

            if month.officeEntryCount == 0 && month.damageCount == 0 {
                WheelSysPalantirStatusStrip(
                    icon: "minus.circle",
                    message: "office.analytics.month_empty".localized,
                    tint: PalantirTheme.textMuted
                )
            } else {
                if !month.byType.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("office.analytics.office_breakdown".localized.uppercased())
                            .font(PalantirTheme.labelFont(9))
                            .foregroundStyle(PalantirTheme.textMuted)
                        ForEach(month.byType, id: \.type.rawValue) { row in
                            HStack(spacing: 8) {
                                Image(systemName: row.type.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palantirTint(for: row.type))
                                    .frame(width: 18)
                                Text(row.type.hubTitleLocalized)
                                    .font(PalantirTheme.bodyFont(12))
                                    .foregroundStyle(PalantirTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(String(format: "office.analytics.entry_count".localized, row.count))
                                    .font(PalantirTheme.labelFont(10))
                                    .foregroundStyle(PalantirTheme.textMuted)
                                if canViewTotals {
                                    Text(AppCurrency.format(row.amount))
                                        .font(PalantirTheme.dataFont(11))
                                        .foregroundStyle(PalantirTheme.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(10)
                    .background(PalantirTheme.surfaceHigh.opacity(0.45))
                    .overlay(Rectangle().stroke(PalantirTheme.border.opacity(0.6), lineWidth: 1))
                }

                if !month.topPlates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("office.analytics.damage_by_vehicle".localized.uppercased())
                            .font(PalantirTheme.labelFont(9))
                            .foregroundStyle(PalantirTheme.textMuted)
                        ForEach(month.topPlates, id: \.plate) { row in
                            HStack(spacing: 8) {
                                Text(row.plate)
                                    .font(PalantirTheme.dataFont(12))
                                    .foregroundStyle(PalantirTheme.textPrimary)
                                Spacer(minLength: 0)
                                PalantirOpsBadge(text: "\(row.count)", tone: .accent)
                                if row.open > 0 {
                                    PalantirOpsBadge(
                                        text: String(format: "office.analytics.open_short".localized, row.open),
                                        tone: .warning
                                    )
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(10)
                    .background(PalantirTheme.surfaceHigh.opacity(0.45))
                    .overlay(Rectangle().stroke(PalantirTheme.border.opacity(0.6), lineWidth: 1))
                }

                if month.openDamageCount > 0 {
                    WheelSysPalantirStatusStrip(
                        icon: "exclamationmark.triangle.fill",
                        message: String(format: "office.analytics.open_damage_month".localized, month.openDamageCount),
                        tint: PalantirTheme.warning
                    )
                }
            }
        }
    }

    private func monthMetric(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(PalantirTheme.labelFont(8))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(1)
            Text(value)
                .font(PalantirTheme.dataFont(14))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08))
        .overlay(Rectangle().stroke(tint.opacity(0.2), lineWidth: 1))
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
