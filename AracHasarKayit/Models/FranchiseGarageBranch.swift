import Foundation

/// Garage / şube locations from Firestore `franchises/{id}` — typically `garageBranches` array.
/// Each entry: `storageKey` (persisted on `Arac.garageBranchId`), `displayName`, optional `countryCode` (ISO, e.g. TR).
struct FranchiseGarageBranch: Identifiable, Hashable {
    var storageKey: String
    var displayName: String
    var countryCode: String?
    var id: String { storageKey }

    static func parseList(from data: [String: Any]) -> [FranchiseGarageBranch] {
        let arrayFieldNames = [
            "garageBranches", "locations", "branches", "garageLocations",
            "franchiseGarages", "subeler", "garage_branch_list", "officeLocations"
        ]
        for key in arrayFieldNames {
            if let parsed = parseFromArrayField(data[key]), !parsed.isEmpty {
                return parsed
            }
        }
        let mapFieldNames = ["locations", "garageBranchesById", "garageBranchMap", "locationMap", "garages"]
        for key in mapFieldNames {
            if let d = data[key] as? [String: Any], !d.isEmpty {
                let parsed = parseKeyedBranchMap(d)
                if !parsed.isEmpty { return parsed }
            }
        }
        return []
    }

    // MARK: - Parsing helpers

    private static func parseFromArrayField(_ value: Any?) -> [FranchiseGarageBranch]? {
        guard let value else { return nil }
        if let arr = value as? [[String: Any]] {
            let p = parseBranchDictionaries(arr)
            return p.isEmpty ? nil : p
        }
        if let arr = value as? [Any] {
            let dicts = arr.compactMap { $0 as? [String: Any] }
            if !dicts.isEmpty {
                let p = parseBranchDictionaries(dicts)
                return p.isEmpty ? nil : p
            }
            let strings = arr.compactMap { anyString($0) }.filter { !$0.isEmpty }
            if !strings.isEmpty {
                return strings.map { FranchiseGarageBranch(storageKey: $0, displayName: $0, countryCode: nil) }
            }
        }
        return nil
    }

    /// Map keyed by storage id, e.g. `{ "TR_NEVSEHIR": { "displayName": "Nevşehir" } }` or `{ "TR_X": "Label" }`.
    private static func parseKeyedBranchMap(_ map: [String: Any]) -> [FranchiseGarageBranch] {
        map.compactMap { key, value -> FranchiseGarageBranch? in
            let sk = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sk.isEmpty else { return nil }
            if let nested = value as? [String: Any] {
                var m = nested
                if m["storageKey"] == nil { m["storageKey"] = sk }
                return parseBranchDictionaries([m]).first
            }
            if let name = anyString(value), !name.isEmpty {
                return FranchiseGarageBranch(storageKey: sk, displayName: name, countryCode: nil)
            }
            return FranchiseGarageBranch(storageKey: sk, displayName: sk, countryCode: nil)
        }
        .sorted { $0.storageKey < $1.storageKey }
    }

    private static func anyString(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? Int { return String(n) }
        if let n = v as? Int64 { return String(n) }
        if let d = v as? Double { return String(Int(d)) }
        return nil
    }

    private static func stringField(_ dict: [String: Any], _ keys: [String]) -> String {
        for k in keys {
            if let s = anyString(dict[k]), !s.isEmpty { return s }
        }
        return ""
    }

    private static func parseBranchDictionaries(_ arr: [[String: Any]]) -> [FranchiseGarageBranch] {
        arr.compactMap { dict -> FranchiseGarageBranch? in
            let key = stringField(
                dict,
                ["storageKey", "storage_key", "id", "code", "branchId", "branch_id", "branchKey", "branch_key", "key", "franchiseId", "franchise_id"]
            )
            var name = stringField(
                dict,
                ["displayName", "display_name", "name", "title", "label", "branchName", "branch_name", "locationName", "location_name"]
            )
            guard !key.isEmpty else { return nil }
            if name.isEmpty { name = key }
            let rawCc = stringField(dict, ["countryCode", "country_code", "country", "isoCountry", "iso_country"])
            let cc = rawCc.isEmpty ? nil : rawCc.uppercased()
            return FranchiseGarageBranch(storageKey: key, displayName: name, countryCode: cc)
        }
    }
}
