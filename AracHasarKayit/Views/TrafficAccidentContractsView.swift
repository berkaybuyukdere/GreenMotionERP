import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - List grouping (primary RES + optional supplement lines)

private struct TrafficContractListGroup: Identifiable {
    let id: String
    let primary: TrafficAccidentContract
    let supplements: [TrafficAccidentContract]
}

// MARK: - Hub card (Office Operations grid)

struct TrafficAccidentContractsOfficeCard: View {
    let selectedMonth: Date
    let contracts: [TrafficAccidentContract]
    var canViewOperationTotals: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var monthContracts: [TrafficAccidentContract] {
        let r = monthRange
        return contracts.filter { $0.contractIssueDate >= r.start && $0.contractIssueDate <= r.end }
    }

    private var count: Int { monthContracts.count }

    private var totalAmount: Double { monthContracts.reduce(0) { $0 + $1.amount } }

    private var paidSum: Double { TrafficAccidentContract.totalPaidCollected(monthContracts) }

    private var sparklineData: [Double] {
        let pairs = monthContracts.map { (date: $0.contractIssueDate, amount: $0.amount) }
        return CHFleetHubCardSparkline.amountBuckets(month: selectedMonth, datedAmounts: pairs)
    }

    private var sparklineColor: Color {
        CHFleetHubCardSparkline.trendColor(for: sparklineData)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }

    var body: some View {
        let sData = sparklineData
        let subtitle: String = {
            if canViewOperationTotals {
                return "\(count) \("entries".localized) · \("Paid".localized) \(AppCurrency.format(paidSum))"
            }
            return "\(count) \("entries".localized)"
        }()
        if palantirMode {
            PalantirCHHubStatCard(
                icon: "car.side.rear.and.collision.and.car.side.front",
                title: "Traffic accident contracts".localized,
                value: canViewOperationTotals ? AppCurrency.format(totalAmount) : "—",
                subtitle: subtitle,
                tint: PalantirTheme.warning,
                sparklineData: sData,
                sparklineColor: sparklineColor
            )
        } else {
            legacyBody(sparklineData: sData)
        }
    }

    @ViewBuilder
    private func legacyBody(sparklineData sData: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "car.side.rear.and.collision.and.car.side.front")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                Spacer()
                if canViewOperationTotals {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
            }

            if sData.count > 1 {
                SparklineChart(data: sData, color: sparklineColor)
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30)
            }

            if canViewOperationTotals {
                Text(AppCurrency.format(totalAmount))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Text("Traffic accident contracts".localized)
                .font(canViewOperationTotals ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewOperationTotals ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if canViewOperationTotals {
                (Text("\(count) \("entries".localized) · \("Paid".localized) ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                + Text(AppCurrency.format(paidSum))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("\(count) \("entries".localized)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - List + edit

struct TrafficAccidentContractsListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palantirModeEnabled) private var palantirMode

    let selectedMonth: Date

    private var canViewOperationTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
    }

    @State private var listMonth: Date
    @State private var showMonthPicker = false
    @State private var searchQuery = ""
    @State private var paidFilter: PaidFilter = .all
    @State private var editing: TrafficAccidentContract?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var contractPhotoGallerySession: PhotoGalleryFullScreenSession?
    @State private var contractPendingDelete: TrafficAccidentContract?
    @State private var supplementSheetParent: TrafficAccidentContract?

    init(selectedMonth: Date) {
        self.selectedMonth = selectedMonth
        _listMonth = State(initialValue: selectedMonth)
    }

    private enum PaidFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case paid = "Paid"
        var title: String { rawValue.localized }
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: listMonth)
    }

    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: listMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var baseFiltered: [TrafficAccidentContract] {
        let range = dateRange
        return viewModel.trafficAccidentContracts.filter { c in
            c.contractIssueDate >= range.start && c.contractIssueDate <= range.end
        }.sorted { $0.contractIssueDate > $1.contractIssueDate }
    }

    private var filtered: [TrafficAccidentContract] {
        baseFiltered.filter { c in
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = TrafficAccidentContract.matchesRESSearch(query: q, resField: c.resCode)
            let matchesPaid: Bool = {
                switch paidFilter {
                case .all: return true
                case .pending: return !c.isFullyPaid
                case .paid: return c.isFullyPaid
                }
            }()
            return matchesSearch && matchesPaid
        }
    }

    private var pendingCount: Int { baseFiltered.filter { !$0.isFullyPaid }.count }
    private var paidCount: Int { baseFiltered.filter(\.isFullyPaid).count }
    private var unpaidSum: Double { TrafficAccidentContract.totalOutstanding(baseFiltered) }
    private var paidSum: Double { TrafficAccidentContract.totalPaidCollected(baseFiltered) }

    private var contractGroupsForList: [TrafficContractListGroup] {
        buildContractGroups(from: filtered)
    }

    private func buildContractGroups(from rows: [TrafficAccidentContract]) -> [TrafficContractListGroup] {
        let supplements = rows.filter(\.isSupplementLine)
        let primaries = rows.filter { !$0.isSupplementLine }
        let supByParent = Dictionary(grouping: supplements) { $0.supplementOfDocumentId ?? "" }
        var groups: [TrafficContractListGroup] = primaries.map { p in
            let pid = p.documentId ?? ""
            let kids = (supByParent[pid] ?? []).sorted { $0.contractIssueDate > $1.contractIssueDate }
            let gid = pid.isEmpty ? p.id.uuidString : pid
            return TrafficContractListGroup(id: gid, primary: p, supplements: kids)
        }
        let primaryDocIds = Set(primaries.map { $0.documentId ?? $0.id.uuidString })
        let orphanSupplements = supplements.filter { sup in
            guard let pid = sup.supplementOfDocumentId else { return false }
            return !primaryDocIds.contains(pid)
        }
        for o in orphanSupplements.sorted(by: { $0.contractIssueDate > $1.contractIssueDate }) {
            let gid = o.documentId ?? o.id.uuidString
            groups.append(TrafficContractListGroup(id: gid, primary: o, supplements: []))
        }
        return groups
    }

    var body: some View {
        List {
            analyticsSection

            Section {
                Picker("Payment filter".localized, selection: $paidFilter) {
                    ForEach(PaidFilter.allCases, id: \.self) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES or RES-12345".localized, text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("\("Contracts".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No contracts this month".localized)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contractGroupsForList) { group in
                        TrafficAccidentContractRow(
                            contract: group.primary,
                            officePayments: viewModel.officeOperations,
                            isSubordinate: false,
                            onTogglePaid: { togglePaid(group.primary) },
                            onOpenEditor: { editing = group.primary },
                            onAddSupplement: {
                                supplementSheetParent = group.primary
                            },
                            onPreviewPhotos: {
                                guard !group.primary.photos.isEmpty else { return }
                                contractPhotoGallerySession = PhotoGalleryFullScreenSession(urlStrings: group.primary.photos, startIndex: 0)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                contractPendingDelete = group.primary
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                        }
                        ForEach(group.supplements) { contract in
                            TrafficAccidentContractRow(
                                contract: contract,
                                officePayments: viewModel.officeOperations,
                                isSubordinate: true,
                                onTogglePaid: { togglePaid(contract) },
                                onOpenEditor: { editing = contract },
                                onAddSupplement: nil,
                                onPreviewPhotos: {
                                    guard !contract.photos.isEmpty else { return }
                                    contractPhotoGallerySession = PhotoGalleryFullScreenSession(urlStrings: contract.photos, startIndex: 0)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    contractPendingDelete = contract
                                } label: {
                                    Label("Delete".localized, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Traffic accident contracts".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .fleetListPalantirChrome(enabled: palantirMode)
        .palantirOpsScreen()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    if palantirMode {
                        Image(systemName: "chevron.left")
                            .font(PalantirTheme.labelFont(12))
                            .foregroundStyle(PalantirTheme.accent)
                    } else {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                }
                .accessibilityLabel("Back".localized)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Generate PDF Report".localized, systemImage: "doc.fill")
                    }
                    .disabled(filtered.isEmpty || isExporting)

                    Button {
                        exportCSV()
                    } label: {
                        Label("Generate Excel Report".localized, systemImage: "tablecells.fill")
                    }
                    .disabled(filtered.isEmpty || isExporting)
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

            }
        }
        .onChange(of: selectedMonth) { _, newMonth in
            listMonth = newMonth
        }
        .sheet(isPresented: $showMonthPicker) {
            trafficMonthPickerSheet
        }
        .sheet(item: $editing) { c in
            NavigationStack {
                TrafficAccidentContractEditorView(mode: .edit(c)) {
                    supplementSheetParent = c
                }
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(item: $supplementSheetParent) { parent in
            NavigationStack {
                TrafficAccidentContractEditorView(mode: .addSupplement(parent: parent))
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .fullScreenCover(item: $contractPhotoGallerySession) { session in
            Group {
                if let urls = session.urlStrings {
                    NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
                } else if let imgs = session.images {
                    NativePhotoGalleryView(images: imgs, initialIndex: session.startIndex)
                }
            }
        }
        .alert("Delete this contract?".localized, isPresented: Binding(
            get: { contractPendingDelete != nil },
            set: { if !$0 { contractPendingDelete = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { contractPendingDelete = nil }
            Button("Delete".localized, role: .destructive) {
                if let c = contractPendingDelete {
                    viewModel.trafficAccidentContractSil(c)
                    contractPendingDelete = nil
                }
            }
        } message: {
            Text(contractPendingDelete?.displayResCode ?? "")
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var analyticsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showMonthPicker = true
                } label: {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Select Month".localized)

                HStack(spacing: 6) {
                    Text("Total entries".localized)
                    Text("\(baseFiltered.count)")
                        .fontWeight(.bold)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    TrafficContractStatPill(title: "Pending".localized, value: "\(pendingCount)", color: .orange)
                    TrafficContractStatPill(title: "Paid".localized, value: "\(paidCount)", color: .green)
                }

                if canViewOperationTotals {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total unpaid".localized).font(.caption).foregroundStyle(.secondary)
                            Text(AppCurrency.format(unpaidSum)).font(.headline.weight(.bold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total paid".localized).font(.caption).foregroundStyle(.secondary)
                            Text(AppCurrency.format(paidSum)).font(.headline.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var trafficMonthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Select Month".localized,
                    selection: $listMonth,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                Spacer()
            }
            .padding()
            .navigationTitle("Select Month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        showMonthPicker = false
                    }
                }
            }
        }
    }

    private func togglePaid(_ contract: TrafficAccidentContract) {
        var u = contract
        if u.isFullyPaid {
            u.paidAmount = nil
        } else {
            u.paidAmount = u.amount
        }
        viewModel.trafficAccidentContractGuncelle(u)
        HapticManager.shared.medium()
    }

    private func exportPDF() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let data = TrafficAccidentContractExporter.pdfData(
                contracts: filtered,
                franchiseName: viewModel.franchiseName,
                monthLabel: monthDisplayText
            )
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fd = DateFormatter()
            fd.locale = Locale(identifier: "en_US_POSIX")
            fd.dateFormat = "yyyy-MM-dd"
            let tag = filtered.map(\.createdAt).max().map { fd.string(from: $0) } ?? "nodate"
            let url = documentsPath.appendingPathComponent("TrafficAccidentContracts_\(tag).pdf")
            do {
                try data.write(to: url)
                shareURL = url
                showShareSheet = true
            } catch {
                ErrorManager.shared.showError(error, context: "PDF Generation")
            }
            isExporting = false
        }
    }

    private func exportCSV() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let raw = viewModel.franchiseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGM = raw.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let brand = (raw.isEmpty || isGM) ? PDFExportBranding.genericCompanyTitle : raw.uppercased()
            var csv = ""
            csv += "\(brand) — TRAFFIC ACCIDENT CONTRACTS\n"
            csv += "\(UserDefaults.standard.selectedCountry.name)\n"
            csv += "Month:,\(monthDisplayText)\n\n"
            csv += "SUMMARY\n"
            csv += "Pending count:,\(pendingCount)\n"
            csv += "Paid count:,\(paidCount)\n"
            if canViewOperationTotals {
                csv += "Total unpaid:,\(AppCurrency.amountWithCode(unpaidSum))\n"
                csv += "Total paid:,\(AppCurrency.amountWithCode(paidSum))\n"
            }
            csv += "\n"
            csv += "DETAIL\n"
            csv += "Contract issue date;Record created;RES;Amount (\(AppCurrency.code));Paid;Status;Photos;Recorded by\n"
            let dfDay = DateFormatter()
            dfDay.dateFormat = "yyyy-MM-dd"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            for c in filtered.sorted(by: { $0.contractIssueDate > $1.contractIssueDate }) {
                let paidStr = c.paidAmount.map { String(format: "%.2f", $0) } ?? ""
                let status = c.isFullyPaid ? "Paid" : "Pending"
                let by = escapeCsv(c.createdByName ?? "")
                csv += "\(dfDay.string(from: c.contractIssueDate));\(df.string(from: c.createdAt));\(escapeCsv(c.displayResCode));\(String(format: "%.2f", c.amount));\(paidStr);\(status);\(c.photos.count);\(by)\n"
            }
            csv += "\n\(PDFExportBranding.csvGeneratedByLine)\n"

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documentsPath.appendingPathComponent("TrafficAccidentContracts_\(Date().timeIntervalSince1970).csv")
            var bomData = Data([0xEF, 0xBB, 0xBF])
            bomData.append(csv.data(using: .utf8) ?? Data())
            do {
                try bomData.write(to: url)
                shareURL = url
                showShareSheet = true
            } catch {
                ErrorManager.shared.showError(error, context: "CSV Generation")
            }
            isExporting = false
        }
    }

    private func escapeCsv(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
    }
}

private struct TrafficContractStatPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }
}

private struct TrafficAccidentContractRow: View {
    let contract: TrafficAccidentContract
    let officePayments: [OfficeOperation]
    var isSubordinate: Bool = false
    let onTogglePaid: () -> Void
    let onOpenEditor: () -> Void
    /// Only primary rows pass this; opens sheet to add another line for the same RES.
    var onAddSupplement: (() -> Void)? = nil
    let onPreviewPhotos: () -> Void

    private var paidSoFar: Double { min(contract.amount, contract.paidAmount ?? 0) }

    private var statusIconName: String {
        if contract.isFullyPaid { return "checkmark.circle.fill" }
        if contract.hasPartialPayment { return "circle.lefthalf.filled" }
        return "circle.fill"
    }

    private var isLinkedToPayment: Bool {
        if contract.linkedPaymentOfficeOperationDocumentId != nil { return true }
        let tac = contract.documentId ?? contract.id.uuidString
        return officePayments.contains { $0.linkedTrafficContractDocumentId == tac }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePaid) {
                Image(systemName: statusIconName)
                    .font(.title3)
                    .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 6) {
                        if isSubordinate {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(contract.displayResCode)
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    if let add = onAddSupplement {
                        Button(action: add) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add another contract for this RES".localized)
                    }
                    Text(AppCurrency.format(contract.amount))
                        .font(.subheadline.weight(.bold))
                    if isLinkedToPayment {
                        Text("Linked".localized)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text("Traffic accident".localized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if paidSoFar > 0.009 {
                    (Text(AppCurrency.format(paidSoFar))
                        .foregroundStyle(.green)
                    + Text(" / ")
                        .foregroundStyle(.secondary)
                    + Text(AppCurrency.format(contract.amount))
                        .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange))
                    .font(.caption.weight(.semibold))
                }
                if let raw = contract.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, !raw.contains("@") {
                    Text("\("Recorded by".localized) \(raw)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let uid = contract.createdBy, !uid.isEmpty {
                    Text("\("Recorded by".localized) \(String(uid.prefix(8)))…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Label(contract.contractIssueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !contract.photos.isEmpty {
                        Button(action: onPreviewPhotos) {
                            Label("\(contract.photos.count)", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View photos".localized)
                    }
                    Text(contract.isFullyPaid ? "Paid".localized : "Pending".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenEditor)
        }
        .padding(.leading, isSubordinate ? 12 : 0)
        .padding(.vertical, 4)
    }
}

// MARK: - Editor

struct TrafficAccidentContractEditorView: View {
    enum Mode: Hashable {
        case create
        case edit(TrafficAccidentContract)
        case addSupplement(parent: TrafficAccidentContract)
    }

    private enum SaveOverlayPhase: Hashable {
        case uploading
        case completed
    }

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    private let onRequestAddSupplementFromEditor: (() -> Void)?

    init(mode: Mode, onRequestAddSupplementFromEditor: (() -> Void)? = nil) {
        self.mode = mode
        self.onRequestAddSupplementFromEditor = onRequestAddSupplementFromEditor
    }

    /// Digits only; stored as `RES-…` on save.
    @State private var resDigitsInput = ""
    @State private var amountText = ""
    /// Optional partial payment (e.g. 400 of 1000); empty = none yet (pending).
    @State private var paidAmountText = ""
    @State private var contractIssueDate = Date()
    @State private var resDuplicateWarning = ""
    /// Required for create / supplement; pre-filled on edit.
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @State private var showSaveOverlay = false
    @State private var saveOverlayPhase: SaveOverlayPhase = .uploading
    @State private var saveUploadProgress: Double = 0

    private var existing: TrafficAccidentContract? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    private var supplementParent: TrafficAccidentContract? {
        if case .addSupplement(let p) = mode { return p }
        return nil
    }

    var body: some View {
        ZStack {
            editorForm
                .blur(radius: showSaveOverlay ? 8 : 0)
                .allowsHitTesting(!showSaveOverlay)

            if showSaveOverlay {
                contractSaveOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var editorForm: some View {
        Form {
            Section("Contract".localized) {
                HStack(spacing: 10) {
                    Image(systemName: "number.square.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    HStack {
                        Text("RES-")
                            .foregroundStyle(.secondary)
                            .font(.body.weight(.medium))
                        if resEntryDisabled {
                            Text(resDigitsInput.isEmpty ? "—" : resDigitsInput)
                                .foregroundStyle(.primary)
                        } else {
                            TextField("digits only".localized, text: $resDigitsInput)
                                .keyboardType(.numberPad)
                                .onChange(of: resDigitsInput) { _, newVal in
                                    let d = newVal.filter(\.isNumber)
                                    if d != newVal { resDigitsInput = d }
                                }
                        }
                    }
                }
                if !resDuplicateWarning.isEmpty {
                    Text(resDuplicateWarning)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                DatePicker("Contract issue date".localized, selection: $contractIssueDate, displayedComponents: [.date])
                HStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    TextField("Amount".localized, text: $amountText)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "creditcard")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    TextField("Paid amount (optional)".localized, text: $paidAmountText)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code).foregroundStyle(.secondary)
                }
                Text("Leave empty until the customer pays; enter a partial amount for orange pending.".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if case .edit(let p) = mode, !p.isSupplementLine, let add = onRequestAddSupplementFromEditor {
                Section {
                    Button(action: add) {
                        Label("Add another contract for this RES".localized, systemImage: "plus.circle.fill")
                    }
                }
            }

            Section("Photos".localized) {
                if !uploadedPhotoURLs.isEmpty || !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(uploadedPhotoURLs.enumerated()), id: \.offset) { index, url in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: uploadedPhotoURLs, startIndex: index)
                                    } label: {
                                        AsyncImageView(urlString: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        uploadedPhotoURLs.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                            }
                            ForEach(selectedImages.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        photoGallerySession = PhotoGalleryFullScreenSession(images: selectedImages, startIndex: index)
                                    } label: {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        selectedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                Text("At least one photo is required.".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    showImagePicker = true
                } label: {
                    Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
                }
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo".localized, systemImage: "camera")
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(modeTitle)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isUploading || showSaveOverlay || !isValid)
            }
        }
        .navigationTitle(modeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .interactiveDismissDisabled(isUploading || showSaveOverlay)
        .onAppear {
            if let e = existing {
                resDigitsInput = TrafficAccidentContract.resDigits(from: e.resCode)
                amountText = String(format: "%.2f", e.amount)
                if let p = e.paidAmount {
                    paidAmountText = String(format: "%.2f", p)
                } else {
                    paidAmountText = ""
                }
                uploadedPhotoURLs = e.photos
                contractIssueDate = e.contractIssueDate
            } else if let p = supplementParent {
                resDigitsInput = TrafficAccidentContract.resDigits(from: p.resCode)
                amountText = ""
                paidAmountText = ""
                uploadedPhotoURLs = []
                contractIssueDate = Date()
            } else {
                contractIssueDate = Date()
            }
            refreshResDuplicateWarning()
        }
        .onChange(of: resDigitsInput) { _, _ in
            refreshResDuplicateWarning()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let img = capturedImage {
                selectedImages.append(img)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
        .fullScreenCover(item: $photoGallerySession) { session in
            Group {
                if let urls = session.urlStrings {
                    NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
                } else if let imgs = session.images {
                    NativePhotoGalleryView(images: imgs, initialIndex: session.startIndex)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: showSaveOverlay) { _, isVisible in
            if isVisible { dismissKeyboard() }
        }
    }

    private var contractSaveOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if saveOverlayPhase == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Contract saved".localized)
                        .font(.headline)
                } else {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 7)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: max(0.05, min(saveUploadProgress, 1)))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                            .animation(.linear(duration: 0.2), value: saveUploadProgress)
                        Text("\(Int((max(0.05, min(saveUploadProgress, 1)) * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    Text("Saving contract...".localized)
                        .font(.headline)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(18)
            .shadow(radius: 12)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resolvedRecorderNameForSave() -> String? {
        if let n = authManager.userProfile?.nameOrUsernameForAudit { return n }
        if let d = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty, !d.contains("@") {
            return d
        }
        return nil
    }

    private var resEntryDisabled: Bool {
        switch mode {
        case .addSupplement: return true
        case .edit(let c): return c.isSupplementLine
        case .create: return false
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "Add contract".localized
        case .edit: return "Edit contract".localized
        case .addSupplement: return "Additional contract".localized
        }
    }

    private var hasBlockingResDuplicate: Bool {
        let canonical = TrafficAccidentContract.canonicalRES(from: resDigitsInput)
        guard !canonical.isEmpty else { return false }
        switch mode {
        case .create:
            return viewModel.hasPrimaryTrafficContract(res: canonical)
        case .edit(let old):
            let ex = old.documentId ?? old.id.uuidString
            return viewModel.hasPrimaryTrafficContract(res: canonical, excludingDocumentId: ex)
        case .addSupplement:
            return false
        }
    }

    private func refreshResDuplicateWarning() {
        let canonical = TrafficAccidentContract.canonicalRES(from: resDigitsInput)
        guard !canonical.isEmpty else {
            resDuplicateWarning = ""
            return
        }
        switch mode {
        case .create:
            if viewModel.hasPrimaryTrafficContract(res: canonical) {
                resDuplicateWarning = "This RES has already been used.".localized
            } else {
                resDuplicateWarning = ""
            }
        case .edit(let old):
            let ex = old.documentId ?? old.id.uuidString
            if viewModel.hasPrimaryTrafficContract(res: canonical, excludingDocumentId: ex) {
                resDuplicateWarning = "This RES has already been used.".localized
            } else {
                resDuplicateWarning = ""
            }
        case .addSupplement:
            resDuplicateWarning = ""
        }
    }

    private var isValid: Bool {
        let digits = TrafficAccidentContract.resDigits(from: resDigitsInput)
        guard !digits.isEmpty, let a = Double(amountText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return false }
        let photoCount = selectedImages.count + uploadedPhotoURLs.count
        guard photoCount > 0, !hasBlockingResDuplicate else { return false }
        return true
    }

    /// Parsed optional paid amount; `nil` if blank or zero (treated as nothing paid yet).
    private static func parsePaidAmount(_ text: String, maxAmount: Double) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0.009 else { return nil }
        return min(max(0, v), max(0, maxAmount))
    }

    private func save() {
        let canonical = TrafficAccidentContract.canonicalRES(from: resDigitsInput)
        guard !canonical.isEmpty, let amt = Double(amountText.replacingOccurrences(of: ",", with: ".")), amt > 0 else { return }
        guard !isUploading else { return }
        if hasBlockingResDuplicate {
            ToastManager.shared.show("This RES has already been used.".localized, type: .warning)
            return
        }

        isUploading = true
        saveOverlayPhase = .uploading
        saveUploadProgress = 0.05
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveOverlay = true
        }

        let existing = uploadedPhotoURLs
        let newImages = selectedImages
        let totalNew = newImages.count

        if totalNew == 0 {
            saveUploadProgress = 1
            saveOverlayPhase = .completed
            HapticManager.shared.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                finalizeContractSave(urls: existing, canonical: canonical, amt: amt)
            }
            return
        }

        var urls = existing
        var idx = 0

        func uploadStep() {
            guard idx < totalNew else {
                saveUploadProgress = 1
                saveOverlayPhase = .completed
                HapticManager.shared.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    finalizeContractSave(urls: urls, canonical: canonical, amt: amt)
                }
                return
            }
            let img = newImages[idx]
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/traffic_accident_contracts/\(UUID().uuidString).jpg"
            Task { @MainActor in
                let url = try? await ImageUploadActor.shared.upload(image: img, path: path)
                if let url {
                    urls.append(url)
                }
                idx += 1
                saveUploadProgress = min(0.98, 0.05 + Double(idx) / Double(totalNew) * 0.93)
                uploadStep()
            }
        }
        uploadStep()
    }

    private func finalizeContractSave(urls: [String], canonical: String, amt: Double) {
        guard !urls.isEmpty else {
            isUploading = false
            showSaveOverlay = false
            ToastManager.shared.show("Add at least one contract photo.".localized, type: .warning)
            return
        }
        let uid = Auth.auth().currentUser?.uid
        let parsedPaid = Self.parsePaidAmount(paidAmountText, maxAmount: amt)
        let recorder = resolvedRecorderNameForSave()
        let processedForSave: Date = {
            if case .edit(let old) = mode { return old.processedDate }
            return Date()
        }()

        Task { @MainActor in
            await TrafficContractSaveActor.shared.enqueueMain {
                switch mode {
                case .create:
                    let idem = TrafficAccidentContract.primaryIdempotencyKey(
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        canonicalRES: canonical
                    )
                    var c = TrafficAccidentContract(
                        photos: urls,
                        amount: amt,
                        resCode: canonical,
                        paidAmount: parsedPaid,
                        createdAt: Date(),
                        contractIssueDate: contractIssueDate,
                        processedDate: processedForSave,
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        createdBy: uid,
                        createdByName: recorder,
                        paymentMethod: nil,
                        supplementOfDocumentId: nil,
                        idempotencyKey: idem
                    )
                    c.documentId = TrafficAccidentContract.stableDocumentId(forIdempotencyKey: idem)
                    viewModel.trafficAccidentContractEkle(c)
                case .edit(let old):
                    var c = old
                    c.resCode = canonical
                    c.amount = amt
                    c.photos = urls
                    c.paidAmount = parsedPaid
                    c.contractIssueDate = contractIssueDate
                    c.processedDate = processedForSave
                    c.paymentMethod = nil
                    viewModel.trafficAccidentContractGuncelle(c)
                case .addSupplement(let parent):
                    guard let pid = parent.documentId, !pid.isEmpty else {
                        isUploading = false
                        showSaveOverlay = false
                        ToastManager.shared.show("Missing parent contract id.".localized, type: .error)
                        return
                    }
                    var c = TrafficAccidentContract(
                        photos: urls,
                        amount: amt,
                        resCode: parent.resCode,
                        paidAmount: parsedPaid,
                        createdAt: Date(),
                        contractIssueDate: contractIssueDate,
                        processedDate: processedForSave,
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        createdBy: uid,
                        createdByName: recorder,
                        paymentMethod: nil,
                        supplementOfDocumentId: pid
                    )
                    c.documentId = c.id.uuidString
                    viewModel.trafficAccidentContractEkle(c)
                }
                isUploading = false
                showSaveOverlay = false
                dismiss()
            }
        }
    }
}

private enum TrafficAccidentContractExporter {
    static func pdfData(contracts: [TrafficAccidentContract], franchiseName: String, monthLabel: String) -> Data {
        let pdfMetadata = [
            kCGPDFContextTitle: "Traffic Accident Contracts",
            kCGPDFContextAuthor: PDFExportBranding.pdfMetadataAuthor,
            kCGPDFContextCreator: PDFExportBranding.pdfMetadataAuthor
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let rawName = franchiseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGM = rawName.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let companyName = (rawName.isEmpty || isGM) ? PDFExportBranding.genericCompanyTitle : rawName.uppercased()

        let pendingN = contracts.filter { !$0.isFullyPaid }.count
        let paidN = contracts.filter(\.isFullyPaid).count
        let unpaidSum = TrafficAccidentContract.totalOutstanding(contracts)
        let paidSum = TrafficAccidentContract.totalPaidCollected(contracts)

        return renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            var y: CGFloat = 60

            companyName.draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 18), .foregroundColor: SwissPDFHelper.black])
            y += 22
            UserDefaults.standard.selectedCountry.name.uppercased().draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaThin(size: 9), .foregroundColor: SwissPDFHelper.mediumGray])
            y += 36
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 26

            "Traffic Accident Contracts".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 22), .foregroundColor: SwissPDFHelper.black])
            y += 30
            "Month:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 10), .foregroundColor: SwissPDFHelper.black])
            monthLabel.draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helvetica(size: 10), .foregroundColor: SwissPDFHelper.black])
            y += 28

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 22

            "SUMMARY".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 22
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            "Pending count:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(pendingN)".draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 18
            "Paid count:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(paidN)".draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 18
            "Total unpaid:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            AppCurrency.amountWithCode(unpaidSum).draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: UIColor.systemOrange])
            y += 18
            "Total paid:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            AppCurrency.amountWithCode(paidSum).draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: UIColor.systemGreen])
            y += 28

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 22

            "DETAIL".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 20

            let headerFont = SwissPDFHelper.helveticaBold(size: 7)
            let rowFont = SwissPDFHelper.helvetica(size: 7)
            let resFont = SwissPDFHelper.helveticaBold(size: 7)
            let amtFont = SwissPDFHelper.helveticaBold(size: 7)
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "dd.MM.yy"
            let dtFmt = DateFormatter()
            dtFmt.dateFormat = "dd.MM.yy HH:mm"

            let sorted = contracts.sorted { $0.contractIssueDate > $1.contractIssueDate }
            let leftM: CGFloat = 48
            let rightM = pageRect.width - 48
            let rowH: CGFloat = 14

            func drawTableHeader(at yy: inout CGFloat) {
                ctx.setFillColor(SwissPDFHelper.mediumGray.withAlphaComponent(0.22).cgColor)
                ctx.fill(CGRect(x: leftM, y: yy - 2, width: rightM - leftM, height: rowH + 2))
                let hIssue = "Contract issue date".localized
                let hRec = "Record created".localized
                let hRes = "RES / reference".localized
                let hAmt = "Amount".localized
                let hPaid = "Paid".localized
                let hSt = "Status".localized
                let hBy = "Recorded by".localized
                hIssue.draw(at: CGPoint(x: leftM, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hRec.draw(at: CGPoint(x: leftM + 72, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hRes.draw(at: CGPoint(x: leftM + 152, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hAmt.draw(at: CGPoint(x: leftM + 232, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hPaid.draw(at: CGPoint(x: leftM + 302, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hSt.draw(at: CGPoint(x: leftM + 352, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                hBy.draw(at: CGPoint(x: leftM + 402, y: yy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                yy += rowH + 4
                SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: leftM, y: yy), to: CGPoint(x: rightM, y: yy), width: 0.5)
                yy += 6
            }

            drawTableHeader(at: &y)

            for (index, c) in sorted.prefix(52).enumerated() {
                if y > 760 {
                    context.beginPage()
                    y = 56
                    drawTableHeader(at: &y)
                }
                if index % 2 == 1 {
                    ctx.setFillColor(SwissPDFHelper.veryLightGray.cgColor)
                    ctx.fill(CGRect(x: leftM, y: y - 2, width: rightM - leftM, height: rowH + 2))
                }
                let paidStr = c.paidAmount.map { String(format: "%.0f", $0) } ?? "—"
                let st = c.isFullyPaid ? "Paid".localized : "Pending".localized
                let by = (c.createdByName ?? "").replacingOccurrences(of: ",", with: ";")
                let byShort = String(by.prefix(18))

                dayFmt.string(from: c.contractIssueDate).draw(at: CGPoint(x: leftM, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.darkGray])
                dtFmt.string(from: c.createdAt).draw(at: CGPoint(x: leftM + 72, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.darkGray])
                c.displayResCode.draw(at: CGPoint(x: leftM + 152, y: y), withAttributes: [.font: resFont, .foregroundColor: SwissPDFHelper.black])
                AppCurrency.amountWithCode(c.amount).draw(at: CGPoint(x: leftM + 232, y: y), withAttributes: [.font: amtFont, .foregroundColor: SwissPDFHelper.black])
                paidStr.draw(at: CGPoint(x: leftM + 302, y: y), withAttributes: [.font: amtFont, .foregroundColor: SwissPDFHelper.black])
                st.draw(at: CGPoint(x: leftM + 352, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.darkGray])
                byShort.draw(at: CGPoint(x: leftM + 402, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.darkGray])
                y += rowH + 4
            }

            let footerY = pageRect.height - 28
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 16), to: CGPoint(x: pageRect.width - 60, y: footerY - 16), width: 0.25)
            let footer = "\(PDFExportBranding.copyrightLine) • \(UserDefaults.standard.selectedCountry.name)"
            footer.draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: SwissPDFHelper.helveticaThin(size: 7), .foregroundColor: SwissPDFHelper.lightGray])
        }
    }
}
