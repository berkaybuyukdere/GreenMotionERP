import SwiftUI

struct AracListesiView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Binding var navigateToVehicleId: UUID?
    @State private var aramaMetni = ""
    @State private var yeniAracGoster = false
    @State private var filtreGoster = false
    @State private var seciliKategoriler: Set<String> = []
    @State private var sortOption: SortOption = .dateNewest
    @State private var damageFilter: DamageFilter = .all
    @State private var navigateToVehicle: Arac?
    @State private var shouldNavigate = false
    
    enum SortOption: String, CaseIterable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case plateAZ = "Plate A-Z"
        case plateZA = "Plate Z-A"
        case brandAZ = "Brand A-Z"
    }
    
    enum DamageFilter: String, CaseIterable {
        case all = "All Vehicles"
        case withDamage = "With Damage"
        case noDamage = "No Damage"
    }
    
    private var kategoriFiltreli: [Arac] {
        if seciliKategoriler.isEmpty { return viewModel.araclar }
        return viewModel.araclar.filter { seciliKategoriler.contains($0.kategori) }
    }
    
    private var damageFiltered: [Arac] {
        let kaynak = kategoriFiltreli
        switch damageFilter {
        case .all:
            return kaynak
        case .withDamage:
            return kaynak.filter { !$0.hasarKayitlari.isEmpty }
        case .noDamage:
            return kaynak.filter { $0.hasarKayitlari.isEmpty }
        }
    }
    
    @State private var aramaSonuclari: [Arac] = []
    @State private var aramaYapiliyor = false
    
    private var aramaFiltreli: [Arac] {
        let kaynak = damageFiltered
        let q = aramaMetni.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if q.isEmpty { 
            return kaynak 
        }
        
        // Use cached search results for better performance
        if !aramaSonuclari.isEmpty {
            return aramaSonuclari
        }
        
        return kaynak
    }
    
    private func performSearch() {
        let q = aramaMetni.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if q.isEmpty {
            DispatchQueue.main.async {
                self.aramaSonuclari = []
                self.aramaYapiliyor = false
            }
            return
        }
        
        aramaYapiliyor = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let kaynak = self.damageFiltered
            let results = kaynak.filter { arac in
                if arac.plaka.localizedCaseInsensitiveContains(q) { return true }
                if arac.marka.localizedCaseInsensitiveContains(q) { return true }
                if arac.model.localizedCaseInsensitiveContains(q) { return true }
                if arac.hasarKayitlari.contains(where: { $0.resKodu.localizedCaseInsensitiveContains(q) }) { return true }
                return false
            }
            
            DispatchQueue.main.async {
                self.aramaSonuclari = results
                self.aramaYapiliyor = false
            }
        }
    }
    
    private var sortedVehicles: [Arac] {
        let kaynak = aramaFiltreli
        switch sortOption {
        case .dateNewest:
            // Sort by ID (newer first) - UUID as proxy for insertion order
            return kaynak.sorted(by: { $0.id.uuidString > $1.id.uuidString })
        case .dateOldest:
            // Sort by ID (older first)
            return kaynak.sorted(by: { $0.id.uuidString < $1.id.uuidString })
        case .plateAZ:
            return kaynak.sorted(by: { $0.plaka < $1.plaka })
        case .plateZA:
            return kaynak.sorted(by: { $0.plaka > $1.plaka })
        case .brandAZ:
            return kaynak.sorted(by: { $0.marka < $1.marka })
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.araclar.isEmpty {
                    BosDurumView(yeniAracGoster: $yeniAracGoster)
                } else {
                    VStack(spacing: 0) {
                        if !seciliKategoriler.isEmpty {
                            SeciliKategoriEtiketleriView(seciliKategoriler: $seciliKategoriler)
                        }
                        
                        List {
                            ForEach(sortedVehicles) { arac in
                                NavigationLink(destination: AracDetayView(arac: arac)) {
                                    ModernAracSatirView(arac: arac)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .background(
                            NavigationLink(
                                destination: navigateToVehicle.map { AracDetayView(arac: $0) },
                                isActive: $shouldNavigate,
                                label: { EmptyView() }
                            )
                            .hidden()
                        )
                    }
                    .searchable(text: $aramaMetni, prompt: "Search by plate, brand, model...")
                    .onChange(of: aramaMetni) { _ in
                        performSearch()
                    }
                }
            }
            .navigationTitle("Araçlar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        // Damage Filter
                        Menu {
                            ForEach(DamageFilter.allCases, id: \.self) { filter in
                                Button {
                                    damageFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.rawValue)
                                        if damageFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: damageFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .foregroundColor(damageFilter == .all ? .blue : .orange)
                        }
                        
                        // Sort Menu
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button { filtreGoster = true } label: {
                            Image(systemName: seciliKategoriler.isEmpty ? "slider.horizontal.3" : "slider.horizontal.3")
                                .foregroundColor(seciliKategoriler.isEmpty ? .blue : .orange)
                        }
                        Button { yeniAracGoster = true } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $yeniAracGoster) {
                NavigationView { ManuelAracEkleView() }
            }
            .sheet(isPresented: $filtreGoster) {
                NavigationView {
                    KategoriFiltreView(seciliKategoriler: $seciliKategoriler, tumKategoriler: viewModel.kategoriler)
                }
            }
            .onChange(of: navigateToVehicleId) { vehicleId in
                if let vehicleId = vehicleId,
                   let vehicle = viewModel.araclar.first(where: { $0.id == vehicleId }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        navigateToVehicle = vehicle
                        shouldNavigate = true
                        // Reset the navigation trigger
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigateToVehicleId = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Satır (Row) Görünümü
struct ModernAracSatirView: View {
    let arac: Arac
    
    private var sonHasar: HasarKaydi? {
        arac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(arac.plakaFormatli)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(arac.marka) \(arac.model)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Responsive badges with wrapping
                HStack(spacing: 6) {
                    // Category badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "tag.fill").font(.system(size: 9))
                        Text(arac.kategori).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)

                    // Spare key badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill").font(.system(size: 9))
                        Text("\(arac.spareKeyCount)").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)

                    // Vignette badge (compact)
                    if arac.vignetteVar {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                            Text("Vig").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            Spacer()
            
            // Hasar durumu rozeti - Sadece hasar varsa göster
            if let last = sonHasar {
                if last.durum == .done {
                    DurumRozeti(title: "Done", color: .green, icon: "checkmark.circle.fill")
                } else {
                    DurumRozeti(title: "Progress", color: .orange, icon: "clock.fill")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DurumRozeti: View {
    let title: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - Boş Durum
private struct BosDurumView: View {
    @Binding var yeniAracGoster: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Henüz Araç Yok")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Plaka tarayarak veya manuel olarak araç ekleyin")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                yeniAracGoster = true
            } label: {
                Label("Araç Ekle", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
    }
}

// MARK: - Seçili Kategori Etiketleri
private struct SeciliKategoriEtiketleriView: View {
    @Binding var seciliKategoriler: Set<String>
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(seciliKategoriler).sorted(), id: \.self) { kategori in
                    HStack(spacing: 4) {
                        Text(kategori).font(.caption).fontWeight(.semibold)
                        Button {
                            seciliKategoriler.remove(kategori)
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                
                Button {
                    seciliKategoriler.removeAll()
                } label: {
                    Text("Tümünü Temizle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.gray.opacity(0.1))
    }
}

// MARK: - Kategori Filtre View (Missing type fixed by including it here)
struct KategoriFiltreView: View {
    @Binding var seciliKategoriler: Set<String>
    let tumKategoriler: [String]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Section("Kategoriler") {
                ForEach(tumKategoriler.sorted(), id: \.self) { kategori in
                    Button {
                        toggle(kategori)
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                            Text(kategori)
                                .foregroundColor(.primary)
                            Spacer()
                            if seciliKategoriler.contains(kategori) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle").foregroundColor(Color.gray)
                            }
                        }
                    }
                }
            }
            
            if !seciliKategoriler.isEmpty {
                Section {
                    Button(role: .destructive) {
                        seciliKategoriler.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Filtreyi Temizle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Filtrele")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Bitti") { dismiss() }
            }
        }
    }
    
    private func toggle(_ kategori: String) {
        if seciliKategoriler.contains(kategori) {
            seciliKategoriler.remove(kategori)
        } else {
            seciliKategoriler.insert(kategori)
        }
    }
}
