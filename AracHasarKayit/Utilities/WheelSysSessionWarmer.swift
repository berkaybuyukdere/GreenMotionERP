import Foundation

/// Background warm requests to collect full ASP.NET cookie set (incl. ASP.NET_SessionId).
/// Never logs cookie values — only cookie names.
enum WheelSysSessionWarmer {
    private static let cookieDomain = "ch.wheelsys.greenmotion.com"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 VehicleSentinel"

    private static let warmURLs: [URL] = [
        URL(string: "https://ch.wheelsys.greenmotion.com/ui/manage/master/rentals.aspx")!,
        URL(string: "https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx")!,
    ]

    /// Inject base auth cookies, warm key WheelSys pages, return merged header.
    static func warmAndBuildCookieHeader(from baseHeader: String) async -> String {
        guard FranchiseCapabilityMatrix.wheelSysEnabledForActiveFranchise(
            FirebaseService.shared.currentFranchiseId
        ) else {
            return baseHeader
        }

        let trimmed = baseHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return baseHeader }

        let store = HTTPCookieStorage.shared
        injectCookies(from: trimmed, into: store)

        for url in warmURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            _ = try? await URLSession.shared.data(for: request)
        }

        let merged = buildHeader(from: store)
        logCookieNames(merged, label: "after warm")
        return merged.isEmpty ? trimmed : merged
    }

    private static func injectCookies(from header: String, into store: HTTPCookieStorage) {
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: cookieDomain,
                .path: "/",
            ]
            if name.hasPrefix("__Secure-") {
                properties[.secure] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: properties) {
                store.setCookie(cookie)
            }
        }
    }

    private static func buildHeader(from store: HTTPCookieStorage) -> String {
        let cookies = store.cookies?.filter {
            $0.domain.contains("wheelsys.greenmotion.com")
        } ?? []

        var byName: [String: HTTPCookie] = [:]
        for cookie in cookies {
            byName[cookie.name] = cookie
        }
        return byName.values
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    static func logCookieNames(_ header: String, label: String) {
        let names = header.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces).split(separator: "=").first.map(String.init) ?? "" }
            .filter { !$0.isEmpty }
            .sorted()
        print("[WheelSys] \(label): count=\(names.count) names=[\(names.joined(separator: ", "))]")
        print("[WheelSys] hasAspNetSession=\(names.contains("ASP.NET_SessionId"))")
    }
}
