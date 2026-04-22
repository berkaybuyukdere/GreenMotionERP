import SwiftUI

/// Day planner: search, collapsible sections, tap date for calendar, same-day check-outs / returns.
struct OperationsHubView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDay = Date()
    @State private var searchText = ""
    @State private var showDatePickerSheet = false
    @State private var expandedCheckouts = true
    @State private var expandedReturns = true
    /// After finishing a return from this hub, show read-only detail (not only popping to the list).
    @State private var returnDetailAfterComplete: IadeIslemi?

    private var dayStart: Date {
        Calendar.current.startOfDay(for: selectedDay)
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
    }

    /// Matches web Operations: finished check-out wizard (including “parked / awaiting code”) counts as done, not “waiting”.
    private func checkoutIsDone(_ ex: ExitIslemi) -> Bool {
        ex.status == .completed || ex.status == .parked
    }

    /// Same logic as web `operationsDedupe.js`: pending web doc may use `qr:*` while iOS completed doc does not — fall back to vehicle + NAV.
    private func exitNavNormalized(_ ex: ExitIslemi) -> String {
        let raw = (ex.navKodu ?? ex.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = raw.filter { $0.isNumber }
        if digits.isEmpty { return raw.lowercased() }
        return String(digits)
    }

    private func exitBusinessDedupeKey(_ ex: ExitIslemi) -> String {
        let qt = ex.qrToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qt.isEmpty { return "qr:\(qt)" }
        let nav = exitNavNormalized(ex)
        let aid = ex.aracId.uuidString.lowercased()
        let plt = ex.aracPlaka.replacingOccurrences(of: " ", with: "").lowercased()
        if !nav.isEmpty {
            if !aid.isEmpty { return "aid:\(aid)|nav:\(nav)" }
            if !plt.isEmpty { return "plt:\(plt)|nav:\(nav)" }
        }
        return "id:\(ex.id.uuidString.lowercased())"
    }

    private func exitWeakDedupeKey(_ ex: ExitIslemi) -> String? {
        let nav = exitNavNormalized(ex)
        guard !nav.isEmpty else { return nil }
        let aid = ex.aracId.uuidString.lowercased()
        return "w:aid:\(aid)|nav:\(nav)"
    }

    /// Collapse duplicate pending returns (same linked checkout or same vehicle + day + email).
    private func returnPendingDedupeKey(_ r: IadeIslemi) -> String {
        if let le = r.linkedExitId {
            return "le:\(le.uuidString.lowercased())"
        }
        let email = (r.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if email.isEmpty {
            return "id:\(r.id.uuidString.lowercased())"
        }
        let plate = r.aracPlaka.replacingOccurrences(of: " ", with: "").lowercased()
        let aid = r.aracId.uuidString.lowercased()
        let day = Int(dayStart.timeIntervalSince1970)
        return "w:aid:\(aid)|plt:\(plate)|d:\(day)|em:\(email)"
    }

    private var exitsOnDay: [ExitIslemi] {
        viewModel.exitIslemleri.filter { $0.exitTarihi >= dayStart && $0.exitTarihi < dayEnd }
    }

    private var returnsOnDay: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { $0.iadeTarihi >= dayStart && $0.iadeTarihi < dayEnd }
    }

    private var pendingExits: [ExitIslemi] {
        let onDay = exitsOnDay
        let done = onDay.filter { checkoutIsDone($0) }
        var completedStrong = Set<String>()
        var completedWeak = Set<String>()
        for ex in done {
            completedStrong.insert(exitBusinessDedupeKey(ex))
            if let w = exitWeakDedupeKey(ex) { completedWeak.insert(w) }
        }
        let base = onDay
            .filter { !checkoutIsDone($0) }
            .filter { ex in
                if completedStrong.contains(exitBusinessDedupeKey(ex)) { return false }
                if let w = exitWeakDedupeKey(ex), completedWeak.contains(w) { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
        // Two Firestore exit docs for the same vehicle + NAV (e.g. web created a second row) still have different
        // `qrToken`, so `exitBusinessDedupeKey` does not merge them. Collapse by weak key; keep newest (`base` order).
        var seenPendingWeak = Set<String>()
        var pendingDeduped: [ExitIslemi] = []
        for ex in base {
            if let w = exitWeakDedupeKey(ex) {
                if seenPendingWeak.contains(w) { continue }
                seenPendingWeak.insert(w)
            }
            pendingDeduped.append(ex)
        }
        return filterSearchExits(pendingDeduped)
    }

    private var doneExits: [ExitIslemi] {
        let sorted = exitsOnDay.filter { checkoutIsDone($0) }
            .sorted { $0.createdAt > $1.createdAt }
        var seenStrong = Set<String>()
        var seenWeak = Set<String>()
        var out: [ExitIslemi] = []
        for ex in sorted {
            let sk = exitBusinessDedupeKey(ex)
            if seenStrong.contains(sk) { continue }
            if let w = exitWeakDedupeKey(ex), seenWeak.contains(w) { continue }
            seenStrong.insert(sk)
            if let w = exitWeakDedupeKey(ex) { seenWeak.insert(w) }
            out.append(ex)
        }
        return filterSearchExits(out)
    }

    private var pendingReturns: [IadeIslemi] {
        let sorted = returnsOnDay.filter { $0.status != .completed }
            .sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var deduped: [IadeIslemi] = []
        for r in sorted {
            let k = returnPendingDedupeKey(r)
            if seen.contains(k) { continue }
            seen.insert(k)
            deduped.append(r)
        }
        return filterSearchReturns(deduped)
    }

    private var doneReturns: [IadeIslemi] {
        let sorted = returnsOnDay.filter { $0.status == .completed }
            .sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var deduped: [IadeIslemi] = []
        for r in sorted {
            let k = returnPendingDedupeKey(r)
            if seen.contains(k) { continue }
            seen.insert(k)
            deduped.append(r)
        }
        return filterSearchReturns(deduped)
    }

    /// Planned return date (`plannedReturnAt` / web `plannedCheckinAt`) on the selected day, after checkout is done and before a completed return exists.
    private var expectedReturnExitsOnDay: [ExitIslemi] {
        let raw = viewModel.exitIslemleri.filter { ex in
            guard let pr = ex.plannedReturnAt else { return false }
            guard pr >= dayStart && pr < dayEnd else { return false }
            guard checkoutIsDone(ex) else { return false }
            if ex.expectedReturnDismissedAt != nil { return false }
            let hasNonCompletedReturn = viewModel.iadeIslemleri.contains {
                $0.aracId == ex.aracId && $0.status != .completed
            }
            if hasNonCompletedReturn { return false }
            let hasCompletedReturnAfter = viewModel.iadeIslemleri.contains {
                $0.aracId == ex.aracId && $0.status == .completed && $0.createdAt > ex.createdAt
            }
            return !hasCompletedReturnAfter
        }
        .sorted { $0.createdAt > $1.createdAt }
        return filterSearchExpectedReturns(raw)
    }

    private func filterSearchExits(_ list: [ExitIslemi]) -> [ExitIslemi] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return list }
        return list.filter { ex in
            ex.aracPlaka.lowercased().contains(q)
                || ex.resKodu.lowercased().contains(q)
                || (ex.navKodu ?? "").lowercased().contains(q)
                || "\(ex.customerFirstName ?? "") \(ex.customerLastName ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .contains(q)
                || (ex.customerEmail ?? "").lowercased().contains(q)
        }
    }

    private func filterSearchReturns(_ list: [IadeIslemi]) -> [IadeIslemi] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return list }
        return list.filter { r in
            r.aracPlaka.lowercased().contains(q)
                || "\(r.customerFirstName ?? "") \(r.customerLastName ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .contains(q)
                || (r.customerEmail ?? "").lowercased().contains(q)
        }
    }

    private func filterSearchExpectedReturns(_ list: [ExitIslemi]) -> [ExitIslemi] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return list }
        return list.filter { ex in
            ex.aracPlaka.lowercased().contains(q)
                || ex.resKodu.lowercased().contains(q)
                || "\(ex.customerFirstName ?? "") \(ex.customerLastName ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .contains(q)
        }
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: selectedDay)
    }

    /// Pairs “Waiting” / “Completed” row heights across Check-outs vs Returns on iPad-wide layout.
    private var opsPairedRowMinHeight: CGFloat { 200 }

    private var operationsCompactLayout: some View {
        VStack(spacing: 14) {
            DisclosureGroup(isExpanded: $expandedCheckouts) {
                VStack(alignment: .leading, spacing: 12) {
                    pendingBlock(title: "Waiting / in progress".localized, exits: pendingExits, returns: nil, expectedReturns: nil, pending: true)
                    pendingBlock(title: "Completed".localized, exits: doneExits, returns: nil, expectedReturns: nil, pending: false)
                }
                .padding(.top, 8)
            } label: {
                Label("Check-outs".localized, systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 4)

            DisclosureGroup(isExpanded: $expandedReturns) {
                VStack(alignment: .leading, spacing: 12) {
                    pendingBlock(
                        title: "Waiting / in progress".localized,
                        exits: nil,
                        returns: pendingReturns,
                        expectedReturns: expectedReturnExitsOnDay,
                        pending: true
                    )
                    pendingBlock(title: "Completed".localized, exits: nil, returns: doneReturns, expectedReturns: nil, pending: false)
                }
                .padding(.top, 8)
            } label: {
                Label("Returns".localized, systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.headline)
                    .foregroundColor(.teal)
            }
            .padding(.horizontal, 4)
        }
    }

    /// Two columns: aligned Waiting row and aligned Completed row (min height per cell).
    private var operationsWideLayout: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Label("Check-outs".localized, systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("Returns".localized, systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.headline)
                    .foregroundColor(.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 16) {
                pendingBlock(title: "Waiting / in progress".localized, exits: pendingExits, returns: nil, expectedReturns: nil, pending: true)
                    .frame(maxWidth: .infinity, minHeight: opsPairedRowMinHeight, alignment: .topLeading)
                pendingBlock(
                    title: "Waiting / in progress".localized,
                    exits: nil,
                    returns: pendingReturns,
                    expectedReturns: expectedReturnExitsOnDay,
                    pending: true
                )
                .frame(maxWidth: .infinity, minHeight: opsPairedRowMinHeight, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 16) {
                pendingBlock(title: "Completed".localized, exits: doneExits, returns: nil, expectedReturns: nil, pending: false)
                    .frame(maxWidth: .infinity, minHeight: opsPairedRowMinHeight, alignment: .topLeading)
                pendingBlock(title: "Completed".localized, exits: nil, returns: doneReturns, expectedReturns: nil, pending: false)
                    .frame(maxWidth: .infinity, minHeight: opsPairedRowMinHeight, alignment: .topLeading)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                dayPickerBar
                ScrollView {
                    Group {
                        if horizontalSizeClass == .regular {
                            operationsWideLayout
                        } else {
                            operationsCompactLayout
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Operations".localized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDatePickerSheet) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "",
                            selection: $selectedDay,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding()
                        Spacer()
                    }
                    .navigationTitle("Select date".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done".localized) { showDatePickerSheet = false }
                        }
                    }
                }
            }
            .sheet(item: $returnDetailAfterComplete) { iade in
                NavigationStack {
                    IadeDetayView(iade: iade)
                        .environmentObject(viewModel)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("operations.search_placeholder".localized, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var dayPickerBar: some View {
        HStack {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                showDatePickerSheet = true
            } label: {
                Text(dayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func shiftDay(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = d
        }
    }

    /// Category · brand model (from loaded vehicles list).
    private func vehicleSummaryLine(for aracId: UUID) -> String {
        guard let a = viewModel.araclar.first(where: { $0.id == aracId }) else { return "—" }
        let mm = [a.marka, a.model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let kat = a.kategori.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !kat.isEmpty { parts.append(kat) }
        if !mm.isEmpty { parts.append(mm) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// Prefill return form from a completed checkout (linked exit + planned return date).
    private func prefillReturnFromExpectedExit(_ exit: ExitIslemi) -> TRFrontDeskHandoverPrefill {
        let digits = exit.resKodu.filter { $0.isNumber }
        let plannedIn = exit.plannedReturnAt ?? exit.exitTarihi
        return TRFrontDeskHandoverPrefill(
            frontDeskDocumentId: "",
            customerFirstName: exit.customerFirstName ?? "",
            customerLastName: exit.customerLastName ?? "",
            customerEmail: exit.customerEmail ?? "",
            navDigits: digits,
            plannedCheckout: exit.exitTarihi,
            plannedCheckin: plannedIn,
            pickupBranchName: exit.pickUpBranch,
            dropoffBranchName: exit.dropOffBranch,
            km: exit.km,
            linkedExitId: exit.id.uuidString
        )
    }

    @ViewBuilder
    private func pendingBlock(
        title: String,
        exits: [ExitIslemi]?,
        returns: [IadeIslemi]?,
        expectedReturns: [ExitIslemi]?,
        pending: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if let exits = exits {
                if exits.isEmpty {
                    Text("None for this day.".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(exits) { ex in
                        if pending {
                            NavigationLink {
                                if let arac = viewModel.araclar.first(where: { $0.id == ex.aracId }) {
                                    ExitIslemView(arac: arac, existingExit: ex, trHandoverPrefill: nil, onExitCompleted: { _ in })
                                } else {
                                    Text("operations.vehicle_missing".localized)
                                        .foregroundColor(.secondary)
                                }
                            } label: {
                                exitRow(ex, pending: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: ExitDetayView(exit: ex)) {
                                exitRow(ex, pending: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let returns = returns {
                if returns.isEmpty && (expectedReturns ?? []).isEmpty {
                    Text("None for this day.".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(returns) { r in
                        if pending {
                            NavigationLink {
                                if let arac = viewModel.araclar.first(where: { $0.id == r.aracId }) {
                                    IadeIslemView(
                                        arac: arac,
                                        existingIade: r,
                                        trReturnHandoverPrefill: nil,
                                        onIadeCompleted: { completed in
                                            returnDetailAfterComplete = completed
                                        }
                                    )
                                } else {
                                    Text("operations.vehicle_missing".localized)
                                        .foregroundColor(.secondary)
                                }
                            } label: {
                                returnRow(r, pending: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: IadeDetayView(iade: r)) {
                                returnRow(r, pending: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let expected = expectedReturns, pending {
                        ForEach(expected) { ex in
                            NavigationLink {
                                if let arac = viewModel.araclar.first(where: { $0.id == ex.aracId }) {
                                    IadeIslemView(
                                        arac: arac,
                                        existingIade: nil,
                                        trReturnHandoverPrefill: prefillReturnFromExpectedExit(ex),
                                        onIadeCompleted: { completed in
                                            returnDetailAfterComplete = completed
                                        }
                                    )
                                } else {
                                    Text("operations.vehicle_missing".localized)
                                        .foregroundColor(.secondary)
                                }
                            } label: {
                                expectedReturnRow(ex)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func exitRow(_ exit: ExitIslemi, pending: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .foregroundColor(pending ? .orange : .green)
            VStack(alignment: .leading, spacing: 4) {
                Text(resDisplay(exit))
                    .font(.system(size: 15, weight: .semibold))
                Text(vehicleSummaryLine(for: exit.aracId))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(exit.aracPlaka)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel(exit.exitTarihi))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func expectedReturnRow(_ exit: ExitIslemi) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("operations.expected_return".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(exit.aracPlaka)
                    .font(.system(size: 15, weight: .semibold))
                Text(vehicleSummaryLine(for: exit.aracId))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let pr = exit.plannedReturnAt {
                Text(timeLabel(pr))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func returnRow(_ r: IadeIslemi, pending: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundColor(pending ? .orange : .green)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.aracPlaka)
                    .font(.system(size: 15, weight: .semibold))
                Text(vehicleSummaryLine(for: r.aracId))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                let email = (r.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                Text(email.isEmpty ? "—" : email)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(timeLabel(r.iadeTarihi))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func resDisplay(_ exit: ExitIslemi) -> String {
        let r = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { return r }
        return exit.aracPlaka
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}
