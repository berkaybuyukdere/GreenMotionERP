import SwiftUI
import FirebaseAuth
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Work Hours detail page (opened from Report card)

struct WorkTimeDetailView: View {
    let initialMonth: Date
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: Date
    @State private var showMonthPicker = false

    init(initialMonth: Date) {
        self.initialMonth = initialMonth
        _selectedMonth = State(initialValue: initialMonth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                monthSelectorBar
                    .padding(.horizontal)
                    .padding(.top, 12)
                WorkTimePlanSection(month: selectedMonth)
                    .environmentObject(authManager)
                    .padding(.horizontal)
                    .padding(.top, 12)
                WorkTimeTrackingSection(selectedMonth: $selectedMonth)
                    .environmentObject(authManager)
            }
        }
        .navigationTitle("Work Hours".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    HapticManager.shared.light()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back".localized)
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            monthPickerSheet
        }
    }

    private var monthSelectorBar: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                HapticManager.shared.medium()
                showMonthPicker = true
            } label: {
                Text(WorkTimeMonthCalendarView.monthTitle(for: selectedMonth))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                HapticManager.shared.light()
                let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                if next <= Date() {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedMonth = next
                    }
                }
            } label: {
                let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                let disabled = next > Date()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(disabled ? Color.secondary.opacity(0.3) : Color.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    private var monthPickerSheet: some View {
        NavigationView {
            DatePicker(
                "Select month".localized,
                selection: $selectedMonth,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Select month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { showMonthPicker = false }
                }
            }
        }
    }
}

// MARK: - Hero carousel (detail page top banner)

struct ReportTabHeroCarousel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            carouselCard(
                icon: "clock.badge.checkmark",
                title: "Track work hours".localized,
                subtitle: "Tap a day to log in & out times.".localized,
                tint: .orange
            )
            carouselCard(
                icon: "calendar",
                title: "Monthly overview".localized,
                subtitle: "Day and month totals update automatically.".localized,
                tint: .blue
            )
            carouselCard(
                icon: "square.and.arrow.up",
                title: "Export reports".localized,
                subtitle: "Share Excel or PDF anytime.".localized,
                tint: .indigo
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    private func carouselCard(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(.systemGray5).opacity(0.35) : Color(.systemBackground))
        )
        .padding(.horizontal, 2)
    }
}

// MARK: - Main section embedded in Reports

struct WorkTimeTrackingSection: View {
    @Binding var selectedMonth: Date
    @EnvironmentObject private var authManager: AuthenticationManager
    @StateObject private var store = WorkTimeTrackingStore()
    @State private var managerScope: ManagerWorkScope = .myHours
    @State private var selectedTeamMemberId: String?
    @State private var editorContext: WorkDayEditorContext?
    @State private var shareItem: WorkSharePayload?
    @State private var exportError: String?

    private var isFranchiseManager: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    private var viewAllTeam: Bool {
        isFranchiseManager && managerScope == .team
    }

    private var entriesForCalendar: [WorkTimeEntry] {
        if viewAllTeam, let uid = selectedTeamMemberId {
            return store.entries.filter { $0.userId == uid }
        }
        if viewAllTeam && selectedTeamMemberId == nil {
            return []
        }
        return store.entries
    }

    private var monthTotalMinutes: Int {
        entriesForCalendar.reduce(0) { $0 + $1.totalMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerCard

            if isFranchiseManager {
                Picker("", selection: $managerScope) {
                    Text("My hours".localized).tag(ManagerWorkScope.myHours)
                    Text("Team (manager)".localized).tag(ManagerWorkScope.team)
                }
                .pickerStyle(.segmented)
                .onChange(of: managerScope) { _, new in
                    if new == .myHours {
                        selectedTeamMemberId = nil
                    }
                    reloadStore()
                }
            }

            if viewAllTeam {
                teamOverview
                if selectedTeamMemberId == nil {
                    Text("Select a team member above to open their calendar.".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let err = store.lastError {
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
            }

            WorkTimeMonthCalendarView(
                month: selectedMonth,
                entries: entriesForCalendar,
                canTapDay: canTapSelectedCalendar
            ) { day in
                openEditor(for: day)
            }

            exportBar

            if exportError != nil {
                Text(exportError ?? "")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .onAppear {
            reloadStore()
        }
        .onChange(of: selectedMonth) { _, _ in
            reloadStore()
        }
        .onChange(of: selectedTeamMemberId) { _, _ in
            // entries already loaded; calendar just filters
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserChanged"))) { _ in
            reloadStore()
        }
        .sheet(item: $editorContext) { ctx in
            WorkTimeDayEditorSheet(
                context: ctx,
                profile: authManager.userProfile,
                onSave: { clockIn, clockOut, notes, isHoliday in
                    try await store.saveEntry(
                        day: ctx.day,
                        clockIn: clockIn,
                        clockOut: clockOut,
                        notes: notes,
                        profile: authManager.userProfile,
                        isHoliday: isHoliday
                    )
                },
                onDelete: {
                    try await store.deleteEntry(day: ctx.day, storedEntry: ctx.entry)
                },
                onFinished: {
                    editorContext = nil
                    reloadStore()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { payload in
            ActivityViewController(activityItems: [payload.url])
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Work hours".localized, systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Text(WorkTimeEntry.formattedDuration(minutes: monthTotalMinutes))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text("Month total".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    @ViewBuilder
    private var teamOverview: some View {
        let aggregates = store.teamAggregates(from: store.entries)
        VStack(alignment: .leading, spacing: 10) {
            Text("Team totals (this month)".localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if aggregates.isEmpty {
                Text("No work hour entries for this month.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(aggregates) { row in
                            let isSelected = selectedTeamMemberId == row.userId
                            Button {
                                HapticManager.shared.light()
                                // Toggle: tap again to deselect
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTeamMemberId = isSelected ? nil : row.userId
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .lineLimit(1)
                                    Text(WorkTimeEntry.formattedDuration(minutes: row.totalMinutes))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.orange)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? Color.orange : Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? Color.orange : Color.orange.opacity(0.25), lineWidth: isSelected ? 0 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var exportBar: some View {
        HStack(spacing: 12) {
            Button {
                exportExcelSpreadsheet()
            } label: {
                Label("Export Excel (CSV)".localized, systemImage: "tablecells")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                exportPDF()
            } label: {
                Label("Export PDF".localized, systemImage: "doc.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canTapSelectedCalendar: Bool {
        if viewAllTeam {
            guard let uid = selectedTeamMemberId, let my = Auth.auth().currentUser?.uid else { return false }
            return uid == my
        }
        return true
    }

    private func reloadStore() {
        store.cancelLoad()
        let viewAll = isFranchiseManager && managerScope == .team
        store.loadEntries(forMonth: selectedMonth, viewAllInFranchise: viewAll)
    }

    private func openEditor(for day: Date) {
        guard canTapSelectedCalendar || (viewAllTeam && selectedTeamMemberId != nil) else { return }
        let key = WorkTimeEntry.dayKey(for: day)
        let entry = entriesForCalendar.first { $0.dayKey == key }
        let readOnly = viewAllTeam && selectedTeamMemberId != nil && selectedTeamMemberId != Auth.auth().currentUser?.uid

        if readOnly, let entry {
            HapticManager.shared.light()
            editorContext = WorkDayEditorContext(day: day, entry: entry, mode: .readOnly)
        } else if !readOnly {
            HapticManager.shared.light()
            editorContext = WorkDayEditorContext(day: day, entry: entry, mode: .editable)
        }
    }

    private func exportPayloadEntries() -> [WorkTimeEntry] {
        if isFranchiseManager && managerScope == .team {
            return store.entries.sorted { ($0.userId, $0.dayKey) < ($1.userId, $1.dayKey) }
        }
        return store.entries.filter { $0.userId == Auth.auth().currentUser?.uid }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private func exportExcelSpreadsheet() {
        exportError = nil
        let data = exportPayloadEntries()
        guard !data.isEmpty else {
            exportError = "No rows to export.".localized
            return
        }
        let mTitle = WorkTimeMonthCalendarView.monthTitle(for: selectedMonth)
        let csv = WorkTimeExportHelper.buildCSV(entries: data, monthTitle: mTitle)
        do {
            let url = try WorkTimeExportHelper.writeTempCSV(csv)
            shareItem = WorkSharePayload(url: url)
            HapticManager.shared.medium()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportPDF() {
        exportError = nil
        let data = exportPayloadEntries()
        guard !data.isEmpty else {
            exportError = "No rows to export.".localized
            return
        }
        let mTitle = WorkTimeMonthCalendarView.monthTitle(for: selectedMonth)
        let title = "Work hours".localized
        guard let url = WorkTimeExportHelper.makePDF(entries: data, title: title, monthTitle: mTitle) else {
            exportError = "Could not create PDF.".localized
            return
        }
        shareItem = WorkSharePayload(url: url)
        HapticManager.shared.medium()
    }
}

// MARK: - Supporting types

private enum ManagerWorkScope: Hashable {
    case myHours
    case team
}

struct WorkSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct WorkDayEditorContext: Identifiable {
    let id = UUID()
    let day: Date
    let entry: WorkTimeEntry?
    let mode: EditorMode

    enum EditorMode {
        case editable
        case readOnly
    }
}

// MARK: - Month calendar grid

struct WorkTimeMonthCalendarView: View {
    let month: Date
    let entries: [WorkTimeEntry]
    let canTapDay: Bool
    var onSelect: (Date) -> Void

    private var calendar: Calendar { Calendar.current }

    private var gridDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leading = (firstWeekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: startOfMonth) {
                cells.append(date)
            }
        }
        return cells
    }

    private var weekdaySymbols: [String] {
        let syms = calendar.shortWeekdaySymbols
        if syms.count == 7 {
            return Array(syms[1...]) + [syms[0]]
        }
        return syms
    }

    static func monthTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Self.monthTitle(for: month))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                // Legend
                HStack(spacing: 10) {
                    legendItem(color: .orange, label: "Work".localized)
                    legendItem(color: .green, label: "Holiday".localized)
                }
                .font(.system(size: 10, weight: .medium))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdaySymbols[i])
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, dayOpt in
                    if let day = dayOpt {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let key = WorkTimeEntry.dayKey(for: day)
        let entry = entries.first { $0.dayKey == key }
        let isToday = calendar.isDateInToday(day)
        let tapEnabled = canTapDay || entry != nil
        let isHoliday = entry?.isHoliday == true
        let isWorked = entry != nil && !isHoliday

        let accentColor: Color = isHoliday ? .green : (isWorked ? .orange : .clear)
        let bgColor: Color = isHoliday
            ? Color.green.opacity(0.15)
            : (isWorked ? Color.orange.opacity(0.15) : Color(.systemBackground).opacity(0.4))

        Button {
            if tapEnabled { onSelect(day) }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isHoliday ? Color.green : (isWorked ? Color.orange : Color.primary))
                if isHoliday {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.green)
                } else if let entry, entry.totalMinutes > 0 {
                    Text(WorkTimeEntry.formattedDuration(minutes: entry.totalMinutes))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday ? Color.orange : (accentColor == .clear ? Color.clear : accentColor.opacity(0.4)), lineWidth: isToday ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!tapEnabled && entry == nil)
        .opacity(tapEnabled ? 1 : 0.45)
    }
}

// MARK: - Day editor

struct WorkTimeDayEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let context: WorkDayEditorContext
    let profile: UserProfile?
    let onSave: (Date, Date, String, Bool) async throws -> Void
    let onDelete: () async throws -> Void
    var onFinished: () -> Void

    @State private var clockIn = Date()
    @State private var clockOut = Date()
    @State private var notes = ""
    @State private var isHoliday = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showSaveConfirm = false
    @State private var showDeleteConfirmSheet = false
    @State private var canDeleteStoredEntry = false
    @State private var isDeleting = false
    @State private var showAuditHistory = false

    private var editable: Bool { context.mode == .editable }
    private var day: Date { context.day }

    private var canViewAuditTrail: Bool {
        guard let role = profile?.role else { return false }
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    private var auditRecordId: String? {
        let dayKey = WorkTimeEntry.dayKey(for: day)
        if let entry = context.entry {
            return WorkTimeEntry.documentId(userId: entry.userId, dayKey: entry.dayKey)
        }
        guard let myUid = Auth.auth().currentUser?.uid else { return nil }
        return WorkTimeEntry.documentId(userId: myUid, dayKey: dayKey)
    }

    private var liveMinutes: Int {
        let cin = WorkTimeEntry.combine(day: day, timeSource: clockIn)
        let cout = WorkTimeEntry.combine(day: day, timeSource: clockOut)
        return WorkTimeEntry.totalMinutes(day: day, clockIn: cin, clockOut: cout)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    durationHeroCard

                    editorCard(title: "Day type".localized, icon: "leaf.fill") {
                        Toggle(isOn: $isHoliday) {
                            Text("Mark as Holiday".localized)
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(.green)
                        .disabled(!editable)
                    }

                    if !isHoliday {
                        editorCard(title: "Times".localized, icon: "clock.fill") {
                            DatePicker("Clock in".localized, selection: $clockIn, displayedComponents: .hourAndMinute)
                                .disabled(!editable)
                            Divider()
                            DatePicker("Clock out".localized, selection: $clockOut, displayedComponents: .hourAndMinute)
                                .disabled(!editable)
                        }
                    }

                    editorCard(title: "Notes".localized, icon: "text.alignleft") {
                        TextField("Optional notes".localized, text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .disabled(!editable)
                    }

                    if let err = errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, editable ? 88 : 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(shortDayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
                if canViewAuditTrail, auditRecordId != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAuditHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("Work time history".localized)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editable {
                    bottomActionBar
                }
            }
            .confirmationDialog(
                "Save changes?".localized,
                isPresented: $showSaveConfirm,
                titleVisibility: .visible
            ) {
                Button("Update".localized) {
                    Task { await save() }
                }
                Button("Cancel".localized, role: .cancel) {}
            } message: {
                Text("Are you sure you want to update this entry?".localized)
            }
            .sheet(isPresented: $showDeleteConfirmSheet) {
                WorkTimeDeleteConfirmSheet(
                    dayTitle: shortDayTitle,
                    isDeleting: isDeleting,
                    onCancel: {
                        print("🗑️ [WorkTimeDelete] UI cancel tapped")
                        showDeleteConfirmSheet = false
                    },
                    onConfirm: {
                        print("🗑️ [WorkTimeDelete] UI confirm tapped")
                        Task { await performDelete() }
                    }
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isDeleting)
            }
            .sheet(isPresented: $showAuditHistory) {
                if let recordId = auditRecordId {
                    WorkTimeAuditHistorySheet(recordId: recordId, dayTitle: shortDayTitle)
                }
            }
            .interactiveDismissDisabled(isBusy || isDeleting)
            .onAppear {
                applyInitialValues()
                canDeleteStoredEntry = context.entry != nil
                let dk = WorkTimeEntry.dayKey(for: day)
                print("🗑️ [WorkTimeDelete] editor open dayKey=\(dk) hasEntry=\(context.entry != nil) editable=\(editable)")
            }
        }
    }

    private var durationHeroCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: isHoliday ? "leaf.fill" : "clock.badge.checkmark.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isHoliday ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(isHoliday ? "Holiday".localized : "Duration".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(isHoliday ? "—" : WorkTimeEntry.formattedDuration(minutes: liveMinutes))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func editorCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : Color(.systemBackground))
        )
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if canDeleteStoredEntry {
                    Button {
                        print("🗑️ [WorkTimeDelete] Remove tapped — opening confirm sheet")
                        showDeleteConfirmSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(isDeleting ? "Removing…".localized : "Remove".localized)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isDeleting || isBusy)
                }

                Button {
                    if context.entry != nil {
                        showSaveConfirm = true
                    } else {
                        Task { await save() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isBusy && !isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text("Save".localized)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isBusy || isDeleting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var shortDayTitle: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        return f.string(from: day)
    }

    private func applyInitialValues() {
        if let e = context.entry {
            clockIn = e.clockIn
            clockOut = e.clockOut
            notes = e.notes
            isHoliday = e.isHoliday
        } else {
            let cal = Calendar.current
            let base = cal.startOfDay(for: day)
            let inMin = UserDefaults.standard.object(forKey: "wt.defInM") as? Int ?? (8 * 60)
            let outMin = UserDefaults.standard.object(forKey: "wt.defOutM") as? Int ?? (17 * 60)
            clockIn = cal.date(byAdding: .minute, value: inMin, to: base) ?? base
            clockOut = cal.date(byAdding: .minute, value: outMin, to: base) ?? base
            isHoliday = false
        }
    }

    private func persistTimeDefaults(mergedIn: Date, mergedOut: Date) {
        let cal = Calendar.current
        let inh = cal.component(.hour, from: mergedIn)
        let inm = cal.component(.minute, from: mergedIn)
        let outh = cal.component(.hour, from: mergedOut)
        let outm = cal.component(.minute, from: mergedOut)
        UserDefaults.standard.set(inh * 60 + inm, forKey: "wt.defInM")
        UserDefaults.standard.set(outh * 60 + outm, forKey: "wt.defOutM")
    }

    private func save() async {
        guard editable else { return }
        isBusy = true
        errorMessage = nil
        let mergedIn = WorkTimeEntry.combine(day: day, timeSource: clockIn)
        let mergedOut = WorkTimeEntry.combine(day: day, timeSource: clockOut)
        do {
            try await onSave(mergedIn, mergedOut, notes, isHoliday)
            if !isHoliday { persistTimeDefaults(mergedIn: mergedIn, mergedOut: mergedOut) }
            HapticManager.shared.medium()
            dismiss()
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func performDelete() async {
        guard editable else {
            print("❌ [WorkTimeDelete] aborted — not editable")
            return
        }
        guard canDeleteStoredEntry else {
            print("❌ [WorkTimeDelete] aborted — canDeleteStoredEntry=false")
            errorMessage = "No saved entry to delete.".localized
            return
        }
        isDeleting = true
        isBusy = true
        errorMessage = nil
        print("🗑️ [WorkTimeDelete] performDelete started")
        do {
            try await onDelete()
            print("✅ [WorkTimeDelete] performDelete success — closing editor")
            HapticManager.shared.light()
            canDeleteStoredEntry = false
            showDeleteConfirmSheet = false
            isDeleting = false
            isBusy = false
            dismiss()
            onFinished()
        } catch {
            print("❌ [WorkTimeDelete] performDelete error: \(error.localizedDescription)")
            showDeleteConfirmSheet = false
            errorMessage = error.localizedDescription
            isDeleting = false
            isBusy = false
        }
    }
}

// MARK: - Delete confirmation (stable sheet — avoids SwiftUI alert dismiss bugs)

private struct WorkTimeDeleteConfirmSheet: View {
    let dayTitle: String
    let isDeleting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)

            VStack(spacing: 6) {
                Text("Delete this day's work entry?".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(dayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("This action cannot be undone.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Cancel".localized) {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .disabled(isDeleting)

                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Delete".localized)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
        }
        .padding(24)
    }
}

// MARK: - Audit history (on demand — never auto-refreshes the editor)

private struct WorkTimeAuditHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let recordId: String
    let dayTitle: String

    @State private var auditLogs: [AuditLog] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history…".localized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView(
                        "Could not load history".localized,
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if auditLogs.isEmpty {
                    ContentUnavailableView(
                        "No work time audit entries.".localized,
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Changes to this day will appear here.".localized)
                    )
                } else {
                    List(auditLogs) { log in
                        WorkTimeAuditLogRow(log: log)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Work time history".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func loadOnce() {
        guard isLoading else { return }
        AuditTrailManager.shared.fetchLogs(for: recordId) { logs in
            auditLogs = logs
            isLoading = false
        }
    }
}

private struct WorkTimeAuditLogRow: View {
    let log: AuditLog

    private var actionColor: Color {
        switch log.action {
        case .deleted: return .red
        case .created: return .green
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: log.action == .deleted ? "trash.fill" : (log.action == .created ? "plus.circle.fill" : "pencil.circle.fill"))
                    .foregroundStyle(actionColor)
                Text(log.action.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(actionColor)
                Spacer()
                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let name = log.userName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let changedKeys = ["clockIn", "clockOut", "totalMinutes", "notes"].filter { log.changes[$0] != nil }
            ForEach(changedKeys, id: \.self) { key in
                if let change = log.changes[key] {
                    HStack(alignment: .top, spacing: 6) {
                        Text(key + ":")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let before = change.before, !before.isEmpty {
                            Text(before)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .strikethrough()
                        }
                        if let after = change.after, !after.isEmpty {
                            Text("→ " + after)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plan Section

struct WorkTimePlanSection: View {
    let month: Date
    @EnvironmentObject private var authManager: AuthenticationManager
    @StateObject private var planStore = WorkTimePlanStore()
    @State private var showPlanViewer = false
    @State private var showUploadPicker = false    // drives action-sheet dialog only
    @State private var showPhotoPicker = false      // drives .photosPicker directly
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var canManagePlan: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Plan".localized, systemImage: "doc.richtext")
                    .font(.headline)
                Spacer()
                if canManagePlan {
                    Button {
                        HapticManager.shared.light()
                        if planStore.plan != nil {
                            showDeleteConfirm = true
                        } else {
                            showUploadPicker = true
                        }
                    } label: {
                        Text(planStore.plan != nil ? "Replace Plan".localized : "Upload Plan".localized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .confirmationDialog("Delete Plan".localized, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                        Button("Delete".localized, role: .destructive) {
                            Task { await performDelete() }
                        }
                        Button("Replace Plan".localized) { showUploadPicker = true }
                        Button("Cancel".localized, role: .cancel) {}
                    }
                }
            }

            if planStore.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if let plan = planStore.plan {
                planCard(plan)
            } else {
                Text("No plan uploaded yet.".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if planStore.isUploading {
                HStack {
                    ProgressView()
                    Text("Uploading...".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear { planStore.loadPlan(forMonth: month) }
        .onChange(of: month) { _, new in planStore.loadPlan(forMonth: new) }
        .confirmationDialog("Upload Plan".localized, isPresented: $showUploadPicker, titleVisibility: .visible) {
            Button("Photo / Image".localized) {
                showUploadPicker = false
                selectedPhotoItem = nil
                showPhotoPicker = true
            }
            Button("Document (PDF, Excel, etc.)".localized) {
                showUploadPicker = false
                showDocumentPicker = true
            }
            Button("Cancel".localized, role: .cancel) {
                showUploadPicker = false
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
        .sheet(isPresented: $showDocumentPicker) {
            WorkTimePlanDocumentPicker { url in
                Task { await uploadDocument(url) }
            }
        }
        .sheet(isPresented: $showPlanViewer) {
            if let plan = planStore.plan {
                WorkTimePlanViewerSheet(plan: plan)
            }
        }
    }

    private func planCard(_ plan: WorkTimePlan) -> some View {
        Button {
            HapticManager.shared.light()
            showPlanViewer = true
        } label: {
            HStack(spacing: 14) {
                // Large icon — no filename shown
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.13))
                        .frame(width: 52, height: 52)
                    Image(systemName: iconForContentType(plan.contentType))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(labelForContentType(plan.contentType))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Uploaded by".localized + " " + plan.uploaderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(Color.orange.opacity(0.7))
            }
            .padding(14)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func iconForContentType(_ ct: String) -> String {
        if ct.hasPrefix("image") { return "photo.fill" }
        if ct.contains("pdf") { return "doc.richtext.fill" }
        if ct.contains("excel") || ct.contains("spreadsheet") || ct.contains("csv") { return "tablecells.badge.ellipsis" }
        return "doc.fill"
    }

    private func labelForContentType(_ ct: String) -> String {
        if ct.hasPrefix("image") { return "Photo".localized }
        if ct.contains("pdf") { return "PDF" }
        if ct.contains("excel") || ct.contains("spreadsheet") { return "Excel / Spreadsheet".localized }
        if ct.contains("csv") { return "CSV" }
        return "Document".localized
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let fileName = "plan_\(WorkTimePlan.monthKey(for: month)).jpg"
            try await planStore.uploadPlan(data: data, contentType: "image/jpeg", fileName: fileName, month: month, profile: authManager.userProfile)
            HapticManager.shared.medium()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadDocument(_ url: URL) async {
        errorMessage = nil
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let ct: String
            switch ext {
            case "pdf": ct = "application/pdf"
            case "xlsx", "xls": ct = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case "csv": ct = "text/csv"
            case "jpg", "jpeg": ct = "image/jpeg"
            case "png": ct = "image/png"
            default: ct = "application/octet-stream"
            }
            try await planStore.uploadPlan(data: data, contentType: ct, fileName: url.lastPathComponent, month: month, profile: authManager.userProfile)
            HapticManager.shared.medium()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performDelete() async {
        errorMessage = nil
        do {
            try await planStore.deletePlan(forMonth: month)
            HapticManager.shared.light()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Document Picker UIKit wrapper

struct WorkTimePlanDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .spreadsheet, .commaSeparatedText, .jpeg, .png, .image, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Plan viewer sheet

struct WorkTimePlanViewerSheet: View {
    let plan: WorkTimePlan
    @Environment(\.dismiss) private var dismiss
    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = false

    private var navTitle: String {
        if plan.contentType.hasPrefix("image") { return "Photo".localized }
        if plan.contentType.contains("pdf") { return "PDF" }
        return "Document".localized
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.contentType.hasPrefix("image") {
                    imageViewer
                } else {
                    linkViewer
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let url = URL(string: plan.fileURL) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var imageViewer: some View {
        if let img = loadedImage {
            WorkTimeZoomableImageView(image: img)
                .ignoresSafeArea(edges: .bottom)
        } else if isLoadingImage {
            ZStack {
                Color.black
                ProgressView()
                    .tint(.white)
            }
        } else {
            Color.black.onAppear { loadImage() }
        }
    }

    @ViewBuilder
    private var linkViewer: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: plan.contentType.contains("pdf") ? "doc.richtext.fill" : "tablecells.badge.ellipsis")
                    .font(.system(size: 72))
                    .foregroundStyle(.orange)
                VStack(spacing: 8) {
                    Text(plan.contentType.contains("pdf") ? "PDF" : "Spreadsheet")
                        .font(.title3.weight(.bold))
                    Text("Uploaded by".localized + " " + plan.uploaderName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(plan.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = URL(string: plan.fileURL) {
                    Link(destination: url) {
                        Label("Open file".localized, systemImage: "arrow.up.right.square.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func loadImage() {
        guard let url = URL(string: plan.fileURL) else { return }
        isLoadingImage = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoadingImage = false
                if let data, let img = UIImage(data: data) {
                    loadedImage = img
                }
            }
        }.resume()
    }
}

// MARK: - Zoomable image viewer (UIScrollView-based, supports pinch + double-tap)

struct WorkTimeZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        DispatchQueue.main.async {
            guard let imageView = context.coordinator.imageView else { return }
            let size = uiView.bounds.size
            guard size != .zero else { return }
            imageView.frame = CGRect(origin: .zero, size: size)
            uiView.contentSize = size
            context.coordinator.centerContent()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

        func centerContent() {
            guard let sv = scrollView, let iv = imageView else { return }
            let offsetX = max((sv.bounds.width  - iv.frame.width)  / 2, 0)
            let offsetY = max((sv.bounds.height - iv.frame.height) / 2, 0)
            iv.frame.origin = CGPoint(x: offsetX, y: offsetY)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > sv.minimumZoomScale {
                sv.setZoomScale(sv.minimumZoomScale, animated: true)
            } else {
                let loc = gesture.location(in: gesture.view)
                let rect = CGRect(x: loc.x - 60, y: loc.y - 60, width: 120, height: 120)
                sv.zoom(to: rect, animated: true)
            }
        }
    }
}
