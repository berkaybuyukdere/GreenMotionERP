import Foundation
import FirebaseAuth

extension AracViewModel {
    func policeReportEkle(_ report: PoliceReport) {
        var r = report
        if r.createdBy == nil { r.createdBy = Auth.auth().currentUser?.uid }
        if r.createdByName == nil {
            r.createdByName = authManager?.userProfile?.nameOrUsernameForAudit
        }
        r.franchiseId = firebaseService.currentFranchiseId.uppercased()
        if r.documentId == nil { r.documentId = r.id.uuidString }

        firebaseService.savePoliceReport(r) { error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Police Report Save")
                } else {
                    ToastManager.shared.show("Police report saved".localized, type: .success)
                }
            }
        }
    }

    func policeReportGuncelle(_ report: PoliceReport) {
        firebaseService.updatePoliceReport(report) { error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Police Report Update")
                }
            }
        }
    }

    func policeReportSil(_ report: PoliceReport) {
        firebaseService.deletePoliceReport(report) { error in
            DispatchQueue.main.async {
                if let error = error {
                    ErrorManager.shared.showError(error, context: "Police Report Delete")
                }
            }
        }
    }

    func togglePoliceReportProcessed(_ report: PoliceReport) {
        var updated = report
        updated.isProcessed.toggle()
        policeReportGuncelle(updated)
        HapticManager.shared.selection()
    }
}
