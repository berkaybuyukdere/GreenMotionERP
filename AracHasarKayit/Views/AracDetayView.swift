import SwiftUI

struct AracDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var duzenlemeGoster = false
    @State private var hasarEkleGoster = false
    @State private var iadeIslemGoster = false
    @State private var silmeOnayiGoster = false
    @State private var showHeadDocument = false
    @State private var headDocumentImage: UIImage?
    @State private var isLoadingHeadDoc = false
    
    var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }
    
    var latestDamage: HasarKaydi? {
        guncelArac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(guncelArac.plakaFormatli)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("\(guncelArac.marka) \(guncelArac.model)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.caption)
                                Text(guncelArac.kategori)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: guncelArac.vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(guncelArac.vignetteVar ? .green : .red)
                                Text("Vignette")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((guncelArac.vignetteVar ? Color.green : Color.red).opacity(0.2))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.caption)
                                Text("\(guncelArac.spareKeyCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Kayıt Tarihi", systemImage: "calendar")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(guncelArac.kayitTarihi, style: .date)
                            .fontWeight(.semibold)
                    }
                    
                    Button {
                        iadeIslemGoster = true
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text("İade İşlemi Yap")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 8)
            }
            
            Section("İstatistikler") {
                HStack {
                    Label("Toplam Hasar", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(guncelArac.hasarKayitlari.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Servis Kayıtları", systemImage: "wrench.and.screwdriver.fill")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(viewModel.aracServisleri(aracId: guncelArac.id).count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Spare Keys", systemImage: "key.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(guncelArac.spareKeyCount)")
                        .fontWeight(.semibold)
                }
                
                if let headDocURL = guncelArac.headDocumentURL, !headDocURL.isEmpty {
                    Button {
                        loadAndShowHeadDocument(url: headDocURL)
                    } label: {
                        HStack {
                            Label("View Head Document", systemImage: "doc.text.image")
                            Spacer()
                            if isLoadingHeadDoc {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            Section {
                ForEach(guncelArac.hasarKayitlari) { hasar in
                    NavigationLink(destination: HasarDetayView(hasar: hasar, aracId: guncelArac.id, aracPlaka: guncelArac.plakaFormatli)) {
                        HasarSatirView(hasar: hasar)
                    }
                }
                .onDelete(perform: hasarSil)
                
                Button {
                    hasarEkleGoster = true
                } label: {
                    Label("Hasar Ekle", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            } header: {
                HStack {
                    Text("Hasar Kayıtları")
                    Spacer()
                    Text("\(guncelArac.hasarKayitlari.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Aracı Sil", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Araç Detayları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    duzenlemeGoster = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                }
            }
        }
        .sheet(isPresented: $duzenlemeGoster) {
            NavigationView {
                AracDuzenleView(arac: guncelArac)
            }
        }
        .sheet(isPresented: $hasarEkleGoster) {
            NavigationView {
                HasarEkleView(aracId: guncelArac.id)
            }
        }
        .sheet(isPresented: $iadeIslemGoster) {
            NavigationView {
                IadeIslemView(arac: guncelArac)
            }
        }
        .sheet(isPresented: $showHeadDocument) {
            NavigationView {
                HeadDocumentPreviewView(image: headDocumentImage)
            }
        }
        .alert("Delete Vehicle", isPresented: $silmeOnayiGoster) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.aracSil(guncelArac)
                
                // Show deletion toast
                ToastManager.shared.show("✓ Vehicle Deleted", type: .error)
                
                // Navigate back after deletion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete this vehicle and all its damage records?")
        }
        .onAppear {
            arac = guncelArac
        }
    }
    
    func hasarSil(at offsets: IndexSet) {
        for index in offsets {
            let hasar = guncelArac.hasarKayitlari[index]
            viewModel.hasarSil(aracId: guncelArac.id, hasarId: hasar.id)
            
            // Show success toast
            ToastManager.shared.show("✓ Damage Record Deleted", type: .success)
        }
    }
    
    func loadAndShowHeadDocument(url: String) {
        isLoadingHeadDoc = true
        
        guard let imageURL = URL(string: url) else {
            isLoadingHeadDoc = false
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                isLoadingHeadDoc = false
                
                if let data = data, let image = UIImage(data: data) {
                    headDocumentImage = image
                    showHeadDocument = true
                } else {
                    print("❌ Failed to load head document image")
                }
            }
        }.resume()
    }
}

struct HeadDocumentPreviewView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage?
    
    var body: some View {
        VStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Image not available")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Head Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct HasarSatirView: View {
    let hasar: HasarKaydi
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(hasar.resKodu)
                    .font(.headline)
                
                Text("\(hasar.km) km")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label {
                        Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if !hasar.fotograflar.isEmpty {
                        Label("\(hasar.fotograflar.count)", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: hasar.durum == .done ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundColor(hasar.durum == .done ? .green : .yellow)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}
