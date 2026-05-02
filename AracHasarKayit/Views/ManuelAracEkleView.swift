import SwiftUI
import FirebaseAuth

struct ManuelAracEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var plaka: String
    @State private var marka = ""
    @State private var model = ""
    @State private var vin = ""
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
    @State private var garageBranchKey: String = ""

    /// Türkiye: `franchises` koleksiyonundaki `TR_*` dokümanları; yoksa aktif dokümandaki `garageBranches`.
    private var garageBranchesFromFranchiseDoc: [FranchiseGarageBranch] {
        let tr = viewModel.turkeyFranchiseLocationBranches
        if !tr.isEmpty { return tr }
        return viewModel.franchiseGarageBranches
    }

    @ViewBuilder
    private var garageBranchSection: some View {
        if isTurkeySession {
            Section("Garage branch".localized) {
                if garageBranchesFromFranchiseDoc.isEmpty {
                    Text("No TR franchise documents were found (franchises collection, ids starting with TR_). This vehicle will be saved with your login session branch.".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Branch".localized, selection: $garageBranchKey) {
                        ForEach(garageBranchesFromFranchiseDoc) { b in
                            Text(b.displayName).tag(b.storageKey)
                        }
                    }
                }
            }
        }
    }

    private func alignGarageBranchDefault() {
        guard isTurkeySession, garageBranchKey.isEmpty else { return }
        let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
        let list = garageBranchesFromFranchiseDoc
        if let m = list.first(where: { TurkiyeGarajSubeleri.equivalentGarageBranchKeys($0.storageKey, session) }) {
            garageBranchKey = m.storageKey
        } else if let first = list.first {
            garageBranchKey = first.storageKey
        }
    }

    private var isTurkeySession: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }
    
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
            VehicleInfoSection(plaka: $plaka, marka: $marka, model: $model, vin: $vin)
            garageBranchSection
            CategorySection(
                kategori: $kategori,
                yeniKategoriGoster: $yeniKategoriGoster,
                viewModel: viewModel,
                canAddCategory: authManager.userProfile?.canManageVehicleCategories ?? false
            )
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
        .onAppear {
            viewModel.reloadFranchiseGarageMetadataFromFirestore()
            alignGarageBranchDefault()
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
        let vinTrim = vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let yeniArac = Arac(
            plaka: temizPlaka,
            marka: marka,
            model: model,
            kategori: kategori,
            vin: vinTrim.isEmpty ? nil : vinTrim,
            vignetteVar: vignetteVar,
            spareKeyCount: spareKeys,
            headDocumentURL: headDocumentURL,
            createdBy: currentUserId,
            garageBranchId: isTurkeySession
                ? TurkiyeGarajSubeleri.persistedGarageBranchIdForTurkeyVehicle(
                    csvOrPickerValue: garageBranchesFromFranchiseDoc.isEmpty ? nil : garageBranchKey
                )
                : nil
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
    @Binding var vin: String

    private var platePlaceholder: String {
        let countryId = UserDefaults.standard.selectedCountryId
        let example = CountryManager.plateExamples(for: countryId).first ?? "AB1234"
        return String(format: "Plate example: %@".localized, example)
    }

    var body: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Image(systemName: "number.square.fill")
                    .foregroundColor(.blue)
                TextField(platePlaceholder, text: $plaka)
                    .textInputAutocapitalization(.characters)
            }
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Brand".localized, text: $marka)
            }
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.blue)
                TextField("Model".localized, text: $model)
            }
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.blue)
                TextField("VIN (optional)".localized, text: $vin)
                    .textInputAutocapitalization(.characters)
            }
        }
    }
}

private struct CategorySection: View {
    @Binding var kategori: String
    @Binding var yeniKategoriGoster: Bool
    let viewModel: AracViewModel
    var canAddCategory: Bool = true

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

            if canAddCategory {
                Button {
                    yeniKategoriGoster = true
                } label: {
                    Label("Add New Category".localized, systemImage: "plus.circle")
                        .foregroundColor(.blue)
                }
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
