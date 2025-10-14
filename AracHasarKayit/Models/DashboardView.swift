import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showLogoutConfirmation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Üst istatistikler
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        DashboardKart(
                            baslik: "DAMAGED CARS",
                            deger: "\(viewModel.damagedCarsCount)",
                            ikon: "exclamationmark.triangle.fill",
                            renk: .orange
                        )
                        
                        DashboardKart(
                            baslik: "AVAILABLE CARS",
                            deger: "\(viewModel.availableCarsCount)",
                            ikon: "checkmark.circle.fill",
                            renk: .green
                        )
                        
                        DashboardKart(
                            baslik: "İADE İŞLEMİ",
                            deger: "\(viewModel.toplamIadeSayisi)",
                            ikon: "arrow.uturn.backward.circle.fill",
                            renk: .purple
                        )
                        
                        DashboardKart(
                            baslik: "SERVİS",
                            deger: "\(viewModel.aktifServisSayisi)",
                            ikon: "wrench.and.screwdriver.fill",
                            renk: .blue
                        )
                    }
                    .padding(.horizontal)
                    
                    // Servis Durumu Grafiği
                    if !viewModel.servisler.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Servis Durumu")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ServisDurumBar(
                                    baslik: "Serviste",
                                    sayi: viewModel.aktifServisSayisi,
                                    toplam: viewModel.servisler.count,
                                    renk: .orange
                                )
                                
                                ServisDurumBar(
                                    baslik: "Tamamlandı",
                                    sayi: viewModel.tamamlananServisSayisi,
                                    toplam: viewModel.servisler.count,
                                    renk: .green
                                )
                                
                                ServisDurumBar(
                                    baslik: "İptal",
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
                    
                    // Kategori Dağılımı - MODERN TASARIM
                    if !viewModel.araclar.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Araç Kategorileri")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            let kategoriDagilim = Dictionary(grouping: viewModel.araclar, by: { $0.kategori })
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(kategoriDagilim.keys.sorted(), id: \.self) { kategori in
                                        NavigationLink(destination: KategoriAraclarView(kategori: kategori)) {
                                            ModernKategoriKart(
                                                kategori: kategori,
                                                aracSayisi: kategoriDagilim[kategori]?.count ?? 0
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Son Aktiviteler - İCONLAR İYİLEŞTİRİLDİ
                    if !viewModel.activities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Son Aktiviteler")
                                    .font(.headline)
                                Spacer()
                                NavigationLink(destination: ActivityView()) {
                                    Text("Tümünü Gör")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                ForEach(viewModel.activities.prefix(5)) { activity in
                                    ModernActivityRow(activity: activity)
                                    
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
                    
                    // Boş durum
                    if viewModel.araclar.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("Henüz Veri Yok")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Araç eklemeye başlayın ve verileriniz burada görünecek")
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
                        if let user = authManager.currentUser {
                            Text(user.email ?? "Kullanıcı")
                                .font(.caption)
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Çıkış Yap", isPresented: $showLogoutConfirmation) {
                Button("İptal", role: .cancel) { }
                Button("Çıkış Yap", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Çıkış yapmak istediğinizden emin misiniz?")
            }
        }
    }
}

// MODERN KATEGORİ KARTI - Dashboard kartlarıyla benzer stil
struct ModernKategoriKart: View {
    let kategori: String
    let aracSayisi: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // İkon
            HStack {
                Image(systemName: "car.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Spacer()
            }
            
            // Kategori İsmi
            Text(kategori)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
            
            // Araç Sayısı
            HStack(spacing: 4) {
                Text("\(aracSayisi)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("araç")
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

// MODERN AKTİVİTE SATIRI
struct ModernActivityRow: View {
    let activity: Activity
    
    var body: some View {
        HStack(spacing: 14) {
            // Sol tarafta büyük ve belirgin ikon
            ZStack {
                Circle()
                    .fill(Color(activity.tip.renk).opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: activity.tip.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(activity.tip.renk))
            }
            
            // Bilgiler
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.tip.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(activity.aciklama)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Zaman
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
