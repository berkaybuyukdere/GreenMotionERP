import SwiftUI

/// Journal: fleet availability split by the same open-rental rule as vehicle detail
/// (checkout handover after last completed return → on rental).
struct JournalFleetStatusView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var selectedArac: Arac?
    @State private var isAvailableExpanded = true
    @State private var isParkedExpanded = true
    @State private var isRentalExpanded = true
    
    @State private var cachedAvailable: [FleetRow] = []
    @State private var cachedParked: [FleetRow] = []
    @State private var cachedRental: [FleetRow] = []
    
    private struct TableColumn {
        let title: String
        let width: CGFloat
        let alignment: Alignment
    }
    
    private struct FleetRow: Identifiable {
        let id: UUID
        let arac: Arac
        let resText: String
        let checkoutText: String
        let returnText: String
    }
    
    private let columns: [TableColumn] = [
        .init(title: "Category".localized, width: 56, alignment: .leading),
        .init(title: "Plate".localized, width: 92, alignment: .leading),
        .init(title: "RES".localized, width: 100, alignment: .leading),
        .init(title: "Check-out".localized, width: 118, alignment: .leading),
        .init(title: "Last return".localized, width: 118, alignment: .leading)
    ]
    
    private var tableWidth: CGFloat {
        columns.reduce(0) { $0 + $1.width } + CGFloat(max(0, columns.count - 1) * 6)
    }
    
    private var rentalRows: [FleetRow] {
        cachedRental
            .sorted { lhs, rhs in
                let c = lhs.arac.kategori.localizedCaseInsensitiveCompare(rhs.arac.kategori)
                if c != .orderedSame { return c == .orderedAscending }
                return lhs.arac.plakaFormatli.localizedCaseInsensitiveCompare(rhs.arac.plakaFormatli) == .orderedAscending
            }
    }
    
    private var availableRows: [FleetRow] {
        cachedAvailable
            .sorted { lhs, rhs in
                let c = lhs.arac.kategori.localizedCaseInsensitiveCompare(rhs.arac.kategori)
                if c != .orderedSame { return c == .orderedAscending }
                return lhs.arac.plakaFormatli.localizedCaseInsensitiveCompare(rhs.arac.plakaFormatli) == .orderedAscending
            }
    }
    
    private var parkedRows: [FleetRow] {
        cachedParked
            .sorted { lhs, rhs in
                let c = lhs.arac.kategori.localizedCaseInsensitiveCompare(rhs.arac.kategori)
                if c != .orderedSame { return c == .orderedAscending }
                return lhs.arac.plakaFormatli.localizedCaseInsensitiveCompare(rhs.arac.plakaFormatli) == .orderedAscending
            }
    }
    
    var body: some View {
        List {
            fleetSection(
                title: "Available".localized,
                rows: availableRows,
                emptyMessage: "No available vehicles".localized,
                isExpanded: $isAvailableExpanded,
                style: .normal
            )
            fleetSection(
                title: "Parked".localized,
                rows: parkedRows,
                emptyMessage: "No parked vehicles".localized,
                isExpanded: $isParkedExpanded,
                style: .parked
            )
            fleetSection(
                title: "On rental".localized,
                rows: rentalRows,
                emptyMessage: "No vehicles on rental".localized,
                isExpanded: $isRentalExpanded,
                style: .normal
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fleet status".localized)
        .navigationBarTitleDisplayMode(.inline)
        .background(navigationLinkLayer)
        .transaction { $0.animation = nil }
        .onAppear(perform: rebuildBuckets)
        .onChange(of: viewModel.araclar) { _ in rebuildBuckets() }
        .onChange(of: viewModel.iadeIslemleri.count) { _ in rebuildBuckets() }
        .onChange(of: viewModel.exitIslemleri.count) { _ in rebuildBuckets() }
    }
    
    private enum SectionStyle {
        case normal
        case parked
    }
    
    private func fleetSection(
        title: String,
        rows: [FleetRow],
        emptyMessage: String,
        isExpanded: Binding<Bool>,
        style: SectionStyle
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: isExpanded) {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        headerRow(style: style)
                        if rows.isEmpty {
                            HStack {
                                Text(emptyMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(width: tableWidth, alignment: .leading)
                            .padding(.vertical, 10)
                        } else {
                            ForEach(rows.indices, id: \.self) { idx in
                                let row = rows[idx]
                                if style == .parked {
                                    parkedDataRow(row, stripe: idx % 2 == 1)
                                } else {
                                    fleetDataRow(row, stripe: idx % 2 == 1)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(width: tableWidth, alignment: .leading)
                }
            } label: {
                Text(title)
            }
        } footer: {
            Text("Double tap a row to open the vehicle.".localized)
                .font(.caption2)
        }
    }
    
    private func headerRow(style: SectionStyle) -> some View {
        HStack(spacing: 6) {
            ForEach(columns.indices, id: \.self) { idx in
                Text(columns[idx].title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: columns[idx].width, alignment: columns[idx].alignment)
            }
        }
        .padding(.vertical, 7)
        .background(
            style == .parked
                ? Color.purple.opacity(0.18)
                : Color.secondary.opacity(0.12)
        )
    }
    
    private func fleetDataRow(_ row: FleetRow, stripe: Bool) -> some View {
        HStack(spacing: 6) {
            cell(row.arac.kategori.isEmpty ? "—" : row.arac.kategori, columns[0])
            cell(row.arac.plakaFormatli, columns[1], weight: .semibold)
            cell(row.resText, columns[2])
            cell(row.checkoutText, columns[3])
            cell(row.returnText, columns[4])
        }
        .padding(.vertical, 6)
        .background(stripe ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedArac = row.arac
        }
    }
    
    private func parkedDataRow(_ row: FleetRow, stripe: Bool) -> some View {
        fleetDataRow(row, stripe: stripe)
            .background(
                (stripe ? Color.purple.opacity(0.24) : Color.purple.opacity(0.12))
            )
    }
    
    private func cell(_ text: String, _ col: TableColumn, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.caption.weight(weight))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: col.width, alignment: col.alignment)
    }
    
    @ViewBuilder
    private var navigationLinkLayer: some View {
        NavigationLink(
            destination: Group {
                if let selectedArac {
                    AracDetayView(arac: selectedArac)
                } else {
                    EmptyView()
                }
            },
            isActive: Binding(
                get: { selectedArac != nil },
                set: { active in if !active { selectedArac = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }
    
    // MARK: - Same recency rules as `AracDetayView`
    
    private enum FleetBucket {
        case available
        case parked
        case rental
    }
    
    private func rebuildBuckets() {
        var available: [FleetRow] = []
        var parked: [FleetRow] = []
        var rental: [FleetRow] = []
        
        for arac in viewModel.araclar {
            if let row = row(for: arac, target: .available) {
                available.append(row)
            }
            if let row = row(for: arac, target: .parked) {
                parked.append(row)
            }
            if let row = row(for: arac, target: .rental) {
                rental.append(row)
            }
        }
        
        cachedAvailable = available
        cachedParked = parked
        cachedRental = rental
    }
    
    private func row(for arac: Arac, target: FleetBucket) -> FleetRow? {
        let iadeler = viewModel.iadeIslemleri
            .filter { $0.aracId == arac.id && $0.status == .completed }
            .sorted { $0.iadeTarihi > $1.iadeTarihi }
        
        let exits = viewModel.exitIslemleri
            .filter { $0.aracId == arac.id }
            .sorted { $0.createdAt > $1.createdAt }
        
        let lastReturnRecency: Date? = iadeler
            .map { max($0.createdAt, $0.iadeTarihi) }
            .max()
        
        let outbound = exits.filter { $0.status == .completed || $0.status == .parked }
        
        let openOutbound: [ExitIslemi] = {
            guard let cutoff = lastReturnRecency else { return outbound }
            return outbound.filter { checkoutRecency($0) > cutoff }
        }()
        
        let latestOpen: ExitIslemi? = openOutbound.max { a, b in
            let ra = checkoutRecency(a)
            let rb = checkoutRecency(b)
            if ra != rb { return ra < rb }
            return a.createdAt < b.createdAt
        }
        
        let isOut = latestOpen != nil
        let rawRes = latestOpen?.resKodu.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isParked = isOut && rawRes.isEmpty
        
        switch target {
        case .available:
            guard !isOut else { return nil }
        case .parked:
            guard isParked else { return nil }
        case .rental:
            guard isOut && !isParked else { return nil }
        }
        
        let dash = "—"
        
        if (target == .rental || target == .parked), let open = latestOpen {
            return FleetRow(
                id: arac.id,
                arac: arac,
                resText: formatRes(open.resKodu),
                checkoutText: formatDateTime(checkoutRecency(open)),
                returnText: lastReturnRecency.map(formatDateTime) ?? dash
            )
        }
        
        let latestCheckout: Date? = outbound.map { checkoutRecency($0) }.max()
        return FleetRow(
            id: arac.id,
            arac: arac,
            resText: dash,
            checkoutText: latestCheckout.map(formatDateTime) ?? dash,
            returnText: lastReturnRecency.map(formatDateTime) ?? dash
        )
    }
    
    private func checkoutRecency(_ exit: ExitIslemi) -> Date {
        max(exit.createdAt, exit.exitTarihi)
    }
    
    private func formatRes(_ raw: String) -> String {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return "—" }
        return r.uppercased().hasPrefix("RES-") ? r.uppercased() : "RES-\(r)"
    }
    
    private func formatDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
