import SwiftUI

struct ServisEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    var duzenlenecekServis: Servis?
    
    @State private var seciliAracId: UUID?
    @State private var seciliServisFirmaId: UUID?
    @State private var servisFirmaAdi = ""
    @State private var durum: Servis.ServisDurum = .serviste
    @State private var gonderilmeTarihi = Date()
    @State private var teslimTarihi: Date?
    @State private var teslimTarihiVar = false
    @State private var aciklama = ""
    @State private var seciliNedenler: Set<Servis.ServisNeden> = []
    
    var duzenlemeModuMu: Bool {
        duzenlenecekServis != nil
    }
    
    var body: some View {
        Form {
            // Araç seçimi
            Section("Araç") {
                if viewModel.araclar.isEmpty {
                    Text("Henüz kayıtlı araç yok")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Araç Seçin", selection: $seciliAracId) {
                        Text("Araç seçin").tag(nil as UUID?)
                        ForEach(viewModel.araclar) { arac in
                            Text("\(arac.plakaFormatli) - \(arac.marka) \(arac.model)")
                                .tag(arac.id as UUID?)
                        }
                    }
                }
            }
            
            // Servis firması seçimi
            Section("Servis Firması") {
                if viewModel.servisFirmalari.isEmpty {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.blue)
                        TextField("Servis Firması Adı", text: $servisFirmaAdi)
                    }
                    
                    NavigationLink(destination: ServisFirmalariView()) {
                        Label("Servis Firması Ekle", systemImage: "plus.circle")
                            .foregroundColor(.blue)
                    }
                } else {
                    Picker("Firma Seçin", selection: $seciliServisFirmaId) {
                        Text("Manuel gir").tag(nil as UUID?)
                        ForEach(viewModel.servisFirmalari) { firma in
                            Text(firma.ad).tag(firma.id as UUID?)
                        }
                    }
                    .onChange(of: seciliServisFirmaId) { newValue in
                        if let firmaId = newValue,
                           let firma = viewModel.servisFirmalari.first(where: { $0.id == firmaId }) {
                            servisFirmaAdi = firma.ad
                        }
                    }
                    
                    if seciliServisFirmaId == nil {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.blue)
                            TextField("Servis Firması Adı", text: $servisFirmaAdi)
                        }
                    }
                }
            }
            
            // Servis nedenleri
            Section("Servis Nedenleri") {
                ForEach(Servis.ServisNeden.allCases, id: \.self) { neden in
                    Button {
                        if seciliNedenler.contains(neden) {
                            seciliNedenler.remove(neden)
                        } else {
                            seciliNedenler.insert(neden)
                        }
                    } label: {
                        HStack {
                            Image(systemName: neden.icon)
                                .foregroundColor(.blue)
                            Text(neden.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if seciliNedenler.contains(neden) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            
            // Servis durumu
            Section("Durum") {
                Picker("Servis Durumu", selection: $durum) {
                    ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                        Label(durum.rawValue, systemImage: durum.icon)
                            .tag(durum)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Tarihler
            Section("Tarihler") {
                DatePicker("Gönderilme Tarihi", selection: $gonderilmeTarihi, displayedComponents: [.date])
                
                Toggle("Teslim Tarihi Belirle", isOn: $teslimTarihiVar)
                
                if teslimTarihiVar {
                    DatePicker("Teslim Tarihi", selection: Binding(
                        get: { teslimTarihi ?? Date() },
                        set: { teslimTarihi = $0 }
                    ), displayedComponents: [.date])
                }
            }
            
            // Açıklama
            Section("Açıklama") {
                TextEditor(text: $aciklama)
                    .frame(minHeight: 100)
            }
            
            // Kaydet butonu
            Section {
                Button {
                    kaydet()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(duzenlemeModuMu ? "Güncelle" : "Kaydet")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!formGecerli)
            }
        }
        .navigationTitle(duzenlemeModuMu ? "Servis Düzenle" : "Yeni Servis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if let servis = duzenlenecekServis {
                seciliAracId = servis.aracId
                seciliServisFirmaId = servis.servisFirmaId
                servisFirmaAdi = servis.servisFirmaAdi
                durum = servis.durum
                gonderilmeTarihi = servis.gonderilmeTarihi
                teslimTarihi = servis.teslimTarihi
                teslimTarihiVar = servis.teslimTarihi != nil
                aciklama = servis.aciklama
                seciliNedenler = Set(servis.servisNedenleri)
            }
        }
    }
    
    var formGecerli: Bool {
        seciliAracId != nil && !servisFirmaAdi.isEmpty && !seciliNedenler.isEmpty
    }
    
    func kaydet() {
        guard let aracId = seciliAracId,
              let arac = viewModel.araclar.first(where: { $0.id == aracId }) else { return }
        
        if duzenlemeModuMu, var servis = duzenlenecekServis {
            servis.aracId = aracId
            servis.aracPlaka = arac.plakaFormatli
            servis.servisFirmaId = seciliServisFirmaId
            servis.servisFirmaAdi = servisFirmaAdi
            servis.durum = durum
            servis.gonderilmeTarihi = gonderilmeTarihi
            servis.teslimTarihi = teslimTarihiVar ? teslimTarihi : nil
            servis.aciklama = aciklama
            servis.servisNedenleri = Array(seciliNedenler)
            viewModel.servisGuncelle(servis)
            
            // Show update toast
            ToastManager.shared.show("✓ Service Updated", type: .info)
        } else {
            let yeniServis = Servis(
                aracId: aracId,
                aracPlaka: arac.plakaFormatli,
                servisFirmaId: seciliServisFirmaId,
                servisFirmaAdi: servisFirmaAdi,
                durum: durum,
                gonderilmeTarihi: gonderilmeTarihi,
                aciklama: aciklama,
                servisNedenleri: Array(seciliNedenler)
            )
            viewModel.servisEkle(yeniServis)
            
            // Show success toast
            ToastManager.shared.show("✓ Service Added", type: .success)
        }
        
        dismiss()
    }
}
