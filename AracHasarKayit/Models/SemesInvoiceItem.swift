import Foundation
import FirebaseFirestore

struct SemesInvoiceItem: Identifiable, Equatable {
    let id: String
    let invoiceId: String
    let fileName: String
    let fileType: String
    let storagePath: String
    let storageUrl: String
    let uploadedAt: Date?
    let uploadedBy: String
    let franchiseId: String
    let paymentStatus: String
    let requiredAmount: Double
    let paidAmount: Double

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        invoiceId = data["invoiceId"] as? String ?? document.documentID
        fileName = data["fileName"] as? String ?? invoiceId
        fileType = (data["fileType"] as? String ?? "pdf").lowercased()
        storagePath = data["storagePath"] as? String ?? ""
        storageUrl = data["storageUrl"] as? String ?? data["storageURL"] as? String ?? ""
        uploadedBy = data["uploadedBy"] as? String ?? ""
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        paymentStatus = data["paymentStatus"] as? String ?? "pending"
        if let n = data["requiredAmount"] as? Double {
            requiredAmount = n
        } else if let n = data["requiredAmount"] as? Int {
            requiredAmount = Double(n)
        } else {
            requiredAmount = 0
        }
        if let n = data["paidAmount"] as? Double {
            paidAmount = n
        } else if let n = data["paidAmount"] as? Int {
            paidAmount = Double(n)
        } else {
            paidAmount = 0
        }
        if let ts = data["uploadedAt"] as? Timestamp {
            uploadedAt = ts.dateValue()
        } else {
            uploadedAt = nil
        }
    }

    var displayTitle: String { fileName.isEmpty ? invoiceId : fileName }

    var searchBlob: String {
        [invoiceId, fileName, uploadedBy, paymentStatus, fileType]
            .joined(separator: " ")
            .lowercased()
    }
}
