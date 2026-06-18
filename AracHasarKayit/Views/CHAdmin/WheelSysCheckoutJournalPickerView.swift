import SwiftUI

/// CH checkout entry: WheelSys journal with date filter, category highlight, double-tap to select reservation.
struct WheelSysCheckoutJournalPickerView: View {
    let arac: Arac
    var onSelect: (WheelSysCheckoutPrefill) -> Void
    var onCancel: () -> Void

    @StateObject private var journalVM: WheelSysJournalViewModel
    @State private var selectingEntityId: Int?
    @State private var selectionError: String?

    private let palantirPurple = Color(red: 0.427, green: 0.365, blue: 0.988)

    init(
        arac: Arac,
        onSelect: @escaping (WheelSysCheckoutPrefill) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.arac = arac
        self.onSelect = onSelect
        self.onCancel = onCancel
        _journalVM = StateObject(wrappedValue: WheelSysJournalViewModel(
            franchiseId: FirebaseService.shared.currentFranchiseId.uppercased()
        ))
    }

    var body: some View {
        NavigationView {
            Group {
                if journalVM.loading && journalVM.checkoutRows.isEmpty && journalVM.returnRows.isEmpty {
                    ProgressView("wheelsys.checkout.journal_loading".localized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    journalContent
                }
            }
            .navigationTitle("wheelsys.checkout.journal_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { onCancel() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await journalVM.loadJournal() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(journalVM.loading)
                }
            }
            .task {
                await journalVM.loadJournal()
                journalVM.resolveHighlightGroup(forPlate: arac.plaka)
                journalVM.scheduleLazyEnrichment()
            }
            .onChange(of: journalVM.selectedDay) { _, _ in
                journalVM.scheduleLazyEnrichment()
            }
            .alert("Error".localized, isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(selectionError ?? "")
            }
        }
    }

    private var journalContent: some View {
        VStack(spacing: 0) {
            dateToolbar
            if !journalVM.highlightGroup.isEmpty {
                highlightBanner
            }
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 8) {
                    journalColumn(
                        title: "ch_ops.checkout_section".localized,
                        count: journalVM.checkoutRows.count,
                        rows: journalVM.checkoutRows,
                        isCheckout: true,
                        width: geo.size.width * 0.52
                    )
                    journalColumn(
                        title: "ch_ops.return_section".localized,
                        count: journalVM.returnRows.count,
                        rows: journalVM.returnRows,
                        isCheckout: false,
                        width: geo.size.width * 0.48 - 8
                    )
                }
            }
        }
        .background(PalantirTheme.surface)
    }

    private var dateToolbar: some View {
        HStack(spacing: 8) {
            Button { journalVM.shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            DatePicker("", selection: Binding(
                get: { journalVM.selectedDay },
                set: { journalVM.setSelectedDay($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)

            Button { journalVM.shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button("ch_ops.today".localized) { journalVM.goToToday() }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(PalantirTheme.surfaceHigh)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

            Spacer()
            if journalVM.loading {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(12)
        .background(PalantirTheme.surfaceHigh)
    }

    private var highlightBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .foregroundStyle(palantirPurple)
            Text(String(format: "wheelsys.checkout.group_hint".localized, journalVM.highlightGroup, arac.plakaFormatli))
                .font(.caption)
                .foregroundStyle(PalantirTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(palantirPurple.opacity(0.12))
    }

    private func journalColumn(
        title: String,
        count: Int,
        rows: [WheelSysJournalRow],
        isCheckout: Bool,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Text("(\(count))")
                Spacer()
            }
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(PalantirTheme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PalantirTheme.surfaceHigh)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(isCheckout ? "ch_ops.checkout_empty".localized : "ch_ops.return_empty".localized)
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                            .padding(16)
                    } else {
                        ForEach(rows) { row in
                            journalRow(row, isCheckout: isCheckout)
                        }
                    }
                }
            }
        }
        .frame(width: width)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }

    private func journalRow(_ row: WheelSysJournalRow, isCheckout: Bool) -> some View {
        let matchesGroup = rowMatchesHighlight(row)
        let isSelecting = selectingEntityId == row.effectiveBookingEntityId

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(row.rowNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(width: 18, alignment: .leading)
                Text(formatTime(row.eventDateTime))
                    .font(.caption.weight(.semibold))
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
            Text(journalVM.customerName(for: row))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(journalVM.vehicleGroup(for: row))
                    .font(.caption.weight(.bold))
                Text(row.plate.isEmpty ? "—" : row.plate)
                    .font(.caption.monospaced())
                Spacer()
            }
            .foregroundStyle(matchesGroup ? palantirPurple : PalantirTheme.textPrimary)
            if isSelecting {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(matchesGroup ? palantirPurple.opacity(0.14) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onAppear {
            Task { await journalVM.enrichIfNeeded(entityId: row.rentalEntityId) }
        }
        .onTapGesture(count: 2) {
            guard isCheckout else { return }
            Task { await handleCheckoutRowSelected(row) }
        }
    }

    private func rowMatchesHighlight(_ row: WheelSysJournalRow) -> Bool {
        let g = journalVM.highlightGroup.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !g.isEmpty else { return false }
        return journalVM.vehicleGroup(for: row).uppercased() == g
    }

    @MainActor
    private func handleCheckoutRowSelected(_ row: WheelSysJournalRow) async {
        selectingEntityId = row.effectiveBookingEntityId
        defer { selectingEntityId = nil }

        await journalVM.enrichIfNeeded(entityId: row.rentalEntityId)
        let customer = journalVM.customerName(for: row)
        var resNo = ""

        do {
            let preview = try await WheelSysCheckinService.loadBookingPreview(
                franchiseId: FirebaseService.shared.currentFranchiseId,
                entityId: row.effectiveBookingEntityId,
                resNo: journalVM.rentalNumber(for: row) ?? row.rentalNumber,
                displayDocNo: row.rentalNumber
            )
            resNo = preview.resNo
        } catch {
            resNo = resNoFromEnrichment(row) ?? ""
            if resNo.isEmpty {
                selectionError = error.localizedDescription
                return
            }
        }

        let prefill = WheelSysCheckoutPrefill(
            bookingEntityId: row.effectiveBookingEntityId,
            resNo: resNo,
            customerName: customer == "-" ? nil : customer,
            vehicleGroup: journalVM.vehicleGroup(for: row),
            eventDateTime: row.eventDateTime,
            assignedPlate: row.plate.nilIfEmpty,
            isUnassigned: row.isUnassigned
        )
        onSelect(prefill)
    }

    private func resNoFromEnrichment(_ row: WheelSysJournalRow) -> String? {
        if let detail = journalVM.rentalDetailsByEntityId[row.rentalEntityId] {
            if let title = detail.title {
                if let range = title.range(of: "RES-\\d+", options: .regularExpression) {
                    return String(title[range])
                }
            }
            if let rnt = detail.rentalNumber {
                return rnt
            }
        }
        return nil
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
