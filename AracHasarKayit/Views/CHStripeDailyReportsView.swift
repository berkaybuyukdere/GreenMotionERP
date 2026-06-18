import SwiftUI
import Charts

/// Stripe daily reports — KPIs, charts, and period filters for CH financial hub.
struct CHStripeDailyReportsView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme

    let franchiseId: String

    @State private var period: CHStripeDailyReportPeriod = .sevenDays
    @State private var snapshot: CHStripeDailyReportSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartDay: String?

    private var canViewTotals: Bool {
        authManager.userProfile?.canViewStripePaymentTotals ?? false
    }

    private var dailySeries: [CHStripeDailyReportDayPoint] {
        snapshot?.dailySeries ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            periodPicker
            if let snapshot {
                rangeCaption(snapshot)
                kpiSection(snapshot)
                paymentsChartSection
                chargebacksChartSection
                mailOrderCategorySection(snapshot.mailOrder.byCategory)
            } else if isLoading {
                loadingPlaceholder
            } else {
                emptyPlaceholder
            }
        }
        .task(id: period) {
            await load()
        }
        .refreshable {
            await load()
        }
        .alert("Error".localized, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CHStripeDailyReportPeriod.allCases) { item in
                    Button {
                        period = item
                    } label: {
                        Text(item.localizedTitle)
                            .font(.caption.weight(period == item ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(period == item ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rangeCaption(_ snapshot: CHStripeDailyReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ch_stripe.reports_range".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let syncedAt = snapshot.syncedAt {
                    Text(String(format: "ch_stripe.daily_last_sync".localized, syncedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(snapshot.startDayKey) — \(snapshot.endDayKey)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func kpiSection(_ snapshot: CHStripeDailyReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_stripe.reports_kpis".localized)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                kpiTile(
                    title: "ch_stripe.reports_kpi_payments".localized,
                    metric: snapshot.payments,
                    icon: "creditcard.fill",
                    color: .green
                )
                kpiTile(
                    title: "ch_stripe.chargebacks_title".localized,
                    metric: snapshot.chargebacks,
                    icon: "exclamationmark.shield.fill",
                    color: .orange
                )
                kpiTile(
                    title: "ch_stripe.reports_kpi_mailorder".localized,
                    metric: CHStripeReportMetric(count: snapshot.mailOrder.count, volume: snapshot.mailOrder.volume),
                    icon: "envelope.fill",
                    color: .purple
                )
            }
        }
        .padding()
        .background(cardBackground)
    }

    private func kpiTile(title: String, metric: CHStripeReportMetric, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(metric.count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
            if canViewTotals {
                Text(AppCurrency.format(metric.volume))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(colorScheme == .dark ? 0.15 : 0.08)))
    }

    private var paymentsChartSection: some View {
        chartCard(title: "ch_stripe.reports_chart_payments".localized, color: .green) {
            Chart(dailySeries) { point in
                BarMark(
                    x: .value("Day", point.dayKey),
                    y: .value("Volume", canViewTotals ? point.payments.volume : Double(point.payments.count))
                )
                .foregroundStyle(
                    selectedChartDay == point.dayKey
                        ? Color.green
                        : Color.green.opacity(0.55)
                )
            }
            .frame(height: 180)
            .chartXSelection(value: $selectedChartDay)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    if let key = value.as(String.self),
                       let point = dailySeries.first(where: { $0.dayKey == key }) {
                        AxisValueLabel(point.shortLabel)
                    }
                }
            }
            .chartYAxisLabel(canViewTotals ? AppCurrency.code : "Count".localized)
        }
    }

    private var chargebacksChartSection: some View {
        chartCard(title: "ch_stripe.reports_chart_chargebacks".localized, color: .orange) {
            Chart(dailySeries) { point in
                LineMark(
                    x: .value("Day", point.shortLabel),
                    y: .value("Count", point.chargebacks.count)
                )
                .foregroundStyle(Color.orange)
                PointMark(
                    x: .value("Day", point.shortLabel),
                    y: .value("Count", point.chargebacks.count)
                )
                .foregroundStyle(Color.orange)
            }
            .frame(height: 160)
            .chartYAxisLabel("Count".localized)
        }
    }

    private func mailOrderCategorySection(_ categories: CHStripeMailOrderCategoryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_stripe.reports_mailorder_by_category".localized)
                .font(.subheadline.weight(.semibold))

            Chart {
                ForEach(CHStripeMailOrderCategory.allCases) { cat in
                    let metric = categories.metric(for: cat)
                    BarMark(
                        x: .value("Category", cat.localizedTitle),
                        y: .value("Volume", canViewTotals ? metric.volume : Double(metric.count))
                    )
                    .foregroundStyle(by: .value("Category", cat.rawValue))
                }
            }
            .frame(height: 180)
            .chartForegroundStyleScale([
                CHStripeMailOrderCategory.trafficFine.rawValue: Color.blue,
                CHStripeMailOrderCategory.damage.rawValue: Color.red,
            ])

            HStack(spacing: 10) {
                ForEach(CHStripeMailOrderCategory.allCases) { cat in
                    let metric = categories.metric(for: cat)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(cat.localizedTitle, systemImage: cat.icon)
                            .font(.caption2.weight(.semibold))
                        Text("\(metric.count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                        if canViewTotals {
                            Text(AppCurrency.format(metric.volume))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                }
            }
        }
        .padding()
        .background(cardBackground)
    }

    @ViewBuilder
    private func chartCard<Content: View>(
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            content()
        }
        .padding()
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 40)
    }

    private var emptyPlaceholder: some View {
        Text("ch_stripe.reports_empty".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await CHStripeFinancialService.fetchDailyReports(
                franchiseId: franchiseId,
                period: period
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
