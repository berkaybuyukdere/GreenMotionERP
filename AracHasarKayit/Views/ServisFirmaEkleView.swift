import SwiftUI

struct ServisFirmaEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    var duzenlenecekFirma: ServisFirma?
    
    @State private var ad = ""
    @State private var telefon = ""
    @State private var email = ""
    @State private var adres = ""
    @State private var notlar = ""
    
    var duzenlemeModuMu: Bool {
        duzenlenecekFirma != nil
    }
    
    var body: some View {
        Form {
            Section("Firma Bilgileri") {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.blue)
                    TextField("Firma Adı", text: $ad)
                }
                
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.blue)
                    TextField("Telefon", text: $telefon)
                        .keyboardType(.phonePad)
                }
                
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.blue)
                    TextField("E-posta", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    TextField("Adres", text: $adres)
                }
            }
            
            Section("Notlar") {
                TextEditor(text: $notlar)
                    .frame(minHeight: 100)
            }
            
            Section {
                Button {
                    kaydet()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(duzenlemeModuMu ? "Güncelle" : "Kaydet")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(ad.isEmpty)
            }
        }
        .navigationTitle(duzenlemeModuMu ? "Firma Düzenle" : "Yeni Servis Firması")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("İptal") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if let firma = duzenlenecekFirma {
                ad = firma.ad
                telefon = firma.telefon
                email = firma.email
                adres = firma.adres
                notlar = firma.notlar
            }
        }
    }
    
    func kaydet() {
        if duzenlemeModuMu, var firma = duzenlenecekFirma {
            // Güncelleme
            firma.ad = ad
            firma.telefon = telefon
            firma.email = email
            firma.adres = adres
            firma.notlar = notlar
            viewModel.servisFirmaGuncelle(firma)
        } else {
            // Yeni ekleme
            let yeniFirma = ServisFirma(
                ad: ad,
                telefon: telefon,
                email: email,
                adres: adres,
                notlar: notlar
            )
            viewModel.servisFirmaEkle(yeniFirma)
        }
        
        dismiss()
    }
}
