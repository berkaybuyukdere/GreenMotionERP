import SwiftUI

struct ManuelAracEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var plaka: String
    @State private var marka = ""
    @State private var model = ""
    @State private var kategori = "A"
    @State private var vignetteVar = false
    @State private var spareKeyCount = "0"
    @State private var headDocumentURL: String?
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    
    init(plaka: String = "") {
        _plaka = State(initialValue: plaka)
    }
    
    var body: some View {
        Form {
            VehicleInfoSection(plaka: $plaka, marka: $marka, model: $model)
            CategorySection(kategori: $kategori, yeniKategoriGoster: $yeniKategoriGoster, viewModel: viewModel)
            VignetteSection(vignetteVar: $vignetteVar)
            SpareKeyHeadDocSection(
                spareKeyCount: $spareKeyCount,
                headDocumentURL: $headDocumentURL,
                showImagePicker: $showImagePicker,
                isUploading: isUploading
            )
            SaveSection(isUploading: isUploading, kaydet: kaydet)
        }
        .navigationTitle("Araç Ekle")
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
                    self.kategori = String(kategori)
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
            
            let vehicleKey = plaka.isEmpty ? UUID().uuidString : plaka.replacingOccurrences(of: " ", with: "")
            let path = "kafa_kagitlari/\(vehicleKey)/head_\(UUID().uuidString).jpg"
            
            FirebaseImageManager.shared.uploadImage(img, path: path) { urlString, error in
                DispatchQueue.main.async {
                    isUploading = false
                    if let urlString = urlString {
                        headDocumentURL = urlString
                        print("✅ Head document uploaded: \(urlString)")
                    } else if let error = error {
                        print("❌ Head document upload failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func kaydet() {
        let temizPlaka = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        let spareKeys = Int(spareKeyCount) ?? 0
        
        let yeniArac = Arac(
            plaka: temizPlaka,
            marka: marka,
            model: model,
            kategori: kategori,
            vignetteVar: vignetteVar,
            spareKeyCount: spareKeys,
            headDocumentURL: headDocumentURL
        )
        
        viewModel.aracEkle(yeniArac)
        dismiss()
    }
}

private struct VehicleInfoSection: View {
    @Binding var plaka: String
    @Binding var marka: String
    @Binding var model: String
    
    var body: some View {
        Section("Araç Bilgileri") {
            HStack {
                Image(systemName: "number.square.fill")
                    .foregroundColor(.blue)
                TextField("Plaka", text: $plaka)
                    .textInputAutocapitalization(.characters)
            }
            
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Marka", text: $marka)
            }
            
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.blue)
                TextField("Model", text: $model)
            }
        }
    }
}

private struct CategorySection: View {
    @Binding var kategori: String
    @Binding var yeniKategoriGoster: Bool
    let viewModel: AracViewModel
    
    var body: some View {
        Section("Kategori") {
            Picker("Kategori", selection: $kategori) {
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
    @Binding var vignetteVar: Bool
    
    var body: some View {
        Section("Vignette") {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundColor(.blue)
                Text("Vignette Var mı?")
                Spacer()
                Button {
                    vignetteVar.toggle()
                } label: {
                    Image(systemName: vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(vignetteVar ? .green : .red)
                }
            }
        }
    }
}

private struct SpareKeyHeadDocSection: View {
    @Binding var spareKeyCount: String
    @Binding var headDocumentURL: String?
    @Binding var showImagePicker: Bool
    let isUploading: Bool
    
    var body: some View {
        Section("Spare Key & Head Document") {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                TextField("Spare Key Count", text: $spareKeyCount)
                    .keyboardType(.numberPad)
            }
            
            if let url = headDocumentURL, !url.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Head Document Uploaded")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Remove") {
                        headDocumentURL = nil
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
                    Text("Kaydet")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isUploading)
        }
    }
}
