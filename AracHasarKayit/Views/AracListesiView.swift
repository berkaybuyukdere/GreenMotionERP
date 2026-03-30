import SwiftUI

struct AracListesiView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Binding var navigateToVehicleId: UUID?
    @State private var yeniAracGoster = false
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""

    // Filtered vehicles based on search query
    private var filteredAraclar: [Arac] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return viewModel.araclar
        }
        let q = searchText.lowercased()
        return viewModel.araclar.filter {
            $0.plakaFormatli.lowercased().contains(q) ||
            $0.marka.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.kategori.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.araclar.isEmpty {
                    BosDurumView(yeniAracGoster: $yeniAracGoster)
                } else {
                    vehicleListView
                }
            }
            .navigationTitle("Vehicles".localized)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by plate, model or category…".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        yeniAracGoster = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $yeniAracGoster) {
                NavigationView { ManuelAracEkleView() }
            }
            .navigationDestination(for: Arac.self) { vehicle in
                AracDetayView(arac: vehicle)
            }
            .onChange(of: navigateToVehicleId) { vehicleId in
                guard let vehicleId = vehicleId else { return }
                guard let vehicle = viewModel.araclar.first(where: { $0.id == vehicleId }) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigationPath.append(vehicle)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        navigateToVehicleId = nil
                    }
                }
            }
        }
    }

    // MARK: - Vehicle List View
    @ViewBuilder
    private var vehicleListView: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty

        if isSearching {
            // Flat search results
            if filteredAraclar.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filteredAraclar) { vehicle in
                        NavigationLink(destination: AracDetayView(arac: vehicle)) {
                            ModernAracSatirView(arac: vehicle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        } else {
            categoriesFirstView
        }
    }

    // MARK: - Categories First View
    private var categoriesFirstView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let kategoriler = viewModel.kategoriler
                ForEach(kategoriler, id: \.self) { kategori in
                    CategoryExpandableCard(
                        name: kategori,
                        vehicles: viewModel.araclar.filter { $0.kategori == kategori }
                    )
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Satır (Row) Görünümü
struct ModernAracSatirView: View {
    let arac: Arac
    
    private var sonHasar: HasarKaydi? {
        arac.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih }).first
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(arac.plakaFormatli)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(arac.marka) \(arac.model)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Responsive badges with wrapping
                HStack(spacing: 6) {
                    // Category badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "tag.fill").font(.system(size: 9))
                        Text(arac.kategori).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)

                    // Spare key badge (compact)
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill").font(.system(size: 9))
                        Text("\(arac.spareKeyCount)").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)

                    // Vignette badge (compact)
                    if arac.vignetteVar {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                            Text("Vig").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            Spacer()
            
            // Requested: hide right-side Done/Progress indicator from Vehicles list UI.
        }
        .padding(.vertical, 6)
    }
}

private struct DurumRozeti: View {
    let title: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - Boş Durum
private struct BosDurumView: View {
    @Binding var yeniAracGoster: Bool
    
    var body: some View {
        EmptyStateView(
            icon: "car.circle.fill",
            title: "No Vehicles Yet",
            message: "Start by scanning a vehicle or adding one manually",
            buttonText: "Add Vehicle",
            buttonAction: { yeniAracGoster = true }
        )
    }
}

// MARK: - Category Expandable Card
private struct CategoryExpandableCard: View {
    let name: String
    let vehicles: [Arac]
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "car.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    // Category Name
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Count Badge
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .font(.caption2)
                        Text("\(vehicles.count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .cornerRadius(12)
                    
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            
            // Expanded Content
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                ForEach(vehicles) { vehicle in
                    NavigationLink(destination: AracDetayView(arac: vehicle)) {
                        ModernAracSatirView(arac: vehicle)
                            .padding(.leading, 16)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                                                        }
                    )
                    
                    if vehicle.id != vehicles.last?.id {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

