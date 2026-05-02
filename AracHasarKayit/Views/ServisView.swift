import SwiftUI
import UIKit

struct ServisView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var searchQuery = ""
    @State private var yeniServisGoster = false
    @State private var durumFiltresi: Servis.ServisDurum?
    @State private var servisFirmalarGoster = false
    @State private var isRefreshingServis = false
    @State private var lastServisSync: Date?
    
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
                if let last = lastServisSync {
                    HStack {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "Last synced: %@".localized, last.formatted(date: .omitted, time: .shortened)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%d records".localized, viewModel.servisler.count))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        guard !isRefreshingServis else { return }
                        isRefreshingServis = true
                        viewModel.servisleriYukle {
                            lastServisSync = Date()
                            isRefreshingServis = false
                        }
                    } label: {
                        Group {
                            if isRefreshingServis {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .disabled(isRefreshingServis)
                    .accessibilityLabel("Refresh service records".localized)
                    
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
                    
                    Button("Done".localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
                
                ServiceMetricCard(
                    title: "In Service".localized,
                    value: "\(viewModel.aktifServisSayisi)",
                    icon: "clock.fill",
                    color: .orange
                )
                
                ServiceMetricCard(
                    title: "Completed".localized,
                    value: "\(viewModel.tamamlananServisSayisi)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                ServiceMetricCard(
                    title: "Cancelled".localized,
                    value: "\(viewModel.iptalServisSayisi)",
                    icon: "xmark.circle.fill",
                    color: .red
                )
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
                        .stroke(Color.blue.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1)
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
    /// Use a regular `VStack` inside `ScrollView` (not `LazyVStack`) so row spacing stays tight; `LazyVStack` + `NavigationLink` often leaves large random gaps.
    private var serviceListSection: some View {
        VStack(spacing: 12) {
            ForEach(filtreliServisler) { servis in
                NavigationLink(destination: ServisDetayView(servis: servis)) {
                    ServisSatirView(servis: servis)
                }
                .buttonStyle(.plain)
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
        ServisExportManager.shared.exportToCSV(servisler: filtreliServisler, viewController: exportPresenter())
    }
    
    func exportServislerXLSX() {
        ServisExportManager.shared.exportToXLSX(servisler: filtreliServisler, viewController: exportPresenter())
    }
    
    func exportServislerPDF() {
        ServisExportManager.shared.exportToPDF(servisler: filtreliServisler, viewController: exportPresenter())
    }

    private func exportPresenter() -> UIViewController? {
        ServisExportManager.bestPresenterViewController()
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
                    .foregroundColor(Color(.systemGray))
                
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
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 4, x: 0, y: 1)
    }
}
