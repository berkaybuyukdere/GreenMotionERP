import SwiftUI
import FirebaseAuth

// MARK: - Hub card

struct FleetOperationsOfficeCard: View {
    let selectedMonth: Date
    let viewModel: AracViewModel
    var canViewFinancials: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var logItems: [FleetOperationLogItem] {
        viewModel.fleetOperationLogItems(for: selectedMonth)
    }

    private var itemCount: Int { logItems.count }

    private var totalAmount: Double { logItems.reduce(0) { $0 + $1.amount } }

    private var sparklineData: [Double] {
        let pairs = logItems.map { (date: $0.sortDate, amount: $0.amount) }
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
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }

            if sData.count > 1 {
                SparklineChart(data: sData, color: sparklineColor)
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30)
            }

            if canViewFinancials {
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

            Text("Operations".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text("\(itemCount) \("entries".localized) · \("Traffic · Inkasso · Banking".localized)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
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

// MARK: - Hub list

struct FleetOperationsHubView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date

    @State private var listMonth: Date
    @State private var showMonthPicker = false
    @State private var searchQuery = ""
    @State private var showIntake = false
    @State private var intakePreselectedRoute: FleetOperationRoute?
    @State private var editingTraffic: TrafficAccidentContract?
    @State private var detailOfficeOperation: OfficeOperation?

    init(selectedMonth: Date, preselectedRoute: FleetOperationRoute? = nil) {
        self.selectedMonth = selectedMonth
        _listMonth = State(initialValue: selectedMonth)
        _intakePreselectedRoute = State(initialValue: preselectedRoute)
    }

    private var logItems: [FleetOperationLogItem] {
        viewModel.fleetOperationLogItems(for: listMonth)
    }

    private var filteredItems: [FleetOperationLogItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return logItems }
        return logItems.filter { item in
            switch item {
            case .traffic(let c):
                return TrafficAccidentContract.matchesRESSearch(query: q, resField: c.resCode)
            case .inkasso(let o), .banking(let o):
                return TrafficAccidentContract.matchesRESSearch(query: q, resField: o.referenceNumber ?? "", notes: o.notes)
            }
        }
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: listMonth)
    }

    var body: some View {
        List {
            Section {
                Button {
                    showMonthPicker = true
                } label: {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Text("All new records are created here. Choose Traffic accident, Inkasso, or Banking transaction to file under the correct area.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES or RES-12345".localized, text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("\("Operations".localized) (\(filteredItems.count))") {
                if filteredItems.isEmpty {
                    Text("No operations this month".localized)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredItems) { item in
                        Button {
                            openDetail(for: item)
                        } label: {
                            FleetOperationLogRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Operations".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back".localized)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    intakePreselectedRoute = nil
                    showIntake = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add operation".localized)
            }
        }
        .onChange(of: selectedMonth) { _, m in listMonth = m }
        .sheet(isPresented: $showMonthPicker) { operationsMonthPickerSheet }
        .sheet(isPresented: $showIntake) {
            NavigationStack {
                FleetOperationIntakeSheet(preselectedRoute: intakePreselectedRoute)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(item: $editingTraffic) { contract in
            NavigationStack {
                TrafficAccidentContractEditorView(mode: .edit(contract))
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(item: $detailOfficeOperation) { op in
            NavigationStack {
                OfficeOperationDetailView(operation: op)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var operationsMonthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Select Month".localized, selection: $listMonth, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Spacer()
            }
            .padding()
            .navigationTitle("Select Month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { showMonthPicker = false }
                }
            }
        }
    }

    private func openDetail(for item: FleetOperationLogItem) {
        HapticManager.shared.light()
        switch item {
        case .traffic(let c):
            editingTraffic = c
        case .inkasso(let o), .banking(let o):
            detailOfficeOperation = o
        }
    }
}

private struct FleetOperationLogRow: View {
    let item: FleetOperationLogItem

    private var routeColor: Color {
        switch item.route {
        case .trafficAccident: return .orange
        case .inkasso: return .red
        case .bankingTransaction: return .indigo
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.route.hubIconName)
                .font(.title3)
                .foregroundStyle(routeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.route.localizedTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(routeColor.opacity(0.15))
                        .foregroundStyle(routeColor)
                        .clipShape(Capsule())
                    Spacer()
                    Text(AppCurrency.format(item.amount))
                        .font(.headline.weight(.bold))
                }
                if item.resDisplay != "—" {
                    Text(item.resDisplay)
                        .font(.subheadline.weight(.semibold))
                }
                if let name = item.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, !name.contains("@") {
                    Text("\("Recorded by".localized) \(name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Label(item.sortDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.photoCount > 0 {
                        Label("\(item.photoCount)", systemImage: "photo")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Intake (create + route)

struct FleetOperationIntakeSheet: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    var preselectedRoute: FleetOperationRoute?

    @State private var selectedRoute: FleetOperationRoute?
    @State private var resDigits = ""
    @State private var amountText = ""
    @State private var paidAmountText = ""
    @State private var expectedAmountText = ""
    @State private var notes = ""
    @State private var contractIssueDate = Date()
    @State private var processedDate = Date()
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var showSaveOverlay = false
    @State private var saveOverlaySucceeded = false
    @State private var resDuplicateWarning = ""

    private var isTraffic: Bool { selectedRoute == .trafficAccident }

    private var parsedAmount: Double? {
        let t = amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    private var canSave: Bool {
        guard selectedRoute != nil, parsedAmount != nil else { return false }
        if isTraffic {
            let digits = TrafficAccidentContract.resDigits(from: resDigits)
            guard !digits.isEmpty, !selectedImages.isEmpty, resDuplicateWarning.isEmpty else { return false }
        }
        return true
    }

    var body: some View {
        ZStack {
            Form {
                Section("Operation type".localized) {
                    FleetOperationRoutePicker(selection: $selectedRoute)
                    if selectedRoute == nil {
                        Text("Select where this record should be filed.".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if selectedRoute != nil {
                    Section("Details".localized) {
                        HStack(spacing: 10) {
                            Image(systemName: "number.square.fill").foregroundStyle(.blue).frame(width: 22)
                            Text("RES-").foregroundStyle(.secondary)
                            TextField("digits only".localized, text: $resDigits)
                                .keyboardType(.numberPad)
                                .onChange(of: resDigits) { _, v in
                                    let d = v.filter(\.isNumber)
                                    if d != v { resDigits = d }
                                    refreshResWarning()
                                }
                        }
                        if !resDuplicateWarning.isEmpty {
                            Text(resDuplicateWarning).font(.caption).foregroundStyle(.red)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "banknote").foregroundStyle(.blue).frame(width: 22)
                            TextField("Amount".localized, text: $amountText).keyboardType(.decimalPad)
                            Text(AppCurrency.code).foregroundStyle(.secondary)
                        }

                        if isTraffic {
                            DatePicker("Contract issue date".localized, selection: $contractIssueDate, displayedComponents: [.date])
                            HStack(spacing: 10) {
                                Image(systemName: "creditcard").foregroundStyle(.blue).frame(width: 22)
                                TextField("Paid amount (optional)".localized, text: $paidAmountText).keyboardType(.decimalPad)
                                Text(AppCurrency.code).foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "target").foregroundStyle(.orange).frame(width: 22)
                                TextField("Expected amount (optional)".localized, text: $expectedAmountText).keyboardType(.decimalPad)
                                Text(AppCurrency.code).foregroundStyle(.secondary)
                            }
                            DatePicker("Date".localized, selection: $processedDate, displayedComponents: [.date, .hourAndMinute])
                        }

                        TextField("Notes (optional)".localized, text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    Section("Photos".localized) {
                        photoPickerSection
                        if isTraffic {
                            Text("At least one photo is required for traffic accident contracts.".localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Photos optional".localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button("Save".localized) {
                            Task { await saveTapped() }
                        }
                        .disabled(!canSave || isSaving)
                    }
                }
            }
            .blur(radius: showSaveOverlay ? 6 : 0)
            .allowsHitTesting(!showSaveOverlay)

            if showSaveOverlay { intakeSaveOverlay }
        }
        .navigationTitle("Add operation".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .onAppear {
            if selectedRoute == nil { selectedRoute = preselectedRoute }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showImagePicker) { ImagePicker(selectedImages: $selectedImages) }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let img = capturedImage {
                selectedImages.append(img)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
    }

    @ViewBuilder
    private var photoPickerSection: some View {
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
                            Button { selectedImages.remove(at: i) } label: {
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
        Button { showImagePicker = true } label: {
            Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
        }
        Button { showCamera = true } label: {
            Label("Take Photo".localized, systemImage: "camera")
        }
    }

    private var intakeSaveOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                if saveOverlaySucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Operation saved".localized).font(.headline)
                } else {
                    ProgressView().scaleEffect(1.2)
                    Text("Saving...".localized).font(.headline)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func refreshResWarning() {
        guard isTraffic else {
            resDuplicateWarning = ""
            return
        }
        let canon = TrafficAccidentContract.canonicalRES(from: resDigits)
        if canon.isEmpty {
            resDuplicateWarning = ""
            return
        }
        resDuplicateWarning = viewModel.hasPrimaryTrafficContract(res: canon)
            ? "This RES has already been used.".localized
            : ""
    }

    @MainActor
    private func saveTapped() async {
        guard let route = selectedRoute, let amount = parsedAmount else { return }
        let canon = TrafficAccidentContract.canonicalRES(from: resDigits)
        if isTraffic && canon.isEmpty { return }

        isSaving = true
        showSaveOverlay = true
        saveOverlaySucceeded = false

        var urls: [String] = []
        for img in selectedImages {
            let folder = route == .trafficAccident ? "traffic_accident_contracts" : "office_operations"
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/\(folder)/\(UUID().uuidString).jpg"
            if let url = try? await ImageUploadActor.shared.upload(image: img, path: path) {
                urls.append(url)
            }
        }

        if isTraffic && urls.isEmpty {
            isSaving = false
            showSaveOverlay = false
            ToastManager.shared.show("Add at least one contract photo.".localized, type: .warning)
            return
        }

        let paid: Double? = {
            guard isTraffic, let max = parsedAmount else { return nil }
            let t = paidAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0.009 else { return nil }
            return min(v, max)
        }()

        let expected: Double? = {
            guard !isTraffic else { return nil }
            let t = expectedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
            return v
        }()

        viewModel.submitFleetOperation(
            route: route,
            amount: amount,
            resCanonical: canon,
            photos: urls,
            notes: notes,
            processedDate: processedDate,
            contractIssueDate: contractIssueDate,
            paidAmount: paid,
            expectedAmount: expected
        )

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
