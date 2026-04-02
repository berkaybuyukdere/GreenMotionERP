import SwiftUI

enum VacationViewMode {
    case monthly
    case yearly
}

// Scroll offset preference key for detecting scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct VacationTimesView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedMonth = Date()
    @State private var selectedYear = Date()
    @State private var viewMode: VacationViewMode = .monthly
    @State private var showAddVacation = false
    @State private var editingVacation: VacationTime?
    @State private var selectedEmployee: String?
    @State private var isEmployeesExpanded = true // Start expanded by default
    
    private let holidaysHelper = SwissHolidaysHelper.shared
    
    // Get unique employee names from vacation times
    private var employeeNames: [String] {
        let names = Set(viewModel.vacationTimes.map { $0.employeeName })
        return Array(names).sorted()
    }
    
    // Get month range
    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        let start = calendar.date(from: components) ?? selectedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: start) ?? selectedMonth
        return (start, end)
    }
    
    // Get all dates in the month
    private var monthDates: [Date] {
        let calendar = Calendar.current
        let (start, end) = monthRange
        var dates: [Date] = []
        var current = start
        
        while current <= end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }
        
        return dates
    }
    
    // Get vacation dates for selected employee in current month
    private var selectedEmployeeVacationDates: [Date] {
        guard let employee = selectedEmployee else { return [] }
        let (start, end) = monthRange
        var dates: [Date] = []
        
        let vacations = viewModel.vacationTimes.filter { vacation in
            vacation.employeeName == employee &&
            vacation.isActive &&
            vacation.startDate <= end &&
            vacation.endDate >= start
        }
        
        for vacation in vacations {
            var current = max(vacation.startDate, start)
            let vacationEnd = min(vacation.endDate, end)
            
            while current <= vacationEnd {
                dates.append(current)
                current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? vacationEnd
            }
        }
        
        return dates
    }
    
    // Check if employee is on vacation on a specific date
    private func isEmployeeOnVacation(_ employeeName: String, on date: Date) -> Bool {
        return viewModel.vacationTimes.contains { vacation in
            vacation.employeeName == employeeName && vacation.contains(date: date)
        }
    }
    
    // Get vacation for employee on a specific date
    private func getVacation(for employeeName: String, on date: Date) -> VacationTime? {
        return viewModel.vacationTimes.first { vacation in
            vacation.employeeName == employeeName && vacation.contains(date: date)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // View mode selector
                viewModeSelector
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                
                Divider()
                
                // Main content - Calendar takes full width and fits screen
                ScrollView {
                    VStack(spacing: 0) {
                        if viewMode == .monthly {
                            monthlyCalendarSection
                                .padding()
                        } else {
                            yearlyCalendarSection
                                .padding()
                        }
                        
                        // Employees section - always visible at bottom
                        employeesCollapsibleSection
                            .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Vacation Times".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back".localized)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Navigation buttons
                    if viewMode == .monthly {
                        Button {
                            selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.blue)
                        }
                        
                        Button {
                            selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        }
                    } else {
                        Button {
                            selectedYear = Calendar.current.date(byAdding: .year, value: -1, to: selectedYear) ?? selectedYear
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.blue)
                        }
                        
                        Button {
                            selectedYear = Calendar.current.date(byAdding: .year, value: 1, to: selectedYear) ?? selectedYear
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Add button (only for authorized users)
                    if viewModel.isYaseminOrFrontUser() {
                        Button {
                            editingVacation = nil
                            showAddVacation = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddVacation) {
                AddVacationTimeView(
                    vacationTime: editingVacation,
                    employeeNames: employeeNames,
                    onSave: { vacationTime in
                        if let editing = editingVacation {
                            // Update existing
                            var updated = vacationTime
                            updated.id = editing.id
                            updated.documentId = editing.documentId
                            viewModel.saveVacationTime(updated) { error in
                                if error == nil {
                                    showAddVacation = false
                                }
                            }
                        } else {
                            // Create new
                            viewModel.saveVacationTime(vacationTime) { error in
                                if error == nil {
                                    showAddVacation = false
                                }
                            }
                        }
                    }
                )
                .environmentObject(viewModel)
            }
            .onChange(of: selectedEmployee) { oldValue, newValue in
                // When employee is selected, automatically show their vacation dates
                if let employee = newValue {
                    // Find the first vacation date for this employee in current month
                    let (start, end) = monthRange
                    if let firstVacation = viewModel.vacationTimes.first(where: { vacation in
                        vacation.employeeName == employee &&
                        vacation.isActive &&
                        vacation.startDate <= end &&
                        vacation.endDate >= start
                    }) {
                        // Navigate to the month containing the vacation
                        selectedMonth = firstVacation.startDate
                    }
                }
            }
        }
    }
    
    // MARK: - View Mode Selector
    private var viewModeSelector: some View {
        Picker("View Mode", selection: $viewMode) {
            Text("Monthly".localized).tag(VacationViewMode.monthly)
            Text("Yearly".localized).tag(VacationViewMode.yearly)
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Monthly Calendar Section
    private var monthlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Month header
            monthHeader
            
            // Calendar grid - fits screen
            calendarGrid
        }
    }
    
    // MARK: - Yearly Calendar Section
    private var yearlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Year header
            yearHeader
            
            // Year grid - 12 months
            yearlyGrid
        }
    }
    
    private var monthHeader: some View {
        HStack {
            Text(selectedMonth, style: .date)
                .font(.title)
                .fontWeight(.bold)
            Spacer()
        }
    }
    
    private var yearHeader: some View {
        HStack {
            Text(yearString)
                .font(.title)
                .fontWeight(.bold)
            Spacer()
        }
    }
    
    private var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: selectedYear)
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // Calendar days - fit to screen
            let weeks = chunkDatesIntoWeeks(monthDates)
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        let date = weeks[weekIndex][dayIndex]
                        CalendarDayCell(
                            date: date,
                            isInMonth: monthRange.start <= date && date <= monthRange.end,
                            isWeekend: holidaysHelper.isWeekend(date),
                            isHoliday: holidaysHelper.isPublicHoliday(date),
                            holidayName: holidaysHelper.getHolidayName(for: date),
                            employees: employeeNames,
                            isEmployeeOnVacation: { name in isEmployeeOnVacation(name, on: date) },
                            getVacation: { name in getVacation(for: name, on: date) },
                            isSelectedEmployeeDate: selectedEmployee != nil && selectedEmployeeVacationDates.contains { Calendar.current.isDate($0, inSameDayAs: date) },
                            onEmployeeTap: { employeeName in
                                if viewModel.isYaseminOrFrontUser() {
                                    if let vacation = getVacation(for: employeeName, on: date) {
                                        editingVacation = vacation
                                        showAddVacation = true
                                    } else {
                                        // Create new vacation starting from this date
                                        editingVacation = VacationTime(
                                            employeeName: employeeName,
                                            startDate: date,
                                            endDate: date,
                                            createdBy: viewModel.authManager?.currentUser?.email ?? ""
                                        )
                                        showAddVacation = true
                                    }
                                } else {
                                    // Just select employee to show their dates
                                    selectedEmployee = employeeName
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var yearlyGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            ForEach(0..<12, id: \.self) { monthIndex in
                let monthDate = Calendar.current.date(byAdding: .month, value: monthIndex, to: yearStart) ?? selectedYear
                YearlyMonthCard(
                    month: monthDate,
                    year: selectedYear,
                    employees: employeeNames,
                    vacationTimes: viewModel.vacationTimes,
                    holidaysHelper: holidaysHelper,
                    isEmployeeOnVacation: { name, date in isEmployeeOnVacation(name, on: date) },
                    onMonthTap: {
                        selectedMonth = monthDate
                        viewMode = .monthly
                    }
                )
            }
        }
    }
    
    private var yearStart: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: selectedYear)
        return calendar.date(from: DateComponents(year: components.year, month: 1, day: 1)) ?? selectedYear
    }
    
    // MARK: - Collapsible Employees Section
    private var employeesCollapsibleSection: some View {
        VStack(spacing: 0) {
            // Header with collapse/expand button
            HStack {
                Text("Employees".localized)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    withAnimation(.spring()) {
                        isEmployeesExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isEmployeesExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            // Employee list - collapsible
            if isEmployeesExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(employeeNames, id: \.self) { employeeName in
                            EmployeeChip(
                                employeeName: employeeName,
                                isSelected: selectedEmployee == employeeName,
                                isOnVacation: isEmployeeOnVacationThisMonth(employeeName),
                                onTap: {
                                    selectedEmployee = selectedEmployee == employeeName ? nil : employeeName
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
        .cornerRadius(16)
        .shadow(radius: 5)
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    private func isEmployeeOnVacationThisMonth(_ employeeName: String) -> Bool {
        let (start, end) = monthRange
        return viewModel.vacationTimes.contains { vacation in
            vacation.employeeName == employeeName &&
            vacation.isActive &&
            vacation.startDate <= end &&
            vacation.endDate >= start
        }
    }
    
    private func chunkDatesIntoWeeks(_ dates: [Date]) -> [[Date]] {
        var weeks: [[Date]] = []
        var currentWeek: [Date] = []
        
        let calendar = Calendar.current
        
        for date in dates {
            let weekday = calendar.component(.weekday, from: date)
            let adjustedWeekday = (weekday + 5) % 7 // Convert to Monday = 0
            
            // Add padding days at the start
            if currentWeek.isEmpty && adjustedWeekday > 0 {
                for _ in 0..<adjustedWeekday {
                    if let firstDate = dates.first {
                        if let paddingDate = calendar.date(byAdding: .day, value: -adjustedWeekday, to: firstDate) {
                            currentWeek.append(paddingDate)
                        }
                    }
                }
            }
            
            currentWeek.append(date)
            
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                if let lastDate = currentWeek.last {
                    if let nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate) {
                        currentWeek.append(nextDate)
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            weeks.append(currentWeek)
        }
        
        return weeks
    }
}

// MARK: - Employee Chip
struct EmployeeChip: View {
    let employeeName: String
    let isSelected: Bool
    let isOnVacation: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isOnVacation {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                }
                Text(employeeName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Calendar Day Cell
struct CalendarDayCell: View {
    let date: Date
    let isInMonth: Bool
    let isWeekend: Bool
    let isHoliday: Bool
    let holidayName: String?
    let employees: [String]
    let isEmployeeOnVacation: (String) -> Bool
    let getVacation: (String) -> VacationTime?
    let isSelectedEmployeeDate: Bool
    let onEmployeeTap: (String) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Day number
            HStack {
                Text("\(dayNumber)")
                    .font(.system(size: 14, weight: isInMonth ? .semibold : .regular))
                    .foregroundColor(isInMonth ? .primary : .secondary)
                Spacer()
            }
            
            // Employee indicators - show all, make text visible
            VStack(alignment: .leading, spacing: 3) {
                ForEach(employees.prefix(5), id: \.self) { employeeName in
                    if isEmployeeOnVacation(employeeName) {
                        Button {
                            onEmployeeTap(employeeName)
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isSelectedEmployeeDate ? Color.blue : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(employeeName)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundColor(isSelectedEmployeeDate ? .blue : .orange)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if employees.count > 5 {
                    let remaining = employees.count - 5
                    Text("+\(remaining)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            
            // Holiday indicator
            if let holidayName = holidayName {
                Text(holidayName)
                    .font(.system(size: 7))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(6)
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isSelectedEmployeeDate ? 2 : (isHoliday || isWeekend ? 1.5 : 0))
        )
    }
    
    private var backgroundColor: Color {
        if isSelectedEmployeeDate {
            return Color.blue.opacity(0.2)
        } else if isHoliday {
            return Color.red.opacity(0.15)
        } else if isWeekend {
            return Color.blue.opacity(0.1)
        } else if !isInMonth {
            return colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
        } else {
            return colorScheme == .dark ? Color(.systemGray6).opacity(0.5) : Color(.systemBackground)
        }
    }
    
    private var borderColor: Color {
        if isSelectedEmployeeDate {
            return Color.blue
        } else if isHoliday {
            return Color.red.opacity(0.6)
        } else if isWeekend {
            return Color.blue.opacity(0.4)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Yearly Month Card
struct YearlyMonthCard: View {
    let month: Date
    let year: Date
    let employees: [String]
    let vacationTimes: [VacationTime]
    let holidaysHelper: SwissHolidaysHelper
    let isEmployeeOnVacation: (String, Date) -> Bool
    let onMonthTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: month)
    }
    
    private var monthDates: [Date] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let start = calendar.date(from: components) else { return [] }
        guard let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return [] }
        
        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }
        return dates
    }
    
    private var vacationDaysCount: Int {
        monthDates.filter { date in
            employees.contains { isEmployeeOnVacation($0, date) }
        }.count
    }
    
    var body: some View {
        Button(action: onMonthTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Month name
                Text(monthName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // Mini calendar
                VStack(spacing: 4) {
                    // Weekday headers
                    HStack(spacing: 2) {
                        ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Calendar grid
                    let weeks = chunkDatesIntoWeeksForYear(monthDates)
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        HStack(spacing: 2) {
                            ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                                let date = weeks[weekIndex][dayIndex]
                                let isInMonth = Calendar.current.component(.month, from: date) == Calendar.current.component(.month, from: month)
                                let hasVacation = employees.contains { isEmployeeOnVacation($0, date) }
                                let isWeekend = holidaysHelper.isWeekend(date)
                                let isHoliday = holidaysHelper.isPublicHoliday(date)
                                
                                ZStack {
                                    Circle()
                                        .fill(backgroundColor(for: date, isInMonth: isInMonth, hasVacation: hasVacation, isWeekend: isWeekend, isHoliday: isHoliday))
                                        .frame(width: 20, height: 20)
                                    
                                    Text("\(Calendar.current.component(.day, from: date))")
                                        .font(.system(size: 9, weight: isInMonth ? .medium : .regular))
                                        .foregroundColor(textColor(for: date, isInMonth: isInMonth, hasVacation: hasVacation))
                                }
                            }
                        }
                    }
                }
                
                // Vacation summary
                if vacationDaysCount > 0 {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(vacationDaysCount) \("vacation days".localized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func backgroundColor(for date: Date, isInMonth: Bool, hasVacation: Bool, isWeekend: Bool, isHoliday: Bool) -> Color {
        if !isInMonth {
            return Color.clear
        } else if isHoliday {
            return Color.red.opacity(0.3)
        } else if hasVacation {
            return Color.orange.opacity(0.6)
        } else if isWeekend {
            return Color.blue.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private func textColor(for date: Date, isInMonth: Bool, hasVacation: Bool) -> Color {
        if !isInMonth {
            return .secondary.opacity(0.5)
        } else if hasVacation {
            return .white
        } else {
            return .primary
        }
    }
    
    private func chunkDatesIntoWeeksForYear(_ dates: [Date]) -> [[Date]] {
        var weeks: [[Date]] = []
        var currentWeek: [Date] = []
        
        let calendar = Calendar.current
        
        for date in dates {
            let weekday = calendar.component(.weekday, from: date)
            let adjustedWeekday = (weekday + 5) % 7
            
            if currentWeek.isEmpty && adjustedWeekday > 0 {
                for _ in 0..<adjustedWeekday {
                    if let firstDate = dates.first {
                        if let paddingDate = calendar.date(byAdding: .day, value: -adjustedWeekday, to: firstDate) {
                            currentWeek.append(paddingDate)
                        }
                    }
                }
            }
            
            currentWeek.append(date)
            
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                if let lastDate = currentWeek.last {
                    if let nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate) {
                        currentWeek.append(nextDate)
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            weeks.append(currentWeek)
        }
        
        return weeks
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Add Vacation Time View
struct AddVacationTimeView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let vacationTime: VacationTime?
    let employeeNames: [String]
    let onSave: (VacationTime) -> Void
    
    @State private var employeeName: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var isActive: Bool = true
    @State private var showingDeleteAlert = false
    
    var isEditing: Bool { vacationTime != nil }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Vacation Details".localized) {
                    Picker("Employee".localized, selection: $employeeName) {
                        ForEach(employeeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    DatePicker("Start Date".localized, selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date".localized, selection: $endDate, displayedComponents: .date)
                    Toggle("Active".localized, isOn: $isActive)
                }
                
                Button(isEditing ? "Update Vacation".localized : "Add Vacation".localized) {
                    saveVacation()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                
                if isEditing {
                    Button("Delete Vacation".localized) {
                        showingDeleteAlert = true
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red)
                }
            }
            .onAppear(perform: setupView)
            .navigationTitle(isEditing ? "Edit Vacation".localized : "Add Vacation".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized) { dismiss() }
                }
            }
            .alert("Delete Vacation".localized, isPresented: $showingDeleteAlert) {
                Button("Delete".localized, role: .destructive, action: deleteVacation)
                Button("Cancel".localized, role: .cancel) { }
            } message: {
                Text(String(format: "Are you sure you want to delete this vacation time for %@?".localized, employeeName))
            }
        }
    }
    
    private func setupView() {
        if let vacationTime = vacationTime {
            employeeName = vacationTime.employeeName
            startDate = vacationTime.startDate
            endDate = vacationTime.endDate
            isActive = vacationTime.isActive
        } else if !employeeNames.isEmpty {
            employeeName = employeeNames[0]
        }
    }
    
    private func saveVacation() {
        guard let currentUserEmail = viewModel.authManager?.currentUser?.email else {
            return
        }
        
        let newVacation = VacationTime(
            id: vacationTime?.id ?? UUID(),
            documentId: vacationTime?.documentId,
            employeeName: employeeName,
            startDate: startDate,
            endDate: endDate,
            isActive: isActive,
            createdBy: vacationTime?.createdBy ?? currentUserEmail
        )
        
        onSave(newVacation)
    }
    
    private func deleteVacation() {
        guard let vacationTime = vacationTime else { return }
        viewModel.deleteVacationTime(vacationTime) { error in
            if error == nil {
                dismiss()
            }
        }
    }
}
