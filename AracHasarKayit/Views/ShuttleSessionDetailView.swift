import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Detailed view of a shuttle session with customer entry controls
struct ShuttleSessionDetailView: View {
    let session: ShuttleSession
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var entries: [ShuttleEntry] = []
    @State private var isLoading = true
    @State private var customerCount: String = ""
    @State private var lastCustomerCount: Int = 1
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Session Stats
                sessionStatsSection
                
                // Customer Entry (only for active sessions)
                if session.isActive && session.id != nil && session.id == shuttleManager.currentSession?.id {
                    customerEntrySection
                }
                
                // Entries List
                entriesSection
                
                // Actions
                actionsSection
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.cyan.opacity(0.05), Color.blue.opacity(0.02)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(session.formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEntries()
        }
        .onAppear {
            // Pre-fill with last count
            if customerCount.isEmpty {
                customerCount = "\(lastCustomerCount)"
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .onTapGesture {
            isFocused = false
        }
    }
    
    // MARK: - Session Stats Section
    
    private var sessionStatsSection: some View {
        VStack(spacing: 16) {
            // Status Badge
            HStack {
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isActive ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    
                    Text(session.isActive ? "Active Session".localized : "Completed".localized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(session.isActive ? .green : .gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    (session.isActive ? Color.green : Color.gray).opacity(0.1)
                )
                .cornerRadius(20)
                
                Spacer()
            }
            
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    title: "Total Customers".localized,
                    value: "\(session.totalCustomers)",
                    icon: "person.2.fill",
                    color: .cyan
                )
                
                StatCard(
                    title: "Total Trips".localized,
                    value: "\(entries.count)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .purple
                )
                
                StatCard(
                    title: "Duration".localized,
                    value: session.duration,
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Avg/Trip".localized,
                    value: entries.isEmpty ? "0" : String(format: "%.1f", Double(session.totalCustomers) / Double(entries.count)),
                    icon: "chart.bar.fill",
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Customer Entry Section
    
    private var customerEntrySection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "person.2.circle.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
                
                Text("Add Customer Entry".localized)
                    .font(.headline)
                
                Spacer()
            }
            
            // Customer Count Input
            HStack(spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.cyan)
                
                TextField("Number of customers".localized, text: $customerCount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .focused($isFocused)
            }
            
            // Pick Up & Drop Off Buttons
            HStack(spacing: 16) {
                // Pick Up Button
                Button {
                    addEntry(type: .pickup)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                        Text("Pick Up".localized)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                // Drop Off Button
                Button {
                    addEntry(type: .dropoff)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                        Text("Drop Off".localized)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - Entries Section
    
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
                
                Text("Trip History".localized)
                    .font(.headline)
                
                Spacer()
                
                Text("\(entries.count) \("trips".localized)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if entries.isEmpty {
                Text("No entries yet".localized)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                ForEach(entries) { entry in
                    EntryCard(entry: entry)
                }
            }
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Export PDF
            Button {
                exportPDF()
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                    Text("Export as PDF".localized)
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.cyan, Color.blue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .cyan.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            // End Session (only for active sessions)
            if session.isActive && session.id != nil && session.id == shuttleManager.currentSession?.id {
                Button {
                    endSession()
                    HapticManager.shared.medium()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("End Session".localized)
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                    .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            
            // Delete Session (for all sessions - but with confirmation)
            Button {
                deleteSession()
                HapticManager.shared.medium()
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text(session.isActive ? "Cancel & Delete Session".localized : "Delete Session".localized)
                    Spacer()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(ShuttleTheme.error.opacity(0.8))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Actions
    
    private func addEntry(type: ShuttleEntryType) {
        guard let count = Int(customerCount), count > 0 else { return }
        
        // Save last count
        lastCustomerCount = count
        
        Task {
            try? await shuttleManager.addCustomerEntry(customerCount: count, entryType: type)
            
            // Reload entries
            await loadEntries()
            
            // Auto-fill with last count
            await MainActor.run {
                customerCount = "\(count)"
                isFocused = false
            }
        }
    }
    
    private func loadEntries() async {
        guard let sessionId = session.id else { return }
        
        do {
            let snapshot = try await FirebaseService.shared.getFilteredQuery("shuttleEntries")
                .whereField("sessionId", isEqualTo: sessionId)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let loadedEntries = snapshot.documents.compactMap { doc in
                try? doc.data(as: ShuttleEntry.self)
            }
            
            await MainActor.run {
                entries = loadedEntries
                isLoading = false
            }
        } catch {
            print("❌ Error loading entries: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func exportPDF() {
        let url = ShuttleReportGenerator.shared.generatePDFReport(for: session)
        shareURL = url
        showShareSheet = true
    }
    
    private func endSession() {
        Task {
            try? await shuttleManager.endDailySession()
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func deleteSession() {
        guard let sessionId = session.id else { return }
        
        Task {
            // If active session, end it first
            if session.isActive && session.id == shuttleManager.currentSession?.id {
                try? await shuttleManager.endDailySession()
                
                // Small delay to ensure Firebase updates
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
            
            // Delete session
            try? await FirebaseService.shared.getCollectionReference("shuttleSessions")
                .document(sessionId)
                .delete()
            
            // Delete entries
            let snapshot = try? await FirebaseService.shared.getFilteredQuery("shuttleEntries")
                .whereField("sessionId", isEqualTo: sessionId)
                .getDocuments()
            
            for doc in snapshot?.documents ?? [] {
                try? await doc.reference.delete()
            }
            
            await MainActor.run {
                ToastManager.shared.show("✓ \("Session Deleted".localized)", type: .success)
                HapticManager.shared.success()
                dismiss()
            }
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Entry Card

struct EntryCard: View {
    let entry: ShuttleEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(entry.entryType == .pickup ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: entry.entryType.icon)
                    .font(.title3)
                    .foregroundColor(entry.entryType == .pickup ? .green : .blue)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.formattedDateTime)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(entry.entryType.rawValue.localized)
                    .font(.caption)
                    .foregroundColor(entry.entryType == .pickup ? .green : .blue)
            }
            
            Spacer()
            
            // Customer Count
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(entry.customerCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Preview

struct ShuttleSessionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ShuttleSessionDetailView(
                session: ShuttleSession(
                    date: Date(),
                    driverName: "Admin",
                    driverUID: "123",
                    entries: [],
                    totalCustomers: 10,
                    isActive: true,
                    startTime: Date()
                )
            )
        }
    }
}

