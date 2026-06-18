import Foundation

/// In-memory WheelSys session cookie from the last successful WKWebView login.
/// Never log the value — only presence flags.
enum WheelSysCookieCache {
    private(set) static var lastCookie: String?

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

    static func set(_ cookie: String) {
        let auth = authOnly(from: cookie) ?? cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        lastCookie = auth
        logPresence(auth, label: "cookie cached")
    }

    static func clear() {
        lastCookie = nil
        print("[WheelSys] cookie cache cleared")
    }

    static var isValid: Bool {
        guard let c = lastCookie, !c.isEmpty else { return false }
        return c.contains(".wheelsys=") && c.contains("__Secure-SID=")
    }

    static func logPresence(_ header: String, label: String) {
        let hasWheelsys = header.contains(".wheelsys=")
        let hasSID = header.contains("__Secure-SID=")
        print("[WheelSys] \(label): hasWheelsys=\(hasWheelsys) hasSID=\(hasSID) cookieLength=\(header.count)")
    }
}
