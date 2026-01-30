import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var seciliActivity: Activity?
    @State private var detayGoster = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var selectedOfficeOperation: OfficeOperation?
    @State private var navigateToOfficeOperation = false
    
    var filtreliActivities: [Activity] {
        let allActivities = viewModel.activities
        guard !aramaMetni.isEmpty else {
            return allActivities
        }
        
        let searchText = aramaMetni.lowercased()
        return allActivities.filter { activity in
            activity.aciklama.lowercased().contains(searchText) ||
            (activity.aracPlaka?.lowercased().contains(searchText) ?? false) ||
            (activity.kullaniciAdi?.lowercased().contains(searchText) ?? false) ||
            (activity.kullaniciEmail?.lowercased().contains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Aktivite Geçmişi".localized)
                .sheet(isPresented: $detayGoster) {
                    if let activity = seciliActivity {
                        ActivityDetayView(activity: activity)
                    }
                }
                .background(
                    NavigationLink(
                        destination: selectedArac.map { AracDetayView(arac: $0) },
                        isActive: $navigateToVehicleDetail,
                        label: { EmptyView() }
                    )
                )
                .background(
                    NavigationLink(
                        destination: selectedOfficeOperation.map { operation in
                            OfficeOperationDetailViewWrapper(operation: operation)
                                .environmentObject(viewModel)
                        },
                        isActive: $navigateToOfficeOperation,
                        label: { EmptyView() }
                    )
                )
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
                if viewModel.activities.isEmpty {
            emptyStateView
        } else {
            activitiesListView
        }
    }
    
    private var emptyStateView: some View {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Henüz Aktivite Yok".localized)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Araç ve hasar kayıtlarınız burada görünecek".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
    }
    
    private var activitiesListView: some View {
                    List {
                        ForEach(gruplananActivities.keys.sorted(by: >), id: \.self) { tarih in
                            Section(tarihBasligi(tarih)) {
                                ForEach(gruplananActivities[tarih] ?? []) { activity in
                                    ActivitySatirView(activity: activity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                navigateToActivityDetail(activity)
                                        }
                                }
                            }
                        }
                    }
                    .searchable(text: $aramaMetni, prompt: "Aktivite ara...")
                }
    
    private func navigateToActivityDetail(_ activity: Activity) {
        // Check if it's an office operation
        if activity.tip == .officeOperation, let operationId = activity.officeOperationId {
            if let operation = viewModel.officeOperations.first(where: { $0.id == operationId }) {
                selectedOfficeOperation = operation
                navigateToOfficeOperation = true
                return
            }
        }
        
        // Otherwise, show activity detail sheet or navigate to vehicle
        if let plate = activity.aracPlaka {
            if let arac = viewModel.araclar.first(where: { $0.plaka == plate || $0.plakaFormatli == plate }) {
                selectedArac = arac
                navigateToVehicleDetail = true
                return
            }
        }
        
        // Fallback: show activity detail sheet
        seciliActivity = activity
        detayGoster = true
    }
    
    var gruplananActivities: [String: [Activity]] {
        Dictionary(grouping: filtreliActivities) { activity in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: activity.tarih)
        }
    }
    
    func tarihBasligi(_ tarihStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let tarih = formatter.date(from: tarihStr) else { return tarihStr }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(tarih) {
            return "Today"
        } else if calendar.isDateInYesterday(tarih) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: tarih)
        }
    }
}

struct ActivitySatirView: View {
    let activity: Activity
    
    var body: some View {
        HStack(spacing: 12) {
            // İkon
            Image(systemName: activity.tip.icon)
                .font(.system(size: 20))
                .foregroundColor(activity.tip.color)
                .frame(width: 28, height: 28)
            
            // Bilgiler
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.tip.englishDisplayName)
                        .font(.headline)
                    
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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if let plaka = activity.aracPlaka {
                    HStack(spacing: 4) {
                        Image(systemName: "number.square.fill")
                            .font(.caption2)
                        Text(plaka)
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Zaman
                Text(activity.tarih, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Detay gösterge
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// Aktivite detay görünümü
struct ActivityDetayView: View {
    let activity: Activity
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Ana bilgi
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: activity.tip.icon)
                            .font(.system(size: 50))
                            .foregroundColor(activity.tip.color)
                        
                        Text(activity.tip.rawValue)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(activity.tarih.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                // Plaka bilgisi
                if let plaka = activity.aracPlaka {
                    Section("Araç") {
                        HStack {
                            Image(systemName: "number.square.fill")
                                .foregroundColor(.blue)
                            Text(plaka)
                                .font(.headline)
                        }
                    }
                }
                
                // Açıklama
                Section("Açıklama") {
                    Text(activity.aciklama)
                        .font(.body)
                }
                
                // Kullanıcı bilgisi
                if let kullaniciAdi = activity.kullaniciAdi, !kullaniciAdi.isEmpty {
                    Section("User") {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(kullaniciAdi)
                                .font(.body)
                        }
                    }
                } else if let kullaniciEmail = activity.kullaniciEmail, !kullaniciEmail.isEmpty {
                    Section("User") {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(kullaniciEmail)
                                .font(.body)
                        }
                    }
                }
                
                // Detaylı açıklama
                if let detay = activity.detayliAciklama, !detay.isEmpty {
                    Section("Detaylı Bilgi") {
                        Text(detay)
                            .font(.body)
                    }
                }
            }
            .navigationTitle("Aktivite Detayı".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}
