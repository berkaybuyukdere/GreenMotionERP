import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Main Shuttle View - All sessions with filtering, sorting, and PDF generation
struct ShuttleMainView: View {
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var sessions: [ShuttleSession] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .dateNewest
    @State private var filterOption: FilterOption = .all
    @State private var showGenerateReport = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var navigateToCurrentSession = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    enum SortOption: String, CaseIterable {
        case dateNewest = "Date (Newest)"
        case dateOldest = "Date (Oldest)"
        case customersHigh = "Customers (High-Low)"
        case customersLow = "Customers (Low-High)"
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "All Sessions"
        case active = "Active"
        case completed = "Completed"
    }
    
    var filteredAndSortedSessions: [ShuttleSession] {
        var result = sessions
        
        // Filter
        switch filterOption {
        case .all:
            break
        case .active:
            result = result.filter { $0.isActive }
        case .completed:
            result = result.filter { !$0.isActive }
        }
        
        // Search
        if !searchText.isEmpty {
            result = result.filter { session in
                session.driverName.localizedCaseInsensitiveContains(searchText) ||
                session.formattedDate.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        switch sortOption {
        case .dateNewest:
            result.sort { $0.startTime > $1.startTime }
        case .dateOldest:
            result.sort { $0.startTime < $1.startTime }
        case .customersHigh:
            result.sort { $0.totalCustomers > $1.totalCustomers }
        case .customersLow:
            result.sort { $0.totalCustomers < $1.totalCustomers }
        }
        
        return result
    }
    
    var body: some View {
        ZStack {
            // Background gradient (dark/light mode adaptive)
            LinearGradient(
                gradient: Gradient(colors: [Color.cyan.opacity(0.1), Color.blue.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Filter & Sort Bar
                filterSortBar
                
                // Content
                if isLoading {
                    loadingView
                } else if filteredAndSortedSessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }
            
            // Hidden NavigationLink for programmatic navigation
            if let currentSession = shuttleManager.currentSession {
                NavigationLink(
                    destination: ShuttleSessionDetailView(session: currentSession),
                    isActive: $navigateToCurrentSession
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
        .navigationTitle("Shuttle")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by driver or date...")
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty && newValue.count >= 3 {
                                }
        }
        .onAppear {
                        loadSessions()
        }
        .onDisappear {
                        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShuttleSessionUpdated"))) { _ in
            loadSessions()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Back")
                    }
                    .foregroundColor(.cyan)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Start Session Button (if no active session)
                    if shuttleManager.currentSession == nil {
                        Button {
                                                        shuttleManager.startDailySession()
                            HapticManager.shared.success()
                            ToastManager.shared.show("✓ Session Started", type: .success)
                            
                            // Navigate to session after 1 second
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                navigateToCurrentSession = true
                            }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Generate Report Button
                    Button {
                                                showGenerateReport = true
                        HapticManager.shared.medium()
                    } label: {
                        Label("Report", systemImage: "doc.text.fill")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showGenerateReport) {
            GenerateShuttleReportView()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
    
    // MARK: - Filter & Sort Bar
    
    private var filterSortBar: some View {
        HStack(spacing: 12) {
            // Filter Menu
            Menu {
                Picker("Filter", selection: $filterOption) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .onChange(of: filterOption) { oldValue, newValue in
                                        }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterOption.rawValue)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.1))
                .foregroundColor(.cyan)
                .cornerRadius(20)
            }
            
            // Sort Menu
            Menu {
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .onChange(of: sortOption) { oldValue, newValue in
                                        }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.rawValue)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(20)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Sessions List
    
    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Current Session Card (if active)
                if let currentSession = shuttleManager.currentSession {
                    NavigationLink(destination: ShuttleSessionDetailView(session: currentSession)) {
                        SessionCard(session: currentSession, isCurrent: true)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            }
                    )
                }
                
                // Past Sessions
                ForEach(filteredAndSortedSessions) { session in
                    if session.id != shuttleManager.currentSession?.id {
                        NavigationLink(destination: ShuttleSessionDetailView(session: session)) {
                            SessionCard(session: session, isCurrent: false)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                }
                        )
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading sessions...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bus.fill")
                .font(.system(size: 80))
                .foregroundColor(.cyan.opacity(0.3))
            
            Text("No Sessions Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Start a new shuttle session to begin tracking")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                shuttleManager.startDailySession()
                HapticManager.shared.success()
                ToastManager.shared.show("✓ Session Started", type: .success)
                
                // Navigate to session after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    navigateToCurrentSession = true
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Shuttle Session")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load Sessions
    
    private func loadSessions() {
        isLoading = true
        
        Task {
            do {
                let snapshot = try await FirebaseService.shared.getFilteredQuery("shuttleSessions")
                    .order(by: "startTime", descending: true)
                    .limit(to: 100)
                    .getDocuments()
                
                let loadedSessions = snapshot.documents.compactMap { doc in
                    try? doc.data(as: ShuttleSession.self)
                }
                
                await MainActor.run {
                    sessions = loadedSessions
                    isLoading = false
                }
            } catch {
                print("❌ Error loading sessions: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: ShuttleSession
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.cyan, Color.blue]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: "bus.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.formattedDate)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isCurrent {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                
                Text(session.driverName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    Label("\(session.totalCustomers)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    
                    Label("\(session.entries.count) entries", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Label(session.duration, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: isCurrent ? Color.green.opacity(0.2) : Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Preview

struct ShuttleMainView_Previews: PreviewProvider {
    static var previews: some View {
        ShuttleMainView()
    }
}