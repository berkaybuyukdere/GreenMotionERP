import Foundation

struct GroqChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String
    let content: String
    var isUser: Bool { role == "user" }
}

enum GroqInsightsError: LocalizedError {
    case missingAPIKey
    case notAvailableInRegion
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key is not available."
        case .notAvailableInRegion:
            return "Jarvis is available for Switzerland franchise sessions only."
        case .invalidResponse:
            return "Could not parse Groq response."
        case .httpError(let code, let body):
            return "Groq API error (\(code)): \(body)"
        }
    }
}

/// Groq chat API for Switzerland admin Panel Jarvis (read-only analytics).
final class GroqInsightsService {
    static let shared = GroqInsightsService()

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let textModel = "llama-3.3-70b-versatile"

    private init() {}

    var hasAPIKey: Bool { resolvedAPIKey() != nil }

    static func isEnabledForSwitzerland(
        serviceFranchiseId: String,
        userProfile: UserProfile?,
        fallbackCountryCode: String
    ) -> Bool {
        FranchiseCapabilityMatrix.isSwitzerlandFranchiseContext(
            serviceFranchiseId: serviceFranchiseId,
            userProfile: userProfile,
            fallbackCountryCode: fallbackCountryCode
        )
    }

    private func resolvedAPIKey() -> String? {
        GroqSecureKeyProvider.apiKey()
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "tr": return "Turkish"
        case "de": return "German"
        default: return "English"
        }
    }

    private static let coreRules = """
    READ-ONLY analyst for Green Motion Switzerland. NEVER write/update/delete Firebase data.
    Use ONLY numbers in the JSON context. If missing, state clearly. No invented figures.
    Do NOT offer PDF/Excel/files unless the user explicitly asked for export in this message.
    Format: 4–7 tight bullets with metric + implication + action. Optional one-line headline.
    Optional machine block when tables help (omit if not needed):
    ```jarvis
    {"use_tables":["table_id"]}
    ```
    """

    /// Structured quick-action analysis (minimal tokens).
    func jarvisAnalyze(
        request: JarvisAnalysisRequest,
        contextJSON: String,
        tablesHint: [String]
    ) async throws -> String {
        let lang = languageName(request.languageCode)
        let domainLabel = request.domain.rawValue
        let periodLabel = request.period.rawValue
        let tableIds = tablesHint.joined(separator: ", ")

        let system = """
        \(Self.coreRules)
        Task: \(domainLabel) analysis for \(periodLabel) window.
        Language: \(lang).
        Available table ids: \(tableIds).
        """

        let userContent: String
        if request.domain == .systemHealth {
            userContent = "System health JSON:\n\(contextJSON)\nSummarize risks and remediation steps."
        } else {
            userContent = "Metrics JSON:\n\(contextJSON)\nDeliver operational insights for \(domainLabel)."
        }

        return try await complete(
            messages: [
                GroqChatMessage(role: "system", content: system),
                GroqChatMessage(role: "user", content: userContent)
            ],
            maxTokens: 720,
            temperature: 0.25
        )
    }

    /// Free-form question with compact overview context only.
    func jarvisFreeChat(
        userMessage: String,
        overviewJSON: String,
        history: [GroqChatMessage],
        languageCode: String
    ) async throws -> String {
        let lang = languageName(languageCode)
        let system = """
        \(Self.coreRules)
        Language: \(lang). User may ask cross-domain questions; stay within overview metrics or say which Panel area to open.
        """
        let learning = JarvisLearningStore.recentContextSummary()
        let enrichedUser = learning.isEmpty ? userMessage : "\(userMessage)\n\n[\(learning)]"

        var msgs = [
            GroqChatMessage(role: "system", content: system),
            GroqChatMessage(role: "user", content: "Overview JSON:\n\(overviewJSON)")
        ]
        msgs.append(contentsOf: history.suffix(6))
        msgs.append(GroqChatMessage(role: "user", content: enrichedUser))
        return try await complete(messages: msgs, maxTokens: 900, temperature: 0.3)
    }

    private func complete(messages: [GroqChatMessage], maxTokens: Int, temperature: Double = 0.35) async throws -> String {
        guard let apiKey = resolvedAPIKey() else { throw GroqInsightsError.missingAPIKey }
        let payload: [String: Any] = [
            "model": textModel,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        return try await postJSON(payload: payload, apiKey: apiKey)
    }

    private func postJSON(payload: [String: Any], apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqInsightsError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GroqInsightsError.httpError(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqInsightsError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
