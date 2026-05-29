import SwiftUI

/// Fixed-height Jarvis chat strip for the CH admin panel (replaces launcher button).
struct CHPanelEmbeddedJarvisChat: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let fleetContext: JarvisFleetDataContext
    let languageCode: String
    let jarvisEnabled: Bool
    var onExpand: (() -> Void)?

    @State private var rows: [JarvisChatRow] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chatArea
            inputBar
        }
        .palantirCard()
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(PalantirTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("JARVIS")
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.accent)
                    .tracking(1.1)
                if horizontalSizeClass == .compact {
                    Text("jarvis.launcher.subtitle".localized)
                        .font(PalantirTheme.bodyFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if rows.isEmpty {
                        Text("jarvis.launcher.body".localized)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(horizontalSizeClass == .compact ? 6 : 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                    }
                    ForEach(rows) { row in
                        Text(row.text)
                            .font(PalantirTheme.bodyFont(11))
                            .foregroundStyle(PalantirTheme.textPrimary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: row.isUser ? .trailing : .leading)
                            .background(row.isUser ? PalantirTheme.surfaceHigh : PalantirTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.border))
                            .id(row.id)
                    }
                    if isSending {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75).tint(PalantirTheme.accent)
                            Text("ch_panel.jarvis_thinking".localized)
                                .font(PalantirTheme.dataFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                        .id("thinking")
                    }
                }
            }
            .onChange(of: rows.count) { _, _ in
                if let last = rows.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let errorText {
                Text(errorText)
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.critical)
                    .lineLimit(2)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("ch_panel.jarvis_placeholder".localized, text: $input, axis: .vertical)
                    .lineLimit(1...3)
                    .font(PalantirTheme.bodyFont(12))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .frame(minHeight: 36)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.border))
                Button(action: sendFreeform) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(PalantirTheme.accent)
                }
                .disabled(
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSending
                        || !jarvisEnabled
                        || !GroqInsightsService.shared.hasAPIKey
                )
            }
        }
        .padding(.top, 8)
    }

    private func sendFreeform() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, jarvisEnabled, GroqInsightsService.shared.hasAPIKey else { return }
        input = ""
        errorText = nil
        rows.append(JarvisChatRow(isUser: true, text: text, tables: []))
        isSending = true
        let history = rows.dropLast().map { GroqChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }

        Task {
            do {
                let raw = try await GroqInsightsService.shared.jarvisFreeChat(
                    userMessage: text,
                    overviewJSON: fleetContext.overviewJSON(),
                    history: Array(history),
                    languageCode: languageCode
                )
                let parsed = JarvisResponseParser.parse(raw)
                await MainActor.run {
                    rows.append(JarvisChatRow(isUser: false, text: parsed.text, tables: []))
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}
