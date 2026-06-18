import Foundation
import FirebaseFirestore

enum CHStripeMailOrderCategory: String, CaseIterable, Identifiable {
    case trafficFine = "traffic_fine"
    case damage = "damage"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .trafficFine: return "ch_stripe.mailorder_category_traffic_fine".localized
        case .damage: return "ch_stripe.mailorder_category_damage".localized
        }
    }

    var icon: String {
        switch self {
        case .trafficFine: return "exclamationmark.triangle.fill"
        case .damage: return "car.side.rear.and.collision.and.car.side.front"
        }
    }
}

enum CHStripeMailOrderStatus: String {
    case pending
    case paid
    case expired
    case cancelled

    var localizedTitle: String {
        switch self {
        case .pending: return "ch_stripe.mailorder_status_pending".localized
        case .paid: return "ch_stripe.mailorder_status_paid".localized
        case .expired: return "ch_stripe.mailorder_status_expired".localized
        case .cancelled: return "ch_stripe.mailorder_status_cancelled".localized
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .paid: return "checkmark.circle.fill"
        case .expired: return "hourglass.bottomhalf.filled"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

struct CHStripeMailOrderRecord: Identifiable, Equatable {
    let id: String
    let franchiseId: String
    let amount: Double
    let currency: String
    let status: CHStripeMailOrderStatus
    let paymentUrl: String
    let customerEmail: String
    let customerName: String
    let category: CHStripeMailOrderCategory?
    let resNo: String
    let customerReference: String
    let plate: String
    let note: String
    let description: String
    let emailSent: Bool
    let createdAt: Date?

    var displayCategory: CHStripeMailOrderCategory? { category }

    init?(document: QueryDocumentSnapshot) {
        let d = document.data()
        id = document.documentID
        franchiseId = d["franchiseId"] as? String ?? StripeCHConfig.franchiseId
        let minor = d["amount"] as? Int ?? Int((d["amount"] as? Double ?? 0) * 100)
        amount = Double(minor) / 100.0
        currency = (d["currency"] as? String ?? StripeCHConfig.currency).uppercased()
        let statusRaw = d["status"] as? String ?? "pending"
        status = CHStripeMailOrderStatus(rawValue: statusRaw) ?? .pending
        paymentUrl = d["paymentUrl"] as? String ?? ""
        customerEmail = d["customerEmail"] as? String ?? ""
        customerName = d["customerName"] as? String ?? ""
        if let catRaw = d["category"] as? String,
           let cat = CHStripeMailOrderCategory(rawValue: catRaw) {
            category = cat
        } else {
            category = nil
        }
        let storedRes = d["resNo"] as? String ?? ""
        resNo = storedRes.isEmpty ? (d["customerReference"] as? String ?? "") : storedRes
        customerReference = d["customerReference"] as? String ?? resNo
        plate = d["plate"] as? String ?? ""
        note = d["note"] as? String ?? d["description"] as? String ?? ""
        description = note
        emailSent = d["emailSent"] as? Bool ?? false
        if let ts = d["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = nil
        }
    }
}

enum CHStripeDisputeStatus: String {
    case warningNeedsResponse = "warning_needs_response"
    case warningUnderReview = "warning_under_review"
    case warningClosed = "warning_closed"
    case needsResponse = "needs_response"
    case underReview = "under_review"
    case chargeRefunded = "charge_refunded"
    case won
    case lost

    var localizedTitle: String {
        switch self {
        case .needsResponse, .warningNeedsResponse:
            return "ch_stripe.dispute_needs_response".localized
        case .underReview, .warningUnderReview:
            return "ch_stripe.dispute_under_review".localized
        case .won: return "ch_stripe.dispute_won".localized
        case .lost: return "ch_stripe.dispute_lost".localized
        case .chargeRefunded: return "ch_stripe.dispute_refunded".localized
        case .warningClosed: return "ch_stripe.dispute_closed".localized
        }
    }

    var isOpen: Bool {
        switch self {
        case .needsResponse, .warningNeedsResponse, .underReview, .warningUnderReview:
            return true
        default:
            return false
        }
    }

    var icon: String {
        isOpen ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
    }
}

struct CHStripeDisputeRecord: Identifiable, Equatable {
    let id: String
    let franchiseId: String
    let stripeDisputeId: String
    let stripeChargeId: String?
    let amount: Double
    let currency: String
    let status: CHStripeDisputeStatus
    let reason: String
    let cardBrand: String?
    let cardLast4: String?
    let customerReference: String
    let plate: String
    let evidenceDueBy: Date?
    let createdAt: Date?

    init?(document: QueryDocumentSnapshot) {
        let d = document.data()
        id = document.documentID
        franchiseId = d["franchiseId"] as? String ?? StripeCHConfig.franchiseId
        stripeDisputeId = d["stripeDisputeId"] as? String ?? id
        stripeChargeId = d["stripeChargeId"] as? String
        let minor = d["amount"] as? Int ?? Int((d["amount"] as? Double ?? 0) * 100)
        amount = Double(minor) / 100.0
        currency = (d["currency"] as? String ?? StripeCHConfig.currency).uppercased()
        let statusRaw = (d["status"] as? String ?? "needs_response")
            .replacingOccurrences(of: "-", with: "_")
        status = CHStripeDisputeStatus(rawValue: statusRaw) ?? .needsResponse
        reason = d["reason"] as? String ?? ""
        cardBrand = d["cardBrand"] as? String
        cardLast4 = d["cardLast4"] as? String
        customerReference = d["customerReference"] as? String ?? ""
        plate = d["plate"] as? String ?? ""
        if let ts = d["evidenceDueBy"] as? Timestamp {
            evidenceDueBy = ts.dateValue()
        } else {
            evidenceDueBy = nil
        }
        if let ts = d["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = nil
        }
    }
}

struct CHStripeFinancialTotals: Equatable {
    var mailOrderPaid: Double = 0
    var mailOrderPending: Double = 0
    var disputeOpenAmount: Double = 0
    var disputeLostAmount: Double = 0

    static func from(
        mailOrders: [CHStripeMailOrderRecord],
        disputes: [CHStripeDisputeRecord]
    ) -> CHStripeFinancialTotals {
        var t = CHStripeFinancialTotals()
        for o in mailOrders {
            switch o.status {
            case .paid: t.mailOrderPaid += o.amount
            case .pending: t.mailOrderPending += o.amount
            default: break
            }
        }
        for d in disputes {
            if d.status.isOpen {
                t.disputeOpenAmount += d.amount
            } else if d.status == .lost {
                t.disputeLostAmount += d.amount
            }
        }
        return t
    }
}

enum CHStripePaymentBucket: String, CaseIterable {
    case successful
    case hold
    case pending
    case cancelled

    var localizedTitle: String {
        switch self {
        case .successful: return "ch_stripe.daily_successful".localized
        case .hold: return "ch_stripe.daily_hold".localized
        case .pending: return "ch_stripe.daily_pending".localized
        case .cancelled: return "ch_stripe.daily_cancelled".localized
        }
    }

    var icon: String {
        switch self {
        case .successful: return "checkmark.circle.fill"
        case .hold: return "lock.fill"
        case .pending: return "clock.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

struct CHStripePaymentTransaction: Identifiable, Equatable {
    let id: String
    let bucket: CHStripePaymentBucket
    let status: String
    let statusLabel: String
    let amount: Double
    let amountReceived: Double
    let holdAmount: Double
    let currency: String
    let channel: String
    let paymentMethod: String
    let cardBrand: String?
    let cardLast4: String?
    let description: String
    let plate: String
    let reference: String
    let resNo: String
    let customerName: String
    let customerEmail: String
    let note: String
    let category: CHStripeMailOrderCategory?
    let paymentIntentId: String?
    let createdAt: Date?

    var canIncreaseDeposit: Bool {
        bucket == .hold && paymentIntentId != nil && !(paymentIntentId ?? "").isEmpty
    }

    init?(dictionary: [String: Any]) {
        guard let rawId = dictionary["id"] as? String else { return nil }
        id = rawId
        paymentIntentId = dictionary["paymentIntentId"] as? String
            ?? (dictionary["id"] as? String).flatMap { $0.hasPrefix("pi_") ? $0 : nil }
        let bucketRaw = dictionary["bucket"] as? String ?? "pending"
        bucket = CHStripePaymentBucket(rawValue: bucketRaw) ?? .pending
        status = dictionary["status"] as? String ?? bucketRaw
        statusLabel = dictionary["statusLabel"] as? String ?? bucket.localizedTitle
        let minor = dictionary["amount"] as? Int ?? Int(dictionary["amount"] as? Double ?? 0)
        amount = Double(minor) / 100.0
        let recvMinor = dictionary["amountReceived"] as? Int
            ?? Int(dictionary["amountReceived"] as? Double ?? 0)
        amountReceived = Double(recvMinor) / 100.0
        let holdMinor = dictionary["holdAmount"] as? Int
            ?? Int(dictionary["holdAmount"] as? Double ?? 0)
        holdAmount = Double(holdMinor) / 100.0
        currency = (dictionary["currency"] as? String ?? StripeCHConfig.currency).uppercased()
        channel = dictionary["channel"] as? String ?? "online"
        paymentMethod = dictionary["paymentMethod"] as? String ?? "card"
        cardBrand = dictionary["cardBrand"] as? String
        cardLast4 = dictionary["cardLast4"] as? String
        description = dictionary["description"] as? String ?? ""
        plate = dictionary["plate"] as? String ?? ""
        reference = dictionary["reference"] as? String ?? ""
        resNo = dictionary["resNo"] as? String ?? reference
        customerName = dictionary["customerName"] as? String ?? ""
        customerEmail = dictionary["customerEmail"] as? String ?? ""
        note = dictionary["note"] as? String ?? ""
        if let catRaw = dictionary["category"] as? String {
            category = CHStripeMailOrderCategory(rawValue: catRaw)
        } else {
            category = nil
        }
        if let iso = dictionary["createdAt"] as? String,
           let date = ISO8601DateFormatter().date(from: iso) {
            createdAt = date
        } else if let unix = dictionary["created"] as? Int {
            createdAt = Date(timeIntervalSince1970: TimeInterval(unix))
        } else {
            createdAt = nil
        }
    }

    var displayAmount: Double {
        switch bucket {
        case .successful: return amountReceived
        case .hold: return holdAmount > 0 ? holdAmount : amount
        default: return amount
        }
    }

    var channelTitle: String {
        switch channel {
        case "terminal": return "Terminal / POS"
        case "mail_order": return "Mail order"
        default: return "Online"
        }
    }
}

struct CHStripeDailyClosingSummary: Equatable {
    var successfulCount: Int = 0
    var successfulAmount: Double = 0
    var holdCount: Int = 0
    var holdAmount: Double = 0
    var pendingCount: Int = 0
    var pendingAmount: Double = 0
    var cancelledCount: Int = 0
    var cancelledAmount: Double = 0

    static func from(dictionary: [String: Any]?, currency _: String = "CHF") -> CHStripeDailyClosingSummary {
        var s = CHStripeDailyClosingSummary()
        guard let summary = dictionary else { return s }
        func read(_ key: String) -> (Int, Double) {
            guard let block = summary[key] as? [String: Any] else { return (0, 0) }
            let count = block["count"] as? Int ?? 0
            let minor = block["amount"] as? Int ?? Int(block["amount"] as? Double ?? 0)
            return (count, Double(minor) / 100.0)
        }
        (s.successfulCount, s.successfulAmount) = read("successful")
        (s.holdCount, s.holdAmount) = read("hold")
        (s.pendingCount, s.pendingAmount) = read("pending")
        (s.cancelledCount, s.cancelledAmount) = read("cancelled")
        return s
    }
}

// MARK: - Daily reports

enum CHStripeDailyReportPeriod: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case oneEightyDays = "180d"
    case oneYear = "1y"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .oneDay: return "ch_stripe.reports_period_1d".localized
        case .sevenDays: return "ch_stripe.reports_period_7d".localized
        case .thirtyDays: return "ch_stripe.reports_period_30d".localized
        case .oneEightyDays: return "ch_stripe.reports_period_180d".localized
        case .oneYear: return "ch_stripe.reports_period_1y".localized
        }
    }
}

struct CHStripeReportMetric: Equatable {
    var count: Int = 0
    var volume: Double = 0

    static func from(dictionary: [String: Any]?) -> CHStripeReportMetric {
        guard let d = dictionary else { return CHStripeReportMetric() }
        let count = d["count"] as? Int ?? 0
        let minor = d["volume"] as? Int ?? Int(d["volume"] as? Double ?? 0)
        return CHStripeReportMetric(count: count, volume: Double(minor) / 100.0)
    }
}

struct CHStripeMailOrderCategoryMetrics: Equatable {
    var trafficFine: CHStripeReportMetric = .init()
    var damage: CHStripeReportMetric = .init()
    var other: CHStripeReportMetric = .init()

    static func from(dictionary: [String: Any]?) -> CHStripeMailOrderCategoryMetrics {
        guard let d = dictionary else { return CHStripeMailOrderCategoryMetrics() }
        return CHStripeMailOrderCategoryMetrics(
            trafficFine: .from(dictionary: d["traffic_fine"] as? [String: Any]),
            damage: .from(dictionary: d["damage"] as? [String: Any]),
            other: .from(dictionary: d["other"] as? [String: Any])
        )
    }

    func metric(for category: CHStripeMailOrderCategory) -> CHStripeReportMetric {
        switch category {
        case .trafficFine: return trafficFine
        case .damage: return damage
        }
    }
}

struct CHStripeMailOrderReportMetric: Equatable {
    var count: Int = 0
    var volume: Double = 0
    var byCategory: CHStripeMailOrderCategoryMetrics = .init()

    static func from(dictionary: [String: Any]?) -> CHStripeMailOrderReportMetric {
        guard let d = dictionary else { return CHStripeMailOrderReportMetric() }
        let base = CHStripeReportMetric.from(dictionary: d)
        return CHStripeMailOrderReportMetric(
            count: base.count,
            volume: base.volume,
            byCategory: .from(dictionary: d["byCategory"] as? [String: Any])
        )
    }
}

struct CHStripeDailyReportDayPoint: Identifiable, Equatable {
    let dayKey: String
    let payments: CHStripeReportMetric
    let chargebacks: CHStripeReportMetric
    let mailOrder: CHStripeMailOrderReportMetric

    var id: String { dayKey }

    var chartDate: Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.timeZone = TimeZone(identifier: "Europe/Zurich")
        return Calendar.current.date(from: comps) ?? Date()
    }

    var shortLabel: String {
        chartDate.formatted(.dateTime.day().month(.narrow))
    }

    static func from(dictionary: [String: Any]) -> CHStripeDailyReportDayPoint? {
        guard let dayKey = dictionary["dayKey"] as? String else { return nil }
        return CHStripeDailyReportDayPoint(
            dayKey: dayKey,
            payments: .from(dictionary: dictionary["payments"] as? [String: Any]),
            chargebacks: .from(dictionary: dictionary["chargebacks"] as? [String: Any]),
            mailOrder: .from(dictionary: dictionary["mailOrder"] as? [String: Any])
        )
    }
}

struct CHStripeDailyReportSnapshot: Equatable {
    let period: CHStripeDailyReportPeriod
    let startDayKey: String
    let endDayKey: String
    let timeZone: String
    let payments: CHStripeReportMetric
    let chargebacks: CHStripeReportMetric
    let mailOrder: CHStripeMailOrderReportMetric
    let dailySeries: [CHStripeDailyReportDayPoint]
    let syncedAt: Date?

    static func from(dictionary: [String: Any]) -> CHStripeDailyReportSnapshot? {
        let periodRaw = dictionary["period"] as? String ?? "7d"
        let period = CHStripeDailyReportPeriod(rawValue: periodRaw) ?? .sevenDays
        let kpis = dictionary["kpis"] as? [String: Any] ?? [:]
        let seriesRaw = dictionary["dailySeries"] as? [[String: Any]] ?? []
        let series = seriesRaw.compactMap { CHStripeDailyReportDayPoint.from(dictionary: $0) }
        let syncedAt: Date?
        if let iso = dictionary["syncedAt"] as? String {
            syncedAt = ISO8601DateFormatter().date(from: iso)
        } else {
            syncedAt = nil
        }
        return CHStripeDailyReportSnapshot(
            period: period,
            startDayKey: dictionary["startDayKey"] as? String ?? "",
            endDayKey: dictionary["endDayKey"] as? String ?? "",
            timeZone: dictionary["timeZone"] as? String ?? "Europe/Zurich",
            payments: .from(dictionary: kpis["payments"] as? [String: Any]),
            chargebacks: .from(dictionary: kpis["chargebacks"] as? [String: Any]),
            mailOrder: .from(dictionary: kpis["mailOrder"] as? [String: Any]),
            dailySeries: series,
            syncedAt: syncedAt
        )
    }
}
