import Foundation

/// Re-localizes user-generated or legacy strings (saved in creator locale) for the active app language.
enum PersistedLabelLocalizer {
    private static let officeTypeKeyByNormalizedLabel: [String: String] = buildOfficeTypeReverseMap()

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func buildOfficeTypeReverseMap() -> [String: String] {
        var map: [String: String] = [:]
        for type in OfficeOperationType.allCases {
            let key = type.rawValue
            map[normalize(key)] = key
            for bundle in [LocalizationManager.shared.bundle] + auxiliaryLanguageBundles {
                let translated = NSLocalizedString(key, bundle: bundle, value: key, comment: "")
                map[normalize(translated)] = key
            }
        }
        // Legacy / shorthand labels seen in older builds
        map[normalize("POS")] = OfficeOperationType.posClosing.rawValue
        map[normalize("Fuel")] = OfficeOperationType.fuelReceipt.rawValue
        map[normalize("Yakıt")] = OfficeOperationType.fuelReceipt.rawValue
        map[normalize("Washing")] = OfficeOperationType.washing.rawValue
        map[normalize("Yıkama")] = OfficeOperationType.washing.rawValue
        return map
    }

    private static var auxiliaryLanguageBundles: [Bundle] {
        ["tr", "de"].compactMap { code in
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
            return Bundle(path: path)
        }
    }

    static func canonicalOfficeTypeKey(for label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if OfficeOperationType(rawValue: trimmed) != nil { return trimmed }
        return officeTypeKeyByNormalizedLabel[normalize(trimmed)]
    }

    static func localizedOfficeTypeName(_ stored: String) -> String {
        guard let key = canonicalOfficeTypeKey(for: stored) else {
            return stored
        }
        return key.localized
    }

    /// `"Yakıt Makbuzu - CHF 12.00"` → localized type + preserved amount tail.
    static func localizeOfficeOperationLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return line }

        let separators = [" - ", " – ", " — ", " · "]
        for sep in separators {
            guard let range = trimmed.range(of: sep) else { continue }
            let typePart = String(trimmed[..<range.lowerBound])
            let tail = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let localizedType = localizedOfficeTypeName(typePart)
            if tail.isEmpty { return localizedType }
            return "\(localizedType)\(sep)\(tail)"
        }

        return localizedOfficeTypeName(trimmed)
    }

    static func localizeActivityDescription(_ activity: Activity) -> String {
        let lower = activity.aciklama.lowercased()
        let plate = activity.aracPlaka ?? activity.aciklama.components(separatedBy: " - ").first ?? ""

        switch activity.tip {
        case .officeOperation, .officeOperationSilindi:
            return localizeOfficeOperationLine(activity.aciklama)

        case .iadeYapildi:
            if lower.contains("güncellendi") || lower.contains("updated") {
                return "\(plate) - \("Return Updated".localized)"
            }
            if lower.contains("tamamland") || lower.contains("completed") {
                return "\(plate) - \("Return Completed".localized)"
            }
            return "\(plate) - \("Return Completed".localized)"

        case .exitYapildi:
            if lower.contains("güncellendi") || lower.contains("updated") {
                return "\(plate) - \("Check Out Updated".localized)"
            }
            if lower.contains("completed") || lower.contains("tamamland") {
                return "\(plate) - \("Check Out Completed".localized)"
            }
            return "\(plate) - \("Check Out Completed".localized)"

        case .checkInKaydedildi:
            return localizeCheckInLine(activity.aciklama)

        case .aracEklendi:
            return localizeVehicleStatusLine(activity.aciklama, addedKey: "Vehicle Added", deletedKey: nil)

        case .aracSilindi:
            return localizeVehicleStatusLine(activity.aciklama, addedKey: nil, deletedKey: "Vehicle Deleted")

        case .hasarEklendi, .hasarSilindi, .hasarGuncellendi:
            return localizeDamageLine(activity.aciklama, tip: activity.tip)

        case .servisEklendi:
            return localizeServiceLine(activity.aciklama)

        case .wheelsysNtrOpen, .wheelsysNtrClose,
             .wheelsysPrecheckin, .wheelsysCheckinSync,
             .wheelsysNoteSaved, .wheelsysNoteDeleted,
             .wheelsysVehicleAssigned, .wheelsysVehicleRemoved, .wheelsysVehicleChanged:
            if let detail = activity.detayliAciklama, !detail.isEmpty {
                return "\(plate) — \(detail)"
            }
            return plate.isEmpty ? activity.aciklama : plate

        default:
            return localizeGenericStoredString(activity.aciklama)
        }
    }

    static func localizedLiveActivityTitle(_ title: String, kind: LiveActivityKind) -> String {
        let key = normalize(title)
        switch key {
        case normalize("Signed in"): return "live_activity.signed_in".localized
        case normalize("Signed out"): return "live_activity.signed_out".localized
        case normalize("Online"): return "live_activity.online".localized
        case normalize("Offline"): return "live_activity.offline".localized
        case normalize("Away"): return "live_activity.away".localized
        case normalize("Office operation added"): return "live_activity.office_added".localized
        case normalize("Office operation updated"): return "live_activity.office_updated".localized
        case normalize("Office operation deleted"): return "live_activity.office_deleted".localized
        default:
            switch kind {
            case .checkoutCompleted: return "live_activity.checkout_completed".localized
            case .checkoutParked: return "live_activity.checkout_parked".localized
            case .checkoutDeleted: return "live_activity.checkout_deleted".localized
            case .returnCompleted: return "live_activity.return_completed".localized
            case .returnDeleted: return "live_activity.return_deleted".localized
            case .damageCreated: return "live_activity.damage_created".localized
            case .damageUpdated: return "live_activity.damage_updated".localized
            case .damageCompleted: return "live_activity.damage_completed".localized
            case .damageDeleted: return "live_activity.damage_deleted".localized
            case .washingCreated: return "live_activity.washing_created".localized
            case .washingUpdated: return "live_activity.washing_updated".localized
            case .washingDeleted: return "live_activity.washing_deleted".localized
            case .wheelsysPrecheckin: return "live_activity.wheelsys_precheckin".localized
            case .wheelsysCheckinSync: return "live_activity.wheelsys_checkin_sync".localized
            case .wheelsysNoteSaved: return "live_activity.wheelsys_note_saved".localized
            case .wheelsysNoteDeleted: return "live_activity.wheelsys_note_deleted".localized
            case .wheelsysNtrOpen: return "live_activity.wheelsys_ntr_open".localized
            case .wheelsysNtrClose: return "live_activity.wheelsys_ntr_close".localized
            case .wheelsysVehicleAssigned: return "live_activity.wheelsys_vehicle_assigned".localized
            case .wheelsysVehicleRemoved: return "live_activity.wheelsys_vehicle_removed".localized
            case .wheelsysVehicleChanged: return "live_activity.wheelsys_vehicle_changed".localized
            default:
                return title
            }
        }
    }

    static func localizedLiveActivitySubtitle(_ subtitle: String) -> String {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return subtitle }
        if trimmed.contains(" · ") {
            let parts = trimmed.components(separatedBy: " · ")
            guard parts.count >= 2 else { return localizeOfficeOperationLine(trimmed) }
            let typePart = parts[0]
            let tail = parts.dropFirst().joined(separator: " · ")
            return "\(localizedOfficeTypeName(typePart)) · \(tail)"
        }
        return localizeOfficeOperationLine(trimmed)
    }

    static func localizeGenericStoredString(_ stored: String) -> String {
        if let key = canonicalOfficeTypeKey(for: stored) {
            return key.localized
        }
        return stored
    }

    private static func localizeCheckInLine(_ line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("check in") || lower.contains("giriş") || lower.contains("kaydedildi") {
            // Preserve plate / RES / km details after the first segment when present.
            if let dashRange = line.range(of: " - ") {
                let head = String(line[..<dashRange.lowerBound])
                let tail = String(line[dashRange.upperBound...])
                return "\(head) - \("Check In Saved".localized) · \(tail)"
            }
            return line.replacingOccurrences(of: "Check In Kaydedildi", with: "Check In Saved".localized, options: .caseInsensitive)
        }
        return line
    }

    private static func localizeVehicleStatusLine(_ line: String, addedKey: String?, deletedKey: String?) -> String {
        guard let dashRange = line.range(of: " - ") else { return line }
        let plate = String(line[..<dashRange.lowerBound])
        let detail = String(line[dashRange.upperBound...])
        if let addedKey {
            return "\(plate) - \(detail) (\(addedKey.localized))"
        }
        if let deletedKey {
            return "\(plate) - \(detail) (\(deletedKey.localized))"
        }
        return line
    }

    private static func localizeDamageLine(_ line: String, tip: ActivityType) -> String {
        guard let dashRange = line.range(of: " - ") else { return line }
        let plate = String(line[..<dashRange.lowerBound])
        let tail = String(line[dashRange.upperBound...])
        let action: String
        switch tip {
        case .hasarEklendi: action = "Damage Added".localized
        case .hasarSilindi: action = "Damage Deleted".localized
        case .hasarGuncellendi: action = "Damage Updated".localized
        default: return line
        }
        if tail.lowercased().contains("status:") {
            return "\(plate) - \(tail.replacingOccurrences(of: "Status:", with: "\("Status".localized):"))"
        }
        return "\(plate) - \(tail) (\(action))"
    }

    private static func localizeServiceLine(_ line: String) -> String {
        guard let dashRange = line.range(of: " - ") else { return line }
        let plate = String(line[..<dashRange.lowerBound])
        let company = String(line[dashRange.upperBound...])
        return "\(plate) - \(company) (\("Service Added".localized))"
    }
}
