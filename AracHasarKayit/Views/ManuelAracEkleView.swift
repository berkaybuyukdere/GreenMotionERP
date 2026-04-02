import SwiftUI
import FirebaseAuth

struct ManuelAracEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var plaka: String
    @State private var marka = ""
    @State private var model = ""
    @State private var kategori = ""
    @State private var vignetteVar = false
    @State private var spareKeyCount = "0"
    @State private var headDocumentURL: String?
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var isSaving = false
    
    init(plaka: String = "") {
        _plaka = State(initialValue: plaka)
    }
    
    private var canSave: Bool {
        !isUploading &&
        !isSaving &&
        !plaka.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !marka.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !kategori.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            SaveSection(canSave: canSave, kaydet: kaydet)
        }
        .navigationTitle("Add Vehicle".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) {
                    dismiss()
                }
            }
        }
        .alert("New Category".localized, isPresented: $yeniKategoriGoster) {
            TextField("Category Name".localized, text: $yeniKategoriAdi)
            Button("Cancel".localized, role: .cancel) {
                yeniKategoriAdi = ""
            }
            Button("Add".localized) {
                let kategori = VehicleCategory.normalizeName(yeniKategoriAdi)
                if !kategori.isEmpty {
                    viewModel.kategoriEkle(kategori)
                    self.kategori = kategori
                    yeniKategoriAdi = ""
                }
            }
        } message: {
            Text("Add a new category for your franchise".localized)
        }
        .sheet(isPresented: $showImagePicker) {
            SingleImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { img in
            guard let img = img else { return }
            isUploading = true
            
            let vehicleKey = plaka.isEmpty ? UUID().uuidString : plaka.replacingOccurrences(of: " ", with: "")
            let path = "kafa_kagitlari/\(vehicleKey)/head_\(UUID().uuidString).jpg"
            
            CachedImageManager.shared.uploadImage(img, path: path) { urlString, error in
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
        guard canSave else {
            if isUploading {
                ToastManager.shared.show("Please wait for photo upload to finish.".localized, type: .warning)
            }
            return
        }
        isSaving = true
        
        let temizPlaka = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        let spareKeys = Int(spareKeyCount) ?? 0
        
        let currentUserId = Auth.auth().currentUser?.uid
        let yeniArac = Arac(
            plaka: temizPlaka,
            marka: marka,
            model: model,
            kategori: kategori,
            vignetteVar: vignetteVar,
            spareKeyCount: spareKeys,
            headDocumentURL: headDocumentURL,
            createdBy: currentUserId
        )
        
        viewModel.aracEkle(yeniArac)
        
        ToastManager.shared.show("✓ Vehicle Added: \(plaka)", type: .success)
        
        isSaving = false
        dismiss()
    }
}

private struct VehicleInfoSection: View {
    @Binding var plaka: String
    @Binding var marka: String
    @Binding var model: String
    @State private var showBrandPicker = false
    @State private var showModelPicker = false
    @State private var availableModels: [String] = []
    
    private var platePlaceholder: String {
        let countryId = UserDefaults.standard.selectedCountryId
        let example = CountryManager.plateExamples(for: countryId).first ?? "AB1234"
        return String(format: "Plate example: %@".localized, example)
    }
    
    let brandManager = VehicleBrandManager.shared
    
    var body: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Image(systemName: "number.square.fill")
                    .foregroundColor(.blue)
                TextField(platePlaceholder, text: $plaka)
                    .textInputAutocapitalization(.characters)
            }
            
            // Brand Picker
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                
                Menu {
                    Button("Manual Entry".localized) {
                        showBrandPicker = false
                    }
                    
                    Divider()
                    
                    ForEach(brandManager.brandNames, id: \.self) { brandName in
                        Button(brandName) {
                            marka = brandName
                            updateAvailableModels()
                        }
                    }
                } label: {
                    HStack {
                        Text(marka.isEmpty ? "Select Brand".localized : marka)
                            .foregroundColor(marka.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Manual Brand Entry (if needed)
            if !brandManager.brandExists(marka) && !marka.isEmpty {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                    TextField("Custom Brand".localized, text: $marka)
                }
            }
            
            // Model Picker
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.blue)
                
                if !availableModels.isEmpty {
                    Menu {
                        Button("Manual Entry".localized) {
                            model = ""
                        }
                        
                        Divider()
                        
                        ForEach(availableModels, id: \.self) { modelName in
                            Button(modelName) {
                                model = modelName
                            }
                        }
                    } label: {
                        HStack {
                            Text(model.isEmpty ? "Select Model".localized : model)
                                .foregroundColor(model.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    TextField("Model".localized, text: $model)
                }
            }
        }
        .onChange(of: marka) { _ in
            updateAvailableModels()
        }
    }
    
    private func updateAvailableModels() {
        availableModels = brandManager.models(for: marka)
        // Reset model if brand changed
        if !availableModels.isEmpty && !availableModels.contains(model) {
            model = ""
        }
    }
}

private struct CategorySection: View {
    @Binding var kategori: String
    @Binding var yeniKategoriGoster: Bool
    let viewModel: AracViewModel
    
    var body: some View {
        Section("Category".localized) {
            if viewModel.kategoriler.isEmpty {
                Text("No category defined for this franchise yet. Please add category first.".localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Picker("Category".localized, selection: $kategori) {
                    Text("Select Category".localized).tag("")
                    ForEach(viewModel.kategoriler, id: \.self) { kategori in
                        Text(kategori).tag(kategori)
                    }
                }
            }
            
            Button {
                yeniKategoriGoster = true
            } label: {
                Label("Add New Category".localized, systemImage: "plus.circle")
                    .foregroundColor(.blue)
            }
        }
    }
}

private struct VignetteSection: View {
    @Binding var vignetteVar: Bool
    
    var body: some View {
        Section("Vignette".localized) {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundColor(.blue)
                Text("Has Vignette?".localized)
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
        Section("Spare Key & Head Document".localized) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                TextField("Spare Key Count".localized, text: $spareKeyCount)
                    .keyboardType(.numberPad)
            }
            
            if let url = headDocumentURL, !url.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Head Document Uploaded".localized)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Remove".localized) {
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
                        Text("Uploading...".localized)
                    } else {
                        Label("Upload Head Document Photo".localized, systemImage: "photo.on.rectangle")
                    }
                }
            }
            .disabled(isUploading)
        }
    }
}

private struct SaveSection: View {
    let canSave: Bool
    let kaydet: () -> Void
    
    var body: some View {
        Section {
            Button {
                kaydet()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save".localized)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canSave)
        }
    }
}
