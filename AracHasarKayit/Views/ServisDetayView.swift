import SwiftUI

struct ServisDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State var servis: Servis
    @State private var duzenlemeGoster = false
    @State private var silmeOnayiGoster = false
    @Environment(\.dismiss) var dismiss
    
    var guncelServis: Servis {
        viewModel.servisler.first(where: { $0.id == servis.id }) ?? servis
    }
    
    var body: some View {
        List {
            // Durum kartı
            Section {
                VStack(spacing: 16) {
                    Image(systemName: guncelServis.durum.icon)
                        .font(.system(size: 50))
                        .foregroundColor(Color(uiColor: guncelServis.durum.renk))
                    
                    Text(guncelServis.durum.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Color(uiColor: guncelServis.durum.renk))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Araç bilgileri
            Section("Araç Bilgileri") {
                HStack {
                    Label("Plaka", systemImage: "number.square.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(guncelServis.aracPlaka)
                        .fontWeight(.semibold)
                }
                
                if let arac = viewModel.araclar.first(where: { $0.id == guncelServis.aracId }) {
                    HStack {
                        Label("Marka/Model", systemImage: "car.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(arac.marka) \(arac.model)")
                            .fontWeight(.semibold)
                    }
                }
            }
            
            // Service Information
            Section("Service Information") {
                HStack {
                    Label("Service Company", systemImage: "building.2.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(guncelServis.servisFirmaAdi)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Send Date", systemImage: "calendar")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(guncelServis.gonderilmeTarihi, style: .date)
                        .fontWeight(.semibold)
                }
                
                if let teslimTarihi = guncelServis.teslimTarihi {
                    HStack {
                        Label("Delivery Date", systemImage: "calendar.badge.checkmark")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(teslimTarihi, style: .date)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            // Service Reasons
            if !guncelServis.servisNedenleri.isEmpty {
                Section("Service Reasons") {
                    ForEach(guncelServis.servisNedenleri, id: \.self) { neden in
                        HStack {
                            Image(systemName: neden.icon)
                                .foregroundColor(.blue)
                            Text(neden.rawValue)
                        }
                    }
                }
            }
            
            // Açıklama
            if !guncelServis.aciklama.isEmpty {
                Section("Açıklama") {
                    Text(guncelServis.aciklama)
                        .font(.body)
                }
            }
            
            // Tehlikeli işlemler
            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Servis Kaydını Sil", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Servis Detayları")
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
                ServisEkleView(duzenlenecekServis: guncelServis)
            }
        }
        .alert("Servis Kaydını Sil", isPresented: $silmeOnayiGoster) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                viewModel.servisSil(guncelServis)
                dismiss()
            }
        } message: {
            Text("Bu servis kaydını silmek istediğinizden emin misiniz?")
        }
        .onAppear {
            servis = guncelServis
        }
    }
}
