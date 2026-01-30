import SwiftUI
import Charts

/// Advanced analytics dashboard with charts and insights
struct AnalyticsDashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var analytics = AnalyticsViewModel()
    @State private var selectedPeriod: TimePeriod = .monthly
    @State private var selectedDamageDate: Date?
    @State private var selectedReturnDate: Date?
    @State private var selectedOfficeDate: Date?
    
    enum TimePeriod: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        var localizedTitle: String { rawValue.localized }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Insights Section (Top)
                    insightsSection
                    
                    // Period Selector
                    periodSelector
                    
                    // Charts Section
                    if #available(iOS 16.0, *) {
                        chartsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics".localized)
            .onAppear {
                analytics.calculateAnalytics(
                    vehicles: viewModel.araclar,
                    returns: viewModel.iadeIslemleri,
                    officeOperations: viewModel.officeOperations,
                    period: selectedPeriod
                )
            }
            .onChange(of: selectedPeriod) { newPeriod in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    analytics.calculateAnalytics(
                        vehicles: viewModel.araclar,
                        returns: viewModel.iadeIslemleri,
                        officeOperations: viewModel.officeOperations,
                        period: newPeriod
                    )
                }
            }
        }
    }
    
    // MARK: - Insights Section
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights".localized)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                InsightCard(
                    icon: "chart.line.uptrend.xyaxis",
                    text: analytics.topInsight,
                    color: .blue
                )
                
                InsightCard(
                    icon: "exclamationmark.triangle.fill",
                    text: analytics.damageInsight,
                    color: .orange
                )
                
                InsightCard(
                    icon: "arrow.uturn.backward.circle.fill",
                    text: analytics.returnInsight,
                    color: .purple
                )
                
                InsightCard(
                    icon: "building.columns.fill",
                    text: analytics.officeInsight,
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Period Selector
    private var periodSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Period".localized)
                .font(.headline)
                .padding(.horizontal, 4)
            
            Picker("Period".localized, selection: $selectedPeriod) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Text(period.localizedTitle).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    // MARK: - Charts Section
    @available(iOS 16.0, *)
    private var chartsSection: some View {
        VStack(spacing: 24) {
            // Damages Over Time Chart
            damagesChart
            
            // Returns Over Time Chart
            returnsChart
            
            // Office Operations Over Time Chart
            officeOperationsChart
        }
    }
    
    @available(iOS 16.0, *)
    private var damagesChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Damages Over Time".localized)
                    .font(.headline)
                Spacer()
                if let selectedDate = selectedDamageDate,
                   let selectedItem = analytics.damagesData.first(where: { 
                       let calendar = Calendar.current
                       switch selectedPeriod {
                       case .daily:
                           return calendar.isDate($0.date, inSameDayAs: selectedDate)
                       case .weekly:
                           let week1 = calendar.component(.weekOfYear, from: $0.date)
                           let week2 = calendar.component(.weekOfYear, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return week1 == week2 && year1 == year2
                       case .monthly:
                           let month1 = calendar.component(.month, from: $0.date)
                           let month2 = calendar.component(.month, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return month1 == month2 && year1 == year2
                       }
                   }) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selectedItem.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text(selectedItem.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("\(analytics.damagesData.reduce(0) { $0 + $1.count }) " + "total".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Chart(analytics.damagesData) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.orange.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                // Highlight selected point
                if let selectedDate = selectedDamageDate {
                    let calendar = Calendar.current
                    let isSelected: Bool = {
                        switch selectedPeriod {
                        case .daily:
                            return calendar.isDate(item.date, inSameDayAs: selectedDate)
                        case .weekly:
                            let week1 = calendar.component(.weekOfYear, from: item.date)
                            let week2 = calendar.component(.weekOfYear, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return week1 == week2 && year1 == year2
                        case .monthly:
                            let month1 = calendar.component(.month, from: item.date)
                            let month2 = calendar.component(.month, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return month1 == month2 && year1 == year2
                        }
                    }()
                    if isSelected {
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(100)
                    }
                }
            }
            .chartXSelection(value: $selectedDamageDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    @available(iOS 16.0, *)
    private var returnsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Returns Over Time".localized)
                    .font(.headline)
                Spacer()
                if let selectedDate = selectedReturnDate,
                   let selectedItem = analytics.returnsData.first(where: { 
                       let calendar = Calendar.current
                       switch selectedPeriod {
                       case .daily:
                           return calendar.isDate($0.date, inSameDayAs: selectedDate)
                       case .weekly:
                           let week1 = calendar.component(.weekOfYear, from: $0.date)
                           let week2 = calendar.component(.weekOfYear, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return week1 == week2 && year1 == year2
                       case .monthly:
                           let month1 = calendar.component(.month, from: $0.date)
                           let month2 = calendar.component(.month, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return month1 == month2 && year1 == year2
                       }
                   }) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selectedItem.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                        Text(selectedItem.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("\(analytics.returnsData.reduce(0) { $0 + $1.count }) " + "total".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Chart(analytics.returnsData) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.purple.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                // Highlight selected point
                if let selectedDate = selectedReturnDate {
                    let calendar = Calendar.current
                    let isSelected: Bool = {
                        switch selectedPeriod {
                        case .daily:
                            return calendar.isDate(item.date, inSameDayAs: selectedDate)
                        case .weekly:
                            let week1 = calendar.component(.weekOfYear, from: item.date)
                            let week2 = calendar.component(.weekOfYear, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return week1 == week2 && year1 == year2
                        case .monthly:
                            let month1 = calendar.component(.month, from: item.date)
                            let month2 = calendar.component(.month, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return month1 == month2 && year1 == year2
                        }
                    }()
                    if isSelected {
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(100)
                    }
                }
            }
            .chartXSelection(value: $selectedReturnDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    @available(iOS 16.0, *)
    private var officeOperationsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Office Operations Over Time".localized)
                    .font(.headline)
                Spacer()
                if let selectedDate = selectedOfficeDate,
                   let selectedItem = analytics.officeOperationsData.first(where: { 
                       let calendar = Calendar.current
                       switch selectedPeriod {
                       case .daily:
                           return calendar.isDate($0.date, inSameDayAs: selectedDate)
                       case .weekly:
                           let week1 = calendar.component(.weekOfYear, from: $0.date)
                           let week2 = calendar.component(.weekOfYear, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return week1 == week2 && year1 == year2
                       case .monthly:
                           let month1 = calendar.component(.month, from: $0.date)
                           let month2 = calendar.component(.month, from: selectedDate)
                           let year1 = calendar.component(.year, from: $0.date)
                           let year2 = calendar.component(.year, from: selectedDate)
                           return month1 == month2 && year1 == year2
                       }
                   }) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selectedItem.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text(selectedItem.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("\(analytics.officeOperationsData.reduce(0) { $0 + $1.count }) " + "total".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Chart(analytics.officeOperationsData) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.green.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.3), .green.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                // Highlight selected point
                if let selectedDate = selectedOfficeDate {
                    let calendar = Calendar.current
                    let isSelected: Bool = {
                        switch selectedPeriod {
                        case .daily:
                            return calendar.isDate(item.date, inSameDayAs: selectedDate)
                        case .weekly:
                            let week1 = calendar.component(.weekOfYear, from: item.date)
                            let week2 = calendar.component(.weekOfYear, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return week1 == week2 && year1 == year2
                        case .monthly:
                            let month1 = calendar.component(.month, from: item.date)
                            let month2 = calendar.component(.month, from: selectedDate)
                            let year1 = calendar.component(.year, from: item.date)
                            let year2 = calendar.component(.year, from: selectedDate)
                            return month1 == month2 && year1 == year2
                        }
                    }()
                    if isSelected {
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(100)
                    }
                }
            }
            .chartXSelection(value: $selectedOfficeDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Supporting Views

struct InsightCard: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Analytics ViewModel

class AnalyticsViewModel: ObservableObject {
    @Published var damagesData: [TimeSeriesData] = []
    @Published var returnsData: [TimeSeriesData] = []
    @Published var officeOperationsData: [TimeSeriesData] = []
    @Published var topInsight: String = ""
    @Published var damageInsight: String = ""
    @Published var returnInsight: String = ""
    @Published var officeInsight: String = ""
    
    struct TimeSeriesData: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
    }
    
    func calculateAnalytics(
        vehicles: [Arac],
        returns: [IadeIslemi],
        officeOperations: [OfficeOperation],
        period: AnalyticsDashboardView.TimePeriod
    ) {
        calculateDamagesData(vehicles: vehicles, period: period)
        calculateReturnsData(returns: returns, period: period)
        calculateOfficeOperationsData(operations: officeOperations, period: period)
        calculateInsights(vehicles: vehicles, returns: returns, operations: officeOperations, period: period)
    }
    
    private func calculateDamagesData(vehicles: [Arac], period: AnalyticsDashboardView.TimePeriod) {
        let calendar = Calendar.current
        let now = Date()
        var dateRange: (start: Date, end: Date)
        var dateFormatter: DateFormatter
        
        switch period {
        case .daily:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            dateRange = (start, now)
            dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
        case .weekly:
            let start = calendar.date(byAdding: .weekOfYear, value: -12, to: now) ?? now
            dateRange = (start, now)
            dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            dateRange = (start, now)
            dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM yyyy"
        }
        
        var dateCounts: [Date: Int] = [:]
        
        for vehicle in vehicles {
            for damage in vehicle.hasarKayitlari {
                if damage.tarih >= dateRange.start && damage.tarih <= dateRange.end {
                    let key: Date
                    switch period {
                    case .daily:
                        key = calendar.startOfDay(for: damage.tarih)
                    case .weekly:
                        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: damage.tarih)
                        key = calendar.date(from: components) ?? damage.tarih
                    case .monthly:
                        let components = calendar.dateComponents([.year, .month], from: damage.tarih)
                        key = calendar.date(from: components) ?? damage.tarih
                    }
                    dateCounts[key, default: 0] += 1
                }
            }
        }
        
        damagesData = dateCounts
            .map { TimeSeriesData(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    private func calculateReturnsData(returns: [IadeIslemi], period: AnalyticsDashboardView.TimePeriod) {
        let calendar = Calendar.current
        let now = Date()
        var dateRange: (start: Date, end: Date)
        
        switch period {
        case .daily:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            dateRange = (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .weekOfYear, value: -12, to: now) ?? now
            dateRange = (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            dateRange = (start, now)
        }
        
        var dateCounts: [Date: Int] = [:]
        
        for returnItem in returns {
            if returnItem.iadeTarihi >= dateRange.start && returnItem.iadeTarihi <= dateRange.end {
                let key: Date
                switch period {
                case .daily:
                    key = calendar.startOfDay(for: returnItem.iadeTarihi)
                case .weekly:
                    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: returnItem.iadeTarihi)
                    key = calendar.date(from: components) ?? returnItem.iadeTarihi
                case .monthly:
                    let components = calendar.dateComponents([.year, .month], from: returnItem.iadeTarihi)
                    key = calendar.date(from: components) ?? returnItem.iadeTarihi
                }
                dateCounts[key, default: 0] += 1
            }
        }
        
        returnsData = dateCounts
            .map { TimeSeriesData(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    private func calculateOfficeOperationsData(operations: [OfficeOperation], period: AnalyticsDashboardView.TimePeriod) {
        let calendar = Calendar.current
        let now = Date()
        var dateRange: (start: Date, end: Date)
        
        switch period {
        case .daily:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            dateRange = (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .weekOfYear, value: -12, to: now) ?? now
            dateRange = (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
            dateRange = (start, now)
        }
        
        var dateCounts: [Date: Int] = [:]
        
        for operation in operations {
            if operation.date >= dateRange.start && operation.date <= dateRange.end {
                let key: Date
                switch period {
                case .daily:
                    key = calendar.startOfDay(for: operation.date)
                case .weekly:
                    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: operation.date)
                    key = calendar.date(from: components) ?? operation.date
                case .monthly:
                    let components = calendar.dateComponents([.year, .month], from: operation.date)
                    key = calendar.date(from: components) ?? operation.date
                }
                dateCounts[key, default: 0] += 1
            }
        }
        
        officeOperationsData = dateCounts
            .map { TimeSeriesData(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    private func calculateInsights(
        vehicles: [Arac],
        returns: [IadeIslemi],
        operations: [OfficeOperation],
        period: AnalyticsDashboardView.TimePeriod
    ) {
        let calendar = Calendar.current
        let now = Date()
        var currentRange: (start: Date, end: Date)
        var previousRange: (start: Date, end: Date)
        
        switch period {
        case .daily:
            let currentStart = calendar.startOfDay(for: now)
            let currentEnd = now
            let previousStart = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentEnd) ?? currentEnd
            currentRange = (currentStart, currentEnd)
            previousRange = (previousStart, previousEnd)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let currentStart = calendar.date(from: components) ?? now
            let currentEnd = now
            let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: currentEnd) ?? currentEnd
            currentRange = (currentStart, currentEnd)
            previousRange = (previousStart, previousEnd)
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            let currentStart = calendar.date(from: components) ?? now
            let currentEnd = now
            let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .month, value: -1, to: currentEnd) ?? currentEnd
            currentRange = (currentStart, currentEnd)
            previousRange = (previousStart, previousEnd)
        }
        
        // Calculate damages
        let currentDamages = vehicles.flatMap { $0.hasarKayitlari }
            .filter { $0.tarih >= currentRange.start && $0.tarih <= currentRange.end }.count
        let previousDamages = vehicles.flatMap { $0.hasarKayitlari }
            .filter { $0.tarih >= previousRange.start && $0.tarih <= previousRange.end }.count
        
        // Calculate returns
        let currentReturns = returns.filter { $0.iadeTarihi >= currentRange.start && $0.iadeTarihi <= currentRange.end }.count
        let previousReturns = returns.filter { $0.iadeTarihi >= previousRange.start && $0.iadeTarihi <= previousRange.end }.count
        
        // Calculate office operations
        let currentOps = operations.filter { $0.date >= currentRange.start && $0.date <= currentRange.end }.count
        let previousOps = operations.filter { $0.date >= previousRange.start && $0.date <= previousRange.end }.count
        
        // Total damages
        let totalDamages = vehicles.reduce(0) { $0 + $1.hasarKayitlari.count }
        
        // Generate insights
        topInsight = generateTopInsight(
            totalVehicles: vehicles.count,
            totalDamages: totalDamages,
            totalReturns: returns.count
        )
        
        damageInsight = generateChangeInsight(
            current: currentDamages,
            previous: previousDamages,
            type: "damages",
            period: period
        )
        
        returnInsight = generateChangeInsight(
            current: currentReturns,
            previous: previousReturns,
            type: "returns",
            period: period
        )
        
        officeInsight = generateChangeInsight(
            current: currentOps,
            previous: previousOps,
            type: "office operations",
            period: period
        )
    }
    
    private func generateTopInsight(totalVehicles: Int, totalDamages: Int, totalReturns: Int) -> String {
        let loc = LocalizationManager.shared
        if totalVehicles == 0 {
            return loc.string(for: "No vehicles registered yet")
        }
        
        let avgDamagesPerVehicle = Double(totalDamages) / Double(totalVehicles)
        let avgReturnsPerVehicle = Double(totalReturns) / Double(totalVehicles)
        
        if avgDamagesPerVehicle > 2 {
            return String(format: loc.string(for: "High damage rate: %@ damages per vehicle on average"), String(format: "%.1f", avgDamagesPerVehicle))
        } else if avgReturnsPerVehicle > 1 {
            return String(format: loc.string(for: "Active operations: %d returns processed across %d vehicles"), totalReturns, totalVehicles)
        } else {
            return String(format: loc.string(for: "System overview: %d vehicles, %d total damages, %d returns"), totalVehicles, totalDamages, totalReturns)
        }
    }
    
    private func generateChangeInsight(
        current: Int,
        previous: Int,
        type: String,
        period: AnalyticsDashboardView.TimePeriod
    ) -> String {
        let loc = LocalizationManager.shared
        let typeKey: String
        switch type {
        case "damages": typeKey = loc.string(for: "insight.type.damages")
        case "returns": typeKey = loc.string(for: "insight.type.returns")
        default: typeKey = loc.string(for: "insight.type.office_operations")
        }
        let periodText = period.localizedTitle.lowercased()
        
        if previous == 0 {
            if current > 0 {
                return String(format: loc.string(for: "insight.recorded_this"), current, typeKey, periodText)
            } else {
                return String(format: loc.string(for: "insight.no_this"), typeKey, periodText)
            }
        }
        
        let change = current - previous
        let percentChange = abs(Double(change) / Double(previous) * 100)
        let typeCapitalized = typeKey.prefix(1).uppercased() + typeKey.dropFirst()
        
        if change > 0 {
            return String(format: loc.string(for: "insight.increased"), typeCapitalized, change, Float(percentChange), periodText)
        } else if change < 0 {
            return String(format: loc.string(for: "insight.decreased"), typeCapitalized, abs(change), Float(percentChange), periodText)
        } else {
            return String(format: loc.string(for: "insight.stable"), typeCapitalized, current, periodText)
        }
    }
}
