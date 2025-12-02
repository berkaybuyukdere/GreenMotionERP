import SwiftUI
import FirebaseAuth

struct LeaderboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var leaderboard: [LeaderboardEntry] = []
    @State private var currentUserRank: Int?
    @State private var currentUserStats: UserStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedUser: LeaderboardEntry?
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Error Loading Leaderboard")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // Current User Stats Section
                if let stats = currentUserStats {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(authManager.userProfile?.fullName ?? "You")
                                        .font(.headline)
                                    if let rank = currentUserRank {
                                        Text("Rank #\(rank)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(stats.totalPoints)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                    Text("Points")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            // Activity Breakdown
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Activities")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                ActivityStatRow(
                                    icon: "exclamationmark.triangle.fill",
                                    label: "Damage Records",
                                    count: stats.activityStats.damageRecords,
                                    points: stats.activityStats.damageRecords * 100,
                                    color: .orange
                                )
                                
                                ActivityStatRow(
                                    icon: "arrow.uturn.backward.circle.fill",
                                    label: "Return Operations",
                                    count: stats.activityStats.returnOperations,
                                    points: stats.activityStats.returnOperations * 80,
                                    color: .purple
                                )
                                
                                ActivityStatRow(
                                    icon: "arrow.right.circle.fill",
                                    label: "Check Out Operations",
                                    count: stats.activityStats.checkOutOperations,
                                    points: stats.activityStats.checkOutOperations * 60,
                                    color: .blue
                                )
                                
                                ActivityStatRow(
                                    icon: "briefcase.fill",
                                    label: "Office Operations",
                                    count: stats.activityStats.officeOperations,
                                    points: stats.activityStats.officeOperations * 40,
                                    color: .indigo
                                )
                                
                                ActivityStatRow(
                                    icon: "car.fill",
                                    label: "Vehicle Records",
                                    count: stats.activityStats.vehicleRecords,
                                    points: stats.activityStats.vehicleRecords * 20,
                                    color: .green
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Your Statistics")
                    }
                }
                
                // Leaderboard Section
                Section {
                    if leaderboard.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "trophy")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Rankings Yet")
                                .font(.headline)
                            Text("Complete activities to earn points and appear on the leaderboard!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(leaderboard) { entry in
                            LeaderboardRow(entry: entry)
                                .onTapGesture {
                                    selectedUser = entry
                                }
                        }
                    }
                } header: {
                    Text("Top Players")
                } footer: {
                    Text("Points are awarded for completing activities. Higher priority activities earn more points.")
                }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadLeaderboard()
        }
        .refreshable {
            loadLeaderboard()
        }
        .sheet(item: $selectedUser) { user in
            UserDetailView(entry: user)
        }
    }
    
    private func loadLeaderboard() {
        isLoading = true
        errorMessage = nil
        
        // Load leaderboard
        GamificationManager.shared.getLeaderboard(limit: 20) { entries, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                
                self.leaderboard = entries ?? []
                
                // Load current user's rank
                GamificationManager.shared.getCurrentUserRank { rank, error in
                    DispatchQueue.main.async {
                        self.currentUserRank = rank
                    }
                }
                
                // Load current user's stats
                GamificationManager.shared.getCurrentUserStats { stats, error in
                    DispatchQueue.main.async {
                        self.currentUserStats = stats
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                if entry.rank <= 3 {
                    Image(systemName: rankIcon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(rankColor)
                } else {
                    Text("\(entry.rank)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(rankColor)
                }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name.isEmpty ? "Unknown User" : entry.name)
                        .font(.headline)
                    if entry.isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Text("\(entry.activityStats.totalActivities) activities")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Points
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.totalPoints)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text("points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(entry.isCurrentUser ? Color.blue.opacity(0.1) : Color.clear)
    }
    
    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .blue
        }
    }
    
    private var rankIcon: String {
        switch entry.rank {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return ""
        }
    }
}

struct ActivityStatRow: View {
    let icon: String
    let label: String
    let count: Int
    let points: Int
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(points) pts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - User Detail View
struct UserDetailView: View {
    let entry: LeaderboardEntry
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.name.isEmpty ? "Unknown User" : entry.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(rankColor)
                                Text("Rank #\(entry.rank)")
                                    .font(.headline)
                                    .foregroundColor(rankColor)
                            }
                            
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("\(entry.totalPoints) Points")
                                    .font(.headline)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("User Profile")
                }
                
                // Activity Breakdown Section
                Section {
                    ActivityStatRow(
                        icon: "exclamationmark.triangle.fill",
                        label: "Damage Records",
                        count: entry.activityStats.damageRecords,
                        points: entry.activityStats.damageRecords * 100,
                        color: .orange
                    )
                    
                    ActivityStatRow(
                        icon: "arrow.uturn.backward.circle.fill",
                        label: "Return Operations",
                        count: entry.activityStats.returnOperations,
                        points: entry.activityStats.returnOperations * 80,
                        color: .purple
                    )
                    
                    ActivityStatRow(
                        icon: "arrow.right.circle.fill",
                        label: "Check Out Operations",
                        count: entry.activityStats.checkOutOperations,
                        points: entry.activityStats.checkOutOperations * 60,
                        color: .blue
                    )
                    
                    ActivityStatRow(
                        icon: "briefcase.fill",
                        label: "Office Operations",
                        count: entry.activityStats.officeOperations,
                        points: entry.activityStats.officeOperations * 40,
                        color: .indigo
                    )
                    
                    ActivityStatRow(
                        icon: "car.fill",
                        label: "Vehicle Records",
                        count: entry.activityStats.vehicleRecords,
                        points: entry.activityStats.vehicleRecords * 20,
                        color: .green
                    )
                } header: {
                    Text("Activity Breakdown")
                } footer: {
                    Text("Total Activities: \(entry.activityStats.totalActivities)")
                }
                
                // Summary Section
                Section {
                    HStack {
                        Text("Total Activities")
                        Spacer()
                        Text("\(entry.activityStats.totalActivities)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Average Points per Activity")
                        Spacer()
                        Text(String(format: "%.1f", entry.activityStats.totalActivities > 0 ? Double(entry.totalPoints) / Double(entry.activityStats.totalActivities) : 0))
                            .fontWeight(.semibold)
                    }
                } header: {
                    Text("Summary")
                }
            }
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .blue
        }
    }
}

