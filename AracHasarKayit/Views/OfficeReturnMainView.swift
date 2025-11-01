import SwiftUI

struct OfficeReturnMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var selectedMonth: Date = Date()
    @State private var showAddReturn = false
    @State private var selectedReturn: OfficeReturn?
    @State private var showEditReturn: OfficeReturn?
    
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
        return viewModel.officeReturns.filter { returnOp in
            returnOp.date >= range.start && returnOp.date <= range.end
        }
        .sorted { $0.date > $1.date }
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
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                summarySection
                
                Divider()
                    .padding(.vertical)
                
                // Returns List
                returnsListSection
            }
            .padding()
        }
        .navigationTitle("Customer Returns")
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
        VStack(spacing: 16) {
            // Total Amount Card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f CHF", totalAmount))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.indigo)
                }
                
                Spacer()
                
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.indigo)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.indigo.opacity(0.1))
            )
            
            // Count Card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Returns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(filteredReturns.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.indigo.opacity(0.1))
            )
            
            // Breakdown by Reason
            if !returnsByReason.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Breakdown by Reason")
                        .font(.headline)
                    
                    ForEach(returnsByReason, id: \.reason) { item in
                        HStack {
                            Image(systemName: item.reason.icon)
                                .foregroundColor(getColor(for: item.reason))
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.reason.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(item.count) returns")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.2f CHF", item.amount))
                                .font(.headline)
                                .foregroundColor(getColor(for: item.reason))
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(getColor(for: item.reason).opacity(0.1))
                        )
                    }
                }
            }
        }
    }
    
    private var returnsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Returns List")
                .font(.headline)
                .padding(.horizontal)
            
            if filteredReturns.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredReturns) { returnOp in
                    ReturnRowView(returnOp: returnOp) {
                        showEditReturn = returnOp
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "return")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Returns")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No customer returns found for the selected month")
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
                Text("Back")
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
    @State private var showDeleteConfirmation = false
    @State private var selectedPhotoForPreview: String?
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 16) {
                // Photo preview or Icon
                if let firstPhotoURL = returnOp.photos.first, !firstPhotoURL.isEmpty {
                    Button {
                        selectedPhotoForPreview = firstPhotoURL
                    } label: {
                        AsyncImageView(urlString: firstPhotoURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(width: 60, height: 60)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sheet(item: Binding(
                        get: { selectedPhotoForPreview.map { PhotoPreviewItem.url($0) } },
                        set: { if $0 == nil { selectedPhotoForPreview = nil } }
                    )) { item in
                        if case .url(let url) = item {
                            FotografPreviewView(urlString: url)
                        }
                    }
                } else {
                    Image(systemName: returnOp.reason.icon)
                        .font(.title2)
                        .foregroundColor(getColor())
                        .frame(width: 60, height: 60)
                        .background(getColor().opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(returnOp.reason.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(String(format: "%.2f CHF", returnOp.amount))
                        .font(.subheadline)
                        .foregroundColor(getColor())
                    
                    Text(formatDate(returnOp.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Photo count badge
                    if !returnOp.photos.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.fill")
                                .font(.caption2)
                            Text("\(returnOp.photos.count) photo\(returnOp.photos.count > 1 ? "s" : "")")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Actions
                Menu {
                    Button {
                        onTap()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .alert("Delete Return", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.officeReturnSil(returnOp)
            }
        } message: {
            Text("Are you sure you want to delete this return? This action cannot be undone.")
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

