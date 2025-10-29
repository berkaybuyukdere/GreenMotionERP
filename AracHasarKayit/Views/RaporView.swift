import SwiftUI
import Charts

struct RaporView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var selectedReportCard: ReportCardType?
    
    enum ReportCardType: String, CaseIterable, Identifiable {
        case damageReports = "Damage Reports"
        case returnReports = "Return Reports"
        case shuttle = "Shuttle"
        case officeOperations = "Office Operations"
        case officeStatistics = "Office Statistics"
        case service = "Service"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .damageReports: return "exclamationmark.triangle.fill"
            case .returnReports: return "arrow.uturn.backward.circle.fill"
            case .shuttle: return "bus.fill"
            case .officeOperations: return "briefcase.fill"
            case .officeStatistics: return "chart.bar.fill"
            case .service: return "wrench.and.screwdriver.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .damageReports: return .orange
            case .returnReports: return .purple
            case .shuttle: return .cyan
            case .officeOperations: return .blue
            case .officeStatistics: return .green
            case .service: return .red
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Report Cards
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            ForEach(ReportCardType.allCases) { cardType in
                                BigReportCard(
                                    title: cardType.rawValue,
                                    icon: cardType.icon,
                                    color: cardType.color,
                                    count: getCount(for: cardType)
                                )
                                .onTapGesture {
                                    selectedReportCard = cardType
                                }
                            }
                        }
                        .padding(.horizontal)
                        
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
            .navigationTitle("Reports")
            .fullScreenCover(item: $selectedReportCard) { cardType in
                NavigationView {
                    reportDetailView(for: cardType)
                }
            }
        }
    }
    
    @ViewBuilder
    func reportDetailView(for cardType: ReportCardType) -> some View {
        switch cardType {
        case .damageReports:
            DamageReportsView()
                .environmentObject(viewModel)
        case .returnReports:
            ReturnReportsView()
                .environmentObject(viewModel)
        case .shuttle:
            ShuttleMainView()
        case .officeOperations:
            OfficeOperationsMainView()
                .environmentObject(viewModel)
        case .officeStatistics:
            OfficeStatisticsChartView()
                .environmentObject(viewModel)
        case .service:
            ServisView()
        }
    }
    
    func getCount(for cardType: ReportCardType) -> Int {
        switch cardType {
        case .damageReports:
            return viewModel.araclar.flatMap { $0.hasarKayitlari }.count
        case .returnReports:
            return viewModel.iadeIslemleri.count
        case .shuttle:
            // Count active session + today's entries (real-time)
            let activeCount = shuttleManager.currentSession != nil ? 1 : 0
            return shuttleManager.todayEntries.count + activeCount
        case .officeOperations:
            return viewModel.officeOperations.count
        case .officeStatistics:
            return viewModel.officeOperations.count
        case .service:
            return viewModel.servisler.count
        }
    }
}

struct BigReportCard: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(20)
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
    @State private var searchPlate = ""
    @State private var searchRES = ""
    @State private var dateFilter: DateFilterType = .weekly
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showCustomDatePicker = false
    
    enum DateFilterType: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case custom = "Custom"
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch dateFilter {
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .custom:
            return (customStartDate, customEndDate)
        }
    }
    
    var filteredDamages: [(arac: Arac, hasar: HasarKaydi)] {
        var results: [(Arac, HasarKaydi)] = []
        
        for arac in viewModel.araclar {
            for hasar in arac.hasarKayitlari {
                let matchesPlate = searchPlate.isEmpty || arac.plaka.localizedCaseInsensitiveContains(searchPlate)
                let matchesRES = searchRES.isEmpty || hasar.resKodu.localizedCaseInsensitiveContains(searchRES)
                let matchesDate = hasar.tarih >= dateRange.start && hasar.tarih <= dateRange.end
                
                if matchesPlate && matchesRES && matchesDate {
                    results.append((arac, hasar))
                }
            }
        }
        
        return results.sorted(by: { $0.1.tarih > $1.1.tarih })
    }
    
    var plateSuggestions: [String] {
        if searchPlate.isEmpty { return [] }
        return viewModel.araclar
            .map { $0.plakaFormatli }
            .filter { $0.localizedCaseInsensitiveContains(searchPlate) }
            .prefix(5)
            .map { String($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Search by plate", text: $searchPlate)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                        
                        if !plateSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(plateSuggestions, id: \.self) { plate in
                                    Button {
                                        searchPlate = plate
                                    } label: {
                                        Text(plate)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider()
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                    }
                    
                    TextField("Search by RES", text: $searchRES)
                        .textFieldStyle(.roundedBorder)
                }
                
                Picker("Date Filter", selection: $dateFilter) {
                    ForEach(DateFilterType.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dateFilter) { newValue in
                    if newValue == .custom {
                        showCustomDatePicker = true
                    }
                }
            }
            .padding()
            
            Divider()
            
            if filteredDamages.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No Damage Records Found")
                        .font(.headline)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredDamages, id: \.hasar.id) { item in
                        NavigationLink(destination: HasarDetayView(hasar: item.hasar, aracId: item.arac.id, aracPlaka: item.arac.plakaFormatli)) {
                            DamageReportRow(arac: item.arac, hasar: item.hasar)
                        }
                    }
                }
            }
        }
        .navigationTitle("Damage Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showCustomDatePicker) {
            NavigationView {
                Form {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                }
                .navigationTitle("Custom Date Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showCustomDatePicker = false }
                    }
                }
            }
        }
    }
}

struct DamageReportRow: View {
    let arac: Arac
    let hasar: HasarKaydi
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(arac.plakaFormatli) â€¢ \(hasar.resKodu)")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(hasar.km) km", systemImage: "gauge.medium")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("\(hasar.fotograflar.count)", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: hasar.durum == .done ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundColor(hasar.durum == .done ? .green : .yellow)
        }
    }
}

// MARK: - Return Reports View
struct ReturnReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchPlate = ""
    @State private var dateFilter: DateFilterType = .weekly
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showCustomDatePicker = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    
    enum DateFilterType: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case custom = "Custom"
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch dateFilter {
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .custom:
            return (customStartDate, customEndDate)
        }
    }
    
    var filteredReturns: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { iade in
            let matchesPlate = searchPlate.isEmpty || iade.aracPlaka.localizedCaseInsensitiveContains(searchPlate)
            let matchesDate = iade.iadeTarihi >= dateRange.start && iade.iadeTarihi <= dateRange.end
            return matchesPlate && matchesDate
        }.sorted(by: { $0.iadeTarihi > $1.iadeTarihi })
    }
    
    var plateSuggestions: [String] {
        if searchPlate.isEmpty { return [] }
        return viewModel.araclar
            .map { $0.plakaFormatli }
            .filter { $0.localizedCaseInsensitiveContains(searchPlate) }
            .prefix(5)
            .map { String($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Search by plate", text: $searchPlate)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                    
                    if !plateSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(plateSuggestions, id: \.self) { plate in
                                Button {
                                    searchPlate = plate
                                } label: {
                                    Text(plate)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Divider()
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .shadow(radius: 4)
                    }
                }
                
                Picker("Date Filter", selection: $dateFilter) {
                    ForEach(DateFilterType.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dateFilter) { newValue in
                    if newValue == .custom {
                        showCustomDatePicker = true
                    }
                }
            }
            .padding()
            
            Divider()
            
            if filteredReturns.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No Return Reports Found")
                        .font(.headline)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Total Returns")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(filteredReturns.count)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Photos")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(filteredReturns.flatMap { $0.fotograflar }.count)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            HStack(spacing: 16) {
                                Button {
                                    exportReturnPDF()
                                } label: {
                                    HStack {
                                        if isExporting {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "doc.richtext")
                                        }
                                        Text("Export PDF")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(10)
                                }
                                .disabled(isExporting)
                                
                                Button {
                                    exportReturnXLSX()
                                } label: {
                                    HStack {
                                        if isExporting {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "tablecells")
                                        }
                                        Text("Export Excel")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(10)
                                }
                                .disabled(isExporting)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section("Return Operations") {
                        ForEach(filteredReturns) { iade in
                            NavigationLink(destination: IadeDetayView(iade: iade)) {
                                IadeSatirView(iade: iade)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Return Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showCustomDatePicker) {
            NavigationView {
                Form {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                }
                .navigationTitle("Custom Date Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showCustomDatePicker = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }
    
    func exportReturnPDF() {
        isExporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = IadeRaporManager.shared.generatePDF(iadeler: filteredReturns)
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
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3)
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(iade.aracPlaka)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !iade.notlar.isEmpty {
                    Text(iade.notlar)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    Label {
                        Text(iade.iadeTarihi.formatted(date: .abbreviated, time: .shortened))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if !iade.fotograflar.isEmpty {
                        Label("\(iade.fotograflar.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Status badge
            VStack(spacing: 2) {
                if iade.status == .inProgress {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    Text("Saved")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("Done")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(iade.status == .inProgress ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
            .cornerRadius(10)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
