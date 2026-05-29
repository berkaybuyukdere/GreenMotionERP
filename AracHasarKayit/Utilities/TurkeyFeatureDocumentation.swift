import Foundation

/// Turkey-only in-app feature guides (Operations, Checkout, Return, Damage).
enum TurkeyDocumentationTopic: String, CaseIterable, Identifiable {
    case operationsHub = "operations_hub"
    case checkout
    case returnProcess = "return"
    case damage

    var id: String { rawValue }

    var titleKey: String { "tr_docs.topic.\(rawValue).title" }
    var subtitleKey: String { "tr_docs.topic.\(rawValue).subtitle" }
    var iconSystemName: String {
        switch self {
        case .operationsHub: return "calendar.badge.clock"
        case .checkout: return "arrow.right.circle.fill"
        case .returnProcess: return "arrow.uturn.backward.circle.fill"
        case .damage: return "exclamationmark.triangle.fill"
        }
    }

    struct Section: Identifiable {
        let id: String
        let titleKey: String
        let bodyKey: String
        let bulletKeys: [String]
    }

    var sections: [Section] {
        switch self {
        case .operationsHub:
            return [
                Section(
                    id: "overview",
                    titleKey: "tr_docs.topic.operations_hub.section.overview.title",
                    bodyKey: "tr_docs.topic.operations_hub.section.overview.body",
                    bulletKeys: [
                        "tr_docs.topic.operations_hub.section.overview.bullet.1",
                        "tr_docs.topic.operations_hub.section.overview.bullet.2",
                    ]
                ),
                Section(
                    id: "checkouts",
                    titleKey: "tr_docs.topic.operations_hub.section.checkouts.title",
                    bodyKey: "tr_docs.topic.operations_hub.section.checkouts.body",
                    bulletKeys: [
                        "tr_docs.topic.operations_hub.section.checkouts.bullet.1",
                        "tr_docs.topic.operations_hub.section.checkouts.bullet.2",
                        "tr_docs.topic.operations_hub.section.checkouts.bullet.3",
                    ]
                ),
                Section(
                    id: "returns",
                    titleKey: "tr_docs.topic.operations_hub.section.returns.title",
                    bodyKey: "tr_docs.topic.operations_hub.section.returns.body",
                    bulletKeys: [
                        "tr_docs.topic.operations_hub.section.returns.bullet.1",
                        "tr_docs.topic.operations_hub.section.returns.bullet.2",
                        "tr_docs.topic.operations_hub.section.returns.bullet.3",
                    ]
                ),
                Section(
                    id: "search",
                    titleKey: "tr_docs.topic.operations_hub.section.search.title",
                    bodyKey: "tr_docs.topic.operations_hub.section.search.body",
                    bulletKeys: [
                        "tr_docs.topic.operations_hub.section.search.bullet.1",
                        "tr_docs.topic.operations_hub.section.search.bullet.2",
                    ]
                ),
            ]
        case .checkout:
            return [
                Section(
                    id: "start",
                    titleKey: "tr_docs.topic.checkout.section.start.title",
                    bodyKey: "tr_docs.topic.checkout.section.start.body",
                    bulletKeys: [
                        "tr_docs.topic.checkout.section.start.bullet.1",
                        "tr_docs.topic.checkout.section.start.bullet.2",
                    ]
                ),
                Section(
                    id: "photos",
                    titleKey: "tr_docs.topic.checkout.section.photos.title",
                    bodyKey: "tr_docs.topic.checkout.section.photos.body",
                    bulletKeys: [
                        "tr_docs.topic.checkout.section.photos.bullet.1",
                        "tr_docs.topic.checkout.section.photos.bullet.2",
                        "tr_docs.topic.checkout.section.photos.bullet.3",
                    ]
                ),
                Section(
                    id: "customer",
                    titleKey: "tr_docs.topic.checkout.section.customer.title",
                    bodyKey: "tr_docs.topic.checkout.section.customer.body",
                    bulletKeys: [
                        "tr_docs.topic.checkout.section.customer.bullet.1",
                        "tr_docs.topic.checkout.section.customer.bullet.2",
                        "tr_docs.topic.checkout.section.customer.bullet.3",
                    ]
                ),
                Section(
                    id: "complete",
                    titleKey: "tr_docs.topic.checkout.section.complete.title",
                    bodyKey: "tr_docs.topic.checkout.section.complete.body",
                    bulletKeys: [
                        "tr_docs.topic.checkout.section.complete.bullet.1",
                        "tr_docs.topic.checkout.section.complete.bullet.2",
                        "tr_docs.topic.checkout.section.complete.bullet.3",
                    ]
                ),
            ]
        case .returnProcess:
            return [
                Section(
                    id: "start",
                    titleKey: "tr_docs.topic.return.section.start.title",
                    bodyKey: "tr_docs.topic.return.section.start.body",
                    bulletKeys: [
                        "tr_docs.topic.return.section.start.bullet.1",
                        "tr_docs.topic.return.section.start.bullet.2",
                    ]
                ),
                Section(
                    id: "condition",
                    titleKey: "tr_docs.topic.return.section.condition.title",
                    bodyKey: "tr_docs.topic.return.section.condition.body",
                    bulletKeys: [
                        "tr_docs.topic.return.section.condition.bullet.1",
                        "tr_docs.topic.return.section.condition.bullet.2",
                        "tr_docs.topic.return.section.condition.bullet.3",
                    ]
                ),
                Section(
                    id: "customer",
                    titleKey: "tr_docs.topic.return.section.customer.title",
                    bodyKey: "tr_docs.topic.return.section.customer.body",
                    bulletKeys: [
                        "tr_docs.topic.return.section.customer.bullet.1",
                        "tr_docs.topic.return.section.customer.bullet.2",
                    ]
                ),
                Section(
                    id: "complete",
                    titleKey: "tr_docs.topic.return.section.complete.title",
                    bodyKey: "tr_docs.topic.return.section.complete.body",
                    bulletKeys: [
                        "tr_docs.topic.return.section.complete.bullet.1",
                        "tr_docs.topic.return.section.complete.bullet.2",
                        "tr_docs.topic.return.section.complete.bullet.3",
                    ]
                ),
            ]
        case .damage:
            return [
                Section(
                    id: "overview",
                    titleKey: "tr_docs.topic.damage.section.overview.title",
                    bodyKey: "tr_docs.topic.damage.section.overview.body",
                    bulletKeys: [
                        "tr_docs.topic.damage.section.overview.bullet.1",
                        "tr_docs.topic.damage.section.overview.bullet.2",
                    ]
                ),
                Section(
                    id: "nav",
                    titleKey: "tr_docs.topic.damage.section.nav.title",
                    bodyKey: "tr_docs.topic.damage.section.nav.body",
                    bulletKeys: [
                        "tr_docs.topic.damage.section.nav.bullet.1",
                        "tr_docs.topic.damage.section.nav.bullet.2",
                    ]
                ),
                Section(
                    id: "photos",
                    titleKey: "tr_docs.topic.damage.section.photos.title",
                    bodyKey: "tr_docs.topic.damage.section.photos.body",
                    bulletKeys: [
                        "tr_docs.topic.damage.section.photos.bullet.1",
                        "tr_docs.topic.damage.section.photos.bullet.2",
                        "tr_docs.topic.damage.section.photos.bullet.3",
                    ]
                ),
                Section(
                    id: "pdf",
                    titleKey: "tr_docs.topic.damage.section.pdf.title",
                    bodyKey: "tr_docs.topic.damage.section.pdf.body",
                    bulletKeys: [
                        "tr_docs.topic.damage.section.pdf.bullet.1",
                        "tr_docs.topic.damage.section.pdf.bullet.2",
                    ]
                ),
            ]
        }
    }
}

enum TurkeyDocumentationAccess {
    static func isTurkeyContext(serviceFranchiseId: String, userProfile: UserProfile?) -> Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile
        )
    }
}
