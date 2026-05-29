import Foundation

struct JarvisHealthFinding: Identifiable, Codable, Equatable {
    let id: String
    let severity: String
    let category: String
    let message: String
    let count: Int
}

struct JarvisSystemHealthReport: Equatable {
    let franchiseId: String
    let scannedAt: Date
    let findings: [JarvisHealthFinding]
    let summaryJSON: String
    let table: JarvisDataTable

    var hasIssues: Bool { findings.contains { $0.severity != "info" } }
}

enum JarvisSystemHealthScanner {

    static func scan(viewModel: AracViewModel) -> JarvisSystemHealthReport {
        let fid = FirebaseService.shared.currentFranchiseId
        let damages = chScoped(viewModel.allHasarKayitlariForReporting, franchiseId: fid)
        let exits = chScoped(viewModel.exitIslemleri, franchiseId: fid)
        let returns = chScoped(viewModel.iadeIslemleri, franchiseId: fid)
        let office = chScoped(viewModel.officeOperations, franchiseId: fid)
        let traffic = chScoped(viewModel.trafficAccidentContracts, franchiseId: fid)

        var findings: [JarvisHealthFinding] = []

        let dupExits = duplicateExits(exits)
        if !dupExits.isEmpty {
            findings.append(JarvisHealthFinding(
                id: "dup_exit", severity: "warning", category: "checkout",
                message: "Possible duplicate checkouts (same RES within 2h)", count: dupExits.count
            ))
        }

        let dupReturns = duplicateReturns(returns)
        if !dupReturns.isEmpty {
            findings.append(JarvisHealthFinding(
                id: "dup_return", severity: "warning", category: "return",
                message: "Possible duplicate returns (same vehicle within 1h)", count: dupReturns.count
            ))
        }

        let dupOffice = duplicateOfficeOps(office)
        if !dupOffice.isEmpty {
            findings.append(JarvisHealthFinding(
                id: "dup_office", severity: "warning", category: "office",
                message: "Possible duplicate office operations", count: dupOffice.count
            ))
        }

        let orphanReturns = returns.filter { r in
            guard let lid = r.linkedExitId else { return false }
            return !exits.contains { $0.id == lid }
        }
        if !orphanReturns.isEmpty {
            findings.append(JarvisHealthFinding(
                id: "orphan_return", severity: "critical", category: "return",
                message: "Returns linked to missing checkout", count: orphanReturns.count
            ))
        }

        let noPhotoDamages = damages.filter { $0.fotograflar.isEmpty }.count
        if noPhotoDamages > 0 {
            findings.append(JarvisHealthFinding(
                id: "damage_no_photo", severity: "warning", category: "damage",
                message: "Damage reports without photos", count: noPhotoDamages
            ))
        }

        let inProgress = damages.filter { $0.durum == .inProgress }.count
        findings.append(JarvisHealthFinding(
            id: "damage_open", severity: inProgress > 15 ? "warning" : "info", category: "damage",
            message: "Open damage reports", count: inProgress
        ))

        let unpaidTraffic = traffic.filter { ($0.paidAmount ?? 0) < $0.amount - 0.01 }.count
        if unpaidTraffic > 0 {
            findings.append(JarvisHealthFinding(
                id: "traffic_unpaid", severity: "warning", category: "traffic",
                message: "Traffic contracts not fully paid", count: unpaidTraffic
            ))
        }

        findings.append(JarvisHealthFinding(
            id: "fleet_size", severity: "info", category: "system",
            message: "Vehicles in fleet", count: viewModel.araclar.count
        ))

        let payload: [String: Any] = [
            "franchise_id": fid,
            "scanned_at": ISO8601DateFormatter().string(from: Date()),
            "findings": findings.map {
                ["id": $0.id, "severity": $0.severity, "category": $0.category, "message": $0.message, "count": $0.count]
            }
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let jsonStr = String(data: jsonData, encoding: .utf8) ?? "{}"

        let table = JarvisDataTable(
            id: "system_health",
            title: "System health scan",
            headers: ["Severity", "Category", "Issue", "Count"],
            rows: findings.map { [$0.severity.uppercased(), $0.category, $0.message, "\($0.count)"] }
        )

        return JarvisSystemHealthReport(
            franchiseId: fid,
            scannedAt: Date(),
            findings: findings,
            summaryJSON: jsonStr,
            table: table
        )
    }

    private static func chScoped<T>(_ items: [T], franchiseId: String) -> [T] {
        items.filter { item in
            let fid: String
            if let d = item as? HasarKaydi { fid = d.franchiseId }
            else if let e = item as? ExitIslemi { fid = e.franchiseId ?? franchiseId }
            else if let r = item as? IadeIslemi { fid = r.franchiseId }
            else if let o = item as? OfficeOperation { fid = o.franchiseId }
            else if let t = item as? TrafficAccidentContract { fid = t.franchiseId }
            else { return true }
            return FranchiseCapabilityMatrix.isSwitzerland(franchiseId: fid)
        }
    }

    private static func duplicateExits(_ exits: [ExitIslemi]) -> [[ExitIslemi]] {
        var groups: [String: [ExitIslemi]] = [:]
        for e in exits where !e.resKodu.isEmpty {
            groups[e.resKodu, default: []].append(e)
        }
        return groups.values.filter { group in
            guard group.count > 1 else { return false }
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            for i in 1..<sorted.count {
                if sorted[i].createdAt.timeIntervalSince(sorted[i - 1].createdAt) < 7200 { return true }
            }
            return false
        }
    }

    private static func duplicateReturns(_ returns: [IadeIslemi]) -> [[IadeIslemi]] {
        var byPlate: [String: [IadeIslemi]] = [:]
        for r in returns {
            byPlate[r.aracPlaka, default: []].append(r)
        }
        return byPlate.values.filter { group in
            guard group.count > 1 else { return false }
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            for i in 1..<sorted.count {
                if sorted[i].createdAt.timeIntervalSince(sorted[i - 1].createdAt) < 3600 { return true }
            }
            return false
        }
    }

    private static func duplicateOfficeOps(_ ops: [OfficeOperation]) -> [[OfficeOperation]] {
        var keyMap: [String: [OfficeOperation]] = [:]
        for o in ops {
            let plate = o.vehiclePlate ?? ""
            let key = "\(o.type.rawValue)|\(plate)|\(Int(o.amount * 100))|\(Int(o.date.timeIntervalSince1970 / 300))"
            keyMap[key, default: []].append(o)
        }
        return keyMap.values.filter { $0.count > 1 }
    }
}
