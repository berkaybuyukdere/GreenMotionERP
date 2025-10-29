import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var presenceManager = UserPresenceManager.shared
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var showLogoutConfirmation = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var selectedUser: UserPresence?
    @State private var showUserDetail = false
    @State private var navigateToVehicleId: UUID?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Top Statistics - Now Clickable
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: AracListesiView(navigateToVehicleId: $navigateToVehicleId)) {
                            DashboardKart(
                                baslik: "Damaged Cars",
                                deger: "\(viewModel.damagedCarsCount)",
                                ikon: "exclamationmark.triangle.fill",
                                renk: .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: AracListesiView(navigateToVehicleId: $navigateToVehicleId)) {
                            DashboardKart(
                                baslik: "Available Cars",
                                deger: "\(viewModel.availableCarsCount)",
                                ikon: "checkmark.circle.fill",
                                renk: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: ReturnReportsView().environmentObject(viewModel)) {
                            DashboardKart(
                                baslik: "Return Reports",
                                deger: "\(viewModel.toplamIadeSayisi)",
                                ikon: "arrow.uturn.backward.circle.fill",
                                renk: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: ServisView()) {
                            DashboardKart(
                                baslik: "Service",
                                deger: "\(viewModel.aktifServisSayisi)",
                                ikon: "wrench.and.screwdriver.fill",
                                renk: .blue
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal)
                    
                    // Service Status Chart
                    if !viewModel.servisler.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Service Status")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ServisDurumBar(
                                    baslik: "In Service",
                                    sayi: viewModel.aktifServisSayisi,
                                    toplam: viewModel.servisler.count,
                                    renk: .orange
                                )
                                
                                ServisDurumBar(
                                    baslik: "Completed",
                                    sayi: viewModel.tamamlananServisSayisi,
                                    toplam: viewModel.servisler.count,
                                    renk: .green
                                )
                                
                                ServisDurumBar(
                                    baslik: "Cancelled",
                                    sayi: viewModel.iptalServisSayisi,
                                    toplam: viewModel.servisler.count,
                                    renk: .red
                                )
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Shuttle Status Widget
                    if !shuttleManager.activeDriverLocations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Shuttle Status")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(shuttleManager.activeDriverLocations, id: \.driverUID) { driver in
                                ShuttleDriverWidget(location: driver)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Recent Activities
                    if !viewModel.activities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Activities")
                                    .font(.headline)
                                Spacer()
                                NavigationLink(destination: ActivityView()) {
                                    Text("View All")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                ForEach(viewModel.activities.prefix(5)) { activity in
                                    Button {
                                        // Navigate to activity detail
                                        navigateToActivity(activity)
                                    } label: {
                                        ModernActivityRow(activity: activity)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if activity.id != viewModel.activities.prefix(5).last?.id {
                                        Divider()
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Online Users Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Online Users")
                                .font(.headline)
                            Spacer()
                            Text("\(presenceManager.onlineUserCount) online, \(presenceManager.offlineUserCount) offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        OnlineUsersSection(
                            presenceManager: presenceManager,
                            selectedUser: $selectedUser,
                            showUserDetail: $showUserDetail
                        )
                    }
                    
                    // Empty State
                    if viewModel.araclar.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("No Data Yet")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Start adding vehicles and your data will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 60)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let profile = authManager.userProfile {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.fullName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(profile.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let user = authManager.currentUser {
                            Text(user.email ?? "User")
                                .font(.caption)
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .background(
                NavigationLink(
                    destination: selectedArac.map { AracDetayView(arac: $0) },
                    isActive: $navigateToVehicleDetail,
                    label: { EmptyView() }
                )
            )
            .sheet(item: $selectedUser) { user in
                UserDetailSheet(user: user)
            }
            .onAppear {
                // Presence monitoring is now handled by AuthenticationManager
            }
        }
    }
    
    // MARK: - Navigation Helper
    private func navigateToActivity(_ activity: Activity) {
        // Find the related vehicle
        if let plate = activity.aracPlaka {
            if let arac = viewModel.araclar.first(where: { $0.plaka == plate || $0.plakaFormatli == plate }) {
                selectedArac = arac
                navigateToVehicleDetail = true
            }
        }
    }
}

// MARK: - Modern Category Card
struct ModernKategoriKart: View {
    let kategori: String
    let aracSayisi: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Spacer()
            }
            
            Text(kategori)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
            
            HStack(spacing: 4) {
                Text("\(aracSayisi)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("vehicles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 100, height: 110)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Modern Activity Row
struct ModernActivityRow: View {
    let activity: Activity
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(activity.tip.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: activity.tip.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(activity.tip.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.tip.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let kullaniciAdi = activity.kullaniciAdi {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(kullaniciAdi)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(activity.aciklama)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.tarih, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dashboard Card
struct DashboardKart: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2)
                    .foregroundColor(renk)
                Spacer()
            }
            
            Text(deger)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(renk)
            
            Text(baslik)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(renk.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Service Status Bar
struct ServisDurumBar: View {
    let baslik: String
    let sayi: Int
    let toplam: Int
    let renk: Color
    
    var yuzde: Double {
        toplam > 0 ? Double(sayi) / Double(toplam) : 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(baslik)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(sayi)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(renk)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(renk)
                        .frame(width: geometry.size.width * yuzde, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Online Users Section

struct OnlineUsersSection: View {
    @ObservedObject var presenceManager: UserPresenceManager
    @Binding var selectedUser: UserPresence?
    @Binding var showUserDetail: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presenceManager.onlineUsers.isEmpty && presenceManager.offlineUsers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No users yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Online Users
                        ForEach(presenceManager.onlineUsers) { user in
                            UserCard(user: user, selectedUser: $selectedUser)
                        }
                        
                        // Offline Users (max 5)
                        ForEach(presenceManager.offlineUsers.prefix(5)) { user in
                            UserCard(user: user, selectedUser: $selectedUser)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - User Card

struct UserCard: View {
    let user: UserPresence
    @Binding var selectedUser: UserPresence?
    
    // Calculate actual online status based on last seen
    var isActuallyOnline: Bool {
        let timeSinceLastSeen = Date().timeIntervalSince(user.lastSeen)
        return user.status == .online && timeSinceLastSeen <= 300 // 5 minutes
    }
    
    var statusColor: Color {
        isActuallyOnline ? .green : .gray
    }
    
    var body: some View {
        Button {
            selectedUser = user
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Status indicator based on actual online status
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    
                    Text(user.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                
                if !isActuallyOnline {
                    Text(user.lastSeenText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Active now")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(12)
            .frame(width: 140)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Detail Sheet

struct UserDetailSheet: View {
    let user: UserPresence
    @Environment(\.dismiss) var dismiss
    
    var statusColor: Color {
        switch user.status {
        case .online: return .green
        case .offline: return .gray
        case .away: return .orange
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 16) {
                        // Status Circle
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .fill(statusColor)
                                .frame(width: 20, height: 20)
                        }
                        
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(user.status.rawValue)
                            .font(.subheadline)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(statusColor.opacity(0.1))
                            .cornerRadius(20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                
                Section("User Information") {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                        Text("Email")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(user.email)
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Last Seen")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(user.lastSeenText)
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.purple)
                        Text("Exact Time")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(user.lastSeen, style: .time)
                            .font(.subheadline)
                    }
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
}

// MARK: - Shuttle Driver Widget

struct ShuttleDriverWidget: View {
    let location: ShuttleLocation
    
    var body: some View {
        HStack(spacing: 12) {
            // Driver icon
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "bus.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(location.driverName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let speed = location.speed, speed > 0 {
                    HStack(spacing: 16) {
                        Label("\(Int(speed)) km/h", systemImage: "speedometer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
