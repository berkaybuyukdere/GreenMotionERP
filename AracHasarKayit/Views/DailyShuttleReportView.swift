import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Daily Shuttle Report View - Günlük müşteri alış/bırakış kayıtları (shuttleEntries kullanarak)
struct DailyShuttleReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var shuttleManager = ShuttleManager.shared
    var selectedMonth: Date = Date()
    
    @State private var allEntries: [ShuttleEntry] = []
    @State private var isLoading = false
    @State private var showAddReport = false
    @State private var showGenerateReport = false
    @State private var editingSummary: DailySummary?
    @State private var shuttleListener: ListenerRegistration?
    
    // Get month range for filtering
    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: startOfMonth) else {
            return (selectedMonth, selectedMonth)
        }
        return (startOfMonth, endOfMonth)
    }
    
    // Group entries by date and calculate daily summaries
    private var dailySummaries: [DailySummary] {
        let calendar = Calendar.current
        let range = monthRange
        
        // Filter entries by month
        let filteredEntries = allEntries.filter { entry in
            entry.timestamp >= range.start && entry.timestamp <= range.end
        }
        
        // Group by date (start of day)
        let grouped = Dictionary(grouping: filteredEntries) { entry -> Date in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        // Create daily summaries
        return grouped.map { date, entries in
            let pickupEntries = entries.filter { $0.entryType == .pickup }
            let dropoffEntries = entries.filter { $0.entryType == .dropoff }
            
            let pickupCount = pickupEntries.reduce(0) { $0 + $1.customerCount }
            let dropoffCount = dropoffEntries.reduce(0) { $0 + $1.customerCount }
            let totalCustomers = pickupCount + dropoffCount
            
            let driverName = entries.first?.driverName ?? "Unknown"
            let driverUID = entries.first?.driverUID ?? ""
            
            return DailySummary(
                date: date,
                driverName: driverName,
                driverUID: driverUID,
                pickupCount: pickupCount,
                dropoffCount: dropoffCount,
                totalCustomers: totalCustomers,
                entries: entries
            )
        }
        .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if dailySummaries.isEmpty {
                    emptyStateView
                } else {
                    reportsList
                }
            }
            .navigationTitle("Daily Shuttle Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.light()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.cyan)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            HapticManager.shared.medium()
                            showGenerateReport = true
                        } label: {
                            Label("Report", systemImage: "doc.text.fill")
                                .foregroundColor(.cyan)
                        }
                        
                        Button {
                            HapticManager.shared.medium()
                            showAddReport = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddReport) {
                NavigationView {
                    AddDailyShuttleReportView()
                        .environmentObject(viewModel)
                }
            }
            .sheet(isPresented: $showGenerateReport) {
                GenerateShuttleReportView()
            }
            .sheet(item: $editingSummary) { summary in
                NavigationView {
                    EditDailyShuttleReportView(summary: summary, allEntries: $allEntries)
                        .environmentObject(viewModel)
                }
            }
            .onAppear {
                loadShuttleEntries()
                observeShuttleEntries()
            }
            .onDisappear {
                // Cleanup listener when view disappears
                shuttleListener?.remove()
                shuttleListener = nil
            }
        }
    }
    
    private var reportsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Summary Cards
                summaryCards
                
                Divider()
                    .padding(.vertical)
                
                // Reports List
                ForEach(dailySummaries) { summary in
                    DailySummaryCard(summary: summary)
                        .onTapGesture {
                            HapticManager.shared.light()
                            editingSummary = summary
                        }
                        .contextMenu {
                            Button {
                                HapticManager.shared.medium()
                                editingSummary = summary
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                HapticManager.shared.medium()
                                deleteDayEntries(summary)
                            } label: {
                                Label("Delete Day", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
    
    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Days")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("\(dailySummaries.count)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.cyan)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cyan.opacity(0.1))
            )
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Customers")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("\(dailySummaries.reduce(0) { $0 + $1.totalCustomers })")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.cyan)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cyan.opacity(0.1))
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading entries...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bus.fill")
                .font(.system(size: 80))
                .foregroundColor(.cyan.opacity(0.3))
            
            Text("No Daily Reports")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Add entries to track customer pickups and drop-offs")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showAddReport = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Entry")
                }
            }
            .buttonStyle(AppTheme.primaryButtonStyle)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadShuttleEntries() {
        isLoading = true
        
        Task {
            do {
                let range = monthRange
                let snapshot = try await Firestore.firestore()
                    .collection("shuttleEntries")
                    .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: range.start))
                    .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: range.end))
                    .order(by: "timestamp", descending: true)
                    .limit(to: 100) // Reduced from 1000 to 100 for better performance
                    .getDocuments()
                
                let entries = snapshot.documents.compactMap { doc -> ShuttleEntry? in
                    let data = doc.data()
                    var entry = ShuttleEntry(
                        customerCount: data["customerCount"] as? Int ?? 0,
                        entryType: ShuttleEntryType(rawValue: data["entryType"] as? String ?? "Pick Up") ?? .pickup,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        driverName: data["driverName"] as? String ?? "",
                        driverUID: data["driverUID"] as? String ?? "",
                        sessionId: data["sessionId"] as? String ?? ""
                    )
                    entry.id = doc.documentID
                    
                    return entry
                }
                
                await MainActor.run {
                    allEntries = entries
                    isLoading = false
                    print("✅ Loaded \(entries.count) shuttle entries")
                }
            } catch {
                print("❌ Error loading entries: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    ErrorManager.shared.showError(error, context: "Load Shuttle Entries")
                }
            }
        }
    }
    
    private func observeShuttleEntries() {
        let range = monthRange
        
        // Remove existing listener if any
        shuttleListener?.remove()
        
        // Create new listener and store it
        shuttleListener = Firestore.firestore()
            .collection("shuttleEntries")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: range.start))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: range.end))
            .order(by: "timestamp", descending: true)
            .limit(to: 100) // Reduced from 1000 to 100 for better performance
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Listener error: \(error.localizedDescription)")
                    ErrorManager.shared.showError(error, context: "Observe Shuttle Entries")
                    
                    // Always call completion even on error to prevent UI freeze
                    DispatchQueue.main.async {
                        // Keep existing entries on error, don't clear them
                        print("⚠️ Keeping existing entries due to listener error")
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        // If no documents, keep existing entries (might be legitimate empty state)
                        print("⚠️ No documents in snapshot, keeping existing entries")
                    }
                    return
                }
                
                let entries = documents.compactMap { doc -> ShuttleEntry? in
                    let data = doc.data()
                    var entry = ShuttleEntry(
                        customerCount: data["customerCount"] as? Int ?? 0,
                        entryType: ShuttleEntryType(rawValue: data["entryType"] as? String ?? "Pick Up") ?? .pickup,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        driverName: data["driverName"] as? String ?? "",
                        driverUID: data["driverUID"] as? String ?? "",
                        sessionId: data["sessionId"] as? String ?? ""
                    )
                    entry.id = doc.documentID
                    
                    return entry
                }
                
                DispatchQueue.main.async {
                    // Use closure capture to update state
                    // Note: Since this is a struct, we capture the state variable directly
                    // The listener will be removed in onDisappear, so no memory leak
                    self.allEntries = entries
                    print("✅ Real-time update: \(entries.count) shuttle entries")
                }
            }
    }
    
    private func deleteDayEntries(_ summary: DailySummary) {
        Task {
            do {
                let db = Firestore.firestore()
                let entriesToDelete = summary.entries.compactMap { $0.id }
                
                // Firestore batch limit is 500 operations
                let maxBatchSize = 500
                let batches = entriesToDelete.chunked(into: maxBatchSize)
                
                // Process each batch
                for batchEntries in batches {
                    let batch = db.batch()
                    for entryId in batchEntries {
                        let ref = db.collection("shuttleEntries").document(entryId)
                        batch.deleteDocument(ref)
                    }
                    try await batch.commit()
                }
                
                await MainActor.run {
                    allEntries.removeAll { entry in
                        summary.entries.contains { $0.id == entry.id }
                    }
                    ToastManager.shared.show("Day entries deleted", type: .success)
                }
            } catch {
                print("❌ Error deleting entries: \(error)")
                await MainActor.run {
                    ErrorManager.shared.showError(error, context: "Delete Day Entries")
                }
            }
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Daily Summary Model

struct DailySummary: Identifiable {
    var id: Date { date }
    var date: Date
    var driverName: String
    var driverUID: String
    var pickupCount: Int
    var dropoffCount: Int
    var totalCustomers: Int
    var entries: [ShuttleEntry]
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Daily Summary Card

struct DailySummaryCard: View {
    let summary: DailySummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.formattedDate)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(summary.driverName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pickups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text("\(summary.pickupCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop-offs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("\(summary.dropoffCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.totalCustomers)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Add Daily Shuttle Report View

struct AddDailyShuttleReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var shuttleManager = ShuttleManager.shared
    
    @State private var selectedDate: Date = Date()
    @State private var pickupCount: String = ""
    @State private var dropoffCount: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false
    
    var body: some View {
        Form {
            dateSection
            countsSection
            notesSection
            saveSection
        }
        .navigationTitle("Add Daily Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    HapticManager.shared.light()
                    dismiss()
                }
            }
        }
    }
    
    private var dateSection: some View {
        Section("Entry Date") {
            DatePicker("Date & Time", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var countsSection: some View {
        Section("Customer Counts") {
            VStack(spacing: 16) {
                // Pickup Row
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pickups")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Customers picked up")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    TextField("", text: $pickupCount)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                        .onChange(of: pickupCount) { oldValue, newValue in
                            pickupCount = newValue.filter { $0.isNumber }
                        }
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Drop-off Row
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drop-offs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Customers dropped off")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    TextField("", text: $dropoffCount)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                        .onChange(of: dropoffCount) { oldValue, newValue in
                            dropoffCount = newValue.filter { $0.isNumber }
                        }
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Total Row
                HStack {
                    Text("Total Customers")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(totalCustomers)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.cyan)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes (Optional)") {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                HapticManager.shared.medium()
                saveEntries()
            } label: {
                if isSaving {
                    HStack {
                        ProgressView()
                        Text("Saving...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Entries")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(isSaving || !isValid)
            
            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
    }
    
    private var totalCustomers: Int {
        (Int(pickupCount) ?? 0) + (Int(dropoffCount) ?? 0)
    }
    
    // Maximum reasonable customer count per entry
    private let maxCustomersPerEntry = 1000
    
    private var isValid: Bool {
        let pickup = Int(pickupCount) ?? 0
        let dropoff = Int(dropoffCount) ?? 0
        
        // Check if at least one count is greater than 0
        guard pickup > 0 || dropoff > 0 else { return false }
        
        // Check maximum limits
        guard pickup >= 0 && pickup <= maxCustomersPerEntry else { return false }
        guard dropoff >= 0 && dropoff <= maxCustomersPerEntry else { return false }
        
        // Date validation - check if date is within reasonable range
        let calendar = Calendar.current
        let now = Date()
        let maxPastDate = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        let maxFutureDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        
        guard selectedDate >= maxPastDate && selectedDate <= maxFutureDate else {
            return false
        }
        
        return true
    }
    
    // Validation message for user feedback
    private var validationMessage: String? {
        let pickup = Int(pickupCount) ?? 0
        let dropoff = Int(dropoffCount) ?? 0
        
        if pickup < 0 || dropoff < 0 {
            return "Customer count cannot be negative"
        }
        
        if pickup > maxCustomersPerEntry || dropoff > maxCustomersPerEntry {
            return "Customer count cannot exceed \(maxCustomersPerEntry)"
        }
        
        if pickup == 0 && dropoff == 0 {
            return "At least one customer count must be greater than 0"
        }
        
        // Date validation
        let calendar = Calendar.current
        let now = Date()
        let maxPastDate = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        let maxFutureDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        
        if selectedDate < maxPastDate {
            return "Date cannot be more than 12 months in the past"
        }
        
        if selectedDate > maxFutureDate {
            return "Date cannot be in the future"
        }
        
        return nil
    }
    
    private func saveEntries() {
        guard let user = Auth.auth().currentUser else { return }
        guard isValid else { return }
        
        isSaving = true
        
        let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Driver"
        let pickupInt = Int(pickupCount) ?? 0
        let dropoffInt = Int(dropoffCount) ?? 0
        
        Task {
            do {
                let db = Firestore.firestore()
                let batch = db.batch()
                
                // Create a session ID for this day's entries (use date as session identifier)
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: selectedDate)
                let sessionId = "daily_\(Int(dayStart.timeIntervalSince1970))"
                
                // Add pickup entry if count > 0
                if pickupInt > 0 {
                    let pickupEntry = ShuttleEntry(
                        customerCount: pickupInt,
                        entryType: .pickup,
                        timestamp: selectedDate,
                        driverName: driverName,
                        driverUID: user.uid,
                        sessionId: sessionId
                    )
                    
                    let pickupRef = db.collection("shuttleEntries").document()
                    let pickupData: [String: Any] = [
                        "customerCount": pickupEntry.customerCount,
                        "entryType": pickupEntry.entryType.rawValue,
                        "timestamp": Timestamp(date: pickupEntry.timestamp),
                        "driverName": pickupEntry.driverName,
                        "driverUID": pickupEntry.driverUID,
                        "sessionId": pickupEntry.sessionId
                    ]
                    batch.setData(pickupData, forDocument: pickupRef)
                }
                
                // Add dropoff entry if count > 0
                if dropoffInt > 0 {
                    let dropoffEntry = ShuttleEntry(
                        customerCount: dropoffInt,
                        entryType: .dropoff,
                        timestamp: selectedDate,
                        driverName: driverName,
                        driverUID: user.uid,
                        sessionId: sessionId
                    )
                    
                    let dropoffRef = db.collection("shuttleEntries").document()
                    let dropoffData: [String: Any] = [
                        "customerCount": dropoffEntry.customerCount,
                        "entryType": dropoffEntry.entryType.rawValue,
                        "timestamp": Timestamp(date: dropoffEntry.timestamp),
                        "driverName": dropoffEntry.driverName,
                        "driverUID": dropoffEntry.driverUID,
                        "sessionId": dropoffEntry.sessionId
                    ]
                    batch.setData(dropoffData, forDocument: dropoffRef)
                }
                
                try await batch.commit()
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    NotificationCenter.default.post(name: NSNotification.Name("DailyShuttleReportUpdated"), object: nil)
                    ToastManager.shared.show("✓ Entries saved", type: .success)
                }
            } catch {
                print("❌ Error saving entries: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ErrorManager.shared.showError(error, context: "Save Shuttle Entries")
                }
            }
        }
    }
}
