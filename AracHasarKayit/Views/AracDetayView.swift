import SwiftUI

// MARK: - Sheet Wrapper to prevent swipe-to-dismiss
struct SheetWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(true)
    }
}

struct AracDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State var arac: Arac
    @State private var duzenlemeGoster = false
    @State private var hasarEkleGoster = false
    @State private var iadeIslemGoster = false
    @State private var servisEkleGoster = false
    @State private var silmeOnayiGoster = false
    @State private var showHeadDocument = false
    @State private var headDocumentImage: UIImage?
    @State private var isLoadingHeadDoc = false
    @State private var selectedIade: IadeIslemi?
    @State private var showIadeDetay = false
    
    var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }
    
    var latestDamage: HasarKaydi? {
        guncelArac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var aracServiste: Bool {
        viewModel.servisler.contains(where: { $0.aracId == guncelArac.id && $0.durum == .serviste })
    }
    
    var aracIadeleri: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.iadeTarihi > $1.iadeTarihi })
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
                    
                    HStack(spacing: 12) {
                        // Servis Ekle Butonu (Eğer serviste değilse)
                        if !aracServiste {
                            Button {
                                servisEkleGoster = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.title2)
                                    Text("Servis Ekle")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // İade İşlemi Butonu
                        Button {
                            iadeIslemGoster = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.title2)
                                Text("İade İşlemi")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
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
                
                HStack {
                    Label("İade İşlemleri", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.purple)
                    Spacer()
                    Text("\(aracIadeleri.count)")
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
                if guncelArac.hasarKayitlari.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("No Damage Records")
                            .font(.headline)
                        Text("This vehicle has no recorded damages.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(guncelArac.hasarKayitlari) { hasar in
                        NavigationLink(destination: HasarDetayView(hasar: hasar, aracId: guncelArac.id, aracPlaka: guncelArac.plakaFormatli)) {
                            HasarSatirView(hasar: hasar)
                        }
                    }
                    .onDelete(perform: hasarSil)
                }
                
                Button {
                    hasarEkleGoster = true
                } label: {
                    Label(guncelArac.hasarKayitlari.isEmpty ? "Add First Damage Record" : "Add Damage Record", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            } header: {
                HStack {
                    Text("Hasar Kayıtları")
                    Spacer()
                    if !guncelArac.hasarKayitlari.isEmpty {
                        Text("\(guncelArac.hasarKayitlari.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section {
                if aracIadeleri.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 40))
                            .foregroundColor(.purple)
                        Text("No Return Operations")
                            .font(.headline)
                        Text("This vehicle has no recorded return operations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(aracIadeleri) { iade in
                        NavigationLink(destination: IadeDetayView(iade: iade)) {
                            IadeSatirView(iade: iade)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("İade İşlemleri")
                    Spacer()
                    if !aracIadeleri.isEmpty {
                        Text("\(aracIadeleri.count)")
                            .foregroundColor(.secondary)
                    }
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
            SheetWrapper {
                NavigationView {
                    HasarEkleView(aracId: guncelArac.id)
                }
            }
        }
        .sheet(isPresented: $iadeIslemGoster) {
            SheetWrapper {
                NavigationView {
                    IadeIslemView(arac: guncelArac) { completedIade in
                        selectedIade = completedIade
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showIadeDetay = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $servisEkleGoster) {
            NavigationView {
                ServisEkleView(preSelectedAracId: guncelArac.id)
            }
        }
        .sheet(isPresented: $showHeadDocument) {
            NavigationView {
                HeadDocumentPreviewView(image: headDocumentImage)
            }
        }
        .sheet(isPresented: $showIadeDetay) {
            if let iade = selectedIade {
                NavigationView {
                    IadeDetayView(iade: iade)
                }
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
                        .foregroundColor(Color.gray)
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasar.resKodu)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !hasar.notlar.isEmpty {
                            Text(hasar.notlar)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(hasar.km) km")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    if !hasar.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("\(hasar.fotograflar.count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 6, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        hasar.durum == .done ? .green : .red
    }
    
    private var statusIcon: String {
        hasar.durum == .done ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(hasar.durum == .done ? "Done" : "In Progress")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}

