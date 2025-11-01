import SwiftUI
import FirebaseAuth

struct TimetableView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedWeek: Date = Date()
    @State private var showAddSchedule = false
    @State private var editingSchedule: WorkSchedule?
    @State private var isLoading = false
    
    private var calendar = Calendar.current
    
    // Current week start (Monday)
    private var weekStart: Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedWeek))!
    }
    
    // Week days
    private var weekDays: [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    // Filtered schedules for current week
    private var currentWeekSchedules: [WorkSchedule] {
        viewModel.workSchedules.filter { schedule in
            calendar.isDate(schedule.weekStartDate, equalTo: weekStart, toGranularity: .weekOfYear)
        }
    }
    
    // Unique users
    private var uniqueUsers: [String] {
        currentWeekSchedules.map { $0.userId }.uniqued()
    }
    
    // Current user ID
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // Current user's schedule
    private var currentUserSchedule: WorkSchedule? {
        guard let userId = currentUserId else { return nil }
        return currentWeekSchedules.first { $0.userId == userId }
    }
    
    // Total statistics (Only current user's data)
    private var totalEmployees: Int {
        uniqueUsers.count
    }
    
    private var totalWeeklyHours: Double {
        currentUserSchedule?.calculatedWeeklyHours ?? 0.0
    }
    
    private var totalVacationDays: Int {
        currentUserSchedule?.calculatedVacationDays ?? 0
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Statistics Cards (User-specific)
                statisticsCards
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                
                // Week Selector
                weekSelector
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                
                // Timetable Grid
                ScrollView {
                    timetableGrid
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Timetable")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.teal)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSchedule = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.teal)
                    }
                }
            }
            .sheet(isPresented: $showAddSchedule) {
                NavigationView {
                    AddEditScheduleView(weekStart: weekStart)
                        .environmentObject(viewModel)
                }
            }
            .sheet(item: $editingSchedule) { schedule in
                NavigationView {
                    AddEditScheduleView(weekStart: schedule.weekStartDate, editingSchedule: schedule)
                        .environmentObject(viewModel)
                }
            }
            .onAppear {
                loadWeekSchedules()
            }
        }
    }
    
    // MARK: - Statistics Cards (User-specific)
    
    private var statisticsCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            TimetableStatCard(
                title: "Employees",
                value: "\(totalEmployees)",
                icon: "person.3.fill",
                color: .blue
            )
            
            TimetableStatCard(
                title: "My Hours",
                value: String(format: "%.0f", totalWeeklyHours),
                icon: "clock.fill",
                color: .green
            )
            
            TimetableStatCard(
                title: "My Vacation",
                value: "\(totalVacationDays)",
                icon: "beach.umbrella.fill",
                color: .orange
            )
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Week Selector
    
    private var weekSelector: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
                    loadWeekSchedules()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(.teal)
            }
            
            VStack(spacing: 6) {
                Text(weekRangeText)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Week \(weekNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Button {
                withAnimation {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
                    loadWeekSchedules()
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.teal)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
    
    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let endDate = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: endDate))"
    }
    
    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: weekStart)
    }
    
    // MARK: - Timetable Grid
    
    private var timetableGrid: some View {
        VStack(spacing: 0) {
            // Header row (Days)
            HStack(spacing: 0) {
                // Empty corner
                Text("User")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(width: 110, height: 50)
                    .background(Color(.systemGray6))
                
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 6) {
                        Text(dayName(for: day))
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(dayNumber(for: day))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemGray6))
                }
            }
            
            // User rows - Show all schedules (sorted by user name)
            let sortedSchedules = currentWeekSchedules.sorted { $0.userName < $1.userName }
            
            if sortedSchedules.isEmpty {
                EmptyTimetableRow()
                    .padding(.vertical, 40)
            } else {
                ForEach(Array(sortedSchedules.enumerated()), id: \.offset) { index, schedule in
                    VStack(spacing: 0) {
                        TimetableUserRow(
                            schedule: schedule,
                            weekDays: weekDays,
                            color: UserColorAssignment.colorForIndex(index)
                        )
                        .onTapGesture {
                            editingSchedule = schedule
                        }
                        
                        // Divider between rows (except last)
                        if index < sortedSchedules.count - 1 {
                            Divider()
                                .background(Color(.separator))
                                .padding(.horizontal, 8)
                        }
                    }
                    .id("\(schedule.userId)_\(schedule.weekStartDate.timeIntervalSince1970)")
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
    
    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private func loadWeekSchedules() {
        isLoading = true
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedWeek))!
        
        FirebaseService.shared.loadWorkSchedules(weekStartDate: weekStart) { [weak viewModel] schedules, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    print("❌ Error loading schedules: \(error)")
                    ErrorManager.shared.showError(error, context: "Load Work Schedules")
                } else if let schedules = schedules {
                    viewModel?.workSchedules = schedules
                }
            }
        }
    }
}

// MARK: - Timetable Stat Card

struct TimetableStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Timetable User Row

struct TimetableUserRow: View {
    let schedule: WorkSchedule
    let weekDays: [Date]
    let color: Color
    
    var body: some View {
        HStack(spacing: 0) {
            // User name column
            VStack(alignment: .leading, spacing: 6) {
                Text(schedule.userName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                HStack(spacing: 4) {
                    Text("\(String(format: "%.0f", schedule.calculatedWeeklyHours))h")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if schedule.calculatedVacationDays > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(schedule.calculatedVacationDays)d")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 110, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            
            // Days columns
            ForEach(weekDays, id: \.self) { day in
                TimetableDayCell(
                    day: day,
                    schedule: schedule,
                    color: color
                )
            }
        }
        .frame(minHeight: 70)
        .background(Color(.systemBackground))
    }
}

// MARK: - Timetable Day Cell

struct TimetableDayCell: View {
    let day: Date
    let schedule: WorkSchedule
    let color: Color
    
    private var daySchedule: DailySchedule? {
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: day) - 2 // Convert to 0-6 (Monday=0)
        let adjustedDay = dayOfWeek < 0 ? 6 : dayOfWeek
        return schedule.schedules.first { $0.dayOfWeek == adjustedDay }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            if let daily = daySchedule {
                if daily.isVacation {
                    Image(systemName: "beach.umbrella.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Off")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                } else {
                    Text(daily.startTime)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(daily.endTime)
                        .font(.caption2)
                        .foregroundColor(.primary)
                    Text(daily.shiftType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 70)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            Group {
                if let daily = daySchedule {
                    if daily.isVacation {
                        Color.orange.opacity(0.2)
                    } else {
                        // Working day - green background
                        Color.green.opacity(0.25)
                    }
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            Group {
                if let daily = daySchedule, !daily.isVacation {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.3), lineWidth: 1.5)
                }
            }
        )
    }
}

// MARK: - Empty Timetable Row

struct EmptyTimetableRow: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.gray.opacity(0.5))
                
                Text("No schedules yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Tap + to add a schedule")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add/Edit Schedule View

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
    
    private var weekDays: [(Int, String)] {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return Array(days.enumerated().map { ($0, $1) })
    }
    
    var body: some View {
        Form {
            Section("Employee Information") {
                TextField("Name", text: $userName)
                    .textInputAutocapitalization(.words)
            }
            
            Section("Working Days & Hours") {
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
                                Label("Vacation", systemImage: "beach.umbrella.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            
            Section("Working Hours") {
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                
                Picker("Shift Type", selection: $selectedShiftType) {
                    ForEach(DailySchedule.ShiftType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.rawValue)
                        }
                        .tag(type)
                    }
                }
            }
            
            Section("Vacation Days") {
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
                            Text("Saving...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(editingSchedule != nil ? "Update Schedule" : "Save Schedule")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || userName.isEmpty)
            }
        }
        .navigationTitle(editingSchedule != nil ? "Edit Schedule" : "Add Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if let schedule = editingSchedule {
                userName = schedule.userName
                selectedDays = Set(schedule.schedules.filter { !$0.isVacation }.map { $0.dayOfWeek })
                vacationDays = Set(schedule.schedules.filter { $0.isVacation }.map { $0.dayOfWeek })
                if let firstSchedule = schedule.schedules.first(where: { !$0.isVacation }) {
                    selectedShiftType = firstSchedule.shiftType
                    // Parse start/end times
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    if let start = formatter.date(from: firstSchedule.startTime),
                       let end = formatter.date(from: firstSchedule.endTime) {
                        startTime = start
                        endTime = end
                    }
                }
            } else {
                // Default: Monday-Friday working
                selectedDays = Set([0, 1, 2, 3, 4])
            }
        }
    }
    
    private func saveSchedule() {
        guard let user = Auth.auth().currentUser else { return }
        guard !userName.isEmpty else { return }
        
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
            userName: userName,
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

