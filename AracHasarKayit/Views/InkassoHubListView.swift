import SwiftUI

// MARK: - Hub card

struct InkassoOfficeCard: View {
    let selectedMonth: Date
    let operations: [OfficeOperation]
    var canViewFinancials: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var monthOps: [OfficeOperation] {
        // Shared filter — keeps card count aligned with InkassoHubListView.baseItems.
        FleetOperationsFilter.inkasso.filteredOfficeOperations(operations, in: selectedMonth)
    }

    private var count: Int { monthOps.count }
    private var total: Double { monthOps.reduce(0) { $0 + $1.amount } }

    private var sparklineData: [Double] {
        let pairs = monthOps.map { (date: $0.date, amount: $0.amount) }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: FleetOperationRoute.inkasso.hubIconName)
                    .font(.system(size: 28))
                    .foregroundColor(.red)
                Spacer()
                if canViewFinancials {
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
            if canViewFinancials {
                Text(AppCurrency.format(total))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—").font(.system(size: 18, weight: .bold)).foregroundColor(.secondary)
            }
            Text("Inkasso".localized)
                .font(canViewFinancials ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewFinancials ? .secondary : .primary)
                .lineLimit(2)
            Text("\(count) \("entries".localized)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.systemGray4), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - List

struct InkassoHubListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date

    @State private var searchQuery = ""
    @State private var editingOperation: OfficeOperation?

    private var canViewFinancials: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private var baseItems: [OfficeOperation] {
        // Shared filter — keeps list count aligned with InkassoOfficeCard.
        FleetOperationsFilter.inkasso.filteredOfficeOperations(viewModel.officeOperations, in: selectedMonth)
    }

    private var filtered: [OfficeOperation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseItems.filter { op in
            TrafficAccidentContract.matchesRESSearch(query: q, resField: op.referenceNumber ?? "", notes: op.notes)
        }
    }

    private var totalReceived: Double { baseItems.reduce(0) { $0 + $1.amount } }
    private var totalExpected: Double { baseItems.reduce(0) { $0 + $1.effectiveExpectedAmount } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("Inkasso".localized)
                        Text("\(baseItems.count)").fontWeight(.bold)
                    }
                    .font(.subheadline.weight(.semibold))
                    if canViewFinancials {
                        HStack {
                            Text("Received".localized)
                            Spacer()
                            Text(AppCurrency.format(totalReceived)).fontWeight(.bold)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES, RES-12345 or notes".localized, text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("\("Inkasso".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No inkasso records this month".localized).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { op in
                        HStack(alignment: .center, spacing: 8) {
                            NavigationLink {
                                OfficeOperationDetailView(operation: op)
                                    .environmentObject(viewModel)
                                    .environmentObject(authManager)
                            } label: {
                                InkassoHubRow(operation: op, contracts: viewModel.trafficAccidentContracts)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button { viewModel.advanceFleetPaymentRecordStatus(op) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: op.effectiveFleetPaymentStatus.statusIconName)
                                        .font(.caption.weight(.semibold))
                                    Text(op.effectiveFleetPaymentStatus.localizedTitle)
                                        .font(.caption2.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.65)
                                }
                                .frame(width: 72)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.18))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { editingOperation = op } label: {
                                Label("Edit".localized, systemImage: "pencil")
                            }
                            .tint(.blue)
                            Button(role: .destructive) { viewModel.officeOperationSil(op) } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inkasso".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
            }
        }
        .sheet(item: $editingOperation) { operation in
            NavigationView {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

private struct InkassoHubRow: View {
    let operation: OfficeOperation
    let contracts: [TrafficAccidentContract]

    private var linked: Bool {
        if operation.linkedTrafficContractDocumentId != nil { return true }
        let oDoc = operation.documentId ?? operation.id.uuidString
        return contracts.contains { $0.linkedPaymentOfficeOperationDocumentId == oDoc }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(AppCurrency.format(operation.amount)).font(.headline.weight(.bold))
                    Spacer()
                    if linked {
                        Text("Linked".localized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                let res = TrafficAccidentContract.canonicalRES(from: operation.referenceNumber ?? "")
                if !res.isEmpty { Text(res).font(.subheadline.weight(.semibold)) }
                Label(operation.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
