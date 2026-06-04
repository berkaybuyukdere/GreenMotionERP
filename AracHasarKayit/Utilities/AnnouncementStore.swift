import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

enum ChatSendState: Equatable {
    case sending
    case sent
    case failed
}

@MainActor
final class AnnouncementStore: ObservableObject {
    static let shared = AnnouncementStore()

    @Published private(set) var announcements: [FranchiseAnnouncement] = []
    @Published private(set) var chatMessages: [TeamChatMessage] = []
    @Published private(set) var optimisticMessages: [TeamChatMessage] = []
    @Published private(set) var sendStates: [String: ChatSendState] = [:]
    @Published private(set) var chatReadReceipts: [TeamChatReadReceipt] = []
    @Published private(set) var chatPresence: [TeamChatPresence] = []
    @Published private(set) var readReceipts: [AnnouncementReadReceipt] = []
    @Published private(set) var reactions: [AnnouncementReaction] = []
    @Published private(set) var typingUserNames: [String] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var announcementListener: ListenerRegistration?
    private var chatListener: ListenerRegistration?
    private var chatReadsListener: ListenerRegistration?
    private var chatPresenceListener: ListenerRegistration?
    private var readsListener: ListenerRegistration?
    private var reactionsListener: ListenerRegistration?
    private var typingListener: ListenerRegistration?
    private var lastKnownMessageCount = 0
    private var typingDebounceTask: Task<Void, Never>?
    private var listeningClientCount = 0
    private var activeFranchiseId: String = ""
    private var franchiseContextObserver: NSObjectProtocol?

    private init() {
        activeFranchiseId = FirebaseService.shared.currentFranchiseId
        franchiseContextObserver = NotificationCenter.default.addObserver(
            forName: .franchiseContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleFranchiseContextDidChange()
            }
        }
    }

    deinit {
        if let franchiseContextObserver {
            NotificationCenter.default.removeObserver(franchiseContextObserver)
        }
        announcementListener?.remove()
        chatListener?.remove()
        chatReadsListener?.remove()
        chatPresenceListener?.remove()
        readsListener?.remove()
        reactionsListener?.remove()
        typingListener?.remove()
    }

    private func matchesActiveFranchise(_ franchiseId: String) -> Bool {
        let docFranchise = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let active = activeFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return docFranchise.isEmpty || docFranchise == active
    }

    private func handleFranchiseContextDidChange() {
        let next = FirebaseService.shared.currentFranchiseId
        guard next != activeFranchiseId else { return }
        activeFranchiseId = next
        clearFranchiseScopedLocalState()
        guard listeningClientCount > 0 else { return }
        attachFirestoreListeners()
    }

    private func clearFranchiseScopedLocalState() {
        announcements = []
        chatMessages = []
        optimisticMessages = []
        sendStates = [:]
        chatReadReceipts = []
        chatPresence = []
        readReceipts = []
        reactions = []
        typingUserNames = []
        lastKnownMessageCount = 0
        errorMessage = nil
    }

    func startListening() {
        guard Auth.auth().currentUser != nil else { return }
        listeningClientCount += 1
        activeFranchiseId = FirebaseService.shared.currentFranchiseId
        guard listeningClientCount == 1 else { return }
        isLoading = true
        attachFirestoreListeners()
    }

    private func attachFirestoreListeners() {
        activeFranchiseId = FirebaseService.shared.currentFranchiseId
        removeFirestoreListeners()

        announcementListener = FirebaseService.shared
            .getFilteredQuery("announcements")
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.announcements = (snapshot?.documents ?? [])
                        .compactMap { FranchiseAnnouncement(document: $0) }
                        .filter {
                            self.matchesActiveFranchise($0.franchiseId) &&
                            ($0.status == .published || $0.status == .scheduled)
                        }
                    await self.publishDueScheduledAnnouncementsIfNeeded()
                }
            }

        chatListener = FirebaseService.shared
            .getFilteredQuery("teamChatMessages")
            .order(by: "createdAt", descending: false)
            .limit(to: 300)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let messages = (snapshot?.documents ?? [])
                        .compactMap { TeamChatMessage(document: $0) }
                        .filter { self.matchesActiveFranchise($0.franchiseId) }
                    let previousCount = self.lastKnownMessageCount
                    if previousCount > 0,
                       messages.count > previousCount,
                       let last = messages.last,
                       last.createdByUid != Auth.auth().currentUser?.uid {
                        ChatSoundPlayer.playReceived()
                    }
                    self.lastKnownMessageCount = messages.count
                    self.chatMessages = messages
                    self.reconcileOptimisticMessages()
                }
            }

        chatReadsListener = FirebaseService.shared
            .getFilteredQuery("teamChatReads")
            .limit(to: 1500)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.chatReadReceipts = (snapshot?.documents ?? [])
                        .compactMap { TeamChatReadReceipt(document: $0) }
                        .filter { self.matchesActiveFranchise($0.franchiseId) }
                }
            }

        chatPresenceListener = FirebaseService.shared
            .getFilteredQuery("teamChatPresence")
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.chatPresence = (snapshot?.documents ?? [])
                        .compactMap { TeamChatPresence(document: $0) }
                        .filter { self.matchesActiveFranchise($0.franchiseId) }
                        .sorted { $0.userName.localizedCaseInsensitiveCompare($1.userName) == .orderedAscending }
                }
            }

        readsListener = FirebaseService.shared
            .getFilteredQuery("announcementReads")
            .limit(to: 500)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.readReceipts = (snapshot?.documents ?? [])
                        .compactMap { AnnouncementReadReceipt(document: $0) }
                        .filter { self.matchesActiveFranchise($0.franchiseId) }
                }
            }

        reactionsListener = FirebaseService.shared
            .getFilteredQuery("announcementReactions")
            .limit(to: 500)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.reactions = (snapshot?.documents ?? [])
                        .compactMap { AnnouncementReaction(document: $0) }
                        .filter { self.matchesActiveFranchise($0.franchiseId) }
                }
            }

        typingListener = FirebaseService.shared
            .getFilteredQuery("teamChatTyping")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let uid = Auth.auth().currentUser?.uid ?? ""
                    let cutoff = Date().addingTimeInterval(-6)
                    let names = (snapshot?.documents ?? []).compactMap { doc -> String? in
                        let data = doc.data()
                        guard doc.documentID != uid else { return nil }
                        let updated: Date
                        if let ts = data["updatedAt"] as? Timestamp {
                            updated = ts.dateValue()
                        } else {
                            updated = .distantPast
                        }
                        guard updated >= cutoff else { return nil }
                        return data["userName"] as? String
                    }
                    self.typingUserNames = Array(Set(names)).sorted()
                }
            }
    }

    func stopListening() {
        listeningClientCount = max(0, listeningClientCount - 1)
        guard listeningClientCount == 0 else { return }
        removeFirestoreListeners()
        clearFranchiseScopedLocalState()
        clearTypingIndicator()
    }

    private func removeFirestoreListeners() {
        announcementListener?.remove()
        chatListener?.remove()
        chatReadsListener?.remove()
        chatPresenceListener?.remove()
        readsListener?.remove()
        reactionsListener?.remove()
        typingListener?.remove()
        announcementListener = nil
        chatListener = nil
        chatReadsListener = nil
        chatPresenceListener = nil
        readsListener = nil
        reactionsListener = nil
        typingListener = nil
    }

    func mergedChatMessages() -> [TeamChatMessage] {
        let serverIds = Set(chatMessages.map(\.id))
        let pending = optimisticMessages.filter { !serverIds.contains($0.id) }
        return (chatMessages + pending).sorted { $0.createdAt < $1.createdAt }
    }

    func sendState(for messageId: String) -> ChatSendState? {
        sendStates[messageId]
    }

    private func reconcileOptimisticMessages() {
        let serverIds = Set(chatMessages.map(\.id))
        optimisticMessages.removeAll { serverIds.contains($0.id) }
        for id in serverIds where sendStates[id] == .sending {
            sendStates[id] = .sent
        }
    }

    func publishedAnnouncements() -> [FranchiseAnnouncement] {
        let published = announcements.filter { $0.status == .published }
        return published.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            if lhs.pinned && rhs.pinned {
                let l = lhs.pinnedAt ?? lhs.publishedAt ?? lhs.createdAt
                let r = rhs.pinnedAt ?? rhs.publishedAt ?? rhs.createdAt
                return l > r
            }
            let l = lhs.publishedAt ?? lhs.createdAt
            let r = rhs.publishedAt ?? rhs.createdAt
            return l > r
        }
    }

    func unreadCount(for userId: String) -> Int {
        guard !userId.isEmpty else { return 0 }
        return publishedAnnouncements().filter { item in
            !isRead(announcementId: item.id, userId: userId)
        }.count
    }

    func isRead(announcementId: String, userId: String) -> Bool {
        readReceipts.contains { $0.announcementId == announcementId && $0.userId == userId }
    }

    func readReceipts(for announcementId: String) -> [AnnouncementReadReceipt] {
        readReceipts
            .filter { $0.announcementId == announcementId }
            .sorted { $0.readAt > $1.readAt }
    }

    func reactions(for announcementId: String) -> [AnnouncementReaction] {
        reactions.filter { $0.announcementId == announcementId }
    }

    func reactionSummary(for announcementId: String) -> [(emoji: String, count: Int)] {
        let grouped = Dictionary(grouping: reactions(for: announcementId), by: \.emoji)
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    func markRead(announcementId: String, userId: String, userName: String) async {
        guard !isRead(announcementId: announcementId, userId: userId) else { return }
        let docId = "\(announcementId)_\(userId)"
        let payload: [String: Any] = [
            "announcementId": announcementId,
            "userId": userId,
            "userName": userName,
            "readAt": Timestamp(date: Date()),
            "franchiseId": FirebaseService.shared.currentFranchiseId
        ]
        do {
            try await FirebaseService.shared
                .getCollectionReference("announcementReads")
                .document(docId)
                .setData(payload, merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPinned(announcementId: String, pinned: Bool) async throws {
        var updates: [String: Any] = [
            "pinned": pinned,
            "updatedAt": Timestamp(date: Date())
        ]
        if pinned {
            updates["pinnedAt"] = Timestamp(date: Date())
        } else {
            updates["pinnedAt"] = NSNull()
        }
        try await FirebaseService.shared
            .getCollectionReference("announcements")
            .document(announcementId)
            .updateData(updates)
    }

    func toggleReaction(announcementId: String, emoji: String, userId: String, userName: String) async {
        let docId = "\(announcementId)_\(userId)_\(emoji)"
        let ref = FirebaseService.shared.getCollectionReference("announcementReactions").document(docId)
        if reactions.contains(where: { $0.id == docId }) {
            try? await ref.delete()
            return
        }
        let payload: [String: Any] = [
            "announcementId": announcementId,
            "userId": userId,
            "userName": userName,
            "emoji": emoji,
            "createdAt": Timestamp(date: Date()),
            "franchiseId": FirebaseService.shared.currentFranchiseId
        ]
        try? await ref.setData(payload)
    }

    func publishAnnouncement(
        title: String,
        icon: String,
        iconColorKey: String,
        body: String,
        attachments: [AnnouncementAttachment],
        scheduledAt: Date?,
        publisherUid: String,
        publisherName: String,
        editingId: String? = nil
    ) async throws {
        let franchiseId = FirebaseService.shared.currentFranchiseId
        let now = Date()
        let isScheduled = scheduledAt.map { $0 > now.addingTimeInterval(30) } ?? false
        let status = isScheduled ? AnnouncementStatus.scheduled.rawValue : AnnouncementStatus.published.rawValue
        let docId = editingId ?? UUID().uuidString

        var payload: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "icon": icon,
            "iconColorKey": iconColorKey,
            "body": body.trimmingCharacters(in: .whitespacesAndNewlines),
            "attachments": attachments.map(\.firestorePayload),
            "createdByUid": publisherUid,
            "createdByName": publisherName,
            "updatedAt": Timestamp(date: now),
            "status": status,
            "franchiseId": franchiseId
        ]

        if editingId == nil {
            payload["createdAt"] = Timestamp(date: now)
            payload["pinned"] = false
        }
        if isScheduled, let scheduledAt {
            payload["scheduledAt"] = Timestamp(date: scheduledAt)
            payload["publishedAt"] = NSNull()
        } else {
            payload["publishedAt"] = Timestamp(date: now)
            payload["scheduledAt"] = NSNull()
        }

        try await FirebaseService.shared
            .getCollectionReference("announcements")
            .document(docId)
            .setData(payload, merge: true)

        if !isScheduled {
            NotificationManager.shared.sendAnnouncementNotification(
                title: title,
                publisherName: publisherName,
                announcementId: docId
            )
        }
    }

    func deleteAnnouncement(id: String) async throws {
        try await FirebaseService.shared
            .getCollectionReference("announcements")
            .document(id)
            .delete()
    }

    func sendChatMessage(
        body: String,
        attachments: [AnnouncementAttachment],
        senderUid: String,
        senderName: String
    ) async throws {
        let id = enqueueChatMessage(
            body: body,
            attachments: attachments,
            senderUid: senderUid,
            senderName: senderName
        )
        try await flushChatMessage(id: id)
    }

    @discardableResult
    func enqueueChatMessage(
        body: String,
        attachments: [AnnouncementAttachment],
        senderUid: String,
        senderName: String,
        messageId: String = UUID().uuidString
    ) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return messageId }

        let franchiseId = FirebaseService.shared.currentFranchiseId
        let optimistic = TeamChatMessage(
            id: messageId,
            body: trimmed,
            attachments: attachments,
            createdByUid: senderUid,
            createdByName: senderName,
            createdAt: Date(),
            franchiseId: franchiseId
        )
        optimisticMessages.append(optimistic)
        sendStates[messageId] = .sending
        clearTypingIndicator()
        ChatSoundPlayer.playSent()

        Task { await flushChatMessage(id: messageId) }
        return messageId
    }

    func flushChatMessage(id: String) async {
        guard let optimistic = optimisticMessages.first(where: { $0.id == id })
            ?? chatMessages.first(where: { $0.id == id }) else { return }
        do {
            var uploaded = optimistic.attachments
            for index in uploaded.indices {
                let att = uploaded[index]
                guard let localURL = localAttachmentURL(att) else { continue }
                if att.isPhoto, let image = UIImage(contentsOfFile: localURL.path) {
                    uploaded[index] = try await uploadPhoto(image, folder: "teamChat")
                } else if att.isAudio, let data = try? Data(contentsOf: localURL) {
                    uploaded[index] = try await uploadAttachment(
                        data: data,
                        fileName: att.fileName,
                        mimeType: att.mimeType,
                        kind: "audio",
                        folder: "teamChat"
                    )
                } else if let data = try? Data(contentsOf: localURL) {
                    uploaded[index] = try await uploadAttachment(
                        data: data,
                        fileName: att.fileName,
                        mimeType: att.mimeType,
                        kind: att.kind,
                        folder: "teamChat"
                    )
                }
            }

            let payload: [String: Any] = [
                "body": optimistic.body,
                "attachments": uploaded.map(\.firestorePayload),
                "createdByUid": optimistic.createdByUid,
                "createdByName": optimistic.createdByName,
                "createdAt": Timestamp(date: optimistic.createdAt),
                "franchiseId": optimistic.franchiseId
            ]
            try await FirebaseService.shared
                .getCollectionReference("teamChatMessages")
                .document(id)
                .setData(payload)

            sendStates[id] = .sent
            reconcileOptimisticMessages()

            NotificationManager.shared.sendTeamChatNotification(
                senderName: optimistic.createdByName,
                preview: optimistic.body.isEmpty ? "announcements.chat.voice_preview".localized : optimistic.body,
                messageId: id
            )
        } catch {
            sendStates[id] = .failed
            errorMessage = error.localizedDescription
        }
    }

    func makeLocalPhotoAttachment(_ image: UIImage) -> AnnouncementAttachment? {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let fileName = "\(UUID().uuidString).jpg"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(fileName)")
        try? data.write(to: path, options: .atomic)
        return AnnouncementAttachment(
            kind: "photo",
            storagePath: "",
            downloadURL: path.absoluteString,
            fileName: fileName,
            mimeType: "image/jpeg",
            fileSize: Int64(data.count)
        )
    }

    func makeLocalFileAttachment(data: Data, fileName: String, mimeType: String) -> AnnouncementAttachment {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)-\(fileName)")
        try? data.write(to: path, options: .atomic)
        return AnnouncementAttachment(
            kind: mimeType.hasPrefix("image/") ? "photo" : "file",
            storagePath: "",
            downloadURL: path.absoluteString,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(data.count)
        )
    }

    func makeLocalVoiceAttachment(from localURL: URL) -> AnnouncementAttachment? {
        guard let data = try? Data(contentsOf: localURL) else { return nil }
        let fileName = localURL.lastPathComponent
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("chat-voice-\(UUID().uuidString).m4a")
        try? FileManager.default.copyItem(at: localURL, to: dest)
        return AnnouncementAttachment(
            kind: "audio",
            storagePath: "",
            downloadURL: dest.absoluteString,
            fileName: fileName,
            mimeType: "audio/m4a",
            fileSize: Int64(data.count)
        )
    }

    private func localAttachmentURL(_ attachment: AnnouncementAttachment) -> URL? {
        if attachment.downloadURL.hasPrefix("file://"), let url = URL(string: attachment.downloadURL) {
            return url
        }
        if attachment.storagePath.isEmpty, !attachment.downloadURL.isEmpty {
            return URL(fileURLWithPath: attachment.downloadURL)
        }
        return nil
    }

    func deleteChatMessage(id: String) async throws {
        try await FirebaseService.shared
            .getCollectionReference("teamChatMessages")
            .document(id)
            .delete()
        optimisticMessages.removeAll { $0.id == id }
        sendStates.removeValue(forKey: id)
    }

    func deleteChatMessages(ids: [String]) async {
        for id in ids {
            try? await deleteChatMessage(id: id)
        }
    }

    func chatSeenBy(messageId: String, excludingUserId: String? = nil) -> [TeamChatReadReceipt] {
        chatReadReceipts
            .filter { $0.messageId == messageId && $0.userId != excludingUserId }
            .sorted { $0.readAt > $1.readAt }
    }

    func hasSeenChatMessage(messageId: String, userId: String) -> Bool {
        chatReadReceipts.contains { $0.messageId == messageId && $0.userId == userId }
    }

    func markChatMessageSeen(messageId: String, userId: String, userName: String) async {
        guard !hasSeenChatMessage(messageId: messageId, userId: userId) else { return }
        let docId = "\(messageId)_\(userId)"
        let payload: [String: Any] = [
            "messageId": messageId,
            "userId": userId,
            "userName": userName,
            "readAt": Timestamp(date: Date()),
            "franchiseId": FirebaseService.shared.currentFranchiseId
        ]
        try? await FirebaseService.shared
            .getCollectionReference("teamChatReads")
            .document(docId)
            .setData(payload, merge: true)
    }

    func markIncomingMessagesSeen(currentUserId: String, userName: String) async {
        for message in chatMessages where message.createdByUid != currentUserId {
            await markChatMessageSeen(messageId: message.id, userId: currentUserId, userName: userName)
        }
    }

    func touchLastOnline(userId: String, userName: String) async {
        let payload: [String: Any] = [
            "userId": userId,
            "userName": userName,
            "lastOnlineAt": Timestamp(date: Date()),
            "franchiseId": FirebaseService.shared.currentFranchiseId
        ]
        try? await FirebaseService.shared
            .getCollectionReference("teamChatPresence")
            .document(userId)
            .setData(payload, merge: true)
    }

    func allChatMediaAttachments() -> [(message: TeamChatMessage, attachment: AnnouncementAttachment)] {
        mergedChatMessages().flatMap { message in
            message.attachments
                .filter { !$0.isAudio }
                .map { (message, $0) }
        }
        .reversed()
    }

    func updateTypingIndicator(userId: String, userName: String, isTyping: Bool) {
        typingDebounceTask?.cancel()
        guard isTyping else {
            clearTypingIndicator()
            return
        }
        typingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let payload: [String: Any] = [
                "userId": userId,
                "userName": userName,
                "updatedAt": Timestamp(date: Date()),
                "franchiseId": FirebaseService.shared.currentFranchiseId
            ]
            try? await FirebaseService.shared
                .getCollectionReference("teamChatTyping")
                .document(userId)
                .setData(payload, merge: true)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            clearTypingIndicator()
        }
    }

    func clearTypingIndicator() {
        typingDebounceTask?.cancel()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        FirebaseService.shared
            .getCollectionReference("teamChatTyping")
            .document(uid)
            .delete()
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        kind: String,
        folder: String
    ) async throws -> AnnouncementAttachment {
        let ext = (fileName as NSString).pathExtension.isEmpty ? "bin" : (fileName as NSString).pathExtension
        let storagePath = "franchises/\(FirebaseService.shared.currentFranchiseId)/\(folder)/\(UUID().uuidString).\(ext)"
        let url: String = try await withCheckedThrowingContinuation { continuation in
            FirebaseService.shared.uploadData(data, path: storagePath, contentType: mimeType) { url, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: url ?? "")
            }
        }
        return AnnouncementAttachment(
            kind: kind,
            storagePath: storagePath,
            downloadURL: url,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(data.count)
        )
    }

    func uploadPhoto(_ image: UIImage, folder: String) async throws -> AnnouncementAttachment {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "AnnouncementStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Image encoding failed"])
        }
        return try await uploadAttachment(
            data: data,
            fileName: "\(UUID().uuidString).jpg",
            mimeType: "image/jpeg",
            kind: "photo",
            folder: folder
        )
    }

    func uploadVoice(from localURL: URL, folder: String) async throws -> AnnouncementAttachment {
        let data = try Data(contentsOf: localURL)
        return try await uploadAttachment(
            data: data,
            fileName: localURL.lastPathComponent,
            mimeType: "audio/m4a",
            kind: "audio",
            folder: folder
        )
    }

    private func publishDueScheduledAnnouncementsIfNeeded() async {
        let now = Date()
        let due = announcements.filter {
            $0.status == .scheduled && ($0.scheduledAt ?? .distantFuture) <= now
        }
        for item in due {
            let ref = FirebaseService.shared.getCollectionReference("announcements").document(item.id)
            do {
                try await ref.updateData([
                    "status": AnnouncementStatus.published.rawValue,
                    "publishedAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: now)
                ])
                NotificationManager.shared.sendAnnouncementNotification(
                    title: item.title,
                    publisherName: item.createdByName,
                    announcementId: item.id
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
