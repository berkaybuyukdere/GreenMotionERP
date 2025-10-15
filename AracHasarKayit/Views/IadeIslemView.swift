import SwiftUI
import PhotosUI

struct IadeIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    let arac: Arac
    
    @State private var iadeTarihi = Date()
    @State private var notlar = ""
    @State private var seciliFotograflar: [UIImage] = []
    @State private var galeriAcik = false
    @State private var kayitEdiliyor = false
    @State private var hasarEkleGoster = false
    @State private var kaydedilenIadeId: UUID?
    
    var body: some View {
        Form {
            Section("Araç Bilgileri") {
                HStack {
                    Label("Plaka", systemImage: "number.square.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(arac.plakaFormatli)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Marka/Model", systemImage: "car.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(arac.marka) \(arac.model)")
                        .fontWeight(.semibold)
                }
            }
            
            Section("İade Bilgileri") {
                DatePicker("İade Tarihi", selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
            }
            
            Section("Notlar (Opsiyonel)") {
                TextEditor(text: $notlar)
                    .frame(minHeight: 100)
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
                
                if !seciliFotograflar.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(seciliFotograflar.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(8)
                                        .clipped()
                                    
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
                        }
                        .padding(.vertical, 8)
                    }
                }
            } header: {
                HStack {
                    Text("Fotoğraflar")
                    Spacer()
                    Text("\(seciliFotograflar.count)")
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
                            Text("İade İşlemini Tamamla")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(kayitEdiliyor)
            }
        }
        .navigationTitle("İade İşlemi")
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
        .alert("İade Tamamlandı", isPresented: Binding(
            get: { kaydedilenIadeId != nil },
            set: { if !$0 { kaydedilenIadeId = nil } }
        )) {
            Button("Tamam") {
                dismiss()
            }
            Button("Hasar Ekle") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hasarEkleGoster = true
                }
            }
        } message: {
            Text("İade işlemi başarıyla kaydedildi. Bu araca hasar kaydı eklemek ister misiniz?")
        }
    }
    
    func kaydet() {
        kayitEdiliyor = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var fotografURLleri: [String] = []
            let dispatchGroup = DispatchGroup()
            
            for image in seciliFotograflar {
                dispatchGroup.enter()
                FirebaseImageManager.shared.saveImage(image, withDate: iadeTarihi, isHandover: false) { urlString in
                    if let urlString = urlString {
                        fotografURLleri.append(urlString)
                    }
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                let yeniIade = IadeIslemi(
                    aracId: arac.id,
                    aracPlaka: arac.plakaFormatli,
                    iadeTarihi: iadeTarihi,
                    fotograflar: fotografURLleri,
                    notlar: notlar
                )
                
                viewModel.iadeEkle(yeniIade)
                
                kayitEdiliyor = false
                kaydedilenIadeId = yeniIade.id
            }
        }
    }
}
