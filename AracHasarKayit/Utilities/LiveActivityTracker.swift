import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

/// Writes lightweight live ops events to `franchises/{id}/live_activity` for the CH admin feed.
final class LiveActivityTracker {
    static let shared = LiveActivityTracker()

    private var lastEmitAt: [String: Date] = [:]
    private let throttleSeconds: TimeInterval = 18
    private let presenceThrottleSeconds: TimeInterval = 600
    private let queue = DispatchQueue(label: "live.activity.tracker", qos: .utility)

    private var didEmitOnlineThisForegroundSession = false

    private init() {}

    func record(
        _ kind: LiveActivityKind,
        title: String,
        subtitle: String = "",
        plate: String? = nil,
        recordId: String? = nil,
        userProfile: UserProfile? = nil,
        force: Bool = false
    ) {
        guard Auth.auth().currentUser != nil else { return }
        let franchiseId = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !franchiseId.isEmpty else { return }

        let throttleKey = "\(kind.rawValue)|\(plate ?? "")|\(recordId ?? "")|\(title)"
        let interval = kind.isPresenceKind ? presenceThrottleSeconds : throttleSeconds
        if !force {
            let now = Date()
            if let last = lastEmitAt[throttleKey], now.timeIntervalSince(last) < interval {
                return
            }
            lastEmitAt[throttleKey] = now
        }

        let profile = userProfile
        let displayName = profile?.displayName
            ?? Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "User"
        let role = profile?.role.rawValue ?? ""

        var payload: [String: Any] = [
            "userId": Auth.auth().currentUser?.uid ?? "",
            "userName": displayName,
            "userRole": role,
            "kind": kind.rawValue,
            "title": title,
            "subtitle": subtitle,
            "franchiseId": franchiseId,
            "createdAt": FieldValue.serverTimestamp(),
            "deviceInfo": deviceInfo()
        ]
        if let plate, !plate.isEmpty { payload["plate"] = plate }
        if let recordId, !recordId.isEmpty { payload["recordId"] = recordId }

        queue.async {
            FirebaseService.shared
                .getCollectionReference("live_activity")
                .addDocument(data: payload) { error in
                    if let error {
                        print("⚠️ [LiveActivity] \(error.localizedDescription)")
                    }
                }
        }
    }

    func recordLogin(userProfile: UserProfile?) {
        record(
            .login,
            title: "Signed in",
            subtitle: userProfile?.email ?? Auth.auth().currentUser?.email ?? "",
            userProfile: userProfile,
            force: true
        )
        didEmitOnlineThisForegroundSession = false
        recordAppForeground(userProfile: userProfile)
    }

    func recordLogout(userProfile: UserProfile?) {
        record(
            .logout,
            title: "Signed out",
            subtitle: userProfile?.email ?? "",
            userProfile: userProfile,
            force: true
        )
        didEmitOnlineThisForegroundSession = false
    }

    func recordAppForeground(userProfile: UserProfile?) {
        guard !didEmitOnlineThisForegroundSession else { return }
        didEmitOnlineThisForegroundSession = true
        record(
            .presenceOnline,
            title: "Online",
            subtitle: "App in foreground",
            userProfile: userProfile,
            force: true
        )
    }

    func recordAppBackground(userProfile: UserProfile?) {
        didEmitOnlineThisForegroundSession = false
        record(
            .presenceOffline,
            title: "Offline",
            subtitle: "App in background",
            userProfile: userProfile,
            force: true
        )
    }

    func recordAppInactive(userProfile: UserProfile?) {
        record(
            .presenceAway,
            title: "Away",
            subtitle: "App inactive",
            userProfile: userProfile,
            force: false
        )
    }

    private func deviceInfo() -> String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }
}

private extension LiveActivityKind {
    var isPresenceKind: Bool {
        switch self {
        case .presenceOnline, .presenceOffline, .presenceAway:
            return true
        default:
            return false
        }
    }
}
