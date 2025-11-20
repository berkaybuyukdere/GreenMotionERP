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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Statistics Cards
                statisticsCards
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                
                // Week Selector
                weekSelector
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                
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
                } else if currentWeekSchedules.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.teal.opacity(0.5))
                        Text("No schedules for this week")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Tap + to add a schedule")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ScrollView(.vertical, showsIndicators: true) {
                            timetableGrid
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Timetable")
            .navigationBarTitleDisplayMode(.large)
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.translation.width > 100 {
                            // Swipe right - previous week
                            withAnimation {
                                selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
                                observeWeekSchedules()
                            }
                        } else if value.translation.width < -100 {
                            // Swipe left - next week
                            withAnimation {
                                selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
                                observeWeekSchedules()
                            }
                        }
                    }
            )
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
    
    // MARK: - Statistics Cards
    
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
                value: String(format: "%.0fh", totalWeeklyHours),
                icon: "clock.fill",
                color: .green
            )
            
            TimetableStatCard(
                title: "My Vacation",
                value: "\(totalVacationDays) days",
                icon: "beach.umbrella.fill",
                color: .orange
            )
        }
    }
    
    // MARK: - Week Selector
    
    private var weekSelector: some View {
        HStack(spacing: 20) {
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
                    observeWeekSchedules()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.teal)
            }
            
            VStack(spacing: 6) {
                Text(weekRangeText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Week \(weekNumber)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
                    observeWeekSchedules()
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.teal)
            }
            
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedWeek = Date()
                    observeWeekSchedules()
                }
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.teal)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
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
        let sortedSchedules = currentWeekSchedules.sorted { $0.userName < $1.userName }
        
        return VStack(spacing: 0) {
            // Header row (Days)
            HStack(spacing: 0) {
                // User column header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Employee")
                        .font(.system(size: 13, weight: .bold))
                    Text("Hours")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 120, height: 60)
                .padding(.horizontal, 12)
                .background(
                    LinearGradient(
                        colors: [Color(.systemGray6), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 4) {
                        Text(dayName(for: day))
                            .font(.system(size: 12, weight: .bold))
                        Text(dayNumber(for: day))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemGray6), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
            
            // User rows
            ForEach(Array(sortedSchedules.enumerated()), id: \.offset) { index, schedule in
                TimetableUserRow(
                    schedule: schedule,
                    weekDays: weekDays,
                    color: UserColorAssignment.colorForIndex(index),
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
                .id("\(schedule.userId)_\(schedule.weekStartDate.timeIntervalSince1970)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
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
        
        print("🔍 Loading work schedules for week starting: \(weekStart)")
        
        // Use FirebaseService directly for real-time updates
        FirebaseService.shared.observeWorkSchedules(weekStartDate: weekStart) { (schedules: [WorkSchedule]) in
            DispatchQueue.main.async {
                self.isLoading = false
                
                // Replace all schedules in viewModel with the new ones
                // This ensures we have the latest data
                viewModel.workSchedules = schedules
                
                print("✅ Work schedules updated in viewModel: \(schedules.count) schedules for week starting \(weekStart)")
                print("   Users: \(schedules.map { $0.userName }.joined(separator: ", "))")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Timetable User Row

struct TimetableUserRow: View {
    let schedule: WorkSchedule
    let weekDays: [Date]
    let color: Color
    var canEdit: Bool = true
    
    var body: some View {
        HStack(spacing: 0) {
            // User name column
            VStack(alignment: .leading, spacing: 6) {
                Text(schedule.userName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                HStack(spacing: 6) {
                    Label("\(String(format: "%.0f", schedule.calculatedWeeklyHours))h", systemImage: "clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if schedule.calculatedVacationDays > 0 {
                        Label("\(schedule.calculatedVacationDays)d", systemImage: "beach.umbrella.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 120, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.15), color.opacity(0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Rectangle()
                    .frame(width: 3)
                    .foregroundColor(color)
                    .opacity(0.6),
                alignment: .leading
            )
            
            // Days columns
            ForEach(weekDays, id: \.self) { day in
                TimetableDayCell(
                    day: day,
                    schedule: schedule,
                    color: color
                )
            }
        }
        .frame(minHeight: 85)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator).opacity(0.5)),
            alignment: .bottom
        )
        .opacity(canEdit ? 1.0 : 0.6)
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
                    VStack(spacing: 4) {
                        Image(systemName: "beach.umbrella.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.orange)
                        Text("Off")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                } else {
                    VStack(spacing: 3) {
                        Text("\(daily.startTime)-\(daily.endTime)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text(daily.shiftType.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } else {
                Text("-")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 85)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            Group {
                if let daily = daySchedule {
                    if daily.isVacation {
                        LinearGradient(
                            colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
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
                        .stroke(color.opacity(0.4), lineWidth: 2)
                }
            }
        )
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

