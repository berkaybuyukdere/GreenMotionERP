import SwiftUI

struct AracListesiView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var yeniAracGoster = false
    @State private var filtreGoster = false
    @State private var seciliKategoriler: Set<String> = []
    
    private var kategoriFiltreli: [Arac] {
        if seciliKategoriler.isEmpty { return viewModel.araclar }
        return viewModel.araclar.filter { seciliKategoriler.contains($0.kategori) }
    }
    
    private var aramaFiltreli: [Arac] {
        let kaynak = kategoriFiltreli
        let q = aramaMetni.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return kaynak }
        return kaynak.filter { arac in
            if arac.plaka.localizedCaseInsensitiveContains(q) { return true }
            if arac.marka.localizedCaseInsensitiveContains(q) { return true }
            if arac.model.localizedCaseInsensitiveContains(q) { return true }
            if arac.hasarKayitlari.contains(where: { $0.resKodu.localizedCaseInsensitiveContains(q) }) { return true }
            return false
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
                            ForEach(aramaFiltreli) { arac in
                                NavigationLink(destination: AracDetayView(arac: arac)) {
                                    ModernAracSatirView(arac: arac)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                    .searchable(text: $aramaMetni, prompt: "Plaka, marka, model veya RES kodu...")
                }
            }
            .navigationTitle("Araçlar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button { filtreGoster = true } label: {
                            Image(systemName: seciliKategoriler.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(arac.plakaFormatli)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("\(arac.marka) \(arac.model)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    // Kategori etiketi
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill").font(.caption2)
                        Text(arac.kategori).font(.caption).fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // Yedek anahtar etiketi
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill").font(.caption2)
                        Text("\(arac.spareKeyCount)").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)

                    // Vignette etiketi
                    if arac.vignetteVar {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.caption2)
                            Text("Vignette").font(.caption).fontWeight(.semibold)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
            
            // Hasar durumu rozeti - Sadece hasar varsa göster
            if let last = sonHasar {
                if last.durum == .done {
                    DurumRozeti(title: "Done", color: .green, icon: "checkmark.circle.fill")
                } else {
                    DurumRozeti(title: "In Progress", color: .yellow, icon: "questionmark.circle.fill")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct DurumRozeti: View {
    let title: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.caption).fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(12)
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
                                Image(systemName: "circle").foregroundColor(.gray)
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
