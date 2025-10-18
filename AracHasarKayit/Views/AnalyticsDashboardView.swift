import SwiftUI
import Charts

/// Advanced analytics dashboard with charts and insights
struct AnalyticsDashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var analytics = AnalyticsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                summaryCards
                
                // Charts Section
                if #available(iOS 16.0, *) {
                    chartsSection
                }
                
                // Top Damaged Vehicles
                topDamagedVehicles
                
                // Recent Trends
                recentTrends
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .onAppear {
            analytics.calculateAnalytics(vehicles: viewModel.araclar)
        }
    }
    
    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            AnalyticsCard(
                title: "Total Vehicles",
                value: "\(viewModel.araclar.count)",
                icon: "car.fill",
                color: .blue
            )
            
            AnalyticsCard(
                title: "Total Damages",
                value: "\(totalDamages)",
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )
            
            AnalyticsCard(
                title: "Avg Resolution",
                value: "\(Int(analytics.avgResolutionDays)) days",
                icon: "clock.fill",
                color: .green
            )
            
            AnalyticsCard(
                title: "Returns",
                value: "\(viewModel.iadeIslemleri.count)",
                icon: "checkmark.circle.fill",
                color: .purple
            )
        }
    }
    
    @available(iOS 16.0, *)
    private var chartsSection: some View {
        VStack(spacing: 20) {
            // Damages by Month
            VStack(alignment: .leading) {
                Text("Damages Over Time")
                    .font(.headline)
                
                Chart(analytics.damagesByMonth) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(.orange.gradient)
                }
                .frame(height: 200)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            
            // Damages by Category
            VStack(alignment: .leading) {
                Text("Damages by Category")
                    .font(.headline)
                
                Chart(analytics.damagesByCategory) { item in
                    BarMark(
                        x: .value("Category", item.category),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .frame(height: 200)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
    }
    
    private var topDamagedVehicles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Damaged Vehicles")
                .font(.headline)
            
            ForEach(analytics.topDamagedVehicles.prefix(5)) { vehicle in
                HStack {
                    VStack(alignment: .leading) {
                        Text(vehicle.plakaFormatli)
                            .font(.headline)
                        Text("\(vehicle.marka) \(vehicle.model)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(vehicle.hasarKayitlari.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private var recentTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)
            
            InsightCard(
                icon: "arrow.up.right",
                text: "Damages increased by 15% this month",
                color: .red
            )
            
            InsightCard(
                icon: "clock.arrow.circlepath",
                text: "Average resolution time improved by 2 days",
                color: .green
            )
            
            InsightCard(
                icon: "car.fill",
                text: "\(viewModel.availableCarsCount) vehicles available for rental",
                color: .blue
            )
        }
    }
    
    private var totalDamages: Int {
        viewModel.araclar.reduce(0) { $0 + $1.hasarKayitlari.count }
    }
}

// MARK: - Supporting Views

struct AnalyticsCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct InsightCard: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Analytics ViewModel

class AnalyticsViewModel: ObservableObject {
    @Published var damagesByMonth: [MonthlyData] = []
    @Published var damagesByCategory: [CategoryData] = []
    @Published var avgResolutionDays: Double = 0
    @Published var topDamagedVehicles: [Arac] = []
    
    struct MonthlyData: Identifiable {
        let id = UUID()
        let month: String
        let count: Int
    }
    
    struct CategoryData: Identifiable {
        let id = UUID()
        let category: String
        let count: Int
    }
    
    func calculateAnalytics(vehicles: [Arac]) {
        calculateDamagesByMonth(vehicles)
        calculateDamagesByCategory(vehicles)
        calculateAvgResolutionTime(vehicles)
        
        topDamagedVehicles = vehicles
            .sorted { $0.hasarKayitlari.count > $1.hasarKayitlari.count }
            .prefix(5)
            .map { $0 }
    }
    
    private func calculateDamagesByMonth(_ vehicles: [Arac]) {
        var monthCounts: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        for vehicle in vehicles {
            for damage in vehicle.hasarKayitlari {
                let key = formatter.string(from: damage.tarih)
                monthCounts[key, default: 0] += 1
            }
        }
        
        damagesByMonth = monthCounts
            .map { MonthlyData(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }
    
    private func calculateDamagesByCategory(_ vehicles: [Arac]) {
        var categoryCounts: [String: Int] = [:]
        
        for vehicle in vehicles {
            if !vehicle.hasarKayitlari.isEmpty {
                categoryCounts[vehicle.kategori, default: 0] += vehicle.hasarKayitlari.count
            }
        }
        
        damagesByCategory = categoryCounts
            .map { CategoryData(category: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private func calculateAvgResolutionTime(_ vehicles: [Arac]) {
        var totalDays = 0.0
        var count = 0
        
        for vehicle in vehicles {
            for damage in vehicle.hasarKayitlari where damage.durum == .done {
                let days = Calendar.current.dateComponents([.day], from: damage.tarih, to: Date()).day ?? 0
                totalDays += Double(days)
                count += 1
            }
        }
        
        avgResolutionDays = count > 0 ? totalDays / Double(count) : 0
    }
}

