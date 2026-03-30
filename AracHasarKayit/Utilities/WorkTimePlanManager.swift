import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Model

struct WorkTimePlan: Identifiable, Codable {
    /// Document ID is "{franchiseId}_{monthKey}" e.g. "CH_2026-03"
    var id: String
    var franchiseId: String
    var monthKey: String
    var fileURL: String
    var contentType: String       // "image/jpeg", "application/pdf", "text/csv" etc.
    var originalFileName: String
    var uploaderName: String
    var uploadedAt: Date

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 2000, c.month ?? 1)
    }

    static func documentId(franchiseId: String, monthKey: String) -> String {
        "\(franchiseId)_\(monthKey)"
    }

    static func from(_ doc: DocumentSnapshot) -> WorkTimePlan? {
        guard let data = doc.data(),
              let fid = data["franchiseId"] as? String,
              let mk = data["monthKey"] as? String,
              let url = data["fileURL"] as? String,
              let ct = data["contentType"] as? String,
              let fn = data["originalFileName"] as? String,
              let un = data["uploaderName"] as? String,
              let ts = (data["uploadedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        return WorkTimePlan(
            id: doc.documentID,
            franchiseId: fid,
            monthKey: mk,
            fileURL: url,
            contentType: ct,
            originalFileName: fn,
            uploaderName: un,
            uploadedAt: ts
        )
    }
}

// MARK: - Store

@MainActor
final class WorkTimePlanStore: ObservableObject {
    @Published private(set) var plan: WorkTimePlan?
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var lastError: String?

    func loadPlan(forMonth month: Date) {
        let fid = FirebaseService.shared.currentFranchiseId
        let mk = WorkTimePlan.monthKey(for: month)
        let docId = WorkTimePlan.documentId(franchiseId: fid, monthKey: mk)
        isLoading = true
        lastError = nil

        FirebaseService.shared.getCollectionReference("workTimePlans")
            .document(docId)
            .getDocument { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error {
                        if !FirebaseService.isPermissionError(error) {
                            self?.lastError = error.localizedDescription
                        }
                        self?.plan = nil
                        return
                    }
                    guard let snapshot, snapshot.exists else {
                        self?.plan = nil
                        return
                    }
                    self?.plan = WorkTimePlan.from(snapshot)
                }
            }
    }

    func uploadPlan(
        data: Data,
        contentType: String,
        fileName: String,
        month: Date,
        profile: UserProfile?
    ) async throws {
        guard Auth.auth().currentUser != nil else {
            throw WorkTimePlanError.notSignedIn
        }
        let fid = FirebaseService.shared.currentFranchiseId
        let mk = WorkTimePlan.monthKey(for: month)
        let docId = WorkTimePlan.documentId(franchiseId: fid, monthKey: mk)
        let ext = (fileName as NSString).pathExtension.lowercased()
        let storagePath = "franchises/\(fid)/workTimePlans/\(mk)/\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)"

        isUploading = true
        lastError = nil

        let downloadURL: String = try await withCheckedThrowingContinuation { continuation in
            FirebaseService.shared.uploadData(data, path: storagePath, contentType: contentType) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: WorkTimePlanError.uploadFailed)
                }
            }
        }

        let planData: [String: Any] = [
            "franchiseId": fid,
            "monthKey": mk,
            "fileURL": downloadURL,
            "contentType": contentType,
            "originalFileName": fileName,
            "uploaderName": profile?.displayName ?? "",
            "uploadedAt": Timestamp(date: Date())
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FirebaseService.shared.getCollectionReference("workTimePlans")
                .document(docId)
                .setData(planData, merge: false) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
        }

        isUploading = false
        // Refresh
        loadPlan(forMonth: month)
    }

    func deletePlan(forMonth month: Date) async throws {
        let fid = FirebaseService.shared.currentFranchiseId
        let mk = WorkTimePlan.monthKey(for: month)
        let docId = WorkTimePlan.documentId(franchiseId: fid, monthKey: mk)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FirebaseService.shared.getCollectionReference("workTimePlans")
                .document(docId)
                .delete { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
        }
        plan = nil
    }
}

enum WorkTimePlanError: LocalizedError {
    case notSignedIn
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You must be signed in.".localized
        case .uploadFailed: return "Upload failed.".localized
        }
    }
}
