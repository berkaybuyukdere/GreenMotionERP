import SwiftUI

struct AracDuzenleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showCompanyPicker = false
    
    var body: some View {
        Form {
            VehicleInfoSection(arac: $arac, authManager: authManager)
                .environmentObject(viewModel)
            CategorySection(
                arac: $arac,
                yeniKategoriGoster: $yeniKategoriGoster,
                viewModel: viewModel,
                canAddCategory: authManager.userProfile?.canManageVehicleCategories ?? false
            )
            VignetteSection(arac: $arac)
            SpareKeyHeadDocSection(
                arac: $arac,
                showImagePicker: $showImagePicker,
                isUploading: isUploading
            )
            AssistantCompanySection(
                arac: $arac,
                showCompanyPicker: $showCompanyPicker
            )
            SaveSection(isUploading: isUploading, kaydet: kaydet)
        }
        .navigationTitle("Edit Vehicle".localized)
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
                    arac.kategori = kategori
                    yeniKategoriAdi = ""
                }
            }
        } message: {
            Text("Add a new category for your franchise".localized)
        }
        .sheet(isPresented: $showImagePicker) {
            SingleImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCompanyPicker) {
            CompanyPickerView(
                selectedCompany: Binding(
                    get: {
                        guard let name = arac.assistantCompanyName,
                              let phone = arac.assistantCompanyPhone else {
                            return nil
                        }
                        return AssistantCompany(name: name, phoneNumber: phone)
                    },
                    set: { newCompany in
                        arac.assistantCompanyName = newCompany?.name
                        arac.assistantCompanyPhone = newCompany?.phoneNumber
                    }
                )
            )
            .environmentObject(viewModel)
        }
        .onChange(of: selectedImage) { img in
            guard let img = img else { return }
            isUploading = true
            
            let path = "kafa_kagitlari/\(arac.id.uuidString)/head_\(UUID().uuidString).jpg"
            
            CachedImageManager.shared.uploadImage(img, path: path) { urlString, error in
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
        guard !isUploading else {
            ToastManager.shared.show("Please wait for photo upload to finish.".localized, type: .warning)
            return
        }
        viewModel.aracGuncelle(arac)
        dismiss()
    }
}

private struct VehicleInfoSection: View {
    @Binding var arac: Arac
    let authManager: AuthenticationManager
    @EnvironmentObject var viewModel: AracViewModel

    private var isTurkeySession: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    private var garageBranchesFromFirebase: [FranchiseGarageBranch] {
        viewModel.garageBranchesForSelectedCountry(countryCode: UserDefaults.standard.selectedCountry.countryCode)
    }
    
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
                TextField(platePlaceholder, text: $arac.plaka)
                    .textInputAutocapitalization(.characters)
            }
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                TextField("Brand".localized, text: $arac.marka)
            }
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.blue)
                TextField("Model".localized, text: $arac.model)
            }
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.blue)
                TextField("VIN (optional)".localized, text: Binding(
                    get: { arac.vin ?? "" },
                    set: { nv in
                        let t = nv.trimmingCharacters(in: .whitespacesAndNewlines)
                        arac.vin = t.isEmpty ? nil : t
                    }
                ))
                .textInputAutocapitalization(.characters)
            }
            if isTurkeySession {
                if garageBranchesFromFirebase.isEmpty {
                    TextField("Branch storage key".localized, text: Binding(
                        get: { arac.garageBranchId ?? "" },
                        set: { arac.garageBranchId = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.characters)
                } else {
                    Picker("Branch / Şube".localized, selection: Binding(
                        get: { arac.garageBranchId ?? garageBranchesFromFirebase.first?.storageKey ?? "" },
                        set: { arac.garageBranchId = $0 }
                    )) {
                        ForEach(garageBranchesFromFirebase) { b in
                            Text(b.displayName).tag(b.storageKey)
                        }
                    }
                }
            }
        }
    }
}

private struct CategorySection: View {
    @Binding var arac: Arac
    @Binding var yeniKategoriGoster: Bool
    let viewModel: AracViewModel
    var canAddCategory: Bool = true

    var body: some View {
        Section("Category".localized) {
            Picker("Category".localized, selection: $arac.kategori) {
                ForEach(viewModel.kategoriler, id: \.self) { kategori in
                    Text(kategori).tag(kategori)
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
    @Binding var arac: Arac
    
    var body: some View {
        Section("Vignette".localized) {
            HStack {
                Image(systemName: "ticket.fill")
                    .foregroundColor(.blue)
                Text("Has Vignette?".localized)
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
        Section("Spare Key & Head Document".localized) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                Stepper("\("Spare Keys".localized): \(arac.spareKeyCount)", value: $arac.spareKeyCount, in: 0...10)
            }
            
            if let url = arac.headDocumentURL, !url.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Head Document Uploaded".localized)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Remove".localized) {
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

private struct AssistantCompanySection: View {
    @Binding var arac: Arac
    @Binding var showCompanyPicker: Bool
    
    var selectedCompany: AssistantCompany? {
        guard let name = arac.assistantCompanyName,
              let phone = arac.assistantCompanyPhone else {
            return nil
        }
        return AssistantCompany(name: name, phoneNumber: phone)
    }
    
    var body: some View {
        Section("Assistant Company".localized) {
            Button {
                showCompanyPicker = true
            } label: {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.blue)
                    Text(selectedCompany?.name ?? "Select Company".localized)
                        .foregroundColor(selectedCompany == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let company = selectedCompany {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(company.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(company.phoneNumber)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                Button {
                    arac.assistantCompanyName = nil
                    arac.assistantCompanyPhone = nil
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Remove Company".localized)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
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
                    Text("Save Changes".localized)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isUploading)
        }
    }
}
