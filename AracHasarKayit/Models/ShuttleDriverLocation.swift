import Foundation
import CoreLocation
import FirebaseFirestore

struct ShuttleDriverLocation: Identifiable, Equatable {
    let id: String
    let driverUid: String
    let driverName: String
    let latitude: Double
    let longitude: Double
    let isSharing: Bool
    let updatedAt: Date
    let sharingEndedAt: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isLiveOnMap: Bool { isSharing }

    var offlineSince: Date? {
        isSharing ? nil : (sharingEndedAt ?? updatedAt)
    }

    static func from(document: QueryDocumentSnapshot) -> ShuttleDriverLocation? {
        let data = document.data()
        guard let uid = data["driverUid"] as? String,
              let lat = data["latitude"] as? Double,
              let lng = data["longitude"] as? Double else { return nil }
        let sharing = data["isSharing"] as? Bool ?? false
        let name = (data["driverName"] as? String) ?? "Shuttle"
        let updated: Date
        if let ts = data["updatedAt"] as? Timestamp {
            updated = ts.dateValue()
        } else {
            updated = Date()
        }
        let ended: Date?
        if let ts = data["sharingEndedAt"] as? Timestamp {
            ended = ts.dateValue()
        } else {
            ended = nil
        }
        // Show live drivers; show offline ghost pin for ~2h after sharing stopped.
        if sharing {
            return ShuttleDriverLocation(
                id: document.documentID,
                driverUid: uid,
                driverName: name,
                latitude: lat,
                longitude: lng,
                isSharing: true,
                updatedAt: updated,
                sharingEndedAt: nil
            )
        }
        guard let ended else { return nil }
        let age = Date().timeIntervalSince(ended)
        guard age < 2 * 3600 else { return nil }
        return ShuttleDriverLocation(
            id: document.documentID,
            driverUid: uid,
            driverName: name,
            latitude: lat,
            longitude: lng,
            isSharing: false,
            updatedAt: updated,
            sharingEndedAt: ended
        )
    }
}
