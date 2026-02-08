import Foundation
import FirebaseFirestore
import SwiftUI

/// Paginated activities manager for efficient loading
/// Loads activities in chunks to improve performance
class PaginatedActivitiesManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var hasMoreData = true
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize: Int
    private var listener: ListenerRegistration?
    
    // MARK: - Initialization
    
    init(pageSize: Int = 20) {
        self.pageSize = pageSize
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Public Methods
    
    /// Load initial page of activities
    func loadInitialPage() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        lastDocument = nil
        activities = []
        hasMoreData = true
        
        print("📄 Loading initial page of activities...")
        
        FirebaseService.shared.getFilteredQuery("activities")
            .order(by: "tarih", descending: true)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        print("❌ Failed to load activities: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.hasMoreData = false
                        return
                    }
                    
                    let newActivities = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    self.activities = newActivities
                    self.lastDocument = documents.last
                    self.hasMoreData = documents.count == self.pageSize
                    
                    print("✅ Loaded \(newActivities.count) activities")
                }
            }
    }
    
    /// Load next page of activities
    func loadNextPage() {
        guard !isLoading, hasMoreData, let lastDoc = lastDocument else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        print("📄 Loading next page of activities...")
        
        FirebaseService.shared.getFilteredQuery("activities")
            .order(by: "tarih", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        print("❌ Failed to load next page: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.hasMoreData = false
                        return
                    }
                    
                    let newActivities = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    self.activities.append(contentsOf: newActivities)
                    self.lastDocument = documents.last
                    self.hasMoreData = documents.count == self.pageSize
                    
                    print("✅ Loaded \(newActivities.count) more activities (Total: \(self.activities.count))")
                }
            }
    }
    
    /// Refresh activities (pull to refresh)
    func refresh() {
        loadInitialPage()
    }
    
    /// Filter activities by type
    func filterByType(_ type: ActivityType?) {
        guard let type = type else {
            loadInitialPage()
            return
        }
        
        isLoading = true
        errorMessage = nil
        lastDocument = nil
        activities = []
        
        print("🔍 Filtering activities by type: \(type.rawValue)")
        
        FirebaseService.shared.getFilteredQuery("activities")
            .whereField("tip", isEqualTo: type.rawValue)
            .order(by: "tarih", descending: true)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.hasMoreData = false
                        return
                    }
                    
                    let filteredActivities = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    self.activities = filteredActivities
                    self.lastDocument = documents.last
                    self.hasMoreData = documents.count == self.pageSize
                    
                    print("✅ Filtered \(filteredActivities.count) activities")
                }
            }
    }
    
    /// Search activities by vehicle plate
    func searchByPlate(_ plate: String) {
        guard !plate.isEmpty else {
            loadInitialPage()
            return
        }
        
        isLoading = true
        errorMessage = nil
        activities = []
        
        print("🔍 Searching activities for plate: \(plate)")
        
        FirebaseService.shared.getFilteredQuery("activities")
            .whereField("aracPlaka", isEqualTo: plate)
            .order(by: "tarih", descending: true)
            .limit(to: 50) // Show more results for search
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        return
                    }
                    
                    let searchResults = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    self.activities = searchResults
                    self.hasMoreData = false // Disable pagination for search
                    
                    print("✅ Found \(searchResults.count) activities for plate: \(plate)")
                }
            }
    }
    
    /// Enable real-time updates for current activities
    func enableRealTimeUpdates() {
        listener?.remove()
        
        listener = FirebaseService.shared.getFilteredQuery("activities")
            .order(by: "tarih", descending: true)
            .limit(to: pageSize)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    let newActivities = documents.compactMap { doc -> Activity? in
                        try? doc.data(as: Activity.self)
                    }
                    
                    // Only update if there are changes
                    if newActivities != self.activities {
                        self.activities = newActivities
                        print("🔄 Activities updated in real-time: \(newActivities.count) items")
                    }
                }
            }
    }
    
    /// Disable real-time updates
    func disableRealTimeUpdates() {
        listener?.remove()
        listener = nil
        print("⏸️ Real-time updates disabled")
    }
}

// MARK: - SwiftUI View

struct PaginatedActivitiesView: View {
    @StateObject private var manager = PaginatedActivitiesManager(pageSize: 20)
    @State private var selectedFilter: ActivityType?
    @State private var searchPlate = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                
                // Activities list
                if manager.activities.isEmpty && !manager.isLoading {
                    emptyState
                } else {
                    activitiesList
                }
            }
            .navigationTitle("Recent Activities")
            .navigationBarItems(trailing: refreshButton)
            .onAppear {
                manager.loadInitialPage()
            }
        }
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All filter
                FilterChip(
                    title: "All",
                    isSelected: selectedFilter == nil,
                    action: {
                        selectedFilter = nil
                        manager.loadInitialPage()
                    }
                )
                
                // Type filters
                ForEach(ActivityType.allCases, id: \.rawValue) { type in
                    FilterChip(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: selectedFilter == type,
                        action: {
                            selectedFilter = type
                            manager.filterByType(type)
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    private var activitiesList: some View {
        List {
            ForEach(manager.activities) { activity in
                ActivityRowView(activity: activity)
            }
            
            // Load more button
            if manager.hasMoreData {
                HStack {
                    Spacer()
                    if manager.isLoading {
                        ProgressView()
                            .padding()
                    } else {
                        Button("Load More") {
                            manager.loadNextPage()
                        }
                        .padding()
                    }
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            manager.refresh()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Activities Yet")
                .font(.headline)
            
            Text("Activities will appear here when you perform actions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var refreshButton: some View {
        Button {
            manager.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
    }
}

// MARK: - Helper Views

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct ActivityRowView: View {
    let activity: Activity
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: activity.tip.icon)
                .font(.title3)
                .foregroundColor(activity.tip.color)
                .frame(width: 40, height: 40)
                .background(activity.tip.color.opacity(0.1))
                .cornerRadius(8)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.tip.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(activity.aciklama)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let userName = activity.kullaniciAdi {
                    Text("by \(userName)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Time
            Text(timeAgo(from: activity.tarih))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // Removed: colorForType - now using activity.tip.color directly (Color type)
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - ActivityType Extension

extension ActivityType: CaseIterable {
    static var allCases: [ActivityType] {
        return [.aracEklendi, .aracSilindi, .hasarEklendi, .hasarSilindi, .hasarGuncellendi, .servisEklendi, .iadeYapildi]
    }
}

