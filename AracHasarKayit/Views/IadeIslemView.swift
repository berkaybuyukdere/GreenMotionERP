import SwiftUI

struct IadeIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    
    @State private var iadeTarihi = Date()
    @State private var notlar = ""
    @State private var fotograflar: [UIImage] = []
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    
    var body: some View {
        Form {
            Section("İade Bilgileri") {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.purple)
                    Text("Araç")
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("İade Tarihi", selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
            }
            
            Section("Notlar") {
                TextEditor(text: $notlar)
                    .frame(height: 100)
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
                            Text("İade İşlemini Tamamla")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isUploading)
            }
        }
        .navigationTitle("İade İşlemi")
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
        isUploading = true
        uploadedPhotoURLs = []
        
        let group = DispatchGroup()
        
        for foto in fotograflar {
            group.enter()
            let path = "iade_fotograflari/\(UUID().uuidString).jpg"
            FirebaseImageManager.shared.uploadImage(foto, path: path) { url, error in
                if let url = url {
                    uploadedPhotoURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let yeniIade = IadeIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                iadeTarihi: iadeTarihi,
                fotograflar: uploadedPhotoURLs,
                notlar: notlar
            )
            
            viewModel.iadeEkle(yeniIade)
            isUploading = false
            dismiss()
        }
    }
}
