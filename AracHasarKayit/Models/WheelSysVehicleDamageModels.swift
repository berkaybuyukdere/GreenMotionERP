import Foundation

struct WheelSysVehicleDamageAttachment: Identifiable, Hashable, Codable {
    let attachmentId: String
    let filename: String
    let fileType: String
    let previewable: Bool
    let previewPath: String?

    var id: String { attachmentId }

    var isImage: Bool { fileType.lowercased() == "image" }
}

struct WheelSysVehicleDamageRelatedItem: Identifiable, Hashable, Codable {
    let type: String
    let label: String
    let url: String?

    var id: String { "\(type)-\(label)-\(url ?? "")" }
}

struct WheelSysVehicleDamageRecord: Identifiable, Hashable, Codable {
    let damageId: String
    let damageNo: String?
    let vehicleId: Int
    let plateNo: String?
    let normalizedPlateNo: String?
    let damageType: String?
    let area: String?
    let element: String?
    let action: String?
    let memo: String?
    let chargeText: String?
    let chargeAmount: Double?
    let currency: String?
    let relatedRentalNo: String?
    let addedOn: String?
    let recordedBy: String?
    let recordedOn: String?
    let labourHours: String?
    let attachments: [WheelSysVehicleDamageAttachment]
    let relatedItems: [WheelSysVehicleDamageRelatedItem]
    let source: String
    let syncedAt: String

    var id: String { damageId }

    var displayTitle: String {
        let parts = [damageType, area, element]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return "Unknown damage".localized }
        return parts.joined(separator: " · ")
    }

    var locationSummary: String {
        [area, element]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var previewAttachments: [WheelSysVehicleDamageAttachment] {
        attachments.filter { $0.previewable && ($0.previewPath?.isEmpty == false) }
    }
}

struct WheelSysVehicleDamageHistoryResponse: Hashable {
    let vehicleId: Int
    let resolvedVehicleEntityId: String
    let damages: [WheelSysVehicleDamageRecord]
    let damageCount: Int
    let syncedAt: String
}
