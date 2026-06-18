import SwiftUI

private enum DailyClosingFilter: String, CaseIterable, Identifiable {
    case all
    case successful
    case hold
    case pending
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .successful: return CHStripePaymentBucket.successful.localizedTitle
        case .hold: return CHStripePaymentBucket.hold.localizedTitle
        case .pending: return CHStripePaymentBucket.pending.localizedTitle
        case .cancelled: return CHStripePaymentBucket.cancelled.localizedTitle
        }
    }

    var bucket: CHStripePaymentBucket? {
        switch self {
        case .all: return nil
        case .successful: return .successful
        case .hold: return .hold
        case .pending: return .pending
        case .cancelled: return .cancelled
        }
    }
}

/// Stripe daily closing — terminal, mail-order and online payments for Switzerland.
struct CHStripeDailyClosingView: View {
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var selectedDate = Date()
    @State private var transactions: [CHStripePaymentTransaction] = []
    @State private var summary = CHStripeDailyClosingSummary()
    @State private var dayKey = ""
    @State private var syncedAt: Date?
    @State private var filter: DailyClosingFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTransaction: CHStripePaymentTransaction?

    private var franchiseId: String {
        let sid = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !sid.isEmpty { return sid }
        return authManager.userProfile?.franchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? StripeCHConfig.franchiseId
    }

    private var canViewTotals: Bool {
        authManager.userProfile?.canViewStripePaymentTotals ?? false
    }

    private var filteredTransactions: [CHStripePaymentTransaction] {
        guard let bucket = filter.bucket else { return transactions }
        return transactions.filter { $0.bucket == bucket }
    }

    var body: some View {
        List {
            Section {
                DatePicker(
                    "ch_stripe.daily_date".localized,
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .onChange(of: selectedDate) { _, _ in
                    Task { await load() }
                }

                if let syncedAt {
                    Text(String(format: "ch_stripe.daily_last_sync".localized, syncedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if canViewTotals {
                Section("ch_stripe.daily_totals".localized) {
                    summaryRow(
                        title: CHStripePaymentBucket.successful.localizedTitle,
                        count: summary.successfulCount,
                        amount: summary.successfulAmount,
                        color: .green,
                        bucket: .successful
                    )
                    summaryRow(
                        title: CHStripePaymentBucket.hold.localizedTitle,
                        count: summary.holdCount,
                        amount: summary.holdAmount,
                        color: .blue,
                        bucket: .hold
                    )
                    summaryRow(
                        title: CHStripePaymentBucket.pending.localizedTitle,
                        count: summary.pendingCount,
                        amount: summary.pendingAmount,
                        color: .orange,
                        bucket: .pending
                    )
                    summaryRow(
                        title: CHStripePaymentBucket.cancelled.localizedTitle,
                        count: summary.cancelledCount,
                        amount: summary.cancelledAmount,
                        color: .red,
                        bucket: .cancelled
                    )
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(DailyClosingFilter.allCases) { item in
                            Button {
                                filter = item
                            } label: {
                                Text(item.title)
                                    .font(.caption.weight(filter == item ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(filter == item ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section("ch_stripe.daily_transactions".localized) {
                if isLoading && transactions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if filteredTransactions.isEmpty {
                    Text("ch_stripe.daily_empty".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTransactions) { tx in
                        Button {
                            selectedTransaction = tx
                        } label: {
                            transactionRow(tx)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("ch_stripe.daily_closing_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $selectedTransaction) { tx in
            CHStripeTransactionDetailSheet(
                transaction: tx,
                franchiseId: franchiseId,
                onCompleted: {
                    selectedTransaction = nil
                    Task { await load() }
                }
            )
        }
    }

    @ViewBuilder
    private func summaryRow(
        title: String,
        count: Int,
        amount: Double,
        color: Color,
        bucket: CHStripePaymentBucket
    ) -> some View {
        Button {
            filter = filter == .all ? bucketFilter(for: bucket) : (filter == bucketFilter(for: bucket) ? .all : bucketFilter(for: bucket))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bucket.icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if canViewTotals {
                    Text(AppCurrency.amountWithCode(amount))
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func transactionRow(_ tx: CHStripePaymentTransaction) -> some View {
        HStack(spacing: 8) {
            if canViewTotals {
                Text(AppCurrency.amountWithCode(tx.displayAmount))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(minWidth: 72, alignment: .leading)
            }

            Text(tx.statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(bucketColor(tx.bucket))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)

            CHStripePaymentMethodLabel(
                brand: tx.cardBrand,
                last4: tx.cardLast4,
                methodType: tx.paymentMethod
            )
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                if let category = tx.category {
                    Text(category.localizedTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(tx.description.isEmpty ? (tx.resNo.isEmpty ? tx.reference : tx.resNo) : tx.description)
                    .font(.caption)
                    .lineLimit(1)
                if !tx.customerEmail.isEmpty || !tx.plate.isEmpty {
                    Text(tx.customerEmail.isEmpty ? tx.plate : tx.customerEmail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let at = tx.createdAt {
                Text(at.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    private func bucketFilter(for bucket: CHStripePaymentBucket) -> DailyClosingFilter {
        switch bucket {
        case .successful: return .successful
        case .hold: return .hold
        case .pending: return .pending
        case .cancelled: return .cancelled
        }
    }

    private func bucketColor(_ bucket: CHStripePaymentBucket) -> Color {
        switch bucket {
        case .successful: return .green
        case .hold: return .blue
        case .pending: return .orange
        case .cancelled: return .red
        }
    }

    private func dayKeyString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let key = dayKeyString(for: selectedDate)
            let res = try await CHStripeFinancialService.fetchDailyClosing(
                franchiseId: franchiseId,
                dayKey: key
            )
            dayKey = res.dayKey
            transactions = res.transactions
            summary = res.summary
            syncedAt = res.syncedAt ?? Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Transaction detail + deposit increase

private struct CHStripeTransactionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let transaction: CHStripePaymentTransaction
    let franchiseId: String
    let onCompleted: () -> Void

    @State private var captureAmountText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment details".localized) {
                    LabeledContent("ch_stripe.daily_hold".localized, value: transaction.statusLabel)
                    if canViewAmount {
                        LabeledContent("Amount (CHF)".localized, value: AppCurrency.amountWithCode(transaction.displayAmount))
                    }
                    LabeledContent("Channel", value: transaction.channelTitle)
                    if let category = transaction.category {
                        LabeledContent("ch_stripe.mailorder_category_label".localized, value: category.localizedTitle)
                    }
                    if !transaction.resNo.isEmpty {
                        LabeledContent("ch_stripe.res_code_label".localized, value: transaction.resNo)
                    }
                    if !transaction.customerName.isEmpty {
                        LabeledContent("Customer name".localized, value: transaction.customerName)
                    }
                    if !transaction.customerEmail.isEmpty {
                        LabeledContent("Customer email".localized, value: transaction.customerEmail)
                    }
                    if !transaction.note.isEmpty {
                        LabeledContent("Note".localized, value: transaction.note)
                    }
                }

                if transaction.canIncreaseDeposit {
                    Section {
                        Text("ch_stripe.increase_deposit_desc".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Amount (CHF)".localized, text: $captureAmountText)
                            .keyboardType(.decimalPad)
                        Button {
                            Task { await increaseDeposit() }
                        } label: {
                            HStack {
                                if isProcessing { ProgressView() }
                                Text("ch_stripe.increase_deposit".localized)
                            }
                        }
                        .disabled(isProcessing)
                    } header: {
                        Text("ch_stripe.increase_deposit".localized)
                    }
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Payment details".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .onAppear {
                if captureAmountText.isEmpty {
                    captureAmountText = String(format: "%.2f", transaction.displayAmount)
                        .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var canViewAmount: Bool { true }

    private func increaseDeposit() async {
        let amount = Double(captureAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard amount >= 0.5 else {
            errorMessage = "ch_stripe.invalid_amount".localized
            return
        }
        guard let piId = transaction.paymentIntentId ?? (transaction.id.hasPrefix("pi_") ? transaction.id : nil) else {
            errorMessage = "ch_stripe.deposit_pi_missing".localized
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await CHStripeFinancialService.increaseDepositHold(
                franchiseId: franchiseId,
                paymentIntentId: piId,
                amountChf: amount
            )
            successMessage = String(
                format: "ch_stripe.deposit_capture_success".localized,
                AppCurrency.amountWithCode(result.capturedAmount)
            )
            HapticManager.shared.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onCompleted()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

/// Compact payment method label — brand + masked last4 (Stripe dashboard style).
struct CHStripePaymentMethodLabel: View {
    let brand: String?
    let last4: String?
    let methodType: String

    private var brandTitle: String {
        let raw = (brand ?? methodType).lowercased()
        if raw.contains("visa") { return "VISA" }
        if raw.contains("master") { return "MC" }
        if raw.contains("amex") { return "AMEX" }
        if raw.contains("link") { return "Link" }
        if raw.contains("twint") { return "TWINT" }
        if raw.contains("card_present") || raw.contains("terminal") { return "POS" }
        return "Card"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(brandTitle)
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            if let last4, !last4.isEmpty {
                Text("•••• \(last4)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
