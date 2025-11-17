import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var seciliActivity: Activity?
    @State private var detayGoster = false
    
    var filtreliActivities: [Activity] {
        if aramaMetni.isEmpty {
            return viewModel.activities
        } else {
            return viewModel.activities.filter { activity in
                activity.aciklama.localizedCaseInsensitiveContains(aramaMetni) ||
                (activity.aracPlaka?.localizedCaseInsensitiveContains(aramaMetni) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.activities.isEmpty {
                    // Boş durum
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Henüz Aktivite Yok")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Araç ve hasar kayıtlarınız burada görünecek")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(gruplananActivities.keys.sorted(by: >), id: \.self) { tarih in
                            Section(tarihBasligi(tarih)) {
                                ForEach(gruplananActivities[tarih] ?? []) { activity in
                                    ActivitySatirView(activity: activity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            seciliActivity = activity
                                            detayGoster = true
                                        }
                                }
                            }
                        }
                    }
                    .searchable(text: $aramaMetni, prompt: "Aktivite ara...")
                }
            }
            .navigationTitle("Aktivite Geçmişi")
            .sheet(isPresented: $detayGoster) {
                if let activity = seciliActivity {
                    ActivityDetayView(activity: activity)
                }
            }
        }
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
            return "Bugün"
        } else if calendar.isDateInYesterday(tarih) {
            return "Dün"
        } else {
            formatter.dateFormat = "d MMMM yyyy"
            formatter.locale = Locale(identifier: "tr_TR")
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
            .navigationTitle("Aktivite Detayı")
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
