import SwiftUI

struct KategoriAraclarView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let kategori: String
    
    var kategoriAraclari: [Arac] {
        viewModel.araclar.filter { $0.kategori == kategori }
    }
    
    var body: some View {
        List {
            // İstatistikler
            Section {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kategori")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(kategori)
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Toplam Araç")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(kategoriAraclari.count)")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Divider()
                    
                    HStack(spacing: 20) {
                        // Hasarlı
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("\(kategoriAraclari.filter { !$0.hasarKayitlari.isEmpty }.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Text("Hasarlı")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                        
                        // Hasarsız
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("\(kategoriAraclari.filter { $0.hasarKayitlari.isEmpty }.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Hasarsız")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                        
                        // Vignette
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("\(kategoriAraclari.filter { $0.vignetteVar }.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("Vignette")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Araç Listesi
            Section("Araçlar (\(kategoriAraclari.count))") {
                if kategoriAraclari.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Bu kategoride araç yok")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(kategoriAraclari) { arac in
                        NavigationLink(destination: AracDetayView(arac: arac)) {
                            ModernAracSatirView(arac: arac)
                        }
                    }
                }
            }
        }
        .navigationTitle("Kategori \(kategori)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
