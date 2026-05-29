import SwiftUI
import Charts
import FirebaseFirestore
import FirebaseAuth
import Kingfisher

struct RaporView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var selectedReportCard: ReportCardType?
    
    // Monthly period tracking - defaults to current month
    @State private var selectedMonth: Date = Date()
    @State private var showMonthPicker = false
    @State private var shuttleEntriesCount: Int = 0
    @State private var shuttleEntriesPreviousCount: Int = 0
    @State private var customerInfoScanCount: Int = 0
    @State private var fileLibraryFileCount: Int = 0
    /// Firestore-backed counts when in-memory tail misses older months (Scope-V2 1200-doc cap).
    @State private var serverExitCountForMonth: Int?
    @State private var serverReturnCountForMonth: Int?

    private var damageSource: [HasarKaydi] {
        // Use ALL vehicles (including soft-deleted) to match the web dashboard which
        // also counts damage records from deleted vehicles. Using only `araclar`
        // (non-deleted) causes a ~5 record undercount vs Firebase/web.
        viewModel.allVehiclesForReports.flatMap { $0.hasarKayitlari }
    }
    
    enum ReportCardType: String, CaseIterable, Identifiable {
        case damageReports = "Damage Reports"
        case returnReports = "Return Reports"
        case exitReports = "Check Out Reports"
        case officeOperations = "Office Operations"
        case shuttle = "Shuttle"
        case customerReturns = "Customer Returns"
        case service = "Service"
        case assistantNumbers = "Assistant Numbers"
        case customerInfoScan = "Customer Info Scan"
        case workHours = "Work Hours"
        case recentlyDeleted = "Recently Deleted"
        case documentScan = "Document Scan"
        case files = "Files"
        case vehicleTrack = "Vehicle Track"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .damageReports: return "exclamationmark.triangle.fill"
            case .returnReports: return "arrow.uturn.backward.circle.fill"
            case .exitReports: return "arrow.right.circle.fill"
            case .shuttle: return "bus.fill"
            case .officeOperations: return "briefcase.fill"
            case .customerReturns: return "arrow.uturn.backward.circle.fill"
            case .service: return "wrench.and.screwdriver.fill"
            case .assistantNumbers: return "phone.fill"
            case .customerInfoScan: return "person.text.rectangle.fill"
            case .workHours: return "clock.badge.checkmark"
            case .recentlyDeleted: return "trash.circle.fill"
            case .documentScan: return "doc.text.viewfinder"
            case .files: return "folder.fill"
            case .vehicleTrack: return "arrow.left.arrow.right.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .damageReports: return .orange
            case .returnReports: return .blue
            case .exitReports: return .blue
            case .shuttle: return .cyan
            case .officeOperations: return .blue
            case .customerReturns: return .indigo
            case .service: return .red
            case .assistantNumbers: return .indigo
            case .customerInfoScan: return .teal
            case .workHours: return .orange
            case .recentlyDeleted: return .red
            case .documentScan: return .mint
            case .files: return .teal
            case .vehicleTrack: return .cyan
            }
        }
    }

    /// Report tiles in the grid (TR-only: Customer / office returns tile).
    private var visibleReportCardTypes: [ReportCardType] {
        let trOnly: Set<ReportCardType> = [.customerReturns]
        var list: [ReportCardType]
        if FranchiseCapabilityMatrix.operationsEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) {
            list = ReportCardType.allCases
        } else {
            list = ReportCardType.allCases.filter { !trOnly.contains($0) }
        }
        if !FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) {
            list = list.filter { $0 != .vehicleTrack }
        }
        if !FranchiseCapabilityMatrix.shuttleModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: authManager.userProfile?.countryCode ?? "CH"
        ) {
            list = list.filter { $0 != .shuttle }
        }
        if !FranchiseCapabilityMatrix.fileLibraryEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: authManager.userProfile?.countryCode ?? "CH"
        ) {
            list = list.filter { $0 != .files }
        } else {
            list = list.filter { $0 != .documentScan }
        }
        return list
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                                Color.clear
                    .onAppear {
                        // Scope-V2: Reports needs the full history tail.
                        // Lazy-attach the history listeners only when this screen opens.
                        viewModel.attachExitHistoryListenerIfNeeded()
                        viewModel.attachIadeHistoryListenerIfNeeded()
                        refreshServerReportCounts(for: selectedMonth)
                        }
                    .onChange(of: selectedMonth) { _, newMonth in
                        refreshServerReportCounts(for: newMonth)
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
                            ForEach(visibleReportCardTypes) { cardType in
                                if cardType == .workHours {
                                    WorkHoursReportCard()
                                        .onTapGesture {
                                            HapticManager.shared.medium()
                                            selectedReportCard = cardType
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                } else if cardType == .recentlyDeleted {
                                    RecentlyDeletedReportCard()
                                        .onTapGesture {
                                            HapticManager.shared.medium()
                                            selectedReportCard = cardType
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                } else if cardType == .documentScan {
                                    BigReportCard(
                                        title: cardType.rawValue.localized,
                                        icon: cardType.icon,
                                        color: cardType.color,
                                        count: 0,
                                        kpiMetric: nil
                                    )
                                    .onTapGesture {
                                        HapticManager.shared.medium()
                                        selectedReportCard = cardType
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                } else {
                                    let currentCount = getCount(for: cardType)
                                    let previousCount = getPreviousMonthCount(for: cardType)
                                    let kpiMetric = cardType == .damageReports ? calculateKPIMetric(current: currentCount, previous: previousCount) : nil
                                    
                                    BigReportCard(
                                        title: cardType.rawValue.localized,
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
                        }
                        .padding(.horizontal)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedMonth)
                        
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selectedReportCard) { cardType in
                NavigationStack {
                    reportDetailView(for: cardType, selectedMonth: selectedMonth, dismissFullScreen: { selectedReportCard = nil })
                        .id(selectedMonth) // Force view refresh when month changes
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                monthPickerView
            }
            .onAppear {
                loadShuttleEntriesCount()
                loadCustomerInfoScanCount()
                loadFileLibraryFileCount()
            }
            .onChange(of: selectedMonth) { _ in
                loadShuttleEntriesCount()
                loadCustomerInfoScanCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserChanged"))) { _ in
                // Reset data when user changes
                print("🔄 User changed - resetting RaporView shuttle count")
                shuttleEntriesCount = 0
                shuttleEntriesPreviousCount = 0
                customerInfoScanCount = 0
                fileLibraryFileCount = 0
                loadShuttleEntriesCount()
                loadCustomerInfoScanCount()
                loadFileLibraryFileCount()
            }
        }
    }
    
    // MARK: - Load Shuttle Entries Count
    /// Inclusive calendar month bounds (matches `DailyShuttleReportView` and avoids off-by-one vs half-open ranges).
    private func monthInclusiveRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: components),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) else {
            return (date, date)
        }
        return (monthStart, monthEnd)
    }

    private func loadShuttleEntriesCount() {
        let currentRange = monthInclusiveRange(for: selectedMonth)
        let prevMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let previousRange = monthInclusiveRange(for: prevMonth)

        func fetchCount(range: (start: Date, end: Date), assign: @escaping (Int) -> Void) {
            FirebaseService.shared.getFilteredQuery("shuttleEntries")
                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: range.start))
                .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: range.end))
                .getDocuments { snapshot, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error loading shuttle entries count: \(error.localizedDescription)")
                            assign(0)
                            return
                        }
                        assign(snapshot?.documents.count ?? 0)
                    }
                }
        }

        fetchCount(range: currentRange) { self.shuttleEntriesCount = $0 }
        fetchCount(range: previousRange) { self.shuttleEntriesPreviousCount = $0 }
        print("✅ Shuttle entries count requested for \(selectedMonth) and previous month")
    }

    // MARK: - Load Customer Info Scan Count
    private func loadCustomerInfoScanCount() {
        let dateRange = getMonthDateRange(for: selectedMonth)
        FirebaseService.shared.getFilteredQuery("frontDeskCustomers")
            .whereField("submittedAt", isGreaterThanOrEqualTo: Timestamp(date: dateRange.start))
            .whereField("submittedAt", isLessThan: Timestamp(date: dateRange.end))
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("⚠️ Customer info month count query failed, using fallback: \(error.localizedDescription)")
                        FirebaseService.shared.getFilteredQuery("frontDeskCustomers").getDocuments { fallbackSnapshot, _ in
                            DispatchQueue.main.async {
                                self.customerInfoScanCount = fallbackSnapshot?.documents.count ?? 0
                            }
                        }
                        return
                    }
                    self.customerInfoScanCount = snapshot?.documents.count ?? 0
                }
            }
    }
    
    // MARK: - Load File Library Count
    private func loadFileLibraryFileCount() {
        guard FranchiseCapabilityMatrix.fileLibraryEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: authManager.userProfile?.countryCode ?? "CH"
        ) else {
            fileLibraryFileCount = 0
            return
        }

        FirebaseService.shared.loadFileLibrary { items, error in
            DispatchQueue.main.async {
                if let error {
                    print("⚠️ File library count query failed: \(error.localizedDescription)")
                    self.fileLibraryFileCount = 0
                    return
                }
                self.fileLibraryFileCount = items?.filter { $0.type == .file }.count ?? 0
            }
        }
    }
    
    // MARK: - Fixed Header (Title + Month Selector)
    private var fixedHeader: some View {
        VStack(spacing: 10) {
            // Title row
            HStack(alignment: .firstTextBaseline) {
                Text("Reports".localized)
                    .font(.system(size: 28, weight: .bold, design: .default))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)

            // Month selector — compact pill design
            monthSelectorHeader
        }
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .top)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Month Selector Header (compact pill design)
    private var monthSelectorHeader: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                HapticManager.shared.medium()
                showMonthPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.blue)

                    Text(monthDisplayText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .contentTransition(.numericText())

                    if isCurrentMonth {
                        Capsule()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCurrentMonth ? Color.green.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedMonth)

            Spacer()

            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isCurrentMonth ? Color.secondary.opacity(0.4) : Color.blue)
                    .frame(width: 34, height: 34)
                    .background((isCurrentMonth ? Color.gray : Color.blue).opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
                            "Select Month".localized,
                            selection: $selectedMonth,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .accentColor(.blue)
                    } header: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Choose a month to view reports".localized)
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
                                    Text("Reset to Current Month".localized)
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
                                Text("Month Information".localized)
                                    .font(.headline)
                            }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Selected Month".localized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(monthDisplayText)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                if isCurrentMonth {
                                    Label("Current".localized, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if !isCurrentMonth {
                                let daysDiff = Calendar.current.dateComponents([.day], from: selectedMonth, to: Date()).day ?? 0
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.orange)
                                    Text("\(daysDiff) " + "days ago".localized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Details".localized)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.light()
                        showMonthPicker = false
                    } label: {
                        Text("Done".localized)
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
    /// Returns a half-open interval [startOfMonth, startOfNextMonth) using the device's
    /// local timezone — identical to the web's `new Date(year, month, 1)` approach.
    private func getMonthDateRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)

        guard let startOfMonth = calendar.date(from: components),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            let now = Date()
            let fb = calendar.dateComponents([.year, .month], from: now)
            let s = calendar.date(from: fb) ?? now
            let e = calendar.date(byAdding: .month, value: 1, to: s) ?? now
            return (s, e)
        }

        return (startOfMonth, startOfNextMonth)
    }
    
    @ViewBuilder
    func reportDetailView(for cardType: ReportCardType, selectedMonth: Date, dismissFullScreen: @escaping () -> Void = {}) -> some View {
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
                .environmentObject(authManager)
                .environmentObject(viewModel)
        case .officeOperations:
            OfficeOperationsMainView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
                .environmentObject(authManager)
        case .customerReturns:
            OfficeReturnMainView(selectedMonth: selectedMonth)
                .environmentObject(viewModel)
        case .service:
            ServisView()
                .environmentObject(viewModel)
        case .assistantNumbers:
            AssistantNumberView()
                .environmentObject(viewModel)
        case .customerInfoScan:
            NavigationStack {
                CustomerInfoScanView(onClose: dismissFullScreen)
            }
            .environmentObject(viewModel)
            .environmentObject(authManager)
        case .workHours:
            WorkTimeDetailView(initialMonth: selectedMonth)
                .environmentObject(authManager)
        case .recentlyDeleted:
            RecentlyDeletedDetailView()
                .environmentObject(viewModel)
                .environmentObject(authManager)
        case .documentScan:
            DocumentScanReportView()
        case .files:
            FileLibraryView()
        case .vehicleTrack:
            VehicleTrackReportView(selectedMonth: selectedMonth, onClose: dismissFullScreen)
                .environmentObject(viewModel)
                .environmentObject(authManager)
        }
    }
    
    func getCount(for cardType: ReportCardType) -> Int {
        let dateRange = getMonthDateRange(for: selectedMonth)
        
        switch cardType {
        case .damageReports:
            let filtered = damageSource
                .filter { $0.tarih >= dateRange.start && $0.tarih < dateRange.end }
            let totalAll = damageSource.count
            let allVehicles = viewModel.allVehiclesForReports.count
            let visibleVehicles = viewModel.araclar.count
            print("📊 RaporView.getCount(.damageReports) → current=\(filtered.count), allDamage=\(totalAll), allVehicles=\(allVehicles), visibleVehicles=\(visibleVehicles), range=\(dateRange.start) – \(dateRange.end)")
            return filtered.count
        case .returnReports:
            let local = viewModel.iadeIslemleri.filter {
                ReportTransactionDates.returnIsReportable($0) &&
                ReportTransactionDates.isInHalfOpenRange(
                    ReportTransactionDates.returnDate($0),
                    start: dateRange.start,
                    end: dateRange.end
                )
            }.count
            if let server = serverReturnCountForMonth {
                return max(local, server)
            }
            return local
        case .exitReports:
            let local = viewModel.exitIslemleri.filter {
                ReportTransactionDates.exitIsReportable($0) &&
                ReportTransactionDates.isInHalfOpenRange(
                    ReportTransactionDates.exitDate($0),
                    start: dateRange.start,
                    end: dateRange.end
                )
            }.count
            if let server = serverExitCountForMonth {
                return max(local, server)
            }
            return local
        case .shuttle:
            return shuttleEntriesCount
        case .officeOperations:
            let inc = monthInclusiveRange(for: selectedMonth)
            return viewModel.officeOperations
                .filter { $0.date >= inc.start && $0.date <= inc.end }
                .count
        case .customerReturns:
            return viewModel.officeReturns
                .filter { $0.date >= dateRange.start && $0.date < dateRange.end }
                .count
        case .service:
            return viewModel.servisler.count
        case .assistantNumbers:
            return viewModel.assistantCompanies.count
        case .customerInfoScan:
            return customerInfoScanCount
        case .workHours:
            return 0
        case .recentlyDeleted:
            return 0
        case .documentScan:
            return 0
        case .files:
            return fileLibraryFileCount
        case .vehicleTrack:
            return VehicleTrackReportView.dashboardBadgeCount(
                viewModel: viewModel,
                authManager: authManager,
                range: dateRange
            )
        }
    }

    // MARK: - Previous Month Count
    func getPreviousMonthCount(for cardType: ReportCardType) -> Int {
        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else {
            return 0
        }

        let dateRange = getMonthDateRange(for: previousMonth)

        switch cardType {
        case .damageReports:
            return damageSource
                .filter { $0.tarih >= dateRange.start && $0.tarih < dateRange.end }
                .count
        case .returnReports:
            return viewModel.iadeIslemleri.filter {
                ReportTransactionDates.returnIsReportable($0) &&
                ReportTransactionDates.isInHalfOpenRange(
                    ReportTransactionDates.returnDate($0),
                    start: dateRange.start,
                    end: dateRange.end
                )
            }.count
        case .exitReports:
            return viewModel.exitIslemleri.filter {
                ReportTransactionDates.exitIsReportable($0) &&
                ReportTransactionDates.isInHalfOpenRange(
                    ReportTransactionDates.exitDate($0),
                    start: dateRange.start,
                    end: dateRange.end
                )
            }.count
        case .shuttle:
            return shuttleEntriesPreviousCount
        case .officeOperations:
            let inc = monthInclusiveRange(for: previousMonth)
            return viewModel.officeOperations
                .filter { $0.date >= inc.start && $0.date <= inc.end }
                .count
        case .customerReturns:
            return viewModel.officeReturns
                .filter { $0.date >= dateRange.start && $0.date < dateRange.end }
                .count
        case .vehicleTrack:
            return VehicleTrackReportView.dashboardBadgeCount(
                viewModel: viewModel,
                authManager: authManager,
                range: dateRange
            )
        default:
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

    private func refreshServerReportCounts(for month: Date) {
        let range = getMonthDateRange(for: month)
        serverExitCountForMonth = nil
        serverReturnCountForMonth = nil
        FirebaseService.shared.fetchExitReportCount(from: range.start, to: range.end) { count, _ in
            DispatchQueue.main.async {
                guard Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) else { return }
                serverExitCountForMonth = count
            }
        }
        FirebaseService.shared.fetchReturnReportCount(from: range.start, to: range.end) { count, _ in
            DispatchQueue.main.async {
                guard Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) else { return }
                serverReturnCountForMonth = count
            }
        }
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

// MARK: - Work Hours Report Card (special card without numeric count)
struct WorkHoursReportCard: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text("Work Hours".localized)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Track & export".localized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Recently Deleted Report Card
struct RecentlyDeletedReportCard: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)

            VStack(spacing: 6) {
                Text("Recently Deleted".localized)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Tap to restore".localized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.red.opacity(0.30), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Deleted item JSON → UI snapshot (Recently Deleted list + detail)
private enum DeletedItemSnapshotParser {
    struct Parsed {
        var photos: [String] = []
        var notes: String = ""
        var details: [(String, String)] = []
    }

    static func parse(_ item: DeletedItemRecord) -> Parsed {
        var result = Parsed()
        guard let data = item.dataJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }

        let photoKeys = ["fotograflar", "photos", "imageURLs", "photoURLs"]
        for key in photoKeys {
            if let arr = dict[key] as? [String], !arr.isEmpty {
                result.photos = arr.filter { !$0.isEmpty }
                break
            }
        }

        for key in ["notlar", "notes", "note", "aciklama"] {
            if let n = dict[key] as? String, !n.isEmpty {
                result.notes = n
                break
            }
        }

        switch item.itemType {
        case .iadeIslemi:
            if let plate = dict["aracPlaka"] as? String, !plate.isEmpty { result.details.append(("Plate", plate)) }
            if let km = dict["kmBilgisi"] as? Int { result.details.append(("KM", "\(km)")) }
            else if let km = dict["kmBilgisi"] as? Double { result.details.append(("KM", "\(Int(km))")) }
            if let fuel = dict["yakitDurumu"] as? Int { result.details.append(("Fuel", "\(fuel)/8")) }
            else if let fuel = dict["yakitDurumu"] as? Double { result.details.append(("Fuel", "\(Int(fuel))/8")) }
            if let res = dict["resKodu"] as? String, !res.isEmpty { result.details.append(("RES", res)) }

        case .exitIslemi:
            if let plate = dict["aracPlaka"] as? String, !plate.isEmpty { result.details.append(("Plate", plate)) }
            if let res = dict["resKodu"] as? String, !res.isEmpty { result.details.append(("RES", res)) }
            if let km = dict["kmBilgisi"] as? Int { result.details.append(("KM", "\(km)")) }
            else if let km = dict["kmBilgisi"] as? Double { result.details.append(("KM", "\(Int(km))")) }
            if let fuel = dict["yakitDurumu"] as? Int { result.details.append(("Fuel", "\(fuel)/8")) }
            else if let fuel = dict["yakitDurumu"] as? Double { result.details.append(("Fuel", "\(Int(fuel))/8")) }

        case .officeOperation:
            if let amount = dict["amount"] as? Double {
                result.details.append(("Amount", String(format: "%.2f", amount)))
            }
            if let plate = dict["vehiclePlate"] as? String, !plate.isEmpty {
                result.details.append(("Plate", plate))
            }
            if let typeRaw = dict["type"] as? String, !typeRaw.isEmpty {
                result.details.append(("Operation type", typeRaw))
            }
            if let d = dateFromDict(dict["date"]) {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .short
                result.details.append(("Date", fmt.string(from: d)))
            }
            if let n = dict["posCount"] as? Int, n > 0 { result.details.append(("POS count", "\(n)")) }
            if let arr = dict["posAmounts"] as? [Double], !arr.isEmpty {
                let s = arr.map { String(format: "%.2f", $0) }.joined(separator: ", ")
                result.details.append(("POS amounts", s))
            }
            if let fn = dict["fineNumber"] as? String, !fn.isEmpty { result.details.append(("Fine #", fn)) }
            if let ft = dict["fineType"] as? String, !ft.isEmpty { result.details.append(("Fine type", ft)) }
            if let ps = dict["paymentStatus"] as? String, !ps.isEmpty { result.details.append(("Payment", ps)) }
            if let bn = dict["bankName"] as? String, !bn.isEmpty { result.details.append(("Bank", bn)) }
            if let tn = dict["transactionNumber"] as? String, !tn.isEmpty { result.details.append(("Transaction", tn)) }
            if let pn = dict["productName"] as? String, !pn.isEmpty { result.details.append(("Product", pn)) }
            if let sp = dict["salesPerson"] as? String, !sp.isEmpty { result.details.append(("Sales person", sp)) }

        case .hasarKaydi:
            if let res = dict["resKodu"] as? String, !res.isEmpty { result.details.append(("RES", res)) }
            if let type = dict["hasarTipi"] as? String, !type.isEmpty { result.details.append(("Type", type)) }

        case .arac:
            if let plate = dict["plaka"] as? String, !plate.isEmpty { result.details.append(("Plate", plate)) }
            if let brand = dict["marka"] as? String, !brand.isEmpty { result.details.append(("Brand", brand)) }
        }

        return result
    }

    private static func dateFromDict(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let ts = value as? Timestamp {
            return ts.dateValue()
        }
        if let d = value as? Double {
            return Date(timeIntervalSince1970: d > 1e12 ? d / 1000.0 : d)
        }
        if let i = value as? Int64 {
            let d = Double(i)
            return Date(timeIntervalSince1970: d > 1e12 ? d / 1000.0 : d)
        }
        if let dict = value as? [String: Any],
           let seconds = dict["_seconds"] as? Int64 {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }
}

// MARK: - Recently Deleted — full-screen detail (photos + fields)
private struct RecentlyDeletedItemDetailView: View {
    let item: DeletedItemRecord
    let parsed: DeletedItemSnapshotParser.Parsed
    @Binding var restoringItemId: String?
    var onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: item.itemType.icon)
                        .font(.title2)
                        .foregroundColor(.red.opacity(0.85))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(item.itemType.label))
                            .font(.headline)
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Deletion".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("\(item.deletedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.deletedByName)")
                        .font(.caption)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if !parsed.details.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Details".localized)
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(parsed.details.enumerated()), id: \.offset) { _, pair in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pair.0)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(pair.1)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                if !parsed.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes".localized)
                            .font(.headline)
                        Text(parsed.notes)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                if !parsed.photos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Photos".localized)
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(parsed.photos, id: \.self) { url in
                                    KFImage(URL(string: url))
                                        .placeholder {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.systemGray5))
                                                .frame(width: 220, height: 180)
                                                .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                        }
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 220, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }

                if restoringItemId == item.id {
                    HStack {
                        ProgressView()
                        Text("Restoring…".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        onRestore()
                    } label: {
                        Text("Restore".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Deleted item".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recently Deleted Detail View
struct RecentlyDeletedDetailView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var deletedItems: [DeletedItemRecord] = []
    @State private var isLoading = false
    @State private var restoringItemId: String? = nil
    @State private var selectedTypeFilter: DeletedItemRecord.DeletedItemType? = nil
    @State private var searchText: String = ""

    private var currentFranchiseId: String {
        let fromService = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !fromService.isEmpty { return fromService }
        return (authManager.userProfile?.resolvedFranchiseIdForDataAccess() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("Loading...".localized)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if deletedItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trash.slash.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No recently deleted items.".localized)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Deleted returns, exits, office operations, and other records appear here for 30 days.".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                filterChip(title: "All".localized, selected: selectedTypeFilter == nil) {
                                    selectedTypeFilter = nil
                                }
                                ForEach(DeletedItemRecord.DeletedItemType.allCases, id: \.rawValue) { t in
                                    filterChip(title: t.label.localized, selected: selectedTypeFilter == t) {
                                        selectedTypeFilter = t
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        TextField("Search deleted item".localized, text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(filteredItems) { item in
                        HStack(alignment: .center, spacing: 8) {
                            NavigationLink {
                                RecentlyDeletedItemDetailView(
                                    item: item,
                                    parsed: DeletedItemSnapshotParser.parse(item),
                                    restoringItemId: $restoringItemId,
                                    onRestore: { restoreItem(item) }
                                )
                            } label: {
                                deletedItemSummaryRow(item)
                            }

                            if restoringItemId == item.id {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Button {
                                    restoreItem(item)
                                } label: {
                                    Text("Restore".localized)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recently Deleted".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        loadDeletedItems()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .disabled(isLoading)
                    if !filteredItems.isEmpty {
                        Button("Restore All".localized) {
                            restoreAllFilteredItems()
                        }
                        .fontWeight(.semibold)
                        .disabled(restoringItemId != nil)
                    }
                    Button("Done".localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadDeletedItems() }
    }

    private var filteredItems: [DeletedItemRecord] {
        deletedItems.filter { item in
            let typeOK = selectedTypeFilter == nil || item.itemType == selectedTypeFilter
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let textOK = q.isEmpty
                || item.description.lowercased().contains(q)
                || item.deletedByName.lowercased().contains(q)
                || item.itemType.label.lowercased().contains(q)
            return typeOK && textOK
        }
    }

    @ViewBuilder
    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.blue : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func deletedItemSummaryRow(_ item: DeletedItemRecord) -> some View {
        let parsedData = DeletedItemSnapshotParser.parse(item)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: item.itemType.icon)
                    .font(.system(size: 18))
                    .foregroundColor(.red.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.description)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(item.itemType.label))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.75), in: Capsule())
                    Text(item.deletedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("· \(item.deletedByName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !parsedData.photos.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("\(parsedData.photos.count) \(parsedData.photos.count == 1 ? "photo" : "photos")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func loadDeletedItems() {
        guard !currentFranchiseId.isEmpty else { return }
        isLoading = true
        let db = Firestore.firestore()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        db.collection("franchises").document(currentFranchiseId)
            .collection("deletedItems")
            .whereField("deletedAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .order(by: "deletedAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.deletedItems = snapshot?.documents
                        .compactMap { try? $0.data(as: DeletedItemRecord.self) } ?? []
                }
            }
    }

    private func restoreItem(_ item: DeletedItemRecord) {
        guard !currentFranchiseId.isEmpty else { return }
        restoringItemId = item.id
        let db = Firestore.firestore()
        guard let jsonData = item.dataJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            restoringItemId = nil
            return
        }
        restoreByType(item: item, rawDict: dict, db: db) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.restoringItemId = nil
                    ToastManager.shared.show("Restore failed: \(error.localizedDescription)", type: .error)
                } else {
                    if let docId = item.documentId {
                        db.collection("franchises").document(self.currentFranchiseId)
                            .collection("deletedItems").document(docId)
                            .delete { _ in
                                DispatchQueue.main.async {
                                    self.restoringItemId = nil
                                    self.deletedItems.removeAll { $0.id == item.id }
                                    ToastManager.shared.show("Item restored successfully", type: .success)
                                }
                            }
                    } else {
                        self.restoringItemId = nil
                        ToastManager.shared.show("Item restored successfully", type: .success)
                    }
                }
            }
        }
    }

    private func restoreAllFilteredItems() {
        guard !filteredItems.isEmpty else { return }
        restoreNext(index: 0, items: filteredItems)
    }

    private func restoreNext(index: Int, items: [DeletedItemRecord]) {
        guard index < items.count else {
            ToastManager.shared.show("All selected items restored", type: .success)
            loadDeletedItems()
            return
        }
        let item = items[index]
        restoreItem(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            restoreNext(index: index + 1, items: items)
        }
    }

    private func restoreByType(
        item: DeletedItemRecord,
        rawDict: [String: Any],
        db: Firestore,
        completion: @escaping (Error?) -> Void
    ) {
        switch item.itemType {
        case .hasarKaydi:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            guard let data = item.dataJSON.data(using: .utf8),
                  let hasar = try? decoder.decode(HasarKaydi.self, from: data) else {
                completion(NSError(domain: "restore", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Damage payload decode failed"]))
                return
            }
            if let vehicle = viewModel.araclar.first(where: { $0.id == hasar.aracId }),
               vehicle.hasarKayitlari.contains(where: { $0.id == hasar.id }) {
                viewModel.hasarGuncelle(aracId: hasar.aracId, hasar: hasar)
            } else {
                viewModel.hasarEkle(aracId: hasar.aracId, hasar: hasar)
            }
            completion(nil)
        default:
            let payload = makeFirestoreCompatiblePayload(rawDict)
            let docRef = db.document("\(item.originalCollectionPath)/\(item.originalDocumentId)")
            docRef.setData(payload, merge: false, completion: completion)
        }
    }

    private func makeFirestoreCompatiblePayload(_ dict: [String: Any]) -> [String: Any] {
        var output = dict
        let dateLikeKeys = [
            "createdAt", "updatedAt", "deletedAt", "tarih", "iadeTarihi",
            "createdDate", "date", "handoverTarihi", "lastUpdated", "timestamp", "checkInDate"
        ]
        for key in dateLikeKeys {
            if let value = output[key] {
                if let ms = value as? Double {
                    output[key] = Timestamp(date: Date(timeIntervalSince1970: ms / 1000.0))
                } else if let ms = value as? Int64 {
                    output[key] = Timestamp(date: Date(timeIntervalSince1970: Double(ms) / 1000.0))
                } else if let ms = value as? Int {
                    output[key] = Timestamp(date: Date(timeIntervalSince1970: Double(ms) / 1000.0))
                }
            }
        }
        return output
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
        .navigationTitle("Office Statistics".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
    
    private var totalOverviewCard: some View {
        VStack(spacing: 16) {
            // 4 Cards in 2x2 grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatisticCard(
                    title: "Total Amount".localized,
                    value: AppCurrency.amountWithCode(totalAmount),
                    icon: "eurosign.circle.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Credit Card".localized,
                    value: AppCurrency.amountWithCode(viewModel.totalCreditCardAmount),
                    icon: "creditcard.fill",
                    color: .purple
                )
                
                StatisticCard(
                    title: "POS Total".localized,
                    value: AppCurrency.amountWithCode(viewModel.totalPOSAmount),
                    icon: "centsign.circle.fill",
                    color: .green
                )
                
                StatisticCard(
                    title: "Operations".localized,
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
            Text("Amount by Type".localized)
                .font(.title2)
                .fontWeight(.bold)
            
            Chart(typeBreakdown, id: \.type) { item in
                BarMark(
                    x: .value("Amount", item.amount),
                    y: .value("Type", item.type.rawValue)
                )
                .foregroundStyle(by: .value("Type", item.type.rawValue))
                .annotation(position: .trailing) {
                    Text(AppCurrency.amountWithCode(item.amount, fractionDigits: 0))
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
            Text("Daily Trend (Last 30 Days)".localized)
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
                Text("No data available".localized)
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
            Text("Monthly Breakdown".localized)
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
                        Text(AppCurrency.code)
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
            Text("Statistics".localized)
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
                Text(AppCurrency.amountWithCode(amount))
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

// MARK: - Shared Report Date Filtering
enum ReportDateFilterPreset: String, CaseIterable {
    case all = "All"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

private func reportMonthStart(_ date: Date) -> Date {
    let cal = Calendar.current
    return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
}

private func makePresetDateRange(_ preset: ReportDateFilterPreset, selectedMonth: Date) -> (start: Date, end: Date) {
    let calendar = Calendar.current
    let now = Date()
    switch preset {
    case .all:
        return (.distantPast, .distantFuture)
    case .daily:
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        return (start, end)
    case .weekly:
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return (start, now)
    case .monthly:
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) else {
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        }
        return (monthStart, monthEnd)
    }
}

private func makeReportFilterDateRange(preset: ReportDateFilterPreset, filterMonth: Date) -> (start: Date, end: Date) {
    makePresetDateRange(preset, selectedMonth: filterMonth)
}

private func reportDateMatchesFilter(
    _ value: Date,
    preset: ReportDateFilterPreset,
    filterMonth: Date
) -> Bool {
    let range = makeReportFilterDateRange(preset: preset, filterMonth: filterMonth)
    return value >= range.start && value <= range.end
}

private func reportFilterSummaryText(preset: ReportDateFilterPreset, filterMonth: Date) -> String {
    if preset == .monthly {
        return filterMonth.formatted(.dateTime.month(.wide).year())
    }
    return preset.rawValue.localized
}

struct ReportDateFilterControls: View {
    @Binding var preset: ReportDateFilterPreset
    @Binding var filterMonth: Date
    @Binding var showMonthPicker: Bool

    var body: some View {
        VStack(spacing: 10) {
            Picker("Date Filter".localized, selection: $preset) {
                ForEach(ReportDateFilterPreset.allCases, id: \.self) { filter in
                    Text(filter.rawValue.localized).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Text(reportFilterSummaryText(preset: preset, filterMonth: filterMonth))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    showMonthPicker = true
                } label: {
                    Label("Select month".localized, systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct ReportMonthPickerSheet: View {
    @Binding var filterMonth: Date
    @Environment(\.dismiss) private var dismiss
    @State private var pickedMonth: Date

    init(filterMonth: Binding<Date>) {
        _filterMonth = filterMonth
        _pickedMonth = State(initialValue: filterMonth.wrappedValue)
    }

    var body: some View {
        NavigationView {
            DatePicker(
                "",
                selection: $pickedMonth,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .navigationTitle("Select month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) {
                        filterMonth = reportMonthStart(pickedMonth)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Damage Reports View
struct DamageReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var searchQuery = ""
    @State private var dateFilterPreset: ReportDateFilterPreset = .all
    @State private var filterMonth: Date
    @State private var showMonthPicker = false
    @State private var showPDFExportSheet = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false

    init(selectedMonth: Date = Date()) {
        self.selectedMonth = selectedMonth
        _filterMonth = State(initialValue: reportMonthStart(selectedMonth))
    }
    
    var dateRange: (start: Date, end: Date) {
        makeReportFilterDateRange(preset: dateFilterPreset, filterMonth: filterMonth)
    }
    
    var filteredDamages: [(arac: Arac, hasar: HasarKaydi)] {
        var results: [(Arac, HasarKaydi)] = []
        
        for arac in viewModel.araclar {
            for hasar in arac.hasarKayitlari {
                let matchesSearch = searchQuery.isEmpty || 
                    arac.plaka.localizedCaseInsensitiveContains(searchQuery) ||
                    hasar.resKodu.localizedCaseInsensitiveContains(searchQuery)
                let matchesDate = reportDateMatchesFilter(
                    hasar.tarih,
                    preset: dateFilterPreset,
                    filterMonth: filterMonth
                )
                
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dateFilterPreset)
        .navigationTitle("Damage Reports".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showPDFExportSheet = true
                    } label: {
                        Label("Export PDF".localized, systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done".localized) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPDFExportSheet) {
            PDFExportDateRangeView(
                title: "Export Damage Report".localized,
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
        .sheet(isPresented: $showMonthPicker) {
            ReportMonthPickerSheet(filterMonth: $filterMonth)
        }
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = damageStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview".localized)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                DamageMetricCard(
                    title: "Total".localized,
                    value: "\(stats.total)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "Completed".localized,
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "In Progress".localized,
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                DamageMetricCard(
                    title: "Photos".localized,
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .orange
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
                Text("Ara".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search by plate or RES code".localized, text: $searchQuery)
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
            
            ReportDateFilterControls(
                preset: $dateFilterPreset,
                filterMonth: $filterMonth,
                showMonthPicker: $showMonthPicker
            )
            .sensoryFeedback(.selection, trigger: dateFilterPreset)
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
            
                    Text("No Damage Records Found".localized)
                        .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter".localized)
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
                    Text("Select Date Range".localized)
                } footer: {
                    Text("Export all records within the selected date range as PDF".localized)
                }
                
                Section {
                    Button {
                        onExport(startDate, endDate)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Export PDF".localized)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel".localized) {
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
    @State private var dateFilterPreset: ReportDateFilterPreset
    @State private var filterMonth: Date
    @State private var showMonthPicker = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var showPDFExportSheet = false

    init(selectedMonth: Date = Date()) {
        self.selectedMonth = selectedMonth
        _filterMonth = State(initialValue: reportMonthStart(selectedMonth))
        _dateFilterPreset = State(initialValue: .monthly)
    }
    
    var dateRange: (start: Date, end: Date) {
        makeReportFilterDateRange(preset: dateFilterPreset, filterMonth: filterMonth)
    }
    
    var filteredReturns: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { iade in
            guard ReportTransactionDates.returnIsReportable(iade) else { return false }
            let matchesSearch = searchQuery.isEmpty || iade.aracPlaka.localizedCaseInsensitiveContains(searchQuery) || iade.notlar.localizedCaseInsensitiveContains(searchQuery)
            let matchesDate = reportDateMatchesFilter(
                ReportTransactionDates.returnDate(iade),
                preset: dateFilterPreset,
                filterMonth: filterMonth
            )
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
        .navigationTitle("Return Reports".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showPDFExportSheet = true
                    } label: {
                        Label("Export PDF".localized, systemImage: "doc.richtext")
                    }
                    
                    Button {
                        exportReturnXLSX()
                    } label: {
                        Label("Export Excel".localized, systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showPDFExportSheet) {
            PDFExportDateRangeView(
                title: "Export Return Report".localized,
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dateFilterPreset)
        .sheet(isPresented: $showMonthPicker) {
            ReportMonthPickerSheet(filterMonth: $filterMonth)
        }
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = returnStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview".localized)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ReturnMetricCard(
                    title: "Total".localized,
                    value: "\(stats.total)",
                    icon: "arrow.uturn.backward.circle.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Photos".localized,
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "In Progress".localized,
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Completed".localized,
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .blue
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
                Text("Ara".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search by plate or notes".localized, text: $searchQuery)
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
            
            ReportDateFilterControls(
                preset: $dateFilterPreset,
                filterMonth: $filterMonth,
                showMonthPicker: $showMonthPicker
            )
            .sensoryFeedback(.selection, trigger: dateFilterPreset)
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
            
            Text("No Return Reports Found".localized)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter".localized)
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
        HStack(spacing: 12) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(iade.aracPlaka)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !iade.notlar.isEmpty {
                            Text(iade.notlar)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(iade.iadeTarihi.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    if !iade.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("\(iade.fotograflar.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 2, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        iade.status == .inProgress ? .orange : .green
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(iade.status == .inProgress ? "Saved".localized : "Done".localized)
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
                    Text("Damaged Vehicles by Category".localized)
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
                    Text("Office Operations Total".localized)
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
                                Text(AppCurrency.amountWithCode(item.amount))
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
                    Text("Recent Returns".localized)
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

// MARK: - Exit Reports View
struct ExitReportsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var searchQuery = ""
    @State private var dateFilterPreset: ReportDateFilterPreset
    @State private var filterMonth: Date
    @State private var showMonthPicker = false

    init(selectedMonth: Date = Date()) {
        self.selectedMonth = selectedMonth
        _filterMonth = State(initialValue: reportMonthStart(selectedMonth))
        _dateFilterPreset = State(initialValue: .monthly)
    }
    
    var dateRange: (start: Date, end: Date) {
        makeReportFilterDateRange(preset: dateFilterPreset, filterMonth: filterMonth)
    }
    
    var filteredExits: [ExitIslemi] {
        viewModel.exitIslemleri.filter { exit in
            guard !exit.isDeleted else { return false }
            let matchesSearch = searchQuery.isEmpty || 
                exit.aracPlaka.localizedCaseInsensitiveContains(searchQuery) || 
                exit.notlar.localizedCaseInsensitiveContains(searchQuery) ||
                exit.resKodu.localizedCaseInsensitiveContains(searchQuery)
            // Exit raporunda kullanıcıya gösterilen işlem tarihiyle filtrele.
            let filterTarihi = exit.exitTarihi
            let matchesDate = reportDateMatchesFilter(
                filterTarihi,
                preset: dateFilterPreset,
                filterMonth: filterMonth
            )
            return matchesSearch && matchesDate
        }.sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    // MARK: - Statistics
    var exitStatistics: (total: Int, totalPhotos: Int, inProgress: Int, completed: Int) {
        let exits = filteredExits
        let total = exits.count
        let totalPhotos = exits.reduce(0) { $0 + $1.fotograflar.count }
        let inProgress = exits.filter { $0.status == .inProgress }.count
        let completed = exits.filter { $0.status == .completed }.count
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
        .navigationTitle("Check Out Reports".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            ReportMonthPickerSheet(filterMonth: $filterMonth)
        }
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        let stats = exitStatistics
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Overview".localized)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ReturnMetricCard(
                    title: "Total".localized,
                    value: "\(stats.total)",
                    icon: "arrow.right.circle.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Photos".localized,
                    value: "\(stats.totalPhotos)",
                    icon: "photo.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "In Progress".localized,
                    value: "\(stats.inProgress)",
                    icon: "clock.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ReturnMetricCard(
                    title: "Completed".localized,
                    value: "\(stats.completed)",
                    icon: "checkmark.circle.fill",
                    color: .blue
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
                TextField("Search by plate, notes or RES code...".localized, text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            ReportDateFilterControls(
                preset: $dateFilterPreset,
                filterMonth: $filterMonth,
                showMonthPicker: $showMonthPicker
            )
            .sensoryFeedback(.selection, trigger: dateFilterPreset)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Exit List Section
    private var exitListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredExits, id: \.listStableId) { exit in
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
            
            Text("No Check Out Reports Found".localized)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or date filter".localized)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Exit Row View
struct ExitSatirView: View {
    let exit: ExitIslemi
    /// Vehicle detail list: keep rows compact (no km/fuel line). Reports can show the extra line.
    var showKmFuelLine: Bool = true
    /// Pending check-out: orange outer stroke so “waiting” is visible at a glance.
    var emphasizePendingOutline: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    private var isTurkeyFranchise: Bool {
        exit.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("TR")
    }

    private var isGermanyFranchise: Bool {
        exit.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("DE")
    }
    
    private var displayResCode: String {
        let r = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return exit.aracPlaka }
        var upper = r.uppercased()
        while upper.hasPrefix("RES-") || upper.hasPrefix("RNT-") || upper.hasPrefix("NAV-") {
            upper = String(upper.dropFirst(4))
        }
        let suffix = upper
        if suffix.isEmpty { return exit.aracPlaka }
        if isTurkeyFranchise { return "NAV-\(suffix)" }
        if isGermanyFranchise { return "RNT-\(suffix)" }
        return "RES-\(suffix)"
    }

    private var isFrontDeskIntakeNote: Bool {
        exit.notlar.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Front desk intake:")
    }

    private var kmFuelSubtitle: String? {
        var parts: [String] = []
        if let km = exit.km { parts.append("\(km) km") }
        if let y = exit.yakitSeviyesi?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty {
            parts.append(y)
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    private var displayNotesLine: String? {
        let n = exit.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || isFrontDeskIntakeNote { return nil }
        return n
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon - Yeşil araç ikonu
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayResCode)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(exit.aracPlaka)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        if showKmFuelLine, let kmFuel = kmFuelSubtitle {
                            Text(kmFuel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let note = displayNotesLine {
                            Text(note)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(exit.exitTarihi.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    if !exit.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("\(exit.fotograflar.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 2, x: 0, y: 1)
                .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    emphasizePendingOutline && exit.status == .inProgress ? Color.orange : Color.clear,
                    lineWidth: emphasizePendingOutline && exit.status == .inProgress ? 2.5 : 0
                )
        )
    }
    
    private var statusColor: Color {
        switch exit.status {
        case .completed, .parked:
            return .green
        case .inProgress:
            return .orange
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(statusText)
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
    
    private var statusText: String {
        switch exit.status {
        case .completed, .parked:
            return "Done".localized
        case .inProgress:
            return "Saved".localized
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
