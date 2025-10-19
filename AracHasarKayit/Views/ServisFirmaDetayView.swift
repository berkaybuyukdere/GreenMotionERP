import SwiftUI

struct ServisFirmaDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State var firma: ServisFirma
    @State private var duzenlemeGoster = false
    @State private var silmeOnayiGoster = false
    @Environment(\.dismiss) var dismiss
    
    var guncelFirma: ServisFirma {
        viewModel.servisFirmalari.first(where: { $0.id == firma.id }) ?? firma
    }
    
    var firmaServisleri: [Servis] {
        viewModel.servisler.filter { $0.servisFirmaId == firma.id }
    }
    
    var body: some View {
        List {
            // Firma bilgileri
            Section("Firma Bilgileri") {
                HStack {
                    Label("Firma Adı", systemImage: "building.2.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(guncelFirma.ad)
                        .fontWeight(.semibold)
                }
                
                if !guncelFirma.telefon.isEmpty {
                    HStack {
                        Label("Telefon", systemImage: "phone.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Link(guncelFirma.telefon, destination: URL(string: "tel:\(guncelFirma.telefon)")!)
                            .fontWeight(.semibold)
                    }
                }
                
                if !guncelFirma.email.isEmpty {
                    HStack {
                        Label("E-posta", systemImage: "envelope.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Link(guncelFirma.email, destination: URL(string: "mailto:\(guncelFirma.email)")!)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }
                
                if !guncelFirma.adres.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Adres", systemImage: "location.fill")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Text(guncelFirma.adres)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                }
                
                HStack {
                    Label("Kayıt Tarihi", systemImage: "calendar")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(guncelFirma.kayitTarihi, style: .date)
                        .fontWeight(.semibold)
                }
            }
            
            // Notlar
            if !guncelFirma.notlar.isEmpty {
                Section("Notlar") {
                    Text(guncelFirma.notlar)
                        .font(.body)
                }
            }
            
            // Servis geçmişi
            if !firmaServisleri.isEmpty {
                Section("Servis Geçmişi (\(firmaServisleri.count))") {
                    ForEach(firmaServisleri.sorted { $0.gonderilmeTarihi > $1.gonderilmeTarihi }) { servis in
                        NavigationLink(destination: ServisDetayView(servis: servis)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(servis.aracPlaka)
                                    .font(.headline)
                                
                                HStack {
                                    Text(servis.gonderilmeTarihi.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text(servis.durum.rawValue)
                                        .font(.caption)
                                        .foregroundColor(Color(uiColor: servis.durum.renk))
                                }
                            }
                        }
                    }
                }
            }
            
            // Tehlikeli işlemler
            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Firmayı Sil", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Firma Detayları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ❌ CUSTOM BACK BUTTON KALDIRILDI
            
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
                ServisFirmaEkleView(duzenlenecekFirma: guncelFirma)
            }
        }
        .alert("Firmayı Sil", isPresented: $silmeOnayiGoster) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                viewModel.servisFirmaSil(guncelFirma)
                dismiss()
            }
        } message: {
            Text("Bu firmayı silmek istediğinizden emin misiniz?\n\nNot: Firma silinse bile mevcut servis kayıtları etkilenmez.")
        }
        .onAppear {
            firma = guncelFirma
        }
    }
}
