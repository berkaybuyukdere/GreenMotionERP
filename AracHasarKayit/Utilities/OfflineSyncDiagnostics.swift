import Foundation

/// Heuristics for “likely to succeed after reconnect” vs hard failures (permissions, etc.).
enum OfflineSyncDiagnostics {
    static func isLikelyTransientNetworkFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return true
        }
        if ns.domain == "FIRStorageErrorDomain" {
            // Common codes: network (-13020), retry limit exceeded (-13040), cancelled (-13040 area)
            return [-13020, -13040, -13010].contains(ns.code)
        }
        return false
    }
}
