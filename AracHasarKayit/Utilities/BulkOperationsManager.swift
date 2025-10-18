import Foundation
import SwiftUI

/// Bulk operations manager for multiple selections
class BulkOperationsManager: ObservableObject {
    @Published var selectedVehicles: Set<UUID> = []
    @Published var isSelectionMode = false
    @Published var operationInProgress = false
    
    func toggleSelection(_ vehicleId: UUID) {
        if selectedVehicles.contains(vehicleId) {
            selectedVehicles.remove(vehicleId)
        } else {
            selectedVehicles.insert(vehicleId)
        }
    }
    
    func selectAll(_ vehicles: [Arac]) {
        selectedVehicles = Set(vehicles.map { $0.id })
    }
    
    func deselectAll() {
        selectedVehicles.removeAll()
    }
    
    func bulkDelete(_ vehicles: [Arac], completion: @escaping (Int) -> Void) {
        let selected = vehicles.filter { selectedVehicles.contains($0.id) }
        operationInProgress = true
        
        CascadeDeleteManager.shared.bulkDeleteVehicles(selected) { progress, total in
            print("Progress: \(progress)/\(total)")
        } completion: { result in
            self.operationInProgress = false
            self.deselectAll()
            
            switch result {
            case .success(let count):
                completion(count)
            case .failure:
                completion(0)
            }
        }
    }
    
    func bulkExport(_ vehicles: [Arac]) -> URL? {
        let selected = vehicles.filter { selectedVehicles.contains($0.id) }
        var csvString = "Plate,Brand,Model,Category,Damages,Vignette,Keys\n"
        
        for vehicle in selected {
            csvString += "\(vehicle.plaka),\(vehicle.marka),\(vehicle.model),\(vehicle.kategori),\(vehicle.hasarKayitlari.count),\(vehicle.vignetteVar),\(vehicle.spareKeyCount)\n"
        }
        
        let filename = "vehicles_export_\(Date().timeIntervalSince1970).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        try? csvString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

