import SwiftUI

struct OfficeOperationsMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedOperation: OfficeOperationType?
    @State private var showAddOperation = false
    @State private var showAllOperationsReport = false
    @State private var showProtocols = false
    
    // Decimal formatter
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }
    
    func formatAmount(_ amount: Double) -> String {
        if let formatted = numberFormatter.string(from: NSNumber(value: amount)) {
            return "\(formatted) CHF"
        }
        return String(format: "%.2f CHF", amount)
    }
    
    var body: some View {
        NavigationStack {
            contentView
        }
        .sheet(isPresented: $showAddOperation) {
            NavigationView {
                AddOfficeOperationView()
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showAllOperationsReport) {
            NavigationView {
                AllOfficeOperationsReportView()
                    .environmentObject(viewModel)
                    .navigationTitle("Overall Report")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAllOperationsReport = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProtocols) {
            ProtocolListView()
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                operationCardsGrid
                
                Divider()
                    .padding(.vertical)
                
                OfficeStatisticsSummaryView()
                    .environmentObject(viewModel)
                    .padding()
                    .allowsHitTesting(false) // ÇÖZÜM: Tıklamayı engelle
                
                generateReportButton
                    .padding(.top, 8) // ÇÖZÜM: Araya boşluk ekle
            }
        }
        .navigationTitle("Office Operations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                addButton
            }
        }
        .navigationDestination(item: $selectedOperation) { opType in
            OfficeOperationListView(operationType: opType)
                .environmentObject(viewModel)
        }
    }
    
    private var operationCardsGrid: some View {
        let types: [OfficeOperationType] = [.creditCard, .posClosing, .fuelReceipt, .washing]
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            ForEach(types, id: \.rawValue) { opType in
                let count = viewModel.officeOperations.filter { $0.type == opType }.count
                let totalAmount = viewModel.officeOperations.filter { $0.type == opType }.reduce(0) { $0 + $1.amount }
                
                Button {
                    selectedOperation = opType
                    HapticManager.shared.medium()
                } label: {
                    BigOfficeOperationCard(
                        type: opType,
                        count: count,
                        totalAmount: totalAmount
                    )
                }
                .buttonStyle(CardButtonStyle())
            }
            
            // Protocols Card
            Button {
                showProtocols = true
                HapticManager.shared.medium()
            } label: {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Protocols")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("View protocols")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .frame(height: 120)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
            }
            .buttonStyle(CardButtonStyle())
        }
        .padding()
    }
    
    private var generateReportButton: some View {
        Button {
            showAllOperationsReport = true
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                Text("Generate Overall Report")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back")
            }
            .foregroundColor(.blue)
        }
    }
    
    private var addButton: some View {
        Button {
            showAddOperation = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }
}

struct BigOfficeOperationCard: View {
    let type: OfficeOperationType
    let count: Int
    let totalAmount: Double
    @Environment(\.colorScheme) var colorScheme
    
    var color: Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? color.opacity(0.2) : color.opacity(0.1)
    }
    
    var textColor: Color {
        colorScheme == .dark ? .white : .primary
    }
    
    var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .secondary
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: type.icon)
                .font(.system(size: 40))
                .foregroundColor(color)
            
            Text(String(format: "%.2f CHF", totalAmount))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            
            Text(type.rawValue)
                .font(.caption)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text("\(count) entries")
                .font(.caption2)
                .foregroundColor(secondaryTextColor)
            
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption)
                .foregroundColor(color.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(color.opacity(colorScheme == .dark ? 0.4 : 0.3), lineWidth: 2)
                )
        )
        .shadow(color: color.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Office Statistics Summary View
struct OfficeStatisticsSummaryView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var totalAmount: Double {
        viewModel.officeOperations.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Statistics")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    QuickStatCard(
                        title: "Credit Card",
                        amount: viewModel.totalCreditCardAmount,
                        color: .blue
                    )
                    
                    QuickStatCard(
                        title: "POS",
                        amount: viewModel.totalPOSAmount,
                        color: .green
                    )
                }
                
                HStack(spacing: 12) {
                    QuickStatCard(
                        title: "Fuel",
                        amount: viewModel.totalFuelAmount,
                        color: .orange
                    )
                    
                    QuickStatCard(
                        title: "Washing",
                        amount: viewModel.totalWashingAmount,
                        color: .cyan
                    )
                }
            }
        }
    }
}

struct QuickStatCard: View {
    let title: String
    let amount: Double
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f CHF", amount))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
        .cornerRadius(12)
    }
    // MARK: - Office Operation List View
    struct OfficeOperationListView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.colorScheme) var colorScheme
        let operationType: OfficeOperationType
        
        @State private var searchQuery = ""
        @State private var dateFilter: DateFilterType = .weekly
        @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        @State private var customEndDate = Date()
        @State private var showCustomDatePicker = false
        @State private var showStatistics = false
        @State private var showReportGenerator = false
        @State private var editingOperation: OfficeOperation? // ÇÖZÜM: Edit state'i
        
        enum DateFilterType: String, CaseIterable {
            case daily = "Daily"
            case weekly = "Weekly"
            case monthly = "Monthly"
            case custom = "Custom"
        }
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch dateFilter {
            case .daily:
                let start = calendar.startOfDay(for: now)
                return (start, now)
            case .weekly:
                let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return (start, now)
            case .monthly:
                let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return (start, now)
            case .custom:
                return (customStartDate, customEndDate)
            }
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
        
        var plateSuggestions: [String] {
            if searchQuery.isEmpty { return [] }
            return viewModel.araclar
                .map { $0.plakaFormatli }
                .filter { $0.localizedCaseInsensitiveContains(searchQuery) }
                .prefix(5)
                .map { String($0) }
        }
        
        var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Search...", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                        
                        if !plateSuggestions.isEmpty && (operationType == .fuelReceipt || operationType == .washing) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(plateSuggestions, id: \.self) { plate in
                                    Button {
                                        searchQuery = plate
                                    } label: {
                                        Text(plate)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider()
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                    }
                    
                    Picker("Date Filter", selection: $dateFilter) {
                        ForEach(DateFilterType.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dateFilter) { newValue in
                        if newValue == .custom {
                            showCustomDatePicker = true
                        }
                    }
                }
                .padding()
                
                Divider()
                
                if filteredOperations.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Operations Found")
                            .font(.headline)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Total Amount")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f CHF", totalAmount))
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(getColor())
                                
                                VStack(spacing: 12) {
                                    Button {
                                        showStatistics = true
                                        HapticManager.shared.medium()
                                    } label: {
                                        Label("Statistics", systemImage: "chart.bar.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .background(getColor())
                                            .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        showReportGenerator = true
                                        HapticManager.shared.medium()
                                    } label: {
                                        Label("Generate Report", systemImage: "doc.text.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)  // Height ekle
                                            .background(Color.blue)
                                            .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)  // ÇÖZÜM: Plain style ekle
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
                                        editingOperation = operation  // ÇÖZÜM: Edit çalışıyor
                                        HapticManager.shared.medium()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                    
                                    Button {
                                        deleteOperation(operation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                            .onDelete(perform: deleteOperations)
                        }
                    }
                }
            }
            .navigationTitle(operationType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showCustomDatePicker) {
                NavigationView {
                    Form {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Date Range")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showCustomDatePicker = false }
                        }
                    }
                }
            }
        .sheet(item: $editingOperation) { operation in
            NavigationView {
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
        }
    }
        
        func deleteOperations(at offsets: IndexSet) {
            for index in offsets {
                let operation = filteredOperations[index]
                viewModel.officeOperationSil(operation)
            }
        }
        
        func deleteOperation(_ operation: OfficeOperation) {
            viewModel.officeOperationSil(operation)
        }
        
        func getColor() -> Color {
            switch operationType.color {
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "cyan": return .cyan
            default: return colorScheme == .dark ? .white : .gray
            }
        }
    }

    struct OfficeOperationRow: View {
        let operation: OfficeOperation
        @Environment(\.colorScheme) var colorScheme
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: operation.type.icon)
                    .font(.title3)
                    .foregroundColor(getColor())
                    .frame(width: 30)
                
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
        
        func getColor() -> Color {
            switch operation.type.color {
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "cyan": return .cyan
            default: return colorScheme == .dark ? .white : .gray
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
        @State private var uploadedPhotoURLs: [String] = []
        @State private var isUploading = false
        
        var plateSuggestions: [String] {
            if vehiclePlate.isEmpty { return [] }
            return viewModel.araclar
                .map { $0.plakaFormatli }
                .filter { $0.localizedCaseInsensitiveContains(vehiclePlate) }
                .prefix(5)
                .map { String($0) }
        }
        
        var body: some View {
            Form {
                Section("Operation Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(OfficeOperationType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if selectedType != .posClosing {
                    Section("Amount") {
                        HStack {
                            Image(systemName: "eurosign.circle.fill")
                                .foregroundColor(.green)
                            TextField("Amount", text: $amount)
                                .keyboardType(.decimalPad)
                            Text("CHF")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if selectedType == .fuelReceipt || selectedType == .washing {
                    Section("Vehicle Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "car.fill")
                                    .foregroundColor(.blue)
                                TextField("Vehicle Plate", text: $vehiclePlate)
                                    .textInputAutocapitalization(.characters)
                            }
                            
                            if !plateSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(plateSuggestions, id: \.self) { plate in
                                        if let vehicle = viewModel.araclar.first(where: { $0.plakaFormatli == plate }) {
                                            Button {
                                                vehiclePlate = plate
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(plate)
                                                            .font(.subheadline)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.primary)
                                                        Text("\(vehicle.marka) \(vehicle.model)")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                            }
                                            Divider()
                                        }
                                    }
                                }
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            
                            if !vehiclePlate.isEmpty, let vehicle = viewModel.araclar.first(where: { $0.plakaFormatli == vehiclePlate }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Selected Vehicle")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(vehicle.marka) \(vehicle.model)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                if selectedType == .posClosing {
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
                    
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                            .foregroundColor(.blue)
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
                
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
        }
        
        var isValid: Bool {
            if selectedType == .posClosing {
                guard let pos1 = Double(pos1Amount), pos1 >= 0,
                      let pos2 = Double(pos2Amount), pos2 >= 0 else { return false }
                return (pos1 + pos2) > 0
            } else {
                guard let amountValue = Double(amount), amountValue > 0 else { return false }
            }
            
            if (selectedType == .fuelReceipt || selectedType == .washing) && vehiclePlate.isEmpty {
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
                    vehiclePlate: (selectedType == .fuelReceipt || selectedType == .washing) ? vehiclePlate : nil,
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
        @Environment(\.colorScheme) var colorScheme
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
                EditOfficeOperationView(operation: operation)
                    .environmentObject(viewModel)
            }
            .onAppear {
                print("🔍 OfficeOperationDetailView appeared for operation: \(operation.id)")
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

    // MARK: - Edit Office Operation View
    struct EditOfficeOperationView: View {
        @EnvironmentObject var viewModel: AracViewModel
        @Environment(\.dismiss) var dismiss
        let operation: OfficeOperation
        
        @State private var amount: String
        @State private var vehiclePlate: String
        @State private var notes: String
        @State private var posCount: String
        @State private var isSaving = false
        
        init(operation: OfficeOperation) {
            self.operation = operation
            _amount = State(initialValue: String(format: "%.2f", operation.amount))
            _vehiclePlate = State(initialValue: operation.vehiclePlate ?? "")
            _notes = State(initialValue: operation.notes)
            _posCount = State(initialValue: operation.posCount.map(String.init) ?? "")
        }
        
        var body: some View {
            Form {
                    Section("Operation Details") {
                        HStack {
                            Label("Type", systemImage: operation.type.icon)
                            Spacer()
                            Text(operation.type.rawValue)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Date", systemImage: "calendar")
                            Spacer()
                            Text(operation.date.formatted(date: .long, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("Amount") {
                        HStack {
                            Text("Amount (CHF)")
                            Spacer()
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    Section("Vehicle") {
                        TextField("Vehicle Plate (Optional)", text: $vehiclePlate)
                    }
                    
                    Section("POS Count") {
                        TextField("POS Count (Optional)", text: $posCount)
                            .keyboardType(.numberPad)
                    }
                    
                    Section("Notes") {
                        TextField("Notes (Optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Edit Operation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveOperation()
                        }
                        .disabled(isSaving)
                    }
                }
        }
        
        private func saveOperation() {
            guard let amountValue = Double(amount) else { return }
            
            isSaving = true
            
            var updatedOperation = operation
            updatedOperation.amount = amountValue
            updatedOperation.vehiclePlate = vehiclePlate.isEmpty ? nil : vehiclePlate
            updatedOperation.notes = notes
            updatedOperation.posCount = posCount.isEmpty ? nil : Int(posCount)
            
            Task {
                await viewModel.updateOfficeOperation(updatedOperation)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
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
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).pdf")
                
                do {
                    try pdfData.write(to: tempURL)
                    shareURL = tempURL
                    showShareSheet = true
                    isGenerating = false
                } catch {
                    print("Error writing PDF: \(error)")
                    isGenerating = false
                }
            }
        }
        
        func generateExcelReport() {
            isGenerating = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let csvData = createCSVData()
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("OfficeReport_\(Date().timeIntervalSince1970).csv")
                
                do {
                    try csvData.write(to: tempURL)
                    shareURL = tempURL
                    showShareSheet = true
                    isGenerating = false
                } catch {
                    print("Error writing CSV: \(error)")
                    isGenerating = false
                }
            }
        }
        
        func createPDFData() -> Data {
            let pdfMetadata = [
                kCGPDFContextTitle: "\(operationType.rawValue) Report",
                kCGPDFContextAuthor: "Green Motion AG"
            ]
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetadata as [String: Any]
            
            let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
            
            return renderer.pdfData { context in
                context.beginPage()
                
                let titleFont = UIFont.boldSystemFont(ofSize: 24)
                let bodyFont = UIFont.systemFont(ofSize: 12)
                
                var yPosition: CGFloat = 50
                
                // Title
                let title = "\(operationType.rawValue) Report"
                title.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: titleFont])
                yPosition += 40
                
                // Period
                "Period: \(reportPeriod.rawValue)".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 30
                
                // Summary
                "Total Operations: \(filteredOperations.count)".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 20
                "Total Amount: \(String(format: "%.2f CHF", totalAmount))".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 30
                
                // Operations list
                for operation in filteredOperations.prefix(30) {
                    let dateStr = operation.date.formatted(date: .abbreviated, time: .omitted)
                    let amountStr = String(format: "%.2f CHF", operation.amount)
                    let line = "\(dateStr) - \(amountStr)"
                    line.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
                    yPosition += 20
                    
                    if yPosition > 750 { break }
                }
            }
        }
        
        func createCSVData() -> Data {
            var csv = "Date,Amount,Type,Notes\n"
            
            for operation in filteredOperations {
                let dateStr = operation.date.formatted(date: .numeric, time: .omitted)
                let amountStr = String(format: "%.2f", operation.amount)
                let notes = operation.notes.replacingOccurrences(of: ",", with: ";")
                csv += "\(dateStr),\(amountStr),\(operationType.rawValue),\(notes)\n"
            }
            
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
                
                if operationType == .fuelReceipt || operationType == .washing {
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
}

// MARK: - All Office Operations Report View
struct AllOfficeOperationsReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var reportPeriod: ReportPeriod = .weekly
    @State private var selectedOperationType: OfficeOperationType? = nil  // nil = All Operations
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
        
        var ops = viewModel.officeOperations.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }
        
        // Filter by operation type if selected
        if let selectedType = selectedOperationType {
            ops = ops.filter { $0.type == selectedType }
        }
        
        return ops
    }
    
    var totalAmount: Double {
        filteredOperations.reduce(0) { $0 + $1.amount }
    }
    
    var operationsByType: [(type: OfficeOperationType, amount: Double, count: Int)] {
        var result: [(type: OfficeOperationType, amount: Double, count: Int)] = []
        
        for opType in OfficeOperationType.allCases {
            let ops = filteredOperations.filter { $0.type == opType }
            let amount = ops.reduce(0) { $0 + $1.amount }
            if !ops.isEmpty {
                result.append((type: opType, amount: amount, count: ops.count))
            }
        }
        
        return result.sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        List {
            Section("Operation Type") {
                Picker("Select Type", selection: $selectedOperationType) {
                    Text("All Operations").tag(nil as OfficeOperationType?)
                    ForEach(OfficeOperationType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.rawValue)
                        }.tag(type as OfficeOperationType?)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedType = selectedOperationType {
                    HStack {
                        Image(systemName: selectedType.icon)
                            .foregroundColor(getColor(for: selectedType))
                        Text("Filtering: \(selectedType.rawValue)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
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
            
            Section("Overall Summary") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Period")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(reportPeriod.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Operations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(filteredOperations.count)")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f CHF", totalAmount))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    Spacer()
                }
            }
            
            if !operationsByType.isEmpty {
                Section("Breakdown by Type") {
                    ForEach(operationsByType, id: \.type) { item in
                        HStack {
                            Image(systemName: item.type.icon)
                                .foregroundColor(getColor(for: item.type))
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.type.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(item.count) entries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.2f CHF", item.amount))
                                .font(.headline)
                                .foregroundColor(getColor(for: item.type))
                        }
                        .padding(.vertical, 4)
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
        .navigationTitle("Generate Overall Report")
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
    
    func getColor(for type: OfficeOperationType) -> Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    func generatePDFReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let pdfData = createPDFData()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("OverallOfficeReport_\(Date().timeIntervalSince1970).pdf")
            
            do {
                try pdfData.write(to: tempURL)
                shareURL = tempURL
                showShareSheet = true
                isGenerating = false
            } catch {
                print("Error writing PDF: \(error)")
                isGenerating = false
            }
        }
    }
    
    func generateExcelReport() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let csvData = createCSVData()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("OverallOfficeReport_\(Date().timeIntervalSince1970).csv")
            
            do {
                try csvData.write(to: tempURL)
                shareURL = tempURL
                showShareSheet = true
                isGenerating = false
            } catch {
                print("Error writing CSV: \(error)")
                isGenerating = false
            }
        }
    }
    
    func createPDFData() -> Data {
        let pdfMetadata = [
            kCGPDFContextTitle: selectedOperationType?.rawValue ?? "Office Operations Report",
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
            
            // MARK: - HEADER SECTION (Green Banner)
            ctx.setFillColor(UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: pageRect.width, height: 100))
            
            // Company Logo/Name
            let companyName = "GREEN MOTION AG"
            let companyFont = UIFont.systemFont(ofSize: 28, weight: .black)
            let companyAttrs: [NSAttributedString.Key: Any] = [
                .font: companyFont,
                .foregroundColor: UIColor.white
            ]
            companyName.draw(at: CGPoint(x: 50, y: 35), withAttributes: companyAttrs)
            
            // Subtitle
            let subtitle = "ZÜRICH • SWITZERLAND"
            let subtitleFont = UIFont.systemFont(ofSize: 10, weight: .medium)
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            subtitle.draw(at: CGPoint(x: 50, y: 68), withAttributes: subtitleAttrs)
            
            var yPosition: CGFloat = 130
            
            // MARK: - TITLE
            let reportTitle = selectedOperationType != nil ? "\(selectedOperationType!.rawValue) Report" : "Office Operations Report"
            let titleFont = UIFont.boldSystemFont(ofSize: 22)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.darkGray
            ]
            reportTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: titleAttrs)
            yPosition += 40
            
            // MARK: - INFO BOX
            ctx.setFillColor(UIColor(white: 0.95, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 40, y: yPosition, width: pageRect.width - 80, height: 100))
            ctx.setStrokeColor(UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.5).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: 40, y: yPosition, width: pageRect.width - 80, height: 100))
            
            let infoFont = UIFont.systemFont(ofSize: 11)
            let labelFont = UIFont.boldSystemFont(ofSize: 11)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            
            // Report Date
            let reportDateLabel = "Report Generated:"
            let reportDateValue = dateFormatter.string(from: Date())
            reportDateLabel.draw(at: CGPoint(x: 55, y: yPosition + 15), withAttributes: [.font: labelFont, .foregroundColor: UIColor.darkGray])
            reportDateValue.draw(at: CGPoint(x: 180, y: yPosition + 15), withAttributes: [.font: infoFont, .foregroundColor: UIColor.black])
            
            // Period
            let periodLabel = "Period:"
            let periodValue = reportPeriod.rawValue
            periodLabel.draw(at: CGPoint(x: 55, y: yPosition + 35), withAttributes: [.font: labelFont, .foregroundColor: UIColor.darkGray])
            periodValue.draw(at: CGPoint(x: 180, y: yPosition + 35), withAttributes: [.font: infoFont, .foregroundColor: UIColor.black])
            
            // Date Range
            if reportPeriod == .custom {
                let rangeLabel = "Date Range:"
                let rangeValue = "\(dateFormatter.string(from: customStartDate)) - \(dateFormatter.string(from: customEndDate))"
                rangeLabel.draw(at: CGPoint(x: 55, y: yPosition + 55), withAttributes: [.font: labelFont, .foregroundColor: UIColor.darkGray])
                rangeValue.draw(at: CGPoint(x: 180, y: yPosition + 55), withAttributes: [.font: infoFont, .foregroundColor: UIColor.black])
            }
            
            // Operation Type
            if let selectedType = selectedOperationType {
                let typeLabel = "Operation Type:"
                let typeValue = selectedType.rawValue
                typeLabel.draw(at: CGPoint(x: 55, y: yPosition + 75), withAttributes: [.font: labelFont, .foregroundColor: UIColor.darkGray])
                typeValue.draw(at: CGPoint(x: 180, y: yPosition + 75), withAttributes: [.font: infoFont, .foregroundColor: UIColor.blue])
            }
            
            yPosition += 120
            
            // MARK: - SUMMARY SECTION
            let summaryTitle = "SUMMARY"
            let sectionFont = UIFont.boldSystemFont(ofSize: 14)
            summaryTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)])
            yPosition += 25
            
            // Summary Box
            ctx.setFillColor(UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.1).cgColor)
            ctx.fill(CGRect(x: 40, y: yPosition, width: pageRect.width - 80, height: 70))
            
            let summaryFont = UIFont.systemFont(ofSize: 12)
            let summaryBoldFont = UIFont.boldSystemFont(ofSize: 16)
            
            "Total Operations:".draw(at: CGPoint(x: 55, y: yPosition + 15), withAttributes: [.font: summaryFont, .foregroundColor: UIColor.darkGray])
            "\(filteredOperations.count)".draw(at: CGPoint(x: 200, y: yPosition + 12), withAttributes: [.font: summaryBoldFont, .foregroundColor: UIColor.black])
            
            "Total Amount:".draw(at: CGPoint(x: 55, y: yPosition + 45), withAttributes: [.font: summaryFont, .foregroundColor: UIColor.darkGray])
            "\(String(format: "%.2f CHF", totalAmount))".draw(at: CGPoint(x: 200, y: yPosition + 42), withAttributes: [.font: summaryBoldFont, .foregroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)])
            
            yPosition += 90
            
            // MARK: - BREAKDOWN SECTION
            if !operationsByType.isEmpty {
                let breakdownTitle = "BREAKDOWN BY TYPE"
                breakdownTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: sectionFont, .foregroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)])
                yPosition += 30
                
                // Table Header
                ctx.setFillColor(UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.2).cgColor)
                ctx.fill(CGRect(x: 40, y: yPosition, width: pageRect.width - 80, height: 25))
                
                let headerFont = UIFont.boldSystemFont(ofSize: 11)
                "TYPE".draw(at: CGPoint(x: 50, y: yPosition + 7), withAttributes: [.font: headerFont])
                "ENTRIES".draw(at: CGPoint(x: 300, y: yPosition + 7), withAttributes: [.font: headerFont])
                "AMOUNT".draw(at: CGPoint(x: 430, y: yPosition + 7), withAttributes: [.font: headerFont])
                yPosition += 30
                
                let rowFont = UIFont.systemFont(ofSize: 11)
                
                for (index, item) in operationsByType.prefix(15).enumerated() {
                    if yPosition > 750 {
                        context.beginPage()
                        yPosition = 50
                    }
                    
                    // Alternating row colors
                    if index % 2 == 0 {
                        ctx.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
                        ctx.fill(CGRect(x: 40, y: yPosition - 5, width: pageRect.width - 80, height: 22))
                    }
                    
                    item.type.rawValue.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: rowFont])
                    "\(item.count)".draw(at: CGPoint(x: 300, y: yPosition), withAttributes: [.font: rowFont])
                    "\(String(format: "%.2f CHF", item.amount))".draw(at: CGPoint(x: 430, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)])
                    
                    yPosition += 22
                }
            }
            
            // MARK: - FOOTER
            let footerY = pageRect.height - 40
            ctx.setFillColor(UIColor(white: 0.9, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: footerY, width: pageRect.width, height: 40))
            
            let footerFont = UIFont.systemFont(ofSize: 8)
            let footerText = "Green Motion AG • Zürich, Switzerland • This is a computer-generated report"
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.darkGray
            ]
            footerText.draw(at: CGPoint(x: 50, y: footerY + 15), withAttributes: footerAttrs)
            
            let pageNumber = "Page 1"
            pageNumber.draw(at: CGPoint(x: pageRect.width - 100, y: footerY + 15), withAttributes: footerAttrs)
        }
    }
    
    func createCSVData() -> Data {
        var csv = ""
        
        // Header Section
        csv += "GREEN MOTION AG - OFFICE OPERATIONS REPORT\n"
        csv += "Zürich Switzerland\n"
        csv += "\n"
        csv += "Report Generated:,\(Date().formatted(date: .long, time: .shortened))\n"
        csv += "Period:,\(reportPeriod.rawValue)\n"
        if let selectedType = selectedOperationType {
            csv += "Operation Type:,\(selectedType.rawValue)\n"
        } else {
            csv += "Operation Type:,All Operations\n"
        }
        csv += "\n"
        
        // Summary Section
        csv += "SUMMARY\n"
        csv += "Total Operations:,\(filteredOperations.count)\n"
        csv += "Total Amount:,\(String(format: "%.2f CHF", totalAmount))\n"
        csv += "\n"
        
        // Breakdown Section
        if !operationsByType.isEmpty {
            csv += "BREAKDOWN BY TYPE\n"
            csv += "Type,Entries,Amount (CHF)\n"
            for item in operationsByType {
                csv += "\(item.type.rawValue),\(item.count),\(String(format: "%.2f", item.amount))\n"
            }
            csv += "\n"
        }
        
        // Detailed Operations Table
        csv += "DETAILED OPERATIONS\n"
        csv += "Date,Time,Type,Amount (CHF),Vehicle Plate,POS Count,Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        for operation in filteredOperations.sorted(by: { $0.date > $1.date }) {
            let dateStr = dateFormatter.string(from: operation.date)
            let timeStr = timeFormatter.string(from: operation.date)
            let amountStr = String(format: "%.2f", operation.amount)
            let plate = operation.vehiclePlate ?? "-"
            let posCount = operation.posCount != nil ? "\(operation.posCount!)" : "-"
            let notes = operation.notes.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
            
            csv += "\(dateStr),\(timeStr),\(operation.type.rawValue),\(amountStr),\(plate),\(posCount),\(notes)\n"
        }
        
        csv += "\n"
        csv += "End of Report\n"
        csv += "Generated by Green Motion Fleet Management System\n"
        
        return csv.data(using: .utf8) ?? Data()
    }
}

// MARK: - Protocol Card
struct ProtocolCard: View {
    @StateObject private var viewModel = ProtocolListViewModel()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Protocols")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(viewModel.totalProtocols) protocols")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                if viewModel.totalBaseCost > 0 {
                    Text("€\(viewModel.totalBaseCost, specifier: "%.2f") total")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(height: 120)
        .background(
            LinearGradient(
                colors: [Color.purple, Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}

// MARK: - Card Button Style
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
