import Foundation
import SwiftUI

/// Advanced search and filter manager for vehicles
class SearchFilterManager: ObservableObject {
    @Published var searchText = ""
    @Published var selectedCategory: String?
    @Published var showOnlyDamaged = false
    @Published var showOnlyAvailable = false
    @Published var showOnlyWithVignette = false
    @Published var sortOption: SortOption = .plateAscending
    @Published var dateRange: DateRange?
    
    enum SortOption: String, CaseIterable {
        case plateAscending = "Plate (A-Z)"
        case plateDescending = "Plate (Z-A)"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostDamages = "Most Damages"
        case leastDamages = "Least Damages"
        case brandAscending = "Brand (A-Z)"
    }
    
    struct DateRange {
        let start: Date
        let end: Date
    }
    
    func filterAndSort(_ vehicles: [Arac]) -> [Arac] {
        var filtered = vehicles
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { vehicle in
                vehicle.plaka.localizedCaseInsensitiveContains(searchText) ||
                vehicle.marka.localizedCaseInsensitiveContains(searchText) ||
                vehicle.model.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Category filter
        if let category = selectedCategory {
            filtered = filtered.filter { $0.kategori == category }
        }
        
        // Damage filters
        if showOnlyDamaged {
            filtered = filtered.filter { !$0.hasarKayitlari.isEmpty }
        }
        if showOnlyAvailable {
            filtered = filtered.filter { $0.hasarKayitlari.isEmpty }
        }
        
        // Vignette filter
        if showOnlyWithVignette {
            filtered = filtered.filter { $0.vignetteVar }
        }
        
        // Date range filter
        if let range = dateRange {
            filtered = filtered.filter { vehicle in
                vehicle.kayitTarihi >= range.start && vehicle.kayitTarihi <= range.end
            }
        }
        
        // Sort
        switch sortOption {
        case .plateAscending:
            filtered.sort { $0.plaka < $1.plaka }
        case .plateDescending:
            filtered.sort { $0.plaka > $1.plaka }
        case .newestFirst:
            filtered.sort { $0.kayitTarihi > $1.kayitTarihi }
        case .oldestFirst:
            filtered.sort { $0.kayitTarihi < $1.kayitTarihi }
        case .mostDamages:
            filtered.sort { $0.hasarKayitlari.count > $1.hasarKayitlari.count }
        case .leastDamages:
            filtered.sort { $0.hasarKayitlari.count < $1.hasarKayitlari.count }
        case .brandAscending:
            filtered.sort { $0.marka < $1.marka }
        }
        
        return filtered
    }
    
    func resetFilters() {
        searchText = ""
        selectedCategory = nil
        showOnlyDamaged = false
        showOnlyAvailable = false
        showOnlyWithVignette = false
        dateRange = nil
        sortOption = .plateAscending
    }
    
    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedCategory != nil || showOnlyDamaged || showOnlyAvailable || showOnlyWithVignette || dateRange != nil
    }
}

