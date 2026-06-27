import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FirebaseAuth

private struct ChatDisplayRow: Identifiable {
    enum Kind {
        case incoming(TeamChatMessage, showAvatar: Bool, showName: Bool, position: MessagesTheme.BubbleGroupPosition)
        case outgoing(TeamChatMessage, showName: Bool, position: MessagesTheme.BubbleGroupPosition)
        case dateSeparator(Date)
        case typingIndicator
    }

    let id: String
    let kind: Kind
}

struct TeamChatTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palantirModeEnabled) private var palantirMode
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @ObservedObject var store: AnnouncementStore
    var searchQuery: String = ""

    @State private var draft = ""
    @State private var attachments: [AnnouncementAttachment] = []
    @State private var showAttachmentBar = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var galleryItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var selectedVehicle: Arac?
    @State private var selectedHasar: HasarKaydi?
    @State private var selectedHasarAracId: UUID?
    @State private var selectedHasarPlaka: String?
    @State private var previewAttachment: AttachmentPreviewItem?
    @StateObject private var voiceRecorder = TeamChatVoiceRecorder()
    @State private var pendingDeleteMessage: TeamChatMessage?
    @State private var showDeleteAlert = false
    @State private var seenSheetReceipts: [TeamChatReadReceipt] = []
    @State private var showSeenSheet = false
    @State private var isSelectionMode = false
    @State private var selectedMessageIds: Set<String> = []
    @State private var showBulkDeleteAlert = false

    private var nav: FleetTokenNavigationHandler { FleetTokenNavigationHandler(viewModel: viewModel) }
    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: MessagesTheme.samePersonGap) {
                        if store.chatMessages.isEmpty && store.typingUserNames.isEmpty {
                            ContentUnavailableView(
                                "announcements.chat_empty.title".localized,
                                systemImage: "message.fill",
                                description: Text("announcements.chat_empty.subtitle".localized)
                            )
                            .padding(.top, 48)
                        } else {
                            ForEach(displayRows) { row in
                                rowView(row)
                                    .id(row.id)
                                    .padding(.top, rowTopPadding(for: row))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(palantirMode ? PalantirTheme.background : MessagesTheme.chatBackground(for: colorScheme))
                .onChange(of: store.mergedChatMessages().count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: store.typingUserNames.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            composerSection

            if isSelectionMode {
                selectionToolbar
            }
        }
        .onAppear {
            Task {
                guard let profile = authManager.userProfile,
                      let uid = Auth.auth().currentUser?.uid else { return }
                await store.touchLastOnline(userId: uid, userName: profile.displayName)
                await store.markIncomingMessagesSeen(currentUserId: uid, userName: profile.displayName)
            }
        }
        .alert("announcements.chat.delete_confirm".localized, isPresented: $showDeleteAlert) {
            Button("announcements.chat.delete_for_everyone".localized, role: .destructive) {
                guard let message = pendingDeleteMessage else { return }
                let id = message.id
                pendingDeleteMessage = nil
                Task {
                    try? await store.deleteChatMessage(id: id)
                    HapticManager.shared.light()
                }
            }
            Button("Cancel".localized, role: .cancel) {
                pendingDeleteMessage = nil
            }
        }
        .alert("announcements.chat.bulk_delete_confirm".localized, isPresented: $showBulkDeleteAlert) {
            Button("announcements.chat.delete_for_everyone".localized, role: .destructive) {
                let ids = Array(selectedMessageIds)
                selectedMessageIds.removeAll()
                isSelectionMode = false
                Task {
                    await store.deleteChatMessages(ids: ids)
                    HapticManager.shared.light()
                }
            }
            Button("Cancel".localized, role: .cancel) {}
        }
        .sheet(isPresented: $showSeenSheet) {
            TeamChatSeenBySheet(receipts: seenSheetReceipts)
        }
        .onChange(of: galleryItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importGallery(items) }
        }
        .onChange(of: draft) { _, newValue in
            guard let profile = authManager.userProfile,
                  let uid = Auth.auth().currentUser?.uid else { return }
            store.updateTypingIndicator(
                userId: uid,
                userName: profile.displayName,
                isTyping: !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
            CameraPicker(selectedImage: $capturedImage)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .data, .image, .audio], allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        .fullScreenCover(item: $previewAttachment) { item in
            AttachmentPreviewSheet(attachment: item.attachment)
        }
        .navigationDestination(item: $selectedVehicle) { arac in
            AracDetayView(arac: arac)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedHasar != nil && selectedHasarAracId != nil },
            set: { if !$0 { selectedHasar = nil; selectedHasarAracId = nil } }
        )) {
            if let hasar = selectedHasar, let aracId = selectedHasarAracId {
                HasarDetayView(hasar: hasar, aracId: aracId, aracPlaka: selectedHasarPlaka ?? "")
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = displayRows.last {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var displayRows: [ChatDisplayRow] {
        var rows: [ChatDisplayRow] = []
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let messages = store.mergedChatMessages().filter { message in
            guard !q.isEmpty else { return true }
            return message.body.lowercased().contains(q) ||
                message.createdByName.lowercased().contains(q) ||
                message.attachments.contains { $0.fileName.lowercased().contains(q) }
        }

        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            if let previous, !Calendar.current.isDate(message.createdAt, inSameDayAs: previous.createdAt) {
                rows.append(ChatDisplayRow(id: "date-\(message.id)", kind: .dateSeparator(message.createdAt)))
            }

            let outgoing = message.createdByUid == currentUid
            let groupedPrev = isGroupedWith(previous, message)
            let groupedNext = isGroupedWith(message, next)
            let position = bubblePosition(groupedWithPrevious: groupedPrev, groupedWithNext: groupedNext)

            if outgoing {
                rows.append(ChatDisplayRow(
                    id: message.id,
                    kind: .outgoing(message, showName: !groupedPrev, position: position)
                ))
            } else {
                rows.append(ChatDisplayRow(
                    id: message.id,
                    kind: .incoming(message, showAvatar: !groupedPrev, showName: !groupedPrev, position: position)
                ))
            }
        }

        if !store.typingUserNames.isEmpty {
            rows.append(ChatDisplayRow(id: "typing", kind: .typingIndicator))
        }
        return rows
    }

    private func isGroupedWith(_ a: TeamChatMessage?, _ b: TeamChatMessage?) -> Bool {
        guard let a, let b else { return false }
        guard a.createdByUid == b.createdByUid else { return false }
        return b.createdAt.timeIntervalSince(a.createdAt) < 300
    }

    private func bubblePosition(groupedWithPrevious: Bool, groupedWithNext: Bool) -> MessagesTheme.BubbleGroupPosition {
        switch (groupedWithPrevious, groupedWithNext) {
        case (false, false): return .single
        case (false, true): return .top
        case (true, true): return .middle
        case (true, false): return .bottom
        }
    }

    private func rowTopPadding(for row: ChatDisplayRow) -> CGFloat {
        switch row.kind {
        case .dateSeparator:
            return MessagesTheme.differentPersonGap
        case .incoming(_, _, let showName, _), .outgoing(_, let showName, _):
            return showName ? MessagesTheme.differentPersonGap : 0
        case .typingIndicator:
            return MessagesTheme.differentPersonGap
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatDisplayRow) -> some View {
        switch row.kind {
        case .dateSeparator(let date):
            dateSeparator(date)
        case .incoming(let message, let showAvatar, let showName, let position):
            incomingRow(message, showAvatar: showAvatar, showName: showName, position: position)
        case .outgoing(let message, let showName, let position):
            outgoingRow(message, showName: showName, position: position)
        case .typingIndicator:
            typingRow
        }
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ChatAvatarView(name: store.typingUserNames.first ?? "?", uid: "typing")
            VStack(alignment: .leading, spacing: 4) {
                if let name = store.typingUserNames.first {
                    Text(name)
                        .font(MessagesTheme.senderNameFont)
                        .foregroundStyle(MessagesTheme.iosGray)
                }
                TypingIndicatorView()
            }
            Spacer(minLength: 48)
        }
    }

    private func dateSeparator(_ date: Date) -> some View {
        Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(MessagesTheme.timestampFont.weight(.semibold))
            .foregroundStyle(MessagesTheme.dateChipText(for: colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(MessagesTheme.dateChipBackground(for: colorScheme))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func incomingRow(_ message: TeamChatMessage, showAvatar: Bool, showName: Bool, position: MessagesTheme.BubbleGroupPosition) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Group {
                if showAvatar {
                    ChatAvatarView(name: message.createdByName, uid: message.createdByUid)
                } else {
                    Color.clear.frame(width: MessagesTheme.avatarSize, height: MessagesTheme.avatarSize)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if showName {
                    Text(message.createdByName)
                        .font(MessagesTheme.senderNameFont)
                        .foregroundStyle(MessagesTheme.iosGray)
                        .padding(.leading, 2)
                }
                messageContent(message, outgoing: false, position: position)
            }

            Spacer(minLength: 48)
        }
        .contentShape(Rectangle())
        .contextMenu {
            messageContextMenu(message)
        }
    }

    private func outgoingRow(_ message: TeamChatMessage, showName: Bool, position: MessagesTheme.BubbleGroupPosition) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSelectionMode {
                selectionCheckmark(for: message.id)
            }

            Spacer(minLength: isSelectionMode ? 12 : 48)

            VStack(alignment: .trailing, spacing: 4) {
                if showName {
                    Text("announcements.chat.you".localized)
                        .font(MessagesTheme.senderNameFont)
                        .foregroundStyle(MessagesTheme.iosGray)
                        .padding(.trailing, 2)
                }
                messageContent(message, outgoing: true, position: position)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode, isOwnMessage(message) {
                toggleSelection(message.id)
            }
        }
        .contextMenu {
            messageContextMenu(message)
        }
    }

    private func isOwnMessage(_ message: TeamChatMessage) -> Bool {
        message.createdByUid == currentUid
    }

    @ViewBuilder
    private func selectionCheckmark(for id: String) -> some View {
        Image(systemName: selectedMessageIds.contains(id) ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selectedMessageIds.contains(id) ? MessagesTheme.iosBlue : MessagesTheme.mutedText(for: colorScheme))
    }

    private func toggleSelection(_ id: String) {
        if selectedMessageIds.contains(id) {
            selectedMessageIds.remove(id)
        } else {
            selectedMessageIds.insert(id)
        }
        HapticManager.shared.light()
    }

    @ViewBuilder
    private func messageContextMenu(_ message: TeamChatMessage) -> some View {
        if !message.body.isEmpty {
            Button {
                UIPasteboard.general.string = message.body
                HapticManager.shared.light()
            } label: {
                Label("announcements.chat.copy".localized, systemImage: "doc.on.doc")
            }
        }
        if isOwnMessage(message) {
            Button {
                isSelectionMode = true
                selectedMessageIds.insert(message.id)
            } label: {
                Label("announcements.chat.select".localized, systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                pendingDeleteMessage = message
                showDeleteAlert = true
            } label: {
                Label("announcements.chat.delete".localized, systemImage: "trash")
            }
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Button("Cancel".localized) {
                isSelectionMode = false
                selectedMessageIds.removeAll()
            }
            Spacer()
            Text("\(selectedMessageIds.count)")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("announcements.chat.delete".localized) {
                showBulkDeleteAlert = true
            }
            .disabled(selectedMessageIds.isEmpty)
            .foregroundStyle(selectedMessageIds.isEmpty ? MessagesTheme.mutedText(for: colorScheme) : .red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func messageContent(_ message: TeamChatMessage, outgoing: Bool, position: MessagesTheme.BubbleGroupPosition) -> some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
            if message.attachments.contains(where: { $0.isAudio }) {
                ForEach(message.attachments.filter(\.isAudio)) { att in
                    VoiceMessageBubble(attachment: att, outgoing: outgoing)
                        .clipShape(MessagesTheme.bubbleShape(outgoing: outgoing, position: position))
                }
            }

            if !message.body.isEmpty {
                FleetRichTextView(
                    text: message.body,
                    vehicles: viewModel.araclar,
                    style: outgoing ? .onOutgoingBubble : .onIncomingBubble,
                    onOpenPlate: openPlate,
                    onOpenRES: openRES
                )
                .messagesTextStyle()
                .padding(.horizontal, MessagesTheme.bubblePaddingH)
                .padding(.vertical, MessagesTheme.bubblePaddingV)
                .background(outgoing ? MessagesTheme.outgoingBubble : MessagesTheme.incomingBubble)
                .clipShape(MessagesTheme.bubbleShape(outgoing: outgoing, position: position))
                .frame(maxWidth: MessagesTheme.maxBubbleWidth, alignment: outgoing ? .trailing : .leading)
            }

            let nonAudio = message.attachments.filter { !$0.isAudio }
            if !nonAudio.isEmpty {
                ChatInlineAttachmentsView(
                    attachments: nonAudio,
                    outgoing: outgoing,
                    position: position,
                    onTap: { att in previewAttachment = AttachmentPreviewItem(attachment: att) }
                )
            }

            HStack(spacing: 4) {
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(MessagesTheme.timestampFont)
                    .foregroundStyle(MessagesTheme.mutedText(for: colorScheme))
                if outgoing {
                    deliveryIndicator(for: message)
                    seenLabel(for: message)
                }
            }
        }
        .onAppear {
            if !outgoing, let profile = authManager.userProfile,
               let uid = Auth.auth().currentUser?.uid {
                Task {
                    await store.markChatMessageSeen(
                        messageId: message.id,
                        userId: uid,
                        userName: profile.displayName
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func deliveryIndicator(for message: TeamChatMessage) -> some View {
        switch store.sendState(for: message.id) {
        case .sending:
            ProgressView()
                .scaleEffect(0.55)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .sent, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func seenLabel(for message: TeamChatMessage) -> some View {
        let seen = store.chatSeenBy(messageId: message.id, excludingUserId: currentUid)
        if seen.isEmpty {
            Image(systemName: store.sendState(for: message.id) == .sent || store.sendState(for: message.id) == nil ? "checkmark" : "clock")
                .font(.caption2)
                .foregroundStyle(MessagesTheme.mutedText(for: colorScheme))
        } else {
            Button {
                seenSheetReceipts = seen
                showSeenSheet = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text(seen.map(\.userName).prefix(2).joined(separator: ", "))
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(MessagesTheme.iosBlue)
            }
            .buttonStyle(.plain)
        }
    }

    private var composerSection: some View {
        VStack(spacing: 0) {
            if !isSelectionMode {
                composerBody
            }
        }
        .background {
            if palantirMode {
                PalantirTheme.surface
            } else {
                Color.clear.background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            Divider().background(palantirMode ? PalantirTheme.border : MessagesTheme.composerBorder(for: colorScheme))
        }
    }

    @ViewBuilder
    private var composerBody: some View {
        VStack(spacing: 0) {
            if voiceRecorder.isRecording {
                VoiceRecordingBar(recorder: voiceRecorder)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if showAttachmentBar {
                ComposerMediaPickerBar(
                    galleryItems: $galleryItems,
                    maxSelection: 4,
                    onCamera: { showCamera = true },
                    onFileImport: { showFileImporter = true }
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !attachments.isEmpty {
                AnnouncementAttachmentStrip(attachments: attachments, onRemove: { id in
                    attachments.removeAll { $0.id == id }
                }, onTap: { att in
                    previewAttachment = AttachmentPreviewItem(attachment: att)
                })
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            composerBar
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showAttachmentBar)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: voiceRecorder.isRecording)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                withAnimation { showAttachmentBar.toggle() }
                HapticManager.shared.light()
            } label: {
                Image(systemName: showAttachmentBar ? "xmark" : "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(showAttachmentBar ? MessagesTheme.mutedText(for: colorScheme) : MessagesTheme.iosBlue)
                    .frame(width: 34, height: 34)
                    .background {
                        if palantirMode {
                            PalantirTheme.surfaceHigh
                        } else {
                            Color.clear.background(.ultraThinMaterial)
                        }
                    }
                    .overlay(Rectangle().strokeBorder(palantirMode ? PalantirTheme.border : MessagesTheme.composerBorder(for: colorScheme), lineWidth: 1))
            }

            if !isSelectionMode {
                Button {
                    withAnimation {
                        isSelectionMode = true
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(MessagesTheme.mutedText(for: colorScheme))
                }
            }

            if voiceRecorder.isRecording {
                Button("announcements.chat.cancel_record".localized) {
                    voiceRecorder.cancel()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

                Button("announcements.chat.send_voice".localized) {
                    Task { await sendVoiceMessage() }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MessagesTheme.iosBlue)
            } else {
                FleetTokenComposerField(
                    text: $draft,
                    vehicles: viewModel.araclar,
                    placeholder: "announcements.chat_placeholder".localized
                )
                .messagesComposerFieldStyle()

                Button {
                    Task {
                        if draft.isEmpty && attachments.isEmpty {
                            try? voiceRecorder.start()
                            HapticManager.shared.medium()
                        } else {
                            await send()
                        }
                    }
                } label: {
                    Image(systemName: canSend ? "arrow.up.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, canSend || voiceRecorder.isRecording ? MessagesTheme.iosBlue : MessagesTheme.iosGray.opacity(0.5))
                }
                .disabled(voiceRecorder.isRecording && !canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private func send() async {
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid else { return }
        let body = draft
        let pending = attachments
        draft = ""
        attachments = []
        showAttachmentBar = false
        store.enqueueChatMessage(
            body: body,
            attachments: pending,
            senderUid: uid,
            senderName: profile.displayName
        )
        HapticManager.shared.light()
    }

    private func sendVoiceMessage() async {
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid,
              let url = voiceRecorder.stop() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let att = store.makeLocalVoiceAttachment(from: url) else {
            errorMessageFallback()
            return
        }
        store.enqueueChatMessage(
            body: "",
            attachments: [att],
            senderUid: uid,
            senderName: profile.displayName
        )
    }

    private func errorMessageFallback() {
        HapticManager.shared.error()
    }

    private func handleCameraDismiss() {
        guard let capturedImage else { return }
        self.capturedImage = nil
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid,
              let att = store.makeLocalPhotoAttachment(capturedImage) else { return }
        store.enqueueChatMessage(
            body: "",
            attachments: [att],
            senderUid: uid,
            senderName: profile.displayName
        )
    }

    private func importGallery(_ items: [PhotosPickerItem]) async {
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid else { return }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let att = store.makeLocalPhotoAttachment(image) else { continue }
            store.enqueueChatMessage(
                body: "",
                attachments: [att],
                senderUid: uid,
                senderName: profile.displayName
            )
        }
        galleryItems = []
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid else { return }
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let att = store.makeLocalFileAttachment(data: data, fileName: url.lastPathComponent, mimeType: mime)
            store.enqueueChatMessage(
                body: "",
                attachments: [att],
                senderUid: uid,
                senderName: profile.displayName
            )
        }
    }

    private func openPlate(_ normalized: String) {
        if let arac = nav.vehicle(forPlate: normalized) {
            selectedVehicle = arac
        }
    }

    private func openRES(_ code: String) {
        if let match = nav.damageMatch(forRES: code) {
            selectedHasar = match.hasar
            selectedHasarAracId = match.arac.id
            selectedHasarPlaka = match.arac.plakaFormatli
        }
    }
}
