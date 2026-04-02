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
    @State private var checkInGoster = false
    @State private var iadeIslemGoster = false
    @State private var exitIslemGoster = false
    @State private var servisEkleGoster = false
    @State private var silmeOnayiGoster = false
    @State private var showHeadDocument = false
    @State private var headDocumentImage: UIImage?
    @State private var isLoadingHeadDoc = false
    @State private var selectedIade: IadeIslemi?
    @State private var showIadeDetay = false
    @State private var isDamageExpanded = false
    @State private var isReturnExpanded = false
    @State private var isExitExpanded = false
    @State private var showCompanyPicker = false
    @State private var selectedExitForEditing: ExitIslemi?
    @State private var checkInSilmeOnayi: LastCheckInSnapshot?
    
    var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }
    
    var selectedCompany: AssistantCompany? {
        guard let companyName = guncelArac.assistantCompanyName,
              let companyPhone = guncelArac.assistantCompanyPhone else {
            return nil
        }
        return AssistantCompany(name: companyName, phoneNumber: companyPhone)
    }
    
    var latestDamage: HasarKaydi? {
        guncelArac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var aracServiste: Bool {
        viewModel.servisler.contains(where: { $0.aracId == guncelArac.id && $0.durum == .serviste })
    }
    
    var aracServisleri: [Servis] {
        viewModel.servisler.filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.gonderilmeTarihi > $1.gonderilmeTarihi })
    }
    
    var aktifServis: Servis? {
        // Önce serviste olan varsa onu göster, yoksa en son servis kaydını göster
        let servisler = aracServisleri
        if let servisteOlan = servisler.first(where: { $0.durum == .serviste }) {
            return servisteOlan
        }
        if let sonServis = servisler.first {
            return sonServis
        }
        return nil
    }
    
    var aracIadeleri: [IadeIslemi] {
        viewModel.iadeIslemleri.filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.iadeTarihi > $1.iadeTarihi })
    }
    
    var aracExitleri: [ExitIslemi] {
        viewModel.exitIslemleri.filter { $0.aracId == guncelArac.id }
            .sorted(by: { $0.createdAt > $1.createdAt }) // Gerçek işlem tarihine göre sırala
    }
    
    var activeDraftExit: ExitIslemi? {
        aracExitleri.first(where: { $0.status != .completed })
    }
    
    /// End of the last completed return cycle (createdAt vs iadeTarihi — whichever is later).
    private var lastReturnRecency: Date? {
        aracIadeleri
            .filter { $0.status == .completed }
            .map { max($0.createdAt, $0.iadeTarihi) }
            .max()
    }
    
    /// Handover time for a checkout row (aligns with detail screen / PDF).
    private func checkoutRecency(_ exit: ExitIslemi) -> Date {
        max(exit.createdAt, exit.exitTarihi)
    }
    
    /// Outbound checkouts (handover done): completed or parked — **excluding** cycles already closed by a later return.
    private var openOutboundExits: [ExitIslemi] {
        let outbound = aracExitleri.filter { $0.status == .completed || $0.status == .parked }
        guard let cutoff = lastReturnRecency else { return outbound }
        return outbound.filter { checkoutRecency($0) > cutoff }
    }
    
    /// The **current** open checkout for check-in / RETURN (must match the latest row the user sees for an active rental).
    private var latestOpenOutboundExit: ExitIslemi? {
        openOutboundExits.max { a, b in
            let ra = checkoutRecency(a)
            let rb = checkoutRecency(b)
            if ra != rb { return ra < rb }
            return a.createdAt < b.createdAt
        }
    }
    
    /// True when there is at least one checkout after the last return (vehicle out on an open cycle).
    private var vehicleLikelyOut: Bool {
        latestOpenOutboundExit != nil
    }
    
    private func normalizedResToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "RES-", with: "")
            .filter { $0.isNumber }
    }
    
    /// Latest check-in snapshot tied to the current open checkout (exit id or matching RES digits).
    private var checkInSnapshotForCurrentExit: LastCheckInSnapshot? {
        guard let exit = latestOpenOutboundExit else { return nil }
        let targetId = exit.id
        let resNum = normalizedResToken(exit.resKodu)
        let matches = guncelArac.checkInKayitlari.filter { snap in
            if let lid = snap.linkedExitId, lid == targetId { return true }
            if !resNum.isEmpty, normalizedResToken(snap.reservationNumber) == resNum { return true }
            return false
        }
        return matches.max { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.id.uuidString < b.id.uuidString
        }
    }
    
    /// True when there is a check-in row for the **current** latest open checkout (by exit id or matching RES digits).
    private var hasCheckInForCurrentExit: Bool {
        checkInSnapshotForCurrentExit != nil
    }
    
    private var checkInActionSubtitle: String {
        if latestOpenOutboundExit == nil {
            return "After CHECK OUT when vehicle returns".localized
        }
        if let snap = checkInSnapshotForCurrentExit {
            return String(format: "Latest RES check-in on file: %lld km · fuel %lld/8".localized, snap.km, snap.fuelEighths)
        }
        return "Open RES: enter km & fuel (8 = full)".localized
    }
    
    /// Return (iade) flow can be started whenever there is an open checkout.
    private var canOpenReturn: Bool {
        vehicleLikelyOut
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
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)
                            
                            HStack(spacing: 4) {
                                Image(systemName: guncelArac.vignetteVar ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(guncelArac.vignetteVar ? .green : .orange)
                                Text("Vignette".localized)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((guncelArac.vignetteVar ? Color.green : Color.orange).opacity(0.15))
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
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Kayıt Tarihi".localized, systemImage: "calendar")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(guncelArac.kayitTarihi, style: .date)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                selectedExitForEditing = activeDraftExit
                                exitIslemGoster = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title2)
                                    Text("CHECK OUT".localized)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button {
                                iadeIslemGoster = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.title2)
                                    Text("RETURN".localized)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Altta: SERVIS EKLE tek başına uzun (daha dar ve soft gri)
                        if !aracServiste {
                        Button {
                                servisEkleGoster = true
                        } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.title3)
                                    Text("SERVIS EKLE".localized)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Assistant Company Section
                    VStack(spacing: 8) {
                        Divider()
                        
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                            Text("Assistant Company".localized)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                showCompanyPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    if let company = selectedCompany {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(company.name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            Text(company.phoneNumber)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text("Select".localized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Servis Durumu Alanı (Eğer servis kaydı varsa göster)
                    if let servis = aktifServis {
                        VStack(spacing: 12) {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Servis Durumu".localized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: servis.durum.icon)
                                            .font(.title3)
                                            .foregroundColor(Color(servis.durum.renk))
                                        
                                        Text(servis.durum.displayTitle)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if !servis.servisFirmaAdi.isEmpty {
                                            Text("• \(servis.servisFirmaAdi)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Menu {
                                    ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                                        Button {
                                            servisDurumGuncelle(servis: servis, yeniDurum: durum)
                                        } label: {
                                            HStack {
                                                Text(durum.displayTitle)
                                                if servis.durum == durum {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("İstatistikler".localized) {
                HStack {
                    Label("Toplam Hasar".localized, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(guncelArac.hasarKayitlari.count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Servis Kayıtları".localized, systemImage: "wrench.and.screwdriver.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(viewModel.aracServisleri(aracId: guncelArac.id).count)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("Spare Keys".localized, systemImage: "key.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(guncelArac.spareKeyCount)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label("İade İşlemleri".localized, systemImage: "checkmark.shield.fill")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(aracIadeleri.count)")
                        .fontWeight(.semibold)
                }
                
                if let headDocURL = guncelArac.headDocumentURL, !headDocURL.isEmpty {
                    Button {
                        loadAndShowHeadDocument(url: headDocURL)
                    } label: {
                        HStack {
                            Label("View Head Document".localized, systemImage: "doc.text.image")
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
            
            // Damage Records - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isDamageExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                        
                        Text("Damage Records".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if !guncelArac.hasarKayitlari.isEmpty {
                            Text("(\(guncelArac.hasarKayitlari.count))")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isDamageExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button {
                    hasarEkleGoster = true
                } label: {
                    Label(guncelArac.hasarKayitlari.isEmpty ? "Add First Damage Record" : "Add Damage Record", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                
                if isDamageExpanded {
                if guncelArac.hasarKayitlari.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                                .foregroundColor(.gray)
                        Text("No Damage Records".localized)
                            .font(.headline)
                        Text("This vehicle has no recorded damages.".localized)
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                    }
                    .onDelete(perform: hasarSil)
                }
                }
            }
            
            // Return Processes - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isReturnExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                        
                        Text("Return Processes".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if !aracIadeleri.isEmpty {
                            Text("(\(aracIadeleri.count))")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isReturnExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if isReturnExpanded {
                    if aracIadeleri.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 40))
                                .foregroundColor(.gray)
                        Text("No Return Operations".localized)
                            .font(.headline)
                        Text("This vehicle has no recorded return operations.".localized)
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
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        }
                    }
                }
            }
            
            // Check Out Processes - Expandable Section
            Section {
                // Modern Expandable Button Header
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExitExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                        
                        Text("Check Out Processes".localized)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        if !aracExitleri.isEmpty {
                            Text("(\(aracExitleri.count))")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExitExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if !isExitExpanded, let parkedExit = aracExitleri.first(where: { $0.status == .parked }) {
                    NavigationLink(destination: ExitDetayView(exit: parkedExit)) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "car.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.purple)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("This vehicle is parked".localized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.purple)
                                Text("Check out is saved as parked. Tap to continue and complete.".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.purple.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.40), lineWidth: 1.0)
                        )
                        .shadow(color: Color.purple.opacity(0.10), radius: 4, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)
                }
                
                if isExitExpanded {
                    if aracExitleri.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No Check Out Operations".localized)
                                .font(.headline)
                            Text("This vehicle has no recorded check out operations.".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(aracExitleri) { exit in
                            NavigationLink(destination: ExitDetayView(exit: exit)) {
                                ExitSatirView(exit: exit)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        }
                    }
                }
            }
            
            Section {
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    Label("Aracı Sil".localized, systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Araç Detayları".localized)
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
        .sheet(isPresented: $checkInGoster) {
            if let exit = latestOpenOutboundExit {
                SheetWrapper {
                    NavigationView {
                        CheckInView(aracId: guncelArac.id, linkedExit: exit)
                    }
                }
            }
        }
        .sheet(isPresented: $exitIslemGoster) {
            SheetWrapper {
                NavigationView {
                    ExitIslemView(arac: guncelArac, existingExit: selectedExitForEditing)
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
        .sheet(isPresented: $showCompanyPicker) {
            CompanyPickerView(
                selectedCompany: Binding(
                    get: { selectedCompany },
                    set: { newCompany in
                        var updatedArac = guncelArac
                        updatedArac.assistantCompanyName = newCompany?.name
                        updatedArac.assistantCompanyPhone = newCompany?.phoneNumber
                        viewModel.aracGuncelle(updatedArac)
                        arac = updatedArac
                    }
                )
            )
            .environmentObject(viewModel)
        }
        .alert("Delete check-in?".localized, isPresented: Binding(
            get: { checkInSilmeOnayi != nil },
            set: { if !$0 { checkInSilmeOnayi = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { checkInSilmeOnayi = nil }
            Button("Delete".localized, role: .destructive) {
                if let snap = checkInSilmeOnayi {
                    viewModel.aracCheckInKaydiSil(aracId: guncelArac.id, checkInId: snap.id) { ok in
                        if ok {
                            ToastManager.shared.show("Check-in removed".localized, type: .info)
                        }
                    }
                }
                checkInSilmeOnayi = nil
            }
        } message: {
            Text("This removes only this check-in record from the vehicle.".localized)
        }
        .alert("Aracı Sil".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Sil".localized, role: .destructive) {
                viewModel.aracSil(guncelArac)
                
                // Show deletion toast
                ToastManager.shared.show("✓ Vehicle Deleted", type: .success)
                
                // Navigate back after deletion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        } message: {
            Text("Bu aracı ve tüm hasar kayıtlarını silmek istediğinizden emin misiniz?".localized)
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
    
    func servisDurumGuncelle(servis: Servis, yeniDurum: Servis.ServisDurum) {
        guard servis.durum != yeniDurum else { return }
        
        var guncellenmisServis = servis
        guncellenmisServis.durum = yeniDurum
        
        // Eğer tamamlandı ise teslim tarihini ayarla
        if yeniDurum == .tamamlandi && guncellenmisServis.teslimTarihi == nil {
            guncellenmisServis.teslimTarihi = Date()
        }
        
        viewModel.servisGuncelle(guncellenmisServis)
        
        // Show success toast
        ToastManager.shared.show("✓ Service Status Updated", type: .success)
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
                    Text("Image not available".localized)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Head Document".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
}

struct HasarSatirView: View {
    let hasar: HasarKaydi
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hasar.resKodu)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !hasar.notlar.isEmpty {
                            Text(hasar.notlar)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(hasar.tarih.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(hasar.km) km")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    if !hasar.fotograflar.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("\(hasar.fotograflar.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 2, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        hasar.durum == .done ? .green : .orange
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

