import SwiftUI

struct AracDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State var arac: Arac
    @State private var duzenlemeGoster = false
    @State private var hasarEkleGoster = false
    @State private var iadeIslemGoster = false
    @State private var silmeOnayiGoster = false
    
    var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(guncelArac.plakaFormatli)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("\(guncelArac.marka) \(guncelArac.model)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.caption)
                                Text(guncelArac.kategori)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: guncelArac.vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(guncelArac.vignetteVar ? .green : .red)
                                Text("Vignette")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((guncelArac.vignetteVar ? Color.green : Color.red).opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Kayıt Tarihi", systemImage: "calendar")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(guncelArac.kayitTarihi, style: .date)
                            .fontWeight(.semibold)
                    }
                    
                    Button {
                        iadeIslemGoster = true
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text("İade İşlemi Yap")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("İstatistikler") {
                HStack {
                    Label("Toplam Hasar", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(guncelArac.hasarKayitlari.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Servis Kayıtları", systemImage: "wrench.and.screwdriver.fill")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(viewModel.aracServisleri(aracId: guncelArac.id).count)")
                        .fontWeight(.semibold)
                }
            }
            
            Section {
                ForEach(guncelArac.hasarKayitlari) { hasar in
                    NavigationLink(destination: HasarDetayView(hasar: hasar, aracId: guncelArac.id, aracPlaka: guncelArac.plakaFormatli)) {
                        HasarSatirView(hasar: hasar)
                    }
                }
                .onDelete(perform: hasarSil)
                
                Button {
                    hasarEkleGoster = true
                } label: {
                    Label("Hasar Ekle", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            } header: {
                HStack {
                    Text("Hasar Kayıtları")
                    Spacer()
                    Text("\(guncelArac.hasarKayitlari.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Aracı Sil", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Araç Detayları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    duzenlemeGoster = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                }
            }
        }
        .sheet(isPresented: $duzenlemeGoster) {
            NavigationView {
                AracDuzenleView(arac: guncelArac)
            }
        }
        .sheet(isPresented: $hasarEkleGoster) {
            NavigationView {
                HasarEkleView(aracId: guncelArac.id)
            }
        }
        .sheet(isPresented: $iadeIslemGoster) {
            NavigationView {
                IadeIslemView(arac: guncelArac)
            }
        }
        .alert("Aracı Sil", isPresented: $silmeOnayiGoster) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                viewModel.aracSil(guncelArac)
            }
        } message: {
            Text("Bu aracı ve tüm hasar kayıtlarını silmek istediğinizden emin misiniz?")
        }
        .onAppear {
            arac = guncelArac
        }
    }
    
    func hasarSil(at offsets: IndexSet) {
        for index in offsets {
            let hasar = guncelArac.hasarKayitlari[index]
            viewModel.hasarSil(aracId: guncelArac.id, hasarId: hasar.id)
        }
    }
}

struct HasarSatirView: View {
    let hasar: HasarKaydi
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(hasar.resKodu)
                    .font(.headline)
                
                Text("\(hasar.km) km")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label {
                        Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if !hasar.fotograflar.isEmpty {
                        Label("\(hasar.fotograflar.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
