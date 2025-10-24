import SwiftUI

struct ProtocolListView: View {
    @StateObject private var viewModel = ProtocolListViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var searchQuery = ""
    @State private var selectedStatus: String = "All"
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showStatistics = false
    @State private var showFilters = false
    
    private let statusOptions = ["All", "DRAFT", "PENDING", "COMPLETE", "OVERDUE", "CANCELLED"]
    
    var filteredProtocols: [Protocol] {
        var protocols = viewModel.protocols
        
        // Filter by search query
        if !searchQuery.isEmpty {
            protocols = protocols.filter { protocolItem in
                protocolItem.customerName.localizedCaseInsensitiveContains(searchQuery) ||
                protocolItem.vehiclePlate.localizedCaseInsensitiveContains(searchQuery) ||
                protocolItem.protocolName.localizedCaseInsensitiveContains(searchQuery) ||
                protocolItem.reservationNumber.localizedCaseInsensitiveContains(searchQuery) ||
                protocolItem.protocolId.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        // Filter by status
        if selectedStatus != "All" {
            protocols = protocols.filter { $0.status.uppercased() == selectedStatus.uppercased() }
        }
        
        // Filter by date range (more lenient - if date parsing fails, include the protocol)
        protocols = protocols.filter { protocolItem in
            guard let createdAt = protocolItem.createdAtFormatted else { 
                // If date parsing fails, include the protocol
                return true 
            }
            return createdAt >= startDate && createdAt <= endDate
        }
        
        return protocols
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchAndFilterSection
                Divider()
                
                if viewModel.isLoading {
                    loadingView
                } else if filteredProtocols.isEmpty {
                    emptyStateView
                } else {
                    protocolListSection
                }
            }
            .navigationTitle("Protocols")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showStatistics = true
                        } label: {
                            Image(systemName: "chart.bar.fill")
                        }
                        .disabled(viewModel.protocols.isEmpty)
                        
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showStatistics) {
                ProtocolStatisticsView(protocols: viewModel.protocols)
            }
            .sheet(isPresented: $showFilters) {
                ProtocolFiltersView(
                    selectedStatus: $selectedStatus,
                    startDate: $startDate,
                    endDate: $endDate,
                    statusOptions: statusOptions
                )
            }
        }
    }
    
    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.gray)
                TextField("Search protocols...", text: $searchQuery)
            }
            .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Status", selection: $selectedStatus) {
                    ForEach(statusOptions, id: \.self) { status in
                        Text(status == "All" ? "All" : ProtocolStatus(rawValue: status)?.displayName ?? status)
                            .tag(status)
                    }
                }
                .pickerStyle(.menu)
                
                Spacer()
                
                Button("Filters") {
                    showFilters = true
                }
                .font(.caption)
            }
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading protocols...")
                .foregroundColor(.secondary)
            
            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        viewModel.loadProtocols()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(Color.gray.opacity(0.5))
            
            Text("No Protocols Found")
                .font(.headline)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var protocolListSection: some View {
        List {
            ForEach(filteredProtocols) { protocolItem in
                NavigationLink(destination: ProtocolDetailView(protocol: protocolItem)) {
                    ProtocolRowView(protocol: protocolItem)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Protocol Row View
struct ProtocolRowView: View {
    let `protocol`: Protocol
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(`protocol`.protocolName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("ID: \(`protocol`.protocolId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Image(systemName: `protocol`.statusIcon)
                            .foregroundColor(Color(`protocol`.statusColor))
                        Text(`protocol`.status)
                            .font(.caption)
                            .foregroundColor(Color(`protocol`.statusColor))
                    }
                    
                    if let baseCost = `protocol`.baseCostDouble {
                        Text("CHF \(baseCost, specifier: "%.2f")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customer: \(`protocol`.customerName)")
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    Text("Vehicle: \(`protocol`.vehiclePlate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reservation: \(`protocol`.reservationNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let createdAt = `protocol`.createdAtFormatted {
                        Text(createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Protocol Detail View
struct ProtocolDetailView: View {
    let `protocol`: Protocol
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(`protocol`.protocolName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("ID: \(`protocol`.protocolId)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            HStack {
                                Image(systemName: `protocol`.statusIcon)
                                    .foregroundColor(Color(`protocol`.statusColor))
                                Text(`protocol`.status)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(`protocol`.statusColor))
                            }
                            
                            if let baseCost = `protocol`.baseCostDouble {
                                Text("CHF \(baseCost, specifier: "%.2f")")
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Customer Information
                DetailSection(title: "Customer Information") {
                    DetailRow(label: "Name", value: `protocol`.customerName)
                    DetailRow(label: "Vehicle Plate", value: `protocol`.vehiclePlate)
                    DetailRow(label: "Reservation", value: `protocol`.reservationNumber)
                }
                
                // Protocol Information
                DetailSection(title: "Protocol Information") {
                    DetailRow(label: "Type", value: `protocol`.protocolType)
                    DetailRow(label: "Template", value: `protocol`.templatePath)
                    DetailRow(label: "Base Cost", value: `protocol`.baseCost)
                }
                
                // Dates
                DetailSection(title: "Dates") {
                    DetailRow(label: "Check In", value: formatDate(`protocol`.checkInDate))
                    DetailRow(label: "Check Out", value: formatDate(`protocol`.checkOutDate))
                    DetailRow(label: "Created", value: formatDate(`protocol`.createdAt))
                    DetailRow(label: "Updated", value: formatDate(`protocol`.updatedAt))
                }
                
                // Field Values
                if let fieldValues = `protocol`.fieldValuesDict, !fieldValues.isEmpty {
                    DetailSection(title: "Field Values") {
                        ForEach(Array(fieldValues.keys.sorted()), id: \.self) { key in
                            DetailRow(label: key, value: fieldValues[key] ?? "")
                        }
                    }
                }
                
                // Audit Information
                DetailSection(title: "Audit Information") {
                    DetailRow(label: "Created By", value: `protocol`.createdBy)
                    DetailRow(label: "Updated By", value: `protocol`.updatedBy)
                }
            }
            .padding()
        }
        .navigationTitle("Protocol Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Detail Section
struct DetailSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 4) {
                content
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Protocol Statistics View
struct ProtocolStatisticsView: View {
    let protocols: [Protocol]
    @Environment(\.dismiss) var dismiss
    
    private var statistics: ProtocolStatistics {
        ProtocolStatistics(protocols: protocols)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Overview Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ProtocolStatCard(title: "Total Protocols", value: "\(statistics.totalProtocols)", color: .blue)
                        ProtocolStatCard(title: "Total Value", value: String(format: "CHF %.2f", statistics.totalBaseCost), color: .green)
                        ProtocolStatCard(title: "Average Value", value: String(format: "CHF %.2f", statistics.averageBaseCost), color: Color.orange)
                        ProtocolStatCard(title: "Completion Rate", value: statistics.totalProtocols > 0 ? "\(Int((Double(statistics.completedCount) / Double(statistics.totalProtocols)) * 100))%" : "0%", color: .purple)
                    }
                    
                    // Status Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status Breakdown")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            StatusRow(status: "Draft", count: statistics.draftCount, color: Color.gray)
                            StatusRow(status: "Pending", count: statistics.pendingCount, color: Color.orange)
                            StatusRow(status: "Complete", count: statistics.completedCount, color: .green)
                            StatusRow(status: "Overdue", count: statistics.overdueCount, color: .red)
                            StatusRow(status: "Cancelled", count: statistics.cancelledCount, color: .red)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Protocol Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Protocol Stat Card
struct ProtocolStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Status Row
struct StatusRow: View {
    let status: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(status)
                .font(.subheadline)
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Protocol Filters View
struct ProtocolFiltersView: View {
    @Binding var selectedStatus: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let statusOptions: [String]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Status Filter") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(statusOptions, id: \.self) { status in
                            Text(status == "All" ? "All" : ProtocolStatus(rawValue: status)?.displayName ?? status)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Date Range") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedStatus = "All"
                        startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                        endDate = Date()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProtocolListView()
}
