import Foundation

/// Public customer self-fill URLs (QR on checkout / return sheets). Keep in sync with web `franchiseCapabilities.js`.
enum CustomerFormWebLinks {
    /// Production ERPX hosting — override via Info.plist `CustomerFormWebBaseURL` if needed.
    static var baseURL: String {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "CustomerFormWebBaseURL") as? String {
            let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) }
        }
        return "https://vehiclesentinel.com"
    }

    static func returnFormURL(token: String, franchiseId: String) -> String {
        formURL(page: "return.html", token: token, franchiseId: franchiseId)
    }

    static func checkoutFormURL(token: String, franchiseId: String) -> String {
        formURL(page: "checkout.html", token: token, franchiseId: franchiseId)
    }

    private static func formURL(page: String, token: String, franchiseId: String) -> String {
        let fr = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = URLComponents()
        parts.scheme = "https"
        if let hostURL = URL(string: baseURL), let host = hostURL.host {
            parts.host = host
            parts.scheme = hostURL.scheme ?? "https"
            if let port = hostURL.port { parts.port = port }
            let path = hostURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            parts.path = path.isEmpty ? "/\(page)" : "\(hostURL.path)/\(page)".replacingOccurrences(of: "//", with: "/")
        } else {
            parts.host = "vehiclesentinel.com"
            parts.path = "/\(page)"
        }
        parts.queryItems = [
            URLQueryItem(name: "token", value: tok),
            URLQueryItem(name: "franchise", value: fr),
        ]
        return parts.url?.absoluteString ?? "\(baseURL)/\(page)?token=\(tok)&franchise=\(fr)"
    }
}
