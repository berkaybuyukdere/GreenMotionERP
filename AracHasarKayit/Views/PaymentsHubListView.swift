import SwiftUI

// MARK: - Hub card

struct BankingTransactionOfficeCard: View {
    let selectedMonth: Date
    let operations: [OfficeOperation]
    var canViewOperationTotals: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    private var monthOps: [OfficeOperation] {
        // Shared filter — keeps card count aligned with PaymentsHubListView.basePayments.
        FleetOperationsFilter.banking.filteredOfficeOperations(operations, in: selectedMonth)
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
        if palantirMode {
            PalantirCHHubStatCard(
                icon: "building.columns.fill",
                title: "Banking Transaction".localized,
                value: canViewOperationTotals ? AppCurrency.format(total) : "—",
                subtitle: "\(count) \("entries".localized)",
                tint: PalantirTheme.purple,
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
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.indigo)
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
                Text(AppCurrency.format(total))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—").font(.system(size: 18, weight: .bold)).foregroundColor(.secondary)
            }
            Text("Banking Transaction".localized)
                .font(canViewOperationTotals ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewOperationTotals ? .secondary : .primary)
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

/// Banking transaction hub (office type `.banking`): month scope, RES search, banking-transaction rows only.
struct PaymentsHubListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palantirModeEnabled) private var palantirMode

    let selectedMonth: Date

    @State private var searchQuery = ""
    @State private var editingOperation: OfficeOperation?

    private var canViewOperationTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private var basePayments: [OfficeOperation] {
        // Shared filter — keeps list count aligned with BankingTransactionOfficeCard.
        FleetOperationsFilter.banking.filteredOfficeOperations(viewModel.officeOperations, in: selectedMonth)
    }

    private var filtered: [OfficeOperation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return basePayments.filter { op in
            TrafficAccidentContract.matchesRESSearch(
                query: q,
                resField: op.referenceNumber ?? "",
                notes: op.notes
            )
        }
    }

    private var totalReceived: Double { basePayments.reduce(0) { $0 + $1.amount } }
    private var totalExpected: Double { basePayments.reduce(0) { $0 + $1.effectiveExpectedAmount } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text("Banking transactions".localized)
                        Text("\(basePayments.count)")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline.weight(.semibold))

                    if canViewOperationTotals {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Expected".localized)
                                Spacer()
                                Text(AppCurrency.format(totalExpected))
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Text("Received".localized)
                                Spacer()
                                Text(AppCurrency.format(totalReceived))
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                        }
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

            Section("\("Banking Transaction".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No banking transactions this month".localized)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { op in
                        HStack(alignment: .center, spacing: 8) {
                            NavigationLink {
                                OfficeOperationDetailView(operation: op)
                                    .environmentObject(viewModel)
                                    .environmentObject(authManager)
                            } label: {
                                PaymentHubRow(operation: op, contracts: viewModel.trafficAccidentContracts)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                viewModel.advanceFleetPaymentRecordStatus(op)
                            } label: {
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
                                .background(Color.purple.opacity(0.2))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Tap to advance status".localized)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingOperation = op
                            } label: {
                                Label("Edit".localized, systemImage: "pencil")
                            }
                            .tint(.blue)
                            Button(role: .destructive) {
                                viewModel.officeOperationSil(op)
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Banking Transaction".localized)
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

private struct PaymentHubRow: View {
    let operation: OfficeOperation
    let contracts: [TrafficAccidentContract]
    @Environment(\.palantirModeEnabled) private var palantirMode

    private var linked: Bool {
        if operation.linkedTrafficContractDocumentId != nil { return true }
        let oDoc = operation.documentId ?? operation.id.uuidString
        return contracts.contains { $0.linkedPaymentOfficeOperationDocumentId == oDoc }
    }

    var body: some View {
        if palantirMode {
            palantirRowBody
        } else {
            legacyRowBody
        }
    }

    private var palantirRowBody: some View {
        HStack(spacing: 12) {
            PalantirOpsIconTile(systemName: "building.columns.fill", tint: PalantirTheme.purple, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(AppCurrency.format(operation.amount))
                        .font(PalantirTheme.dataFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    if linked {
                        Text("Linked".localized)
                            .font(PalantirTheme.labelFont(9))
                            .foregroundStyle(PalantirTheme.success)
                    }
                }
                let res = TrafficAccidentContract.canonicalRES(from: operation.referenceNumber ?? "")
                if !res.isEmpty {
                    Text(res)
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                if abs(operation.effectiveExpectedAmount - operation.amount) > 0.02 {
                    Text("\("Expected".localized) \(AppCurrency.format(operation.effectiveExpectedAmount))")
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Text(operation.date.formatted(date: .abbreviated, time: .shortened))
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .palantirOpsListRowSurface()
    }

    private var legacyRowBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(AppCurrency.format(operation.amount))
                        .font(.headline.weight(.bold))
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
                if abs(operation.effectiveExpectedAmount - operation.amount) > 0.02 {
                    HStack(spacing: 4) {
                        Text("Expected".localized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(AppCurrency.format(operation.effectiveExpectedAmount))
                            .font(.caption2.weight(.semibold))
                    }
                }

                let res = TrafficAccidentContract.canonicalRES(from: operation.referenceNumber ?? "")
                if !res.isEmpty {
                    Text(res)
                        .font(.subheadline.weight(.semibold))
                }

                if let raw = operation.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, !raw.contains("@") {
                    Text("\("Recorded by".localized) \(raw)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let uid = operation.createdBy, !uid.isEmpty {
                    Text("\("Recorded by".localized) \(String(uid.prefix(8)))…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Label(operation.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


