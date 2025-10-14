import SwiftUI

struct ServisView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var yeniServisGoster = false
    @State private var durumFiltresi: Servis.ServisDurum?
    @State private var servisFirmalarGoster = false
    
    var filtreliServisler: [Servis] {
        var servisler = viewModel.servisler
        
        // Durum filtreleme
        if let durum = durumFiltresi {
            servisler = servisler.filter { $0.durum == durum }
        }
        
        // Arama filtreleme
        if !aramaMetni.isEmpty {
            servisler = servisler.filter { servis in
                servis.aracPlaka.localizedCaseInsensitiveContains(aramaMetni) ||
                servis.servisFirmaAdi.localizedCaseInsensitiveContains(aramaMetni) ||
                servis.aciklama.localizedCaseInsensitiveContains(aramaMetni)
            }
        }
        
        return servisler.sorted { $0.gonderilmeTarihi > $1.gonderilmeTarihi }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.servisler.isEmpty {
                    // BoÅŸ durum
                    VStack(spacing: 20) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("HenÃ¼z Servis KaydÄ± Yok")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("AraÃ§larÄ±nÄ±zÄ±n servis kayÄ±tlarÄ± burada gÃ¶rÃ¼necek")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            yeniServisGoster = true
                        } label: {
                            Label("Servis KaydÄ± Ekle", systemImage: "plus.circle.fill")
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
                        // Ä°statistik kartÄ±
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                StatKart(
                                    baslik: "Toplam Servis",
                                    deger: "\(viewModel.servisler.count)",
                                    ikon: "wrench.and.screwdriver.fill",
                                    renk: .blue
                                )
                                
                                StatKart(
                                    baslik: "Serviste",
                                    deger: "\(viewModel.aktifServisSayisi)",
                                    ikon: "clock.fill",
                                    renk: .orange
                                )
                                
                                StatKart(
                                    baslik: "TamamlandÄ±",
                                    deger: "\(viewModel.tamamlananServisSayisi)",
                                    ikon: "checkmark.circle.fill",
                                    renk: .green
                                )
                                
                                StatKart(
                                    baslik: "Ä°ptal",
                                    deger: "\(viewModel.iptalServisSayisi)",
                                    ikon: "xmark.circle.fill",
                                    renk: .red
                                )
                            }
                            .padding()
                        }
                        
                        // Durum filtreleri
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                DurumFiltreBadge(
                                    baslik: "TÃ¼mÃ¼",
                                    secili: durumFiltresi == nil
                                ) {
                                    durumFiltresi = nil
                                }
                                
                                ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                                    DurumFiltreBadge(
                                        baslik: durum.rawValue,
                                        secili: durumFiltresi == durum,
                                        renk: Color(durum.renk)
                                    ) {
                                        durumFiltresi = durum
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        
                        Divider()
                        
                        // Servis listesi
                        List {
                            ForEach(filtreliServisler) { servis in
                                NavigationLink(destination: ServisDetayView(servis: servis)) {
                                    ServisSatirView(servis: servis)
                                }
                            }
                            .onDelete(perform: servisSil)
                        }
                        .searchable(text: $aramaMetni, prompt: "Servis ara...")
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Servis KayÄ±tlarÄ±")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            yeniServisGoster = true
                        } label: {
                            Label("Yeni Servis Ekle", systemImage: "plus.circle")
                        }
                        
                        if !viewModel.servisler.isEmpty {
                            Divider()
                            
                            Button {
                                exportServislerCSV()
                            } label: {
                                Label("CSV Ä°ndir", systemImage: "doc.text")
                            }
                            
                            Button {
                                exportServislerXLSX()
                            } label: {
                                Label("Excel Ä°ndir", systemImage: "tablecells")
                            }
                            
                            Button {
                                exportServislerPDF()
                            } label: {
                                Label("PDF Ä°ndir", systemImage: "doc.richtext")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            servisFirmalarGoster = true
                        } label: {
                            Label("Servis FirmalarÄ±", systemImage: "building.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
                
                if !viewModel.servisler.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $yeniServisGoster) {
                NavigationView {
                    ServisEkleView()
                }
            }
            .sheet(isPresented: $servisFirmalarGoster) {
                NavigationView {
                    ServisFirmalariView()
                }
            }
        }
    }
    
    func servisSil(at offsets: IndexSet) {
        for index in offsets {
            let servis = filtreliServisler[index]
            viewModel.servisSil(servis)
        }
    }
    
    // Export fonksiyonlarÄ±
    func exportServislerCSV() {
        ServisExportManager.shared.exportToCSV(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func exportServislerXLSX() {
        ServisExportManager.shared.exportToXLSX(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func exportServislerPDF() {
        ServisExportManager.shared.exportToPDF(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func getRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .filter { $0.isKeyWindow }
            .first?.rootViewController
    }
}
