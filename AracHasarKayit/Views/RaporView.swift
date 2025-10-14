import SwiftUI

struct RaporView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var seciliTarihTipi: TarihTipi = .gunluk
    @State private var baslangicTarihi = Date()
    @State private var bitisTarihi = Date()
    @State private var ozelTarihSecimi = false
    
    enum TarihTipi: String, CaseIterable {
        case gunluk = "Günlük"
        case haftalik = "Haftalık"
        case aylik = "Aylık"
        case ozel = "Özel Tarih"
        
        var icon: String {
            switch self {
            case .gunluk: return "calendar"
            case .haftalik: return "calendar.badge.clock"
            case .aylik: return "calendar.circle"
            case .ozel: return "calendar.badge.plus"
            }
        }
    }
    
    var filtreLenmisIadeler: [IadeIslemi] {
        let calendar = Calendar.current
        let bugun = Date()
        
        switch seciliTarihTipi {
        case .gunluk:
            return viewModel.iadeIslemleri.filter { iade in
                calendar.isDate(iade.iadeTarihi, inSameDayAs: bugun)
            }
        case .haftalik:
            let haftaOnce = calendar.date(byAdding: .day, value: -7, to: bugun)!
            return viewModel.iadeIslemleri.filter { iade in
                iade.iadeTarihi >= haftaOnce && iade.iadeTarihi <= bugun
            }
        case .aylik:
            let ayOnce = calendar.date(byAdding: .month, value: -1, to: bugun)!
            return viewModel.iadeIslemleri.filter { iade in
                iade.iadeTarihi >= ayOnce && iade.iadeTarihi <= bugun
            }
        case .ozel:
            return viewModel.iadeIslemleri.filter { iade in
                iade.iadeTarihi >= baslangicTarihi && iade.iadeTarihi <= bitisTarihi
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tarih seçimi
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TarihTipi.allCases, id: \.self) { tip in
                            Button {
                                seciliTarihTipi = tip
                                if tip == .ozel {
                                    ozelTarihSecimi = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: tip.icon)
                                        .font(.caption)
                                    Text(tip.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(seciliTarihTipi == tip ? .semibold : .regular)
                                }
                                .foregroundColor(seciliTarihTipi == tip ? .white : .blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(seciliTarihTipi == tip ? Color.blue : Color.blue.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                if filtreLenmisIadeler.isEmpty {
                    // Boş durum
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Bu Dönemde İade Yok")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Seçilen tarih aralığında iade işlemi bulunamadı")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        // Özet istatistikler
                        Section {
                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Toplam İade")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(filtreLenmisIadeler.count)")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.purple)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("Fotoğraf")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(filtreLenmisIadeler.flatMap { $0.fotograflar }.count)")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Divider()
                                
                                HStack(spacing: 16) {
                                    Button {
                                        exportPDF()
                                    } label: {
                                        Label("PDF İndir", systemImage: "doc.richtext")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.red)
                                            .cornerRadius(10)
                                    }
                                    
                                    Button {
                                        exportXLSX()
                                    } label: {
                                        Label("Excel İndir", systemImage: "tablecells")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.green)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // İade listesi
                        Section("İade İşlemleri") {
                            ForEach(filtreLenmisIadeler.sorted { $0.iadeTarihi > $1.iadeTarihi }) { iade in
                                NavigationLink(destination: IadeDetayView(iade: iade)) {
                                    IadeSatirView(iade: iade)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Raporlar")
        }
        .sheet(isPresented: $ozelTarihSecimi) {
            NavigationView {
                Form {
                    Section("Tarih Aralığı") {
                        DatePicker("Başlangıç", selection: $baslangicTarihi, displayedComponents: .date)
                        DatePicker("Bitiş", selection: $bitisTarihi, displayedComponents: .date)
                    }
                    
                    Section {
                        Button {
                            ozelTarihSecimi = false
                        } label: {
                            Text("Uygula")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle("Özel Tarih Seç")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("İptal") {
                            seciliTarihTipi = .gunluk
                            ozelTarihSecimi = false
                        }
                    }
                }
            }
        }
    }
    
    func exportPDF() {
        IadeRaporManager.shared.exportToPDF(iadeler: filtreLenmisIadeler, viewController: getRootViewController())
    }
    
    func exportXLSX() {
        IadeRaporManager.shared.exportToXLSX(iadeler: filtreLenmisIadeler, viewController: getRootViewController())
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

struct IadeSatirView: View {
    let iade: IadeIslemi
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3)
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(iade.aracPlaka)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !iade.notlar.isEmpty {
                    Text(iade.notlar)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    Label {
                        Text(iade.iadeTarihi.formatted(date: .abbreviated, time: .shortened))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if !iade.fotograflar.isEmpty {
                        Label("\(iade.fotograflar.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
