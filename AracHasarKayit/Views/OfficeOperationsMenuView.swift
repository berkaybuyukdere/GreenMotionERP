import SwiftUI

struct OfficeOperationsMenuView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var selectedOperation: OfficeOperationType?
    @State private var showAddOperation = false
    
    private var currentMonthOperations: [OfficeOperation] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) else {
            return viewModel.officeOperations
        }
        return viewModel.officeOperations.filter { $0.date >= monthStart && $0.date <= monthEnd }
    }

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            operationCardsScroll
            emptyStateView
            Spacer()
        }
        .navigationTitle("Office Operations".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done".localized) { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddOperation = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $selectedOperation) { opType in
            NavigationView {
                OfficeOperationListView(operationType: opType, selectedMonth: selectedMonth)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            }
        .sheet(isPresented: $showAddOperation) {
            NavigationView {
                AddOfficeOperationView()
                    .environmentObject(viewModel)
            }
        }
    }
    
    private var headerSection: some View {
        Text("Select Operation Type".localized)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
    
    private var operationCardsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(OfficeOperationType.allCases, id: \.self) { opType in
                    let count = currentMonthOperations.filter { $0.type == opType }.count
                    let totalAmount = currentMonthOperations.filter { $0.type == opType }.reduce(0) { $0 + $1.amount }
                    
                    OfficeOperationCard(
                        type: opType,
                        count: count,
                        totalAmount: totalAmount
                    )
                    .onTapGesture {
                        selectedOperation = opType
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var emptyStateView: some View {
        Group {
            if selectedOperation == nil {
                VStack(spacing: 20) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("Select Operation Type".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Choose an operation type from above".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct OfficeOperationCard: View {
    let type: OfficeOperationType
    let count: Int
    let totalAmount: Double
    
    var color: Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(AppCurrency.amountWithCode(totalAmount))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            
            Text(type.rawValue.localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Text("\(count) \("entries".localized)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 160, height: 140)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Office Operation List View
struct OfficeOperationListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let operationType: OfficeOperationType
    let selectedMonth: Date

    private var canViewFinancials: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin
    }

    @State private var searchQuery = ""
    @State private var showReportGenerator = false
    @State private var editingOperation: OfficeOperation?
    
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
    
    var filteredOperations: [OfficeOperation] {
        viewModel.officeOperations.filter { op in
            let matchesType = op.type == operationType
            let matchesDate = op.date >= dateRange.start && op.date <= dateRange.end
            let matchesSearch = searchQuery.isEmpty ||
                (op.vehiclePlate?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                op.notes.localizedCaseInsensitiveContains(searchQuery)
            
            return matchesType && matchesDate && matchesSearch
        }.sorted { $0.date > $1.date }
    }
    
    var totalAmount: Double {
        filteredOperations.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Total Amount — visible to managers/admins/superadmins only
            if canViewFinancials {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Amount".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(AppCurrency.format(totalAmount))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(getColor())
                        }
                        Spacer()
                        Button {
                            showReportGenerator = true
                            HapticManager.shared.medium()
                        } label: {
                            Label("Generate Report".localized, systemImage: "doc.text.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(getColor())
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 5)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(filteredOperations.count) \("records".localized)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...".localized, text: $searchQuery)
                        .textInputAutocapitalization(.characters)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 5)
            .padding(.horizontal)
            .padding(.top, canViewFinancials ? 0 : 8)

            if filteredOperations.isEmpty {
                emptyStateView
            } else {
                operationListSection
                    .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(operationType.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showReportGenerator) {
            NavigationView {
                OfficeOperationReportGeneratorView(operationType: operationType, operations: filteredOperations)
                    .environmentObject(viewModel)
            }
        }
        .sheet(item: $editingOperation) { operation in
            NavigationView {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Operations Found".localized)
                .font(.headline)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var operationListSection: some View {
        List {
            Section("\(operationType.rawValue.localized) \("List".localized)") {
                ForEach(filteredOperations) { operation in
                    NavigationLink(destination: OfficeOperationDetailView(operation: operation)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)) {
                        OfficeOperationRow(operation: operation)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            editingOperation = operation
                            HapticManager.shared.medium()
                        } label: {
                            Label("Edit".localized, systemImage: "pencil")
                        }
                        .tint(.blue)
                        
                        Button(role: .destructive) {
                            viewModel.officeOperationSil(operation)
                            HapticManager.shared.success()
                        } label: {
                            Label("Delete".localized, systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
    
    func deleteOperations(at offsets: IndexSet) {
        for index in offsets {
            let operation = filteredOperations[index]
            viewModel.officeOperationSil(operation)
        }
    }
    
    func getColor() -> Color {
        switch operationType.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
}

struct OfficeOperationRow: View {
    let operation: OfficeOperation
    @EnvironmentObject var viewModel: AracViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Status icon for fuel receipts
            if operation.type == .fuelReceipt {
                Button {
                    toggleFuelCompletion()
                } label: {
                    Image(systemName: operation.isCompleted ? "checkmark.circle.fill" : "circle.fill")
                        .font(.title3)
                        .foregroundColor(operation.isCompleted ? .green : .yellow)
                }
                .buttonStyle(AppTheme.ghostButtonStyle)
                .frame(width: 30)
            } else {
                Image(systemName: operation.type.icon)
                    .font(.title3)
                    .foregroundColor(getColor())
                    .frame(width: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(AppCurrency.format(operation.amount))
                        .font(.headline)
                        .fontWeight(.bold)

                    if let plate = operation.vehiclePlate {
                        Text("• \(plate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Show additional info based on operation type
                if operation.type == .trafficFine, let fineNumber = operation.fineNumber {
                    Text("Fine #\(fineNumber)")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                } else if operation.type == .banking, let bankName = operation.bankName {
                    Text(bankName)
                        .font(.caption)
                        .foregroundColor(.indigo.opacity(0.8))
                        .lineLimit(1)
                } else if operation.type == .additionalSales, let productName = operation.productName {
                    Text(productName)
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.8))
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    Label(operation.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !operation.photos.isEmpty {
                        Label("\(operation.photos.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let posCount = operation.posCount {
                        Label("\(posCount) POS", systemImage: "creditcard")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    // Show completion status for fuel
                    if operation.type == .fuelReceipt {
                        Label(operation.isCompleted ? "Done".localized : "Pending".localized, systemImage: operation.isCompleted ? "checkmark" : "clock")
                            .font(.caption)
                            .foregroundColor(operation.isCompleted ? .green : .yellow)
                    }
                    
                    // Show payment status for traffic fines
                    if operation.type == .trafficFine, let paymentStatus = operation.paymentStatus {
                        Label(paymentStatus, systemImage: paymentStatus.lowercased().contains("paid") ? "checkmark.circle" : "clock")
                            .font(.caption)
                            .foregroundColor(paymentStatus.lowercased().contains("paid") ? .green : 
                                           paymentStatus.lowercased().contains("pending") ? .orange : .red)
                    }
                    
                    // Show transaction type for banking
                    if operation.type == .banking, let transactionType = operation.transactionType {
                        Label(transactionType, systemImage: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                    
                    // Show salesperson for additional sales
                    if operation.type == .additionalSales,
                       let seller = operation.salesPerson ?? operation.customerName {
                        Label(seller, systemImage: "person")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                
                if !operation.notes.isEmpty {
                    Text(operation.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func toggleFuelCompletion() {
        var updatedOperation = operation
        updatedOperation.isCompleted.toggle()
        
        HapticManager.shared.medium()
        viewModel.officeOperationGuncelle(updatedOperation) { success in
            if success {
                HapticManager.shared.success()
                ToastManager.shared.show(updatedOperation.isCompleted ? "✓ Marked as done".localized : "Pending".localized, type: .success)
            } else {
                HapticManager.shared.error()
            }
        }
    }
    
    func getColor() -> Color {
        switch operation.type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Edit Office Operation View
struct EditOfficeOperationView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    let operation: OfficeOperation
    
    @State private var amount = ""
    @State private var vehiclePlate = ""
    @State private var pos1Amount = ""
    @State private var pos2Amount = ""
    @State private var posTerminalAmounts: [String] = ["", ""]
    @State private var posTerminalCount: Int = 2
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var pulseAnimation = false
    
    init(operation: OfficeOperation) {
        self.operation = operation
        _amount = State(initialValue: String(format: "%.2f", operation.amount))
        _vehiclePlate = State(initialValue: operation.vehiclePlate ?? "")
        _notes = State(initialValue: operation.notes)
        _uploadedPhotoURLs = State(initialValue: operation.photos)
        
        if operation.type == .posClosing, let posAmounts = operation.posAmounts {
            _pos1Amount = State(initialValue: String(format: "%.2f", posAmounts.first ?? 0))
            _pos2Amount = State(initialValue: String(format: "%.2f", posAmounts.last ?? 0))
            let count = max(posAmounts.count, 1)
            _posTerminalCount = State(initialValue: count)
            _posTerminalAmounts = State(initialValue: posAmounts.map { String(format: "%.2f", $0) })
        }
    }
    
    var body: some View {
        ZStack {
            Form {
                Section("Operation Type".localized) {
                    HStack {
                        Label(operation.type.rawValue.localized, systemImage: operation.type.icon)
                        Spacer()
                        Text("(Cannot be changed)".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if operation.type != .posClosing {
                    amountSection
                }
                
                if operation.type == .fuelReceipt {
                    vehicleSection
                }
                
                if operation.type == .posClosing {
                    posSection
                }
                
                photoSection
                notesSection
                saveSection
            }
            .blur(radius: showCompletionOverlay ? 8 : 0)
            .allowsHitTesting(!showCompletionOverlay)
            
            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle("Edit Operation".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let newImage = capturedImage {
                selectedImages.append(newImage)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
        .onChange(of: showCompletionOverlay) { isVisible in
            if isVisible {
                dismissKeyboard()
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }
    
    private var amountSection: some View {
        Section("Amount".localized) {
            HStack {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(.green)
                TextField("Amount".localized, text: $amount)
                    .keyboardType(.decimalPad)
            }
        }
    }
    
    private var vehicleSection: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Vehicle Plate".localized, text: $vehiclePlate)
                    .textInputAutocapitalization(.characters)
            }
        }
    }
    
    private var posSection: some View {
        Section {
            Stepper(value: $posTerminalCount, in: 1...10, onEditingChanged: { _ in }) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.blue)
                    Text(String(format: "POS Terminals: %d".localized, posTerminalCount))
                        .fontWeight(.medium)
                }
            }
            .onChange(of: posTerminalCount) { newCount in
                if posTerminalAmounts.count < newCount {
                    posTerminalAmounts.append(contentsOf: Array(repeating: "", count: newCount - posTerminalAmounts.count))
                } else if posTerminalAmounts.count > newCount {
                    posTerminalAmounts = Array(posTerminalAmounts.prefix(newCount))
                }
            }

            ForEach(0..<posTerminalCount, id: \.self) { idx in
                HStack {
                    Image(systemName: "\(idx + 1).circle.fill")
                        .foregroundColor(idx == 0 ? .green : .blue)
                    Text(String(format: "POS %d Amount".localized, idx + 1))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("0.00", text: Binding(
                        get: { idx < posTerminalAmounts.count ? posTerminalAmounts[idx] : "" },
                        set: { newVal in
                            if idx < posTerminalAmounts.count { posTerminalAmounts[idx] = newVal }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    Text(AppCurrency.code)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(String(format: "POS Information (%d Terminals)".localized, posTerminalCount))
        }
    }
    
    private var photoSection: some View {
        Section("Photos".localized) {
            if !uploadedPhotoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(uploadedPhotoURLs, id: \.self) { photoURL in
                            ZStack(alignment: .topTrailing) {
                                AsyncImageView(urlString: photoURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                Button {
                                    uploadedPhotoURLs.removeAll { $0 == photoURL }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
            
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
            
            HStack(spacing: 16) {
                Button {
                    showImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.fill")
                        Text("From Gallery".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes".localized) {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                completionSucceeded = false
                pulseAnimation = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionOverlay = true
                }
                saveOperation()
            } label: {
                if isUploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...".localized)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Changes".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(isUploading || !isValid)
        }
    }
    
    private var completionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if completionSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Done".localized)
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                    Text("Uploading...".localized)
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
    
    var isValid: Bool {
        if operation.type == .posClosing {
            let amounts = posTerminalAmounts.prefix(posTerminalCount).compactMap { Double($0) }
            guard amounts.count == posTerminalCount else { return false }
            return amounts.reduce(0, +) > 0
        } else {
            guard let amountValue = Double(amount), amountValue > 0 else { return false }
        }
        
        if operation.type == .fuelReceipt && vehiclePlate.isEmpty {
            return false
        }
        
        return true
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func saveOperation() {
        isUploading = true
        
        let group = DispatchGroup()
        var newPhotoURLs: [String] = uploadedPhotoURLs
        var uploadErrors: [Error] = []
        let lock = NSLock()
        
        for image in selectedImages {
            group.enter()
            let path = "office_operations/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        newPhotoURLs.append(url)
                        lock.unlock()
                    } else if let error = error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error: \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Check if there were upload errors
            if !uploadErrors.isEmpty {
                self.isUploading = false
                let failedCount = uploadErrors.count
                let totalCount = selectedImages.count
                
                if failedCount == totalCount {
                    // All photos failed
                    withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.".localized)
                    return
                } else {
                    // Some photos failed - continue with available photos
                    ErrorManager.shared.showError(message: String(format: "%d out of %d photos failed to upload. Operation will be saved with available photos.".localized, failedCount, totalCount))
                }
            }
            
            let finalAmount: Double
            var posAmounts: [Double]?
            
            if operation.type == .posClosing {
                let amounts = posTerminalAmounts.prefix(posTerminalCount).map { Double($0) ?? 0 }
                posAmounts = Array(amounts)
                finalAmount = amounts.reduce(0, +)
            } else {
                finalAmount = Double(amount) ?? 0
            }
            
            var updatedOperation = operation
            updatedOperation.amount = finalAmount
            updatedOperation.photos = newPhotoURLs
            updatedOperation.vehiclePlate = operation.type == .fuelReceipt ? vehiclePlate : nil
            updatedOperation.posCount = operation.type == .posClosing ? posTerminalCount : operation.posCount
            updatedOperation.posAmounts = posAmounts
            updatedOperation.notes = notes
            
            viewModel.officeOperationGuncelle(updatedOperation) { success in
                isUploading = false
                if success {
                    HapticManager.shared.success()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        completionSucceeded = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
                        dismiss()
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
                }
            }
        }
    }
}

// MARK: - Add Office Operation View
struct AddOfficeOperationView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedType: OfficeOperationType = .creditCard
    @State private var amount = ""
    @State private var vehiclePlate = ""
    @State private var pos1Amount = ""
    @State private var pos2Amount = ""
    /// How many POS terminals the user wants to record (user-configurable, 1–10)
    @State private var posTerminalCount: Int = 2
    /// Amounts for each terminal, indexed 0..<posTerminalCount
    @State private var posTerminalAmounts: [String] = ["", ""]
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    
    // MARK: - Traffic Fine Fields
    @State private var fineNumber = ""
    @State private var fineType = ""
    @State private var paymentStatus = "Pending"
    @State private var customerName = ""
    @State private var resCode = ""
    
    // MARK: - Banking Fields
    @State private var transactionNumber = ""
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var transactionType = ""
    @State private var referenceNumber = ""
    
    // MARK: - Additional Sales Fields
    @State private var productName = ""
    @State private var quantity = ""
    @State private var unitPrice = ""
    @State private var invoiceNumber = ""
    @State private var selectedSalesPerson = ""
    @State private var showCreateSalesPersonAlert = false
    @State private var newSalesPersonName = ""
    
    @State private var showTypePicker = false
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var pulseAnimation = false
    
    private var availableSalesPeople: [String] {
        Array(Set(viewModel.additionalSalesPeople)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
    
    var body: some View {
        ZStack {
            Form {
                typeSection
                
                if selectedType != .posClosing {
                    amountSection
                }
                
                // Traffic Fine specific fields
                trafficFineSection
                
                // Banking specific fields
                bankingSection
                
                // Additional Sales specific fields
                additionalSalesSection
                
                if selectedType == .fuelReceipt {
                    vehicleSection
                }
                
                if selectedType == .posClosing {
                    posSection
                }
                
                photoSection
                notesSection
                saveSection
            }
            .blur(radius: showCompletionOverlay ? 8 : 0)
            .allowsHitTesting(!showCompletionOverlay)
            
            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .sheet(isPresented: $showTypePicker) {
            OperationTypePickerView(selectedType: $selectedType)
        }
        .onChange(of: selectedType) { newType in
            if newType == .washing {
                // Do not auto-fill; let user enter the actual amount.
            }
            if newType == .additionalSales {
                if availableSalesPeople.isEmpty {
                    selectedSalesPerson = ""
                } else if !availableSalesPeople.contains(selectedSalesPerson) {
                    selectedSalesPerson = availableSalesPeople[0]
                }
            }
        }
        .alert("Create a person".localized, isPresented: $showCreateSalesPersonAlert) {
            TextField("Person name".localized, text: $newSalesPersonName)
            Button("Cancel".localized, role: .cancel) {
                newSalesPersonName = ""
            }
            Button("Save".localized) {
                let name = newSalesPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.addAdditionalSalesPerson(name: name) { success in
                    if success {
                        selectedSalesPerson = name
                        ToastManager.shared.show("Person added".localized, type: .success)
                    } else {
                        ToastManager.shared.show("Failed to add person".localized, type: .error)
                    }
                    newSalesPersonName = ""
                }
            }
        } message: {
            Text("Add person for this franchise".localized)
        }
        .navigationTitle("Add Office Operation".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let newImage = capturedImage {
                selectedImages.append(newImage)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
        .onChange(of: showCompletionOverlay) { isVisible in
            if isVisible {
                dismissKeyboard()
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }
    
    private var typeSection: some View {
        Section("Operation Type*".localized) {
            Button {
                showTypePicker = true
            } label: {
                HStack {
                    Image(systemName: selectedType.icon)
                        .foregroundColor(getTypeColor())
                    Text(selectedType.rawValue.localized)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
    }
    
    private func getTypeColor() -> Color {
        switch selectedType.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
    
    private var amountSection: some View {
        Section("Amount (\(AppCurrency.code))*") {
            HStack {
                Image(systemName: "creditcard.circle.fill")
                    .foregroundColor(.green)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                Text(AppCurrency.code)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Traffic Fine Specific Fields
    @ViewBuilder
    private var trafficFineSection: some View {
        if selectedType == .trafficFine {
            Section("Traffic Fine Details".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.red)
                        TextField("Plate*".localized, text: $vehiclePlate)
                            .textInputAutocapitalization(.characters)
                    }
                    
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.red)
                        TextField("Customer Name*".localized, text: $customerName)
                    }
                    
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.secondary)
                        TextField("Res code (e.g., Res-12454)".localized, text: $resCode)
                    }
                    
                    Picker("Status".localized, selection: $paymentStatus) {
                        Text("Pending".localized).tag("Pending")
                        Text("Paid".localized).tag("Paid")
                        Text("Overdue".localized).tag("Overdue")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    // MARK: - Banking Specific Fields
    @ViewBuilder
    private var bankingSection: some View {
        if selectedType == .banking {
            Section("Banking Details".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.secondary)
                        TextField("Res code (e.g., Res-12454)".localized, text: $resCode)
                    }
                }
            }
        }
    }
    
    // MARK: - Additional Sales Specific Fields
    @ViewBuilder
    private var additionalSalesSection: some View {
        if selectedType == .additionalSales {
            Section("Additional Sales".localized) {
                if availableSalesPeople.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No person found for this franchise".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            showCreateSalesPersonAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Create a person".localized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Picker("Sold By".localized, selection: $selectedSalesPerson) {
                        ForEach(availableSalesPeople, id: \.self) { person in
                            Text(person).tag(person)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button {
                        showCreateSalesPersonAlert = true
                    } label: {
                        Label("Create a person".localized, systemImage: "plus.circle")
                    }
                }
            }
        }
    }
    
    private var vehicleSection: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Vehicle Plate".localized, text: $vehiclePlate)
                    .textInputAutocapitalization(.characters)
            }
        }
    }
    
    private var posSection: some View {
        Section {
            // Terminal count stepper
            Stepper(value: $posTerminalCount, in: 1...10, onEditingChanged: { _ in
                // Grow / shrink the amounts array to match the new count
                if posTerminalAmounts.count < posTerminalCount {
                    posTerminalAmounts.append(contentsOf: Array(repeating: "", count: posTerminalCount - posTerminalAmounts.count))
                } else if posTerminalAmounts.count > posTerminalCount {
                    posTerminalAmounts = Array(posTerminalAmounts.prefix(posTerminalCount))
                }
            }) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.blue)
                    Text(String(format: "POS Terminals: %d".localized, posTerminalCount))
                        .fontWeight(.medium)
                }
            }
            .onChange(of: posTerminalCount) { newCount in
                if posTerminalAmounts.count < newCount {
                    posTerminalAmounts.append(contentsOf: Array(repeating: "", count: newCount - posTerminalAmounts.count))
                } else if posTerminalAmounts.count > newCount {
                    posTerminalAmounts = Array(posTerminalAmounts.prefix(newCount))
                }
            }

            // One row per terminal
            ForEach(0..<posTerminalCount, id: \.self) { idx in
                HStack {
                    Image(systemName: "\(idx + 1).circle.fill")
                        .foregroundColor(idx == 0 ? .green : .blue)
                    Text(String(format: "POS %d Amount".localized, idx + 1))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("0.00", text: Binding(
                        get: { idx < posTerminalAmounts.count ? posTerminalAmounts[idx] : "" },
                        set: { newVal in
                            if idx < posTerminalAmounts.count { posTerminalAmounts[idx] = newVal }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    Text(AppCurrency.code)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(String(format: "POS Information (%d Terminals)".localized, posTerminalCount))
        }
    }
    
    private var photoSection: some View {
        Section("Photos".localized) {
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    guard !showCamera else { return }
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Gallery".localized)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showCamera)
                
                Button(action: {
                    guard !showImagePicker else { return }
                    showCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                        Text("Take Photo".localized)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(showImagePicker)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes".localized) {
            TextEditor(text: $notes)
                .frame(height: 100)
                .overlay(
                    Group {
                        if notes.isEmpty {
                            Text("Additional notes...".localized)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
    
    private var saveSection: some View {
        Section {
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    completionSucceeded = false
                    pulseAnimation = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletionOverlay = true
                    }
                    saveOperation()
                } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                            Text("Uploading...".localized)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Add Operation".localized)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || !isValid)
            }
        }
    }
    
    private var completionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if completionSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Done".localized)
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                    Text("Uploading...".localized)
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
    
    var isValid: Bool {
        // Amount validation
        if selectedType == .posClosing {
            let amounts = posTerminalAmounts.prefix(posTerminalCount).compactMap { Double($0) }
            guard amounts.count == posTerminalCount else { return false }
            return amounts.reduce(0, +) > 0
        } else {
            guard let amountValue = Double(amount), amountValue > 0 else { return false }
        }
        
        // Traffic Fine specific validations
        if selectedType == .trafficFine {
            if vehiclePlate.isEmpty || customerName.isEmpty {
                return false
            }
        }
        
        // Fuel Receipt requires vehicle plate
        if selectedType == .fuelReceipt && vehiclePlate.isEmpty {
            return false
        }
        
        if selectedType == .additionalSales && selectedSalesPerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        
        return true
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func saveOperation() {
        isUploading = true
        uploadedPhotoURLs = []
        
        let group = DispatchGroup()
        let urlLock = NSLock()
        
        for image in selectedImages {
            group.enter()
            let path = "office_operations/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                if let url = url {
                    urlLock.lock()
                    uploadedPhotoURLs.append(url)
                    urlLock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let finalAmount: Double
            var posAmounts: [Double]?
            
            if selectedType == .posClosing {
                let amounts = posTerminalAmounts.prefix(posTerminalCount).map { Double($0) ?? 0 }
                posAmounts = Array(amounts)
                finalAmount = amounts.reduce(0, +)
            } else {
                finalAmount = Double(amount) ?? 0
            }
            
            // Create operation with type-specific fields
            var operation = OfficeOperation(
                type: selectedType,
                date: Date(),
                amount: finalAmount,
                photos: uploadedPhotoURLs,
                vehiclePlate: (selectedType == .fuelReceipt || selectedType == .trafficFine) ? vehiclePlate : nil,
                posCount: selectedType == .posClosing ? posTerminalCount : nil,
                posAmounts: posAmounts,
                notes: notes
            )
            
            // Set Traffic Fine specific fields
            if selectedType == .trafficFine {
                operation.fineNumber = resCode.isEmpty ? nil : resCode
                operation.paymentStatus = paymentStatus
                operation.customerName = customerName.isEmpty ? nil : customerName
            }
            
            // Set Banking specific fields
            if selectedType == .banking {
                operation.referenceNumber = resCode.isEmpty ? nil : resCode
            }
            
            if selectedType == .additionalSales {
                operation.salesPerson = selectedSalesPerson
            }
            
            viewModel.officeOperationEkle(operation)
            isUploading = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                completionSucceeded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
                dismiss()
            }
        }
    }
}

// MARK: - Operation Type Picker View
struct OperationTypePickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedType: OfficeOperationType
    
    var body: some View {
        NavigationView {
            List {
                ForEach(OfficeOperationType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: type.icon)
                                .font(.title2)
                                .foregroundColor(getColor(for: type))
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            if selectedType == type {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Operation Type".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getColor(for type: OfficeOperationType) -> Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Office Operation Detail View
struct OfficeOperationDetailView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    let operation: OfficeOperation

    private var canViewFinancials: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin
    }

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showPhotoGallery = false
    @State private var selectedPhotoIndex: Int = 0

    var body: some View {
        List {
            Section("Details".localized) {
                HStack {
                    Label("Type".localized, systemImage: operation.type.icon)
                    Spacer()
                    Text(operation.type.rawValue.localized)
                        .foregroundColor(.secondary)
                }

                if canViewFinancials {
                    HStack {
                        Label("Amount".localized, systemImage: "eurosign.circle")
                        Spacer()
                        Text(AppCurrency.format(operation.amount))
                            .font(.headline)
                    }
                }
                
                HStack {
                    Label("Date".localized, systemImage: "calendar")
                    Spacer()
                    Text(operation.date.formatted(date: .long, time: .shortened))
                        .foregroundColor(.secondary)
                }
                
                if operation.type == .additionalSales,
                   let seller = operation.salesPerson ?? operation.customerName {
                    HStack {
                        Label("Sold By".localized, systemImage: "person.fill")
                        Spacer()
                        Text(seller)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let plate = operation.vehiclePlate {
                    HStack {
                        Label("Vehicle".localized, systemImage: "car")
                        Spacer()
                        Text(plate)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let posCount = operation.posCount {
                    HStack {
                        Label("POS Count".localized, systemImage: "creditcard")
                        Spacer()
                        Text("\(posCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let amounts = operation.posAmounts {
                        ForEach(amounts.indices, id: \.self) { index in
                            HStack {
                                Text(String(format: "POS %d".localized, index + 1))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(AppCurrency.amountWithCode(amounts[index]))
                                    .fontWeight(.semibold)
                            }
                            .padding(.leading)
                        }
                    }
                }
            }
            
if !operation.notes.isEmpty {
            Section("Notes".localized) {
                Text(operation.notes)
                    .foregroundColor(.secondary)
                }
            }
            
            if !operation.photos.isEmpty {
                Section("Photos".localized) {
                    ForEach(Array(operation.photos.enumerated()), id: \.offset) { index, photoURL in
                        Button {
                            selectedPhotoIndex = index
                            showPhotoGallery = true
                        } label: {
                            AsyncImageView(urlString: photoURL) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Operation", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Operation Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSheet = true
                    HapticManager.shared.medium()
                } label: {
                    Label("Edit", systemImage: "pencil.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationView {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
        }
        .fullScreenCover(isPresented: $showPhotoGallery) {
            PhotoGalleryView(photoURLs: operation.photos, initialIndex: selectedPhotoIndex)
        }
        .alert("Delete Operation".localized, isPresented: $showDeleteAlert) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.officeOperationSil(operation)
                HapticManager.shared.success()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this operation? This action cannot be undone.".localized)
        }
    }
}

// MARK: - Office Operation Report Generator View
struct OfficeOperationReportGeneratorView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    let operationType: OfficeOperationType
    let operations: [OfficeOperation]
    
    @State private var reportPeriod: ReportPeriod = .daily
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isGenerating = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    
    enum ReportPeriod: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"
        case custom = "Custom Range"
    }
    
    var filteredOperations: [OfficeOperation] {
        let calendar = Calendar.current
        let now = Date()
        
        let dateRange: (start: Date, end: Date)
        
        switch reportPeriod {
        case .daily:
            let start = calendar.startOfDay(for: now)
            dateRange = (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            dateRange = (start, now)
        case .monthly:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            dateRange = (start, now)
        case .yearly:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            dateRange = (start, now)
        case .custom:
            dateRange = (customStartDate, customEndDate)
        }
        
        return operations.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }
    }
    
    var totalAmount: Double {
        filteredOperations.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        List {
            Section("Report Period".localized) {
                Picker("Period".localized, selection: $reportPeriod) {
                    ForEach(ReportPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue.localized).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                
                if reportPeriod == .custom {
                    DatePicker("Start Date".localized, selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date".localized, selection: $customEndDate, displayedComponents: .date)
                }
            }
            
            Section("Report Summary".localized) {
                HStack {
                    Text("Period".localized)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(reportPeriod.rawValue.localized)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Total Operations".localized)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(filteredOperations.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Total Amount".localized)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(AppCurrency.amountWithCode(totalAmount))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                if operationType == .posClosing {
                    let maxTerminals = filteredOperations.compactMap { $0.posAmounts?.count }.max() ?? 2
                    ForEach(0..<maxTerminals, id: \.self) { idx in
                        let terminalTotal = filteredOperations.compactMap { $0.posAmounts?.indices.contains(idx) == true ? $0.posAmounts?[idx] : nil }.reduce(0, +)
                        HStack {
                            Text(String(format: "POS %d Total".localized, idx + 1))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(AppCurrency.amountWithCode(terminalTotal))
                                .fontWeight(.semibold)
                                .foregroundColor(idx == 0 ? .green : .blue)
                        }
                    }
                }
            }
            
            Section("Export Options".localized) {
                Button {
                    generatePDFReport()
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text("Generate PDF Report".localized)
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                    .foregroundColor(.red)
                }
                .disabled(isGenerating || filteredOperations.isEmpty)
                
                Button {
                    generateExcelReport()
                } label: {
                    HStack {
                        Image(systemName: "tablecells.fill")
                        Text("Generate Excel Report".localized)
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        }
                    }
                    .foregroundColor(.green)
                }
                .disabled(isGenerating || filteredOperations.isEmpty)
            }
            
            if filteredOperations.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("No operations found for this period".localized)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .navigationTitle("Generate Report".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
    
    func generatePDFReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let pdfData = createPDFData()
            
            // Use documents directory instead of temporary for better file access
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).pdf")
            
            do {
                try pdfData.write(to: fileURL)
                
                // Ensure file is accessible
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("❌ PDF file was not created successfully")
                    ErrorManager.shared.showError(message: "Failed to create PDF file")
                    isGenerating = false
                    return
                }
                
                print("✅ PDF created successfully at: \(fileURL.path)")
                shareURL = fileURL
                isGenerating = false
                
                                let operationsCount = viewModel.officeOperations.filter { $0.type == operationType }.count
                // Small delay to ensure file is fully written
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showShareSheet = true
                }
            } catch {
                print("❌ Error writing PDF: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "PDF Generation")
                isGenerating = false
            }
        }
    }
    
    func generateExcelReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let csvData = createCSVData()
            
            // Use documents directory instead of temporary for better file access
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).csv")
            
            do {
                try csvData.write(to: fileURL)
                
                // Ensure file is accessible
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("❌ CSV file was not created successfully")
                    ErrorManager.shared.showError(message: "Failed to create CSV file")
                    isGenerating = false
                    return
                }
                
                print("✅ CSV created successfully at: \(fileURL.path)")
                shareURL = fileURL
                isGenerating = false
                
                                let operationsCount = viewModel.officeOperations.filter { $0.type == operationType }.count
                // Small delay to ensure file is fully written
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showShareSheet = true
                }
            } catch {
                print("❌ Error writing CSV: \(error.localizedDescription)")
                ErrorManager.shared.showError(error, context: "CSV Generation")
                isGenerating = false
            }
        }
    }
    
    func createPDFData() -> Data {
        let pdfMetadata = [
            kCGPDFContextTitle: "\(operationType.rawValue) Report",
            kCGPDFContextAuthor: viewModel.franchiseName.isEmpty ? "Green Motion" : viewModel.franchiseName,
            kCGPDFContextCreator: (viewModel.franchiseName.isEmpty ? "Green Motion" : viewModel.franchiseName) + " Fleet Management"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        return renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            
            // MARK: - SWISS DESIGN HEADER (Minimal, no colors)
            var yPosition: CGFloat = 60
            
            // Company Name - Bold Helvetica
            let companyName = viewModel.franchiseName.isEmpty ? "GREEN MOTION" : viewModel.franchiseName.uppercased()
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            let companyAttrs: [NSAttributedString.Key: Any] = [
                .font: companyFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: companyAttrs)
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let countryName = UserDefaults.standard.selectedCountry.name.uppercased()
            let subtitle = countryName
            let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: SwissPDFHelper.mediumGray
            ]
            subtitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: subtitleAttrs)
            yPosition += 40
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - TITLE (Swiss Design: Bold, minimal)
            let reportTitle = "\(operationType.rawValue) Report"
            let titleFont = SwissPDFHelper.helveticaBold(size: 24)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            reportTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: titleAttrs)
            yPosition += 35
            
            // MARK: - INFO (Swiss Design: Clean lines, no boxes)
            let infoFont = SwissPDFHelper.helvetica(size: 10)
            let labelFont = SwissPDFHelper.helveticaBold(size: 10)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            
            // Report Date
            let reportDateLabel = "Report Generated:"
            let reportDateValue = dateFormatter.string(from: Date())
            reportDateLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            reportDateValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            // Period
            let periodLabel = "Period:"
            let periodValue = reportPeriod.rawValue
            periodLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            periodValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            // Date Range
            if reportPeriod == .custom {
                let rangeLabel = "Date Range:"
                let rangeValue = "\(dateFormatter.string(from: customStartDate)) - \(dateFormatter.string(from: customEndDate))"
                rangeLabel.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
                rangeValue.draw(at: CGPoint(x: 200, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 18
            }
            
            yPosition += 25
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - SUMMARY SECTION (Swiss Design: Clean typography)
            let summaryTitle = "SUMMARY"
            let sectionFont = SwissPDFHelper.helveticaBold(size: 12)
            summaryTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Summary - No boxes, just clean lines
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            let summaryBoldFont = SwissPDFHelper.helveticaBold(size: 14)
            
            "Total Operations:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(filteredOperations.count)".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 20
            
            "Total Amount:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(AppCurrency.amountWithCode(totalAmount))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 20
            
            // POS Details
            if operationType == .posClosing {
                let maxTerminalsPDF = filteredOperations.compactMap { $0.posAmounts?.count }.max() ?? 2
                for idx in 0..<maxTerminalsPDF {
                    let termTotal = filteredOperations.compactMap { $0.posAmounts?.indices.contains(idx) == true ? $0.posAmounts?[idx] : nil }.reduce(0, +)
                    "POS \(idx + 1) Total:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
                    "\(AppCurrency.amountWithCode(termTotal))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
                    yPosition += 20
                }
            }
            
            yPosition += 20
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // MARK: - OPERATIONS LIST (Swiss Design: Grid system, thin lines)
            let listTitle = "DETAILED OPERATIONS"
            listTitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Table Header - Bold, underlined
            let headerFont = SwissPDFHelper.helveticaBold(size: 9)
            let headerY = yPosition
            "DATE".draw(at: CGPoint(x: 60, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "TIME".draw(at: CGPoint(x: 180, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "AMOUNT".draw(at: CGPoint(x: 350, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            if operationType == .fuelReceipt || operationType == .washing {
                "PLATE".draw(at: CGPoint(x: 450, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            }
            
            // Underline header
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: headerY + 12), to: CGPoint(x: pageRect.width - 60, y: headerY + 12), width: 0.5)
            yPosition += 20
            
            let rowFont = SwissPDFHelper.helvetica(size: 9)
            let dateFormatterShort = DateFormatter()
            dateFormatterShort.dateFormat = "dd/MM/yyyy"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            
            for (index, operation) in filteredOperations.prefix(25).enumerated() {
                if yPosition > 750 {
                    context.beginPage()
                    yPosition = 60
                }
                
                // No alternating colors - just clean lines
                dateFormatterShort.string(from: operation.date).draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                timeFormatter.string(from: operation.date).draw(at: CGPoint(x: 180, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                "\(AppCurrency.amountWithCode(operation.amount))".draw(at: CGPoint(x: 350, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                
                if let plate = operation.vehiclePlate {
                    plate.draw(at: CGPoint(x: 450, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                }
                
                // Thin separator line
                if index < filteredOperations.prefix(25).count - 1 {
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition + 12), to: CGPoint(x: pageRect.width - 60, y: yPosition + 12), width: 0.25)
                }
                
                yPosition += 18
            }
            
            // MARK: - FOOTER (Swiss Design: Minimal, thin line)
            let footerY = pageRect.height - 30
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 20), to: CGPoint(x: pageRect.width - 60, y: footerY - 20), width: 0.25)
            
            let footerFont = SwissPDFHelper.helveticaThin(size: 7)
            let menuBrandLabel = viewModel.franchiseName.isEmpty ? "Green Motion" : viewModel.franchiseName
            let footerText = "\(menuBrandLabel) • \(UserDefaults.standard.selectedCountry.name)"
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: SwissPDFHelper.lightGray
            ]
            footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: footerAttrs)
            
            let pageNumber = "1"
            pageNumber.draw(at: CGPoint(x: pageRect.width - 80, y: footerY), withAttributes: footerAttrs)
        }
    }
    
    func createCSVData() -> Data {
        var csv = ""
        
        // Header Section
        let csvBrand = viewModel.franchiseName.isEmpty ? "GREEN MOTION" : viewModel.franchiseName.uppercased()
        csv += "\(csvBrand) - \(operationType.rawValue.uppercased()) REPORT\n"
        csv += "\(UserDefaults.standard.selectedCountry.name)\n"
        csv += "\n"
        csv += "Report Generated:,\(Date().formatted(date: .long, time: .shortened))\n"
        csv += "Period:,\(reportPeriod.rawValue)\n"
        csv += "\n"
        
        // Summary Section
        csv += "SUMMARY\n"
        csv += "Total Operations:,\(filteredOperations.count)\n"
        csv += "Total Amount:,\(AppCurrency.amountWithCode(totalAmount))\n"
        
        if operationType == .posClosing {
            let maxTerminalsCSV = filteredOperations.compactMap { $0.posAmounts?.count }.max() ?? 2
            for idx in 0..<maxTerminalsCSV {
                let termTotal = filteredOperations.compactMap { $0.posAmounts?.indices.contains(idx) == true ? $0.posAmounts?[idx] : nil }.reduce(0, +)
                csv += "POS \(idx + 1) Total:,\(AppCurrency.amountWithCode(termTotal))\n"
            }
        }
        csv += "\n"
        
        // Detailed Operations Table
        csv += "DETAILED OPERATIONS\n"
        csv += "Date,Time,Amount (\(AppCurrency.code))"
        if operationType == .fuelReceipt || operationType == .washing {
            csv += ",Vehicle Plate"
        }
        if operationType == .posClosing {
            let maxTerminalsHeader = filteredOperations.compactMap { $0.posAmounts?.count }.max() ?? 2
            for idx in 0..<maxTerminalsHeader {
                csv += ",POS \(idx + 1) Amount"
            }
        }
        csv += ",Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        for operation in filteredOperations {
            let dateStr = dateFormatter.string(from: operation.date)
            let timeStr = timeFormatter.string(from: operation.date)
            let amountStr = String(format: "%.2f", operation.amount)
            
            csv += "\(dateStr),\(timeStr),\(amountStr)"
            
            if operationType == .fuelReceipt || operationType == .washing {
                csv += ",\(operation.vehiclePlate ?? "-")"
            }
            
            if operationType == .posClosing {
                let maxTerminalsRow = filteredOperations.compactMap { $0.posAmounts?.count }.max() ?? 2
                for idx in 0..<maxTerminalsRow {
                    let val = operation.posAmounts?.indices.contains(idx) == true ? operation.posAmounts?[idx] ?? 0 : 0
                    csv += ",\(String(format: "%.2f", val))"
                }
            }
            
            let notes = operation.notes.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
            csv += ",\(notes)\n"
        }
        
        csv += "\n"
        csv += "End of Report\n"
        csv += "Generated by Green Motion Fleet Management System\n"
        
        return csv.data(using: .utf8) ?? Data()
    }
}

// MARK: - Office Operation Statistics View
struct OfficeOperationStatisticsView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    let operationType: OfficeOperationType
    let operations: [OfficeOperation]
    
    var totalAmount: Double {
        operations.reduce(0) { $0 + $1.amount }
    }
    
    var averageAmount: Double {
        operations.isEmpty ? 0 : totalAmount / Double(operations.count)
    }
    
    var groupedByDate: [String: Double] {
        var result: [String: Double] = [:]
        for op in operations {
            let key = op.date.formatted(date: .abbreviated, time: .omitted)
            result[key, default: 0] += op.amount
        }
        return result
    }
    
    var body: some View {
        List {
            Section("Summary".localized) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Amount".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(AppCurrency.amountWithCode(totalAmount))
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average Amount".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(AppCurrency.amountWithCode(averageAmount))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Entries".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(operations.count)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            
            Section("Daily Breakdown".localized) {
                ForEach(groupedByDate.sorted(by: { $0.key > $1.key }), id: \.key) { date, amount in
                    HStack {
                        Text(date)
                            .font(.subheadline)
                        Spacer()
                        Text(AppCurrency.amountWithCode(amount))
                            .font(.headline)
                    }
                }
            }
            
            if operationType == .posClosing {
                Section("POS Statistics".localized) {
                    let totalPOS = operations.compactMap { $0.posCount }.reduce(0, +)
                    HStack {
                        Text("Total POS Processed".localized)
                        Spacer()
                        Text("\(totalPOS)")
                            .fontWeight(.semibold)
                    }
                }
            }
            
            if operationType == .fuelReceipt {
                Section("Vehicle Breakdown".localized) {
                    let vehicleGroups = Dictionary(grouping: operations.compactMap { op -> (String, Double)? in
                        guard let plate = op.vehiclePlate else { return nil }
                        return (plate, op.amount)
                    }, by: { $0.0 })
                    
                    ForEach(vehicleGroups.keys.sorted(), id: \.self) { plate in
                        let total = vehicleGroups[plate]?.reduce(0) { $0 + $1.1 } ?? 0
                        HStack {
                            Text(plate)
                                .font(.subheadline)
                            Spacer()
                            Text(AppCurrency.amountWithCode(total))
                                .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
}
