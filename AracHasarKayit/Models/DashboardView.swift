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
    @EnvironmentObject var localization: LocalizationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var navigateToVehicleId: UUID?
    @State private var showParkedCheckoutSheet = false
    
    // Check if current user is superadmin (role-based, no email hardcode)
    private var isAdminUser: Bool {
        authManager.userProfile?.isSuperAdmin == true
    }

    private var activeCountry: Country {
        if let profile = authManager.userProfile {
            if let byFranchise = CountryManager.country(byId: profile.franchiseId) {
                return byFranchise
            }
            if let byCode = CountryManager.country(byCode: profile.countryCode) {
                return byCode
            }
        }
        return UserDefaults.standard.selectedCountry
    }

    private var greetingHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if let profile = authManager.userProfile {
                    Text(String(format: "Hello, %@".localized, profile.displayName))
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 5) {
                    Text(activeCountry.flag)
                        .font(.system(size: 14))
                    Text(viewModel.franchiseName.isEmpty ? activeCountry.name : viewModel.franchiseName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
    
    private var parkedExits: [ExitIslemi] {
        viewModel.exitIslemleri
            .filter { $0.status == .parked }
            .sorted { $0.createdAt > $1.createdAt }
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
                    greetingHeader
                    // Top Statistics - Now Clickable
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: DamageReportsView(selectedMonth: Date()).environmentObject(viewModel)) {
                            DashboardKartWithMetric(
                                baslik: "Today's Damage Reports".localized,
                                deger: "\(viewModel.todayDamageReportsCount)",
                                ikon: "exclamationmark.triangle.fill",
                                renk: .orange,
                                metric: viewModel.damageReportsChangeMetric,
                                sparkData: viewModel.damageSparkline
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
                                baslik: "Today's Check Outs".localized,
                                deger: "\(viewModel.todayExitCount)",
                                ikon: "arrow.right.circle.fill",
                                renk: .blue,
                                sparkData: viewModel.exitSparkline
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
                                baslik: "Today's Returns".localized,
                                deger: "\(viewModel.todayReturnsCount)",
                                ikon: "arrow.uturn.backward.circle.fill",
                                renk: .purple,
                                sparkData: viewModel.returnSparkline
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
                        
                        NavigationLink(destination: OfficeOperationsMainView().environmentObject(viewModel)) {
                            DashboardKart(
                                baslik: "Today's Office Ops".localized,
                                deger: "\(viewModel.todayOfficeOperationsCount)",
                                ikon: "briefcase.fill",
                                renk: .indigo,
                                sparkData: viewModel.officeOpsSparkline
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                AnalyticsManager.shared.trackButtonTap(
                                    action: "view_office_operations",
                                    screen: "dashboard",
                                    buttonLabel: "Office Operations"
                                )
                            }
                        )
                    }
                    .padding(.horizontal)
                    
                    if !parkedExits.isEmpty {
                        Button {
                            showParkedCheckoutSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.purple.opacity(0.18))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "car.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.purple)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Parked Check Outs Waiting".localized)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.purple)
                                    Text(String(format: "%d parked vehicles are waiting for completion".localized, parkedExits.count))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.purple.opacity(0.8))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.purple.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.purple.opacity(0.40), lineWidth: 1.0)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    
                    // Recent Activities
                    if !viewModel.activities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Activities".localized)
                                    .font(.headline)
                                Spacer()
                                NavigationLink(destination: ActivityView()) {
                                    Text("View All".localized)
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
                    
                    // Admin Panel Card (only for superadmin role)
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
                            
                            Text("No Data Yet".localized)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Start adding vehicles and your data will appear here".localized)
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
            .navigationTitle("Dashboard".localized)
            .navigationBarTitleDisplayMode(.inline)
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
                    .environmentObject(localization)
            }
            .sheet(isPresented: $showParkedCheckoutSheet) {
                NavigationView {
                    List {
                        ForEach(parkedExits) { parkedExit in
                            NavigationLink(destination: ExitDetayView(exit: parkedExit).environmentObject(viewModel)) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.18))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Image(systemName: "car.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.purple)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(parkedExit.aracPlaka)
                                            .font(.subheadline.weight(.semibold))
                                        Text(parkedExit.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("Parked".localized)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .navigationTitle("Parked Check Outs".localized)
                    .navigationBarTitleDisplayMode(.inline)
                }
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
                Text("araç".localized)
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
                    
                    if let kullaniciAdi = activity.kullaniciAdi?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !kullaniciAdi.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(kullaniciAdi)
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if let kullaniciEmail = activity.kullaniciEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !kullaniciEmail.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(kullaniciEmail.components(separatedBy: "@").first ?? kullaniciEmail)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(activity.localizedDescription)
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
            return "Just now".localized
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(format: "%d min ago".localized, minutes)
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return String(format: "%d hours ago".localized, hours)
        } else {
            let days = Int(seconds / 86400)
            if days == 1 {
                return "Yesterday".localized
            } else if days < 7 {
                return String(format: "%d days ago".localized, days)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
}

// MARK: - Mini Sparkline Chart (iOS Stocks style)
struct SparklineChart: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = normalised(in: geo.size)
            ZStack {
                // Fill gradient under the line
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        p.addLine(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Line
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalised(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let minV = data.min() ?? 0
        let maxV = data.max() ?? 1
        let span = maxV - minV == 0 ? 1.0 : maxV - minV
        return data.enumerated().map { idx, v in
            let x = CGFloat(idx) / CGFloat(data.count - 1) * size.width
            let y = size.height - CGFloat((v - minV) / span) * size.height * 0.85 - size.height * 0.08
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Dashboard Card
struct DashboardKart: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    var sparkData: [Double] = []
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ikon)
                    .font(.title2)
                    .foregroundColor(renk)
                Spacer()
            }

            if sparkData.count > 1 {
                SparklineChart(data: sparkData, color: renk)
                    .frame(height: 36)
            }
            
            Text(deger)
                .font(.system(size: 30, weight: .bold))
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
    var sparkData: [Double] = []
    @Environment(\.colorScheme) var colorScheme
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if sparkData.count > 1 {
                SparklineChart(data: sparkData, color: renk)
                    .frame(height: 36)
            }
            
            Text(deger)
                .font(.system(size: 30, weight: .bold))
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
                Text("Admin Panel".localized)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Firebase Connection Tests".localized)
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
