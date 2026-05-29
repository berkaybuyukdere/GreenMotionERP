import SwiftUI

private enum ProtocolPaymentFilter: String, CaseIterable, Identifiable {
    case all, paid, pending, unpaid
    var id: String { rawValue }
}

struct ProtocolListView: View {
    @StateObject private var viewModel = ProtocolListViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var searchQuery = ""
    @State private var paymentFilter: ProtocolPaymentFilter = .all
    @State private var useDateFilter = false
    @State private var startDate = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showFilters = false
    @State private var listExpanded = true
    @State private var visibleListCount = 50

    private static let listPageSize = 50

    var filteredProtocols: [Protocol] {
        var items = viewModel.protocols

        if paymentFilter != .all {
            items = items.filter { $0.effectivePaymentStatus == paymentFilter.rawValue }
        }

        if !searchQuery.isEmpty {
            items = items.filter { item in
                item.customerName.localizedCaseInsensitiveContains(searchQuery) ||
                item.vehiclePlate.localizedCaseInsensitiveContains(searchQuery) ||
                item.protocolName.localizedCaseInsensitiveContains(searchQuery) ||
                item.reservationNumber.localizedCaseInsensitiveContains(searchQuery) ||
                item.protocolId.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        if useDateFilter {
            let rangeEnd = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
            items = items.filter { item in
                guard let createdAt = item.createdAtFormatted else { return true }
                return createdAt >= startDate && createdAt <= rangeEnd
            }
        }

        return items
    }

    private var displayedProtocols: [Protocol] {
        Array(filteredProtocols.prefix(visibleListCount))
    }

    private var hasMoreProtocols: Bool {
        visibleListCount < filteredProtocols.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                PalantirTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        kpiSection
                        paymentFilterChips
                        searchBar
                        generatedProtocolsHeader

                        if listExpanded {
                            if viewModel.isLoading && viewModel.protocols.isEmpty {
                                loadingView
                            } else if filteredProtocols.isEmpty {
                                emptyStateView
                            } else {
                                protocolRows
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("protocols.generated.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done".localized) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(PalantirTheme.accent)
                    }
                }
            }
            .refreshable { viewModel.refreshProtocols() }
            .sheet(isPresented: $showFilters) {
                ProtocolDateFiltersView(
                    startDate: $startDate,
                    endDate: $endDate,
                    useDateFilter: $useDateFilter
                )
            }
            .onChange(of: searchQuery) { _, _ in visibleListCount = Self.listPageSize }
            .onChange(of: paymentFilter) { _, _ in visibleListCount = Self.listPageSize }
            .onChange(of: useDateFilter) { _, _ in visibleListCount = Self.listPageSize }
            .onChange(of: startDate) { _, _ in visibleListCount = Self.listPageSize }
            .onChange(of: endDate) { _, _ in visibleListCount = Self.listPageSize }
        }
    }

    private var kpiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("protocols.kpi.section".localized)
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ProtocolKPICard(
                    label: "protocols.kpi.total".localized,
                    value: "\(viewModel.totalProtocols)",
                    footnote: shownFootnote,
                    tone: .neutral
                )
                ProtocolKPICard(
                    label: "protocols.kpi.paid".localized,
                    value: "\(viewModel.paidCount)",
                    footnote: "protocols.kpi.paid.footnote".localized,
                    tone: .success
                )
                ProtocolKPICard(
                    label: "protocols.kpi.pending".localized,
                    value: "\(viewModel.pendingPaymentCount)",
                    footnote: "protocols.kpi.pending.footnote".localized,
                    tone: .warning
                )
                ProtocolKPICard(
                    label: "protocols.kpi.unpaid".localized,
                    value: "\(viewModel.unpaidCount)",
                    footnote: AppCurrency.format(viewModel.totalOutstanding) + " " + "protocols.kpi.outstanding".localized,
                    tone: .critical
                )
            }
        }
    }

    private var paymentFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProtocolPaymentFilter.allCases) { filter in
                    ProtocolPaymentChip(
                        title: chipTitle(for: filter),
                        count: chipCount(for: filter),
                        isSelected: paymentFilter == filter,
                        tone: chipTone(for: filter)
                    ) {
                        paymentFilter = filter
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("Search protocols...".localized, text: $searchQuery)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
        .padding(10)
        .background(PalantirTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(PalantirTheme.border, lineWidth: 1)
        )
    }

    private var generatedProtocolsHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { listExpanded.toggle() }
        } label: {
            HStack {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(listExpanded ? 0 : -90))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                Text("protocols.generated.list".localized + " (\(filteredProtocols.count))")
                    .font(PalantirTheme.heroFont(14))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var shownFootnote: String {
        let shown = displayedProtocols.count
        let total = filteredProtocols.count
        if shown < total {
            return String(format: "protocols.kpi.shown_paged".localized, shown, total)
        }
        return "\(total) " + "protocols.kpi.shown".localized
    }

    private var protocolRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(displayedProtocols) { protocolItem in
                NavigationLink(destination: ProtocolDetailView(protocol: protocolItem)) {
                    ProtocolRowView(protocol: protocolItem)
                }
                .buttonStyle(.plain)
            }

            if hasMoreProtocols {
                Button {
                    visibleListCount = min(visibleListCount + Self.listPageSize, filteredProtocols.count)
                } label: {
                    HStack {
                        Spacer()
                        Text(
                            String(
                                format: "protocols.load_more".localized,
                                min(Self.listPageSize, filteredProtocols.count - visibleListCount)
                            )
                        )
                        .font(PalantirTheme.labelFont(12))
                        .foregroundStyle(PalantirTheme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading protocols...".localized)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textMuted)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.critical)
                    .multilineTextAlignment(.center)
                Button("Retry".localized) { viewModel.loadProtocols() }
                    .font(PalantirTheme.labelFont(12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .palantirCard()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(PalantirTheme.textMuted)
            Text("No Protocols Found".localized)
                .font(PalantirTheme.heroFont(15))
                .foregroundStyle(PalantirTheme.textPrimary)
            Text("Try adjusting your search or filters".localized)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .palantirCard()
    }

    private func chipTitle(for filter: ProtocolPaymentFilter) -> String {
        switch filter {
        case .all: return "All".localized
        case .paid: return "protocols.kpi.paid".localized
        case .pending: return "protocols.kpi.pending".localized
        case .unpaid: return "protocols.kpi.unpaid".localized
        }
    }

    private func chipCount(for filter: ProtocolPaymentFilter) -> Int {
        switch filter {
        case .all: return viewModel.totalProtocols
        case .paid: return viewModel.paidCount
        case .pending: return viewModel.pendingPaymentCount
        case .unpaid: return viewModel.unpaidCount
        }
    }

    private func chipTone(for filter: ProtocolPaymentFilter) -> ProtocolKPITone {
        switch filter {
        case .all: return .neutral
        case .paid: return .success
        case .pending: return .warning
        case .unpaid: return .critical
        }
    }
}

// MARK: - Palantir KPI / chips

private enum ProtocolKPITone {
    case neutral, success, warning, critical

    var accent: Color {
        switch self {
        case .neutral: return PalantirTheme.accent
        case .success: return PalantirTheme.success
        case .warning: return PalantirTheme.warning
        case .critical: return PalantirTheme.critical
        }
    }
}

private struct ProtocolKPICard: View {
    let label: String
    let value: String
    let footnote: String
    let tone: ProtocolKPITone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
            Text(value)
                .font(PalantirTheme.dataFont(22))
                .foregroundStyle(tone.accent)
            Text(footnote)
                .font(PalantirTheme.bodyFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .palantirCard()
    }
}

private struct ProtocolPaymentChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let tone: ProtocolKPITone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(tone.accent).frame(width: 6, height: 6)
                Text(title)
                    .font(PalantirTheme.labelFont(11))
                Text("\(count)")
                    .font(PalantirTheme.dataFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? tone.accent.opacity(0.12) : PalantirTheme.surface)
            .foregroundStyle(isSelected ? tone.accent : PalantirTheme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? tone.accent : PalantirTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProtocolDateFiltersView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var useDateFilter: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("protocols.filter.use_date".localized, isOn: $useDateFilter)
                } footer: {
                    Text("protocols.filter.use_date.footer".localized)
                }

                if useDateFilter {
                    Section("Date Range".localized) {
                        DatePicker("Start Date".localized, selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date".localized, selection: $endDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Filters".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset".localized) {
                        useDateFilter = false
                        startDate = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
                        endDate = Date()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Protocol Row View
struct ProtocolRowView: View {
    let `protocol`: Protocol

    private var paymentTone: ProtocolKPITone {
        switch `protocol`.effectivePaymentStatus {
        case "paid": return .success
        case "unpaid": return .critical
        default: return .warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(`protocol`.protocolName)
                        .font(PalantirTheme.heroFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(1)
                    Text(`protocol`.protocolId)
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(`protocol`.effectivePaymentStatus.uppercased())
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(paymentTone.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(paymentTone.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(AppCurrency.format(`protocol`.financialRequired))
                        .font(PalantirTheme.dataFont(13))
                        .foregroundStyle(PalantirTheme.textPrimary)
                }
            }

            HStack {
                Label(`protocol`.customerName, systemImage: "person")
                Spacer()
                Label(`protocol`.vehiclePlate, systemImage: "car")
            }
            .font(PalantirTheme.bodyFont(12))
            .foregroundStyle(PalantirTheme.textMuted)
            .lineLimit(1)

            HStack {
                Text("Reservation".localized + ": \(`protocol`.reservationNumber)")
                Spacer()
                if let createdAt = `protocol`.createdAtFormatted {
                    Text(createdAt, style: .date)
                }
                if `protocol`.financialOutstanding > 0.01 {
                    Text(AppCurrency.format(`protocol`.financialOutstanding) + " " + "protocols.kpi.outstanding".localized)
                        .foregroundStyle(PalantirTheme.critical)
                }
            }
            .font(PalantirTheme.bodyFont(11))
            .foregroundStyle(PalantirTheme.textMuted)
        }
        .palantirCard()
    }
}

// MARK: - Protocol Detail View
struct ProtocolDetailView: View {
    let `protocol`: Protocol
    @Environment(\.dismiss) var dismiss

    private var paymentTone: ProtocolKPITone {
        switch `protocol`.effectivePaymentStatus {
        case "paid": return .success
        case "unpaid": return .critical
        default: return .warning
        }
    }

    private var templateFileName: String {
        let path = `protocol`.templatePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "—" }
        return (path as NSString).lastPathComponent
    }

    var body: some View {
        ZStack {
            PalantirTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard
                    PalantirDetailSection(title: "Customer Information".localized) {
                        PalantirDetailRow(label: "Name".localized, value: `protocol`.customerName)
                        PalantirDetailRow(label: "Vehicle Plate".localized, value: `protocol`.vehiclePlate)
                        PalantirDetailRow(label: "Reservation".localized, value: `protocol`.reservationNumber)
                    }
                    PalantirDetailSection(title: "Protocol Information".localized) {
                        PalantirDetailRow(label: "Type".localized, value: `protocol`.protocolType)
                        PalantirDetailRow(label: "Template".localized, value: templateFileName)
                        PalantirDetailRow(label: "Status".localized, value: `protocol`.status)
                        PalantirDetailRow(
                            label: "protocols.detail.required".localized,
                            value: AppCurrency.format(`protocol`.financialRequired),
                            emphasize: true
                        )
                        if `protocol`.financialPaid > 0.01 {
                            PalantirDetailRow(
                                label: "protocols.detail.paid".localized,
                                value: AppCurrency.format(`protocol`.financialPaid)
                            )
                        }
                        if `protocol`.financialOutstanding > 0.01 {
                            PalantirDetailRow(
                                label: "protocols.kpi.outstanding".localized,
                                value: AppCurrency.format(`protocol`.financialOutstanding),
                                valueColor: PalantirTheme.critical
                            )
                        }
                    }
                    PalantirDetailSection(title: "Dates".localized) {
                        PalantirDetailRow(label: "Check In".localized, value: formatDate(`protocol`.checkInDate))
                        PalantirDetailRow(label: "Check Out".localized, value: formatDate(`protocol`.checkOutDate))
                        PalantirDetailRow(label: "Created".localized, value: formatDate(`protocol`.createdAt))
                        PalantirDetailRow(label: "Updated".localized, value: formatDate(`protocol`.updatedAt))
                    }
                    if let fieldValues = `protocol`.fieldValuesDict, !fieldValues.isEmpty {
                        PalantirDetailSection(title: "Field Values".localized) {
                            ForEach(Array(fieldValues.keys.sorted()), id: \.self) { key in
                                PalantirDetailRow(label: key, value: fieldValues[key] ?? "")
                            }
                        }
                    }
                    PalantirDetailSection(title: "Audit Information".localized) {
                        PalantirDetailRow(label: "Created By".localized, value: `protocol`.createdBy)
                        PalantirDetailRow(label: "Updated By".localized, value: `protocol`.updatedBy)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Protocol Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(`protocol`.protocolName)
                        .font(PalantirTheme.heroFont(17))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    Text("ID".localized + ": \(`protocol`.protocolId)")
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    PalantirOpsBadge(
                        text: `protocol`.effectivePaymentStatus.uppercased(),
                        tone: paymentBadgeTone
                    )
                    Text(AppCurrency.format(`protocol`.financialRequired))
                        .font(PalantirTheme.dataFont(20))
                        .foregroundStyle(PalantirTheme.textPrimary)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: `protocol`.statusIcon)
                    .foregroundStyle(statusColor)
                Text(`protocol`.status)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(statusColor)
            }
        }
        .palantirCard()
    }

    private var paymentBadgeTone: PalantirOpsBadge.Tone {
        switch `protocol`.effectivePaymentStatus {
        case "paid": return .success
        case "unpaid": return .critical
        default: return .warning
        }
    }

    private var statusColor: Color {
        switch `protocol`.statusColor {
        case "green": return PalantirTheme.success
        case "orange": return PalantirTheme.warning
        case "red": return PalantirTheme.critical
        default: return PalantirTheme.textMuted
        }
    }

    private func formatDate(_ dateString: String) -> String {
        if let date = parseISO(dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return dateString.isEmpty ? "—" : dateString
    }

    private func parseISO(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: trimmed) { return d }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: trimmed)
    }
}

private struct PalantirDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PalantirSectionHeader(title: title)
            VStack(spacing: 0) {
                content
            }
        }
        .palantirCard()
    }
}

private struct PalantirDetailRow: View {
    let label: String
    let value: String
    var emphasize: Bool = false
    var valueColor: Color = PalantirTheme.textPrimary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(emphasize ? PalantirTheme.dataFont(13) : PalantirTheme.bodyFont(13))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PalantirTheme.border.opacity(0.5))
                .frame(height: 1)
        }
    }
}

// MARK: - Protocol Statistics View
struct ProtocolStatisticsView: View {
    let protocols: [Protocol]
    @Environment(\.dismiss) var dismiss
    
    private var statistics: ProtocolStatistics {
        ProtocolStatistics(protocols: protocols)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Overview Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ProtocolStatCard(title: "Total Protocols".localized, value: "\(statistics.totalProtocols)", color: .blue)
                        ProtocolStatCard(title: "Total Value".localized, value: AppCurrency.format(statistics.totalBaseCost), color: .green)
                        ProtocolStatCard(title: "Average Value".localized, value: AppCurrency.format(statistics.averageBaseCost), color: Color.orange)
                        ProtocolStatCard(title: "Completion Rate".localized, value: statistics.totalProtocols > 0 ? "\(Int((Double(statistics.completedCount) / Double(statistics.totalProtocols)) * 100))%" : "0%", color: .purple)
                    }
                    
                    // Status Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status Breakdown".localized)
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            StatusRow(status: "Draft".localized, count: statistics.draftCount, color: PalantirTheme.textMuted)
                            StatusRow(status: "Pending".localized, count: statistics.pendingCount, color: Color.orange)
                            StatusRow(status: "Complete".localized, count: statistics.completedCount, color: .green)
                            StatusRow(status: "Overdue".localized, count: statistics.overdueCount, color: .red)
                            StatusRow(status: "Cancelled".localized, count: statistics.cancelledCount, color: .red)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Protocol Statistics".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Protocol Stat Card
struct ProtocolStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Status Row
struct StatusRow: View {
    let status: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(status)
                .font(.subheadline)
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ProtocolListView()
}
