import SwiftUI

struct ServisView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var searchQuery = ""
    @State private var yeniServisGoster = false
    @State private var durumFiltresi: Servis.ServisDurum?
    @State private var servisFirmalarGoster = false
    
    var filtreliServisler: [Servis] {
        var servisler = viewModel.servisler
        
        // Status filtering
        if let durum = durumFiltresi {
            servisler = servisler.filter { $0.durum == durum }
        }
        
        // Search filtering
        if !searchQuery.isEmpty {
            servisler = servisler.filter { servis in
                servis.aracPlaka.localizedCaseInsensitiveContains(searchQuery) ||
                servis.servisFirmaAdi.localizedCaseInsensitiveContains(searchQuery) ||
                servis.aciklama.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        return servisler.sorted { $0.gonderilmeTarihi > $1.gonderilmeTarihi }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Metric Cards Section
                if !viewModel.servisler.isEmpty {
                    metricCardsSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Search & Filter Section
                searchFilterSection
                    .padding(.horizontal)
                    .padding(.top, viewModel.servisler.isEmpty ? 8 : 16)
                
                // List Section
                if viewModel.servisler.isEmpty {
                    emptyStateView
                        .frame(maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    serviceListSection
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Service Records".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done".localized) {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        yeniServisGoster = true
                    } label: {
                        Label("Add New Service".localized, systemImage: "plus.circle")
                    }
                    
                    if !viewModel.servisler.isEmpty {
                        Divider()
                        
                        Button {
                            exportServislerCSV()
                        } label: {
                            Label("Download CSV".localized, systemImage: "doc.text")
                        }
                        
                        Button {
                            exportServislerXLSX()
                        } label: {
                            Label("Download Excel".localized, systemImage: "tablecells")
                        }
                        
                        Button {
                            exportServislerPDF()
                        } label: {
                            Label("Download PDF".localized, systemImage: "doc.richtext")
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        servisFirmalarGoster = true
                    } label: {
                        Label("Service Companies".localized, systemImage: "building.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $yeniServisGoster) {
            NavigationView {
                ServisEkleView()
            }
        }
        .sheet(isPresented: $servisFirmalarGoster) {
            NavigationView {
                ServisFirmalariView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filtreliServisler.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: durumFiltresi)
    }
    
    // MARK: - Metric Cards Section
    private var metricCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview".localized)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ServiceMetricCard(
                    title: "Total".localized,
                    value: "\(viewModel.servisler.count)",
                    icon: "wrench.and.screwdriver.fill",
                    color: .blue
                )
                .transition(.scale.combined(with: .opacity))
                
                ServiceMetricCard(
                    title: "In Service".localized,
                    value: "\(viewModel.aktifServisSayisi)",
                    icon: "clock.fill",
                    color: .orange
                )
                .transition(.scale.combined(with: .opacity))
                
                ServiceMetricCard(
                    title: "Completed".localized,
                    value: "\(viewModel.tamamlananServisSayisi)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                .transition(.scale.combined(with: .opacity))
                
                ServiceMetricCard(
                    title: "Cancelled".localized,
                    value: "\(viewModel.iptalServisSayisi)",
                    icon: "xmark.circle.fill",
                    color: .red
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Search & Filter Section
    private var searchFilterSection: some View {
        VStack(spacing: 16) {
            // Search Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Search".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search by plate, company, or description".localized, text: $searchQuery)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            }
            
            // Status Filter Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    DurumFiltreBadge(
                        baslik: "All".localized,
                        secili: durumFiltresi == nil
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            durumFiltresi = nil
                        }
                    }
                    
                    ForEach(Servis.ServisDurum.allCases, id: \.self) { durum in
                        DurumFiltreBadge(
                            baslik: durum.displayTitle,
                            secili: durumFiltresi == durum,
                            renk: Color(uiColor: durum.renk)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                durumFiltresi = durum
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Service List Section
    private var serviceListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(filtreliServisler.enumerated()), id: \.element.id) { index, servis in
                NavigationLink(destination: ServisDetayView(servis: servis)) {
                    ServisSatirView(servis: servis)
                }
                .buttonStyle(.plain)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("No Service Records".localized)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Your vehicle service records will appear here".localized)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                HapticManager.shared.medium()
                yeniServisGoster = true
            } label: {
                Label("Add Service Record".localized, systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
    }
    
    func servisSil(at offsets: IndexSet) {
        for index in offsets {
            let servis = filtreliServisler[index]
            viewModel.servisSil(servis)
        }
    }
    
    // Export fonksiyonlarÄ±
    func exportServislerCSV() {
        ServisExportManager.shared.exportToCSV(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func exportServislerXLSX() {
        ServisExportManager.shared.exportToXLSX(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func exportServislerPDF() {
        ServisExportManager.shared.exportToPDF(servisler: viewModel.servisler, viewController: getRootViewController())
    }
    
    func getRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .filter { $0.isKeyWindow }
            .first?.rootViewController
    }
}

// MARK: - Service Metric Card
struct ServiceMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? color.opacity(0.4) : color.opacity(0.2), lineWidth: colorScheme == .dark ? 1.5 : 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 8, x: 0, y: 2)
    }
}
