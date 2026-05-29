import Foundation
import Combine

enum FranchisePresenceStatus: String, Equatable {
    case online
    case away
    case offline
    case active

    var label: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .offline: return "Offline"
        case .active: return "Active"
        }
    }

    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .offline: return "circle.slash"
        case .active: return "bolt.fill"
        }
    }

    var accentToken: String {
        switch self {
        case .online, .active: return "success"
        case .away: return "accent"
        case .offline: return "muted"
        }
    }
}

struct FranchiseUserPresence: Identifiable, Equatable {
    let userId: String
    let userName: String
    let userRole: String
    let status: FranchisePresenceStatus
    let updatedAt: Date

    var id: String { userId }

    var relativeUpdate: String {
        FranchisePresenceFormatters.relative.string(for: updatedAt) ?? ""
    }
}

private enum FranchisePresenceFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "en_GB")
        return f
    }()
}

@MainActor
enum LiveFranchisePresenceService {
    private static let presenceFreshness: TimeInterval = 45 * 60
    private static let activeFreshness: TimeInterval = 20 * 60

    static func roster(from events: [LiveActivityEvent]) -> [FranchiseUserPresence] {
        let now = Date()
        var byUser: [String: (name: String, role: String, presence: LiveActivityEvent?, lastOp: LiveActivityEvent?)] = [:]

        for event in events {
            var slot = byUser[event.userId] ?? (event.userName, event.userRole, nil, nil)
            slot.name = event.userName
            slot.role = event.userRole
            if event.kind.isPresence {
                if slot.presence == nil || event.createdAt > (slot.presence?.createdAt ?? .distantPast) {
                    slot.presence = event
                }
            } else if event.kind.isOperational {
                if slot.lastOp == nil || event.createdAt > (slot.lastOp?.createdAt ?? .distantPast) {
                    slot.lastOp = event
                }
            }
            byUser[event.userId] = slot
        }

        return byUser.map { userId, slot in
            let status = resolveStatus(presence: slot.presence, lastOp: slot.lastOp, now: now)
            let updatedAt = max(
                slot.presence?.createdAt ?? .distantPast,
                slot.lastOp?.createdAt ?? .distantPast
            )
            return FranchiseUserPresence(
                userId: userId,
                userName: slot.name,
                userRole: slot.role,
                status: status,
                updatedAt: updatedAt == .distantPast ? now : updatedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            return lhs.userName.localizedCaseInsensitiveCompare(rhs.userName) == .orderedAscending
        }
    }

    private static func resolveStatus(
        presence: LiveActivityEvent?,
        lastOp: LiveActivityEvent?,
        now: Date
    ) -> FranchisePresenceStatus {
        if let presence, now.timeIntervalSince(presence.createdAt) <= presenceFreshness {
            switch presence.kind {
            case .presenceOnline: return .online
            case .presenceAway: return .away
            case .presenceOffline: return .offline
            default: break
            }
        }
        if let lastOp, now.timeIntervalSince(lastOp.createdAt) <= activeFreshness {
            return .active
        }
        return .offline
    }
}

private extension FranchisePresenceStatus {
    var sortRank: Int {
        switch self {
        case .online: return 0
        case .active: return 1
        case .away: return 2
        case .offline: return 3
        }
    }
}
