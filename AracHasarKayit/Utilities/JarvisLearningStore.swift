import Foundation
import SwiftUI

/// Lightweight on-device signals for Jarvis context (no network until user opens Jarvis).
enum JarvisLearningStore {
    private static let key = "jarvis.learning.events"
    private static let maxEvents = 120

    static func record(screen: String, action: String? = nil) {
        var events = load()
        let entry: [String: String] = [
            "screen": screen,
            "action": action ?? "",
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        events.append(entry)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        if let data = try? JSONSerialization.data(withJSONObject: events),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: key)
        }
    }

    /// Compact summary appended to Jarvis prompts (token-efficient).
    static func recentContextSummary(maxLines: Int = 12) -> String {
        let events = load().suffix(maxLines)
        guard !events.isEmpty else { return "" }
        let lines = events.map { e -> String in
            let screen = e["screen"] ?? "?"
            let action = e["action"] ?? ""
            if action.isEmpty { return screen }
            return "\(screen):\(action)"
        }
        return "Recent user navigation: " + lines.joined(separator: " → ")
    }

    private static func load() -> [[String: String]] {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        return arr
    }
}

/// Non-blocking screen beacon — zero layout impact.
struct JarvisLearningBeacon: View {
    let screen: String
    var action: String?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                JarvisLearningStore.record(screen: screen, action: action)
            }
    }
}
