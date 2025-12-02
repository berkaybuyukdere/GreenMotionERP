import SwiftUI
import Charts
import FirebaseFirestore

struct RaporView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var selectedReportCard: ReportCardType?
    
    // Monthly period tracking - defaults to current month
    @State private var selectedMonth: Date = Date()
    @State private var showMonthPicker = false
    @State private var shuttleEntriesCount: Int = 0
    
    enum ReportCardType: String, CaseIterable, Identifiable {
        case damageReports = "Damage Reports"
        case returnReports = "Return Reports"
        case exitReports = "Check Out Reports"
        case officeOperations = "Office Operations"
        case shuttle = "Shuttle"
        case customerReturns = "Customer Returns"
        case statistics = "Statistics"
        case service = "Service"
        case timetable = "Timetable"
        case vacationTimes = "Vacation Times"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .damageReports: return "exclamationmark.triangle.fill"
            case .returnReports: return "arrow.uturn.backward.circle.fill"
            case .exitReports: return "arrow.right.circle.fill"
            case .shuttle: return "bus.fill"
            case .officeOperations: return "briefcase.fill"
            case .customerReturns: return "arrow.uturn.backward.circle.fill"
            case .statistics: return "chart.bar.fill"
            case .service: return "wrench.and.screwdriver.fill"
            case .timetable: return "calendar.badge.clock"
            case .vacationTimes: return "calendar.badge.clock"
            }
        }
        
        var color: Color {
            switch self {
            case .damageReports: return .orange
            case .returnReports: return .purple
            case .exitReports: return .blue
            case .shuttle: return .cyan
            case .officeOperations: return .blue
            case .customerReturns: return .indigo
            case .statistics: return .green
            case .service: return .red
            case .timetable: return .teal
            case .vacationTimes: return .mint
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                                Color.clear
                    .onAppear {
                        }
                    .onDisappear {
                        }
                    .frame(height: 0)
                // Fixed header with title and month selector
                fixedHeader
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Report Cards
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            ForEach(ReportCardType.allCases) { cardType in
                                let currentCount = getCount(for: cardType)
                                let previousCount = getPreviousMonthCount(for: cardType)
                                let kpiMetric = cardType == .damageReports ? calculateKPIMetric(current: currentCount, previous: previousCount) : nil
                                
                                BigReportCard(
                                    title: cardType.rawValue,
                                    icon: cardType.icon,
                                    color: cardType.color,
                                    count: currentCount,
                                    kpiMetric: kpiMetric
                                )
                                .onTapGesture {
                                                                        HapticManager.shared.medium()
                                    selectedReportCard = cardType
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedMonth)
                        
                        // Charts Section
                        if !viewModel.araclar.isEmpty || !viewModel.officeOperations.isEmpty {
                            ReportsOverviewChartsView()
                                .environmentObject(viewModel)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selectedReportCard) { cardType in
                NavigationView {
                    reportDetailView(for: cardType, selectedMonth: selectedMonth)
                        .id(selectedMonth) // Force view refresh when month changes
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                monthPickerView
            }
            .onAppear {
                loadShuttleEntriesCount()
            }
            .onChange(of: selectedMonth) { _ in
                loadShuttleEntriesCount()
            }
        }
    }
    
    // MARK: - Load Shuttle Entries Count
    private func loadShuttleEntriesCount() {
        let dateRange = getMonthDateRange(for: selectedMonth)
        
        Firestore.firestore()
            .collection("shuttleEntries")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: dateRange.start))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: dateRange.end))
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error loading shuttle entries count: \(error.localizedDescription)")
                        self.shuttleEntriesCount = 0
                        return
                    }
                    
                    self.shuttleEntriesCount = snapshot?.documents.count ?? 0
                    print("✅ Shuttle entries count loaded: \(self.shuttleEntriesCount) for month \(self.selectedMonth)")
                }
            }
    }
    
    // MARK: - Fixed Header (Title + Month Selector)
    private var fixedHeader: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Reports")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background(Color(.systemBackground))
            
            // Month selector header
            monthSelectorHeader
                .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Month Selector Header
    private var monthSelectorHeader: some View {
        HStack(spacing: 16) {
            // Previous Month Button
            Button {
                                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Month Display Card
            Button {
                                HapticManager.shared.medium()
                showMonthPicker = true
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text(monthDisplayText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    if !isCurrentMonth {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text("Past Month")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Current")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: isCurrentMonth ? [.green.opacity(0.3), .blue.opacity(0.3)] : [.orange.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Next Month Button
            Button {
                                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        isCurrentMonth ?
                        LinearGradient(
                            colors: [.gray.opacity(0.3), .gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGray6).opacity(0.5),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    
    // MARK: - Month Picker View
    private var monthPickerView: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                Form {
                    Section {
                        DatePicker(
                            "Select Month",
                            selection: $selectedMonth,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .accentColor(.blue)
                    } header: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Choose a month to view reports")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Section {
                        HStack {
                            Spacer()
                            Button {
                                HapticManager.shared.medium()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedMonth = Date()
                                    showMonthPicker = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Reset to Current Month")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    
                    // Month Info Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Month Information")
                                    .font(.headline)
                            }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Selected Month")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(monthDisplayText)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                if isCurrentMonth {
                                    Label("Current", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if !isCurrentMonth {
                                let daysDiff = Calendar.current.dateComponents([.day], from: selectedMonth, to: Date()).day ?? 0
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.orange)
                                    Text("\(daysDiff) days ago")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Details")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.light()
                        showMonthPicker = false
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }
    
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }
    
    
    // MARK: - Helper Functions
    private func selectPreviousMonth() {
        if let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = previousMonth
        }
    }
    
    private func selectNextMonth() {
        if let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
            // Don't allow selecting future months
            let calendar = Calendar.current
            let now = Date()
            if calendar.compare(nextMonth, to: now, toGranularity: .month) != .orderedDescending {
                selectedMonth = nextMonth
            }
        }
    }
    
    // MARK: - Date Range Helper
    private func getMonthDateRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        
        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            // Fallback to current month if calculation fails
            let now = Date()
            let fallbackComponents = calendar.dateComponents([.year, .month], from: now)
            let fallbackStart = calendar.date(from: fallbackComponents) ?? now
            let fallbackEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: fallbackStart) ?? now
            return (fallbackStart, fallbackEnd)
        }
        
        // End of month at 23:59:59
        let endOfMonthEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfMonth) ?? endOfMonth
        
        return (startOfMonth, endOfMonthEnd)
    }
    
    @ViewBuilder
    func reportDetailView(for cardType: ReportCardType, selectedMonth: Date) -> some View {
        switch cardType {
        case .damageReports:
            DamageReportsView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .returnReports:
            ReturnReportsView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .exitReports:
            ExitReportsView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .shuttle:
            DailyShuttleReportView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .officeOperations:
            OfficeOperationsMainView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .customerReturns:
            OfficeReturnMainView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .statistics:
            ComprehensiveStatisticsView()
                .environmentObject(viewModel)
        case .service:
            ServisView()
        case .timetable:
            TimetableView()
                .environmentObject(viewModel)
        case .vacationTimes:
            VacationTimesView()
                .environmentObject(viewModel)
        }
    }
    
    func getCount(for cardType: ReportCardType) -> Int {
        let dateRange = getMonthDateRange(for: selectedMonth)
        
        switch cardType {
        case .damageReports:
            // Filter damage records by month (using tarih field)
            return viewModel.araclar.flatMap { $0.hasarKayitlari }
                .filter { hasar in
                    hasar.tarih >= dateRange.start && hasar.tarih <= dateRange.end
                }
                .count
        case .returnReports:
            // Filter return records by month (using iadeTarihi field)
            return viewModel.iadeIslemleri
                .filter { iade in
                    iade.iadeTarihi >= dateRange.start && iade.iadeTarihi <= dateRange.end
                }
                .count
        case .exitReports:
            // Filter exit records by month (using createdAt field - gerçek işlem tarihi)
            return viewModel.exitIslemleri
                .filter { exit in
                    exit.createdAt >= dateRange.start && exit.createdAt <= dateRange.end
                }
                .count
        case .shuttle:
            // Return total shuttle entries count for selected month
            return shuttleEntriesCount
        case .officeOperations:
            // Filter office operations by month (using date field)
            // Include all types: Credit Card, POS, Fuel, Washing, Additional Sales, Banking, Traffic Fine
            let filteredOps = viewModel.officeOperations
                .filter { operation in
                    operation.date >= dateRange.start && operation.date <= dateRange.end
                }
            return filteredOps.count
        case .customerReturns:
            // Filter customer returns by month (using date field)
            return viewModel.officeReturns
                .filter { returnOp in
                    returnOp.date >= dateRange.start && returnOp.date <= dateRange.end
                }
                .count
        case .statistics:
            // Statistics shows overall counts, not filtered
            return viewModel.araclar.count + viewModel.officeOperations.count
        case .timetable:
            // Timetable shows total unique employees across all schedules
            // Get unique user IDs from all work schedules (not just current week)
            let uniqueUserIds = Set(viewModel.workSchedules.map { $0.userId })
            return uniqueUserIds.count
        case .service:
            // Service records - check if there's a date field, if not keep as is
            // Note: Service model might need checking for date field
            return viewModel.servisler.count
        case .vacationTimes:
            // Count active vacation times for selected month
            let dateRange = getMonthDateRange(for: selectedMonth)
            return viewModel.vacationTimes.filter { vacation in
                vacation.isActive &&
                vacation.startDate <= dateRange.end &&
                vacation.endDate >= dateRange.start
            }.count
        }
    }
    
    // MARK: - Previous Month Count
    func getPreviousMonthCount(for cardType: ReportCardType) -> Int {
        // Calculate previous month
        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return 0
        }
        
        let dateRange = getMonthDateRange(for: previousMonth)
        
        switch cardType {
        case .damageReports:
            // Filter damage records by previous month (using tarih field)
            return viewModel.araclar.flatMap { $0.hasarKayitlari }
                .filter { hasar in
                    hasar.tarih >= dateRange.start && hasar.tarih <= dateRange.end
                }
                .count
        case .returnReports:
            // Filter return records by previous month (using iadeTarihi field)
            return viewModel.iadeIslemleri
                .filter { iade in
                    iade.iadeTarihi >= dateRange.start && iade.iadeTarihi <= dateRange.end
                }
                .count
        case .exitReports:
            // Filter exit records by previous month (using createdAt field - gerçek işlem tarihi)
            return viewModel.exitIslemleri
                .filter { exit in
                    exit.createdAt >= dateRange.start && exit.createdAt <= dateRange.end
                }
                .count
        case .shuttle:
            // For shuttle, we'd need to load previous month's count separately
            // For now, return 0 as shuttle uses async loading
            return 0
        case .officeOperations:
            // Filter office operations by previous month (using date field)
            let filteredOps = viewModel.officeOperations
                .filter { operation in
                    operation.date >= dateRange.start && operation.date <= dateRange.end
                }
            return filteredOps.count
        case .customerReturns:
            // Filter customer returns by previous month (using date field)
            return viewModel.officeReturns
                .filter { returnOp in
                    returnOp.date >= dateRange.start && returnOp.date <= dateRange.end
                }
                .count
        case .vacationTimes:
            // Count active vacation times for previous month
            return viewModel.vacationTimes.filter { vacation in
                vacation.isActive &&
                vacation.startDate <= dateRange.end &&
                vacation.endDate >= dateRange.start
            }.count
        default:
            // Statistics, timetable, service don't have monthly comparison
            return 0
        }
    }
    
    // MARK: - KPI Metric Calculation
    func calculateKPIMetric(current: Int, previous: Int) -> (percentage: Double, isPositive: Bool, change: Int)? {
        // If previous is 0, we can't calculate percentage meaningfully
        guard previous > 0 else {
            // If current is also 0, no change to show
            if current == 0 {
                return nil
            }
            // If current > 0 but previous was 0, show as new (100%+ increase)
            // But we'll show it as a special case
            return (100.0, true, current)
        }
        
        let change = current - previous
        let percentage = (Double(change) / Double(previous)) * 100.0
        let isPositive = change >= 0
        
        return (percentage, isPositive, change)
    }
}

struct BigReportCard: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let kpiMetric: (percentage: Double, isPositive: Bool, change: Int)?
    @Environment(\.colorScheme) var colorScheme
    
    init(title: String, icon: String, color: Color, count: Int, kpiMetric: (percentage: Double, isPositive: Bool, change: Int)? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
        self.count = count
        self.kpiMetric = kpiMetric
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(spacing: kpiMetric != nil ? 12 : 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.primary)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
            
            // KPI Metric Display (only if available)
            if let kpi = kpiMetric {
                HStack(spacing: 6) {
                    Image(systemName: kpi.isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(kpi.isPositive ? .green : .red)
                    
                    Text(String(format: "%.1f%%", abs(kpi.percentage)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(kpi.isPositive ? .green : .red)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: kpi.percentage)
                    
                    if kpi.change != 0 {
                        Text("(\(kpi.isPositive ? "+" : "")\(kpi.change))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: kpi.change)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((kpi.isPositive ? Color.green : Color.red).opacity(0.15))
                )
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
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

// MARK: - Office Statistics Chart View
struct OfficeStatisticsChartView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    var totalAmount: Double {
        viewModel.officeOperations.reduce(0) { $0 + $1.amount }
    }
    
    var last30Days: [OfficeOperation] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return viewModel.officeOperations.filter { $0.date >= thirtyDaysAgo }
    }
    
    var typeBreakdown: [(type: OfficeOperationType, amount: Double, count: Int)] {
        OfficeOperationType.allCases.map { type in
            let ops = viewModel.officeOperations.filter { $0.type == type }
            let total = ops.reduce(0) { $0 + $1.amount }
            return (type: type, amount: total, count: ops.count)
        }
    }
    
    var dailyData: [(date: Date, amount: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: last30Days) { operation -> Date in
            calendar.startOfDay(for: operation.date)
        }
        return grouped.map { (date: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                totalOverviewCard
                
                if #available(iOS 16.0, *) {
                    typeDistributionChart
                    dailyTrendChart
                    monthlyBreakdownChart
                } else {
                    legacyCharts
                }
            }
            .padding()
        }
        .navigationTitle("Office Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
    
    private var totalOverviewCard: some View {
        VStack(spacing: 16) {
            // 4 Cards in 2x2 grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatisticCard(
                    title: "Total Amount",
                    value: String(format: "%.2f CHF", totalAmount),
                    icon: "eurosign.circle.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Credit Card",
                    value: String(format: "%.2f CHF", viewModel.totalCreditCardAmount),
                    icon: "creditcard.fill",
                    color: .purple
                )
                
                StatisticCard(
                    title: "POS Total",
                    value: String(format: "%.2f CHF", viewModel.totalPOSAmount),
                    icon: "centsign.circle.fill",
                    color: .green
                )
                
                StatisticCard(
                    title: "Operations",
                    value: "\(viewModel.officeOperations.count)",
                    icon: "doc.text.fill",
                    color: .orange
                )
            }
        }
    }
    
    @available(iOS 16.0, *)
    private var typeDistributionChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Amount by Type")
                .font(.title2)
                .fontWeight(.bold)
            
            Chart(typeBreakdown, id: \.type) { item in
                BarMark(
                    x: .value("Amount", item.amount),
                    y: .value("Type", item.type.rawValue)
                )
                .foregroundStyle(by: .value("Type", item.type.rawValue))
                .annotation(position: .trailing) {
                    Text(String(format: "%.0f CHF", item.amount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 250)
            .chartForegroundStyleScale([
                "Credit Card Receipt": .blue,
                "POS Daily Closing": .green,
                "Fuel Receipt": .orange,
                "Washing Expense": .cyan
            ])
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(20)
        }
    }
    
    @available(iOS 16.0, *)
    private var dailyTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Trend (Last 30 Days)")
                .font(.title2)
                .fontWeight(.bold)
            
            if !dailyData.isEmpty {
                Chart(dailyData, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date.formatted(.dateTime.day().month(.narrow)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(20)
            } else {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
            }
        }
    }
    
    @available(iOS 16.0, *)
    private var monthlyBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Breakdown")
                .font(.title2)
                .fontWeight(.bold)
            
            let monthlyData = getMonthlyData()
            
            Chart(monthlyData, id: \.month) { item in
                BarMark(
                    x: .value("Month", item.month),
                    y: .value("Amount", item.amount)
                )
                .foregroundStyle(Color.green.gradient)
                .annotation(position: .top) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", item.amount))
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("CHF")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(20)
        }
    }
    
    private var legacyCharts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(typeBreakdown, id: \.type) { item in
                TypeDistributionBar(
                    type: item.type,
                    amount: item.amount,
                    total: totalAmount
                )
            }
        }
    }
    
    func getMonthlyData() -> [(month: String, amount: Double, count: Int)] {
        let calendar = Calendar.current
        let currentDate = Date()
        
        var results: [(month: String, amount: Double, count: Int)] = []
        
        for i in 0..<6 {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: currentDate) else { continue }
            let monthString = monthDate.formatted(.dateTime.month(.abbreviated))
            
            let monthOperations = viewModel.officeOperations.filter { operation in
                calendar.isDate(operation.date, equalTo: monthDate, toGranularity: .month)
            }
            
            let total = monthOperations.reduce(0) { $0 + $1.amount }
            results.append((month: monthString, amount: total, count: monthOperations.count))
        }
        
        return results.reversed()
    }
}

struct MiniStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

struct TypeDistributionBar: View {
    let type: OfficeOperationType
    let amount: Double
    let total: Double
    
    var percentage: Double {
        total > 0 ? (amount / total) * 100 : 0
    }
    
    var color: Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(type.rawValue, systemImage: type.icon)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text(String(format: "%.2f CHF", amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                        .cornerRadius(6)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * (percentage / 100), height: 12)
                        .cornerRadius(6)
                }
            }
            .frame(height: 12)
            
            Text(String(format: "%.1f%%", percentage))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Damage Reports View
struct DamageReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var searchQuery = ""
    @State private var dateFilter: DateFilterType = .monthly
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showCustomDatePicker = false
    @State private var showPDFExportSheet = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    
    enum DateFilterType: String, CaseIterable {
        case all = "All"
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        // Get month range for selected month
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) else {
            // Fallback
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        }
        
        switch dateFilter {
        case .all:
            // Tüm kayıtları göster - çok geniş bir tarih aralığı
            let distantPast = Date.distantPast
            let distantFuture = Date.distantFuture
            return (distantPast, distantFuture)
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .monthly:
            // Use selected month range
            return (monthStart, monthEnd)
        }
    }
    
    var filteredDamages: [(arac: Arac, hasar: HasarKaydi)] {
        var results: [(Arac, HasarKaydi)] = []
        
        for arac in viewModel.araclar {
            for hasar in arac.hasarKayitlari {
                let matchesSearch = searchQuery.isEmpty || 
                    arac.plaka.localizedCaseInsensitiveContains(searchQuery) ||
                    hasar.resKodu.localizedCaseInsensitiveContains(searchQuery)
                // "All" seçildiğinde tarih filtresi uygulanmaz
                let matchesDate = dateFilter == .all || (hasar.tarih >= dateRange.start && hasar.tarih <= dateRange.end)
                
                if matchesSearch && matchesDate {
                    results.append((arac, hasar))
                }
            }
        }
        
        return results.sorted(by: { $0.1.tarih > $1.1.tarih })
    }
    
    var searchSuggestions: [String] {
        if searchQuery.isEmpty { return [] }
        var suggestions: [String] = []
        
        // Plate suggestions
        let plateSuggestions = viewModel.araclar
            .map { $0.plakaFormatli }
            .filter { $0.localizedCaseInsensitiveContains(searchQuery) }
            .prefix(3)
        
        suggestions.append(contentsOf: plateSuggestions)
        
        // RES code suggestions
        let resSuggestions = viewModel.araclar
            .flatMap { arac in
                arac.hasarKayitlari.map { hasar in
                    hasar.resKodu
                }
            }
            .filter { $0.localizedCaseInsensitiveContains(searchQuery) }
            .prefix(3)
        
        suggestions.append(contentsOf: resSuggestions)
        
        return Array(Set(suggestions)).prefix(5).map { String($0) }
    }
    
    // MARK: - Statistics
    var damageStatistics: (total: Int, completed: Int, inProgress: Int, totalPhotos: Int, avgPhotos: Double) {
        let damages = filteredDamages.map { $0.hasar }
        let total = damages.count
        let completed = damages.filter { $0.durum == .done }.count
        let inProgress = damages.filter { $0.durum == .inProgress }.count
        let totalPhotos = damages.reduce(0) { $0 + $1.fotograflar.count }
        let avgPhotos = total > 0 ? Double(totalPhotos) / Double(total) : 0.0
        return (total, completed, inProgress, totalPhotos, avgPhotos)
    }
    
    var body: some View {
        ScrollView {
        VStack(spacing: 0) {
                // Metric Cards Section
                if !filteredDamages.isEmpty {
                    metricCardsSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Search & Filter Section
                searchFilterSection
                    .padding(.horizontal)
                    .padding(.top, filteredDamages.isEmpty ? 8 : 16)
                
                // List Section
                if filteredDamages.isEmpty {
                    emptyStateView
                        .frame(maxHeight: .infinity)
                        .padding(.top, 40)
                        .transition(.opacity)
                } else {
                    damageListSection
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredDamages.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dateFilter)
        .navigationTitle("Damage Reports")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showPDFExportSheet = true
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPDFExportSheet) {
            PDFExportDateRangeView(
                title: "Export Damage Report",
                dateRange: dateRange,
                onExport: { startDate, endDate in
                    exportDamagePDFWithDateRange(start: startDate, end: endDate)
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = damageStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                DamageMetricCard(
                    title: "Total",
                    value: "\(stats.total)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "Completed",
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "In Progress",
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "Photos",
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .purple
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Search & Filter Section
    private var searchFilterSection: some View {
        VStack(spacing: 16) {
            // Unified Search Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Search")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search by plate or RES code", text: $searchQuery)
                        .textInputAutocapitalization(.characters)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                
                if !searchSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchSuggestions, id: \.self) { suggestion in
                            Button {
                                searchQuery = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if suggestion != searchSuggestions.last {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            // Date Filter Picker
            Picker("Date Filter", selection: $dateFilter) {
                ForEach(DateFilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: dateFilter) { oldValue, newValue in
                // No custom date picker needed anymore
            }
            .sensoryFeedback(.selection, trigger: dateFilter)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Damage List Section
    private var damageListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(filteredDamages.enumerated()), id: \.element.hasar.id) { index, item in
                NavigationLink(destination: HasarDetayView(hasar: item.hasar, aracId: item.arac.id, aracPlaka: item.arac.plakaFormatli)) {
                    DamageReportRow(arac: item.arac, hasar: item.hasar)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))
            
                    Text("No Damage Records Found")
                        .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Damage Metric Card
struct DamageMetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
                }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 2)
    }
}

struct DamageReportRow: View {
    let arac: Arac
    let hasar: HasarKaydi
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                        Text(arac.plakaFormatli)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                
                        Text(hasar.resKodu)
                            .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.medium")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(hasar.km) km")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 12))
                        .foregroundColor(.blue)
                        Text("\(hasar.fotograflar.count)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 4, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        switch hasar.durum {
        case .done:
            return .green
        case .inProgress:
            return .blue
        }
    }
    
    private var statusIcon: String {
        switch hasar.durum {
        case .done:
            return "checkmark.circle.fill"
        case .inProgress:
            return "clock.fill"
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(hasar.durum.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}

// MARK: - Damage Reports View Extension
extension DamageReportsView {
    // MARK: - PDF Export Functions
    func exportDamagePDFWithDateRange(start: Date, end: Date) {
        isExporting = true
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: start)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) ?? end
        
        let filtered = viewModel.araclar.flatMap { arac in
            arac.hasarKayitlari.filter { hasar in
                hasar.tarih >= startOfDay && hasar.tarih <= endOfDay
            }.map { (arac: arac, hasar: $0) }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = DamageRaporManager.shared.generatePDF(damages: filtered)
            DispatchQueue.main.async {
                self.isExporting = false
                self.shareURL = fileURL
                self.showShareSheet = true
            }
        }
    }
}

// MARK: - PDF Export Date Range View
struct PDFExportDateRangeView: View {
    let title: String
    let dateRange: (start: Date, end: Date)
    let onExport: (Date, Date) -> Void
    
    @State private var startDate: Date
    @State private var endDate: Date
    @Environment(\.dismiss) var dismiss
    
    init(title: String, dateRange: (start: Date, end: Date), onExport: @escaping (Date, Date) -> Void) {
        self.title = title
        self.dateRange = dateRange
        self.onExport = onExport
        _startDate = State(initialValue: dateRange.start)
        _endDate = State(initialValue: dateRange.end)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                } header: {
                    Text("Select Date Range")
                } footer: {
                    Text("Export all records within the selected date range as PDF")
                }
                
                Section {
                    Button {
                        onExport(startDate, endDate)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Export PDF")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(title)
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
}

// MARK: - Damage Report Manager
class DamageRaporManager {
    static let shared = DamageRaporManager()
    
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func generatePDF(damages: [(arac: Arac, hasar: HasarKaydi)]) -> URL {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = 50
            let leftMargin: CGFloat = 30
            let rightMargin: CGFloat = 30
            let pageWidth = pageSize.width - leftMargin - rightMargin
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Damage Reports"
            title.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let currentDate = "Report Generated: \(dateFormatter.string(from: Date()))"
            currentDate.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 30
            
            let statsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.darkGray
            ]
            let totalPhotos = damages.reduce(0) { $0 + $1.hasar.fotograflar.count }
            let stats = "Total Damages: \(damages.count) | Total Photos: \(totalPhotos)"
            stats.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: statsAttributes)
            yPosition += 40
            
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            
            "Plate".draw(at: CGPoint(x: leftMargin + 5, y: yPosition), withAttributes: headerAttributes)
            "RES Code".draw(at: CGPoint(x: leftMargin + 120, y: yPosition), withAttributes: headerAttributes)
            "Date".draw(at: CGPoint(x: leftMargin + 250, y: yPosition), withAttributes: headerAttributes)
            "Status".draw(at: CGPoint(x: leftMargin + 380, y: yPosition), withAttributes: headerAttributes)
            "Photos".draw(at: CGPoint(x: leftMargin + 450, y: yPosition), withAttributes: headerAttributes)
            yPosition += 25
            
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.black
            ]
            
            for (index, item) in damages.enumerated() {
                if yPosition > pageSize.height - 50 {
                    context.beginPage()
                    yPosition = 50
                }
                
                if index % 2 == 0 {
                    let rowRect = CGRect(x: leftMargin, y: yPosition - 5, width: pageWidth, height: 20)
                    context.cgContext.setFillColor(UIColor(white: 0.95, alpha: 1.0).cgColor)
                    context.cgContext.fill(rowRect)
                }
                
                item.arac.plakaFormatli.draw(at: CGPoint(x: leftMargin + 5, y: yPosition), withAttributes: rowAttributes)
                item.hasar.resKodu.draw(at: CGPoint(x: leftMargin + 120, y: yPosition), withAttributes: rowAttributes)
                dateFormatter.string(from: item.hasar.tarih).draw(at: CGPoint(x: leftMargin + 250, y: yPosition), withAttributes: rowAttributes)
                item.hasar.durum.displayTitle.draw(at: CGPoint(x: leftMargin + 380, y: yPosition), withAttributes: rowAttributes)
                "\(item.hasar.fotograflar.count)".draw(at: CGPoint(x: leftMargin + 450, y: yPosition), withAttributes: rowAttributes)
                
                yPosition += 22
            }
        }
        
        let filename = "damage_report_\(Date().timeIntervalSince1970).pdf"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            print("✅ Damage PDF kaydedildi: \(fileURL.path)")
            return fileURL
        } catch {
            print("❌ PDF oluşturma hatası: \(error)")
            return fileURL
        }
    }
}

// MARK: - Return Reports View
struct ReturnReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var searchQuery = ""
    @State private var dateFilter: DateFilterType = .all
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var showPDFExportSheet = false
    
    enum DateFilterType: String, CaseIterable {
        case all = "All"
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        // Get month range for selected month
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) else {
            // Fallback
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        }
        
        switch dateFilter {
        case .all:
            // Tüm kayıtları göster - çok geniş bir tarih aralığı
            let distantPast = Date.distantPast
            let distantFuture = Date.distantFuture
            return (distantPast, distantFuture)
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .monthly:
            // Use selected month range
            return (monthStart, monthEnd)
        }
    }
    
    var filteredReturns: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { iade in
            let matchesSearch = searchQuery.isEmpty || iade.aracPlaka.localizedCaseInsensitiveContains(searchQuery) || iade.notlar.localizedCaseInsensitiveContains(searchQuery)
            // "All" seçildiğinde tarih filtresi uygulanmaz
            let matchesDate = dateFilter == .all || (iade.iadeTarihi >= dateRange.start && iade.iadeTarihi <= dateRange.end)
            return matchesSearch && matchesDate
        }.sorted(by: { $0.iadeTarihi > $1.iadeTarihi })
    }
    
    // MARK: - Statistics
    var returnStatistics: (total: Int, totalPhotos: Int, inProgress: Int, completed: Int) {
        let returns = filteredReturns
        let total = returns.count
        let totalPhotos = returns.reduce(0) { $0 + $1.fotograflar.count }
        let inProgress = returns.filter { $0.status == .inProgress }.count
        let completed = returns.filter { $0.status == .completed }.count
        return (total, totalPhotos, inProgress, completed)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Metric Cards Section
                if !filteredReturns.isEmpty {
                    metricCardsSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Search & Filter Section
                searchFilterSection
                    .padding(.horizontal)
                    .padding(.top, filteredReturns.isEmpty ? 8 : 16)
                
                // List Section
                if filteredReturns.isEmpty {
                    emptyStateView
                        .frame(maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    returnListSection
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Return Reports")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showPDFExportSheet = true
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                    
                    Button {
                        exportReturnXLSX()
                    } label: {
                        Label("Export Excel", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showPDFExportSheet) {
            PDFExportDateRangeView(
                title: "Export Return Report",
                dateRange: dateRange,
                onExport: { startDate, endDate in
                    exportReturnPDFWithDateRange(start: startDate, end: endDate)
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredReturns.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dateFilter)
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = returnStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ReturnMetricCard(
                    title: "Total",
                    value: "\(stats.total)",
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .purple
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Photos",
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "In Progress",
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Completed",
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Search & Filter Section
    private var searchFilterSection: some View {
        VStack(spacing: 16) {
            // Search Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Search")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search by plate or notes", text: $searchQuery)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            }
            
            // Date Filter Picker
            Picker("Date Filter", selection: $dateFilter) {
                ForEach(DateFilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: dateFilter) { oldValue, newValue in
                // No custom date picker needed anymore
            }
            .sensoryFeedback(.selection, trigger: dateFilter)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Return List Section
    private var returnListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(filteredReturns.enumerated()), id: \.element.id) { index, iade in
                NavigationLink(destination: IadeDetayView(iade: iade)) {
                    IadeSatirView(iade: iade)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("No Return Reports Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
    
    func exportReturnPDFWithDateRange(start: Date, end: Date) {
        isExporting = true
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: start)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) ?? end
        
        let filtered = viewModel.iadeIslemleri.filter { iade in
            iade.iadeTarihi >= startOfDay && iade.iadeTarihi <= endOfDay
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = IadeRaporManager.shared.generatePDF(iadeler: filtered)
            DispatchQueue.main.async {
                self.isExporting = false
                self.shareURL = fileURL
                self.showShareSheet = true
            }
        }
    }
    
    func exportReturnXLSX() {
        isExporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = IadeRaporManager.shared.generateXLSX(iadeler: filteredReturns)
            DispatchQueue.main.async {
                self.isExporting = false
                self.shareURL = fileURL
                self.showShareSheet = true
            }
        }
    }
    
    func getRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .filter { $0.isKeyWindow }
            .first?.rootViewController
    }
}

struct IadeSatirView: View {
    let iade: IadeIslemi
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(iade.aracPlaka)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !iade.notlar.isEmpty {
                            Text(iade.notlar)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(iade.iadeTarihi.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    if !iade.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text("\(iade.fotograflar.count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 6, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        iade.status == .inProgress ? .orange : .green
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(iade.status == .inProgress ? "Saved" : "Done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}

// MARK: - Return Metric Card
struct ReturnMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? color.opacity(0.4) : color.opacity(0.2), lineWidth: colorScheme == .dark ? 1.5 : 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Reports Overview Charts
struct ReportsOverviewChartsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    
    var damagesByCategory: [(category: String, count: Int)] {
        let categoryDamages = Dictionary(grouping: viewModel.araclar.filter { !$0.hasarKayitlari.isEmpty }, by: { $0.kategori })
        return categoryDamages.map { (category: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }
    
    var officeOperationsByType: [(type: String, amount: Double)] {
        var data: [(type: String, amount: Double)] = []
        for opType in OfficeOperationType.allCases {
            let ops = viewModel.officeOperations.filter { $0.type == opType }
            let total = ops.reduce(0) { $0 + $1.amount }
            if total > 0 {
                data.append((type: opType.rawValue, amount: total))
            }
        }
        return data
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Damage Reports Chart
            if !damagesByCategory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Damaged Vehicles by Category")
                        .font(.headline)
                    
                    if #available(iOS 16.0, *) {
                        Chart(damagesByCategory, id: \.category) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Category", item.category)
                            )
                            .foregroundStyle(Color.orange.gradient)
                            .annotation(position: .trailing) {
                                Text("\(item.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    } else {
                        ForEach(damagesByCategory, id: \.category) { item in
                            HStack {
                                Text(item.category)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
            }
            
            // Office Operations Chart
            if !officeOperationsByType.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Office Operations Total")
                        .font(.headline)
                    
                    if #available(iOS 16.0, *) {
                        Chart(officeOperationsByType, id: \.type) { item in
                            SectorMark(
                                angle: .value("Amount", item.amount),
                                innerRadius: .ratio(0.5),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Type", item.type))
                            .annotation(position: .overlay) {
                                Text(String(format: "%.0f", item.amount))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 250)
                        .chartLegend(position: .bottom)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    } else {
                        ForEach(officeOperationsByType, id: \.type) { item in
                            HStack {
                                Text(item.type)
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f CHF", item.amount))
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
            }
            
            // Return Reports Timeline
            if !viewModel.iadeIslemleri.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Returns")
                        .font(.headline)
                    
                    let recentReturns = viewModel.iadeIslemleri.sorted { $0.iadeTarihi > $1.iadeTarihi }.prefix(5)
                    
                    VStack(spacing: 8) {
                        ForEach(Array(recentReturns), id: \.id) { iade in
                            HStack {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundColor(.purple)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(iade.aracPlaka)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(iade.iadeTarihi.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if !iade.fotograflar.isEmpty {
                                    Label("\(iade.fotograflar.count)", systemImage: "photo")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Comprehensive Statistics View
struct ComprehensiveStatisticsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var isLoading = true
    @State private var animationOffset: CGFloat = 50
    @State private var animationOpacity: Double = 0
    
    // Interactive states
    @State private var selectedCategory: String?
    @State private var selectedModel: String?
    @State private var selectedDamageRange: String?
    @State private var selectedOperationType: String?
    @State private var showCategoryDetail = false
    @State private var showModelDetail = false
    @State private var showDamageDetail = false
    @State private var showOperationDetail = false
    @State private var showOverviewCardDetail = false
    @State private var selectedOverviewType: OverviewType?
    
    enum OverviewType {
        case vehicles, damages, returns, services
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.green)
                        Text("Loading Statistics...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVStack(spacing: 24) {
                        // Overview Cards
                        overviewCardsSection
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Vehicle Categories Chart
                        vehicleCategoriesChart
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Vehicle Models Chart
                        vehicleModelsChart
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Damage Count Distribution
                        damageCountChart
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Office Operations Statistics
                        officeOperationsStats
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Return Operations Statistics
                        returnOperationsStats
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Service Statistics
                        serviceStats
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                        
                        // Damage Records Statistics
                        damageStats
                            .offset(y: animationOffset)
                            .opacity(animationOpacity)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            loadStatistics()
        }
        .sheet(isPresented: $showOverviewCardDetail) {
            if let type = selectedOverviewType {
                OverviewDetailView(type: type, viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Overview Cards
    private var overviewCardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Button {
                    HapticManager.shared.light()
                    selectedOverviewType = .vehicles
                    showOverviewCardDetail = true
                } label: {
                    StatisticOverviewCard(
                        title: "Total Vehicles",
                        value: "\(viewModel.araclar.count)",
                        icon: "car.fill",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    HapticManager.shared.light()
                    selectedOverviewType = .damages
                    showOverviewCardDetail = true
                } label: {
                    StatisticOverviewCard(
                        title: "Total Damage Records",
                        value: "\(totalDamageRecords)",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    HapticManager.shared.light()
                    selectedOverviewType = .returns
                    showOverviewCardDetail = true
                } label: {
                    StatisticOverviewCard(
                        title: "Total Returns",
                        value: "\(viewModel.iadeIslemleri.count)",
                        icon: "arrow.uturn.backward.circle.fill",
                        color: .purple
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    HapticManager.shared.light()
                    selectedOverviewType = .services
                    showOverviewCardDetail = true
                } label: {
                    StatisticOverviewCard(
                        title: "Total Services",
                        value: "\(viewModel.servisler.count)",
                        icon: "wrench.and.screwdriver.fill",
                        color: .red
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Vehicle Categories Chart
    private var vehicleCategoriesChart: some View {
        let categoryData = getVehicleCategoriesData()
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Vehicle Categories Distribution")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                if selectedCategory != nil {
                    Button(action: {
                        selectedCategory = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if #available(iOS 16.0, *) {
                Chart(categoryData, id: \.category) { item in
                    BarMark(
                        x: .value("Category", item.category),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(selectedCategory == item.category ? Color.blue.gradient : Color.green.gradient)
                    .annotation(position: .top) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(selectedCategory == item.category ? .blue : .secondary)
                    }
                }
                .frame(height: 250)
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
                .chartXSelection(value: $selectedCategory)
                .onChange(of: selectedCategory) { newValue in
                    if newValue != nil {
                        HapticManager.shared.light()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showCategoryDetail = true
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(categoryData, id: \.category) { item in
                        Button {
                            HapticManager.shared.light()
                            selectedCategory = item.category
                            showCategoryDetail = true
                        } label: {
                            HStack {
                                Text(item.category)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .background(selectedCategory == item.category ? Color.green.opacity(0.3) : Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            }
        }
        .sheet(isPresented: $showCategoryDetail) {
            CategoryDetailView(
                category: selectedCategory ?? "",
                vehicles: viewModel.araclar.filter { $0.kategori == selectedCategory }
            )
        }
    }
    
    // MARK: - Vehicle Models Chart
    private var vehicleModelsChart: some View {
        let modelData = getVehicleModelsData()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Top Vehicle Models")
                .font(.title3)
                .fontWeight(.bold)
            
            if #available(iOS 16.0, *) {
                Chart(modelData.prefix(10), id: \.model) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Model", item.model)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: min(300, CGFloat(modelData.count) * 30))
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    ForEach(modelData.prefix(10), id: \.model) { item in
                        HStack {
                            Text(item.model)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count)")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            }
        }
    }
    
    // MARK: - Damage Count Chart
    private var damageCountChart: some View {
        let damageData = getDamageCountDistribution()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Damage Count Distribution")
                .font(.title3)
                .fontWeight(.bold)
            
            if #available(iOS 16.0, *) {
                Chart(damageData, id: \.label) { item in
                    BarMark(
                        x: .value("Label", item.label),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .annotation(position: .top) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 200)
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    ForEach(damageData, id: \.label) { item in
                        HStack {
                            Text(item.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count)")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            }
        }
    }
    
    // MARK: - Office Operations Statistics
    private var officeOperationsStats: some View {
        let opsByType = getOfficeOperationsByType()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Office Operations")
                .font(.title3)
                .fontWeight(.bold)
            
            if #available(iOS 16.0, *) {
                Chart(opsByType, id: \.type) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Type", item.type))
                    .annotation(position: .overlay) {
                        Text(String(format: "%.0f", item.amount))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 300)
                .chartLegend(position: .bottom)
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    ForEach(opsByType, id: \.type) { item in
                        HStack {
                            Text(item.type)
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f CHF", item.amount))
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(backgroundColor)
                .cornerRadius(16)
            }
        }
    }
    
    // MARK: - Return Operations Statistics
    private var returnOperationsStats: some View {
        let returnData = getReturnStatistics()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Return Operations")
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                StatisticRowCard(
                    title: "Total Returns",
                    value: "\(returnData.total)",
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .purple
                )
                
                StatisticRowCard(
                    title: "Completed",
                    value: "\(returnData.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatisticRowCard(
                    title: "In Progress",
                    value: "\(returnData.inProgress)",
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatisticRowCard(
                    title: "Total Photos",
                    value: "\(returnData.totalPhotos)",
                    icon: "photo.fill",
                    color: .blue
                )
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Service Statistics
    private var serviceStats: some View {
        let serviceData = getServiceStatistics()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Service Operations")
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                StatisticRowCard(
                    title: "Total Services",
                    value: "\(serviceData.total)",
                    icon: "wrench.and.screwdriver.fill",
                    color: .red
                )
                
                StatisticRowCard(
                    title: "In Service",
                    value: "\(serviceData.inService)",
                    icon: "hourglass",
                    color: .orange
                )
                
                StatisticRowCard(
                    title: "Completed",
                    value: "\(serviceData.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatisticRowCard(
                    title: "Cancelled",
                    value: "\(serviceData.cancelled)",
                    icon: "xmark.circle.fill",
                    color: .red
                )
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Damage Statistics
    private var damageStats: some View {
        let damageData = getDamageStatistics()
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Damage Records")
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                StatisticRowCard(
                    title: "Total Damage Records",
                    value: "\(damageData.total)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                
                StatisticRowCard(
                    title: "Completed",
                    value: "\(damageData.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatisticRowCard(
                    title: "In Progress",
                    value: "\(damageData.inProgress)",
                    icon: "clock.fill",
                    color: .yellow
                )
                
                StatisticRowCard(
                    title: "Total Photos",
                    value: "\(damageData.totalPhotos)",
                    icon: "photo.fill",
                    color: .blue
                )
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Helper Computed Properties
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6)
    }
    
    private var totalDamageRecords: Int {
        viewModel.araclar.flatMap { $0.hasarKayitlari }.count
    }
    
    // MARK: - Data Processing Functions
    private func getVehicleCategoriesData() -> [(category: String, count: Int)] {
        let grouped = Dictionary(grouping: viewModel.araclar, by: { $0.kategori })
        return grouped.map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    private func getVehicleModelsData() -> [(model: String, count: Int)] {
        let grouped = Dictionary(grouping: viewModel.araclar, by: { "\($0.marka) \($0.model)" })
        return grouped.map { (model: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    private func getDamageCountDistribution() -> [(label: String, count: Int)] {
        var distribution: [Int: Int] = [:]
        
        for arac in viewModel.araclar {
            let count = arac.hasarKayitlari.count
            distribution[count, default: 0] += 1
        }
        
        return [
            (label: "0 Damage", count: distribution[0] ?? 0),
            (label: "1 Damage", count: distribution[1] ?? 0),
            (label: "2 Damages", count: distribution[2] ?? 0),
            (label: "3+ Damages", count: distribution.filter { $0.key >= 3 }.values.reduce(0, +))
        ]
    }
    
    private func getOfficeOperationsByType() -> [(type: String, amount: Double, count: Int)] {
        OfficeOperationType.allCases.map { type in
            let ops = viewModel.officeOperations.filter { $0.type == type }
            let total = ops.reduce(0) { $0 + $1.amount }
            return (type: type.rawValue, amount: total, count: ops.count)
        }.filter { $0.amount > 0 || $0.count > 0 }
    }
    
    private func getReturnStatistics() -> (total: Int, completed: Int, inProgress: Int, totalPhotos: Int) {
        let total = viewModel.iadeIslemleri.count
        let completed = viewModel.iadeIslemleri.filter { $0.status == .completed }.count
        let inProgress = viewModel.iadeIslemleri.filter { $0.status == .inProgress }.count
        let totalPhotos = viewModel.iadeIslemleri.reduce(0) { $0 + $1.fotograflar.count }
        
        return (total, completed, inProgress, totalPhotos)
    }
    
    private func getServiceStatistics() -> (total: Int, inService: Int, completed: Int, cancelled: Int) {
        let total = viewModel.servisler.count
        let inService = viewModel.servisler.filter { $0.durum == .serviste }.count
        let completed = viewModel.servisler.filter { $0.durum == .tamamlandi }.count
        let cancelled = viewModel.servisler.filter { $0.durum == .iptal }.count
        
        return (total, inService, completed, cancelled)
    }
    
    private func getDamageStatistics() -> (total: Int, completed: Int, inProgress: Int, totalPhotos: Int) {
        let allDamages = viewModel.araclar.flatMap { $0.hasarKayitlari }
        let total = allDamages.count
        let completed = allDamages.filter { $0.durum == .done }.count
        let inProgress = allDamages.filter { $0.durum == .inProgress }.count
        let totalPhotos = allDamages.reduce(0) { $0 + $1.fotograflar.count }
        
        return (total, completed, inProgress, totalPhotos)
    }
    
    // MARK: - Loading Function
    private func loadStatistics() {
        // Simulate loading with animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isLoading = false
                animationOffset = 0
                animationOpacity = 1
            }
        }
    }
}

// MARK: - Statistic Overview Card
struct StatisticOverviewCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Statistic Row Card
struct StatisticRowCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Category Detail View
struct CategoryDetailView: View {
    let category: String
    let vehicles: [Arac]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category: \(category)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Total Vehicles: \(vehicles.count)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Vehicles in this Category") {
                    ForEach(vehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(vehicle.plakaFormatli)
                                .font(.headline)
                            
                            HStack {
                                Text("\(vehicle.marka) \(vehicle.model)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if !vehicle.hasarKayitlari.isEmpty {
                                    Label("\(vehicle.hasarKayitlari.count) damage(s)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Category Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Overview Detail View
struct OverviewDetailView: View {
    let type: ComprehensiveStatisticsView.OverviewType
    @ObservedObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                switch type {
                case .vehicles:
                    Section("Vehicle Statistics") {
                        StatisticDetailRow(title: "Total Vehicles", value: "\(viewModel.araclar.count)")
                        StatisticDetailRow(title: "By Category", value: "\(Set(viewModel.araclar.map { $0.kategori }).count) categories")
                        StatisticDetailRow(title: "With Damage", value: "\(viewModel.damagedCarsCount)")
                        StatisticDetailRow(title: "Without Damage", value: "\(viewModel.availableCarsCount)")
                    }
                    
                    Section("Categories") {
                        let categories = Dictionary(grouping: viewModel.araclar, by: { $0.kategori })
                        ForEach(categories.sorted(by: { $0.key < $1.key }), id: \.key) { category, vehicles in
                            HStack {
                                Text(category)
                                Spacer()
                                Text("\(vehicles.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                case .damages:
                    let allDamages = viewModel.araclar.flatMap { $0.hasarKayitlari }
                    Section("Damage Statistics") {
                        StatisticDetailRow(title: "Total Damage Records", value: "\(allDamages.count)")
                        StatisticDetailRow(title: "Completed", value: "\(allDamages.filter { $0.durum == .done }.count)")
                        StatisticDetailRow(title: "In Progress", value: "\(allDamages.filter { $0.durum == .inProgress }.count)")
                        StatisticDetailRow(title: "Total Photos", value: "\(allDamages.reduce(0) { $0 + $1.fotograflar.count })")
                    }
                    
                case .returns:
                    Section("Return Statistics") {
                        StatisticDetailRow(title: "Total Returns", value: "\(viewModel.iadeIslemleri.count)")
                        StatisticDetailRow(title: "Completed", value: "\(viewModel.iadeIslemleri.filter { $0.status == .completed }.count)")
                        StatisticDetailRow(title: "In Progress", value: "\(viewModel.iadeIslemleri.filter { $0.status == .inProgress }.count)")
                        StatisticDetailRow(title: "Total Photos", value: "\(viewModel.iadeIslemleri.reduce(0) { $0 + $1.fotograflar.count })")
                    }
                    
                case .services:
                    Section("Service Statistics") {
                        StatisticDetailRow(title: "Total Services", value: "\(viewModel.servisler.count)")
                        StatisticDetailRow(title: "In Service", value: "\(viewModel.servisler.filter { $0.durum == .serviste }.count)")
                        StatisticDetailRow(title: "Completed", value: "\(viewModel.servisler.filter { $0.durum == .tamamlandi }.count)")
                        StatisticDetailRow(title: "Cancelled", value: "\(viewModel.servisler.filter { $0.durum == .iptal }.count)")
                    }
                }
            }
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var detailTitle: String {
        switch type {
        case .vehicles: return "Vehicles Details"
        case .damages: return "Damage Records Details"
        case .returns: return "Return Operations Details"
        case .services: return "Service Operations Details"
        }
    }
}

// MARK: - Statistic Detail Row
struct StatisticDetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exit Reports View
struct ExitReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var searchQuery = ""
    @State private var dateFilter: DateFilterType = .all
    
    enum DateFilterType: String, CaseIterable {
        case all = "All"
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        // Get month range for selected month
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) else {
            // Fallback
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        }
        
        switch dateFilter {
        case .all:
            // Tüm kayıtları göster - çok geniş bir tarih aralığı
            let distantPast = Date.distantPast
            let distantFuture = Date.distantFuture
            return (distantPast, distantFuture)
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .monthly:
            // Use selected month range
            return (monthStart, monthEnd)
        }
    }
    
    var filteredExits: [ExitIslemi] {
        viewModel.exitIslemleri.filter { exit in
            let matchesSearch = searchQuery.isEmpty || exit.aracPlaka.localizedCaseInsensitiveContains(searchQuery) || exit.notlar.localizedCaseInsensitiveContains(searchQuery)
            // Filtreleme için gerçek işlem tarihini kullan (createdAt), exitTarihi sadece PDF için
            // "All" seçildiğinde tarih filtresi uygulanmaz
            let filterTarihi = exit.createdAt
            let matchesDate = dateFilter == .all || (filterTarihi >= dateRange.start && filterTarihi <= dateRange.end)
            return matchesSearch && matchesDate
        }.sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    // MARK: - Statistics
    var exitStatistics: (total: Int, totalPhotos: Int, inProgress: Int, completed: Int) {
        // Use all exits from viewModel, not filtered ones, to show correct total count
        let allExits = viewModel.exitIslemleri
        let total = allExits.count
        let totalPhotos = allExits.reduce(0) { $0 + $1.fotograflar.count }
        let inProgress = allExits.filter { $0.status == .inProgress }.count
        let completed = allExits.filter { $0.status == .completed }.count
        return (total, totalPhotos, inProgress, completed)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Metric Cards Section
                if !filteredExits.isEmpty {
                    metricCardsSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Search & Filter Section
                searchFilterSection
                    .padding(.horizontal)
                    .padding(.top, filteredExits.isEmpty ? 8 : 16)
                
                // List Section
                if filteredExits.isEmpty {
                    emptyStateView
                        .frame(maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    exitListSection
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Check Out Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = exitStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ReturnMetricCard(
                    title: "Total",
                    value: "\(stats.total)",
                    icon: "arrow.right.circle.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Photos",
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .green
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "In Progress",
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Completed",
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .purple
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Search & Filter Section
    private var searchFilterSection: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by plate or notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Date Filter Picker
            Picker("Date Filter", selection: $dateFilter) {
                ForEach(DateFilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: dateFilter) { oldValue, newValue in
                // No custom date picker needed anymore
            }
            .sensoryFeedback(.selection, trigger: dateFilter)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Exit List Section
    private var exitListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(filteredExits.enumerated()), id: \.element.id) { index, exit in
                NavigationLink(destination: ExitDetayView(exit: exit)) {
                    ExitSatirView(exit: exit)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("No Check Out Reports Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Exit Row View
struct ExitSatirView: View {
    let exit: ExitIslemi
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon - Yeşil araç ikonu
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "car.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.green)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exit.aracPlaka)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !exit.notlar.isEmpty {
                            Text(exit.notlar)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(exit.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    if !exit.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text("\(exit.fotograflar.count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 6, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        exit.status == .inProgress ? .orange : .green
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(exit.status == .inProgress ? "Saved" : "Done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
