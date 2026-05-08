import SwiftUI

/// Payments hub (office type `.banking`): month scope, search, three category filters — aligned with traffic contracts list patterns.
struct PaymentsHubListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date

    @State private var searchQuery = ""
    @State private var categoryTab: FleetPaymentCategory = .debtCollection
    @State private var editingOperation: OfficeOperation?
    @State private var showAddPayment = false

    private var paymentCategoryOrder: [FleetPaymentCategory] {
        [.debtCollection, .bankingTransaction, .officePayment]
    }

    private var canViewFinancials: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var basePayments: [OfficeOperation] {
        let r = dateRange
        return viewModel.officeOperations.filter { $0.type == .banking && $0.date >= r.start && $0.date <= r.end }
            .sorted { $0.date > $1.date }
    }

    private var filtered: [OfficeOperation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let qDigits = TrafficAccidentContract.resDigits(from: q)
        return basePayments.filter { op in
            guard op.effectivePaymentCategory == categoryTab else { return false }
            if q.isEmpty { return true }
            let res = TrafficAccidentContract.canonicalRES(from: op.referenceNumber ?? "")
            if res.localizedCaseInsensitiveContains(q) { return true }
            if !qDigits.isEmpty, res.contains(qDigits) { return true }
            if op.notes.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    private var totalReceivedFiltered: Double { filtered.reduce(0) { $0 + $1.amount } }
    private var totalExpectedFiltered: Double { filtered.reduce(0) { $0 + $1.effectiveExpectedAmount } }

    private func payments(in category: FleetPaymentCategory) -> [OfficeOperation] {
        basePayments.filter { $0.effectivePaymentCategory == category }
    }

    private func expectedTotal(for category: FleetPaymentCategory) -> Double {
        payments(in: category).reduce(0) { $0 + $1.effectiveExpectedAmount }
    }

    private func receivedTotal(for category: FleetPaymentCategory) -> Double {
        payments(in: category).reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(paymentCategoryOrder, id: \.self) { cat in
                            PaymentCategoryStatPill(
                                title: cat.localizedTitle,
                                count: payments(in: cat).count,
                                expectedTotal: expectedTotal(for: cat),
                                receivedTotal: receivedTotal(for: cat),
                                showMoney: canViewFinancials
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if canViewFinancials {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Expected (this tab)".localized)
                                Spacer()
                                Text(AppCurrency.format(totalExpectedFiltered))
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Text("Received (this tab)".localized)
                                Spacer()
                                Text(AppCurrency.format(totalReceivedFiltered))
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Payment category".localized, selection: $categoryTab) {
                    ForEach(paymentCategoryOrder, id: \.self) { cat in
                        Text(cat.localizedTitle).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Payment category".localized)
                .onChange(of: categoryTab) { _, _ in
                    HapticManager.shared.selection()
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES or notes".localized, text: $searchQuery)
                        .textInputAutocapitalization(.never)
                }
            }

            Section("\("Payments".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No payments this month".localized)
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
        .navigationTitle("Payments".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back".localized)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPayment = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add payment".localized)
            }
        }
        .sheet(isPresented: $showAddPayment) {
            NavigationStack {
                AddPaymentOperationSheet(initialCategory: categoryTab)
                    .environmentObject(viewModel)
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

    private var linked: Bool {
        if operation.linkedTrafficContractDocumentId != nil { return true }
        let oDoc = operation.documentId ?? operation.id.uuidString
        return contracts.contains { $0.linkedPaymentOfficeOperationDocumentId == oDoc }
    }

    var body: some View {
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
                Text(operation.effectivePaymentCategory.localizedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

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

private struct PaymentCategoryStatPill: View {
    let title: String
    let count: Int
    let expectedTotal: Double
    let receivedTotal: Double
    var showMoney: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text("\(count)")
                .font(.caption.weight(.bold))
            if showMoney {
                Text("\("Expected".localized) \(AppCurrency.format(expectedTotal))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("\("Received".localized) \(AppCurrency.format(receivedTotal))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(10)
        .background(Color.indigo.opacity(0.12))
        .cornerRadius(12)
    }
}

/// Add a Payments row (`OfficeOperation` type `.banking`) with category + optional RES + photos + save overlay.
struct AddPaymentOperationSheet: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) private var dismiss

    let initialCategory: FleetPaymentCategory

    @State private var selectedCategory: FleetPaymentCategory
    @State private var expectedAmountText = ""
    @State private var receivedAmountText = ""
    @State private var resDigits = ""
    @State private var opDate = Date()
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var showSaveOverlay = false
    @State private var saveOverlaySucceeded = false

    private var paymentCategoryOrder: [FleetPaymentCategory] {
        [.debtCollection, .bankingTransaction, .officePayment]
    }

    init(initialCategory: FleetPaymentCategory) {
        self.initialCategory = initialCategory
        _selectedCategory = State(initialValue: initialCategory)
    }

    private func parseDouble(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    private var receivedValue: Double? { parseDouble(receivedAmountText) }
    private var expectedValue: Double? {
        let t = expectedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return parseDouble(expectedAmountText)
    }

    private var canSave: Bool {
        receivedValue != nil
    }

    var body: some View {
        ZStack {
            Form {
                Section("Payment type".localized) {
                    VStack(spacing: 0) {
                        ForEach(Array(paymentCategoryOrder.enumerated()), id: \.offset) { idx, cat in
                            if idx > 0 {
                                Divider().padding(.horizontal, 10)
                            }
                            categoryRowButton(cat)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .background(Color.purple.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.28), lineWidth: 1)
                    )
                }
                Section("Details".localized) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 22)
                        TextField("Received amount".localized, text: $receivedAmountText)
                            .keyboardType(.decimalPad)
                        Text(AppCurrency.code)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        TextField("Expected amount (optional)".localized, text: $expectedAmountText)
                            .keyboardType(.decimalPad)
                        Text(AppCurrency.code)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "number.square.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 22)
                        Text("RES-")
                            .foregroundStyle(.secondary)
                        TextField("digits optional".localized, text: $resDigits)
                            .keyboardType(.numberPad)
                            .onChange(of: resDigits) { _, newVal in
                                let d = newVal.filter(\.isNumber)
                                if d != newVal { resDigits = d }
                            }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
                            .frame(width: 22)
                        DatePicker("Date".localized, selection: $opDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .padding(.top, 4)
                        TextField("Notes (optional)".localized, text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                Section("Photos".localized) {
                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(selectedImages.indices, id: \.self) { i in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImages[i])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Button {
                                            selectedImages.remove(at: i)
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
                    Text("Photos optional".localized)
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
                    Button("Save".localized) {
                        Task { await saveWithOverlay() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .blur(radius: showSaveOverlay ? 6 : 0)
            .allowsHitTesting(!showSaveOverlay)

            if showSaveOverlay {
                paymentSaveOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle("Add payment".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .interactiveDismissDisabled(isSaving)
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
    }

    private func categoryRowButton(_ cat: FleetPaymentCategory) -> some View {
        let selected = selectedCategory == cat
        return Button {
            selectedCategory = cat
            HapticManager.shared.selection()
        } label: {
            Text(cat.localizedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.purple : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var paymentSaveOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if saveOverlaySucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Payment saved".localized)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Saving...".localized)
                        .font(.headline)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @MainActor
    private func saveWithOverlay() async {
        guard let received = receivedValue else { return }
        isSaving = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveOverlay = true
            saveOverlaySucceeded = false
        }

        var urls: [String] = []
        for img in selectedImages {
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/office_operations/\(UUID().uuidString).jpg"
            if let url = try? await ImageUploadActor.shared.upload(image: img, path: path) {
                urls.append(url)
            }
        }

        let canon = TrafficAccidentContract.canonicalRES(from: resDigits)
        var op = OfficeOperation(
            type: .banking,
            date: opDate,
            amount: received,
            photos: urls,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        op.paymentCategory = selectedCategory
        op.referenceNumber = canon.isEmpty ? nil : canon
        op.expectedAmount = expectedValue
        op.fleetPaymentRecordStatus = .pending

        viewModel.officeOperationEkle(op)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            saveOverlaySucceeded = true
        }
        HapticManager.shared.success()
        try? await Task.sleep(nanoseconds: 750_000_000)
        isSaving = false
        showSaveOverlay = false
        dismiss()
    }
}
