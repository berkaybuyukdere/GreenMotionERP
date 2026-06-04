import SwiftUI
import Charts
import Kingfisher

// MARK: - Inline chat attachments (photos + files in bubble)

struct ChatInlineAttachmentsView: View {
    let attachments: [AnnouncementAttachment]
    let outgoing: Bool
    let position: MessagesTheme.BubbleGroupPosition
    var onTap: (AnnouncementAttachment) -> Void

    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
            let photos = attachments.filter(\.isPhoto)
            let files = attachments.filter { !$0.isPhoto && !$0.isAudio }

            if !photos.isEmpty {
                if photos.count == 1, let photo = photos.first {
                    photoBubble(photo)
                } else {
                    HStack(spacing: 4) {
                        ForEach(photos.prefix(4)) { photo in
                            photoBubble(photo, compact: true)
                        }
                    }
                }
            }

            ForEach(files) { file in
                fileBubble(file)
            }
        }
    }

    private func photoBubble(_ item: AnnouncementAttachment, compact: Bool = false) -> some View {
        Button { onTap(item) } label: {
            Group {
                if let url = URL(string: item.downloadURL), !item.downloadURL.isEmpty {
                    KFImage(url)
                        .placeholder { Color.gray.opacity(0.2) }
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: compact ? 88 : min(220, MessagesTheme.maxBubbleWidth), height: compact ? 88 : 160)
            .clipShape(MessagesTheme.bubbleShape(outgoing: outgoing, position: position))
        }
        .buttonStyle(.plain)
    }

    private func fileBubble(_ item: AnnouncementAttachment) -> some View {
        Button { onTap(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(outgoing ? .white : .white)
                Text(item.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(outgoing ? .white : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, MessagesTheme.bubblePaddingH)
            .padding(.vertical, 10)
            .frame(maxWidth: MessagesTheme.maxBubbleWidth, alignment: .leading)
            .background(outgoing ? MessagesTheme.outgoingBubble : MessagesTheme.incomingBubble)
            .clipShape(MessagesTheme.bubbleShape(outgoing: outgoing, position: position))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Media gallery

struct TeamChatMediaGalleryView: View {
    @ObservedObject var store: AnnouncementStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: AttachmentPreviewItem?
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(store.allChatMediaAttachments(), id: \.attachment.id) { pair in
                        Button {
                            preview = AttachmentPreviewItem(attachment: pair.attachment)
                        } label: {
                            mediaCell(pair.attachment)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .navigationTitle("announcements.chat.media".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
            .overlay {
                if store.allChatMediaAttachments().isEmpty {
                    ContentUnavailableView(
                        "announcements.chat.media_empty".localized,
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
            }
            .fullScreenCover(item: $preview) { item in
                AttachmentPreviewSheet(attachment: item.attachment)
            }
        }
    }

    @ViewBuilder
    private func mediaCell(_ item: AnnouncementAttachment) -> some View {
        if item.isPhoto, let url = URL(string: item.downloadURL), !item.downloadURL.isEmpty {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 100, minHeight: 100)
                .clipped()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(MessagesTheme.iosBlue)
                Text(item.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 100, minHeight: 100)
            .background(MessagesTheme.iosGray6)
        }
    }
}

// MARK: - Search

struct TeamChatSearchSheet: View {
    @ObservedObject var store: AnnouncementStore
    @Binding var query: String
    @Environment(\.dismiss) private var dismiss

    private var results: [TeamChatMessage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return store.chatMessages.filter {
            $0.body.lowercased().contains(q) ||
            $0.createdByName.lowercased().contains(q) ||
            $0.attachments.contains { $0.fileName.lowercased().contains(q) }
        }
        .reversed()
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Text("announcements.chat.search_hint".localized)
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("announcements.chat.search_empty".localized)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.createdByName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MessagesTheme.iosBlue)
                            Text(message.body.isEmpty ? message.attachments.first?.fileName ?? "—" : message.body)
                                .font(.subheadline)
                                .lineLimit(3)
                            Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $query, prompt: "announcements.chat.search".localized)
            .navigationTitle("announcements.chat.search".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Members + last online

struct TeamChatMembersSheet: View {
    @ObservedObject var store: AnnouncementStore
    @Environment(\.dismiss) private var dismiss

    private var members: [TeamChatPresence] {
        if store.chatPresence.isEmpty {
            return uniqueMembersFromMessages
        }
        return store.chatPresence
    }

    private var uniqueMembersFromMessages: [TeamChatPresence] {
        var map: [String: TeamChatPresence] = [:]
        for msg in store.chatMessages {
            if map[msg.createdByUid] == nil {
                map[msg.createdByUid] = TeamChatPresence(
                    userId: msg.createdByUid,
                    userName: msg.createdByName,
                    lastOnlineAt: msg.createdAt,
                    franchiseId: msg.franchiseId
                )
            }
        }
        return map.values.sorted { $0.userName.localizedCaseInsensitiveCompare($1.userName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(members) { member in
                HStack(spacing: 12) {
                    ChatAvatarView(name: member.userName, uid: member.userId)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.userName)
                            .font(.body.weight(.semibold))
                        Text(member.lastOnlineLabel)
                            .font(.caption)
                            .foregroundStyle(member.isOnline ? .green : .secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(member.isOnline ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("announcements.chat.members".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

extension TeamChatPresence {
    init(userId: String, userName: String, lastOnlineAt: Date, franchiseId: String) {
        self.userId = userId
        self.userName = userName
        self.lastOnlineAt = lastOnlineAt
        self.franchiseId = franchiseId
    }
}

// MARK: - Seen by sheet

struct TeamChatSeenBySheet: View {
    let receipts: [TeamChatReadReceipt]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(receipts) { receipt in
                HStack {
                    ChatAvatarView(name: receipt.userName, uid: receipt.userId)
                    VStack(alignment: .leading) {
                        Text(receipt.userName)
                            .font(.body.weight(.medium))
                        Text(receipt.readAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("announcements.chat.seen_by".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}

// MARK: - AI assistant

struct TeamChatAISheet: View {
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var rows: [GroqChatMessage] = []
    @State private var isSending = false
    @State private var errorText: String?

    private var fleetContext: JarvisFleetDataContext {
        JarvisFleetDataContext.build(viewModel: viewModel)
    }

    private var quickCommands: [(String, String)] {
        [
            ("announcements.chat.ai.damage".localized, "damage reports today"),
            ("announcements.chat.ai.checkout".localized, "check out reports today"),
            ("announcements.chat.ai.return".localized, "return reports today"),
            ("announcements.chat.ai.office".localized, "office ops today"),
            ("announcements.chat.ai.shuttle".localized, "shuttle today"),
            ("announcements.chat.ai.overview".localized, "fleet overview today")
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            quickCommandChips
                            ForEach(rows) { row in
                                aiBubble(row)
                                    .id(row.id)
                            }
                            if isSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("announcements.chat.ai.thinking".localized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: rows.count) { _, _ in
                        if let last = rows.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                HStack(spacing: 8) {
                    TextField("announcements.chat.ai.placeholder".localized, text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await send(input) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .gray : MessagesTheme.iosBlue)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("announcements.chat.ai.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }

    private var quickCommandChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickCommands, id: \.0) { label, command in
                    Button(label) {
                        Task { await send(command) }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MessagesTheme.iosBlue.opacity(0.12))
                    .foregroundStyle(MessagesTheme.iosBlue)
                    .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func aiBubble(_ row: GroqChatMessage) -> some View {
        VStack(alignment: row.isUser ? .trailing : .leading, spacing: 6) {
            if row.isUser {
                Text(row.content)
                    .font(.subheadline)
                    .padding(12)
                    .background(MessagesTheme.outgoingBubble)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                TeamChatAIResponseView(text: row.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        errorText = nil
        isSending = true
        input = ""
        rows.append(GroqChatMessage(role: "user", content: trimmed))
        defer { isSending = false }

        guard GroqInsightsService.shared.hasAPIKey else {
            errorText = GroqInsightsError.missingAPIKey.localizedDescription
            return
        }

        do {
            let lang = LocalizationManager.shared.currentLanguage.rawValue
            let reply = try await GroqInsightsService.shared.teamChatAssistant(
                userMessage: trimmed,
                todayJSON: fleetContext.todayBriefJSON(),
                overviewJSON: fleetContext.overviewJSON(),
                history: rows,
                languageCode: lang
            )
            rows.append(GroqChatMessage(role: "assistant", content: reply))
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct TeamChatAIResponseView: View {
    let text: String

    private var prose: String {
        if let range = text.range(of: "```teamchart") {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private var chartPayload: TeamChatChartPayload? {
        guard let start = text.range(of: "```teamchart"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex) else { return nil }
        let json = text[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TeamChatChartPayload.self, from: data) else { return nil }
        return payload
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prose)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let chart = chartPayload, !chart.labels.isEmpty {
                TeamChatMiniChart(payload: chart)
                    .frame(height: 160)
            }
        }
        .padding(12)
        .background(MessagesTheme.incomingBubble)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TeamChatChartPayload: Decodable {
    let type: String
    let title: String
    let labels: [String]
    let values: [Double]
}

struct TeamChatMiniChart: View {
    let payload: TeamChatChartPayload

    private var points: [(String, Double)] {
        zip(payload.labels, payload.values).map { ($0, $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Chart(points, id: \.0) { label, value in
                if payload.type == "line" {
                    LineMark(x: .value("L", label), y: .value("V", value))
                        .foregroundStyle(MessagesTheme.iosBlue)
                } else if payload.type == "pie" {
                    SectorMark(angle: .value("V", value), innerRadius: .ratio(0.5))
                        .foregroundStyle(by: .value("L", label))
                } else {
                    BarMark(x: .value("L", label), y: .value("V", value))
                        .foregroundStyle(MessagesTheme.iosBlue.gradient)
                }
            }
            .chartLegend(payload.type == "pie" ? .visible : .hidden)
        }
    }
}
