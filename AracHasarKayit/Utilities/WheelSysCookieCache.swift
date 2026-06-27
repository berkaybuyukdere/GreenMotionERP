import Foundation
import FirebaseAuth
import KeychainSwift

/// WheelSys session cookie from the last successful WKWebView login.
/// Persisted per Firebase user + franchise in Keychain.
/// Never log the value — only presence flags.
enum WheelSysCookieCache {
    private static let keychain = KeychainSwift()
    private(set) static var lastCookie: String?
    /// WheelSys operator id tied to the active session cookie (rdUserTo).
    private(set) static var wheelSysOperatorId: String?
    /// Backend Firestore session probe succeeded for the bound Firebase user.
    private(set) static var serverSessionValid = false
    private(set) static var boundUserId: String?

    /// Legacy shared keys (pre per-user isolation) — cleared on rebind.
    private static let legacyActiveSessionKey = "wheelsys_session_cookie_active"

    private static func storageKey(userId: String, franchiseId: String, station: String = "ZRH") -> String {
        let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let st = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "wheelsys_session_\(uid)_\(fid)_\(st)"
    }

    private static func legacyStorageKey(franchiseId: String, station: String = "ZRH") -> String {
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let st = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "wheelsys_session_cookie_\(fid)_\(st)"
    }

    private static func activeSessionKey(userId: String) -> String {
        "wheelsys_session_active_\(userId)"
    }

    static func currentUserId() -> String? {
        Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func operatorStorageKey(userId: String, franchiseId: String) -> String {
        let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "wheelsys_operator_\(uid)_\(fid)"
    }

    static func setWheelSysOperator(id: String?, franchiseId: String? = nil) {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        wheelSysOperatorId = trimmed.isEmpty ? nil : trimmed
        guard let uid = currentUserId(), !uid.isEmpty else { return }
        let fid = (franchiseId ?? FirebaseService.shared.currentFranchiseId)
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !fid.isEmpty else { return }
        let key = operatorStorageKey(userId: uid, franchiseId: fid)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    static func restoreWheelSysOperator(franchiseId: String) {
        guard let uid = currentUserId(), !uid.isEmpty else {
            wheelSysOperatorId = nil
            return
        }
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !fid.isEmpty else {
            wheelSysOperatorId = nil
            return
        }
        let stored = UserDefaults.standard.string(forKey: operatorStorageKey(userId: uid, franchiseId: fid))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        wheelSysOperatorId = stored.isEmpty ? nil : stored
    }

    /// Call when Firebase auth user changes (login, profile restore, logout).
    static func rebindToCurrentUser(clearMemory: Bool = true) {
        purgeLegacySharedKeys()
        let uid = currentUserId()
        if boundUserId != uid {
            if clearMemory {
                lastCookie = nil
                serverSessionValid = false
                wheelSysOperatorId = nil
            }
            boundUserId = uid
        }
    }

    private static func purgeLegacySharedKeys() {
        keychain.delete(legacyActiveSessionKey)
    }

    /// Build Fleet Chart auth cookie — only `.wheelsys` + `__Secure-SID` (matches Chrome).
    static func buildAuthCookie(wheelsys: String, secureSID: String) -> String {
        ".wheelsys=\(wheelsys); __Secure-SID=\(secureSID)"
    }

    /// Extract auth-only cookie from a full header string.
    static func authOnly(from header: String) -> String? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var wheelsys: String?
        var sid: String?
        for part in trimmed.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let name = String(piece[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(piece[piece.index(after: eq)...])
            if name == ".wheelsys" { wheelsys = value }
            if name == "__Secure-SID" { sid = value }
        }
        guard let ws = wheelsys, !ws.isEmpty, let s = sid, !s.isEmpty else { return nil }
        return buildAuthCookie(wheelsys: ws, secureSID: s)
    }

    static func restorePersistedSession(franchiseId: String, station: String = "ZRH") {
        rebindToCurrentUser(clearMemory: true)
        guard let uid = currentUserId(), !uid.isEmpty else {
            lastCookie = nil
            serverSessionValid = false
            return
        }

        let key = storageKey(userId: uid, franchiseId: franchiseId, station: station)
        if let stored = keychain.get(key), let auth = authOnly(from: stored) {
            lastCookie = auth
            keychain.set(auth, forKey: activeSessionKey(userId: uid))
            logPresence(auth, label: "keychain restore user=\(uid.prefix(6))…")
            return
        }

        lastCookie = nil
        WheelSysDebug.log(
            "CookieCache",
            "restore miss user=\(uid.prefix(6))… franchise=\(franchiseId.uppercased()) station=\(station)"
        )
    }

    static func set(_ cookie: String, franchiseId: String? = nil, station: String = "ZRH") {
        guard let uid = currentUserId(), !uid.isEmpty else { return }
        rebindToCurrentUser(clearMemory: false)

        let auth = authOnly(from: cookie) ?? cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        lastCookie = auth
        logPresence(auth, label: "cookie cached user=\(uid.prefix(6))…")
        let fid = (franchiseId ?? FirebaseService.shared.currentFranchiseId)
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !fid.isEmpty else { return }
        purgeLegacySharedKeys()
        keychain.set(auth, forKey: storageKey(userId: uid, franchiseId: fid, station: station))
        keychain.set(auth, forKey: activeSessionKey(userId: uid))
    }

    static func clear(franchiseId: String? = nil, station: String = "ZRH") {
        lastCookie = nil
        serverSessionValid = false
        wheelSysOperatorId = nil
        purgeLegacySharedKeys()
        let uid = boundUserId ?? currentUserId()
        guard let uid, !uid.isEmpty else { return }
        keychain.delete(activeSessionKey(userId: uid))
        if let fid = franchiseId?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !fid.isEmpty {
            keychain.delete(storageKey(userId: uid, franchiseId: fid, station: station))
            keychain.delete(legacyStorageKey(franchiseId: fid, station: station))
        }
        WheelSysDebug.log("CookieCache", "cleared user=\(uid.prefix(6))… franchise=\(franchiseId ?? "all")")
    }

    static func clearAllPersisted() {
        let uid = boundUserId ?? currentUserId()
        lastCookie = nil
        serverSessionValid = false
        boundUserId = nil
        purgeLegacySharedKeys()
        if let uid, !uid.isEmpty {
            keychain.delete(activeSessionKey(userId: uid))
            let fid = FirebaseService.shared.currentFranchiseId
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !fid.isEmpty {
                keychain.delete(storageKey(userId: uid, franchiseId: fid, station: "ZRH"))
                keychain.delete(legacyStorageKey(franchiseId: fid, station: "ZRH"))
            }
        }
        WheelSysDebug.log("CookieCache", "cleared all persisted keys for current user")
    }

    static func markServerSessionValid(_ valid: Bool) {
        if serverSessionValid != valid {
            WheelSysDebug.log("CookieCache", "serverSessionValid=\(valid)")
        }
        serverSessionValid = valid
    }

    static var isValid: Bool {
        guard currentUserId() != nil else { return false }
        guard let c = lastCookie, !c.isEmpty else { return false }
        return c.contains(".wheelsys=") && c.contains("__Secure-SID=")
    }

    /// Callable / server-side WheelSys ops for the current Firebase user only.
    static var hasUsableSession: Bool {
        guard currentUserId() != nil else { return false }
        return isValid || serverSessionValid
    }

    static func logPresence(_ header: String, label: String) {
        let hasWheelsys = header.contains(".wheelsys=")
        let hasSID = header.contains("__Secure-SID=")
        WheelSysDebug.log(
            "CookieCache",
            "\(label): hasWheelsys=\(hasWheelsys) hasSID=\(hasSID) length=\(header.count)"
        )
    }
}
