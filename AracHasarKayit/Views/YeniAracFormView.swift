import SwiftUI

struct YeniAracFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    @State private var availableModels: [String] = []
    @State private var servisEkleGoster = false
    var onVehicleSaved: ((Arac) -> Void)? = nil
    
    let brandManager = VehicleBrandManager.shared
    
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
                // Brand Picker
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    
                    Menu {
                        Button("Manual Entry".localized) {
                            arac.marka = ""
                        }
                        
                        Divider()
                        
                        ForEach(brandManager.brandNames, id: \.self) { brandName in
                            Button(brandName) {
                                arac.marka = brandName
                                updateAvailableModels()
                            }
                        }
                    } label: {
                        HStack {
                            Text(arac.marka.isEmpty ? "Select Brand".localized : arac.marka)
                                .foregroundColor(arac.marka.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Manual Brand Entry (if needed)
                if !brandManager.brandExists(arac.marka) && !arac.marka.isEmpty {
                    HStack {
                        Image(systemName: "pencil")
                            .foregroundColor(.orange)
                        TextField("Custom Brand".localized, text: $arac.marka)
                    }
                }
                
                // Model Picker
                HStack {
                    Image(systemName: "car.2.fill")
                        .foregroundColor(.blue)
                    
                    if !availableModels.isEmpty {
                        Menu {
                            Button("Manual Entry".localized) {
                                arac.model = ""
                            }
                            
                            Divider()
                            
                            ForEach(availableModels, id: \.self) { modelName in
                                Button(modelName) {
                                    arac.model = modelName
                                }
                            }
                        } label: {
                            HStack {
                                Text(arac.model.isEmpty ? "Select Model".localized : arac.model)
                                    .foregroundColor(arac.model.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        TextField("Model".localized, text: $arac.model)
                    }
                }
            }
            .onAppear {
                updateAvailableModels()
            }
            .onChange(of: arac.marka) { _ in
                updateAvailableModels()
            }
            
            Section("Category".localized) {
                Picker("Category".localized, selection: $arac.kategori) {
                    ForEach(viewModel.kategoriler, id: \.self) { kategori in
                        Text(kategori).tag(kategori)
                    }
                }
                
                Button {
                    yeniKategoriGoster = true
                } label: {
                    Label("Add New Category".localized, systemImage: "plus.circle")
                        .foregroundColor(.blue)
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
                .disabled(arac.marka.isEmpty || arac.model.isEmpty)
                
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
                .disabled(arac.marka.isEmpty || arac.model.isEmpty)
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
        .alert("New Category".localized, isPresented: $yeniKategoriGoster) {
            TextField("Category (A-Z)".localized, text: $yeniKategoriAdi)
            Button("Cancel".localized, role: .cancel) {
                yeniKategoriAdi = ""
            }
            Button("Add".localized) {
                if !yeniKategoriAdi.isEmpty {
                    let kategori = yeniKategoriAdi.uppercased().prefix(1)
                    viewModel.kategoriEkle(String(kategori))
                    arac.kategori = String(kategori)
                    yeniKategoriAdi = ""
                }
            }
        } message: {
            Text("Add a new category (single letter A-Z)".localized)
        }
        .sheet(isPresented: $servisEkleGoster) {
            NavigationView {
                ServisEkleView(preSelectedAracId: arac.id)
            }
        }
    }
    
    private func updateAvailableModels() {
        availableModels = brandManager.models(for: arac.marka)
        // Reset model if brand changed and current model doesn't exist
        if !availableModels.isEmpty && !availableModels.contains(arac.model) {
            arac.model = ""
        }
    }
}
