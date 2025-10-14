import SwiftUI

struct AracListesiView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var yeniAracGoster = false
    @State private var filtreGoster = false
    @State private var seciliKategoriler: Set<String> = []
    
    var filtreliAraclar: [Arac] {
        var araclar = viewModel.araclar
        
        // Kategori filtresi
        if !seciliKategoriler.isEmpty {
            araclar = araclar.filter { seciliKategoriler.contains($0.kategori) }
        }
        
        // Arama filtresi
        if !aramaMetni.isEmpty {
            araclar = araclar.filter { arac in
                arac.plaka.localizedCaseInsensitiveContains(aramaMetni) ||
                arac.marka.localizedCaseInsensitiveContains(aramaMetni) ||
                arac.model.localizedCaseInsensitiveContains(aramaMetni) ||
                arac.hasarKayitlari.contains(where: { hasar in
                    hasar.resKodu.localizedCaseInsensitiveContains(aramaMetni)
                })
            }
        }
        
        return araclar
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.araclar.isEmpty {
                    // Boş durum
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
                } else {
                    VStack(spacing: 0) {
                        // Kategori Filtreleri (eğer filtre seçilmişse)
                        if !seciliKategoriler.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(seciliKategoriler).sorted(), id: \.self) { kategori in
                                        HStack(spacing: 4) {
                                            Text(kategori)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            
                                            Button {
                                                seciliKategoriler.remove(kategori)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
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
                        
                        List {
                            ForEach(filtreliAraclar) { arac in
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
                        // Filtre Butonu
                        Button {
                            filtreGoster = true
                        } label: {
                            Image(systemName: seciliKategoriler.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .foregroundColor(seciliKategoriler.isEmpty ? .blue : .orange)
                        }
                        
                        // Ekle Butonu
                        Button {
                            yeniAracGoster = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $yeniAracGoster) {
                NavigationView {
                    ManuelAracEkleView()
                }
            }
            .sheet(isPresented: $filtreGoster) {
                NavigationView {
                    KategoriFiltreView(seciliKategoriler: $seciliKategoriler)
                }
            }
        }
    }
}

// MODERN ARAÇ SATIR GÖRÜNÜMÜ
struct ModernAracSatirView: View {
    let arac: Arac
    
    var body: some View {
        HStack(spacing: 16) {
            // Araç İkonu
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            // Bilgiler
            VStack(alignment: .leading, spacing: 6) {
                // Plaka
                Text(arac.plakaFormatli)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                // Marka Model
                Text("\(arac.marka) \(arac.model)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // İkonlar
                HStack(spacing: 12) {
                    // Kategori
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(arac.kategori)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Vignette
                    if arac.vignetteVar {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text("Vignette")
                                .font(.caption)
                                .fontWeight(.semibold)
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
            
            // Hasar Badge
            if !arac.hasarKayitlari.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    
                    Text("\(arac.hasarKayitlari.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
    }
}

// KATEGORİ FİLTRE VIEW
struct KategoriFiltreView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var seciliKategoriler: Set<String>
    
    var body: some View {
        List {
            Section("Kategoriler") {
                ForEach(viewModel.kategoriler.sorted(), id: \.self) { kategori in
                    Button {
                        if seciliKategoriler.contains(kategori) {
                            seciliKategoriler.remove(kategori)
                        } else {
                            seciliKategoriler.insert(kategori)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                            
                            Text(kategori)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if seciliKategoriler.contains(kategori) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
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
                Button("Bitti") {
                    dismiss()
                }
            }
        }
    }
}
