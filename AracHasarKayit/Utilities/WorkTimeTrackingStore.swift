import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class WorkTimeTrackingStore: ObservableObject {
    @Published private(set) var entries: [WorkTimeEntry] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var loadTask: Task<Void, Never>?

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func loadEntries(forMonth month: Date, viewAllInFranchise: Bool) {
        loadTask?.cancel()
        guard let uid = Auth.auth().currentUser?.uid else {
            entries = []
            return
        }

        let range = WorkTimeEntry.monthDayKeyRange(for: month)
        isLoading = true
        lastError = nil

        loadTask = Task {
            var q: Query = FirebaseService.shared.getFilteredQuery("workTimeEntries")
                .whereField("dayKey", isGreaterThanOrEqualTo: range.start)
                .whereField("dayKey", isLessThanOrEqualTo: range.end)
            if !viewAllInFranchise {
                q = q.whereField("userId", isEqualTo: uid)
            }

            do {
                let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
                    q.getDocuments { snapshot, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let snapshot else {
                            continuation.resume(throwing: NSError(domain: "WorkTime", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty snapshot"]))
                            return
                        }
                        continuation.resume(returning: snapshot)
                    }
                }
                if Task.isCancelled { return }
                let parsed = snapshot.documents.compactMap { WorkTimeEntry.fromDocument($0) }
                self.entries = parsed.sorted { $0.dayKey < $1.dayKey }
                self.isLoading = false
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                self.entries = []
                if FirebaseService.isPermissionError(error) {
                    self.lastError = "Work hours could not be loaded (permission).".localized
                } else {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func saveEntry(
        day: Date,
        clockIn: Date,
        clockOut: Date,
        notes: String,
        profile: UserProfile?,
        isHoliday: Bool = false
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw WorkTimeStoreError.notSignedIn
        }
        let franchiseId = FirebaseService.shared.currentFranchiseId
        let dayKey = WorkTimeEntry.dayKey(for: day)
        let docId = WorkTimeEntry.documentId(userId: uid, dayKey: dayKey)
        let total = isHoliday ? 0 : WorkTimeEntry.totalMinutes(day: day, clockIn: clockIn, clockOut: clockOut)
        let displayName = profile?.displayName ?? ""
        let email = profile?.email ?? ""

        // Fetch existing doc for audit diff
        let existingData = await fetchExistingData(docId: docId)

        let newData: [String: Any] = [
            "franchiseId": franchiseId,
            "userId": uid,
            "dayKey": dayKey,
            "clockIn": Timestamp(date: clockIn),
            "clockOut": Timestamp(date: clockOut),
            "totalMinutes": total,
            "userDisplayName": displayName,
            "userEmail": email,
            "notes": notes,
            "isHoliday": isHoliday,
            "updatedAt": Timestamp(date: Date())
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FirebaseService.shared.getCollectionReference("workTimeEntries")
                .document(docId)
                .setData(newData, merge: true) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
        }

        // Audit log — after successful write
        let auditData: [String: Any] = [
            "dayKey": dayKey,
            "clockIn": clockIn.formatted(date: .numeric, time: .shortened),
            "clockOut": clockOut.formatted(date: .numeric, time: .shortened),
            "totalMinutes": total,
            "notes": notes
        ]
        if let old = existingData {
            let oldAudit: [String: Any] = [
                "dayKey": old["dayKey"] as? String ?? dayKey,
                "clockIn": (old["clockIn"] as? Timestamp)?.dateValue().formatted(date: .numeric, time: .shortened) ?? "",
                "clockOut": (old["clockOut"] as? Timestamp)?.dateValue().formatted(date: .numeric, time: .shortened) ?? "",
                "totalMinutes": old["totalMinutes"] as? Int ?? 0,
                "notes": old["notes"] as? String ?? ""
            ]
            AuditTrailManager.shared.logUpdate(tableName: "workTimeEntries", recordId: docId, oldData: oldAudit, newData: auditData)
        } else {
            AuditTrailManager.shared.logCreation(tableName: "workTimeEntries", recordId: docId, data: auditData)
        }
    }

    func deleteEntry(day: Date) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw WorkTimeStoreError.notSignedIn
        }
        let dayKey = WorkTimeEntry.dayKey(for: day)
        let docId = WorkTimeEntry.documentId(userId: uid, dayKey: dayKey)

        // Fetch existing data for audit before deletion
        let existingData = await fetchExistingData(docId: docId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FirebaseService.shared.getCollectionReference("workTimeEntries")
                .document(docId)
                .delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
        }

        // Audit log — after successful delete
        let auditData: [String: Any]
        if let old = existingData {
            auditData = [
                "dayKey": old["dayKey"] as? String ?? dayKey,
                "clockIn": (old["clockIn"] as? Timestamp)?.dateValue().formatted(date: .numeric, time: .shortened) ?? "",
                "clockOut": (old["clockOut"] as? Timestamp)?.dateValue().formatted(date: .numeric, time: .shortened) ?? "",
                "totalMinutes": old["totalMinutes"] as? Int ?? 0,
                "notes": old["notes"] as? String ?? ""
            ]
        } else {
            auditData = ["dayKey": dayKey]
        }
        AuditTrailManager.shared.logDeletion(tableName: "workTimeEntries", recordId: docId, data: auditData)
    }

    private func fetchExistingData(docId: String) async -> [String: Any]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: Any]?, Never>) in
            FirebaseService.shared.getCollectionReference("workTimeEntries")
                .document(docId)
                .getDocument { snapshot, _ in
                    continuation.resume(returning: snapshot?.data())
                }
        }
    }

    func teamAggregates(from list: [WorkTimeEntry]) -> [TeamWorkAggregate] {
        let grouped = Dictionary(grouping: list, by: \.userId)
        return grouped.map { uid, items in
            let name = items.first?.userDisplayName ?? uid
            let email = items.first?.userEmail ?? ""
            let total = items.reduce(0) { $0 + $1.totalMinutes }
            return TeamWorkAggregate(userId: uid, displayName: name, email: email, totalMinutes: total)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

enum WorkTimeStoreError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in.".localized
        }
    }
}
