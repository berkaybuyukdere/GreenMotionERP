import SwiftUI

struct AnalyticsDashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    
    @State private var visibleTypes: Set<OperationType> = Set(OperationType.allCases)
    @State private var selectedReturn: IadeIslemi?
    @State private var selectedExit: ExitIslemi?
    @State private var selectedDamage: DailyDamageItem?
    @State private var selectedOfficeOperation: OfficeOperation?
    @State private var isExportingEmails = false
    @State private var selectedDate: Date = Date()
    
    private enum OperationType: String, CaseIterable, Hashable {
        case `return` = "Return"
        case exit = "Check Out"
        case damage = "Damage"
        case office = "Office Ops"
        
        var localizedTitle: String { rawValue.localized }
        
        var color: Color {
            switch self {
            case .return: return .purple
            case .exit: return .blue
            case .damage: return .orange
            case .office: return .green
            }
        }
    }
    
    private struct DailyDamageItem: Identifiable, Hashable {
        let hasar: HasarKaydi
        let arac: Arac
        var id: UUID { hasar.id }
    }
    
    private struct DailyOperationRow: Identifiable {
        let id: String
        let type: OperationType
        let plate: String
        let info1: String
        let info2: String
        let statusText: String
        let statusColor: Color
        let mailText: String
        let mailColor: Color
        let photoCount: Int
        let timestamp: Date
        
        let returnItem: IadeIslemi?
        let exitItem: ExitIslemi?
        let damageItem: DailyDamageItem?
        let officeItem: OfficeOperation?
    }
    
    private struct TableColumn {
        let title: String
        let width: CGFloat
        let alignment: Alignment
    }
    
    private let columns: [TableColumn] = [
        .init(title: "Type".localized, width: 82, alignment: .leading),
        .init(title: "Plate".localized, width: 92, alignment: .leading),
        .init(title: "Info 1".localized, width: 140, alignment: .leading),
        .init(title: "Info 2".localized, width: 130, alignment: .leading),
        .init(title: "Status".localized, width: 96, alignment: .leading),
        .init(title: "Mail".localized, width: 90, alignment: .leading),
        .init(title: "Time".localized, width: 84, alignment: .trailing),
        .init(title: "Photos".localized, width: 58, alignment: .trailing)
    ]
    
    private var dayReturns: [IadeIslemi] {
        viewModel.iadeIslemleri
            .filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
    }
    
    private var dayExits: [ExitIslemi] {
        viewModel.exitIslemleri
            .filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
    }
    
    private var dayDamages: [DailyDamageItem] {
        viewModel.araclar
            .flatMap { arac in
                arac.hasarKayitlari
                    .filter { Calendar.current.isDate($0.tarih, inSameDayAs: selectedDate) }
                    .map { DailyDamageItem(hasar: $0, arac: arac) }
            }
    }
    
    private var dayOfficeOps: [OfficeOperation] {
        viewModel.officeOperations
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    private var mergedRows: [DailyOperationRow] {
        var rows: [DailyOperationRow] = []
        
        if visibleTypes.contains(.return) {
            rows.append(contentsOf: dayReturns.map { item in
                let sent = item.returnEmailSentAt != nil ||
                    item.returnEmailLastStatus == "sent" ||
                    viewModel.hasEmailSentRecord(for: item.id.uuidString)
                return DailyOperationRow(
                    id: "return_\(item.id.uuidString)",
                    type: .return,
                    plate: item.aracPlaka,
                    info1: item.customerFullName.isEmpty ? "-" : item.customerFullName,
                    info2: (item.customerEmail ?? "-"),
                    statusText: item.status.rawValue.localized,
                    statusColor: item.status == .completed ? .green : .orange,
                    mailText: sent ? "Sent".localized : "Not Sent".localized,
                    mailColor: sent ? .green : .orange,
                    photoCount: item.fotograflar.count,
                    timestamp: item.createdAt,
                    returnItem: item,
                    exitItem: nil,
                    damageItem: nil,
                    officeItem: nil
                )
            })
        }
        
        if visibleTypes.contains(.exit) {
            rows.append(contentsOf: dayExits.map { item in
                DailyOperationRow(
                    id: "exit_\(item.id.uuidString)",
                    type: .exit,
                    plate: item.aracPlaka,
                    info1: item.resKodu.isEmpty ? "RES-".localized : item.resKodu,
                    info2: item.km.map { "\($0) KM" } ?? "-",
                    statusText: item.status.rawValue.localized,
                    statusColor: item.status == .completed ? .green : .orange,
                    mailText: "-",
                    mailColor: .secondary,
                    photoCount: item.fotograflar.count,
                    timestamp: item.createdAt,
                    returnItem: nil,
                    exitItem: item,
                    damageItem: nil,
                    officeItem: nil
                )
            })
        }
        
        if visibleTypes.contains(.damage) {
            rows.append(contentsOf: dayDamages.map { item in
                DailyOperationRow(
                    id: "damage_\(item.hasar.id.uuidString)",
                    type: .damage,
                    plate: item.arac.plakaFormatli,
                    info1: "\(item.arac.marka) \(item.arac.model)",
                    info2: item.hasar.resKodu,
                    statusText: item.hasar.status.rawValue.localized,
                    statusColor: item.hasar.status == .completed ? .green : .orange,
                    mailText: "-",
                    mailColor: .secondary,
                    photoCount: item.hasar.fotograflar.count,
                    timestamp: item.hasar.tarih,
                    returnItem: nil,
                    exitItem: nil,
                    damageItem: item,
                    officeItem: nil
                )
            })
        }
        
        if visibleTypes.contains(.office) {
            rows.append(contentsOf: dayOfficeOps.map { item in
                DailyOperationRow(
                    id: "office_\(item.id.uuidString)",
                    type: .office,
                    plate: item.vehiclePlate ?? "-",
                    info1: item.type.rawValue.localized,
                    info2: item.referenceNumber ?? item.notes,
                    statusText: item.isCompleted ? "Done".localized : "Pending".localized,
                    statusColor: item.isCompleted ? .green : .orange,
                    mailText: "-",
                    mailColor: .secondary,
                    photoCount: item.photos.count,
                    timestamp: item.date,
                    returnItem: nil,
                    exitItem: nil,
                    damageItem: nil,
                    officeItem: item
                )
            })
        }
        
        return rows.sorted { $0.timestamp > $1.timestamp }
    }
    
    private var tableWidth: CGFloat {
        columns.reduce(0) { $0 + $1.width } + CGFloat(max(0, columns.count - 1) * 6)
    }
    
    private var marketingExportCandidates: [(email: String, sentAt: Date)] {
        let sentReturns = viewModel.iadeIslemleri.filter { item in
            item.returnEmailSentAt != nil ||
            item.returnEmailLastStatus == "sent" ||
            viewModel.hasEmailSentRecord(for: item.id.uuidString)
        }
        
        return sentReturns.compactMap { item -> (email: String, sentAt: Date)? in
            let email = (item.returnEmailRecipient ?? item.customerEmail ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let sentAt = item.returnEmailSentAt ?? viewModel.returnEmailSentFallbackByReturnId[item.id.uuidString]
            guard !email.isEmpty, email.contains("@"), let sentAt else { return nil }
            return (email: email, sentAt: sentAt)
        }
    }
    
    private var marketingExportReadyCount: Int {
        Set(marketingExportCandidates.map(\.email)).count
    }
    
    var body: some View {
        NavigationView {
            List {
                filtersSection
                mergedTableSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Journal".localized)
            .navigationBarTitleDisplayMode(.inline)
            .background(navigationLinks)
        }
    }
    
    private var filtersSection: some View {
        Section {
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    HapticManager.shared.selection()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    HapticManager.shared.selection()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 8) {
                ForEach(OperationType.allCases, id: \.self) { type in
                    filterChip(type)
                }
            }
            
            HStack {
                Label(
                    String(
                        format: "%d sent email(s) ready".localized,
                        marketingExportReadyCount
                    ),
                    systemImage: "tray.and.arrow.down"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    exportSentEmailsToMarketingCampaigns()
                } label: {
                    if isExportingEmails {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Export Emails".localized)
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExportingEmails || marketingExportReadyCount == 0)
            }
            .padding(.top, 4)
        } header: {
            Text("Journal Day".localized)
        } footer: {
            Text("Tap categories to show/hide rows. Return rows open detail with double tap.".localized)
                .font(.caption2)
        }
    }
    
    private func filterChip(_ type: OperationType) -> some View {
        let selected = visibleTypes.contains(type)
        let count = mergedCount(for: type)
        
        return Button {
            if selected { visibleTypes.remove(type) } else { visibleTypes.insert(type) }
            HapticManager.shared.selection()
        } label: {
            VStack(spacing: 3) {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                Text(type.localizedTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? .white : type.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? type.color : type.color.opacity(0.14))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var mergedTableSection: some View {
        Section("Operations".localized) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                    if mergedRows.isEmpty {
                        emptyRow
                    } else {
                        ForEach(mergedRows.indices, id: \.self) { idx in
                            operationRow(mergedRows[idx], index: idx)
                            Divider()
                        }
                    }
                }
                .frame(width: tableWidth, alignment: .leading)
            }
        }
    }
    
    private var headerRow: some View {
        HStack(spacing: 6) {
            ForEach(columns.indices, id: \.self) { idx in
                Text(columns[idx].title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: columns[idx].width, alignment: columns[idx].alignment)
            }
        }
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12))
    }
    
    private var emptyRow: some View {
        HStack {
            Text("No records for today".localized)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(width: tableWidth, alignment: .leading)
        .padding(.vertical, 10)
    }
    
    private func operationRow(_ row: DailyOperationRow, index: Int) -> some View {
        HStack(spacing: 6) {
            rowCell(row.type.localizedTitle, width: columns[0].width, alignment: columns[0].alignment, weight: .semibold, color: row.type.color)
            rowCell(row.plate, width: columns[1].width, alignment: columns[1].alignment, weight: .semibold)
            rowCell(row.info1.isEmpty ? "-" : row.info1, width: columns[2].width, alignment: columns[2].alignment)
            rowCell(row.info2.isEmpty ? "-" : row.info2, width: columns[3].width, alignment: columns[3].alignment)
            rowCell(row.statusText, width: columns[4].width, alignment: columns[4].alignment, weight: .semibold, color: row.statusColor)
            rowCell(row.mailText, width: columns[5].width, alignment: columns[5].alignment, weight: .semibold, color: row.mailColor)
            rowCell(row.timestamp.formatted(date: .omitted, time: .shortened), width: columns[6].width, alignment: columns[6].alignment)
            rowCell("\(row.photoCount)", width: columns[7].width, alignment: columns[7].alignment)
        }
        .padding(.vertical, 6)
        .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let returnItem = row.returnItem else { return }
            selectedReturn = returnItem
        }
        .onTapGesture {
            if let exit = row.exitItem {
                selectedExit = exit
            } else if let damage = row.damageItem {
                selectedDamage = damage
            } else if let office = row.officeItem {
                selectedOfficeOperation = office
            }
        }
    }
    
    private func rowCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        weight: Font.Weight = .regular,
        color: Color = .primary
    ) -> some View {
        Text(text)
            .font(.caption.weight(weight))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
    }
    
    @ViewBuilder
    private var navigationLinks: some View {
        VStack {
            NavigationLink(
                destination: Group {
                    if let selectedReturn {
                        IadeDetayView(iade: selectedReturn)
                    } else { EmptyView() }
                },
                isActive: Binding(
                    get: { selectedReturn != nil },
                    set: { isActive in if !isActive { selectedReturn = nil } }
                )
            ) { EmptyView() }
            .hidden()
            
            NavigationLink(
                destination: Group {
                    if let selectedExit {
                        ExitDetayView(exit: selectedExit)
                    } else { EmptyView() }
                },
                isActive: Binding(
                    get: { selectedExit != nil },
                    set: { isActive in if !isActive { selectedExit = nil } }
                )
            ) { EmptyView() }
            .hidden()
            
            NavigationLink(
                destination: Group {
                    if let selectedDamage {
                        HasarDetayView(
                            hasar: selectedDamage.hasar,
                            aracId: selectedDamage.arac.id,
                            aracPlaka: selectedDamage.arac.plakaFormatli
                        )
                    } else { EmptyView() }
                },
                isActive: Binding(
                    get: { selectedDamage != nil },
                    set: { isActive in if !isActive { selectedDamage = nil } }
                )
            ) { EmptyView() }
            .hidden()
            
            NavigationLink(
                destination: Group {
                    if let selectedOfficeOperation {
                        OfficeOperationDetailView(operation: selectedOfficeOperation)
                            .environmentObject(viewModel)
                    } else { EmptyView() }
                },
                isActive: Binding(
                    get: { selectedOfficeOperation != nil },
                    set: { isActive in if !isActive { selectedOfficeOperation = nil } }
                )
            ) { EmptyView() }
            .hidden()
        }
    }
    
    private func mergedCount(for type: OperationType) -> Int {
        switch type {
        case .return: return dayReturns.count
        case .exit: return dayExits.count
        case .damage: return dayDamages.count
        case .office: return dayOfficeOps.count
        }
    }
    
    private func exportSentEmailsToMarketingCampaigns() {
        let candidates = marketingExportCandidates
        guard !candidates.isEmpty else {
            ToastManager.shared.show("No sent emails available to export".localized, type: .info)
            return
        }
        
        isExportingEmails = true
        
        FirebaseService.shared.exportReturnEmailsIncremental(
            campaignBaseName: "Return Email Export".localized,
            source: "daily_view_returns",
            candidates: candidates
        ) { result in
            DispatchQueue.main.async {
                isExportingEmails = false
                switch result {
                case .success(let exportResult):
                    if exportResult.exportedCount == 0 {
                        HapticManager.shared.selection()
                        ToastManager.shared.show(
                            "No new emails since the last export".localized,
                            type: .info
                        )
                    } else {
                        HapticManager.shared.success()
                        ToastManager.shared.show(
                            String(
                                format: "%d new emails exported to Marketing Campaigns".localized,
                                exportResult.exportedCount
                            ),
                            type: .success
                        )
                    }
                case .failure(let error):
                    HapticManager.shared.error()
                    ErrorManager.shared.showError(error, context: "Marketing Campaign Export")
                }
            }
        }
    }
}
