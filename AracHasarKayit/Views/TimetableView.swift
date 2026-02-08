import SwiftUI
import FirebaseAuth

enum WorkScheduleViewMode {
    case monthly
    case yearly
}

struct TimetableView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedMonth = Date()
    @State private var selectedYear = Date()
    @State private var viewMode: WorkScheduleViewMode = .monthly
    @State private var showAddSchedule = false
    @State private var editingSchedule: WorkSchedule?
    @State private var selectedEmployee: String?
    @State private var isEmployeesExpanded = true
    
    private let holidaysHelper = SwissHolidaysHelper.shared
    
    // Get unique employee names from work schedules
    private var employeeNames: [String] {
        let names = Set(viewModel.workSchedules.map { $0.userName })
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
    
    // Get work dates for selected employee in current month
    private var selectedEmployeeWorkDates: [Date] {
        guard let employee = selectedEmployee else { return [] }
        let (start, end) = monthRange
        var dates: [Date] = []
        
        let schedules = viewModel.workSchedules.filter { schedule in
            schedule.userName == employee
        }
        
        for schedule in schedules {
            let weekStart = schedule.weekStartDate
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            
            // Check if this week overlaps with the month
            if weekStart <= end && weekEnd >= start {
                for dailySchedule in schedule.schedules {
                    if !dailySchedule.isVacation {
                        // Calculate the actual date for this day of week
                        let dayOfWeek = dailySchedule.dayOfWeek
                        let weekStartDay = calendar.component(.weekday, from: weekStart)
                        let adjustedWeekday = (weekStartDay + 5) % 7 // Convert to Monday = 0
                        let dayOffset = dayOfWeek - adjustedWeekday
                        
                        if let workDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) {
                            let dayStart = calendar.startOfDay(for: workDate)
                            if dayStart >= start && dayStart <= end {
                                dates.append(dayStart)
                            }
                        }
                    }
                }
            }
        }
        
        return Array(Set(dates)).sorted()
    }
    
    // Check if employee is working on a specific date
    private func isEmployeeWorking(_ employeeName: String, on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayOfWeek = (calendar.component(.weekday, from: dayStart) + 5) % 7 // Monday = 0
        
        return viewModel.workSchedules.contains { schedule in
            guard schedule.userName == employeeName else { return false }
            
            let weekStart = calendar.startOfDay(for: schedule.weekStartDate)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            
            // Check if date is within this schedule's week
            if dayStart >= weekStart && dayStart < weekEnd {
                // Check if this day has a work schedule
                return schedule.schedules.contains { dailySchedule in
                    dailySchedule.dayOfWeek == dayOfWeek && !dailySchedule.isVacation
                }
            }
            
            return false
        }
    }
    
    // Get work schedule for employee on a specific date
    private func getWorkSchedule(for employeeName: String, on date: Date) -> DailySchedule? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayOfWeek = (calendar.component(.weekday, from: dayStart) + 5) % 7 // Monday = 0
        
        for schedule in viewModel.workSchedules {
            guard schedule.userName == employeeName else { continue }
            
            let weekStart = calendar.startOfDay(for: schedule.weekStartDate)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            
            if dayStart >= weekStart && dayStart < weekEnd {
                return schedule.schedules.first { dailySchedule in
                    dailySchedule.dayOfWeek == dayOfWeek && !dailySchedule.isVacation
                }
            }
        }
        
        return nil
    }
    
    private var calendar: Calendar {
        Calendar.current
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
                
                // Main content
                ScrollView {
                    VStack(spacing: 0) {
                        if viewMode == .monthly {
                            monthlyCalendarSection
                                .padding()
                } else {
                            yearlyCalendarSection
                                .padding()
                        }
                        
                        // Employees section
                        employeesCollapsibleSection
                            .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Work Schedules".localized)
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
                        .foregroundColor(.teal)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Navigation buttons
                    if viewMode == .monthly {
                    Button {
                            selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.teal)
                        }
                        
                        Button {
                            selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.teal)
                        }
                    } else {
                        Button {
                            selectedYear = calendar.date(byAdding: .year, value: -1, to: selectedYear) ?? selectedYear
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.teal)
                        }
                        
                        Button {
                            selectedYear = calendar.date(byAdding: .year, value: 1, to: selectedYear) ?? selectedYear
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.teal)
                        }
                    }
                    
                    // Add button
                    Button {
                        editingSchedule = nil
                        showAddSchedule = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.teal)
                    }
                }
            }
            .sheet(isPresented: $showAddSchedule) {
                NavigationView {
                    AddEditScheduleView(weekStart: getWeekStart(for: selectedMonth), editingSchedule: editingSchedule)
                        .environmentObject(viewModel)
                }
            }
            .onAppear {
                loadWorkSchedules()
            }
        }
    }
    
    private func getWeekStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }
    
    private func loadWorkSchedules() {
        // Load all work schedules for the current month
        let (start, end) = monthRange
        let weekStart = getWeekStart(for: start)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        
        FirebaseService.shared.observeWorkSchedules(weekStartDate: weekStart) { schedules in
            DispatchQueue.main.async {
                // Filter schedules that overlap with the month
                let filteredSchedules = schedules.filter { schedule in
                    let scheduleWeekEnd = calendar.date(byAdding: .day, value: 7, to: schedule.weekStartDate) ?? schedule.weekStartDate
                    return schedule.weekStartDate <= end && scheduleWeekEnd >= start
                }
                viewModel.workSchedules = filteredSchedules
            }
        }
    }
    
    // MARK: - View Mode Selector
    private var viewModeSelector: some View {
        Picker("View Mode".localized, selection: $viewMode) {
            Text("Monthly".localized).tag(WorkScheduleViewMode.monthly)
            Text("Yearly".localized).tag(WorkScheduleViewMode.yearly)
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Monthly Calendar Section
    private var monthlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Month header
            monthHeader
            
            // Calendar grid
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
                    Text(day.localized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // Calendar days
            let weeks = chunkDatesIntoWeeks(monthDates)
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        let date = weeks[weekIndex][dayIndex]
                        WorkScheduleDayCell(
                            date: date,
                            isInMonth: monthRange.start <= date && date <= monthRange.end,
                            isWeekend: holidaysHelper.isWeekend(date),
                            isHoliday: holidaysHelper.isPublicHoliday(date),
                            holidayName: holidaysHelper.getHolidayName(for: date),
                            employees: employeeNames,
                            isEmployeeWorking: { name in isEmployeeWorking(name, on: date) },
                            getWorkSchedule: { name in getWorkSchedule(for: name, on: date) },
                            isSelectedEmployeeDate: selectedEmployee != nil && selectedEmployeeWorkDates.contains { calendar.isDate($0, inSameDayAs: date) },
                            onEmployeeTap: { employeeName in
                                if let schedule = getWorkSchedule(for: employeeName, on: date) {
                                    // Find the work schedule for this employee and date
                                    let weekStart = getWeekStart(for: date)
                                    if let workSchedule = viewModel.workSchedules.first(where: { $0.userName == employeeName && calendar.isDate($0.weekStartDate, inSameDayAs: weekStart) }) {
                                        editingSchedule = workSchedule
                                        showAddSchedule = true
                                    }
                                } else {
                                    // Create new schedule for this week
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
                let monthDate = calendar.date(byAdding: .month, value: monthIndex, to: yearStart) ?? selectedYear
                YearlyWorkScheduleMonthCard(
                    month: monthDate,
                    year: selectedYear,
                    employees: employeeNames,
                    workSchedules: viewModel.workSchedules,
                    holidaysHelper: holidaysHelper,
                    isEmployeeWorking: { name, date in isEmployeeWorking(name, on: date) },
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
                            WorkScheduleEmployeeChip(
                                employeeName: employeeName,
                                isSelected: selectedEmployee == employeeName,
                                isWorking: isEmployeeWorkingThisMonth(employeeName),
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
    
    private func isEmployeeWorkingThisMonth(_ employeeName: String) -> Bool {
        let (start, end) = monthRange
        return monthDates.contains { date in
            isEmployeeWorking(employeeName, on: date)
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

// MARK: - Work Schedule Employee Chip
struct WorkScheduleEmployeeChip: View {
    let employeeName: String
    let isSelected: Bool
    let isWorking: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isWorking {
                    Image(systemName: "briefcase.fill")
                        .font(.caption)
                }
                Text(employeeName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.teal : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Work Schedule Day Cell
struct WorkScheduleDayCell: View {
    let date: Date
    let isInMonth: Bool
    let isWeekend: Bool
    let isHoliday: Bool
    let holidayName: String?
    let employees: [String]
    let isEmployeeWorking: (String) -> Bool
    let getWorkSchedule: (String) -> DailySchedule?
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
            
            // Employee indicators
            VStack(alignment: .leading, spacing: 3) {
                ForEach(employees.prefix(5), id: \.self) { employeeName in
                    if isEmployeeWorking(employeeName) {
                        Button {
                            onEmployeeTap(employeeName)
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isSelectedEmployeeDate ? Color.teal : Color.green)
                                    .frame(width: 6, height: 6)
                                if let schedule = getWorkSchedule(employeeName) {
                                    Text("\(schedule.startTime)-\(schedule.endTime)")
                                        .font(.system(size: 8, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundColor(isSelectedEmployeeDate ? .teal : .green)
                                } else {
                                    Text(employeeName)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundColor(isSelectedEmployeeDate ? .teal : .green)
                                }
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
            return Color.teal.opacity(0.2)
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
            return Color.teal
        } else if isHoliday {
            return Color.red.opacity(0.6)
        } else if isWeekend {
            return Color.blue.opacity(0.4)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Yearly Work Schedule Month Card
struct YearlyWorkScheduleMonthCard: View {
    let month: Date
    let year: Date
    let employees: [String]
    let workSchedules: [WorkSchedule]
    let holidaysHelper: SwissHolidaysHelper
    let isEmployeeWorking: (String, Date) -> Bool
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
    
    private var workDaysCount: Int {
        monthDates.filter { date in
            employees.contains { isEmployeeWorking($0, date) }
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
                        ForEach([("weekday.Mon", "M"), ("weekday.Tue", "T"), ("weekday.Wed", "W"), ("weekday.Thu", "T"), ("weekday.Fri", "F"), ("weekday.Sat", "S"), ("weekday.Sun", "S")], id: \.0) { key, _ in
                            Text(key.localized)
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
                                let hasWork = employees.contains { isEmployeeWorking($0, date) }
                                let isWeekend = holidaysHelper.isWeekend(date)
                                let isHoliday = holidaysHelper.isPublicHoliday(date)
                                
                                ZStack {
                                    Circle()
                                        .fill(backgroundColor(for: date, isInMonth: isInMonth, hasWork: hasWork, isWeekend: isWeekend, isHoliday: isHoliday))
                                        .frame(width: 20, height: 20)
                                    
                                    Text("\(Calendar.current.component(.day, from: date))")
                                        .font(.system(size: 9, weight: isInMonth ? .medium : .regular))
                                        .foregroundColor(textColor(for: date, isInMonth: isInMonth, hasWork: hasWork))
                                }
                            }
                        }
                    }
                }
                
                // Work summary
                if workDaysCount > 0 {
                    HStack {
                        Image(systemName: "briefcase.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(workDaysCount) \("work days".localized)")
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
    
    private func backgroundColor(for date: Date, isInMonth: Bool, hasWork: Bool, isWeekend: Bool, isHoliday: Bool) -> Color {
        if !isInMonth {
            return Color.clear
        } else if isHoliday {
            return Color.red.opacity(0.3)
        } else if hasWork {
            return Color.green.opacity(0.6)
        } else if isWeekend {
            return Color.blue.opacity(0.2)
                    } else {
            return Color.clear
        }
    }
    
    private func textColor(for date: Date, isInMonth: Bool, hasWork: Bool) -> Color {
        if !isInMonth {
            return .secondary.opacity(0.5)
        } else if hasWork {
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

// MARK: - Add/Edit Schedule View (Keep existing implementation)
struct AddEditScheduleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let weekStart: Date
    var editingSchedule: WorkSchedule? = nil
    
    @State private var userName: String = ""
    @State private var selectedDays: Set<Int> = []
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime: Date = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var selectedShiftType: DailySchedule.ShiftType = .fullDay
    @State private var vacationDays: Set<Int> = []
    @State private var isSaving = false
    
    // Get user email as name
    private var userEmailName: String {
        let email = Auth.auth().currentUser?.email ?? ""
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex])
        }
        return email.isEmpty ? "User".localized : email
    }
    
    private var weekDays: [(Int, String)] {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return Array(days.enumerated().map { ($0, $1.localized) })
    }
    
    var body: some View {
        Form {
            Section("Employee Information".localized) {
                Text(userName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
            }
            
            Section("Working Days & Hours".localized) {
                ForEach(weekDays, id: \.0) { dayIndex, dayName in
                    Toggle(isOn: Binding(
                        get: { selectedDays.contains(dayIndex) && !vacationDays.contains(dayIndex) },
                        set: { isOn in
                            if isOn {
                                selectedDays.insert(dayIndex)
                                vacationDays.remove(dayIndex)
                            } else {
                                selectedDays.remove(dayIndex)
                            }
                        }
                    )) {
                        HStack {
                            Text(dayName)
                            Spacer()
                            if vacationDays.contains(dayIndex) {
                                Label("Vacation".localized, systemImage: "beach.umbrella.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            
            Section("Working Hours".localized) {
                DatePicker("Start Time".localized, selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time".localized, selection: $endTime, displayedComponents: .hourAndMinute)
                
                Picker("Shift Type".localized, selection: $selectedShiftType) {
                    ForEach(DailySchedule.ShiftType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.rawValue.localized)
                        }
                        .tag(type)
                    }
                }
            }
            
            Section("Vacation Days".localized) {
                ForEach(weekDays, id: \.0) { dayIndex, dayName in
                    Toggle(isOn: Binding(
                        get: { vacationDays.contains(dayIndex) },
                        set: { isOn in
                            if isOn {
                                vacationDays.insert(dayIndex)
                                selectedDays.remove(dayIndex)
                            } else {
                                vacationDays.remove(dayIndex)
                            }
                        }
                    )) {
                        Text(dayName)
                    }
                }
            }
            
            Section {
                Button {
                    saveSchedule()
                } label: {
                    if isSaving {
                        HStack {
                            ProgressView()
                            Text("Saving...".localized)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(editingSchedule != nil ? "Update Schedule".localized : "Save Schedule".localized)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(editingSchedule != nil ? "Edit Schedule".localized : "Add Schedule".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .onAppear {
            if let schedule = editingSchedule {
                userName = schedule.userName
                selectedDays = Set(schedule.schedules.filter { !$0.isVacation }.map { $0.dayOfWeek })
                vacationDays = Set(schedule.schedules.filter { $0.isVacation }.map { $0.dayOfWeek })
                if let firstSchedule = schedule.schedules.first(where: { !$0.isVacation }) {
                    selectedShiftType = firstSchedule.shiftType
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    if let start = formatter.date(from: firstSchedule.startTime),
                       let end = formatter.date(from: firstSchedule.endTime) {
                        startTime = start
                        endTime = end
                    }
                }
            } else {
                userName = userEmailName
                selectedDays = Set([0, 1, 2, 3, 4])
            }
        }
    }
    
    private func saveSchedule() {
        guard let user = Auth.auth().currentUser else { return }
        
        let finalUserName = userName.isEmpty ? userEmailName : userName
        
        isSaving = true
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let startTimeString = timeFormatter.string(from: startTime)
        let endTimeString = timeFormatter.string(from: endTime)
        
        var dailySchedules: [DailySchedule] = []
        
        // Add working days
        for dayIndex in selectedDays {
            dailySchedules.append(DailySchedule(
                dayOfWeek: dayIndex,
                startTime: startTimeString,
                endTime: endTimeString,
                isVacation: false,
                shiftType: selectedShiftType
            ))
        }
        
        // Add vacation days
        for dayIndex in vacationDays {
            dailySchedules.append(DailySchedule(
                dayOfWeek: dayIndex,
                startTime: "00:00",
                endTime: "00:00",
                isVacation: true,
                shiftType: .fullDay
            ))
        }
        
        var schedule = WorkSchedule(
            userId: editingSchedule?.userId ?? user.uid,
            userName: finalUserName,
            weekStartDate: weekStart,
            schedules: dailySchedules
        )
        
        if let editing = editingSchedule {
            schedule.id = editing.id
            schedule.createdAt = editing.createdAt
            viewModel.workScheduleGuncelle(schedule) { _ in
                isSaving = false
                dismiss()
            }
        } else {
            viewModel.workScheduleKaydet(schedule) { _ in
                isSaving = false
                dismiss()
            }
        }
    }
    
    private var calendar: Calendar {
        Calendar.current
    }
}

// MARK: - Array Extension
extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

