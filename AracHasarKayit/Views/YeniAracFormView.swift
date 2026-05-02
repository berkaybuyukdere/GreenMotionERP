import SwiftUI

struct YeniAracFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var servisEkleGoster = false
    var onVehicleSaved: ((Arac) -> Void)? = nil

    private var hasValidCategory: Bool {
        !arac.kategori.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Plate Scanned".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(arac.plakaFormatli)
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            
            Section("Vehicle Information".localized) {
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
            }
            .onAppear {
                alignCategorySelection()
            }
            
            Section("Category".localized) {
                if viewModel.kategoriler.isEmpty {
                    Text("No category defined for this franchise yet. Please add category first.".localized)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Category".localized, selection: $arac.kategori) {
                        Text("Select Category".localized).tag("")
                        ForEach(viewModel.kategoriler, id: \.self) { kategori in
                            Text(kategori).tag(kategori)
                        }
                    }
                }
                
                if authManager.userProfile?.canManageVehicleCategories ?? false {
                    Button {
                        yeniKategoriGoster = true
                    } label: {
                        Label("Add New Category".localized, systemImage: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            
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
            
            Section {
                Button {
                    viewModel.aracEkle(arac)
                    onVehicleSaved?(arac)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Vehicle".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(arac.marka.isEmpty || arac.model.isEmpty || !hasValidCategory)
                
                Button {
                    viewModel.aracEkle(arac)
                    onVehicleSaved?(arac)
                    // Kısa bir delay ile servis ekleme ekranını aç
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        servisEkleGoster = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                        Text("Save and Add Service".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(arac.marka.isEmpty || arac.model.isEmpty || !hasValidCategory)
            }
        }
        .navigationTitle("New Vehicle".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) {
                    dismiss()
                }
            }
        }
        .onChange(of: viewModel.kategoriler) { _ in
            alignCategorySelection()
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
        .sheet(isPresented: $servisEkleGoster) {
            NavigationView {
                ServisEkleView(preSelectedAracId: arac.id)
            }
        }
    }
    
    private func alignCategorySelection() {
        if !viewModel.kategoriler.contains(arac.kategori) {
            arac.kategori = ""
        }
    }
}
