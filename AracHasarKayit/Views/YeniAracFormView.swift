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
                    
                    Text("Plaka Tarandı")
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
            
            Section("Vehicle Information") {
                // Brand Picker
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    
                    Menu {
                        Button("Manual Entry") {
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
                            Text(arac.marka.isEmpty ? "Select Brand" : arac.marka)
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
                        TextField("Custom Brand", text: $arac.marka)
                    }
                }
                
                // Model Picker
                HStack {
                    Image(systemName: "car.2.fill")
                        .foregroundColor(.blue)
                    
                    if !availableModels.isEmpty {
                        Menu {
                            Button("Manual Entry") {
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
                                Text(arac.model.isEmpty ? "Select Model" : arac.model)
                                    .foregroundColor(arac.model.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        TextField("Model (e.g. 3 Series)", text: $arac.model)
                    }
                }
            }
            .onAppear {
                updateAvailableModels()
            }
            .onChange(of: arac.marka) { _ in
                updateAvailableModels()
            }
            
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
            
            Section {
                Button {
                    viewModel.aracEkle(arac)
                    onVehicleSaved?(arac)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Aracı Kaydet")
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
                        Text("Kaydet ve Servis Ekle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(arac.marka.isEmpty || arac.model.isEmpty)
            }
        }
        .navigationTitle("Yeni Araç")
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
