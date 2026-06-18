import Foundation

/// Switzerland (CH) Stripe — keys loaded from Firestore `stripeConfig/public`.
/// Secret key: Firebase Functions secret `STRIPE_CH_SECRET_KEY` only.
enum StripeCHConfig {
    static let franchiseId = "CH"
    static let currency = "chf"

    private static var cachedPublishableKey: String?
    private static var cachedIsLiveMode: Bool = true

    static var publishableKey: String { cachedPublishableKey ?? "" }
    static var isLiveMode: Bool { cachedIsLiveMode }

    static func applyPublicConfig(publishableKey: String, mode: String) {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            cachedPublishableKey = key
        }
        cachedIsLiveMode = mode.lowercased() == "live"
    }
}
