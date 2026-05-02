import Foundation

/// Türkiye franchise şube listesi — araç kaydı ve Vehicle Track için ortak kimlikler.
/// Firestore `franchiseId` / login picker id’leri ile eşleşmeyen değerler ham olarak saklanır.
enum TurkiyeGarajSubeleri {
    struct Branch: Identifiable, Hashable {
        var id: String { storageKey }
        let storageKey: String
        let displayName: String
    }

    static let branches: [Branch] = [
        Branch(storageKey: "TR_IST_SABIHA", displayName: "İstanbul Sabiha Gökçen"),
        Branch(storageKey: "TR_NEVSEHIR", displayName: "Nevşehir"),
        Branch(storageKey: "TR_IST_AIRPORT", displayName: "İstanbul Havalimanı"),
        Branch(storageKey: "TR_ANTALYA", displayName: "Antalya"),
        Branch(storageKey: "TR_IZMIR", displayName: "İzmir"),
        Branch(storageKey: "TR_ANKARA", displayName: "Ankara")
    ]

    static func displayTitle(forStoredKey key: String?) -> String {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "—" }
        if let b = branches.first(where: { $0.storageKey.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return b.displayName
        }
        let canon = canonicalGarageStorageKey(for: trimmed)
        if !canon.isEmpty, let b = branches.first(where: { $0.storageKey == canon }) {
            return b.displayName
        }
        return trimmed
    }

    /// Oturum şubesi: login picker → yoksa aktif franchise id.
    static func sessionBranchStorageKey() -> String {
        if let s = UserDefaults.standard.loginSelectedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return s.uppercased()
        }
        return FirebaseService.shared.currentFranchiseId.uppercased()
    }

    // MARK: - Canonical branch keys (import / Vehicle Track / garage picker)

    private static func foldBranchToken(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// Resolves CSV text, display names, or `TR_*` keys to the canonical `TR_*` storage key when recognized.
    static func canonicalGarageStorageKey(for raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        if let b = branches.first(where: { $0.storageKey.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return b.storageKey
        }
        let folded = foldBranchToken(trimmed)
        for b in branches {
            if foldBranchToken(b.displayName) == folded { return b.storageKey }
            let afterPrefix = String(b.storageKey.dropFirst(3))
            let tail = afterPrefix.replacingOccurrences(of: "_", with: "")
            if folded == tail { return b.storageKey }
        }
        return ""
    }

    /// Stable identity for matching `garageBranchId` to the session branch (handles “nevsehir” vs `TR_NEVSEHIR`).
    static func normalizedGarageBranchIdentity(for raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        let c = canonicalGarageStorageKey(for: trimmed)
        return c.isEmpty ? trimmed.uppercased() : c
    }

    static func equivalentGarageBranchKeys(_ a: String?, _ b: String?) -> Bool {
        let na = normalizedGarageBranchIdentity(for: a)
        let nb = normalizedGarageBranchIdentity(for: b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb
    }

    /// Value stored on `Arac.garageBranchId` for Türkiye: always a known `TR_*` key when possible, otherwise login session key.
    static func persistedGarageBranchIdForTurkeyVehicle(csvOrPickerValue: String?) -> String {
        let session = sessionBranchStorageKey()
        let trimmed = csvOrPickerValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return session }
        let mapped = canonicalGarageStorageKey(for: trimmed)
        if !mapped.isEmpty { return mapped }
        return session
    }
}
