import Foundation
import FirebaseFirestore

enum VehicleServiceFlagKind: String, Codable, CaseIterable, Identifiable {
    case needsService = "needs_service"
    case ntrReceived = "ntr_received"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .needsService: return "vehicle_service_flag.needs_service".localized
        case .ntrReceived: return "vehicle_service_flag.ntr_received".localized
        }
    }

    var icon: String {
        switch self {
        case .needsService: return "wrench.and.screwdriver.fill"
        case .ntrReceived: return "doc.text.fill"
        }
    }

    var accentColorName: String {
        switch self {
        case .needsService: return "red"
        case .ntrReceived: return "orange"
        }
    }
}

struct VehicleServiceFlag: Identifiable, Equatable {
    let vehicleId: String
    var plate: String
    var kind: VehicleServiceFlagKind
    var note: String
    var updatedByUid: String
    var updatedByName: String
    var updatedAt: Date
    var franchiseId: String

    var id: String { vehicleId }

    init?(
        document: QueryDocumentSnapshot
    ) {
        let data = document.data()
        guard let kindRaw = data["kind"] as? String,
              let kind = VehicleServiceFlagKind(rawValue: kindRaw),
              let plate = data["plate"] as? String else { return nil }
        vehicleId = document.documentID
        self.plate = plate
        self.kind = kind
        note = data["note"] as? String ?? ""
        updatedByUid = data["updatedByUid"] as? String ?? ""
        updatedByName = data["updatedByName"] as? String ?? ""
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["updatedAt"] as? Timestamp {
            updatedAt = ts.dateValue()
        } else {
            updatedAt = Date()
        }
    }

    init(
        vehicleId: String,
        plate: String,
        kind: VehicleServiceFlagKind,
        note: String,
        updatedByUid: String,
        updatedByName: String,
        updatedAt: Date = Date(),
        franchiseId: String
    ) {
        self.vehicleId = vehicleId
        self.plate = plate
        self.kind = kind
        self.note = note
        self.updatedByUid = updatedByUid
        self.updatedByName = updatedByName
        self.updatedAt = updatedAt
        self.franchiseId = franchiseId.uppercased()
    }

    var firestorePayload: [String: Any] {
        [
            "vehicleId": vehicleId,
            "plate": plate,
            "kind": kind.rawValue,
            "note": note,
            "updatedByUid": updatedByUid,
            "updatedByName": updatedByName,
            "updatedAt": Timestamp(date: updatedAt),
            "franchiseId": franchiseId,
            "pinned": true
        ]
    }
}
