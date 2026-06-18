import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum CHStripeFinancialServiceError: LocalizedError {
    case notAuthenticated
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in.".localized
        case .operationFailed(let msg): return msg
        }
    }
}

enum CHStripeFinancialService {
    private static let functions = Functions.functions(region: "europe-west6")

    static func publicConfigDocument(franchiseId: String) -> DocumentReference {
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Firestore.firestore()
            .collection("franchises").document(fid)
            .collection("stripeConfig").document("public")
    }

    static func mailOrdersCollection(franchiseId: String) -> CollectionReference {
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Firestore.firestore()
            .collection("franchises").document(fid)
            .collection("stripeMailOrders")
    }

    static func disputesCollection(franchiseId: String) -> CollectionReference {
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Firestore.firestore()
            .collection("franchises").document(fid)
            .collection("stripeDisputes")
    }

    static func loadPublicConfig(franchiseId: String) async throws {
        let snap = try await publicConfigDocument(franchiseId: franchiseId).getDocument()
        guard let data = snap.data(),
              let pk = data["publishableKey"] as? String,
              !pk.isEmpty else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Stripe config not found for franchise.".localized
            )
        }
        let mode = data["mode"] as? String ?? "live"
        StripeCHConfig.applyPublicConfig(publishableKey: pk, mode: mode)
        StripeCHCardScanService.configureIfNeeded()
    }

    static func subscribeMailOrders(
        franchiseId: String,
        limit: Int = 100,
        onChange: @escaping ([CHStripeMailOrderRecord]) -> Void
    ) -> ListenerRegistration {
        mailOrdersCollection(franchiseId: franchiseId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snap, _ in
                let records = (snap?.documents ?? []).compactMap { CHStripeMailOrderRecord(document: $0) }
                onChange(records)
            }
    }

    static func subscribeDisputes(
        franchiseId: String,
        limit: Int = 100,
        onChange: @escaping ([CHStripeDisputeRecord]) -> Void
    ) -> ListenerRegistration {
        disputesCollection(franchiseId: franchiseId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snap, _ in
                let records = (snap?.documents ?? []).compactMap { CHStripeDisputeRecord(document: $0) }
                onChange(records)
            }
    }

    struct MailOrderRequest {
        var amountChf: Double
        var category: CHStripeMailOrderCategory
        var resNo: String
        var customerEmail: String
        var customerName: String
        var note: String
        var sendEmail: Bool
    }

    struct MailOrderResponse {
        let paymentUrl: String
        let mailOrderId: String
        let emailSent: Bool
    }

    static func createMailOrder(
        franchiseId: String,
        request: MailOrderRequest
    ) async throws -> MailOrderResponse {
        guard Auth.auth().currentUser != nil else {
            throw CHStripeFinancialServiceError.notAuthenticated
        }
        let payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "amountChf": request.amountChf,
            "category": request.category.rawValue,
            "resNo": request.resNo,
            "customerEmail": request.customerEmail,
            "customerName": request.customerName,
            "note": request.note,
            "sendEmail": request.sendEmail,
        ]
        let result = try await functions.httpsCallable("createCHMailOrderPaymentLink").call(payload)
        guard let data = result.data as? [String: Any],
              let url = data["paymentUrl"] as? String,
              let mailOrderId = data["mailOrderId"] as? String else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Invalid payment response from server.".localized
            )
        }
        return MailOrderResponse(
            paymentUrl: url,
            mailOrderId: mailOrderId,
            emailSent: data["emailSent"] as? Bool ?? false
        )
    }

    static func syncDisputes(franchiseId: String) async throws -> Int {
        guard Auth.auth().currentUser != nil else {
            throw CHStripeFinancialServiceError.notAuthenticated
        }
        let result = try await functions.httpsCallable("syncCHStripeDisputes").call([
            "franchiseId": franchiseId.uppercased(),
        ])
        guard let data = result.data as? [String: Any],
              let count = data["synced"] as? Int else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Invalid sync response.".localized
            )
        }
        return count
    }

    struct DailyClosingResponse {
        let dayKey: String
        let transactions: [CHStripePaymentTransaction]
        let summary: CHStripeDailyClosingSummary
        let syncedAt: Date?
    }

    static func fetchDailyClosing(
        franchiseId: String,
        dayKey: String? = nil
    ) async throws -> DailyClosingResponse {
        guard Auth.auth().currentUser != nil else {
            throw CHStripeFinancialServiceError.notAuthenticated
        }
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
        ]
        if let dayKey, !dayKey.isEmpty {
            payload["dayKey"] = dayKey
        }
        let result = try await functions.httpsCallable("listCHStripeDailyClosing").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Invalid daily closing response.".localized
            )
        }
        let key = data["dayKey"] as? String ?? ""
        let txRaw = data["transactions"] as? [[String: Any]] ?? []
        let transactions = txRaw.compactMap { CHStripePaymentTransaction(dictionary: $0) }
        let summary = CHStripeDailyClosingSummary.from(dictionary: data["summary"] as? [String: Any])
        let syncedAt: Date?
        if let iso = data["syncedAt"] as? String {
            syncedAt = ISO8601DateFormatter().date(from: iso)
        } else {
            syncedAt = nil
        }
        return DailyClosingResponse(
            dayKey: key,
            transactions: transactions,
            summary: summary,
            syncedAt: syncedAt
        )
    }

    static func fetchDailyReports(
        franchiseId: String,
        period: CHStripeDailyReportPeriod
    ) async throws -> CHStripeDailyReportSnapshot {
        guard Auth.auth().currentUser != nil else {
            throw CHStripeFinancialServiceError.notAuthenticated
        }
        let result = try await functions.httpsCallable("getCHStripeDailyReports").call([
            "franchiseId": franchiseId.uppercased(),
            "period": period.rawValue,
        ])
        guard let data = result.data as? [String: Any],
              let snapshot = CHStripeDailyReportSnapshot.from(dictionary: data) else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Invalid daily reports response.".localized
            )
        }
        return snapshot
    }

    struct DepositIncreaseResponse {
        let paymentIntentId: String
        let capturedAmount: Double
        let currency: String
        let status: String
        let method: String
    }

    static func increaseDepositHold(
        franchiseId: String,
        paymentIntentId: String,
        amountChf: Double
    ) async throws -> DepositIncreaseResponse {
        guard Auth.auth().currentUser != nil else {
            throw CHStripeFinancialServiceError.notAuthenticated
        }
        let result = try await functions.httpsCallable("increaseCHStripeDepositHold").call([
            "franchiseId": franchiseId.uppercased(),
            "paymentIntentId": paymentIntentId,
            "amountChf": amountChf,
        ])
        guard let data = result.data as? [String: Any],
              let piId = data["paymentIntentId"] as? String else {
            throw CHStripeFinancialServiceError.operationFailed(
                "Invalid deposit capture response.".localized
            )
        }
        let minor = data["capturedAmount"] as? Int
            ?? Int(data["capturedAmount"] as? Double ?? 0)
        return DepositIncreaseResponse(
            paymentIntentId: piId,
            capturedAmount: Double(minor) / 100.0,
            currency: (data["currency"] as? String ?? StripeCHConfig.currency).uppercased(),
            status: data["status"] as? String ?? "",
            method: data["method"] as? String ?? "capture"
        )
    }
}
