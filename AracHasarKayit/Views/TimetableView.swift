import SwiftUI
import FirebaseAuth

struct TimetableView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedWeek: Date = Date()
    @State private var showAddSchedule = false
    @State private var editingSchedule: WorkSchedule?
    @State private var isLoading = false
    @State private var scheduleToDelete: WorkSchedule?
    @State private var showDeleteAlert = false
    
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
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        
        return viewModel.workSchedules.filter { schedule in
            // Compare dates more accurately
            let scheduleWeekStart = schedule.weekStartDate
            let scheduleWeekEnd = calendar.date(byAdding: .day, value: 7, to: scheduleWeekStart) ?? scheduleWeekStart
            
            // Check if schedules overlap with selected week
            return scheduleWeekStart < weekEnd && scheduleWeekEnd > weekStart
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
    
    // Current user email
    private var currentUserEmail: String? {
        Auth.auth().currentUser?.email
    }
    
    // Check if current user is admin
    private var isAdmin: Bool {
        currentUserEmail == "admin@gmail.com"
    }
    
    // Check if user can edit schedule
    private func canEditSchedule(_ schedule: WorkSchedule) -> Bool {
        guard let currentUID = currentUserId else { return false }
        return isAdmin || schedule.userId == currentUID
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
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                
                VStack(spacing: 0) {
                    // Statistics Cards (User-specific)
                    statisticsCards
                        .padding(.horizontal)
                        .padding(.top, isLandscape ? 8 : 12)
                        .padding(.bottom, isLandscape ? 8 : 16)
                    
                    // Week Selector
                    weekSelector
                        .padding(.horizontal)
                        .padding(.bottom, isLandscape ? 8 : 20)
                    
                    // Timetable Grid
                    if isLoading {
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.teal)
                            Text("Loading schedules...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            timetableGrid(isLandscape: isLandscape)
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                        }
                    }
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
                observeWeekSchedules()
            }
            .onChange(of: selectedWeek) { _ in
                // Reload schedules when week changes
                observeWeekSchedules()
            }
            .onDisappear {
                // Cleanup listener if needed
            }
            .alert("Delete Schedule", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    scheduleToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let schedule = scheduleToDelete {
                        deleteSchedule(schedule)
                    }
                    scheduleToDelete = nil
                }
            } message: {
                if let schedule = scheduleToDelete {
                    Text("Are you sure you want to delete \(schedule.userName)'s schedule? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this schedule? This action cannot be undone.")
                }
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
                    observeWeekSchedules()
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
                    observeWeekSchedules()
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
    
    private func timetableGrid(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // Header row (Days)
            HStack(spacing: 0) {
                // Empty corner
                Text("User")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(width: isLandscape ? 120 : 110, height: isLandscape ? 45 : 50)
                    .background(Color(.systemGray6))
                
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: isLandscape ? 4 : 6) {
                        Text(dayName(for: day))
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(dayNumber(for: day))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isLandscape ? 45 : 50)
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
                            color: UserColorAssignment.colorForIndex(index),
                            isLandscape: isLandscape,
                            canEdit: canEditSchedule(schedule)
                        )
                        .onTapGesture {
                            if canEditSchedule(schedule) {
                                editingSchedule = schedule
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEditSchedule(schedule) {
                                Button(role: .destructive) {
                                    scheduleToDelete = schedule
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    editingSchedule = schedule
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
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
    
    private func observeWeekSchedules() {
        isLoading = true
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedWeek))!
        
        // Use FirebaseService directly for real-time updates
        FirebaseService.shared.observeWorkSchedules(weekStartDate: weekStart) { (schedules: [WorkSchedule]) in
            DispatchQueue.main.async {
                self.isLoading = false
                // Update viewModel with filtered schedules for this week
                // But also keep other weeks' schedules for navigation
                // Only replace schedules for this specific week
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                
                // Remove schedules for this week from viewModel
                viewModel.workSchedules.removeAll { schedule in
                    let scheduleWeekStart = schedule.weekStartDate
                    let scheduleWeekEnd = calendar.date(byAdding: .day, value: 7, to: scheduleWeekStart) ?? scheduleWeekStart
                    return scheduleWeekStart < weekEnd && scheduleWeekEnd > weekStart
                }
                
                // Add new schedules for this week
                viewModel.workSchedules.append(contentsOf: schedules)
                print("✅ Work schedules updated: \(schedules.count) schedules for week starting \(weekStart)")
            }
        }
    }
    
    private func loadWeekSchedules() {
        observeWeekSchedules()
    }
    
    private func deleteSchedule(_ schedule: WorkSchedule) {
        viewModel.workScheduleSil(schedule) { error in
            if let error = error {
                ErrorManager.shared.showError(error, context: "Delete Work Schedule")
            } else {
                print("✅ Schedule deleted successfully")
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
    var isLandscape: Bool = false
    var canEdit: Bool = true
    
    var body: some View {
        HStack(spacing: 0) {
            // User name column
            VStack(alignment: .leading, spacing: isLandscape ? 4 : 6) {
                Text(schedule.userName)
                    .font(isLandscape ? .caption : .subheadline)
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
            .frame(width: isLandscape ? 120 : 110, alignment: .leading)
            .padding(.horizontal, isLandscape ? 8 : 10)
            .padding(.vertical, isLandscape ? 8 : 12)
            .background(color.opacity(0.1))
            
            // Days columns
            ForEach(weekDays, id: \.self) { day in
                TimetableDayCell(
                    day: day,
                    schedule: schedule,
                    color: color,
                    isLandscape: isLandscape
                )
            }
        }
        .frame(minHeight: isLandscape ? 60 : 70)
        .background(Color(.systemBackground))
        .opacity(canEdit ? 1.0 : 0.7)
    }
}

// MARK: - Timetable Day Cell

struct TimetableDayCell: View {
    let day: Date
    let schedule: WorkSchedule
    let color: Color
    var isLandscape: Bool = false
    
    private var daySchedule: DailySchedule? {
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: day) - 2 // Convert to 0-6 (Monday=0)
        let adjustedDay = dayOfWeek < 0 ? 6 : dayOfWeek
        return schedule.schedules.first { $0.dayOfWeek == adjustedDay }
    }
    
    var body: some View {
        VStack(spacing: isLandscape ? 3 : 6) {
            if let daily = daySchedule {
                if daily.isVacation {
                    Image(systemName: "beach.umbrella.fill")
                        .font(isLandscape ? .caption2 : .caption)
                        .foregroundColor(.orange)
                    Text("Off")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                } else {
                    Text(daily.startTime)
                        .font(isLandscape ? .caption2 : .caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(daily.endTime)
                        .font(.caption2)
                        .foregroundColor(.primary)
                    if !isLandscape {
                        Text(daily.shiftType.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isLandscape ? 60 : 70)
        .padding(.vertical, isLandscape ? 4 : 8)
        .padding(.horizontal, 2)
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
                    RoundedRectangle(cornerRadius: isLandscape ? 6 : 8)
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
    
    // Get user email as name
    private var userEmailName: String {
        let email = Auth.auth().currentUser?.email ?? ""
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex])
        }
        return email.isEmpty ? "User" : email
    }
    
    private var weekDays: [(Int, String)] {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return Array(days.enumerated().map { ($0, $1) })
    }
    
    var body: some View {
        Form {
            Section("Employee Information") {
                Text(userName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
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
                .disabled(isSaving)
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
                // For new schedule, use email name
                userName = userEmailName
                // Default: Monday-Friday working
                selectedDays = Set([0, 1, 2, 3, 4])
            }
        }
    }
    
    private func saveSchedule() {
        guard let user = Auth.auth().currentUser else { return }
        
        // Use email name if userName is empty (shouldn't happen but safety check)
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

