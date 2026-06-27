import SwiftUI

struct OfficeReturnMainView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode
    var selectedMonth: Date = Date()
    /// When `false`, use the parent navigation stack (e.g. Office Operations hub).
    var embedsNavigationChrome: Bool = true
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
    
    private var canViewOperationTotals: Bool {
        authManager.userProfile?.canViewOfficeOperationTotals ?? false
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
        Group {
            if embedsNavigationChrome {
                NavigationStack {
                    chromeWrappedContent
                }
            } else {
                chromeWrappedContent
            }
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

    private var chromeWrappedContent: some View {
        contentView
            .navigationTitle("Customer Returns".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .fleetListPalantirChrome(enabled: palantirMode)
            .palantirOpsScreen()
            .toolbar {
                if embedsNavigationChrome {
                    ToolbarItem(placement: .navigationBarLeading) {
                        backButton
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
            }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Returns List with embedded summary
            returnsListSection
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
                    if canViewOperationTotals {
                        Text(AppCurrency.format(totalAmount))
                            .font(AppTheme.titleFont)
                            .fontWeight(.bold)
                    } else {
                        Text("—")
                            .font(AppTheme.titleFont)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
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
            if palantirMode {
                Image(systemName: "chevron.left")
                    .font(PalantirTheme.labelFont(12))
                    .foregroundStyle(PalantirTheme.accent)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                    Text("Back".localized)
                }
                .foregroundColor(.blue)
            }
        }
        .accessibilityLabel("Back".localized)
    }
    
    private var addButton: some View {
        Button {
            showAddReturn = true
        } label: {
            if palantirMode {
                PalantirSquareToolbarIconButton(systemName: "plus", accessibilityLabel: "Add return".localized)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
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
    @Environment(\.palantirModeEnabled) private var palantirMode

    var body: some View {
        if palantirMode {
            palantirRowBody
        } else {
            legacyRowBody
        }
    }

    private var palantirRowBody: some View {
        HStack(spacing: 12) {
            PalantirOpsIconTile(systemName: returnOp.reason.icon, tint: palantirRowTint, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(AppCurrency.format(returnOp.amount))
                        .font(PalantirTheme.dataFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    Text(returnOp.reason.rawValue)
                        .font(PalantirTheme.dataFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(1)
                }
                Text(formatDate(returnOp.date))
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                if !returnOp.photos.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9))
                        Text("\(returnOp.photos.count)")
                            .font(PalantirTheme.labelFont(9))
                    }
                    .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .palantirOpsListRowSurface()
    }

    private var palantirRowTint: Color {
        switch returnOp.reason.color {
        case "blue", "cyan", "indigo": return PalantirTheme.accent
        case "green": return PalantirTheme.success
        case "orange", "red": return PalantirTheme.warning
        case "purple": return PalantirTheme.purple
        default: return PalantirTheme.textMuted
        }
    }

    private var legacyRowBody: some View {
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
                    Text(AppCurrency.format(returnOp.amount))
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

