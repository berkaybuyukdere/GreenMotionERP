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
                    // Top Statistics - Now Clickable
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: AracListesiView()) {
                            DashboardKart(
                                baslik: "Damaged Cars",
                                deger: "\(viewModel.damagedCarsCount)",
                                ikon: "exclamationmark.triangle.fill",
                                renk: .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: AracListesiView()) {
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
                    
                    // Category Distribution
                    if !viewModel.araclar.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Vehicle Categories")
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
                    .fill(Color(activity.tip.renk).opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: activity.tip.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(activity.tip.renk))
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
