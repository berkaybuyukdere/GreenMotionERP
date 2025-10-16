import SwiftUI

struct HasarDetayView: View {
    let hasar: HasarKaydi
    let aracId: UUID
    let aracPlaka: String
    @EnvironmentObject var viewModel: AracViewModel
    @State private var fotografGoster = false
    @State private var seciliFotografURL: String?
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var body: some View {
        List {
            // Hasar Bilgileri
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text(hasar.resKodu)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Bilgiler
            Section("Bilgiler") {
                HStack {
                    Label("RES Kodu", systemImage: "number.circle.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hasar.resKodu)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("KM", systemImage: "gauge.medium")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(hasar.km) km")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Tarih", systemImage: "calendar")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hasar.tarih.formatted(date: .long, time: .omitted))
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Handover Tarihi", systemImage: "calendar.badge.clock")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hasar.handoverTarihi.formatted(date: .long, time: .omitted))
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Status", systemImage: hasar.durum == .done ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hasar.durum.rawValue)
                        .fontWeight(.semibold)
                        .foregroundColor(hasar.durum == .done ? .green : .orange)
                }
            }
            
            // Status Değiştirme
            Section {
                Button {
                    toggleDamageStatus()
                } label: {
                    HStack {
                        Image(systemName: hasar.durum == .done ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill")
                        Text(hasar.durum == .done ? "Mark as In Progress" : "Mark as Done")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasar.durum == .done ? Color.orange : Color.green)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Fotoğraflar
            if !hasar.fotograflar.isEmpty {
                Section("Fotoğraflar (\(hasar.fotograflar.count))") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(hasar.fotograflar.enumerated()), id: \.offset) { index, urlString in
                                AsyncImageView(urlString: urlString) { image in
                                    Button {
                                        seciliFotografURL = urlString
                                        fotografGoster = true
                                    } label: {
                                        VStack(spacing: 4) {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 120, height: 120)
                                                .cornerRadius(12)
                                                .clipped()
                                            
                                            Text(index == 0 ? "HANDOVER" : "RETURN")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // PDF Oluştur Butonu
                    Button {
                        generatePDF()
                    } label: {
                        HStack {
                            if pdfOlusturuluyor {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("PDF Oluşturuluyor...")
                            } else {
                                Image(systemName: "doc.fill")
                                Text("Hasar Raporu PDF Oluştur")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .disabled(pdfOlusturuluyor)
                }
            }
        }
        .navigationTitle("Hasar Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $fotografGoster) {
            if let urlString = seciliFotografURL {
                FotografPreviewView(urlString: urlString)
            }
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
    
    func toggleDamageStatus() {
        var updatedHasar = hasar
        updatedHasar.durum = hasar.durum == .done ? .inProgress : .done
        viewModel.hasarGuncelle(aracId: aracId, hasar: updatedHasar)
        HapticManager.shared.success()
    }
    
    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        
        PDFGenerator.shared.generateHasarPDF(
            hasar: hasar,
            aracPlaka: aracPlaka,
            aracKM: hasar.km
        ) { url in
            DispatchQueue.main.async {
                pdfOlusturuluyor = false
                if let url = url {
                    pdfURL = url
                    pdfPaylas = true
                }
            }
        }
    }
}
