import Foundation
import Combine

/// Repository protocol for vehicle operations
protocol VehicleRepository {
    func getVehicles() async throws -> [Arac]
    func saveVehicle(_ vehicle: Arac) async throws
    func updateVehicle(_ vehicle: Arac) async throws
    func deleteVehicle(id: UUID) async throws
    func observeVehicles(completion: @escaping ([Arac]) -> Void) -> AnyCancellable?
}

/// Firebase implementation of VehicleRepository
class FirebaseVehicleRepository: VehicleRepository {
    private let firebaseService: FirebaseService
    
    init(firebaseService: FirebaseService = FirebaseService.shared) {
        self.firebaseService = firebaseService
    }
    
    func getVehicles() async throws -> [Arac] {
        return try await withCheckedThrowingContinuation { continuation in
            firebaseService.loadAraclar { vehicles, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let vehicles = vehicles {
                    continuation.resume(returning: vehicles)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func saveVehicle(_ vehicle: Arac) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            firebaseService.saveArac(vehicle) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func updateVehicle(_ vehicle: Arac) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            firebaseService.updateArac(vehicle) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func deleteVehicle(id: UUID) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            firebaseService.deleteArac(id: id) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func observeVehicles(completion: @escaping ([Arac]) -> Void) -> AnyCancellable? {
        // Note: This would need to be adapted to return a cancellable
        // For now, we'll use the existing observeAraclar method
        firebaseService.observeAraclar(completion: completion)
        return nil // Would need proper implementation
    }
}

/// Mock implementation for testing
class MockVehicleRepository: VehicleRepository {
    var vehicles: [Arac] = []
    var shouldThrowError = false
    
    func getVehicles() async throws -> [Arac] {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1)
        }
        return vehicles
    }
    
    func saveVehicle(_ vehicle: Arac) async throws {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1)
        }
        vehicles.append(vehicle)
    }
    
    func updateVehicle(_ vehicle: Arac) async throws {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1)
        }
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        }
    }
    
    func deleteVehicle(id: UUID) async throws {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1)
        }
        vehicles.removeAll { $0.id == id }
    }
    
    func observeVehicles(completion: @escaping ([Arac]) -> Void) -> AnyCancellable? {
        completion(vehicles)
        return nil
    }
}

