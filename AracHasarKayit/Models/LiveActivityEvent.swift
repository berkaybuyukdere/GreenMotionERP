import Foundation
import FirebaseFirestore

/// Real-time operational event for CH admin live feed (actions only — no page views).
enum LiveActivityKind: String, Codable, CaseIterable {
    case checkoutCompleted = "checkout_completed"
    case checkoutParked = "checkout_parked"
    case checkoutDeleted = "checkout_deleted"
    case returnCompleted = "return_completed"
    case returnDeleted = "return_deleted"
    case damageCreated = "damage_created"
    case damageUpdated = "damage_updated"
    case damageCompleted = "damage_completed"
    case damageDeleted = "damage_deleted"
    case officeCreated = "office_created"
    case officeUpdated = "office_updated"
    case officeDeleted = "office_deleted"
    case washingCreated = "washing_created"
    case washingUpdated = "washing_updated"
    case washingDeleted = "washing_deleted"
    case shuttleSharingOn = "shuttle_sharing_on"
    case shuttleCustomerPing = "shuttle_customer_ping"
    case login = "login"
    case logout = "logout"
    case presenceOnline = "presence_online"
    case presenceOffline = "presence_offline"
    case presenceAway = "presence_away"

    /// Legacy / page-view kinds — hidden from the admin feed.
    static let legacyHiddenKinds: Set<String> = [
        "vehicle_opened", "checkout_started", "return_started",
        "inspection_opened", "shuttle_map_opened", "panel_opened", "jarvis_opened"
    ]

    static func isVisibleInFeed(rawValue: String) -> Bool {
        guard !legacyHiddenKinds.contains(rawValue),
              let kind = LiveActivityKind(rawValue: rawValue) else { return false }
        return kind.isOperational
    }

    var isOperational: Bool {
        switch self {
        case .presenceOnline, .presenceOffline, .presenceAway:
            return false
        default:
            return true
        }
    }

    var isPresence: Bool {
        switch self {
        case .presenceOnline, .presenceOffline, .presenceAway:
            return true
        default:
            return false
        }
    }

    var icon: String {
        switch self {
        case .checkoutCompleted, .checkoutParked, .checkoutDeleted:
            return "arrow.right.circle.fill"
        case .returnCompleted, .returnDeleted:
            return "arrow.uturn.backward.circle.fill"
        case .damageCreated, .damageUpdated, .damageCompleted, .damageDeleted:
            return "exclamationmark.triangle.fill"
        case .officeCreated, .officeUpdated, .officeDeleted:
            return "building.2.fill"
        case .washingCreated, .washingUpdated, .washingDeleted:
            return "drop.fill"
        case .shuttleSharingOn, .shuttleCustomerPing:
            return "bus.fill"
        case .login, .logout:
            return "person.crop.circle.fill"
        case .presenceOnline:
            return "circle.fill"
        case .presenceOffline:
            return "circle.slash"
        case .presenceAway:
            return "moon.fill"
        }
    }

    var accentToken: String {
        switch self {
        case .checkoutCompleted, .returnCompleted, .damageCompleted, .officeCreated, .washingCreated:
            return "success"
        case .damageCreated, .shuttleCustomerPing:
            return "warning"
        case .checkoutDeleted, .returnDeleted, .damageDeleted, .officeDeleted, .washingDeleted:
            return "critical"
        case .checkoutParked, .presenceAway:
            return "accent"
        case .presenceOnline, .login:
            return "success"
        case .presenceOffline, .logout:
            return "muted"
        default:
            return "muted"
        }
    }

    /// Human-readable label for search (English keys; matches event titles).
    var searchLabel: String {
        switch self {
        case .checkoutCompleted: return "check-out completed"
        case .checkoutParked: return "check-out parked"
        case .checkoutDeleted: return "check-out deleted"
        case .returnCompleted: return "return completed"
        case .returnDeleted: return "return deleted"
        case .damageCreated: return "damage created"
        case .damageUpdated: return "damage updated"
        case .damageCompleted: return "damage completed"
        case .damageDeleted: return "damage deleted"
        case .officeCreated: return "office operation created"
        case .officeUpdated: return "office operation updated"
        case .officeDeleted: return "office operation deleted"
        case .washingCreated: return "washing created"
        case .washingUpdated: return "washing updated"
        case .washingDeleted: return "washing deleted"
        case .shuttleSharingOn: return "shuttle location sharing"
        case .shuttleCustomerPing: return "shuttle customer ping"
        case .login: return "sign in login"
        case .logout: return "sign out logout"
        case .presenceOnline: return "online"
        case .presenceOffline: return "offline"
        case .presenceAway: return "away"
        }
    }
}

struct LiveActiveUserSummary: Identifiable, Equatable {
    let userId: String
    let userName: String
    let userRole: String
    let lastSeenAt: Date
    let lastTitle: String

    var id: String { userId }

    var relativeLastSeen: String {
        RelativeDateTimeFormatter.liveFeed.string(for: lastSeenAt) ?? ""
    }
}

struct LiveActivityEvent: Identifiable, Equatable {
    let id: String
    let userId: String
    let userName: String
    let userRole: String
    let kind: LiveActivityKind
    let title: String
    let subtitle: String
    let plate: String?
    let recordId: String?
    let franchiseId: String
    let createdAt: Date
    let deviceInfo: String?

    var relativeTime: String {
        RelativeDateTimeFormatter.liveFeed.string(for: createdAt) ?? ""
    }

    var exactTime: String {
        LiveActivityEvent.exactFormatter.string(from: createdAt)
    }

    var searchBlob: String {
        [
            userName,
            userRole,
            title,
            subtitle,
            plate ?? "",
            kind.searchLabel
        ]
        .joined(separator: " ")
        .lowercased()
    }

    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return searchBlob.contains(q)
    }

    private static let exactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd MMM · HH:mm"
        return f
    }()

    static func from(document: QueryDocumentSnapshot) -> LiveActivityEvent? {
        let data = document.data()
        guard let uid = data["userId"] as? String,
              let kindRaw = data["kind"] as? String,
              !LiveActivityKind.legacyHiddenKinds.contains(kindRaw),
              let kind = LiveActivityKind(rawValue: kindRaw),
              let title = data["title"] as? String else { return nil }
        let created: Date
        if let ts = data["createdAt"] as? Timestamp {
            created = ts.dateValue()
        } else {
            created = Date()
        }
        return LiveActivityEvent(
            id: document.documentID,
            userId: uid,
            userName: (data["userName"] as? String) ?? "User",
            userRole: (data["userRole"] as? String) ?? "",
            kind: kind,
            title: title,
            subtitle: (data["subtitle"] as? String) ?? "",
            plate: data["plate"] as? String,
            recordId: data["recordId"] as? String,
            franchiseId: (data["franchiseId"] as? String) ?? "CH",
            createdAt: created,
            deviceInfo: data["deviceInfo"] as? String
        )
    }
}

private extension RelativeDateTimeFormatter {
    static let liveFeed: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "en_GB")
        return f
    }()
}
