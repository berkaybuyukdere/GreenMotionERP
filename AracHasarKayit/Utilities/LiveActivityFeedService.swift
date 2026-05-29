import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class LiveActivityFeedService: ObservableObject {
    static let shared = LiveActivityFeedService()

    @Published private(set) var events: [LiveActivityEvent] = []
    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?

    private var listener: ListenerRegistration?
    private var listenRetainCount = 0

    private init() {}

    func retainListening() {
        listenRetainCount += 1
        startListening()
    }

    func releaseListening() {
        listenRetainCount = max(0, listenRetainCount - 1)
        if listenRetainCount == 0 {
            stopListening()
        }
    }

    func startListening() {
        guard listener == nil else { return }
        let franchiseId = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !franchiseId.isEmpty else { return }

        isListening = true
        lastError = nil

        listener = FirebaseService.shared
            .getCollectionReference("live_activity")
            .order(by: "createdAt", descending: true)
            .limit(to: 80)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        return
                    }
                    let items = snapshot?.documents.compactMap { LiveActivityEvent.from(document: $0) } ?? []
                    self.events = Self.dedupeFeedEvents(items)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        isListening = false
        events = []
    }

    var operationalEvents: [LiveActivityEvent] {
        events
    }

    func filteredEvents(matching search: String) -> [LiveActivityEvent] {
        events.filter { $0.matches(search: search) }
    }

    /// Collapse noisy / duplicate feed rows (same user + action + record within one minute).
    private static func dedupeFeedEvents(_ items: [LiveActivityEvent]) -> [LiveActivityEvent] {
        var seen = Set<String>()
        var out: [LiveActivityEvent] = []
        out.reserveCapacity(items.count)

        for event in items {
            guard event.kind.isOperational else { continue }
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            switch event.kind {
            case .login, .logout, .presenceOnline, .presenceOffline, .presenceAway:
                continue
            default:
                break
            }

            let minuteBucket = Int(event.createdAt.timeIntervalSince1970 / 60)
            let recordKey = event.recordId ?? event.title
            let key = "\(event.userId)|\(event.kind.rawValue)|\(recordKey)|\(minuteBucket)"
            guard seen.insert(key).inserted else { continue }
            out.append(event)
        }
        return out
    }

    var latestOperationalEvent: LiveActivityEvent? {
        operationalEvents.first
    }

    var presenceRoster: [FranchiseUserPresence] {
        LiveFranchisePresenceService.roster(from: events)
    }

    var eventsLast15Minutes: Int {
        let cutoff = Date().addingTimeInterval(-900)
        return operationalEvents.filter { $0.createdAt >= cutoff }.count
    }
}
