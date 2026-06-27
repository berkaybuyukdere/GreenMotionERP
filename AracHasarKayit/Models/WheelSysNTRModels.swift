import Foundation

struct WheelSysLoggedInUser: Codable, Equatable {
    let id: String
    let name: String
}

enum WheelSysNTRType: Int, CaseIterable, Identifiable {
    case stationChange = 1
    case repair = 2
    case maintenance = 3

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .stationChange: return "wheelsys_ntr.type_station_change"
        case .repair: return "wheelsys_ntr.type_repair"
        case .maintenance: return "wheelsys_ntr.type_maintenance"
        }
    }

    var iconName: String {
        switch self {
        case .stationChange: return "arrow.triangle.swap"
        case .repair: return "wrench.and.screwdriver"
        case .maintenance: return "gearshape"
        }
    }
}

enum WheelSysNTRStatus: String, Codable, Equatable {
    case active
    case closed
}

enum WheelSysNTRSyncStatus: String, Codable, Equatable {
    case success
    case failed
    case pendingRetry
}

struct WheelSysNTRVehiclePayload: Equatable {
    let plateNo: String
    let wheelsysVehicleId: String
    let carGroup: String
    let modelName: String
    let modelId: String?
    let mileage: Int
    let fuelEighths: Int
}

struct WheelSysNTRCreateRequest: Equatable {
    let vehicle: WheelSysNTRVehiclePayload
    let type: WheelSysNTRType
    let station: String
    let startDateTime: Date
    let plannedEndDateTime: Date
}

struct WheelSysNTRCloseRequest: Equatable {
    let ntrEntityId: Int
    let closeKm: Int
    let closeFuelEighths: Int
    let closeDateTime: Date?
    let station: String
}

struct WheelSysAfterSaveResult: Codable, Equatable {
    let success: Bool
    let keyValue: Int?
    let message: String?
    let procException: String?
    let mustReloadEntity: Bool?
    let docNo: String?
}

struct WheelSysNTRCreateResult: Equatable {
    let entityId: Int
    let docNo: String?
    let loggedInUser: WheelSysLoggedInUser
    let afterSave: WheelSysAfterSaveResult
}

struct WheelSysNTRCloseResult: Equatable {
    let entityId: Int
    let loggedInUser: WheelSysLoggedInUser
    let afterSave: WheelSysAfterSaveResult
    let milesTravelled: Int
    let fuelUsed: Int
    let closeDateTime: Date
}

/// Resolved create vs close mode from Firestore + fleet chart.
struct WheelSysNTRResolvedContext: Equatable {
    let isCloseMode: Bool
    let entityId: Int?
    /// Where the entity id came from: firestore | fleet | none
    let entitySource: String

    static let create = WheelSysNTRResolvedContext(isCloseMode: false, entityId: nil, entitySource: "none")
}

struct WheelSysNTRLocalRecord: Codable, Equatable {
    var wheelsysNtrEntityId: Int?
    var wheelsysNtrDocNo: String?
    var wheelsysNtrStatus: WheelSysNTRStatus?
    var wheelsysNtrSyncStatus: WheelSysNTRSyncStatus?
    var wheelsysVehicleId: String?
    var plateNo: String?
    var createdByWheelsysUserId: String?
    var createdByWheelsysUserName: String?
    var startedAt: Date?
    var startKm: Int?
    var startFuel: Int?
    var closedByWheelsysUserId: String?
    var closedByWheelsysUserName: String?
    var closedAt: Date?
    var closeKm: Int?
    var closeFuel: Int?
    var milesTravelled: Int?
    var fuelUsed: Int?
    var lastSyncError: String?
    var historyEntry: WheelSysNTRHistoryEntry?
    /// When true, active NTR start fields are cleared after a successful close.
    var clearActiveState: Bool = false
}

/// Persisted NTR audit row (open / close) on the vehicle document.
struct WheelSysNTRHistoryEntry: Codable, Equatable, Identifiable, Hashable {
    enum Action: String, Codable, Equatable {
        case opened
        case closed
    }

    var id: String
    var action: Action
    var entityId: Int
    var docNo: String?
    var ntrType: Int?
    var wheelsysUserId: String?
    var wheelsysUserName: String?
    var appUserName: String?
    var timestamp: Date
    var km: Int?
    var fuelEighths: Int?
    var milesTravelled: Int?
    var fuelUsed: Int?
    var notes: String?

    static func opened(
        entityId: Int,
        docNo: String?,
        type: WheelSysNTRType,
        wheelsysUser: WheelSysLoggedInUser,
        appUserName: String?,
        km: Int,
        fuel: Int,
        notes: String? = nil
    ) -> WheelSysNTRHistoryEntry {
        WheelSysNTRHistoryEntry(
            id: UUID().uuidString,
            action: .opened,
            entityId: entityId,
            docNo: docNo,
            ntrType: type.rawValue,
            wheelsysUserId: wheelsysUser.id,
            wheelsysUserName: wheelsysUser.name,
            appUserName: appUserName,
            timestamp: Date(),
            km: km,
            fuelEighths: fuel,
            milesTravelled: nil,
            fuelUsed: nil,
            notes: normalizedNotes(notes)
        )
    }

    static func closed(
        entityId: Int,
        docNo: String?,
        wheelsysUser: WheelSysLoggedInUser,
        appUserName: String?,
        km: Int,
        fuel: Int,
        milesTravelled: Int,
        fuelUsed: Int,
        notes: String? = nil
    ) -> WheelSysNTRHistoryEntry {
        WheelSysNTRHistoryEntry(
            id: UUID().uuidString,
            action: .closed,
            entityId: entityId,
            docNo: docNo,
            ntrType: nil,
            wheelsysUserId: wheelsysUser.id,
            wheelsysUserName: wheelsysUser.name,
            appUserName: appUserName,
            timestamp: Date(),
            km: km,
            fuelEighths: fuel,
            milesTravelled: milesTravelled,
            fuelUsed: fuelUsed,
            notes: normalizedNotes(notes)
        )
    }

    private static func normalizedNotes(_ notes: String?) -> String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Why a new NTR cannot be opened right now (fleet / app state).
enum WheelSysNTRCreateBlockReason: Equatable {
    case activeNTR(docNo: String?)
    case onRental(resHint: String?)
    case assignedBooking(docNo: String?)
    case openCheckout(resNo: String?)
    case openReturn

    var localizedMessage: String {
        switch self {
        case .activeNTR(let doc):
            if let doc, !doc.isEmpty {
                return String(format: "wheelsys_ntr.block_active_ntr".localized, doc)
            }
            return "wheelsys_ntr.block_active_ntr_generic".localized
        case .onRental(let res):
            if let res, !res.isEmpty {
                return String(format: "wheelsys_ntr.block_on_rental".localized, res)
            }
            return "wheelsys_ntr.rental_overlap".localized
        case .assignedBooking(let doc):
            if let doc, !doc.isEmpty {
                return String(format: "wheelsys_ntr.block_assigned_booking".localized, doc)
            }
            return "wheelsys_ntr.block_assigned_booking_generic".localized
        case .openCheckout(let res):
            if let res, !res.isEmpty {
                return String(format: "wheelsys_ntr.block_open_checkout".localized, res)
            }
            return "wheelsys_ntr.block_open_checkout_generic".localized
        case .openReturn:
            return "wheelsys_ntr.block_open_return".localized
        }
    }
}

enum VehicleFleetOpsFilter: String, CaseIterable, Identifiable {
    case all
    case ntr
    case available
    case rental
    case parking

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "vehicles.filter.all"
        case .ntr: return "vehicles.filter.ntr"
        case .available: return "vehicles.filter.available"
        case .rental: return "vehicles.filter.rental"
        case .parking: return "vehicles.filter.parking"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "car.2"
        case .ntr: return "wrench"
        case .available: return "checkmark.circle"
        case .rental: return "key"
        case .parking: return "parkingsign"
        }
    }
}

extension Notification.Name {
    static let wheelSysNTRDidChange = Notification.Name("wheelSysNTRDidChange")
    static let wheelSysFleetStatusDidRefresh = Notification.Name("wheelSysFleetStatusDidRefresh")
}
