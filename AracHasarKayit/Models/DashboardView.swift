import SwiftUI
import Charts

// Wrapper for OfficeOperationDetailView to use in NavigationLink
struct OfficeOperationDetailViewWrapper: View {
    let operation: OfficeOperation
    @EnvironmentObject var viewModel: AracViewModel
    
    var body: some View {
        OfficeOperationDetailView(operation: operation)
            .environmentObject(viewModel)
    }
}

struct DashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var navigateToVehicleId: UUID?
    
    // Check if current user is admin
    private var isAdminUser: Bool {
        guard let email = authManager.currentUser?.email?.lowercased() else { return false }
        return email == "admin@gmail.com"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                // Track screen view
                Color.clear
                    .onAppear {
                        AnalyticsManager.shared.trackScreenView("Dashboard", screenClass: "DashboardView")
                    }
                    .onDisappear {
                        AnalyticsManager.shared.trackScreenExit("Dashboard")
                    }
                VStack(spacing: 20) {
                    // Top Statistics - Now Clickable
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: DamageReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                            DashboardKartWithMetric(
                                baslik: "Today's Damage Reports",
                                deger: "\(viewModel.todayDamageReportsCount)",
                                ikon: "exclamationmark.triangle.fill",
                                renk: .orange,
                                metric: viewModel.damageReportsChangeMetric
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                AnalyticsManager.shared.trackButtonTap(
                                    action: "view_damage_reports",
                                    screen: "dashboard",
                                    buttonLabel: "Today's Damage Reports"
                                )
                            }
                        )

                        NavigationLink(destination: ExitReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                            DashboardKart(
                                baslik: "Check Out Count",
                                deger: "\(viewModel.exitIslemleri.count)",
                                ikon: "arrow.right.circle.fill",
                                renk: .blue
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                AnalyticsManager.shared.trackButtonTap(
                                    action: "view_exit_reports",
                                    screen: "dashboard",
                                    buttonLabel: "Check Out Count"
                                )
                            }
                        )

                        NavigationLink(destination: ReturnReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                            DashboardKart(
                                baslik: "Today's Returns",
                                deger: "\(viewModel.todayReturnsCount)",
                                ikon: "arrow.uturn.backward.circle.fill",
                                renk: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                AnalyticsManager.shared.trackButtonTap(
                                    action: "view_return_reports",
                                    screen: "dashboard",
                                    buttonLabel: "Today's Returns"
                                )
                            }
                        )
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
                    
                    // Admin Panel Card (only for admin@gmail.com)
                    if isAdminUser {
                        NavigationLink(destination: AdminPanelView()
                            .environmentObject(viewModel)
                            .environmentObject(authManager)) {
                            AdminPanelCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
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
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(authManager)
            }
            .background(
                Group {
                NavigationLink(
                    destination: selectedArac.map { AracDetayView(arac: $0) },
                    isActive: $navigateToVehicleDetail,
                    label: { EmptyView() }
                )
                    
                    if let operation = selectedOfficeOperation {
                        NavigationLink(
                            destination: OfficeOperationDetailViewWrapper(operation: operation)
                                .environmentObject(viewModel),
                            isActive: $navigateToOfficeOperation,
                            label: { EmptyView() }
                        )
                    }
                }
            )
        }
    }
    
    // MARK: - Navigation Helper
    @State private var selectedOfficeOperation: OfficeOperation?
    @State private var navigateToOfficeOperation = false
    
    private func navigateToActivity(_ activity: Activity) {
        // Check if it's an office operation
        if activity.tip == .officeOperation, let operationId = activity.officeOperationId {
            if let operation = viewModel.officeOperations.first(where: { $0.id == operationId }) {
                selectedOfficeOperation = operation
                navigateToOfficeOperation = true
                return
            }
        }
        
        // Otherwise, find the related vehicle
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
                    Text(activity.tip.englishDisplayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let kullaniciAdi = activity.kullaniciAdi, !kullaniciAdi.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(kullaniciAdi)
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if let kullaniciEmail = activity.kullaniciEmail, !kullaniciEmail.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(kullaniciEmail.components(separatedBy: "@").first ?? kullaniciEmail)
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
                Text(formatRelativeTime(activity.tarih))
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
    
    private func formatRelativeTime(_ date: Date) -> String {
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
            if days == 1 {
                return "Yesterday"
            } else if days < 7 {
                return "\(days)d ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
}

// MARK: - Dashboard Card
struct DashboardKart: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
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
                .foregroundColor(.primary)
            
            Text(baslik)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Dashboard Card with Metric
struct DashboardKartWithMetric: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    let metric: String
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2)
                    .foregroundColor(renk)
                Spacer()
                if !metric.isEmpty && metric != "0" {
                    Text(metric)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(metric.hasPrefix("+") ? .green : metric.hasPrefix("-") ? .red : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((metric.hasPrefix("+") ? Color.green : metric.hasPrefix("-") ? Color.red : Color.gray).opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Text(deger)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text(baslik)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
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

// MARK: - Admin Panel Card
struct AdminPanelCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Panel")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Firebase Connection Tests")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                )
        )
        .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
