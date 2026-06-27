import Foundation

/// Lightweight performance tracing for scroll / sheet / network hotspots (DEBUG console).
enum PerfTrace {
    private static var spans: [String: CFAbsoluteTime] = [:]
    private static let lock = NSLock()

    @discardableResult
    static func begin(_ name: String, detail: String? = nil) -> String {
        let token = "\(name)#\(UUID().uuidString.prefix(6))"
        lock.lock()
        spans[token] = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        #if DEBUG
        if let detail, !detail.isEmpty {
            print("[Perf] ▶ \(name) {\(detail)}")
        } else {
            print("[Perf] ▶ \(name)")
        }
        #endif
        return token
    }

    static func end(_ token: String, note: String? = nil) {
        lock.lock()
        let start = spans.removeValue(forKey: token)
        lock.unlock()
        guard let start else { return }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        #if DEBUG
        if let note, !note.isEmpty {
            print(String(format: "[Perf] ◀ %.1fms — %@ (%@)", ms, tokenPrefix(token), note))
        } else {
            print(String(format: "[Perf] ◀ %.1fms — %@", ms, tokenPrefix(token)))
        }
        #endif
    }

    static func mark(_ name: String, detail: String? = nil) {
        #if DEBUG
        if let detail, !detail.isEmpty {
            print("[Perf] • \(name) {\(detail)}")
        } else {
            print("[Perf] • \(name)")
        }
        #endif
    }

    static func measure<T>(_ name: String, detail: String? = nil, _ work: () throws -> T) rethrows -> T {
        let token = begin(name, detail: detail)
        defer { end(token) }
        return try work()
    }

    static func measureAsync<T>(_ name: String, detail: String? = nil, _ work: () async throws -> T) async rethrows -> T {
        let token = begin(name, detail: detail)
        defer { end(token) }
        return try await work()
    }

    private static func tokenPrefix(_ token: String) -> String {
        token.split(separator: "#").first.map(String.init) ?? token
    }
}
