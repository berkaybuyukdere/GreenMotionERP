import Foundation

enum JarvisPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .daily: return "ch_panel.period_daily"
        case .weekly: return "ch_panel.period_weekly"
        case .monthly: return "ch_panel.period_monthly"
        }
    }

    func dateRange(endingAt now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = now
        let start: Date
        switch self {
        case .daily:
            start = calendar.startOfDay(for: now)
        case .weekly:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        case .monthly:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        }
        return (start, end)
    }
}

enum JarvisDomain: String, CaseIterable, Identifiable {
    case overview
    case damages
    case checkouts
    case returns
    case officeOperations
    case banking
    case additionalSales
    case posClosing
    case fuel
    case washing
    case trafficContracts
    case systemHealth

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "jarvis.domain.overview"
        case .damages: return "jarvis.domain.damages"
        case .checkouts: return "jarvis.domain.checkouts"
        case .returns: return "jarvis.domain.returns"
        case .officeOperations: return "jarvis.domain.office_ops"
        case .banking: return "jarvis.domain.banking"
        case .additionalSales: return "jarvis.domain.additional_sales"
        case .posClosing: return "jarvis.domain.pos"
        case .fuel: return "jarvis.domain.fuel"
        case .washing: return "jarvis.domain.washing"
        case .trafficContracts: return "jarvis.domain.traffic"
        case .systemHealth: return "jarvis.domain.health"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .damages: return "car.side.front.open.fill"
        case .checkouts: return "arrow.right.circle"
        case .returns: return "arrow.left.circle"
        case .officeOperations: return "building.2"
        case .banking: return "building.columns"
        case .additionalSales: return "cart"
        case .posClosing: return "centsign.circle"
        case .fuel: return "fuelpump"
        case .washing: return "drop"
        case .trafficContracts: return "doc.text"
        case .systemHealth: return "heart.text.square"
        }
    }
}

struct JarvisQuickAction: Identifiable {
    let id: String
    let period: JarvisPeriod
    let domain: JarvisDomain
    let promptKey: String

    static func gridActions() -> [JarvisQuickAction] {
        var actions: [JarvisQuickAction] = []
        for period in JarvisPeriod.allCases {
            actions.append(JarvisQuickAction(
                id: "exec_\(period.rawValue)",
                period: period,
                domain: .overview,
                promptKey: "jarvis.prompt.executive"
            ))
        }
        let domains: [JarvisDomain] = [
            .damages, .checkouts, .returns, .officeOperations,
            .banking, .additionalSales, .posClosing, .fuel, .washing, .trafficContracts
        ]
        for d in domains {
            actions.append(JarvisQuickAction(
                id: "domain_\(d.rawValue)",
                period: .monthly,
                domain: d,
                promptKey: "jarvis.prompt.domain"
            ))
        }
        actions.append(JarvisQuickAction(
            id: "health_scan",
            period: .monthly,
            domain: .systemHealth,
            promptKey: "jarvis.prompt.health"
        ))
        return actions
    }
}

struct JarvisAnalysisRequest {
    let period: JarvisPeriod
    let domain: JarvisDomain
    let languageCode: String
    let customQuestion: String?

    var userLabel: String {
        if let customQuestion, !customQuestion.isEmpty { return customQuestion }
        return "\(period.rawValue) · \(domain.rawValue)"
    }
}

enum JarvisExportIntent {
    case none
    case pdf
    case excel
}

enum JarvisIntentDetector {
    /// Export only when user explicitly asks (avoids accidental PDF from casual chat).
    static func exportIntent(_ message: String) -> JarvisExportIntent {
        let m = message.lowercased()
        let explicit = ["export", "paylaş", "paylas", "indir", "download", "dışa aktar", "disa aktar", "oluştur", "olustur", "hazırla", "hazirla"]
        let hasExplicit = explicit.contains { m.contains($0) }
        let wantsPDF = m.contains("pdf") && (hasExplicit || m.contains("rapor"))
        let wantsExcel = (m.contains("excel") || m.contains("xlsx") || m.contains("csv")) && hasExplicit
        if wantsPDF { return .pdf }
        if wantsExcel { return .excel }
        return .none
    }
}
