import Foundation

/// Centralized WheelSys debug logging.
///
/// Every WheelSys subsystem (session, fleet, availability, entity sync, return
/// check-in) logs through here so the Xcode console shows consistent,
/// correlatable lines. Never log raw session cookies or PII tokens — only
/// presence flags, plates, entity IDs, counts, and status.
///
/// Format: `[WheelSys][<area>] <message>`  (with optional `cid=<correlationId>`)
enum WheelSysDebug {

    /// Generate a short correlation id to thread a single flow
    /// (e.g. fleet load -> plate match -> entity sync).
    static func newCorrelationId() -> String {
        String(UUID().uuidString.prefix(8))
    }

    static func log(
        _ area: String,
        _ message: @autoclosure () -> String,
        cid: String? = nil
    ) {
        #if DEBUG
        if let cid, !cid.isEmpty {
            print("[WheelSys][\(area)] cid=\(cid) \(message())")
        } else {
            print("[WheelSys][\(area)] \(message())")
        }
        #endif
    }

    static func error(
        _ area: String,
        _ message: @autoclosure () -> String,
        cid: String? = nil
    ) {
        #if DEBUG
        if let cid, !cid.isEmpty {
            print("[WheelSys][\(area)][ERROR] cid=\(cid) \(message())")
        } else {
            print("[WheelSys][\(area)][ERROR] \(message())")
        }
        #endif
    }
}
