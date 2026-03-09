import SwiftUI
import FirebaseAuth

struct OfficeOperationsMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var currentSelectedMonth: Date
    @State private var selectedOperation: OfficeOperationType?
    @State private var showAddOperation = false
    @State private var showAllOperationsReport = false
    @State private var showProtocols = false
    @State private var showMonthPicker = false
    
    init(selectedMonth: Date = Date()) {
        self.selectedMonth = selectedMonth
        // Find the earliest operation date to set default month, or use provided month
        _currentSelectedMonth = State(initialValue: selectedMonth)
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
        NavigationStack {
            contentView
        }
        .onAppear {
                        // Always use the selectedMonth parameter from Reports (or default to current month)
            // Don't override with earliest operation date - respect the month selection from Reports
            let calendar = Calendar.current
            let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
            if let monthStart = calendar.date(from: monthComponents) {
                currentSelectedMonth = monthStart
                print("📅 Set currentSelectedMonth from selectedMonth parameter: \(monthStart)")
            }
        }
        .id(selectedMonth) // Force view refresh when selectedMonth changes from Reports
        .onDisappear {
                        }
        .sheet(isPresented: $showAddOperation) {
            NavigationView {
                AddOfficeOperationView()
                    .environmentObject(viewModel)
            }
        }
        .onChange(of: showAddOperation) { isPresented in
            if isPresented {
                                }
        }
        .sheet(isPresented: $showAllOperationsReport) {
            NavigationView {
                AllOfficeOperationsReportView()
                    .environmentObject(viewModel)
                    .navigationTitle("Overall Report".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done".localized) { showAllOperationsReport = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProtocols) {
            ProtocolListView()
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                operationCardsGrid
                
                Divider()
                    .padding(.vertical)
                
                OfficeStatisticsSummaryView()
                    .environmentObject(viewModel)
                    .padding()
                    .allowsHitTesting(false) // ÇÖZÜM: Tıklamayı engelle
                
                generateReportButton
                    .padding(.top, 8) // ÇÖZÜM: Araya boşluk ekle
            }
        }
        .navigationTitle("Office Operations")
        .navigationBarTitleDisplayMode(.inline)
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
            OfficeOperationListView(operationType: opType, selectedMonth: currentSelectedMonth)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showMonthPicker) {
            monthPickerSheet
        }
    }
    
    private var operationCardsGrid: some View {
        let types: [OfficeOperationType] = [.creditCard, .posClosing, .fuelReceipt, .washing, .additionalSales, .banking, .trafficFine]
        
        // Get month range for selected month
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: currentSelectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            ForEach(types, id: \.rawValue) { opType in
                // Filter by month - show operations in selected month
                let monthOperations = viewModel.officeOperations.filter { 
                    $0.type == opType && $0.date >= monthStart && $0.date <= monthEnd
                }
                let count = monthOperations.count
                let totalAmount = monthOperations.reduce(0) { $0 + $1.amount }
                
                Button {
                                        selectedOperation = opType
                    HapticManager.shared.medium()
                } label: {
                    BigOfficeOperationCard(
                        type: opType,
                        count: count,
                        totalAmount: totalAmount,
                        selectedMonth: currentSelectedMonth,
                        viewModel: viewModel
                    )
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
        }
        .padding()
    }
    
    private var generateReportButton: some View {
        Button {
                        showAllOperationsReport = true
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                Text("Generate Overall Report")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back")
            }
            .foregroundColor(.blue)
        }
    }
    
    private var monthPickerButton: some View {
        Button {
            showMonthPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(monthDisplayText)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.primary)
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
                    selection: $currentSelectedMonth,
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
                        showMonthPicker = false
                    }
                }
            }
        }
    }
    
    private var addButton: some View {
        Button {
            showAddOperation = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }
}

struct BigOfficeOperationCard: View {
    let type: OfficeOperationType
    let count: Int
    let totalAmount: Double
    let selectedMonth: Date
    let viewModel: AracViewModel
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
    
    var body: some View {
        VStack(spacing: 8) {
            // Only icon is colored
            Image(systemName: type.icon)
                .font(.system(size: 36))
                .foregroundColor(color)
            
            // Amount in neutral color
            Text(AppCurrency.format(totalAmount))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            // Monthly comparison metrics for all operation types
            monthlyComparisonMetrics
            
            // Type name in secondary color
            Text(type.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Count in secondary color
            Text("\(count) \("entries".localized)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Month in secondary color
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(monthDisplayText)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            
            // Chevron in secondary color
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180) // Fixed height for all cards
        .padding()
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
    
    // MARK: - Monthly Comparison Metrics
    private var monthlyComparisonMetrics: some View {
        let monthlyMetrics = viewModel.calculateOfficeOperationMonthlyComparison(operationType: type, selectedMonth: selectedMonth)
        
        return HStack(spacing: 4) {
            Image(systemName: monthlyMetrics.amountPercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(monthlyMetrics.amountPercent >= 0 ? .green : .red)
            
            Text(formatMetric(monthlyMetrics.amountPercent, monthlyMetrics.amountChange))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(monthlyMetrics.amountPercent >= 0 ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((monthlyMetrics.amountPercent >= 0 ? Color.green : Color.red).opacity(0.1))
        )
    }
    
    private func formatMetric(_ percent: Double, _ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", percent))%"
    }
}

// MARK: - Protocols Card
struct ProtocolsCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon in soft purple
            Image(systemName: "doc.text.fill")
                .font(.system(size: 36))
                .foregroundColor(Color.purple.opacity(0.7))
            
            // Placeholder for protocols
            Text("Protocols".localized)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            // Type name
            Text("View protocols".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180) // Same height as other cards
        .padding()
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
    // MARK: - Office Operation List View
    struct OfficeOperationListView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.colorScheme) var colorScheme
        let operationType: OfficeOperationType
        let selectedMonth: Date
        
        @State private var searchQuery = ""
        @State private var dateFilter: DateFilterType = .weekly
        @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        @State private var customEndDate = Date()
        @State private var showCustomDatePicker = false
        @State private var showStatistics = false
        @State private var showReportGenerator = false
        @State private var editingOperation: OfficeOperation? // ÇÖZÜM: Edit state'i
        
        private var monthDisplayText: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedMonth)
        }
        
        enum DateFilterType: String, CaseIterable {
            case daily = "Daily"
            case weekly = "Weekly"
            case monthly = "Monthly"
            case custom = "Custom"
        }
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            
            // Use selectedMonth for filtering
            let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
            let monthStart = calendar.date(from: monthComponents) ?? Date()
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
            
            switch dateFilter {
            case .daily:
                let start = calendar.startOfDay(for: selectedMonth)
                return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? selectedMonth)
            case .weekly:
                // Week within selected month
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedMonth)) ?? monthStart
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? monthEnd
                return (max(weekStart, monthStart), min(weekEnd, monthEnd))
            case .monthly:
                return (monthStart, monthEnd)
            case .custom:
                return (customStartDate, customEndDate)
            }
        }
        
        var filteredOperations: [OfficeOperation] {
            viewModel.officeOperations.filter { op in
                let matchesType = op.type == operationType
                let matchesDate = op.date >= dateRange.start && op.date <= dateRange.end
                let matchesSearch = searchQuery.isEmpty ||
                    (op.vehiclePlate?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                    op.notes.localizedCaseInsensitiveContains(searchQuery)
                
                return matchesType && matchesDate && matchesSearch
            }.sorted { $0.date > $1.date }
        }
        
        var totalAmount: Double {
            filteredOperations.reduce(0) { $0 + $1.amount }
        }
        
        var plateSuggestions: [String] {
            if searchQuery.isEmpty { return [] }
            return viewModel.araclar
                .map { $0.plakaFormatli }
                .filter { $0.localizedCaseInsensitiveContains(searchQuery) }
                .prefix(5)
                .map { String($0) }
        }
        
        var body: some View {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(monthDisplayText, systemImage: "calendar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(filteredOperations.count) \("records".localized)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search...".localized, text: $searchQuery)
                                .textInputAutocapitalization(.characters)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        
                        if !plateSuggestions.isEmpty && (operationType == .fuelReceipt || operationType == .washing) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(plateSuggestions, id: \.self) { plate in
                                    Button {
                                        searchQuery = plate
                                    } label: {
                                        HStack {
                                            Text(plate)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Image(systemName: "arrow.up.left")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if plate != plateSuggestions.last {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        Picker("Date Filter".localized, selection: $dateFilter) {
                            ForEach(DateFilterType.allCases, id: \.self) { filter in
                                Text(filter.rawValue.localized).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: dateFilter) { newValue in
                            if newValue == .custom {
                                showCustomDatePicker = true
                            }
                        }
                        
                        if dateFilter == .custom {
                            HStack {
                                Text(customStartDate.formatted(date: .abbreviated, time: .omitted))
                                Text("→")
                                Text(customEndDate.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 5)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Total Amount".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(AppCurrency.format(totalAmount))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(getColor())
                        
                        HStack(spacing: 10) {
                            Button {
                                showStatistics = true
                                HapticManager.shared.medium()
                            } label: {
                                Label("Statistics".localized, systemImage: "chart.bar.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OutlineButtonStyle(color: getColor()))
                            
                            Button {
                                showReportGenerator = true
                                HapticManager.shared.medium()
                            } label: {
                                Label("Generate Report".localized, systemImage: "doc.text.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AppTheme.primaryButtonStyle)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 5)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                if filteredOperations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(.gray.opacity(0.55))
                        Text("No Operations Found".localized)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("\(operationType.rawValue) \("List".localized)") {
                            ForEach(filteredOperations) { operation in
                                NavigationLink(destination: OfficeOperationDetailView(operation: operation).environmentObject(viewModel)) {
                                    OfficeOperationRow(operation: operation)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        editingOperation = operation
                                        HapticManager.shared.medium()
                                    } label: {
                                        Label("Edit".localized, systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                    
                                    Button {
                                        deleteOperation(operation)
                                    } label: {
                                        Label("Delete".localized, systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                            .onDelete(perform: deleteOperations)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(operationType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStatistics) {
            NavigationView {
                OfficeOperationStatisticsView(operationType: operationType, operations: filteredOperations)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showReportGenerator) {
            NavigationView {
                OfficeOperationReportGeneratorView(operationType: operationType, operations: filteredOperations)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showCustomDatePicker) {
                NavigationView {
                    Form {
                        DatePicker("Start Date".localized, selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date".localized, selection: $customEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Date Range".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done".localized) { showCustomDatePicker = false }
                        }
                    }
                }
            }
        .sheet(item: $editingOperation) { operation in
            NavigationView {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
        }
    }
        
        func deleteOperations(at offsets: IndexSet) {
            for index in offsets {
                let operation = filteredOperations[index]
                viewModel.officeOperationSil(operation)
            }
        }
        
        func deleteOperation(_ operation: OfficeOperation) {
            viewModel.officeOperationSil(operation)
        }
        
        func getColor() -> Color {
            switch operationType.color {
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "cyan": return .cyan
            default: return colorScheme == .dark ? .white : .gray
            }
        }
    }

    struct OfficeOperationRow: View {
        let operation: OfficeOperation
        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var viewModel: AracViewModel
        
        var body: some View {
            HStack(spacing: 12) {
                // Status icon for fuel receipts
                if operation.type == .fuelReceipt {
                    Button {
                        toggleFuelCompletion()
                    } label: {
                        Image(systemName: operation.isCompleted ? "checkmark.circle.fill" : "circle.fill")
                            .font(.title3)
                            .foregroundColor(operation.isCompleted ? .green : .yellow)
                    }
                    .buttonStyle(AppTheme.ghostButtonStyle)
                    .frame(width: 30)
                } else {
                    Image(systemName: operation.type.icon)
                        .font(.title3)
                        .foregroundColor(getColor())
                        .frame(width: 30)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(AppCurrency.format(operation.amount))
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        if let plate = operation.vehiclePlate {
                            Text("• \(plate)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Show additional info based on operation type
                    if operation.type == .trafficFine, let fineNumber = operation.fineNumber {
                        Text("\("Fine #".localized)\(fineNumber)")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .lineLimit(1)
                    } else if operation.type == .banking, let bankName = operation.bankName {
                        Text(bankName)
                            .font(.caption)
                            .foregroundColor(.indigo.opacity(0.8))
                            .lineLimit(1)
                    } else if operation.type == .additionalSales, let productName = operation.productName {
                        Text(productName)
                            .font(.caption)
                            .foregroundColor(.purple.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 12) {
                        Label(operation.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !operation.photos.isEmpty {
                            Label("\(operation.photos.count)", systemImage: "photo")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        if let posCount = operation.posCount {
                            Label("\(posCount) \("POS".localized)", systemImage: "creditcard")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        // Show completion status for fuel
                        if operation.type == .fuelReceipt {
                            Label(operation.isCompleted ? "Done" : "Pending", systemImage: operation.isCompleted ? "checkmark" : "clock")
                                .font(.caption)
                                .foregroundColor(operation.isCompleted ? .green : .yellow)
                        }
                        
                        // Show payment status for traffic fines
                        if operation.type == .trafficFine, let paymentStatus = operation.paymentStatus {
                            Label(paymentStatus, systemImage: paymentStatus.lowercased().contains("paid") ? "checkmark.circle" : "clock")
                                .font(.caption)
                                .foregroundColor(paymentStatus.lowercased().contains("paid") ? .green : 
                                               paymentStatus.lowercased().contains("pending") ? .orange : .red)
                        }
                        
                        // Show transaction type for banking
                        if operation.type == .banking, let transactionType = operation.transactionType {
                            Label(transactionType, systemImage: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundColor(.indigo)
                        }
                        
                        // Show customer name for additional sales
                        if operation.type == .additionalSales, let customerName = operation.customerName {
                            Label(customerName, systemImage: "person")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                    
                    if !operation.notes.isEmpty {
                        Text(operation.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        
        private func toggleFuelCompletion() {
            var updatedOperation = operation
            updatedOperation.isCompleted.toggle()
            
            HapticManager.shared.medium()
            viewModel.officeOperationGuncelle(updatedOperation) { success in
                if success {
                    HapticManager.shared.success()
                    ToastManager.shared.show(updatedOperation.isCompleted ? "✓ Marked as done" : "Pending", type: .success)
                } else {
                    HapticManager.shared.error()
                }
            }
        }
        
        func getColor() -> Color {
            switch operation.type.color {
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "cyan": return .cyan
            default: return colorScheme == .dark ? .white : .gray
            }
        }
    }

    // MARK: - Add Office Operation View
    struct AddOfficeOperationView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        
        @State private var selectedType: OfficeOperationType = .creditCard
        @State private var amount = ""
        @State private var vehiclePlate = ""
        @State private var pos1Amount = ""
        @State private var pos2Amount = ""
        @State private var notes = ""
        @State private var selectedImages: [UIImage] = []
        @State private var showImagePicker = false
        @State private var showCamera = false
        @State private var capturedImage: UIImage?
        @State private var uploadedPhotoURLs: [String] = []
        @State private var isUploading = false
        @State private var showCompletionOverlay = false
        @State private var completionSucceeded = false
        @State private var pulseAnimation = false
        
        // MARK: - Traffic Fine Fields
        @State private var fineNumber = ""
        @State private var fineType = ""
        @State private var paymentStatus = "Pending"
        @State private var customerName = ""
        @State private var resCode = ""
        
        // MARK: - Banking Fields
        @State private var transactionNumber = ""
        @State private var bankName = ""
        @State private var accountNumber = ""
        @State private var transactionType = ""
        @State private var referenceNumber = ""
        
        // MARK: - Additional Sales Fields
        @State private var productName = ""
        @State private var quantity = ""
        @State private var unitPrice = ""
        @State private var invoiceNumber = ""
        
        @State private var showTypePicker = false
        
        var plateSuggestions: [String] {
            if vehiclePlate.isEmpty { return [] }
            return viewModel.araclar
                .map { $0.plakaFormatli }
                .filter { $0.localizedCaseInsensitiveContains(vehiclePlate) }
                .prefix(5)
                .map { String($0) }
        }
        
        var body: some View {
            Form {
Section("Operation Type*".localized) {
            Button {
                showTypePicker = true
            } label: {
                        HStack {
                            Image(systemName: selectedType.icon)
                                .foregroundColor(getTypeColor())
                            Text(selectedType.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                // MARK: - Amount Section (for all types except POS)
                if selectedType != .posClosing {
Section("Amount (\(AppCurrency.code))*".localized) {
            HStack {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(.green)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                Text(AppCurrency.code)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Traffic Fine Specific Fields
                if selectedType == .trafficFine {
                    Section("Traffic Fine Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "car.fill")
                                    .foregroundColor(.red)
TextField("Plate*".localized, text: $vehiclePlate)
                            .textInputAutocapitalization(.characters)
                    }
                    
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.red)
                        TextField("Customer Name*".localized, text: $customerName)
                    }
                    
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.secondary)
                        TextField("Res code (e.g., Res-12454)".localized, text: $resCode)
                    }
                    
                    Picker("Status".localized, selection: $paymentStatus) {
                        Text("Pending".localized).tag("Pending")
                        Text("Paid".localized).tag("Paid")
                        Text("Overdue".localized).tag("Overdue")
                    }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                // MARK: - Banking Specific Fields
                if selectedType == .banking {
                    Section("Banking Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "number")
                                    .foregroundColor(.secondary)
                                TextField("Res code (e.g., Res-12454)", text: $resCode)
                            }
                        }
                    }
                }
                
                // MARK: - Additional Sales Specific Fields
                if selectedType == .additionalSales {
                    // Additional Sales doesn't have extra required fields in web form
                }
                
                // MARK: - Vehicle Section (for Fuel Receipt and Washing)
                if selectedType == .fuelReceipt || selectedType == .washing {
                    Section("Vehicle Information".localized) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "car.fill")
                                    .foregroundColor(.blue)
                                TextField("Vehicle Plate".localized, text: $vehiclePlate)
                                    .textInputAutocapitalization(.characters)
                            }
                            
                            if !plateSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(plateSuggestions, id: \.self) { plate in
                                        if let vehicle = viewModel.araclar.first(where: { $0.plakaFormatli == plate }) {
                                            Button {
                                                vehiclePlate = plate
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(plate)
                                                            .font(.subheadline)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.primary)
                                                        Text("\(vehicle.marka) \(vehicle.model)")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                            }
                                            Divider()
                                        }
                                    }
                                }
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            
                            if !vehiclePlate.isEmpty, let vehicle = viewModel.araclar.first(where: { $0.plakaFormatli == vehiclePlate }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Selected Vehicle".localized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(vehicle.marka) \(vehicle.model)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                if selectedType == .posClosing {
                    Section("POS Information (2 Terminals)".localized) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("POS 1 Amount".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            HStack {
                                Image(systemName: "1.circle.fill")
                                    .foregroundColor(.green)
                                TextField("0.00", text: $pos1Amount)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Text(AppCurrency.code)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("POS 2 Amount".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            HStack {
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(.blue)
                                TextField("0.00", text: $pos2Amount)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Text(AppCurrency.code)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Photos".localized) {
                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(selectedImages.indices, id: \.self) { index in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        
                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button(action: {
                            guard !showCamera else { return }
                            showImagePicker = true
                        }) {
                            HStack {
Image(systemName: "photo.on.rectangle")
                        Text("Choose from Gallery".localized)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showCamera)
                
                Button(action: {
                    guard !showImagePicker else { return }
                    showCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                        Text("Take Photo".localized)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(showImagePicker)
                    }
                }
                
Section("Notes".localized) {
            TextEditor(text: $notes)
                .frame(height: 100)
                .overlay(
                    Group {
                        if notes.isEmpty {
                            Text("Additional notes...".localized)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                Section {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            completionSucceeded = false
                            pulseAnimation = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCompletionOverlay = true
                            }
                            saveOperation()
                        } label: {
                            if isUploading {
                                HStack {
                                    ProgressView()
                                    Text("Uploading...")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Add Operation")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUploading || !isValid)
                    }
                }
            }
            .blur(radius: showCompletionOverlay ? 8 : 0)
            .allowsHitTesting(!showCompletionOverlay)
            .overlay {
                if showCompletionOverlay {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale))
                }
            }
.navigationTitle("Add Office Operation".localized)
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showTypePicker) {
                OperationTypePickerView(selectedType: $selectedType)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $selectedImages)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if let newImage = capturedImage {
                    selectedImages.append(newImage)
                    capturedImage = nil
                }
            }) {
                OfficeCameraView(capturedImage: $capturedImage)
            }
            .onChange(of: selectedType) { newType in
                guard newType == .washing else { return }
                let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
                let zeroLikeValues: Set<String> = ["", "0", "0.0", "0.00", "0,0", "0,00"]
                if zeroLikeValues.contains(trimmed) {
                    amount = "14"
                }
            }
            .onChange(of: showCompletionOverlay) { isVisible in
                if isVisible {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                } else {
                    pulseAnimation = false
                }
            }
        }
        
        private var completionOverlay: some View {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    if completionSucceeded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(.green)
                        Text("Done".localized)
                            .font(.headline)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                        Text("Uploading...".localized)
                            .font(.headline)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .background(Color.black.opacity(0.75))
                .foregroundColor(.white)
                .cornerRadius(18)
                .shadow(radius: 12)
            }
        }
        
        var isValid: Bool {
            // Amount validation
            if selectedType == .posClosing {
                guard let pos1 = Double(pos1Amount), pos1 >= 0,
                      let pos2 = Double(pos2Amount), pos2 >= 0 else { return false }
                return (pos1 + pos2) > 0
            } else {
                guard let amountValue = Double(amount), amountValue > 0 else { return false }
            }
            
            // Traffic Fine specific validations
            if selectedType == .trafficFine {
                if vehiclePlate.isEmpty || customerName.isEmpty {
                    return false
                }
            }
            
            // Fuel Receipt and Washing require vehicle plate
            if (selectedType == .fuelReceipt || selectedType == .washing) && vehiclePlate.isEmpty {
                return false
            }
            
            return true
        }
        
        private func getTypeColor() -> Color {
            switch selectedType.color {
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
        
        func saveOperation() {
            isUploading = true
            uploadedPhotoURLs = []
            
            print("📸 Starting photo upload - Selected images count: \(selectedImages.count)")
            
            // If no images selected, proceed without upload
            guard !selectedImages.isEmpty else {
                print("⚠️ No images selected, proceeding without photos")
                proceedWithSave(photos: [])
                return
            }
            
            let group = DispatchGroup()
            var uploadErrors: [Error] = []
            var uploadedURLs: [String] = []
            let lock = NSLock()
            
            for (index, image) in selectedImages.enumerated() {
                group.enter()
                let path = "office_operations/\(UUID().uuidString).jpg"
                print("📤 Uploading photo \(index + 1)/\(selectedImages.count) to path: \(path)")
                
                CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                            DispatchQueue.main.async {
                        if let url = url {
                            lock.lock()
                            uploadedURLs.append(url)
                            lock.unlock()
                            print("✅ Photo \(index + 1) uploaded successfully: \(url)")
                        } else if let error = error {
                            lock.lock()
                            uploadErrors.append(error)
                            lock.unlock()
                            print("❌ Photo \(index + 1) upload error: \(error.localizedDescription)")
                    }
                    group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                lock.lock()
                let finalURLs = uploadedURLs
                let finalErrors = uploadErrors
                lock.unlock()
                
                print("📊 Upload complete - Success: \(finalURLs.count), Failed: \(finalErrors.count)")
                
                    // Check if there were upload errors
                if !finalErrors.isEmpty {
                    let failedCount = finalErrors.count
                        let totalCount = selectedImages.count
                        
                        if failedCount == totalCount {
                            // All photos failed
                            self.isUploading = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.showCompletionOverlay = false
                            }
                            ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                        print("❌ All photos failed to upload")
                            return
                        } else {
                            // Some photos failed - continue with available photos
                            ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Operation will be saved with available photos.".localized, failedCount, totalCount))
                        print("⚠️ Some photos failed, continuing with \(finalURLs.count) photos")
                        }
                }
                
                self.proceedWithSave(photos: finalURLs)
                    }
                }
        
        private func proceedWithSave(photos: [String]) {
            print("💾 Saving operation with \(photos.count) photos")
                
                let finalAmount: Double
                var posAmounts: [Double]?
                
                if selectedType == .posClosing {
                    let amounts = [Double(pos1Amount) ?? 0, Double(pos2Amount) ?? 0]
                    posAmounts = amounts
                    finalAmount = amounts.reduce(0, +)
                } else {
                    finalAmount = Double(amount) ?? 0
                }
                
                // Create operation with type-specific fields
                let currentUserId = Auth.auth().currentUser?.uid
                var operation = OfficeOperation(
                    type: selectedType,
                    date: Date(),
                    amount: finalAmount,
                photos: photos,
                    vehiclePlate: (selectedType == .fuelReceipt || selectedType == .washing || selectedType == .trafficFine) ? vehiclePlate : nil,
                    posCount: selectedType == .posClosing ? 2 : nil,
                    posAmounts: posAmounts,
                    notes: notes,
                    createdBy: currentUserId
                )
                
                // Set Traffic Fine specific fields
                if selectedType == .trafficFine {
                    operation.fineNumber = resCode.isEmpty ? nil : resCode
                    operation.paymentStatus = paymentStatus
                    operation.customerName = customerName.isEmpty ? nil : customerName
                    // Note: fineType is not in web form, so we'll leave it nil
                }
                
                // Set Banking specific fields
                if selectedType == .banking {
                    operation.referenceNumber = resCode.isEmpty ? nil : resCode
                    // Other banking fields can be added later if needed
                }
                
                // Additional Sales doesn't have extra fields in web form currently
                
            print("✅ Saving operation: type=\(selectedType.rawValue), amount=\(finalAmount), photos=\(photos.count)")
                viewModel.officeOperationEkle(operation)
                isUploading = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    completionSucceeded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = false
                    }
                    dismiss()
                }
        }
    }

    // MARK: - Operation Type Picker View
    struct OperationTypePickerView: View {
        @Environment(\.dismiss) var dismiss
        @Binding var selectedType: OfficeOperationType
        
        var body: some View {
            NavigationView {
                List {
                    ForEach(OfficeOperationType.allCases, id: \.self) { type in
                        Button {
                            selectedType = type
                            dismiss()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: type.icon)
                                    .font(.title2)
                                    .foregroundColor(getColor(for: type))
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                                
                                if selectedType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle("Select Operation Type")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        
        private func getColor(for type: OfficeOperationType) -> Color {
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
    }
    
    // MARK: - Office Operation Detail View
    struct OfficeOperationDetailView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        @Environment(\.colorScheme) var colorScheme
        let operation: OfficeOperation
        @State private var showEditSheet = false
        @State private var showPhotoGallery = false
        @State private var selectedPhotoIndex: Int = 0
        @State private var showDeleteAlert = false
        
        var body: some View {
            List {
                Section("Details") {
                    HStack {
                        Label("Type", systemImage: operation.type.icon)
                        Spacer()
                        Text(operation.type.rawValue)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Amount", systemImage: "eurosign.circle")
                        Spacer()
                        Text(AppCurrency.format(operation.amount))
                            .font(.headline)
                    }
                    
                    HStack {
                        Label("Date", systemImage: "calendar")
                        Spacer()
                        Text(operation.date.formatted(date: .long, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    
                    if let plate = operation.vehiclePlate {
                        HStack {
                            Label("Vehicle", systemImage: "car")
                            Spacer()
                            Text(plate)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let posCount = operation.posCount {
                        HStack {
                            Label("POS Count", systemImage: "creditcard")
                            Spacer()
                            Text("\(posCount)")
                                .foregroundColor(.secondary)
                        }
                        
                        if let amounts = operation.posAmounts {
                            ForEach(amounts.indices, id: \.self) { index in
                                HStack {
                                    Text("POS \(index + 1)")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(AppCurrency.format(amounts[index]))
                                        .fontWeight(.semibold)
                                }
                                .padding(.leading)
                            }
                        }
                    }
                }
                
                // MARK: - Traffic Fine Additional Fields
                if operation.type == .trafficFine {
                    if let fineNumber = operation.fineNumber {
                        HStack {
                            Label("Fine Number", systemImage: "number")
                            Spacer()
                            Text(fineNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let fineType = operation.fineType {
                        HStack {
                            Label("Fine Type", systemImage: "exclamationmark.triangle")
                            Spacer()
                            Text(fineType)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let paymentStatus = operation.paymentStatus {
                        HStack {
                            Label("Payment Status", systemImage: "creditcard")
                            Spacer()
                            Text(paymentStatus)
                                .foregroundColor(paymentStatus.lowercased().contains("paid") ? .green : 
                                               paymentStatus.lowercased().contains("pending") ? .orange : .red)
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                // MARK: - Banking Additional Fields
                if operation.type == .banking {
                    if let transactionNumber = operation.transactionNumber {
                        HStack {
                            Label("Transaction Number", systemImage: "number")
                            Spacer()
                            Text(transactionNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let bankName = operation.bankName {
                        HStack {
                            Label("Bank Name", systemImage: "building.columns")
                            Spacer()
                            Text(bankName)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let accountNumber = operation.accountNumber {
                        HStack {
                            Label("Account Number".localized, systemImage: "creditcard")
                            Spacer()
                            Text(accountNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let transactionType = operation.transactionType {
                        HStack {
                            Label("Transaction Type".localized, systemImage: "arrow.left.arrow.right")
                            Spacer()
                            Text(transactionType)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let referenceNumber = operation.referenceNumber {
                        HStack {
                            Label("Reference Number".localized, systemImage: "doc.text")
                            Spacer()
                            Text(referenceNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Additional Sales Additional Fields
                if operation.type == .additionalSales {
                    if let productName = operation.productName {
                        HStack {
                            Label("Product/Service".localized, systemImage: "cart")
                            Spacer()
                            Text(productName)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let quantity = operation.quantity {
                        HStack {
                            Label("Quantity".localized, systemImage: "number")
                            Spacer()
                            Text(String(format: "%.2f", quantity))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let unitPrice = operation.unitPrice {
                        HStack {
                            Label("Unit Price".localized, systemImage: "tag")
                            Spacer()
                            Text(AppCurrency.format(unitPrice))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let customerName = operation.customerName {
                        HStack {
                            Label("Customer".localized, systemImage: "person")
                            Spacer()
                            Text(customerName)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let invoiceNumber = operation.invoiceNumber {
                        HStack {
                            Label("Invoice Number".localized, systemImage: "doc.text")
                            Spacer()
                            Text(invoiceNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if !operation.notes.isEmpty {
                    Section("Notes".localized) {
                        Text(operation.notes)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !operation.photos.isEmpty {
                    Section("Photos".localized) {
                        ForEach(Array(operation.photos.enumerated()), id: \.offset) { index, photoURL in
                            Button {
                                selectedPhotoIndex = index
                                showPhotoGallery = true
                            } label: {
                                AsyncImageView(urlString: photoURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete Operation".localized, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Operation Details".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditSheet = true
                        HapticManager.shared.medium()
                    } label: {
                        Label("Edit".localized, systemImage: "pencil.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
            .fullScreenCover(isPresented: $showPhotoGallery) {
                PhotoGalleryView(photoURLs: operation.photos, initialIndex: selectedPhotoIndex)
            }
            .onAppear {
                print("🔍 OfficeOperationDetailView appeared for operation: \(operation.id)")
            }
            .alert("Delete Operation".localized, isPresented: $showDeleteAlert) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Delete".localized, role: .destructive) {
                    viewModel.officeOperationSil(operation)
                    HapticManager.shared.success()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this operation? This action cannot be undone.".localized)
            }
        }
    }

    // MARK: - Edit Office Operation View
    struct EditOfficeOperationView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        let operation: OfficeOperation
        
        @State private var amount: String
        @State private var vehiclePlate: String
        @State private var notes: String
        @State private var posCount: String
        @State private var isSaving = false
        
        init(operation: OfficeOperation) {
            self.operation = operation
            _amount = State(initialValue: String(format: "%.2f", operation.amount))
            _vehiclePlate = State(initialValue: operation.vehiclePlate ?? "")
            _notes = State(initialValue: operation.notes)
            _posCount = State(initialValue: operation.posCount.map(String.init) ?? "")
        }
        
        var body: some View {
            Form {
                    Section("Operation Details".localized) {
                        HStack {
                            Label("Type".localized, systemImage: operation.type.icon)
                            Spacer()
                            Text(operation.type.rawValue)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Date".localized, systemImage: "calendar")
                            Spacer()
                            Text(operation.date.formatted(date: .long, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("Amount".localized) {
                        HStack {
                            Text("Amount (\(AppCurrency.code))".localized)
                            Spacer()
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    Section("Vehicle".localized) {
                        TextField("Vehicle Plate (Optional)".localized, text: $vehiclePlate)
                    }
                    
                    Section("POS Count".localized) {
                        TextField("POS Count (Optional)".localized, text: $posCount)
                            .keyboardType(.numberPad)
                    }
                    
                    Section("Notes".localized) {
                        TextField("Notes (Optional)".localized, text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Edit Operation".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel".localized) {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save".localized) {
                            saveOperation()
                        }
                        .disabled(isSaving)
                    }
                }
        }
        
        private func saveOperation() {
            guard let amountValue = Double(amount) else { return }
            
            isSaving = true
            
            var updatedOperation = operation
            updatedOperation.amount = amountValue
            updatedOperation.vehiclePlate = vehiclePlate.isEmpty ? nil : vehiclePlate
            updatedOperation.notes = notes
            updatedOperation.posCount = posCount.isEmpty ? nil : Int(posCount)
            
            viewModel.officeOperationGuncelle(updatedOperation) { success in
                isSaving = false
                if success {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Office Operation Report Generator View
    struct OfficeOperationReportGeneratorView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        let operationType: OfficeOperationType
        let operations: [OfficeOperation]
        
        @State private var reportPeriod: ReportPeriod = .daily
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
            
            return operations.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }
        }
        
        var totalAmount: Double {
            filteredOperations.reduce(0) { $0 + $1.amount }
        }
        
        var body: some View {
            List {
                Section("Report Period".localized) {
                    Picker("Period".localized, selection: $reportPeriod) {
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
                
                Section("Report Summary".localized) {
                    HStack {
                        Text("Period".localized)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(reportPeriod.rawValue)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Total Operations".localized)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(filteredOperations.count)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Total Amount".localized)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AppCurrency.format(totalAmount))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    
                    if operationType == .posClosing {
                        let pos1Total = filteredOperations.compactMap { $0.posAmounts?.first }.reduce(0, +)
                        let pos2Total = filteredOperations.compactMap { $0.posAmounts?.last }.reduce(0, +)
                        
                        HStack {
                            Text("POS 1 Total".localized)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppCurrency.format(pos1Total))
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("POS 2 Total".localized)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppCurrency.format(pos2Total))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
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
            .navigationTitle("Generate Report".localized)
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
        
        func generatePDFReport() {
            isGenerating = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let pdfData = createPDFData()
                
                // Use documents directory instead of temporary for better file access
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = documentsPath.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).pdf")
                
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
                let fileURL = documentsPath.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).csv")
                
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
                kCGPDFContextTitle: "\(operationType.rawValue) Report",
                kCGPDFContextAuthor: "Green Motion AG"
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
                
                // Company Name - Bold Helvetica
                let companyName = "GREEN MOTION AG"
                let companyFont = SwissPDFHelper.helveticaBold(size: 18)
                companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: companyFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 25
                
                // Subtitle - Thin Helvetica
                let subtitle = "ZÜRICH • SWITZERLAND"
                let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
                subtitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: subtitleFont, .foregroundColor: SwissPDFHelper.mediumGray])
                yPosition += 40
                
                // Horizontal line separator
                SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
                yPosition += 30
                
                // Title
                let title = "\(operationType.rawValue) Report"
                let titleFont = SwissPDFHelper.helveticaBold(size: 24)
                title.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: titleFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 35
                
                // Period
                let bodyFont = SwissPDFHelper.helvetica(size: 10)
                let labelFont = SwissPDFHelper.helveticaBold(size: 10)
                "Period:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                "\(reportPeriod.rawValue)".draw(at: CGPoint(x: 120, y: yPosition), withAttributes: [.font: bodyFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 25
                
                // Summary
                "Total Operations:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                "\(filteredOperations.count)".draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 14), .foregroundColor: SwissPDFHelper.black])
                yPosition += 20
                
                "Total Amount:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                "\(AppCurrency.amountWithCode(totalAmount))".draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 14), .foregroundColor: SwissPDFHelper.black])
                yPosition += 30
                
                // Horizontal line separator
                SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
                yPosition += 30
                
                // Operations list
                for (index, operation) in filteredOperations.prefix(30).enumerated() {
                    if yPosition > 750 { break }
                    
                    let dateStr = operation.date.formatted(date: .abbreviated, time: .omitted)
                    let amountStr = AppCurrency.amountWithCode(operation.amount)
                    let line = "\(dateStr) - \(amountStr)"
                    line.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: bodyFont, .foregroundColor: SwissPDFHelper.black])
                    
                    // Thin separator line
                    if index < filteredOperations.prefix(30).count - 1 {
                        SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition + 12), to: CGPoint(x: pageRect.width - 60, y: yPosition + 12), width: 0.25)
                    }
                    
                    yPosition += 18
                }
                
                // Footer
                let footerY = pageRect.height - 30
                SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 20), to: CGPoint(x: pageRect.width - 60, y: footerY - 20), width: 0.25)
                
                let footerFont = SwissPDFHelper.helveticaThin(size: 7)
                "Green Motion AG • Zürich, Switzerland".draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
                "1".draw(at: CGPoint(x: pageRect.width - 80, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
            }
        }
        
        func createCSVData() -> Data {
            var csv = "Date,Amount,Type,Notes\n"
            
            for operation in filteredOperations {
                let dateStr = operation.date.formatted(date: .numeric, time: .omitted)
                let amountStr = String(format: "%.2f", operation.amount)
                let notes = operation.notes.replacingOccurrences(of: ",", with: ";")
                csv += "\(dateStr),\(amountStr),\(operationType.rawValue),\(notes)\n"
            }
            
            return csv.data(using: .utf8) ?? Data()
        }
    }

    // MARK: - Office Operation Statistics View
    struct OfficeOperationStatisticsView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        let operationType: OfficeOperationType
        let operations: [OfficeOperation]
        
        var totalAmount: Double {
            operations.reduce(0) { $0 + $1.amount }
        }
        
        var averageAmount: Double {
            operations.isEmpty ? 0 : totalAmount / Double(operations.count)
        }
        
        var groupedByDate: [String: Double] {
            var result: [String: Double] = [:]
            for op in operations {
                let key = op.date.formatted(date: .abbreviated, time: .omitted)
                result[key, default: 0] += op.amount
            }
            return result
        }
        
        var body: some View {
            List {
                Section("Summary".localized) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Amount".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(AppCurrency.format(totalAmount))
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Average Amount".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(AppCurrency.format(averageAmount))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Entries".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(operations.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                
                Section("Daily Breakdown".localized) {
                    ForEach(groupedByDate.sorted(by: { $0.key > $1.key }), id: \.key) { date, amount in
                        HStack {
                            Text(date)
                                .font(.subheadline)
                            Spacer()
                            Text(AppCurrency.format(amount))
                                .font(.headline)
                        }
                    }
                }
                
                if operationType == .posClosing {
                    Section("POS Statistics".localized) {
                        let totalPOS = operations.compactMap { $0.posCount }.reduce(0, +)
                        HStack {
                            Text("Total POS Processed".localized)
                            Spacer()
                            Text("\(totalPOS)")
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                if operationType == .fuelReceipt || operationType == .washing {
                    Section("Vehicle Breakdown".localized) {
                        let vehicleGroups = Dictionary(grouping: operations.compactMap { op -> (String, Double)? in
                            guard let plate = op.vehiclePlate else { return nil }
                            return (plate, op.amount)
                        }, by: { $0.0 })
                        
                        ForEach(vehicleGroups.keys.sorted(), id: \.self) { plate in
                            let total = vehicleGroups[plate]?.reduce(0) { $0 + $1.1 } ?? 0
                            HStack {
                                Text(plate)
                                    .font(.subheadline)
                                Spacer()
                                Text(AppCurrency.format(total))
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Statistics".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - All Office Operations Report View
struct AllOfficeOperationsReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
                            Text(type.rawValue)
                        }.tag(type as OfficeOperationType?)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedType = selectedOperationType {
                    HStack {
                        Image(systemName: selectedType.icon)
                            .foregroundColor(getColor(for: selectedType))
                        Text("\("Filtering".localized): \(selectedType.rawValue)")
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
                        Text(AppCurrency.format(totalAmount))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    Spacer()
                }
            }
            
            if !operationsByType.isEmpty {
                Section("Breakdown by Type".localized) {
                    ForEach(operationsByType, id: \.type) { item in
                        HStack {
                            Image(systemName: item.type.icon)
                                .foregroundColor(getColor(for: item.type))
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.type.rawValue)
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
            let fileURL = documentsPath.appendingPathComponent("OverallOfficeReport_\(Date().timeIntervalSince1970).pdf")
            
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
            kCGPDFContextTitle: selectedOperationType?.rawValue ?? "Office Operations Report",
            kCGPDFContextAuthor: "Green Motion AG",
            kCGPDFContextCreator: "Green Motion Fleet Management"
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
            
            // Company Name - Bold Helvetica
            let companyName = "GREEN MOTION AG"
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            let companyAttrs: [NSAttributedString.Key: Any] = [
                .font: companyFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: companyAttrs)
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let subtitle = "ZÜRICH • SWITZERLAND"
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
            
            // Report Date
            let reportDateLabel = "Report Generated:"
            let reportDateValue = dateFormatter.string(from: Date())
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
                let typeValue = selectedType.rawValue
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
            yPosition += 20
            
            "Total Amount:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(AppCurrency.amountWithCode(totalAmount))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            
            yPosition += 30
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - BREAKDOWN SECTION (Swiss Design: Grid system, thin lines)
            if !operationsByType.isEmpty {
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
                    item.type.rawValue.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
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
            let footerText = "Green Motion AG • Zürich, Switzerland"
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
        csv += "GREEN MOTION AG - OFFICE OPERATIONS REPORT\n"
        csv += "Zürich Switzerland\n"
        csv += "\n"
        csv += "Report Generated:,\(Date().formatted(date: .long, time: .shortened))\n"
        csv += "Period:,\(reportPeriod.rawValue)\n"
        if let selectedType = selectedOperationType {
            csv += "Operation Type:,\(selectedType.rawValue)\n"
        } else {
            csv += "Operation Type:,All Operations\n"
        }
        csv += "\n"
        
        // Summary Section
        csv += "SUMMARY\n"
        csv += "Total Operations:,\(filteredOperations.count)\n"
        csv += "Total Amount:,\(AppCurrency.amountWithCode(totalAmount))\n"
        csv += "\n"
        
        // Breakdown Section
        if !operationsByType.isEmpty {
            csv += "BREAKDOWN BY TYPE\n"
            csv += "Type,Entries,Amount (\(AppCurrency.code))\n"
            for item in operationsByType {
                csv += "\(item.type.rawValue),\(item.count),\(String(format: "%.2f", item.amount))\n"
            }
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
            
            csv += "\(dateStr),\(timeStr),\(operation.type.rawValue),\(amountStr),\(plate),\(posCount),\(notes)\n"
        }
        
        csv += "\n"
        csv += "End of Report\n"
        csv += "Generated by Green Motion Fleet Management System\n"
        
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
