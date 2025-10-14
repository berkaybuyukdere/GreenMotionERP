import SwiftUI

struct ManuelAracEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var plaka = ""
    @State private var marka = ""
    @State private var model = ""
    @State private var seciliKategori = "A"
    @State private var vignetteVar = false
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    
    var body: some View {
        Form {
            Section("Araç Bilgileri") {
                HStack {
                    Image(systemName: "number.square.fill")
                        .foregroundColor(.blue)
                    TextField("Plaka (örn: ZH 123456)", text: $plaka)
                        .textInputAutocapitalization(.characters)
                }
                
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    TextField("Marka (örn: BMW)", text: $marka)
                }
                
                HStack {
                    Image(systemName: "car.2.fill")
                        .foregroundColor(.blue)
                    TextField("Model (örn: 3 Serisi)", text: $model)
                }
            }
            
            Section("Kategori") {
                Picker("Kategori", selection: $seciliKategori) {
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
                        vignetteVar.toggle()
                    } label: {
                        Image(systemName: vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(vignetteVar ? .green : .red)
                    }
                }
            }
            
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
                .disabled(!formGecerli)
            }
        }
        .navigationTitle("Yeni Araç Ekle")
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
                    seciliKategori = String(kategori)
                    yeniKategoriAdi = ""
                }
            }
        } message: {
            Text("Yeni bir kategori ekleyin (A-Z arası tek harf)")
        }
    }
    
    var formGecerli: Bool {
        !plaka.isEmpty && !marka.isEmpty && !model.isEmpty
    }
    
    func kaydet() {
        let yeniArac = Arac(plaka: plaka, marka: marka, model: model, kategori: seciliKategori, vignetteVar: vignetteVar)
        viewModel.aracEkle(yeniArac)
        dismiss()
    }
}
