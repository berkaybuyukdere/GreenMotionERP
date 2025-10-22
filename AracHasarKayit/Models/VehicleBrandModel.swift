import Foundation

/// Vehicle brand and model data structure
struct VehicleBrand: Identifiable, Codable {
    let id: String
    let name: String
    let models: [String]
    
    init(id: String, name: String, models: [String]) {
        self.id = id
        self.name = name
        self.models = models
    }
}

/// Manager for vehicle brands and models
class VehicleBrandManager {
    static let shared = VehicleBrandManager()
    
    private init() {}
    
    // MARK: - Pre-defined Brands and Models
    
    let brands: [VehicleBrand] = [
        VehicleBrand(
            id: "renault",
            name: "Renault",
            models: ["Clio", "Megane", "Captur", "Kadjar", "Talisman", "Zoe"]
        ),
        VehicleBrand(
            id: "bmw",
            name: "BMW",
            models: ["1 Series", "2 Series", "3 Series", "4 Series", "5 Series", "X1", "X3", "X5", "iX3"]
        ),
        VehicleBrand(
            id: "toyota",
            name: "Toyota",
            models: ["RAV4", "C-HR", "Corolla", "Camry", "Yaris", "Aygo X", "Highlander"]
        ),
        VehicleBrand(
            id: "ford",
            name: "Ford",
            models: ["Fiesta", "Focus", "Puma", "Kuga", "Mustang", "Ranger"]
        ),
        VehicleBrand(
            id: "mercedes",
            name: "Mercedes-Benz",
            models: ["A-Class", "B-Class", "C-Class", "E-Class", "GLA", "GLC", "Vito", "Sprinter"]
        ),
        VehicleBrand(
            id: "vw",
            name: "Volkswagen",
            models: ["Golf", "Polo", "Tiguan", "T-Roc", "Passat", "Arteon", "ID.3", "ID.4"]
        ),
        VehicleBrand(
            id: "mini",
            name: "Mini Cooper",
            models: ["3 Door", "5 Door", "Clubman", "Countryman", "John Cooper Works"]
        ),
        VehicleBrand(
            id: "skoda",
            name: "Skoda",
            models: ["Fabia", "Scala", "Octavia", "Superb", "Kamiq", "Karoq", "Kodiaq"]
        ),
        VehicleBrand(
            id: "honda",
            name: "Honda",
            models: ["Jazz", "Civic", "HR-V", "CR-V", "e", "ZR-V"]
        ),
        VehicleBrand(
            id: "audi",
            name: "Audi",
            models: ["A3", "A4", "A6", "Q2", "Q3", "Q5", "Q7", "e-tron"]
        ),
        VehicleBrand(
            id: "opel",
            name: "Opel",
            models: ["Corsa", "Astra", "Insignia", "Crossland", "Grandland", "Mokka"]
        ),
        VehicleBrand(
            id: "peugeot",
            name: "Peugeot",
            models: ["208", "308", "508", "2008", "3008", "5008"]
        ),
        VehicleBrand(
            id: "citroen",
            name: "Citroen",
            models: ["C3", "C4", "C5 Aircross", "Berlingo", "Spacetourer"]
        ),
        VehicleBrand(
            id: "seat",
            name: "Seat",
            models: ["Ibiza", "Leon", "Arona", "Ateca", "Tarraco"]
        ),
        VehicleBrand(
            id: "fiat",
            name: "Fiat",
            models: ["500", "Panda", "Tipo", "500X", "500L"]
        ),
        VehicleBrand(
            id: "volvo",
            name: "Volvo",
            models: ["XC40", "XC60", "XC90", "S60", "S90", "V60", "V90"]
        ),
        VehicleBrand(
            id: "mazda",
            name: "Mazda",
            models: ["CX-3", "CX-5", "CX-9", "MX-5", "RX-8", "RX-7", "RX-9"]
        ),
        VehicleBrand(
            id: "land-rover",
            name: "Land Rover",
            models: ["Discovery", "Range Rover", "Range Rover Sport", "Range Rover Velar", "Range Rover Evoque"]
        ),
        VehicleBrand(
            id: "lexus",
            name: "Lexus",
            models: ["RX", "NX", "LX", "ES", "IS", "LS", "UX"]
        ),
        VehicleBrand(
            id: "hyundai",
            name: "Hyundai",
            models: ["Creta", "Elantra", "Santa Fe", "Tucson", "Venue", "Kona", "ix35"]
        ),
        VehicleBrand(
            id: "dacia",
            name: "Dacia",
            models: ["Duster", "Sandero", "Logan", "Spring", "Spring Electric", "Spring Hybrid"]
        ),
        VehicleBrand(
            id: "kia",
            name: "Kia",
            models: ["Sportage", "Sorento", "Carnival", "Stonic", "Niro", "Rio", "Ceed"]
        ),
        VehicleBrand(
            id: "mitsubishi",
            name: "Mitsubishi",
            models: ["Outlander", "ASX", "Eclipse Cross", "L200", "Mirage", "Space Star", "Space Gear"]
        )
        
    ]
    
    // MARK: - Helper Methods
    
    /// Get all brand names
    var brandNames: [String] {
        brands.map { $0.name }.sorted()
    }
    
    /// Get models for a specific brand
    func models(for brandName: String) -> [String] {
        guard let brand = brands.first(where: { $0.name == brandName }) else {
            return []
        }
        return brand.models.sorted()
    }
    
    /// Check if brand exists
    func brandExists(_ name: String) -> Bool {
        brands.contains(where: { $0.name.lowercased() == name.lowercased() })
    }
    
    /// Check if model exists for brand
    func modelExists(_ modelName: String, for brandName: String) -> Bool {
        let brandModels = models(for: brandName)
        return brandModels.contains(where: { $0.lowercased() == modelName.lowercased() })
    }
}

