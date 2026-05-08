import Foundation
import FirebaseFirestore

enum GarageServiceJobStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case completed

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .pending: return "garage_service.status.pending".localized
        case .completed: return "garage_service.status.completed".localized
        }
    }
}

/// Predefined service reasons; stored as `purpose` string on Firestore (raw value).
enum GarageServiceJobPurpose: String, CaseIterable, Identifiable, Codable {
    case routineMaintenance
    case repair
    case tireService
    case bodywork
    case inspection
    case glass
    case other

    var id: String { rawValue }

    var localizedTitle: String {
        "garage_service.purpose.\(rawValue)".localized
    }
}

struct GarageServiceJob: Identifiable, Codable, Equatable {
    var id: UUID
    /// Firestore document id (may differ from `id` if web creates docs).
    var documentId: String?
    var vehicleId: UUID
    var vehiclePlate: String
    var targetGarageId: String
    /// Human readable service company / garage name snapshot.
    var targetGarageName: String?
    /// `GarageServiceJobPurpose.rawValue` or freeform code from web.
    var purpose: String
    var notes: String
    var photoURLs: [String]
    /// Optional progress photos from service company during completion flow.
    var completionPhotoURLs: [String]
    var serviceDate: Date
    var status: GarageServiceJobStatus
    var createdAt: Date
    var createdBy: String?
    var completedAt: Date?
    var completionNotes: String?
    var franchiseId: String
    /// When garage marks job complete, web queues email to this address (optional).
    var pickupNotifyEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, documentId, vehicleId, vehiclePlate, targetGarageId, targetGarageName, purpose, notes, photoURLs
        case completionPhotoURLs, serviceDate, status, createdAt, createdBy, completedAt, completionNotes
        case franchiseId, pickupNotifyEmail
    }
}
