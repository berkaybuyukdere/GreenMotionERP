import UIKit

/// Holds guided-capture results from the scanner until `HasarEkleView` consumes them for the same vehicle.
final class GuidedInspectionPhotoBuffer {
    static let shared = GuidedInspectionPhotoBuffer()

    private let lock = NSLock()
    private var byVehicle: [UUID: [UIImage]] = [:]

    func set(photos: [UIImage], for vehicleId: UUID) {
        lock.lock()
        byVehicle[vehicleId] = photos
        lock.unlock()
    }

    func takePhotos(for vehicleId: UUID) -> [UIImage]? {
        lock.lock()
        defer { lock.unlock() }
        return byVehicle.removeValue(forKey: vehicleId)
    }
}
