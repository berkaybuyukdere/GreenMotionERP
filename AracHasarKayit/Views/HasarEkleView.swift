import SwiftUI
import PhotosUI

struct HasarEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let aracId: UUID
    var duzenlenecekHasar: HasarKaydi?
    
    @State private var resKodu = ""
    @State private var km = ""
    @State private var tarih = Date()
    @State private var handoverTarihi = Date()
    @State private var seciliFotograflar: [UIImage] = []
    @State private var kayitliFotografAdlari: [String] = []
    @State private var galeriAcik = false
    @State private var kayitEdiliyor = false
    
    var duzenlemeModuMu: Bool {
        duzenlenecekHasar != nil
    }
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var body: some View {
        Form {
            Section("Hasar Bilgileri") {
                // RES Kodu
                VStack(alignment: .leading, spacing: 8) {
                    Text("RES Kodu")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("RES-")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                        
                        TextField("Kod (max 15 karakter)", text: $resKodu)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: resKodu) { newValue in
                                // Max 15 karakter sınırı
                                if newValue.count > 15 {
                                    resKodu = String(newValue.prefix(15))
                                }
                            }
                    }
                }
                
                // KM
                VStack(alignment: .leading, spacing: 8) {
                    Text("Araç KM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("KM", text: $km)
                        .keyboardType(.numberPad)
                }
                
                DatePicker("Tarih", selection: $tarih, displayedComponents: .date)
                
                DatePicker("Handover Tarihi", selection: $handoverTarihi, displayedComponents: .date)
            }
            
            // Fotoğraflar
            Section {
                Button {
                    galeriAcik = true
                } label: {
                    Label("Fotoğraf Ekle", systemImage: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                }
                .disabled(false)
                
                if !seciliFotograflar.isEmpty || !kayitliFotografAdlari.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(seciliFotograflar.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    VStack(spacing: 4) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .clipped()
                                        
                                        Text(index == 0 ? "HANDOVER" : "RETURN")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                    
                                    Button {
                                        seciliFotograflar.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.red))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }
                            
                            ForEach(Array(kayitliFotografAdlari.enumerated()), id: \.offset) { index, urlString in
                                AsyncImageView(urlString: urlString) { image in
                                    ZStack(alignment: .topTrailing) {
                                        VStack(spacing: 4) {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .cornerRadius(8)
                                                .clipped()
                                            
                                            Text(index == 0 ? "HANDOVER" : "RETURN")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                        }
                                        
                                        Button {
                                            kayitliFotografAdlari.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.red))
                                        }
                                        .offset(x: 5, y: -5)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            } header: {
                HStack {
                    Text("Fotoğraflar")
                    Spacer()
                    Text("\(seciliFotograflar.count + kayitliFotografAdlari.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button {
                    kaydet()
                } label: {
                    if kayitEdiliyor {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Kaydediliyor...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(duzenlemeModuMu ? "Güncelle" : "Kaydet")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(kayitEdiliyor || resKodu.isEmpty || km.isEmpty)
            }
        }
        .navigationTitle(duzenlemeModuMu ? "Hasar Düzenle" : "Yeni Hasar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") {
                    dismiss()
                }
                .disabled(kayitEdiliyor)
            }
        }
        .sheet(isPresented: $galeriAcik) {
            ImagePicker(selectedImages: $seciliFotograflar)
        }
        .onAppear {
            if let hasar = duzenlenecekHasar {
                resKodu = hasar.resKodu
                km = "\(hasar.km)"
                tarih = hasar.tarih
                handoverTarihi = hasar.handoverTarihi
                kayitliFotografAdlari = hasar.fotograflar
            }
            // guncelKM kaldırıldı - kullanıcı manuel girecek
        }
    }
    
    func kaydet() {
        guard let kmValue = Int(km) else { return }
        
        kayitEdiliyor = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var tumFotografURLleri: [String] = kayitliFotografAdlari
            let dispatchGroup = DispatchGroup()

            // ✅ Asenkron sırayı düzeltmek için indeksle birlikte topla
            var uploadedWithIndex: [(index: Int, url: String)] = []

            for (index, image) in seciliFotograflar.enumerated() {
                dispatchGroup.enter()
                let fotoTarihi = index == 0 ? handoverTarihi : Date()
                
                FirebaseImageManager.shared.saveImage(image, withDate: fotoTarihi, isHandover: index == 0) { urlString in
                    if let urlString = urlString {
                        uploadedWithIndex.append((index: index, url: urlString))
                    }
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                // ✅ Yüklenenleri indekslerine göre sırala (0 her zaman handover)
                let sortedNewUrls = uploadedWithIndex
                    .sorted(by: { $0.index < $1.index })
                    .map { $0.url }
                
                // Var olan kayıtlı fotoğraflar varsa, kendi sırasını korur.
                // Yeni eklenenleri sonuna, doğru sırada ekliyoruz.
                tumFotografURLleri.append(contentsOf: sortedNewUrls)

                if duzenlemeModuMu, var hasar = duzenlenecekHasar {
                    let silinecekler = hasar.fotograflar.filter { !kayitliFotografAdlari.contains($0) }
                    FirebaseImageManager.shared.deleteImages(silinecekler)
                    
                    hasar.resKodu = "RES-\(resKodu)"
                    hasar.km = kmValue
                    hasar.tarih = tarih
                    hasar.handoverTarihi = handoverTarihi
                    hasar.fotograflar = tumFotografURLleri
                    viewModel.hasarGuncelle(aracId: aracId, hasar: hasar)
                } else {
                    let yeniHasar = HasarKaydi(
                        tarih: tarih,
                        handoverTarihi: handoverTarihi,
                        resKodu: "RES-\(resKodu)",
                        km: kmValue,
                        fotograflar: tumFotografURLleri
                    )
                    viewModel.hasarEkle(aracId: aracId, hasar: yeniHasar)
                }
                
                kayitEdiliyor = false
                dismiss()
            }
        }
    }
}
