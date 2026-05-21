import Foundation
import FirebaseAuth

extension AracViewModel {
    private static let amountLinkTolerance: Double = 0.02

    func enrichOfficeOperationMetadata(_ operation: inout OfficeOperation) {
        if operation.createdBy == nil {
            operation.createdBy = Auth.auth().currentUser?.uid
        }
        if operation.createdByName == nil {
            operation.createdByName = authManager?.userProfile?.nameOrUsernameForAudit
            if operation.createdByName == nil,
               let d = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !d.isEmpty, !d.contains("@") {
                operation.createdByName = d
            }
        }
        operation.franchiseId = firebaseService.currentFranchiseId.uppercased()
    }

    func findBestTrafficContractForPaymentLink(resCanonical: String, amount: Double, category: FleetPaymentCategory) -> TrafficAccidentContract? {
        let matches = trafficAccidentContracts.filter { c in
            guard TrafficAccidentContract.canonicalRES(from: c.resCode) == resCanonical else { return false }
            guard abs(c.amount - amount) < Self.amountLinkTolerance else { return false }
            if let method = c.paymentMethod {
                return method == category
            }
            return true
        }
        return matches.sorted { $0.contractIssueDate > $1.contractIssueDate }.first
    }

    func findBestOfficePaymentForTrafficLink(resCanonical: String, amount: Double, category: FleetPaymentCategory) -> OfficeOperation? {
        officeOperations.filter { op in
            op.type == .banking
                && TrafficAccidentContract.canonicalRES(from: op.referenceNumber ?? "") == resCanonical
                && abs(op.amount - amount) < Self.amountLinkTolerance
                && op.effectivePaymentCategory == category
        }.sorted { $0.date > $1.date }.first
    }

    /// After a Payments (`banking`) office operation is saved: link to matching traffic contract if both sides are unlinked.
    func runFleetPaymentTrafficLinkPassAfterOfficeSave(_ op: OfficeOperation) {
        guard op.type == .banking else { return }
        let res = TrafficAccidentContract.canonicalRES(from: op.referenceNumber ?? "")
        guard !res.isEmpty else { return }
        guard let traffic = findBestTrafficContractForPaymentLink(
            resCanonical: res,
            amount: op.amount,
            category: op.effectivePaymentCategory
        ) else { return }

        let tDoc = traffic.documentId ?? traffic.id.uuidString
        let oDoc = op.documentId ?? op.id.uuidString

        if op.linkedTrafficContractDocumentId != nil && op.linkedTrafficContractDocumentId != tDoc { return }
        if let existing = traffic.linkedPaymentOfficeOperationDocumentId, existing != oDoc { return }

        var opMut = op
        var tMut = traffic
        var changed = false
        if opMut.linkedTrafficContractDocumentId == nil {
            opMut.linkedTrafficContractDocumentId = tDoc
            changed = true
        }
        if tMut.linkedPaymentOfficeOperationDocumentId == nil {
            tMut.linkedPaymentOfficeOperationDocumentId = oDoc
            changed = true
        }
        guard changed else { return }

        firebaseService.updateOfficeOperation(opMut) { _ in }
        firebaseService.updateTrafficAccidentContract(tMut) { _ in }
    }

    /// After a traffic accident contract is saved/updated: mirror office payment if needed, then link to an existing Payments row when possible.
    func runFleetPaymentTrafficSideEffectsAfterContractSave(_ contract: TrafficAccidentContract) {
        if contract.paymentMethod == .officePayment && contract.linkedPaymentOfficeOperationDocumentId == nil {
            ensureMirroredOfficePaymentIfNeeded(for: contract)
            return
        }
        attemptBidirectionalLinkForTrafficContract(contract)
    }

    func attemptBidirectionalLinkForTrafficContract(_ contract: TrafficAccidentContract) {
        let res = TrafficAccidentContract.canonicalRES(from: contract.resCode)
        guard !res.isEmpty else { return }
        guard let op = findBestOfficePaymentForTrafficLink(
            resCanonical: res,
            amount: contract.amount,
            category: contract.effectivePaymentMethod
        ) else { return }

        let tDoc = contract.documentId ?? contract.id.uuidString
        let oDoc = op.documentId ?? op.id.uuidString

        if let existingT = op.linkedTrafficContractDocumentId, existingT != tDoc { return }
        if let existingO = contract.linkedPaymentOfficeOperationDocumentId, existingO != oDoc { return }

        var opMut = op
        var tMut = contract
        var changed = false
        if opMut.linkedTrafficContractDocumentId == nil {
            opMut.linkedTrafficContractDocumentId = tDoc
            changed = true
        }
        if tMut.linkedPaymentOfficeOperationDocumentId == nil {
            tMut.linkedPaymentOfficeOperationDocumentId = oDoc
            changed = true
        }
        guard changed else { return }

        firebaseService.updateOfficeOperation(opMut) { _ in }
        firebaseService.updateTrafficAccidentContract(tMut) { _ in }
    }

    /// Auto-create a Payments office row when a contract is recorded as office payment (CH flow).
    private func ensureMirroredOfficePaymentIfNeeded(for contract: TrafficAccidentContract) {
        guard contract.paymentMethod == .officePayment else { return }
        guard contract.linkedPaymentOfficeOperationDocumentId == nil else { return }
        guard contract.amount > 0.009 else { return }

        let tacKey = contract.documentId ?? contract.id.uuidString
        if officeOperations.contains(where: { $0.linkedTrafficContractDocumentId == tacKey }) { return }

        var op = OfficeOperation(
            type: .banking,
            date: contract.contractIssueDate,
            amount: contract.amount,
            photos: contract.photos,
            notes: "payment.mirror.from_traffic_contract".localized
        )
        op.paymentCategory = .officePayment
        let canon = TrafficAccidentContract.canonicalRES(from: contract.resCode)
        op.referenceNumber = canon.isEmpty ? nil : canon
        op.documentId = UUID().uuidString
        op.linkedTrafficContractDocumentId = tacKey
        enrichOfficeOperationMetadata(&op)

        firebaseService.saveOfficeOperation(op) { [weak self] (err: Error?) in
            guard let self, err == nil else { return }
            var c = contract
            c.linkedPaymentOfficeOperationDocumentId = op.documentId
            self.firebaseService.updateTrafficAccidentContract(c) { _ in
                self.attemptBidirectionalLinkForTrafficContract(c)
            }
        }
    }
}
