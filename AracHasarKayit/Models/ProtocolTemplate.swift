import Foundation
import FirebaseFirestore

struct ProtocolTemplate: Identifiable, Equatable {
    let id: String
    let templateCode: String
    let templateName: String
    let templateType: String
    let templatePath: String
    let fileName: String
    let storagePath: String
    let templateURL: String
    let baseCost: String
    let isActive: Bool
    let updatedAt: Date?

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        templateCode = (data["templateCode"] as? String ?? document.documentID).uppercased()
        templateName = data["templateName"] as? String ?? templateCode
        templateType = data["templateType"] as? String ?? ""
        templatePath = data["templatePath"] as? String ?? ""
        fileName = data["fileName"] as? String ?? ""
        storagePath = data["storagePath"] as? String ?? ""
        templateURL = data["templateUrl"] as? String ?? data["templateURL"] as? String ?? ""
        baseCost = data["baseCost"] as? String ?? ""
        if let active = data["isActive"] as? Bool {
            isActive = active
        } else if let n = data["isActive"] as? Int {
            isActive = n != 0
        } else {
            isActive = true
        }
        updatedAt = Self.parseTimestamp(data["updatedAt"]) ?? Self.parseTimestamp(data["createdAt"])
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let s = value as? String {
            return ISO8601DateFormatter().date(from: s)
        }
        return nil
    }
}

struct ProtocolTemplateUsageStat: Identifiable {
    let id: String
    let template: ProtocolTemplate
    let usageCount: Int
    let lastUsedAt: Date?
}

enum ProtocolTemplateAnalytics {
    static func usageStats(templates: [ProtocolTemplate], protocols: [Protocol]) -> [ProtocolTemplateUsageStat] {
        let activeTemplates = templates.filter(\.isActive)
        return activeTemplates.map { template in
            let matching = protocols.filter { matches(template: template, protocolRecord: $0) }
            let lastUsed = matching.compactMap(\.createdAtFormatted).max()
            return ProtocolTemplateUsageStat(
                id: template.id,
                template: template,
                usageCount: matching.count,
                lastUsedAt: lastUsed
            )
        }
        .sorted { lhs, rhs in
            if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
            return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }
    }

    private static func matches(template: ProtocolTemplate, protocolRecord: Protocol) -> Bool {
        let code = template.templateCode.uppercased()
        let path = protocolRecord.templatePath.uppercased()
        let type = protocolRecord.protocolType.uppercased()
        let name = protocolRecord.protocolName.uppercased()
        if !code.isEmpty, path.contains(code) { return true }
        if !template.templateType.isEmpty,
           template.templateType.uppercased() == type { return true }
        if !template.templateName.isEmpty,
           template.templateName.uppercased() == name { return true }
        return false
    }

    static func protocols(matching template: ProtocolTemplate, in protocols: [Protocol]) -> [Protocol] {
        protocols.filter { matches(template: template, protocolRecord: $0) }
    }
}
