import SwiftUI

struct OfficeOperationsMenuView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    var selectedMonth: Date = Date() // Default to current month if not provided
    @State private var selectedOperation: OfficeOperationType?
    @State private var showAddOperation = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            operationCardsScroll
            emptyStateView
            Spacer()
        }
        .navigationTitle("Office Operations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
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
            }
        }
        .onAppear {
            AnalyticsManager.shared.trackScreenView("Office Operations Menu")
        }
        .sheet(isPresented: $showAddOperation) {
            NavigationView {
                AddOfficeOperationView()
                    .environmentObject(viewModel)
            }
        }
    }
    
    private var headerSection: some View {
        Text("Select Operation Type")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
    
    private var operationCardsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(OfficeOperationType.allCases, id: \.self) { opType in
                    let count = viewModel.officeOperations.filter { $0.type == opType }.count
                    let totalAmount = viewModel.officeOperations.filter { $0.type == opType }.reduce(0) { $0 + $1.amount }
                    
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
                    
                    Text("Select Operation Type")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Choose an operation type from above")
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
            
            Text(String(format: "%.2f CHF", totalAmount))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            
            Text(type.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Text("\(count) entries")
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
    @Environment(\.dismiss) var dismiss
    let operationType: OfficeOperationType
    let selectedMonth: Date
    
    @State private var searchQuery = ""
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showStatistics = false
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
        VStack(spacing: 0) {
            // Month display
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(monthDisplayText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            searchAndFilterSection
            Divider()
            
            if filteredOperations.isEmpty {
                emptyStateView
            } else {
                operationListSection
            }
        }
        .navigationTitle(operationType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showStatistics) {
            NavigationView {
                OfficeOperationStatisticsView(operationType: operationType, operations: filteredOperations)
                    .environmentObject(viewModel)
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
    
    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            TextField("Search...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .foregroundColor(.secondary)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Operations Found")
                .font(.headline)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var operationListSection: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f CHF", totalAmount))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(getColor())
                    
                    HStack(spacing: 16) {
                        Button {
                            showStatistics = true
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                Text("Statistics")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle(color: getColor()))
                        
                        Button {
                            showReportGenerator = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("Generate Report")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppTheme.primaryButtonStyle)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("\(operationType.rawValue) List") {
                ForEach(filteredOperations) { operation in
                    NavigationLink(destination: OfficeOperationDetailView(operation: operation).environmentObject(viewModel)) {
                        OfficeOperationRow(operation: operation)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            editingOperation = operation
                            HapticManager.shared.medium()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                        
                        Button(role: .destructive) {
                            viewModel.officeOperationSil(operation)
                            HapticManager.shared.success()
                        } label: {
                            Label("Delete", systemImage: "trash")
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
                    Text(String(format: "%.2f CHF", operation.amount))
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if let plate = operation.vehiclePlate {
                        Text("• \(plate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
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
                        Label(operation.isCompleted ? "Done" : "Pending", systemImage: operation.isCompleted ? "checkmark" : "clock")
                            .font(.caption)
                            .foregroundColor(operation.isCompleted ? .green : .yellow)
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
                ToastManager.shared.show(updatedOperation.isCompleted ? "✓ Marked as done" : "Pending", type: .success)
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
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    
    init(operation: OfficeOperation) {
        self.operation = operation
        _amount = State(initialValue: String(format: "%.2f", operation.amount))
        _vehiclePlate = State(initialValue: operation.vehiclePlate ?? "")
        _notes = State(initialValue: operation.notes)
        _uploadedPhotoURLs = State(initialValue: operation.photos)
        
        if operation.type == .posClosing, let posAmounts = operation.posAmounts {
            _pos1Amount = State(initialValue: String(format: "%.2f", posAmounts.first ?? 0))
            _pos2Amount = State(initialValue: String(format: "%.2f", posAmounts.last ?? 0))
        }
    }
    
    var body: some View {
        Form {
            Section("Operation Type") {
                HStack {
                    Label(operation.type.rawValue, systemImage: operation.type.icon)
                    Spacer()
                    Text("(Cannot be changed)")
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
        .navigationTitle("Edit Operation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
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
    }
    
    private var amountSection: some View {
        Section("Amount") {
            HStack {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(.green)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
            }
        }
    }
    
    private var vehicleSection: some View {
        Section("Vehicle Information") {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Vehicle Plate", text: $vehiclePlate)
                    .textInputAutocapitalization(.characters)
            }
        }
    }
    
    private var posSection: some View {
        Section("POS Information (2 Terminals)") {
            VStack(spacing: 16) {
                HStack {
                    Text("POS 1 Amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.green)
                    TextField("0.00", text: $pos1Amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("CHF")
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                HStack {
                    Text("POS 2 Amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.blue)
                    TextField("0.00", text: $pos2Amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("CHF")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var photoSection: some View {
        Section("Photos") {
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
                        Text("From Gallery")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                saveOperation()
            } label: {
                if isUploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Changes")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(isUploading || !isValid)
        }
    }
    
    var isValid: Bool {
        if operation.type == .posClosing {
            guard let pos1 = Double(pos1Amount), pos1 >= 0,
                  let pos2 = Double(pos2Amount), pos2 >= 0 else { return false }
            return (pos1 + pos2) > 0
        } else {
            guard let amountValue = Double(amount), amountValue > 0 else { return false }
        }
        
        if operation.type == .fuelReceipt && vehiclePlate.isEmpty {
            return false
        }
        
        return true
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
                    ErrorManager.shared.showError(message: "Failed to upload photos. Please check your internet connection and try again.")
                    return
                } else {
                    // Some photos failed - continue with available photos
                    ErrorManager.shared.showError(message: "\(failedCount) out of \(totalCount) photos failed to upload. Operation will be saved with available photos.")
                }
            }
            
            let finalAmount: Double
            var posAmounts: [Double]?
            
            if operation.type == .posClosing {
                let amounts = [Double(pos1Amount) ?? 0, Double(pos2Amount) ?? 0]
                posAmounts = amounts
                finalAmount = amounts.reduce(0, +)
            } else {
                finalAmount = Double(amount) ?? 0
            }
            
            var updatedOperation = operation
            updatedOperation.amount = finalAmount
            updatedOperation.photos = newPhotoURLs
            updatedOperation.vehiclePlate = operation.type == .fuelReceipt ? vehiclePlate : nil
            updatedOperation.posAmounts = posAmounts
            updatedOperation.notes = notes
            
            viewModel.officeOperationGuncelle(updatedOperation) { success in
                isUploading = false
                if success {
                    HapticManager.shared.success()
                    dismiss()
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
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    
    var body: some View {
        Form {
            typeSection
            
            if selectedType != .posClosing {
                amountSection
            }
            
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
        .navigationTitle("Add Operation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
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
    }
    
    private var typeSection: some View {
        Section("Operation Type") {
            Picker("Type", selection: $selectedType) {
                ForEach(OfficeOperationType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var amountSection: some View {
        Section("Amount") {
            HStack {
                Image(systemName: "eurosign.circle.fill")
                    .foregroundColor(.green)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
            }
        }
    }
    
    private var vehicleSection: some View {
        Section("Vehicle Information") {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Vehicle Plate", text: $vehiclePlate)
                    .textInputAutocapitalization(.characters)
            }
        }
    }
    
    private var posSection: some View {
        Section("POS Information (2 Terminals)") {
            VStack(spacing: 16) {
                HStack {
                    Text("POS 1 Amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.green)
                    TextField("0.00", text: $pos1Amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("CHF")
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                HStack {
                    Text("POS 2 Amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.blue)
                    TextField("0.00", text: $pos2Amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("CHF")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var photoSection: some View {
        Section("Photos") {
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
                        Text("From Gallery")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                saveOperation()
            } label: {
                if isUploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Operation")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(isUploading || !isValid)
        }
    }
    
    var isValid: Bool {
        if selectedType == .posClosing {
            guard let pos1 = Double(pos1Amount), pos1 >= 0,
                  let pos2 = Double(pos2Amount), pos2 >= 0 else { return false }
            return (pos1 + pos2) > 0
        } else {
            guard let amountValue = Double(amount), amountValue > 0 else { return false }
        }
        
        if selectedType == .fuelReceipt && vehiclePlate.isEmpty {
            return false
        }
        
        return true
    }
    
    func saveOperation() {
        isUploading = true
        uploadedPhotoURLs = []
        
        let group = DispatchGroup()
        
        for image in selectedImages {
            group.enter()
            let path = "office_operations/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                if let url = url {
                    uploadedPhotoURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let finalAmount: Double
            var posAmounts: [Double]?
            
            if selectedType == .posClosing {
                let amounts = [Double(pos1Amount) ?? 0, Double(pos2Amount) ?? 0]
                posAmounts = amounts
                finalAmount = amounts.reduce(0, +)
            } else {
                finalAmount = Double(amount) ?? 0
            }
            
            let operation = OfficeOperation(
                type: selectedType,
                date: Date(),
                amount: finalAmount,
                photos: uploadedPhotoURLs,
                vehiclePlate: selectedType == .fuelReceipt ? vehiclePlate : nil,
                posCount: selectedType == .posClosing ? 2 : nil,
                posAmounts: posAmounts,
                notes: notes
            )
            
            viewModel.officeOperationEkle(operation)
            isUploading = false
            dismiss()
        }
    }
}

// MARK: - Office Operation Detail View
struct OfficeOperationDetailView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    let operation: OfficeOperation
    
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        List {
            Section("Details") {
                HStack {
                    Label("Type", systemImage: operation.type.icon)
                    Spacer()
                    Text(operation.type.rawValue)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Amount", systemImage: "eurosign.circle")
                    Spacer()
                    Text(String(format: "%.2f CHF", operation.amount))
                        .font(.headline)
                }
                
                HStack {
                    Label("Date", systemImage: "calendar")
                    Spacer()
                    Text(operation.date.formatted(date: .long, time: .shortened))
                        .foregroundColor(.secondary)
                }
                
                if let plate = operation.vehiclePlate {
                    HStack {
                        Label("Vehicle", systemImage: "car")
                        Spacer()
                        Text(plate)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let posCount = operation.posCount {
                    HStack {
                        Label("POS Count", systemImage: "creditcard")
                        Spacer()
                        Text("\(posCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let amounts = operation.posAmounts {
                        ForEach(amounts.indices, id: \.self) { index in
                            HStack {
                                Text("POS \(index + 1)")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.2f CHF", amounts[index]))
                                    .fontWeight(.semibold)
                            }
                            .padding(.leading)
                        }
                    }
                }
            }
            
            if !operation.notes.isEmpty {
                Section("Notes") {
                    Text(operation.notes)
                        .foregroundColor(.secondary)
                }
            }
            
            if !operation.photos.isEmpty {
                Section("Photos") {
                    ForEach(operation.photos, id: \.self) { photoURL in
                        NavigationLink(destination: FotografPreviewView(urlString: photoURL)) {
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
        .alert("Delete Operation", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.officeOperationSil(operation)
                HapticManager.shared.success()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this operation? This action cannot be undone.")
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
            Section("Report Period") {
                Picker("Period", selection: $reportPeriod) {
                    ForEach(ReportPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                
                if reportPeriod == .custom {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                }
            }
            
            Section("Report Summary") {
                HStack {
                    Text("Period")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(reportPeriod.rawValue)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Total Operations")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(filteredOperations.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Total Amount")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f CHF", totalAmount))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                if operationType == .posClosing {
                    let pos1Total = filteredOperations.compactMap { $0.posAmounts?.first }.reduce(0, +)
                    let pos2Total = filteredOperations.compactMap { $0.posAmounts?.last }.reduce(0, +)
                    
                    HStack {
                        Text("POS 1 Total")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f CHF", pos1Total))
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("POS 2 Total")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f CHF", pos2Total))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section("Export Options") {
                Button {
                    generatePDFReport()
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text("Generate PDF Report")
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
                        Text("Generate Excel Report")
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
                        Text("No operations found for this period")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .navigationTitle("Generate Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
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
                
                // Track analytics
                let operationsCount = viewModel.officeOperations.filter { $0.type == operationType }.count
                AnalyticsManager.shared.trackExport(type: "office_operations", format: "pdf", itemCount: operationsCount)
                
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
                
                // Track analytics
                let operationsCount = viewModel.officeOperations.filter { $0.type == operationType }.count
                AnalyticsManager.shared.trackExport(type: "office_operations", format: "csv", itemCount: operationsCount)
                
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
            kCGPDFContextAuthor: "Green Motion AG",
            kCGPDFContextCreator: "Green Motion Fleet Management"
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
            let companyName = "GREEN MOTION AG"
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            let companyAttrs: [NSAttributedString.Key: Any] = [
                .font: companyFont,
                .foregroundColor: SwissPDFHelper.black
            ]
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: companyAttrs)
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let subtitle = "ZÜRICH • SWITZERLAND"
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
            "\(String(format: "%.2f CHF", totalAmount))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 20
            
            // POS Details
            if operationType == .posClosing {
                let pos1Total = filteredOperations.compactMap { $0.posAmounts?.first }.reduce(0, +)
                let pos2Total = filteredOperations.compactMap { $0.posAmounts?.last }.reduce(0, +)
                
                "POS 1 Total:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
                "\(String(format: "%.2f CHF", pos1Total))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 20
                
                "POS 2 Total:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
                "\(String(format: "%.2f CHF", pos2Total))".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
                yPosition += 20
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
                "\(String(format: "%.2f CHF", operation.amount))".draw(at: CGPoint(x: 350, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                
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
            let footerText = "Green Motion AG • Zürich, Switzerland"
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
        csv += "GREEN MOTION AG - \(operationType.rawValue.uppercased()) REPORT\n"
        csv += "Zürich Switzerland\n"
        csv += "\n"
        csv += "Report Generated:,\(Date().formatted(date: .long, time: .shortened))\n"
        csv += "Period:,\(reportPeriod.rawValue)\n"
        csv += "\n"
        
        // Summary Section
        csv += "SUMMARY\n"
        csv += "Total Operations:,\(filteredOperations.count)\n"
        csv += "Total Amount:,\(String(format: "%.2f CHF", totalAmount))\n"
        
        if operationType == .posClosing {
            let pos1Total = filteredOperations.compactMap { $0.posAmounts?.first }.reduce(0, +)
            let pos2Total = filteredOperations.compactMap { $0.posAmounts?.last }.reduce(0, +)
            csv += "POS 1 Total:,\(String(format: "%.2f CHF", pos1Total))\n"
            csv += "POS 2 Total:,\(String(format: "%.2f CHF", pos2Total))\n"
        }
        csv += "\n"
        
        // Detailed Operations Table
        csv += "DETAILED OPERATIONS\n"
        csv += "Date,Time,Amount (CHF)"
        if operationType == .fuelReceipt || operationType == .washing {
            csv += ",Vehicle Plate"
        }
        if operationType == .posClosing {
            csv += ",POS 1 Amount,POS 2 Amount"
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
            
            if operationType == .posClosing, let posAmounts = operation.posAmounts {
                csv += ",\(String(format: "%.2f", posAmounts.first ?? 0)),\(String(format: "%.2f", posAmounts.last ?? 0))"
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
            Section("Summary") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f CHF", totalAmount))
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f CHF", averageAmount))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Entries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(operations.count)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            
            Section("Daily Breakdown") {
                ForEach(groupedByDate.sorted(by: { $0.key > $1.key }), id: \.key) { date, amount in
                    HStack {
                        Text(date)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f CHF", amount))
                            .font(.headline)
                    }
                }
            }
            
            if operationType == .posClosing {
                Section("POS Statistics") {
                    let totalPOS = operations.compactMap { $0.posCount }.reduce(0, +)
                    HStack {
                        Text("Total POS Processed")
                        Spacer()
                        Text("\(totalPOS)")
                            .fontWeight(.semibold)
                    }
                }
            }
            
            if operationType == .fuelReceipt {
                Section("Vehicle Breakdown") {
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
                            Text(String(format: "%.2f CHF", total))
                                .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
