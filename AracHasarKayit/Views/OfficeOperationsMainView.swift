import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

struct OfficeOperationsMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var currentSelectedMonth: Date
    @State private var selectedOperation: OfficeOperationType?
    @State private var showAddOperation = false
    @State private var showProtocols = false
    @State private var showMonthPicker = false
    @State private var draftPickerMonth: Date = Date()
    @State private var monthOpsSnapshot: [OfficeOperation] = []
    @State private var monthOpsRebuildTask: Task<Void, Never>?
    @State private var stripeMailOrders: [CHStripeMailOrderRecord] = []
    @State private var stripeDisputes: [CHStripeDisputeRecord] = []
    @State private var stripeMailOrdersListener: ListenerRegistration?
    @State private var stripeDisputesListener: ListenerRegistration?

    init(selectedMonth: Date = Date()) {
        self.selectedMonth = selectedMonth
        // Find the earliest operation date to set default month, or use provided month
        _currentSelectedMonth = State(initialValue: selectedMonth)
    }
    
    private var canViewOperationTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
    }

    private var canViewStripePaymentTotals: Bool {
        authManager.userProfile?.canViewStripePaymentTotals ?? false
    }

    private var stripeFranchiseId: String {
        let sid = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !sid.isEmpty { return sid }
        return authManager.userProfile?.franchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? StripeCHConfig.franchiseId
    }

    // Computed property to find the earliest operation date
    private var earliestOperationDate: Date {
        guard !viewModel.officeOperations.isEmpty else {
            return Date()
        }
        let dates = viewModel.officeOperations.map { $0.date }
        return dates.min() ?? Date()
    }
    
    // Decimal formatter
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }
    
    func formatAmount(_ amount: Double) -> String {
        if let formatted = numberFormatter.string(from: NSNumber(value: amount)) {
            return "\(formatted) \(AppCurrency.code)"
        }
        return AppCurrency.amountWithCode(amount)
    }
    
    var body: some View {
        contentView
        .onAppear {
            let calendar = Calendar.current
            let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
            if let monthStart = calendar.date(from: monthComponents) {
                currentSelectedMonth = monthStart
            }
            rebuildMonthOpsSnapshot()
        }
        .onChange(of: currentSelectedMonth) { _, _ in scheduleMonthOpsRebuild() }
        .onReceive(viewModel.$officeOperations) { _ in scheduleMonthOpsRebuild() }
        .onAppear {
            if isSwitzerlandOfficeHub {
                subscribeStripePaymentsIfNeeded()
            }
        }
        .onDisappear {
            stripeMailOrdersListener?.remove()
            stripeDisputesListener?.remove()
            stripeMailOrdersListener = nil
            stripeDisputesListener = nil
        }
        .sheet(isPresented: $showAddOperation) {
            NavigationView {
                AddOfficeOperationView()
                    .environmentObject(viewModel)
                    .environment(\.palantirModeEnabled, true)
            }
            .modifier(ConditionalWheelSysCHChrome(enabled: true))
        }
        .onChange(of: showAddOperation) { isPresented in
            if isPresented {
                                }
        }
        .sheet(isPresented: $showProtocols) {
            ProtocolListView()
        }
        .environment(\.palantirModeEnabled, true)
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    operationCardsGrid
                }
            }
        }
        .navigationTitle("Office Operations".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
            ToolbarItem(placement: .principal) {
                monthPickerButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                addButton
            }
        }
        .navigationDestination(item: $selectedOperation) { opType in
            Group {
                if opType == .banking {
                    PaymentsHubListView(selectedMonth: currentSelectedMonth)
                } else {
                    OfficeOperationListView(operationType: opType, selectedMonth: currentSelectedMonth)
                }
            }
            .environmentObject(viewModel)
            .environmentObject(authManager)
            .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
        }
        .sheet(isPresented: $showMonthPicker) {
            monthPickerSheet
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
        .environment(\.palantirModeEnabled, true)
    }

    private func monthRange(for month: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }
    
    private var isSwitzerlandOfficeHub: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private func rebuildMonthOpsSnapshot() {
        let bounds = monthRange(for: currentSelectedMonth)
        monthOpsSnapshot = viewModel.officeOperations.filter {
            $0.date >= bounds.start && $0.date <= bounds.end
        }
    }

    @MainActor
    private func scheduleMonthOpsRebuild() {
        monthOpsRebuildTask?.cancel()
        monthOpsRebuildTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            rebuildMonthOpsSnapshot()
        }
    }

    private var operationCardsGrid: some View {
        var types: [OfficeOperationType] = [.creditCard, .posClosing, .fuelReceipt, .washing, .additionalSales, .banking, .trafficFine]
        if isSwitzerlandOfficeHub {
            types.removeAll { $0 == .banking }
        }

        let opsByType = Dictionary(grouping: monthOpsSnapshot, by: \.type)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: isSwitzerlandOfficeHub ? 13 : 20) {
            ForEach(types, id: \.rawValue) { opType in
                let monthOperations = opsByType[opType] ?? []
                let count = monthOperations.count
                let totalAmount = monthOperations.reduce(0) { $0 + $1.amount }

                Button {
                    selectedOperation = opType
                    HapticManager.shared.medium()
                } label: {
                    if isSwitzerlandOfficeHub {
                        PalantirOfficeOperationCard(
                            type: opType,
                            count: count,
                            totalAmount: totalAmount,
                            selectedMonth: currentSelectedMonth,
                            monthOperations: monthOperations,
                            canViewOperationTotals: canViewOperationTotals
                        )
                    } else {
                        BigOfficeOperationCard(
                            type: opType,
                            count: count,
                            totalAmount: totalAmount,
                            selectedMonth: currentSelectedMonth,
                            viewModel: viewModel,
                            monthOperations: monthOperations,
                            canViewOperationTotals: canViewOperationTotals
                        )
                    }
                }
                .buttonStyle(CardButtonStyle())
            }
            
                if canViewOperationTotals {
                    NavigationLink {
                        OfficeOperationsAnalyticsView()
                            .environmentObject(viewModel)
                            .environmentObject(authManager)
                    } label: {
                        OfficeAnalyticsHubCard()
                    }
                    .buttonStyle(CardButtonStyle())
                }

            // Protocols Card - matching other cards style
            Button {
                                showProtocols = true
                HapticManager.shared.medium()
            } label: {
                ProtocolsCard()
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink {
                OfficeReturnMainView(selectedMonth: currentSelectedMonth, embedsNavigationChrome: false)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            } label: {
                OfficeReturnsOfficeCard(
                    selectedMonth: currentSelectedMonth,
                    returns: viewModel.officeReturns,
                    canViewOperationTotals: canViewOperationTotals
                )
            }
            .buttonStyle(CardButtonStyle())

            if isSwitzerlandOfficeHub {
                NavigationLink {
                    FleetOperationsHubView(selectedMonth: currentSelectedMonth)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    FleetOperationsOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        viewModel: viewModel,
                        canViewOperationTotals: canViewOperationTotals
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    TrafficAccidentContractsListView(selectedMonth: currentSelectedMonth)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    TrafficAccidentContractsOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        contracts: viewModel.trafficAccidentContracts,
                        canViewOperationTotals: canViewOperationTotals
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    InkassoHubListView(selectedMonth: currentSelectedMonth)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    InkassoOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        operations: viewModel.officeOperations,
                        canViewOperationTotals: canViewOperationTotals
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    PaymentsHubListView(selectedMonth: currentSelectedMonth)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    BankingTransactionOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        operations: viewModel.officeOperations,
                        canViewOperationTotals: canViewOperationTotals
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    PoliceReportsListView(selectedMonth: currentSelectedMonth)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    PoliceReportsOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        reports: viewModel.policeReports
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    CHStripeDailyClosingView()
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    CHStripeDailyClosingOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        canViewTotals: canViewStripePaymentTotals
                    )
                }
                .buttonStyle(CardButtonStyle())

                NavigationLink {
                    CHStripeFinancialHubView(selectedMonth: currentSelectedMonth)
                        .environmentObject(authManager)
                        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
                } label: {
                    CHStripeFinancialOfficeCard(
                        selectedMonth: currentSelectedMonth,
                        mailOrders: stripeMailOrders,
                        disputes: stripeDisputes,
                        canViewTotals: canViewStripePaymentTotals
                    )
                }
                .buttonStyle(CardButtonStyle())
            }
        }
        .padding()
    }

    private func subscribeStripePaymentsIfNeeded() {
        stripeMailOrdersListener?.remove()
        stripeDisputesListener?.remove()
        stripeMailOrdersListener = CHStripeFinancialService.subscribeMailOrders(
            franchiseId: stripeFranchiseId,
            limit: 200
        ) { records in
            stripeMailOrders = records
        }
        stripeDisputesListener = CHStripeFinancialService.subscribeDisputes(
            franchiseId: stripeFranchiseId,
            limit: 100
        ) { records in
            stripeDisputes = records
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back".localized)
            }
            .font(isSwitzerlandOfficeHub ? PalantirTheme.labelFont(12) : .body)
            .foregroundColor(isSwitzerlandOfficeHub ? PalantirTheme.accent : .blue)
        }
    }
    
    private var monthPickerButton: some View {
        Button {
            draftPickerMonth = currentSelectedMonth
            showMonthPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(monthDisplayText)
                    .font(isSwitzerlandOfficeHub ? PalantirTheme.dataFont(13) : .subheadline.weight(.medium))
            }
            .foregroundColor(isSwitzerlandOfficeHub ? PalantirTheme.textPrimary : .primary)
            .padding(.horizontal, isSwitzerlandOfficeHub ? 10 : 0)
            .padding(.vertical, isSwitzerlandOfficeHub ? 6 : 0)
            .overlay(
                Group {
                    if isSwitzerlandOfficeHub {
                        Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                    }
                }
            )
        }
    }
    
    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentSelectedMonth)
    }
    
    private var monthPickerSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker(
                    "Select Month".localized,
                    selection: $draftPickerMonth,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Select Month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        let calendar = Calendar.current
                        let comps = calendar.dateComponents([.year, .month], from: draftPickerMonth)
                        if let monthStart = calendar.date(from: comps) {
                            currentSelectedMonth = monthStart
                        }
                        showMonthPicker = false
                    }
                }
            }
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: isSwitzerlandOfficeHub))
    }
    
    private var addButton: some View {
        Button {
            showAddOperation = true
        } label: {
            if isSwitzerlandOfficeHub {
                PalantirSquareToolbarIconButton(systemName: "plus", accessibilityLabel: "Add operation".localized)
            } else {
                PalantirSquareToolbarIconButton(systemName: "plus", accessibilityLabel: "Add operation".localized)
            }
        }
    }
}

// MARK: - Palantir office operation card (CH hub)

struct PalantirOfficeOperationCard: View {
    let type: OfficeOperationType
    let count: Int
    let totalAmount: Double
    let selectedMonth: Date
    var monthOperations: [OfficeOperation] = []
    var canViewOperationTotals: Bool = true

    private var palantirTint: Color {
        switch type.color {
        case "blue", "cyan", "indigo": return PalantirTheme.accent
        case "green": return PalantirTheme.success
        case "orange", "red": return PalantirTheme.warning
        case "purple": return PalantirTheme.purple
        default: return PalantirTheme.textMuted
        }
    }

    private var sparklineData: [Double] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: comps),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart)
        else { return [] }
        let ops = monthOperations
        let buckets = 4
        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        let bucketSize = max(1, daysInMonth / buckets)
        return (0..<buckets).map { bucket in
            let bucketStart = calendar.date(byAdding: .day, value: bucket * bucketSize, to: monthStart)!
            let bucketEnd = calendar.date(byAdding: .day, value: min((bucket + 1) * bucketSize, daysInMonth), to: monthStart)!
            return ops.filter { $0.date >= bucketStart && $0.date < bucketEnd }.reduce(0) { $0 + $1.amount }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palantirTint)
                Text(type.hubTitleLocalized.uppercased())
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            if sparklineData.count > 1 {
                SparklineChart(data: sparklineData, color: palantirTint)
                    .frame(height: 40)
            }
            if canViewOperationTotals {
                Text(AppCurrency.format(totalAmount))
                    .font(PalantirTheme.heroFont(22))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(PalantirTheme.heroFont(22))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Text("\(count) \("entries".localized)")
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct BigOfficeOperationCard: View {
    let type: OfficeOperationType
    let count: Int
    let totalAmount: Double
    let selectedMonth: Date
    let viewModel: AracViewModel
    var monthOperations: [OfficeOperation] = []
    var canViewOperationTotals: Bool = true
    @Environment(\.colorScheme) var colorScheme

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    var color: Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }

    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }

    // MARK: - Sparkline: weekly buckets for current month
    private var sparklineData: [Double] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: comps),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart)
        else { return [] }

        let ops = monthOperations.isEmpty
            ? viewModel.officeOperations.filter { $0.type == type && $0.date >= monthStart && $0.date <= monthEnd }
            : monthOperations
        let buckets = 4
        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
        let bucketSize = max(1, daysInMonth / buckets)

        return (0..<buckets).map { bucket in
            let bucketStart = calendar.date(byAdding: .day, value: bucket * bucketSize, to: monthStart)!
            let bucketEnd = calendar.date(byAdding: .day, value: min((bucket + 1) * bucketSize, daysInMonth), to: monthStart)!
            return ops.filter { $0.date >= bucketStart && $0.date < bucketEnd }.reduce(0) { $0 + $1.amount }
        }
    }

    private var sparklineColor: Color {
        let metrics = viewModel.calculateOfficeOperationMonthlyComparison(operationType: type, selectedMonth: selectedMonth)
        return metrics.amountPercent >= 0 ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: type.icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
                Spacer()
                if canViewOperationTotals {
                    monthlyComparisonBadge
                }
            }

            // Sparkline
            let sData = sparklineData
            if sData.count > 1 {
                SparklineChart(data: sData, color: sparklineColor)
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30)
            }

            // Amount or dash
            if canViewOperationTotals {
                Text(AppCurrency.format(totalAmount))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }

            // Type name — bold for non-managers, secondary caption for managers
            Text(type.hubTitleLocalized)
                .font(canViewOperationTotals ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewOperationTotals ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text("\(count) \("entries".localized)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Monthly Comparison Badge
    private var monthlyComparisonBadge: some View {
        let metrics = viewModel.calculateOfficeOperationMonthlyComparison(operationType: type, selectedMonth: selectedMonth)
        let isUp = metrics.amountPercent >= 0
        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
            Text("\(isUp ? "+" : "")\(String(format: "%.1f", metrics.amountPercent))%")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(isUp ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((isUp ? Color.green : Color.red).opacity(0.12))
        )
    }
}

// MARK: - Protocols Card
struct ProtocolsCard: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        if palantirMode {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PalantirTheme.purple)
                    Text("Protocols".localized.uppercased())
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                    Spacer(minLength: 0)
                }
                Text("View protocols".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .padding(14)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        } else {
            legacyProtocolsCard
        }
    }

    private var legacyProtocolsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color.purple.opacity(0.75))
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Color.clear.frame(height: 30)

            // Keep same vertical rhythm as other operation cards
            Spacer(minLength: 6)

            Text("Protocols".localized)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("View protocols".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(" ")
                .font(.caption2)
                .foregroundColor(.clear)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Office Statistics Summary View
struct OfficeStatisticsSummaryView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var totalAmount: Double {
        viewModel.officeOperations.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Statistics".localized)
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    QuickStatCard(
                        title: "Credit Card".localized,
                        amount: viewModel.totalCreditCardAmount,
                        color: .blue
                    )
                    
                    QuickStatCard(
                        title: "POS".localized,
                        amount: viewModel.totalPOSAmount,
                        color: .green
                    )
                }
                
                HStack(spacing: 12) {
                    QuickStatCard(
                        title: "Fuel".localized,
                        amount: viewModel.totalFuelAmount,
                        color: .orange
                    )
                    
                    QuickStatCard(
                        title: "Washing".localized,
                        amount: viewModel.totalWashingAmount,
                        color: .cyan
                    )
                }
            }
        }
    }
}

struct QuickStatCard: View {
    let title: String
    let amount: Double
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(AppCurrency.format(amount))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
        .cornerRadius(12)
    }
}

// MARK: - All Office Operations Report View
struct AllOfficeOperationsReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private var canViewOperationTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
    }
    
    @State private var reportPeriod: ReportPeriod = .weekly
    @State private var selectedOperationType: OfficeOperationType? = nil  // nil = All Operations
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isGenerating = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    
    enum ReportPeriod: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"
        case custom = "Custom Range"
    }
    
    var filteredOperations: [OfficeOperation] {
        let calendar = Calendar.current
        let now = Date()
        
        let dateRange: (start: Date, end: Date)
        
        switch reportPeriod {
        case .daily:
            let start = calendar.startOfDay(for: now)
            dateRange = (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            dateRange = (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            dateRange = (start, now)
        case .yearly:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            dateRange = (start, now)
        case .custom:
            dateRange = (customStartDate, customEndDate)
        }
        
        var ops = viewModel.officeOperations.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }
        
        // Filter by operation type if selected
        if let selectedType = selectedOperationType {
            ops = ops.filter { $0.type == selectedType }
        }
        
        return ops
    }
    
    var totalAmount: Double {
        filteredOperations.reduce(0) { $0 + $1.amount }
    }
    
    var operationsByType: [(type: OfficeOperationType, amount: Double, count: Int)] {
        var result: [(type: OfficeOperationType, amount: Double, count: Int)] = []
        
        for opType in OfficeOperationType.allCases {
            let ops = filteredOperations.filter { $0.type == opType }
            let amount = ops.reduce(0) { $0 + $1.amount }
            if !ops.isEmpty {
                result.append((type: opType, amount: amount, count: ops.count))
            }
        }
        
        return result.sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        List {
            Section("Operation Type".localized) {
                Picker("Select Type".localized, selection: $selectedOperationType) {
                    Text("All Operations".localized).tag(nil as OfficeOperationType?)
                    ForEach(OfficeOperationType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.hubTitleLocalized)
                        }.tag(type as OfficeOperationType?)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedType = selectedOperationType {
                    HStack {
                        Image(systemName: selectedType.icon)
                            .foregroundColor(getColor(for: selectedType))
                        Text("\("Filtering".localized): \(selectedType.hubTitleLocalized)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Report Period".localized) {
                Picker("Period", selection: $reportPeriod) {
                    ForEach(ReportPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                
                if reportPeriod == .custom {
                    DatePicker("Start Date".localized, selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date".localized, selection: $customEndDate, displayedComponents: .date)
                }
            }
            
            Section("Overall Summary".localized) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Period".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(reportPeriod.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Operations".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(filteredOperations.count)")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Amount".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if canViewOperationTotals {
                            Text(AppCurrency.format(totalAmount))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        } else {
                            Text("—")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            
            if !operationsByType.isEmpty, canViewOperationTotals {
                Section("Breakdown by Type".localized) {
                    ForEach(operationsByType, id: \.type) { item in
                        HStack {
                            Image(systemName: item.type.icon)
                                .foregroundColor(getColor(for: item.type))
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.type.hubTitleLocalized)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(item.count) \("entries".localized)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(AppCurrency.format(item.amount))
                                .font(.headline)
                                .foregroundColor(getColor(for: item.type))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Export Options".localized) {
                Button {
                    generatePDFReport()
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text("Generate PDF Report".localized)
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                    .foregroundColor(.red)
                }
                .disabled(isGenerating || filteredOperations.isEmpty)
                
                Button {
                    generateExcelReport()
                } label: {
                    HStack {
                        Image(systemName: "tablecells.fill")
                        Text("Generate Excel Report".localized)
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                    .foregroundColor(.green)
                }
                .disabled(isGenerating || filteredOperations.isEmpty)
            }
            
            if filteredOperations.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("No operations found for this period".localized)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .navigationTitle("Generate Overall Report".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
    
    func getColor(for type: OfficeOperationType) -> Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    func generatePDFReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let pdfData = createPDFData()
            
            // Use documents directory instead of temporary for better file access
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fd = DateFormatter()
            fd.locale = Locale(identifier: "en_US_POSIX")
            fd.dateFormat = "yyyy-MM-dd"
            let datePart = filteredOperations.map(\.date).max().map { fd.string(from: $0) } ?? "nodate"
            let fileURL = documentsPath.appendingPathComponent("OverallOfficeReport_\(datePart).pdf")
            
            do {
                try pdfData.write(to: fileURL)
                
                // Ensure file is accessible
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("❌ PDF file was not created successfully")
                    ErrorManager.shared.showError(message: "Failed to create PDF file")
                    isGenerating = false
                    return
                }
                
                print("✅ PDF created successfully at: \(fileURL.path)")
                shareURL = fileURL
                isGenerating = false
                
                                let operationsCount = viewModel.officeOperations.filter { selectedOperationType == nil || $0.type == selectedOperationType }.count
                // Small delay to ensure file is fully written
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showShareSheet = true
                }
            } catch {
                print("❌ Error writing PDF: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "PDF Generation")
                isGenerating = false
            }
        }
    }
    
    func generateExcelReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let csvData = createCSVData()
            
            // Use documents directory instead of temporary for better file access
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("OverallOfficeReport_\(Date().timeIntervalSince1970).csv")
            
            do {
                try csvData.write(to: fileURL)
                
                // Ensure file is accessible
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("❌ CSV file was not created successfully")
                    ErrorManager.shared.showError(message: "Failed to create CSV file")
                    isGenerating = false
                    return
                }
                
                print("✅ CSV created successfully at: \(fileURL.path)")
                shareURL = fileURL
                isGenerating = false
                
                                let operationsCount = viewModel.officeOperations.filter { selectedOperationType == nil || $0.type == selectedOperationType }.count
                // Small delay to ensure file is fully written
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showShareSheet = true
                }
            } catch {
                print("❌ Error writing CSV: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "CSV Generation")
                isGenerating = false
            }
        }
    }
    
    func createPDFData() -> Data {
        let pdfMetadata = [
            kCGPDFContextTitle: selectedOperationType?.hubTitleLocalized ?? "Office Operations Report",
            kCGPDFContextAuthor: PDFExportBranding.pdfMetadataAuthor,
            kCGPDFContextCreator: PDFExportBranding.pdfMetadataAuthor
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        return renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            
            // MARK: - SWISS DESIGN HEADER (Minimal, no colors)
            var yPosition: CGFloat = 60
            
            // Company Name - Bold Helvetica (no hard-coded trade names)
            let rawName = viewModel.franchiseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGM = rawName.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let companyName = (rawName.isEmpty || isGM) ? PDFExportBranding.genericCompanyTitle : rawName.uppercased()
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            let companyAttrs: [NSAttributedString.Key: Any] = [
                .font: companyFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: companyAttrs)
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let subtitle = UserDefaults.standard.selectedCountry.name.uppercased()
            let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: SwissPDFHelper.mediumGray
            ]
            subtitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 40
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - TITLE (Swiss Design: Bold, minimal)
            let reportTitle = selectedOperationType != nil ? "\(selectedOperationType!.rawValue) Report" : "Office Operations Report"
            let titleFont = SwissPDFHelper.helveticaBold(size: 24)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            reportTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: titleAttrs)
            yPosition += 35
            
            // MARK: - INFO (Swiss Design: Clean lines, no boxes)
            let infoFont = SwissPDFHelper.helvetica(size: 10)
            let labelFont = SwissPDFHelper.helveticaBold(size: 10)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            
            // Report reference date — latest operation in export (not PDF generation time)
            let reportDateLabel = "Latest operation:"
            let latestOp = filteredOperations.map(\.date).max()!
            let reportDateValue = dateFormatter.string(from: latestOp)
            reportDateLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            reportDateValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            // Period
            let periodLabel = "Period:"
            let periodValue = reportPeriod.rawValue
            periodLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            periodValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            // Date Range
            if reportPeriod == .custom {
                let rangeLabel = "Date Range:"
                let rangeValue = "\(dateFormatter.string(from: customStartDate)) - \(dateFormatter.string(from: customEndDate))"
                rangeLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                rangeValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 18
            }
            
            // Operation Type
            if let selectedType = selectedOperationType {
                let typeLabel = "Operation Type:"
                let typeValue = selectedType.hubTitleLocalized
                typeLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                typeValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 18
            }
            
            yPosition += 25
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - SUMMARY SECTION (Swiss Design: Clean typography)
            let summaryTitle = "SUMMARY"
            let sectionFont = SwissPDFHelper.helveticaBold(size: 12)
            summaryTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Summary - No boxes, just clean lines
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            let summaryBoldFont = SwissPDFHelper.helveticaBold(size: 14)
            
            "Total Operations:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(filteredOperations.count)".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            
            if canViewOperationTotals {
                yPosition += 20
                "Total Amount:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
                "\(AppCurrency.amountWithCode(totalAmount))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            }
            
            yPosition += 30
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - BREAKDOWN SECTION (Swiss Design: Grid system, thin lines)
            if canViewOperationTotals, !operationsByType.isEmpty {
                let breakdownTitle = "BREAKDOWN BY TYPE"
                breakdownTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 25
                
                // Table Header - Bold, underlined
                let headerFont = SwissPDFHelper.helveticaBold(size: 9)
                let headerY = yPosition
                "TYPE".draw(at: CGPoint(x: 60, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                "ENTRIES".draw(at: CGPoint(x: 300, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                "AMOUNT".draw(at: CGPoint(x: 430, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                
                // Underline header
                SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: headerY + 12), to: CGPoint(x: pageRect.width - 60, y: headerY + 12), width: 0.5)
                yPosition += 20
                
                let rowFont = SwissPDFHelper.helvetica(size: 9)
                
                for (index, item) in operationsByType.prefix(15).enumerated() {
                    if yPosition > 750 {
                        context.beginPage()
                        yPosition = 60
                    }
                    
                    // No alternating colors - just clean lines
                    item.type.hubTitleLocalized.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                    "\(item.count)".draw(at: CGPoint(x: 300, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                    "\(AppCurrency.amountWithCode(item.amount))".draw(at: CGPoint(x: 430, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                    
                    // Thin separator line
                    if index < operationsByType.prefix(15).count - 1 {
                        SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition + 12), to: CGPoint(x: pageRect.width - 60, y: yPosition + 12), width: 0.25)
                    }
                    
                    yPosition += 18
                }
            }
            
            // MARK: - FOOTER (Swiss Design: Minimal, thin line)
            let footerY = pageRect.height - 30
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 20), to: CGPoint(x: pageRect.width - 60, y: footerY - 20), width: 0.25)
            
            let footerFont = SwissPDFHelper.helveticaThin(size: 7)
            let footerText = "\(PDFExportBranding.copyrightLine) • \(UserDefaults.standard.selectedCountry.name)"
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: SwissPDFHelper.lightGray
            ]
            footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: footerAttrs)
            
            let pageNumber = "1"
            pageNumber.draw(at: CGPoint(x: pageRect.width - 80, y: footerY), withAttributes: footerAttrs)
        }
    }
    
    func createCSVData() -> Data {
        var csv = ""
        
        // Header Section
        csv += "OFFICE OPERATIONS REPORT\n"
        csv += "\(UserDefaults.standard.selectedCountry.name)\n"
        csv += "\n"
        let latestCSV = filteredOperations.map(\.date).max().map { $0.formatted(date: .long, time: .shortened) } ?? ""
        csv += "Latest operation:,\(latestCSV)\n"
        csv += "Period:,\(reportPeriod.rawValue)\n"
        if let selectedType = selectedOperationType {
            csv += "Operation Type:,\(selectedType.hubTitleLocalized)\n"
        } else {
            csv += "Operation Type:,All Operations\n"
        }
        csv += "\n"
        
        // Summary Section
        csv += "SUMMARY\n"
        csv += "Total Operations:,\(filteredOperations.count)\n"
        if canViewOperationTotals {
            csv += "Total Amount:,\(AppCurrency.amountWithCode(totalAmount))\n"
            csv += "\n"
            
            // Breakdown Section
            if !operationsByType.isEmpty {
                csv += "BREAKDOWN BY TYPE\n"
                csv += "Type,Entries,Amount (\(AppCurrency.code))\n"
                for item in operationsByType {
                    csv += "\(item.type.hubTitleLocalized),\(item.count),\(String(format: "%.2f", item.amount))\n"
                }
                csv += "\n"
            }
        } else {
            csv += "\n"
        }
        
        // Detailed Operations Table
        csv += "DETAILED OPERATIONS\n"
        csv += "Date,Time,Type,Amount (\(AppCurrency.code)),Vehicle Plate,POS Count,Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        for operation in filteredOperations.sorted(by: { $0.date > $1.date }) {
            let dateStr = dateFormatter.string(from: operation.date)
            let timeStr = timeFormatter.string(from: operation.date)
            let amountStr = String(format: "%.2f", operation.amount)
            let plate = operation.vehiclePlate ?? "-"
            let posCount = operation.posCount != nil ? "\(operation.posCount!)" : "-"
            let notes = operation.notes.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
            
            csv += "\(dateStr),\(timeStr),\(operation.type.hubTitleLocalized),\(amountStr),\(plate),\(posCount),\(notes)\n"
        }
        
        csv += "\n"
        csv += "End of Report\n"
        csv += "\(PDFExportBranding.csvGeneratedByLine)\n"
        
        return csv.data(using: .utf8) ?? Data()
    }
}

// MARK: - Protocol Card
struct ProtocolCard: View {
    @StateObject private var viewModel = ProtocolListViewModel()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Protocols".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(viewModel.totalProtocols) \("protocols".localized)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                if viewModel.totalBaseCost > 0 {
                    Text("\(AppCurrency.format(viewModel.totalBaseCost)) \("total".localized)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(height: 120)
        .background(
            LinearGradient(
                colors: [Color.purple, Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}

// MARK: - Customer returns hub card (Office Operations)

struct OfficeReturnsOfficeCard: View {
    let selectedMonth: Date
    let returns: [OfficeReturn]
    var canViewOperationTotals: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var monthReturns: [OfficeReturn] {
        let r = monthRange
        return returns.filter { $0.date >= r.start && $0.date <= r.end }
    }

    private var count: Int { monthReturns.count }
    private var totalAmount: Double { monthReturns.reduce(0) { $0 + $1.amount } }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }

    var body: some View {
        if palantirMode {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PalantirTheme.success)
                    Text("Customer Returns".localized.uppercased())
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                if canViewOperationTotals {
                    Text(AppCurrency.format(totalAmount))
                        .font(PalantirTheme.heroFont(22))
                        .foregroundStyle(PalantirTheme.textPrimary)
                } else {
                    Text("—")
                        .font(PalantirTheme.heroFont(22))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Text("\(count) \("entries".localized)")
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .padding(14)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        } else {
            legacyOfficeReturnsCard
        }
    }

    private var legacyOfficeReturnsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.teal)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            Color.clear.frame(height: 30)
            if canViewOperationTotals {
                Text(AppCurrency.format(totalAmount))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text("Customer Returns".localized)
                .font(canViewOperationTotals ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewOperationTotals ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text("\(count) \("entries".localized)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Card Button Style
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Camera View for Office Operations
struct OfficeCameraView: View {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        OfficeCameraViewController(capturedImage: $capturedImage)
            .ignoresSafeArea()
    }
}

struct OfficeCameraViewController: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OfficeCameraViewController
        
        init(_ parent: OfficeCameraViewController) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
