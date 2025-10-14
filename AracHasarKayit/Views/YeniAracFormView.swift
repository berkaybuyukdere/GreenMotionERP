import SwiftUI

struct YeniAracFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    
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
            
            Section("Araç Bilgileri") {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    TextField("Marka (örn: BMW)", text: $arac.marka)
                }
                
                HStack {
                    Image(systemName: "car.2.fill")
                        .foregroundColor(.blue)
                    TextField("Model (örn: 3 Serisi)", text: $arac.model)
                }
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
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Aracı Kaydet")
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
    }
}
