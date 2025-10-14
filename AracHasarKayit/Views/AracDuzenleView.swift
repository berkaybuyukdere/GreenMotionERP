import SwiftUI

struct AracDuzenleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var arac: Arac
    @State private var yeniKategoriGoster = false
    @State private var yeniKategoriAdi = ""
    
    var body: some View {
        Form {
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
                    kaydet()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Değişiklikleri Kaydet")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
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
    }
    
    func kaydet() {
        viewModel.aracGuncelle(arac)
        dismiss()
    }
}
