import SwiftUI

struct OfficeReturnMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date()
    @State private var showAddReturn = false
    @State private var showEditReturn: OfficeReturn?
    @State private var returnToDelete: OfficeReturn?
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""
    
    // Get month range for selected month
    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }
    
    private var filteredReturns: [OfficeReturn] {
        let range = monthRange
        var returns = viewModel.officeReturns.filter { returnOp in
            returnOp.date >= range.start && returnOp.date <= range.end
        }
        
        // Search filter
        if !searchText.isEmpty {
            returns = returns.filter { returnOp in
                returnOp.reason.rawValue.localizedCaseInsensitiveContains(searchText) ||
                String(format: "%.2f", returnOp.amount).contains(searchText)
            }
        }
        
        return returns.sorted { $0.date > $1.date }
    }
    
    private var totalAmount: Double {
        filteredReturns.reduce(0) { $0 + $1.amount }
    }
    
    private var returnsByReason: [(reason: OfficeReturnReason, amount: Double, count: Int)] {
        var result: [(reason: OfficeReturnReason, amount: Double, count: Int)] = []
        
        for reason in OfficeReturnReason.allCases {
            let returns = filteredReturns.filter { $0.reason == reason }
            let amount = returns.reduce(0) { $0 + $1.amount }
            if !returns.isEmpty {
                result.append((reason: reason, amount: amount, count: returns.count))
            }
        }
        
        return result.sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            contentView
        }
        .sheet(isPresented: $showAddReturn) {
            NavigationView {
                OfficeReturnEkleView()
                    .environmentObject(viewModel)
            }
        }
        .sheet(item: $showEditReturn) { returnOp in
            NavigationView {
                OfficeReturnEkleView(editingReturn: returnOp)
                    .environmentObject(viewModel)
            }
        }
        .alert("Delete Return".localized, isPresented: $showDeleteConfirmation) {
            Button("Cancel".localized, role: .cancel) {
                returnToDelete = nil
            }
            Button("Delete".localized, role: .destructive) {
                if let returnOp = returnToDelete {
                    viewModel.officeReturnSil(returnOp)
                }
                returnToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this return? This action cannot be undone.".localized)
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Returns List with embedded summary
            returnsListSection
        }
        .navigationTitle("Customer Returns".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                addButton
            }
        }
    }
    
    private var summarySection: some View {
        VStack(spacing: 12) {
            // Total Amount
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Amount".localized)
                        .font(AppTheme.captionFont)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f CHF", totalAmount))
                        .font(AppTheme.titleFont)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
            
            // Count
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Returns".localized)
                        .font(AppTheme.captionFont)
                        .foregroundColor(.secondary)
                    Text("\(filteredReturns.count)")
                        .font(AppTheme.title3Font)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
    
    private var returnsListSection: some View {
        List {
            // Summary Section
            Section {
                summarySection
            }
            
            // Returns List
            if filteredReturns.isEmpty {
                Section {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filteredReturns) { returnOp in
                        NavigationLink(destination: OfficeReturnDetailView(returnOp: returnOp)
                            .environmentObject(viewModel)) {
                            ReturnRowView(returnOp: returnOp) {
                                // This is for swipe action edit
                                showEditReturn = returnOp
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                HapticManager.shared.medium()
                                returnToDelete = returnOp
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                            
                            Button {
                                HapticManager.shared.light()
                                showEditReturn = returnOp
                            } label: {
                                Label("Edit".localized, systemImage: "pencil")
                            }
                            .tint(AppTheme.primary)
                        }
                    }
                } header: {
                    Text(String(format: "Returns (%d)".localized, filteredReturns.count))
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search returns...".localized)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "return")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Returns".localized)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No customer returns found for the selected month".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back".localized)
            }
            .foregroundColor(.blue)
        }
    }
    
    private var addButton: some View {
        Button {
            showAddReturn = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }
    
    private func getColor(for reason: OfficeReturnReason) -> Color {
        switch reason.color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "gray": return .gray
        default: return .indigo
        }
    }
}

struct ReturnRowView: View {
    let returnOp: OfficeReturn
    let onTap: () -> Void
    @EnvironmentObject var viewModel: AracViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(getColor().opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: returnOp.reason.icon)
                    .font(.system(size: 20))
                    .foregroundColor(getColor())
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(returnOp.reason.rawValue)
                    .font(AppTheme.headlineFont)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(String(format: "%.2f CHF", returnOp.amount))
                        .font(AppTheme.bodyFont)
                        .foregroundColor(getColor())
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(returnOp.date))
                        .font(AppTheme.captionFont)
                        .foregroundColor(.secondary)
                }
                
                // Photo indicator
                if !returnOp.photos.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                        Text("\(returnOp.photos.count)")
                            .font(AppTheme.caption2Font)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    private func getColor() -> Color {
        switch returnOp.reason.color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "gray": return .gray
        default: return .indigo
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

