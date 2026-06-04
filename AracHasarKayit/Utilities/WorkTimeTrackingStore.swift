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
        isHoliday: Bool = false,
        ohnePause: Bool = false
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw WorkTimeStoreError.notSignedIn
        }
        let franchiseId = FirebaseService.shared.currentFranchiseId
        let dayKey = WorkTimeEntry.dayKey(for: day)
        let docId = WorkTimeEntry.documentId(userId: uid, dayKey: dayKey)
        let rawMinutes = isHoliday ? 0 : WorkTimeEntry.totalMinutes(day: day, clockIn: clockIn, clockOut: clockOut)
        let total = WorkTimeEntry.billingMinutes(rawMinutes: rawMinutes, franchiseId: franchiseId, ohnePause: ohnePause)
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
            "ohnePause": ohnePause,
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

        upsertLocalEntry(
            docId: docId,
            userId: uid,
            franchiseId: franchiseId,
            dayKey: dayKey,
            clockIn: clockIn,
            clockOut: clockOut,
            totalMinutes: total,
            displayName: displayName,
            email: email,
            notes: notes,
            isHoliday: isHoliday,
            ohnePause: ohnePause
        )
    }

    private func upsertLocalEntry(
        docId: String,
        userId: String,
        franchiseId: String,
        dayKey: String,
        clockIn: Date,
        clockOut: Date,
        totalMinutes: Int,
        displayName: String,
        email: String,
        notes: String,
        isHoliday: Bool,
        ohnePause: Bool
    ) {
        let row = WorkTimeEntry(
            id: docId,
            userId: userId,
            franchiseId: franchiseId,
            dayKey: dayKey,
            clockIn: clockIn,
            clockOut: clockOut,
            totalMinutes: totalMinutes,
            userDisplayName: displayName,
            userEmail: email,
            notes: notes,
            updatedAt: Date(),
            isHoliday: isHoliday,
            ohnePause: ohnePause
        )
        if let idx = entries.firstIndex(where: { $0.id == docId }) {
            entries[idx] = row
        } else {
            entries.append(row)
        }
        entries.sort { $0.dayKey < $1.dayKey }
    }

    func deleteEntry(day: Date, storedEntry: WorkTimeEntry? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ [WorkTimeDelete] not signed in")
            throw WorkTimeStoreError.notSignedIn
        }
        let dayKey = storedEntry?.dayKey ?? WorkTimeEntry.dayKey(for: day)
        let ownerId = storedEntry?.userId ?? uid
        let docId = WorkTimeEntry.documentId(userId: ownerId, dayKey: dayKey)
        let franchiseId = FirebaseService.shared.currentFranchiseId

        print("🗑️ [WorkTimeDelete] start docId=\(docId) franchise=\(franchiseId) auth=\(uid) owner=\(ownerId) dayKey=\(dayKey)")

        guard ownerId == uid else {
            print("❌ [WorkTimeDelete] blocked — entry owner \(ownerId) != auth \(uid)")
            throw WorkTimeStoreError.cannotDeleteOthersEntry
        }

        let existingData = await fetchExistingData(docId: docId)
        if existingData == nil {
            print("⚠️ [WorkTimeDelete] no Firestore doc at \(docId) — removing local row only")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FirebaseService.shared.getCollectionReference("workTimeEntries")
                .document(docId)
                .delete { error in
                    if let error {
                        print("❌ [WorkTimeDelete] Firestore delete failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                        print("✅ [WorkTimeDelete] Firestore delete OK docId=\(docId)")
                        continuation.resume()
                    }
                }
        }

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

        let before = entries.count
        entries.removeAll { $0.userId == ownerId && $0.dayKey == dayKey }
        print("✅ [WorkTimeDelete] local entries \(before) → \(entries.count)")
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
    case cannotDeleteOthersEntry

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in.".localized
        case .cannotDeleteOthersEntry:
            return "You can only delete your own work time entries.".localized
        }
    }
}
