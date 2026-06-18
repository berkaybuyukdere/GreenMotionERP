import SwiftUI

/// WheelSys Daily View — five operational tabs for a selected station and date.
struct WheelSysDailyViewScreen: View {
    let sessionValid: Bool
    var reloadTrigger: Int = 0
    var onSessionExpired: (() -> Void)?

    @StateObject private var dailyVM: WheelSysDailyViewViewModel
    @State private var assignContext: WheelSysAssignBookingContext?

    private let palantirPurple = Color(red: 0.427, green: 0.365, blue: 0.988)
    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!

    init(
        sessionValid: Bool,
        franchiseId: String,
        reloadTrigger: Int = 0,
        onSessionExpired: (() -> Void)? = nil
    ) {
        self.sessionValid = sessionValid
        self.reloadTrigger = reloadTrigger
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
            ) {
                Task { await dailyVM.loadDailyView() }
            }
        }
    }

    private var allTabsEmpty: Bool {
        WheelSysDailyViewTab.allCases.allSatisfy { dailyVM.count(for: $0) == 0 }
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
            Button { dailyVM.shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            DatePicker("", selection: Binding(
                get: { dailyVM.selectedDay },
                set: { dailyVM.setSelectedDay($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.timeZone, Self.zurichTimeZone)

            Button { dailyVM.shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button("ch_ops.today".localized) { dailyVM.goToToday() }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(PalantirTheme.surfaceHigh)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

            Picker("wheelsys_journal.station".localized, selection: Binding(
                get: { dailyVM.station },
                set: { dailyVM.setStation($0) }
            )) {
                Text("ZRH").tag("ZRH")
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            Button {
                Task { await dailyVM.loadDailyView() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(dailyVM.loading)

            if dailyVM.loading {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(12)
        .background(PalantirTheme.surfaceHigh)
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WheelSysDailyViewTab.allCases) { tab in
                    let selected = dailyVM.selectedTab == tab
                    Button {
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
                        .background(selected ? palantirPurple : PalantirTheme.surfaceHigh)
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
        return List {
            if rows.isEmpty {
                Text("wheelsys_daily.empty".localized)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .listRowBackground(PalantirTheme.background)
            } else {
                ForEach(rows) { row in
                    dailyRow(row)
                        .listRowBackground(PalantirTheme.background)
                        .listRowSeparatorTint(PalantirTheme.border)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func dailyRow(_ row: WheelSysDailyViewRow) -> some View {
        if dailyVM.selectedTab == .available {
            availableRow(row)
        } else {
            standardRow(row)
        }
    }

    private func standardRow(_ row: WheelSysDailyViewRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.displayDocNo.isEmpty ? "—" : row.displayDocNo)
                    .font(.subheadline.weight(.semibold))
                if !row.timeText.isEmpty {
                    Text(row.timeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer()
                if row.isUnassigned {
                    Text("wheelsys.checkout.unassigned".localized)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 10) {
                labelValue("ch_ops.col_plate".localized, row.plate.isEmpty ? "—" : row.plate)
                labelValue("ch_ops.col_group".localized, row.vehicleGroup.isEmpty ? "—" : row.vehicleGroup)
                if !row.model.isEmpty {
                    labelValue("ch_ops.col_model".localized, row.model)
                }
            }

            if !row.driverName.isEmpty {
                Text(row.driverName)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textPrimary)
            }

            HStack(spacing: 10) {
                if !row.fuelText.isEmpty, row.fuelText != "—" {
                    labelValue("wheelsys_journal.col_fuel".localized, row.fuelText)
                }
                if let km = row.mileage {
                    labelValue("wheelsys_daily.col_mileage".localized, "\(km)")
                }
            }

            if !row.statusBadges.isEmpty {
                statusBadges(row.statusBadges)
            }

            if row.isUnassigned, let entityId = row.bookingEntityId, entityId > 0 {
                Button {
                    assignContext = assignContext(for: row, entityId: entityId)
                } label: {
                    Label("wheelsys_journal.assign_vehicle".localized, systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(palantirPurple)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func availableRow(_ row: WheelSysDailyViewRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.plate.isEmpty ? "—" : row.plate)
                    .font(.subheadline.weight(.bold).monospaced())
                Spacer()
                if !row.vehicleGroup.isEmpty {
                    Text(row.vehicleGroup)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palantirPurple.opacity(0.15))
                        .foregroundStyle(palantirPurple)
                }
            }

            if !row.model.isEmpty {
                Text(row.model)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textPrimary)
            }

            HStack(spacing: 12) {
                if let km = row.mileage {
                    labelValue("wheelsys_daily.col_mileage".localized, "\(km)")
                }
                if !row.fuelText.isEmpty, row.fuelText != "—" {
                    labelValue("wheelsys_journal.col_fuel".localized, row.fuelText)
                }
            }

            if let until = row.availableUntil, !until.isEmpty {
                labelValue("wheelsys_daily.col_available_until".localized, until)
            }
            if let checkin = row.lastCheckIn, !checkin.isEmpty {
                labelValue("wheelsys_daily.col_last_checkin".localized, checkin)
            }

            if !row.statusBadges.isEmpty {
                statusBadges(row.statusBadges)
            }
        }
        .padding(.vertical, 4)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(PalantirTheme.textMuted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
    }

    private func statusBadges(_ badges: [String]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
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
