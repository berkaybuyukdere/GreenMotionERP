import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Edit Daily Shuttle Report View

struct EditDailyShuttleReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var allEntries: [ShuttleEntry]
    
    let summary: DailySummary
    
    @State private var selectedDate: Date
    @State private var pickupCount: String
    @State private var dropoffCount: String
    @State private var notes: String = ""
    @State private var isSaving = false
    
    init(summary: DailySummary, allEntries: Binding<[ShuttleEntry]>) {
        self.summary = summary
        self._allEntries = allEntries
        
        // Initialize with existing values
        let pickupEntry = summary.entries.first { $0.entryType == .pickup }
        let dropoffEntry = summary.entries.first { $0.entryType == .dropoff }
        
        _selectedDate = State(initialValue: summary.date)
        _pickupCount = State(initialValue: pickupEntry.map { "\($0.customerCount)" } ?? "")
        _dropoffCount = State(initialValue: dropoffEntry.map { "\($0.customerCount)" } ?? "")
    }
    
    var body: some View {
        Form {
            dateSection
            countsSection
            notesSection
            saveSection
        }
        .navigationTitle("Edit Daily Entry")
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
                updateEntries()
            } label: {
                if isSaving {
                    HStack {
                        ProgressView()
                        Text("Updating...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Update Entries")
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
    
    private func updateEntries() {
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
                
                // Get existing entries for this date
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: selectedDate)
                let existingPickupEntries = summary.entries.filter { $0.entryType == .pickup }
                let existingDropoffEntries = summary.entries.filter { $0.entryType == .dropoff }
                
                // Update or create pickup entry
                if pickupInt > 0 {
                    if let existingPickup = existingPickupEntries.first, let entryId = existingPickup.id {
                        // Update existing entry
                        let pickupRef = db.collection("shuttleEntries").document(entryId)
                        let pickupData: [String: Any] = [
                            "customerCount": pickupInt,
                            "entryType": ShuttleEntryType.pickup.rawValue,
                            "timestamp": Timestamp(date: selectedDate),
                            "driverName": driverName,
                            "driverUID": user.uid,
                            "sessionId": existingPickup.sessionId
                        ]
                        batch.setData(pickupData, forDocument: pickupRef, merge: false)
                    } else {
                        // Create new pickup entry
                        let sessionId = "daily_\(Int(dayStart.timeIntervalSince1970))"
                        let pickupRef = db.collection("shuttleEntries").document()
                        let pickupData: [String: Any] = [
                            "customerCount": pickupInt,
                            "entryType": ShuttleEntryType.pickup.rawValue,
                            "timestamp": Timestamp(date: selectedDate),
                            "driverName": driverName,
                            "driverUID": user.uid,
                            "sessionId": sessionId
                        ]
                        batch.setData(pickupData, forDocument: pickupRef)
                    }
                } else {
                    // Delete pickup entries if count is 0
                    for entry in existingPickupEntries {
                        if let entryId = entry.id {
                            let ref = db.collection("shuttleEntries").document(entryId)
                            batch.deleteDocument(ref)
                        }
                    }
                }
                
                // Update or create dropoff entry
                if dropoffInt > 0 {
                    if let existingDropoff = existingDropoffEntries.first, let entryId = existingDropoff.id {
                        // Update existing entry
                        let dropoffRef = db.collection("shuttleEntries").document(entryId)
                        let dropoffData: [String: Any] = [
                            "customerCount": dropoffInt,
                            "entryType": ShuttleEntryType.dropoff.rawValue,
                            "timestamp": Timestamp(date: selectedDate),
                            "driverName": driverName,
                            "driverUID": user.uid,
                            "sessionId": existingDropoff.sessionId
                        ]
                        batch.setData(dropoffData, forDocument: dropoffRef, merge: false)
                    } else {
                        // Create new dropoff entry
                        let sessionId = existingPickupEntries.first?.sessionId ?? "daily_\(Int(dayStart.timeIntervalSince1970))"
                        let dropoffRef = db.collection("shuttleEntries").document()
                        let dropoffData: [String: Any] = [
                            "customerCount": dropoffInt,
                            "entryType": ShuttleEntryType.dropoff.rawValue,
                            "timestamp": Timestamp(date: selectedDate),
                            "driverName": driverName,
                            "driverUID": user.uid,
                            "sessionId": sessionId
                        ]
                        batch.setData(dropoffData, forDocument: dropoffRef)
                    }
                } else {
                    // Delete dropoff entries if count is 0
                    for entry in existingDropoffEntries {
                        if let entryId = entry.id {
                            let ref = db.collection("shuttleEntries").document(entryId)
                            batch.deleteDocument(ref)
                        }
                    }
                }
                
                // Note: Current operations are safe (max 2-3 operations per batch)
                // Firestore batch limit is 500, but we only do 2-3 operations here
                try await batch.commit()
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    NotificationCenter.default.post(name: NSNotification.Name("DailyShuttleReportUpdated"), object: nil)
                    ToastManager.shared.show("✓ Entries updated", type: .success)
                }
            } catch {
                print("❌ Error updating entries: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ErrorManager.shared.showError(error, context: "Update Shuttle Entries")
                }
            }
        }
    }
}

