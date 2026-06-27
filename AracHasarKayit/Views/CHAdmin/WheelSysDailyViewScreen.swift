import SwiftUI

/// WheelSys Daily View — operational tabs for a selected station and date.
struct WheelSysDailyViewScreen: View {
    let sessionValid: Bool
    var reloadTrigger: Int = 0
    var hubMode: Bool = true
    var onSessionExpired: (() -> Void)?

    @StateObject private var dailyVM: WheelSysDailyViewViewModel
    @State private var assignContext: WheelSysAssignBookingContext?
    @State private var detailRow: WheelSysDailyViewRow?

    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!
    private static let palantirPurple = Color(red: 0.427, green: 0.365, blue: 0.988)
    private static let zurichDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = zurichTimeZone
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let assignedRowBorder = palantirPurple
    private static let assignedRowFill = palantirPurple.opacity(0.14)
    private static let unassignedRowBorder = PalantirTheme.textMuted.opacity(0.45)
    private static let unassignedRowFill = PalantirTheme.surfaceHigh

    private var formattedSelectedDay: String {
        Self.zurichDayFormatter.string(from: dailyVM.selectedDay)
    }

    private var visibleTabs: [WheelSysDailyViewTab] {
        hubMode ? WheelSysDailyViewTab.hubTabs : WheelSysDailyViewTab.allCases
    }

    init(
        sessionValid: Bool,
        franchiseId: String,
        reloadTrigger: Int = 0,
        hubMode: Bool = true,
        onSessionExpired: (() -> Void)? = nil
    ) {
        self.sessionValid = sessionValid
        self.reloadTrigger = reloadTrigger
        self.hubMode = hubMode
        self.onSessionExpired = onSessionExpired
        _dailyVM = StateObject(wrappedValue: WheelSysDailyViewViewModel(
            franchiseId: franchiseId.uppercased(),
            onSessionExpired: onSessionExpired
        ))
    }

    var body: some View {
        Group {
            if !sessionValid {
                sessionRequiredPlaceholder
            } else if dailyVM.loading && dailyVM.count(for: dailyVM.selectedTab) == 0 && allTabsEmpty {
                ProgressView("wheelsys_daily.loading".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dailyContent
            }
        }
        .task(id: reloadTrigger) {
            guard sessionValid else { return }
            await dailyVM.loadDailyView()
        }
        .alert("Error".localized, isPresented: Binding(
            get: { dailyVM.errorMessage != nil },
            set: { if !$0 { dailyVM.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(dailyVM.errorMessage ?? "")
        }
        .sheet(item: $assignContext) { context in
            WheelSysAssignVehicleSheet(
                bookingEntityId: context.bookingEntityId,
                carGroup: context.carGroup,
                dateFrom: context.dateFrom,
                dateTo: context.dateTo,
                station: context.station,
                resNo: context.resNo,
                confirmationNo: context.confirmationNo
            ) { _, _ in
                Task { await dailyVM.loadDailyView() }
            }
        }
        .sheet(item: $detailRow) { row in
            WheelSysDailyViewDetailSheet(row: row, tab: dailyVM.selectedTab)
        }
    }

    private var allTabsEmpty: Bool {
        visibleTabs.allSatisfy { dailyVM.count(for: $0) == 0 }
    }

    // MARK: Content

    private var dailyContent: some View {
        VStack(spacing: 0) {
            toolbar
            tabPicker
            searchBar
            rowList
        }
        .background(PalantirTheme.background)
        .refreshable {
            await dailyVM.loadDailyView()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            WheelSysJournalDateToolbar(
                formattedDay: formattedSelectedDay,
                isLoading: dailyVM.loading,
                onPrevious: { dailyVM.shiftDay(-1) },
                onNext: { dailyVM.shiftDay(1) },
                onToday: { dailyVM.goToToday() }
            )

            Button {
                HapticManager.shared.selection()
                Task { await dailyVM.loadDailyView() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(dailyVM.loading)
        }
    }

    private var dailyColumnHeader: some View {
        HStack(spacing: 8) {
            Text("wheelsys_journal.col_res".localized)
                .frame(width: 60, alignment: .leading)
            Text("ch_ops.col_plate".localized)
                .frame(width: 92, alignment: .leading)
            Text("ch_ops.col_group".localized)
                .frame(width: 36, alignment: .leading)
            Text("wheelsys_journal.col_driver".localized)
                .frame(width: 88, alignment: .leading)
            Text("wheelsys_journal.col_fuel".localized)
                .frame(width: 28, alignment: .leading)
            Text("ch_ops.col_time".localized)
                .frame(width: 40, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8, weight: .bold))
        .textCase(.uppercase)
        .foregroundStyle(PalantirTheme.textMuted)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleTabs) { tab in
                    let selected = dailyVM.selectedTab == tab
                    Button {
                        HapticManager.shared.selection()
                        dailyVM.selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.title)
                            Text("(\(dailyVM.count(for: tab)))")
                                .foregroundStyle(selected ? .white.opacity(0.85) : PalantirTheme.textMuted)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selected ? Self.palantirPurple : PalantirTheme.surfaceHigh)
                        .foregroundStyle(selected ? .white : PalantirTheme.textPrimary)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(PalantirTheme.surface)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("wheelsys_daily.search_placeholder".localized, text: $dailyVM.searchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var rowList: some View {
        let rows = dailyVM.rows(for: dailyVM.selectedTab)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if dailyVM.selectedTab != .available {
                    dailyColumnHeader
                }
                if rows.isEmpty {
                    Text("wheelsys_daily.empty".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if dailyVM.selectedTab == .available {
                            availablePalantirRow(row)
                                .onTapGesture(count: 2) {
                                    HapticManager.shared.selection()
                                    detailRow = row
                                }
                        } else {
                            palantirJournalRow(row, index: index)
                                .onTapGesture(count: 2) {
                                    HapticManager.shared.selection()
                                    detailRow = row
                                }
                        }
                    }
                }
            }
        }
    }

    private func palantirJournalRow(_ row: WheelSysDailyViewRow, index: Int) -> some View {
        let res = row.resNo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (row.resNo ?? row.displayDocNo)
            : row.displayDocNo
        let accent = row.isUnassigned ? Self.unassignedRowBorder : Self.assignedRowBorder
        let fill = row.isUnassigned ? Self.unassignedRowFill : Self.assignedRowFill
        return VStack(spacing: 0) {
            WheelSysPalantirJournalListRow(
                accentColor: accent,
                backgroundColor: fill,
                resText: res,
                plateText: row.plate,
                groupText: row.vehicleGroup,
                driverText: row.driverName,
                fuelText: row.fuelText == "—" ? "" : row.fuelText,
                timeText: row.timeText
            )
            if row.isUnassigned, let entityId = row.bookingEntityId, entityId > 0 {
                HStack {
                    Spacer()
                    Button {
                        HapticManager.shared.medium()
                        assignContext = assignContext(for: row, entityId: entityId)
                    } label: {
                        Label("wheelsys_journal.assign_vehicle".localized, systemImage: "car.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.palantirPurple)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .background(fill)
            }
        }
    }

    private func availablePalantirRow(_ row: WheelSysDailyViewRow) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Self.assignedRowBorder)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.plate.isEmpty ? "—" : row.plate)
                        .font(.subheadline.weight(.bold).monospaced())
                    Spacer()
                    if !row.vehicleGroup.isEmpty {
                        PalantirOpsBadge(text: row.vehicleGroup, tone: .accent)
                    }
                }
                if !row.model.isEmpty {
                    Text(row.model)
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textPrimary)
                }
                HStack(spacing: 12) {
                    if let km = row.mileage {
                        Text("\(km) km")
                            .font(PalantirTheme.dataFont(12))
                    }
                    if !row.fuelText.isEmpty, row.fuelText != "—" {
                        Text("\(row.fuelText)/8")
                            .font(PalantirTheme.dataFont(12))
                    }
                }
                .foregroundStyle(PalantirTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 38)
        .background(Self.assignedRowFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private var sessionRequiredPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(PalantirTheme.textMuted)
            Text("wheelsys_checkin.session_required".localized)
                .font(.subheadline)
                .foregroundStyle(PalantirTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func assignContext(for row: WheelSysDailyViewRow, entityId: Int) -> WheelSysAssignBookingContext {
        let from = row.dateFrom ?? dailyVM.selectedDay
        let to = row.dateTo ?? Calendar.current.date(byAdding: .day, value: 1, to: from) ?? from
        // resNo is the RES-XXXXX code; confirmationNo is the external agent code
        let res: String? = {
            if let r = row.resNo, WheelSysResCode.isReservationCode(r) { return r }
            return row.resNo ?? (WheelSysResCode.isReservationCode(row.displayDocNo) ? row.displayDocNo : nil)
        }()
        let conf: String? = {
            if WheelSysResCode.isReservationCode(row.displayDocNo) { return nil }
            return row.displayDocNo.isEmpty ? nil : row.displayDocNo
        }()
        return WheelSysAssignBookingContext(
            bookingEntityId: entityId,
            carGroup: row.carGroup.isEmpty ? row.vehicleGroup : row.carGroup,
            dateFrom: from,
            dateTo: to,
            station: row.station.isEmpty ? dailyVM.station : row.station,
            resNo: res,
            confirmationNo: conf
        )
    }
}

// MARK: - Simple flow layout for badges

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

private struct WheelSysDailyViewDetailSheet: View {
    let row: WheelSysDailyViewRow
    let tab: WheelSysDailyViewTab

    @Environment(\.dismiss) private var dismiss

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WheelSysPalantirSectionCard(
                    title: "wheelsys_daily.process_detail".localized,
                    icon: "doc.text.magnifyingglass"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        compactLine("wheelsys_journal.col_res".localized, detailRes)
                        compactLine("ch_ops.col_plate".localized, row.plate.isEmpty ? "—" : row.plate)
                        if !row.driverName.isEmpty {
                            compactLine("wheelsys_journal.col_driver".localized, row.driverName)
                        }
                        if !row.vehicleGroup.isEmpty {
                            compactLine("ch_ops.col_group".localized, row.vehicleGroup)
                        }
                        if let period = rentalPeriodText {
                            compactLine("wheelsys_daily.rental_period".localized, period)
                        } else if !row.timeText.isEmpty {
                            compactLine("ch_ops.col_time".localized, row.timeText)
                        }
                        if let km = row.mileage {
                            compactLine("wheelsys_daily.col_mileage".localized, "\(km)")
                        }
                        if !row.fuelText.isEmpty, row.fuelText != "—" {
                            compactLine("wheelsys_journal.col_fuel".localized, row.fuelText)
                        }
                        if !row.agentName.isEmpty {
                            compactLine("wheelsys_daily.performed_by".localized, row.agentName)
                        }
                        if !row.statusBadges.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(row.statusBadges, id: \.self) { badge in
                                    PalantirOpsBadge(text: badge, tone: .accent)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                Spacer(minLength: 0)
            }
            .background(PalantirTheme.background)
            .navigationTitle(tab.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var detailRes: String {
        let res = row.resNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !res.isEmpty { return res }
        return row.displayDocNo.isEmpty ? "—" : row.displayDocNo
    }

    private var rentalPeriodText: String? {
        switch (row.dateFrom, row.dateTo) {
        case let (from?, to?):
            return "\(Self.dayFormatter.string(from: from)) – \(Self.dayFormatter.string(from: to))"
        case let (from?, nil):
            return Self.dayFormatter.string(from: from)
        case let (nil, to?):
            return Self.dayFormatter.string(from: to)
        default:
            return nil
        }
    }

    private func compactLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(PalantirTheme.dataFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
