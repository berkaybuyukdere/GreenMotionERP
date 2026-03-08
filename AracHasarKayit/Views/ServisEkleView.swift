import SwiftUI

struct ServisEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var duzenlenecekServis: Servis?
    var preSelectedAracId: UUID?
    
    @State private var seciliAracId: UUID?
    @State private var seciliServisFirmaId: UUID?
    @State private var servisFirmaAdi = ""
    @State private var durum: Servis.ServisDurum = .serviste
    @State private var gonderilmeTarihi = Date()
    @State private var teslimTarihi: Date?
    @State private var teslimTarihiVar = false
    @State private var aciklama = ""
    @State private var seciliNedenler: Set<Servis.ServisNeden> = []
    
    var duzenlemeModuMu: Bool {
        duzenlenecekServis != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Vehicle Selection
                formCard(title: "Vehicle".localized, icon: "car.fill") {
                    if viewModel.araclar.isEmpty {
                        Text("No vehicles registered yet".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("Select Vehicle".localized, selection: $seciliAracId) {
                            Text("Select vehicle".localized).tag(nil as UUID?)
                            ForEach(viewModel.araclar) { arac in
                                Text("\(arac.plakaFormatli) - \(arac.marka) \(arac.model)")
                                    .tag(arac.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.horizontal)
                
                // Service Company Selection
                formCard(title: "Service Company".localized, icon: "building.2.fill") {
                    if viewModel.servisFirmalari.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            TextField("Service Company Name".localized, text: $servisFirmaAdi)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray4), lineWidth: 0.5)
                                )
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        NavigationLink(destination: ServisFirmalariView()) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Add Service Company".localized)
                                    .foregroundColor(.blue)
                            }
                        }
                    } else {
                        Picker("Select Company".localized, selection: $seciliServisFirmaId) {
                            Text("Enter manually".localized).tag(nil as UUID?)
                            ForEach(viewModel.servisFirmalari) { firma in
                                Text(firma.ad).tag(firma.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: seciliServisFirmaId) { oldValue, newValue in
                            if let firmaId = newValue,
                               let firma = viewModel.servisFirmalari.first(where: { $0.id == firmaId }) {
                                servisFirmaAdi = firma.ad
                            }
                        }
                        
                        if seciliServisFirmaId == nil {
                            Divider()
                                .padding(.vertical, 8)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16))
                                TextField("Service Company Name".localized, text: $servisFirmaAdi)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray4), lineWidth: 0.5)
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal)
                
                // Service Reasons
                formCard(title: "Service Reasons".localized, icon: "checkmark.circle.fill") {
                    ForEach(Servis.ServisNeden.allCases, id: \.self) { neden in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if seciliNedenler.contains(neden) {
                                    seciliNedenler.remove(neden)
                                } else {
                                    seciliNedenler.insert(neden)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: neden.icon)
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16))
                                    .frame(width: 24)
                                
                                Text(neden.displayTitle)
                                    .foregroundColor(.primary)
                                    .font(.system(size: 15))
                                
                                Spacer()
                                
                                Image(systemName: seciliNedenler.contains(neden) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(seciliNedenler.contains(neden) ? .green : .gray)
                                    .font(.system(size: 20))
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        
                        if neden != Servis.ServisNeden.allCases.last {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Service Status
                formCard(title: "Status".localized, icon: "info.circle.fill") {
                    Picker("Service Status".localized, selection: $durum) {
                        ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                            Label(durum.displayTitle, systemImage: durum.icon)
                                .tag(durum)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Dates
                formCard(title: "Dates".localized, icon: "calendar") {
                    DatePicker("Send Date".localized, selection: $gonderilmeTarihi, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    Toggle("Set Delivery Date".localized, isOn: $teslimTarihiVar)
                    
                    if teslimTarihiVar {
                        Divider()
                            .padding(.vertical, 8)
                        
                        DatePicker("Delivery Date".localized, selection: Binding(
                            get: { teslimTarihi ?? Date() },
                            set: { teslimTarihi = $0 }
                        ), displayedComponents: [.date])
                        .datePickerStyle(.compact)
                    }
                }
                .padding(.horizontal)
                
                // Description
                formCard(title: "Description".localized, icon: "text.alignleft") {
                    TextEditor(text: $aciklama)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray4), lineWidth: 0.5)
                                )
                        )
                }
                .padding(.horizontal)
                
                // Save Button
                Button {
                    kaydet()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(duzenlemeModuMu ? "Update".localized : "Save".localized)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(formGecerli ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!formGecerli)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top, 8)
        }
        .navigationTitle(duzenlemeModuMu ? "Edit Service".localized : "New Service".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) {
                    dismiss()
                }
            }
        }
        .onAppear {
            // Eğer pre-selected araç varsa onu seç
            if let preSelectedId = preSelectedAracId {
                seciliAracId = preSelectedId
            }
            
            if let servis = duzenlenecekServis {
                seciliAracId = servis.aracId
                seciliServisFirmaId = servis.servisFirmaId
                servisFirmaAdi = servis.servisFirmaAdi
                durum = servis.durum
                gonderilmeTarihi = servis.gonderilmeTarihi
                teslimTarihi = servis.teslimTarihi
                teslimTarihiVar = servis.teslimTarihi != nil
                aciklama = servis.aciklama
                seciliNedenler = Set(servis.servisNedenleri)
            }
        }
    }
    
    var formGecerli: Bool {
        seciliAracId != nil && !servisFirmaAdi.isEmpty && !seciliNedenler.isEmpty
    }
    
    func kaydet() {
        guard let aracId = seciliAracId,
              let arac = viewModel.araclar.first(where: { $0.id == aracId }) else { return }
        
        if duzenlemeModuMu, var servis = duzenlenecekServis {
            servis.aracId = aracId
            servis.aracPlaka = arac.plakaFormatli
            servis.servisFirmaId = seciliServisFirmaId
            servis.servisFirmaAdi = servisFirmaAdi
            servis.durum = durum
            servis.gonderilmeTarihi = gonderilmeTarihi
            servis.teslimTarihi = teslimTarihiVar ? teslimTarihi : nil
            servis.aciklama = aciklama
            servis.servisNedenleri = Array(seciliNedenler)
            viewModel.servisGuncelle(servis)
            
            // Show update toast
            ToastManager.shared.show("✓ Service Updated", type: .info)
        } else {
            let yeniServis = Servis(
                aracId: aracId,
                aracPlaka: arac.plakaFormatli,
                servisFirmaId: seciliServisFirmaId,
                servisFirmaAdi: servisFirmaAdi,
                durum: durum,
                gonderilmeTarihi: gonderilmeTarihi,
                aciklama: aciklama,
                servisNedenleri: Array(seciliNedenler)
            )
            viewModel.servisEkle(yeniServis)
            
            // Show success toast
            ToastManager.shared.show("✓ Service Added", type: .success)
        }
        
        dismiss()
    }
    
    // MARK: - Form Card
    private func formCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Divider()
                .background(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4))
            
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 6, x: 0, y: 2)
    }
}
