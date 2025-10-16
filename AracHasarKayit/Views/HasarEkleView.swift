import SwiftUI

struct HasarEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let aracId: UUID
    
    @State private var tarih = Date()
    @State private var handoverTarihi = Date()
    @State private var resKodu = ""
    @State private var km = ""
    @State private var fotograflar: [UIImage] = []
    @State private var durum: HasarDurum = .inProgress
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }
    
    var body: some View {
        Form {
            Section("Hasar Bilgileri") {
                DatePicker("Tarih", selection: $tarih, displayedComponents: .date)
                DatePicker("Teslim Tarihi", selection: $handoverTarihi, displayedComponents: .date)
                
                HStack {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(.blue)
                    TextField("RES Kodu", text: $resKodu)
                }
                
                HStack {
                    Image(systemName: "gauge.medium.badge.plus")
                        .foregroundColor(.blue)
                    TextField("Kilometre", text: $km)
                        .keyboardType(.numberPad)
                }
                
                Picker("Status", selection: $durum) {
                    Text("In Progress").tag(HasarDurum.inProgress)
                    Text("Done").tag(HasarDurum.done)
                }
                .pickerStyle(.segmented)
            }
            
            Section("Fotoğraflar") {
                if !fotograflar.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(fotograflar.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: fotograflar[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Button {
                                        fotograflar.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                
                Button {
                    showImagePicker = true
                } label: {
                    Label("Fotoğraf Ekle", systemImage: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                }
            }
            
            Section {
                Button {
                    kaydet()
                } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                            Text("Yükleniyor...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Kaydet")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(resKodu.isEmpty || km.isEmpty || isUploading)
            }
        }
        .navigationTitle("Hasar Ekle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $fotograflar)
        }
    }
    
    func kaydet() {
        guard let kmValue = Int(km) else { return }
        
        isUploading = true
        uploadedPhotoURLs = []
        
        let group = DispatchGroup()
        
        for foto in fotograflar {
            group.enter()
            let path = "hasar_fotograflari/\(UUID().uuidString).jpg"
            FirebaseImageManager.shared.uploadImage(foto, path: path) { url, error in
                if let url = url {
                    uploadedPhotoURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Clean RES code to prevent duplication
            let cleanResKodu = resKodu.trimmingCharacters(in: .whitespaces)
            
            let yeniHasar = HasarKaydi(
                tarih: tarih,
                handoverTarihi: handoverTarihi,
                resKodu: cleanResKodu,
                km: kmValue,
                fotograflar: uploadedPhotoURLs,
                durum: durum
            )
            
            viewModel.hasarEkle(aracId: aracId, hasar: yeniHasar)
            isUploading = false
            dismiss()
        }
    }
}
