import Foundation
import FirebaseFirestore

/// Web Front Desk → iOS checkout/return prefill (Turkey franchise trial).
struct TRFrontDeskHandoverPrefill: Equatable {
    let frontDeskDocumentId: String
    let customerFirstName: String
    let customerLastName: String
    let customerEmail: String
    /// Digits only — matches `ExitIslemView` NAV field (no prefix).
    let navDigits: String
    let plannedCheckout: Date?
    let plannedCheckin: Date?
    /// Web `frontDeskCustomers` — pick-up / drop-off location labels (optional).
    let pickupBranchName: String?
    let dropoffBranchName: String?
    let km: Int?
    /// Present when `iosPrefillStatus == return_ready` (links to open checkout).
    let linkedExitId: String?

    /// Firestore query avoids `order(by:)` so we sort client-side (newest `submittedAt` first).
    private static func sortedBySubmittedAt(_ documents: [QueryDocumentSnapshot]) -> [QueryDocumentSnapshot] {
        documents.sorted { a, b in
            let ta = (a.data()["submittedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            let tb = (b.data()["submittedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return ta > tb
        }
    }

    static func pickCheckout(from documents: [QueryDocumentSnapshot]) -> TRFrontDeskHandoverPrefill? {
        for doc in sortedBySubmittedAt(documents) {
            let status = doc.data()["iosPrefillStatus"] as? String
            if status == "checkout_ready" {
                return parse(doc)
            }
        }
        return nil
    }

    static func pickReturn(from documents: [QueryDocumentSnapshot], linkedExitId: UUID) -> TRFrontDeskHandoverPrefill? {
        let target = linkedExitId.uuidString
        for doc in sortedBySubmittedAt(documents) {
            let data = doc.data()
            guard data["iosPrefillStatus"] as? String == "return_ready" else { continue }
            let linkedIadeId = (data["linkedIadeId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !linkedIadeId.isEmpty { continue }
            if (data["linkedExitId"] as? String) == target {
                return parse(doc)
            }
        }
        return nil
    }

    private static func parse(_ doc: QueryDocumentSnapshot) -> TRFrontDeskHandoverPrefill? {
        let data = doc.data()
        let first = (data["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let middle = (data["middleName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let family = (data["familyName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = [middle, family].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (data["email"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawNav = String(data["handoverNavKodu"] as? String ?? "")
        let navDigits = rawNav.filter { $0.isNumber }
        let pc = (data["plannedCheckoutAt"] as? Timestamp)?.dateValue()
        let pi = (data["plannedCheckinAt"] as? Timestamp)?.dateValue()
        let pickupBranchName = (data["pickupBranchName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let dropoffBranchName = (data["dropoffBranchName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let kmVal: Int? = {
            if let k = data["handoverKm"] as? Int { return k }
            if let k = data["handoverKm"] as? Int64 { return Int(k) }
            return nil
        }()
        let linked = data["linkedExitId"] as? String
        return TRFrontDeskHandoverPrefill(
            frontDeskDocumentId: doc.documentID,
            customerFirstName: first,
            customerLastName: last.isEmpty ? family : last,
            customerEmail: email,
            navDigits: navDigits,
            plannedCheckout: pc,
            plannedCheckin: pi,
            pickupBranchName: pickupBranchName,
            dropoffBranchName: dropoffBranchName,
            km: kmVal,
            linkedExitId: linked
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
