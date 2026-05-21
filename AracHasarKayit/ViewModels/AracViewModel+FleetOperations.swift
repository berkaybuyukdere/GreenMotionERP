import Foundation
import FirebaseAuth

extension AracViewModel {
    func fleetOperationMonthRange(for month: Date) -> (start: Date, end: Date) {
        // Single source of truth for the month bounds used by hub cards and lists.
        FleetOperationsFilter.monthRange(for: month)
    }

    func fleetOperationLogItems(for month: Date) -> [FleetOperationLogItem] {
        // Shared filter ensures hub cards and hub lists report identical counts.
        var items: [FleetOperationLogItem] = []

        for c in FleetOperationsFilter.traffic.filteredTrafficContracts(trafficAccidentContracts, in: month) {
            items.append(.traffic(c))
        }

        for op in FleetOperationsFilter.all.filteredOfficeOperations(officeOperations, in: month) {
            switch op.effectivePaymentCategory {
            case .debtCollection, .officePayment:
                items.append(.inkasso(op))
            case .bankingTransaction:
                items.append(.banking(op))
            }
        }

        return items.sorted { $0.sortDate > $1.sortDate }
    }

    func fleetOperationCount(for month: Date) -> Int {
        fleetOperationLogItems(for: month).count
    }

    /// Creates the target record for the selected Operations route (traffic contract or banking office op).
    func submitFleetOperation(
        route: FleetOperationRoute,
        amount: Double,
        resCanonical: String,
        photos: [String],
        notes: String,
        processedDate: Date,
        contractIssueDate: Date? = nil,
        paidAmount: Double? = nil,
        expectedAmount: Double? = nil
    ) {
        let franchiseId = firebaseService.currentFranchiseId
        let uid = Auth.auth().currentUser?.uid
        let recorder = authManager?.userProfile?.nameOrUsernameForAudit
            ?? Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch route {
        case .trafficAccident:
            guard !photos.isEmpty else {
                ToastManager.shared.show("Add at least one contract photo.".localized, type: .warning)
                return
            }
            let issue = contractIssueDate ?? processedDate
            let idem = TrafficAccidentContract.primaryIdempotencyKey(franchiseId: franchiseId, canonicalRES: resCanonical)
            var contract = TrafficAccidentContract(
                photos: photos,
                amount: amount,
                resCode: resCanonical,
                paidAmount: paidAmount,
                createdAt: Date(),
                contractIssueDate: issue,
                processedDate: processedDate,
                franchiseId: franchiseId,
                createdBy: uid,
                createdByName: recorder?.isEmpty == false ? recorder : nil,
                paymentMethod: nil,
                supplementOfDocumentId: nil,
                idempotencyKey: idem
            )
            contract.documentId = TrafficAccidentContract.stableDocumentId(forIdempotencyKey: idem)
            trafficAccidentContractEkle(contract)

        case .inkasso, .bankingTransaction:
            guard let category = route.officePaymentCategory else { return }
            var op = OfficeOperation(
                type: .banking,
                date: processedDate,
                amount: amount,
                photos: photos,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            op.paymentCategory = category
            op.referenceNumber = resCanonical.isEmpty ? nil : resCanonical
            op.expectedAmount = expectedAmount
            op.fleetPaymentRecordStatus = .pending
            enrichOfficeOperationMetadata(&op)
            officeOperationEkle(op)
        }
    }
}
