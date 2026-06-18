import Foundation

/// Stable `TabView` tag indices when optional tabs (Operations, Shuttle Map, CH OPS, CH Panel) differ per session.
struct MainTabRouter {
    let showsOperations: Bool
    let showsShuttleMap: Bool
    let showsCHOps: Bool
    let showsCHPanel: Bool

    let dashboard = 0
    let vehicles = 1
    let scan = 2

    var shuttleMap: Int? {
        guard showsShuttleMap else { return nil }
        return 3
    }

    var operations: Int? {
        guard showsOperations else { return nil }
        var tag = 3
        if showsShuttleMap { tag += 1 }
        return tag
    }

    var chOps: Int? {
        guard showsCHOps else { return nil }
        var tag = 3
        if showsShuttleMap { tag += 1 }
        if showsOperations { tag += 1 }
        return tag
    }

    var report: Int {
        var tag = 3
        if showsShuttleMap { tag += 1 }
        if showsOperations { tag += 1 }
        if showsCHOps { tag += 1 }
        return tag
    }

    var chPanel: Int? {
        guard showsCHPanel else { return nil }
        return report + 1
    }

    var maxTab: Int { chPanel ?? report }

    static func current(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> MainTabRouter {
        let garage = userProfile?.role == .garage
        return MainTabRouter(
            showsOperations: !garage && FranchiseCapabilityMatrix.operationsEnabledForSession(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile
            ),
            showsShuttleMap: FranchiseCapabilityMatrix.shuttleMapTabEnabledForSession(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: fallbackCountryCode
            ),
            showsCHOps: !garage && FranchiseCapabilityMatrix.chOpsJournalTabEnabledForSession(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: fallbackCountryCode
            ),
            showsCHPanel: FranchiseCapabilityMatrix.chAdminPanelTabEnabledForSession(
                serviceFranchiseId: serviceFranchiseId,
                userProfile: userProfile,
                fallbackCountryCode: fallbackCountryCode
            )
        )
    }
}
