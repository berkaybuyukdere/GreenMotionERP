import SwiftUI
import FirebaseFirestore

private enum CHStripeFinancialTab: String, CaseIterable, Identifiable {
    case mailOrder
    case chargebacks
    case dailyReports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mailOrder: return "Mail order / Payment link".localized
        case .chargebacks: return "ch_stripe.chargebacks_title".localized
        case .dailyReports: return "ch_stripe.reports_title".localized
        }
    }

    var icon: String {
        switch self {
        case .mailOrder: return "envelope.fill"
        case .chargebacks: return "exclamationmark.shield.fill"
        case .dailyReports: return "chart.bar.doc.horizontal.fill"
        }
    }
}

/// Switzerland Stripe — Mail order payment links + chargeback (dispute) tracking.
struct CHStripeFinancialHubView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    let selectedMonth: Date

    @State private var selectedTab: CHStripeFinancialTab = .mailOrder
    @State private var mailOrders: [CHStripeMailOrderRecord] = []
    @State private var disputes: [CHStripeDisputeRecord] = []
    @State private var mailOrdersListener: ListenerRegistration?
    @State private var disputesListener: ListenerRegistration?
    @State private var isSyncingDisputes = false
    @State private var errorMessage: String?

    // Mail order form
    @State private var amountText = ""
    @State private var customerEmail = ""
    @State private var customerName = ""
    @State private var resDigits = ""
    @State private var noteText = ""
    @State private var selectedCategory: CHStripeMailOrderCategory?
    @State private var sendEmail = true
    @State private var isCreatingLink = false
    @State private var createdPaymentUrl: String?
    @State private var showShareSheet = false

    private var canonicalResNo: String {
        TrafficAccidentContract.canonicalRES(from: resDigits)
    }

    private var isMailOrderFormValid: Bool {
        guard selectedCategory != nil else { return false }
        guard Validators.validateResCode(resDigits) else { return false }
        guard !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains(".") else { return false }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return amount >= 0.5
    }

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

    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        let start = calendar.date(from: comps) ?? selectedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: start) ?? start
        return (start, end)
    }

    private var monthMailOrders: [CHStripeMailOrderRecord] {
        filterByMonth(mailOrders)
    }

    private var monthDisputes: [CHStripeDisputeRecord] {
        filterByMonth(disputes)
    }

    private var openDisputes: [CHStripeDisputeRecord] {
        disputes.filter { $0.status.isOpen }
    }

    private var totals: CHStripeFinancialTotals {
        CHStripeFinancialTotals.from(mailOrders: monthMailOrders, disputes: monthDisputes)
    }

    private var sectionBackground: Color {
        palantirMode ? PalantirTheme.surface : Color(.secondarySystemBackground)
    }

    private func palantirSectionBackground(cornerRadius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: palantirMode ? 0 : cornerRadius)
            .fill(sectionBackground)
            .overlay {
                if palantirMode {
                    Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
                }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                tabPicker
                if canViewTotals && selectedTab != .dailyReports {
                    totalsSection
                }
                switch selectedTab {
                case .mailOrder:
                    mailOrderFormSection
                    mailOrderHistorySection
                case .chargebacks:
                    chargebacksSection
                case .dailyReports:
                    CHStripeDailyReportsView(franchiseId: franchiseId)
                        .environmentObject(authManager)
                }
            }
            .padding()
        }
        .navigationTitle("Stripe card payments".localized)
        .navigationBarTitleDisplayMode(.inline)
        .palantirOpsScreen()
        .toolbar {
            if selectedTab == .chargebacks {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await syncDisputes() }
                    } label: {
                        if isSyncingDisputes {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSyncingDisputes)
                }
            }
        }
        .onAppear {
            Task {
                try? await CHStripeFinancialService.loadPublicConfig(franchiseId: franchiseId)
            }
            subscribeListeners()
        }
        .onDisappear {
            mailOrdersListener?.remove()
            disputesListener?.remove()
            mailOrdersListener = nil
            disputesListener = nil
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = createdPaymentUrl, let shareURL = URL(string: url) {
                ShareSheet(activityItems: [shareURL])
            }
        }
        .alert("Error".localized, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Stripe card payments".localized, systemImage: "creditcard.fill")
                    .font(palantirMode ? PalantirTheme.labelFont(12) : .headline)
                    .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : .primary)
                Spacer()
                if StripeCHConfig.isLiveMode {
                    Text("Live mode".localized)
                        .font(palantirMode ? PalantirTheme.labelFont(9) : .caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((palantirMode ? PalantirTheme.success : Color.green).opacity(0.15))
                        .foregroundStyle(palantirMode ? PalantirTheme.success : .green)
                        .clipShape(Capsule())
                }
            }
            Text("ch_stripe.financial_intro".localized)
                .font(palantirMode ? PalantirTheme.bodyFont(12) : .subheadline)
                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : .secondary)
        }
        .padding()
        .background { palantirSectionBackground() }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(CHStripeFinancialTab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_stripe.totals_admin_only".localized)
                .font(palantirMode ? PalantirTheme.labelFont(10) : .caption)
                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : .secondary)
            HStack(spacing: 10) {
                totalTile(
                    title: "ch_stripe.mailorder_status_paid".localized,
                    amount: totals.mailOrderPaid,
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                totalTile(
                    title: "ch_stripe.mailorder_status_pending".localized,
                    amount: totals.mailOrderPending,
                    icon: "clock.fill",
                    color: .orange
                )
                totalTile(
                    title: "ch_stripe.dispute_open".localized,
                    amount: totals.disputeOpenAmount,
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                )
            }
        }
        .padding()
        .background { palantirSectionBackground() }
    }

    private func totalTile(title: String, amount: Double, icon: String, color: Color) -> some View {
        let tileTint: Color = {
            if !palantirMode { return color }
            switch color {
            case .green: return PalantirTheme.success
            case .orange: return PalantirTheme.warning
            case .red: return PalantirTheme.critical
            default: return PalantirTheme.accent
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(tileTint)
            Text(AppCurrency.format(amount))
                .font(palantirMode ? PalantirTheme.heroFont(16) : .subheadline.weight(.bold))
                .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(palantirMode ? PalantirTheme.labelFont(9) : .caption2)
                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : .secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: palantirMode ? 0 : 10)
                .fill(palantirMode ? PalantirTheme.background.opacity(0.55) : color.opacity(colorScheme == .dark ? 0.15 : 0.08))
        }
        .overlay {
            if palantirMode {
                Rectangle().stroke(PalantirTheme.border, lineWidth: 1)
            }
        }
    }

    private var mailOrderFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mail order / Payment link".localized)
                .font(palantirMode ? PalantirTheme.labelFont(12) : .subheadline.weight(.semibold))
                .foregroundStyle(palantirMode ? PalantirTheme.textPrimary : .primary)
            Text("ch_stripe.mailorder_desc".localized)
                .font(palantirMode ? PalantirTheme.bodyFont(11) : .caption)
                .foregroundStyle(palantirMode ? PalantirTheme.textMuted : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("ch_stripe.mailorder_category_label".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(CHStripeMailOrderCategory.allCases) { cat in
                        Button {
                            selectedCategory = cat
                            HapticManager.shared.light()
                        } label: {
                            Label(cat.localizedTitle, systemImage: cat.icon)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selectedCategory == cat ?
                                        Color.accentColor.opacity(0.18) :
                                        Color(.tertiarySystemFill)
                                )
                                .foregroundStyle(selectedCategory == cat ? Color.accentColor : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            selectedCategory == cat ? Color.accentColor : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            resCodeField
            formField("Customer name".localized, text: $customerName)
            formField("Customer email".localized, text: $customerEmail, keyboard: .emailAddress)
            formField("Amount (CHF)".localized, text: $amountText, keyboard: .decimalPad)
            formField("Note".localized, text: $noteText,
                      placeholder: "ch_stripe.description_placeholder".localized)

            Toggle("ch_stripe.send_link_by_email".localized, isOn: $sendEmail)

            if let url = createdPaymentUrl {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment link created".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(url)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack {
                        Button {
                            UIPasteboard.general.string = url
                            HapticManager.shared.success()
                        } label: {
                            Label("Copy".localized, systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share".localized, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                Task { await createMailOrder() }
            } label: {
                HStack {
                    if isCreatingLink {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                    }
                    Text(sendEmail ? "ch_stripe.send_payment_link".localized : "Generate payment link".localized)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isCreatingLink || !isMailOrderFormValid)
        }
        .padding()
        .background { palantirSectionBackground() }
    }

    private var resCodeField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ch_stripe.res_code_label".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("RES-")
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                TextField("12345", text: $resDigits)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: resDigits) { _, newVal in
                        let digits = newVal.filter(\.isNumber)
                        if digits != newVal { resDigits = String(digits.prefix(8)) }
                    }
            }
            if !resDigits.isEmpty && !Validators.validateResCode(resDigits) {
                Text("ch_stripe.res_code_invalid".localized)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var mailOrderHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent payments".localized)
                .font(.subheadline.weight(.semibold))
            if monthMailOrders.isEmpty {
                Text("ch_stripe.no_mailorders_yet".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(monthMailOrders) { order in
                    CHStripeMailOrderRow(order: order)
                }
            }
        }
    }

    private var chargebacksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ch_stripe.chargebacks_title".localized)
                .font(.subheadline.weight(.semibold))
            Text("ch_stripe.chargebacks_desc".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !openDisputes.isEmpty {
                Label(
                    String(format: "ch_stripe.open_disputes_count".localized, openDisputes.count),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }

            if monthDisputes.isEmpty {
                Text("ch_stripe.no_disputes_yet".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                ForEach(monthDisputes) { dispute in
                    CHStripeDisputeRow(dispute: dispute)
                }
            }
        }
    }

    private func formField(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? title : placeholder, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Data

    private func filterByMonth<T>(_ items: [T], date: (T) -> Date?) -> [T] {
        let range = monthRange
        return items.filter { item in
            guard let d = date(item) else { return true }
            return d >= range.start && d <= range.end
        }
    }

    private func filterByMonth(_ orders: [CHStripeMailOrderRecord]) -> [CHStripeMailOrderRecord] {
        filterByMonth(orders) { $0.createdAt }
    }

    private func filterByMonth(_ items: [CHStripeDisputeRecord]) -> [CHStripeDisputeRecord] {
        filterByMonth(items) { $0.createdAt }
    }

    private func subscribeListeners() {
        mailOrdersListener?.remove()
        disputesListener?.remove()
        mailOrdersListener = CHStripeFinancialService.subscribeMailOrders(franchiseId: franchiseId) { records in
            mailOrders = records
        }
        disputesListener = CHStripeFinancialService.subscribeDisputes(franchiseId: franchiseId) { records in
            disputes = records
        }
    }

    private func createMailOrder() async {
        guard let category = selectedCategory else {
            errorMessage = "ch_stripe.mailorder_category_required".localized
            return
        }
        guard Validators.validateResCode(resDigits) else {
            errorMessage = "ch_stripe.res_code_invalid".localized
            return
        }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard amount >= 0.5 else {
            errorMessage = "ch_stripe.invalid_amount".localized
            return
        }
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "ch_stripe.customer_name_required".localized
            return
        }
        guard email.contains("@") else {
            errorMessage = "ch_stripe.customer_email_required".localized
            return
        }
        isCreatingLink = true
        defer { isCreatingLink = false }
        do {
            let response = try await CHStripeFinancialService.createMailOrder(
                franchiseId: franchiseId,
                request: .init(
                    amountChf: amount,
                    category: category,
                    resNo: canonicalResNo,
                    customerEmail: email,
                    customerName: name,
                    note: noteText.trimmingCharacters(in: .whitespacesAndNewlines),
                    sendEmail: sendEmail
                )
            )
            createdPaymentUrl = response.paymentUrl
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    private func syncDisputes() async {
        isSyncingDisputes = true
        defer { isSyncingDisputes = false }
        do {
            _ = try await CHStripeFinancialService.syncDisputes(franchiseId: franchiseId)
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

// MARK: - Rows

struct CHStripeMailOrderRow: View {
    let order: CHStripeMailOrderRecord

    var body: some View {
        HStack(spacing: 8) {
            Text(AppCurrency.format(order.amount))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)

            Text(order.status.localizedTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(order.status == .paid ? .green : .orange)
                .frame(width: 52, alignment: .leading)

            if let category = order.displayCategory {
                Text(category.localizedTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: 64, alignment: .leading)
            }

            CHStripePaymentMethodLabel(brand: "link", last4: nil, methodType: "link")

            VStack(alignment: .leading, spacing: 0) {
                if !order.resNo.isEmpty {
                    Text(order.resNo)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(order.customerName.isEmpty ? order.note : order.customerName)
                    .font(.caption)
                    .lineLimit(1)
                if !order.customerEmail.isEmpty {
                    Text(order.customerEmail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let date = order.createdAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CHStripeDisputeRow: View {
    let dispute: CHStripeDisputeRecord

    private var statusColor: Color {
        dispute.status.isOpen ? .orange : (dispute.status == .won ? .green : .red)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(AppCurrency.format(dispute.amount))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)

            Text(dispute.status.localizedTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)

            CHStripePaymentMethodLabel(
                brand: dispute.cardBrand,
                last4: dispute.cardLast4,
                methodType: "card"
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(dispute.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .lineLimit(1)
                if !dispute.plate.isEmpty {
                    Text(dispute.plate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let date = dispute.createdAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Office hub card

struct CHStripeFinancialOfficeCard: View {
    let selectedMonth: Date
    let mailOrders: [CHStripeMailOrderRecord]
    let disputes: [CHStripeDisputeRecord]
    var canViewTotals: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    private var monthMailOrders: [CHStripeMailOrderRecord] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        let start = calendar.date(from: comps) ?? selectedMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: start) ?? start
        return mailOrders.filter {
            guard let d = $0.createdAt else { return false }
            return d >= start && d <= end
        }
    }

    private var openDisputeCount: Int {
        disputes.filter { $0.status.isOpen }.count
    }

    private var paidTotal: Double {
        monthMailOrders.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        let subtitle: String = {
            let entries = "\(monthMailOrders.count) \("entries".localized)"
            if openDisputeCount > 0 {
                return entries + " · " + String(format: "ch_stripe.open_disputes_count".localized, openDisputeCount)
            }
            return entries
        }()
        if palantirMode {
            PalantirCHHubStatCard(
                icon: "envelope.badge.fill",
                title: "Mail order / Payment link".localized,
                value: canViewTotals ? AppCurrency.format(paidTotal) : "—",
                subtitle: subtitle,
                tint: PalantirTheme.purple
            )
        } else {
            legacyBody
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)
                Spacer()
                if openDisputeCount > 0 {
                    Text("\(openDisputeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Color.clear.frame(height: 30)
            if canViewTotals {
                Text(AppCurrency.format(paidTotal))
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text("Mail order / Payment link".localized)
                .font(canViewTotals ? .caption : .subheadline.weight(.semibold))
                .foregroundStyle(canViewTotals ? .secondary : .primary)
                .lineLimit(2)
            Text("\(monthMailOrders.count) \("entries".localized)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.systemGray4), lineWidth: 1))
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

struct CHStripeDailyClosingOfficeCard: View {
    let selectedMonth: Date
    var canViewTotals: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode

    var body: some View {
        if palantirMode {
            PalantirCHHubStatCard(
                icon: "calendar.badge.clock",
                title: "ch_stripe.daily_closing_title".localized,
                value: "—",
                subtitle: "ch_stripe.daily_closing_subtitle".localized,
                tint: PalantirTheme.success
            )
        } else {
            legacyBody
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 28))
                    .foregroundStyle(.teal)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Color.clear.frame(height: 30)
            Text("ch_stripe.daily_closing_title".localized)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("ch_stripe.daily_closing_subtitle".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.systemGray4), lineWidth: 1))
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}
