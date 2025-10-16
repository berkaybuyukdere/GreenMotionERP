import SwiftUI

struct AracDuzenleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    
    var body: some View {
        Form {
            VehicleInfoSection(arac: $arac)
            CategorySection(arac: $arac, yeniKategoriGoster: $yeniKategoriGoster, viewModel: viewModel)
            VignetteSection(arac: $arac)
            SpareKeyHeadDocSection(
                arac: $arac,
                showImagePicker: $showImagePicker,
                isUploading: isUploading
            )
            SaveSection(isUploading: isUploading, kaydet: kaydet)
        }
        .navigationTitle("Araç Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") {
                    dismiss()
                }
            }
        }
        .alert("Yeni Kategori", isPresented: $yeniKategoriGoster) {
            TextField("Kategori (A-Z)", text: $yeniKategoriAdi)
            Button("İptal", role: .cancel) {
                yeniKategoriAdi = ""
            }
            Button("Ekle") {
                if !yeniKategoriAdi.isEmpty {
                    let kategori = yeniKategoriAdi.uppercased().prefix(1)
                    viewModel.kategoriEkle(String(kategori))
                    arac.kategori = String(kategori)
                    yeniKategoriAdi = ""
                }
            }
        } message: {
            Text("Yeni bir kategori ekleyin (A-Z arası tek harf)")
        }
        .sheet(isPresented: $showImagePicker) {
            SingleImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { img in
            guard let img = img else { return }
            isUploading = true
            
            let path = "kafa_kagitlari/\(arac.id.uuidString)/head_\(UUID().uuidString).jpg"
            
            FirebaseImageManager.shared.uploadImage(img, path: path) { urlString, error in
                DispatchQueue.main.async {
                    isUploading = false
                    if let urlString = urlString {
                        arac.headDocumentURL = urlString
                        print("✅ Head document uploaded: \(urlString)")
                    } else if let error = error {
                        print("❌ Head document upload failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func kaydet() {
        viewModel.aracGuncelle(arac)
        dismiss()
    }
}

private struct VehicleInfoSection: View {
    @Binding var arac: Arac
    
    var body: some View {
        Section("Araç Bilgileri") {
            HStack {
                Image(systemName: "number.square.fill")
                    .foregroundColor(.blue)
                TextField("Plaka", text: $arac.plaka)
                    .textInputAutocapitalization(.characters)
            }
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Marka", text: $arac.marka)
            }
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.blue)
                TextField("Model", text: $arac.model)
            }
        }
    }
}

private struct CategorySection: View {
    @Binding var arac: Arac
    @Binding var yeniKategoriGoster: Bool
    let viewModel: AracViewModel
    
    var body: some View {
        Section("Kategori") {
            Picker("Kategori", selection: $arac.kategori) {
                ForEach(viewModel.kategoriler, id: \.self) { kategori in
                    Text(kategori).tag(kategori)
                }
            }
            Button {
                yeniKategoriGoster = true
            } label: {
                Label("Yeni Kategori Ekle", systemImage: "plus.circle")
                    .foregroundColor(.blue)
            }
        }
    }
}

private struct VignetteSection: View {
    @Binding var arac: Arac
    
    var body: some View {
        Section("Vignette") {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundColor(.blue)
                Text("Vignette Var mı?")
                Spacer()
                Button {
                    arac.vignetteVar.toggle()
                } label: {
                    Image(systemName: arac.vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(arac.vignetteVar ? .green : .red)
                }
            }
        }
    }
}

private struct SpareKeyHeadDocSection: View {
    @Binding var arac: Arac
    @Binding var showImagePicker: Bool
    let isUploading: Bool
    
    var body: some View {
        Section("Spare Key & Head Document") {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                Stepper("Spare Keys: \(arac.spareKeyCount)", value: $arac.spareKeyCount, in: 0...10)
            }
            
            if let url = arac.headDocumentURL, !url.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Head Document Uploaded")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Remove") {
                        arac.headDocumentURL = nil
                    }
                    .foregroundColor(.red)
                }
            }
            
            Button {
                showImagePicker = true
            } label: {
                HStack {
                    if isUploading {
                        ProgressView()
                        Text("Uploading...")
                    } else {
                        Label("Upload Head Document Photo", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .disabled(isUploading)
        }
    }
}

private struct SaveSection: View {
    let isUploading: Bool
    let kaydet: () -> Void
    
    var body: some View {
        Section {
            Button {
                kaydet()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Değişiklikleri Kaydet")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isUploading)
        }
    }
}
