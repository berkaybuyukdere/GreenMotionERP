import Foundation
import FirebaseFirestore

struct AnnouncementAttachment: Identifiable, Equatable, Codable {
    var id: String
    var kind: String
    var storagePath: String
    var downloadURL: String
    var fileName: String
    var mimeType: String
    var fileSize: Int64

    var isPhoto: Bool { kind == "photo" }
    var isAudio: Bool { kind == "audio" || mimeType.hasPrefix("audio/") }

    init(
        id: String = UUID().uuidString,
        kind: String,
        storagePath: String,
        downloadURL: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.storagePath = storagePath
        self.downloadURL = downloadURL
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
    }

    init?(data: [String: Any]) {
        guard let kind = data["kind"] as? String else { return nil }
        id = data["id"] as? String ?? UUID().uuidString
        self.kind = kind
        storagePath = data["storagePath"] as? String ?? ""
        downloadURL = data["downloadURL"] as? String ?? ""
        fileName = data["fileName"] as? String ?? ""
        mimeType = data["mimeType"] as? String ?? ""
        if let n = data["fileSize"] as? Int64 {
            fileSize = n
        } else if let n = data["fileSize"] as? Int {
            fileSize = Int64(n)
        } else {
            fileSize = 0
        }
    }

    var firestorePayload: [String: Any] {
        [
            "id": id,
            "kind": kind,
            "storagePath": storagePath,
            "downloadURL": downloadURL,
            "fileName": fileName,
            "mimeType": mimeType,
            "fileSize": fileSize
        ]
    }
}

enum AnnouncementStatus: String, Codable {
    case draft
    case scheduled
    case published
}

struct FranchiseAnnouncement: Identifiable, Equatable {
    let id: String
    var title: String
    var icon: String
    var iconColorKey: String
    var body: String
    var attachments: [AnnouncementAttachment]
    var createdByUid: String
    var createdByName: String
    var createdAt: Date
    var updatedAt: Date?
    var scheduledAt: Date?
    var publishedAt: Date?
    var status: AnnouncementStatus
    var franchiseId: String
    var pinned: Bool
    var pinnedAt: Date?
    /// `general` (default) or `daily_report` for automated 21:30 fleet summaries.
    var announcementKind: String

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let title = data["title"] as? String,
              let icon = data["icon"] as? String,
              let body = data["body"] as? String,
              let createdByUid = data["createdByUid"] as? String,
              let createdByName = data["createdByName"] as? String,
              let statusRaw = data["status"] as? String,
              let status = AnnouncementStatus(rawValue: statusRaw) else { return nil }

        id = document.documentID
        self.title = title
        self.icon = icon
        iconColorKey = data["iconColorKey"] as? String ?? "purple"
        self.body = body
        self.createdByUid = createdByUid
        self.createdByName = createdByName
        self.status = status
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        createdAt = Self.date(from: data["createdAt"]) ?? Date()
        updatedAt = Self.date(from: data["updatedAt"])
        scheduledAt = Self.date(from: data["scheduledAt"])
        publishedAt = Self.date(from: data["publishedAt"])
        attachments = (data["attachments"] as? [[String: Any]] ?? [])
            .compactMap { AnnouncementAttachment(data: $0) }
        pinned = data["pinned"] as? Bool ?? false
        pinnedAt = Self.date(from: data["pinnedAt"])
        announcementKind = (data["announcementKind"] as? String ?? "general").lowercased()
    }

    var isPublished: Bool { status == .published }
    var isDailyReport: Bool { announcementKind == "daily_report" }

    private static func date(from value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}

struct AnnouncementReadReceipt: Identifiable, Equatable {
    let id: String
    let announcementId: String
    let userId: String
    let userName: String
    let readAt: Date
    let franchiseId: String

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let announcementId = data["announcementId"] as? String,
              let userId = data["userId"] as? String else { return nil }
        id = document.documentID
        self.announcementId = announcementId
        self.userId = userId
        userName = data["userName"] as? String ?? ""
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["readAt"] as? Timestamp {
            readAt = ts.dateValue()
        } else {
            readAt = Date()
        }
    }
}

struct AnnouncementReaction: Identifiable, Equatable {
    let id: String
    let announcementId: String
    let userId: String
    let userName: String
    let emoji: String
    let createdAt: Date
    let franchiseId: String

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let announcementId = data["announcementId"] as? String,
              let userId = data["userId"] as? String,
              let emoji = data["emoji"] as? String else { return nil }
        id = document.documentID
        self.announcementId = announcementId
        self.userId = userId
        self.userName = data["userName"] as? String ?? ""
        self.emoji = emoji
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }
    }
}

struct TeamChatMessage: Identifiable, Equatable {
    let id: String
    var body: String
    var attachments: [AnnouncementAttachment]
    var createdByUid: String
    var createdByName: String
    var createdAt: Date
    var franchiseId: String

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let body = data["body"] as? String,
              let createdByUid = data["createdByUid"] as? String,
              let createdByName = data["createdByName"] as? String else { return nil }
        id = document.documentID
        self.body = body
        self.createdByUid = createdByUid
        self.createdByName = createdByName
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }
        attachments = (data["attachments"] as? [[String: Any]] ?? [])
            .compactMap { AnnouncementAttachment(data: $0) }
    }

    init(
        id: String,
        body: String,
        attachments: [AnnouncementAttachment],
        createdByUid: String,
        createdByName: String,
        createdAt: Date,
        franchiseId: String
    ) {
        self.id = id
        self.body = body
        self.attachments = attachments
        self.createdByUid = createdByUid
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.franchiseId = franchiseId
    }
}

struct TeamChatReadReceipt: Identifiable, Equatable {
    let id: String
    let messageId: String
    let userId: String
    let userName: String
    let readAt: Date
    let franchiseId: String

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let messageId = data["messageId"] as? String,
              let userId = data["userId"] as? String else { return nil }
        id = document.documentID
        self.messageId = messageId
        self.userId = userId
        userName = data["userName"] as? String ?? ""
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["readAt"] as? Timestamp {
            readAt = ts.dateValue()
        } else {
            readAt = Date()
        }
    }
}

struct TeamChatPresence: Identifiable, Equatable {
    let userId: String
    let userName: String
    let lastOnlineAt: Date
    let franchiseId: String

    var id: String { userId }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let userId = data["userId"] as? String else { return nil }
        self.userId = userId
        userName = data["userName"] as? String ?? ""
        franchiseId = (data["franchiseId"] as? String ?? "").uppercased()
        if let ts = data["lastOnlineAt"] as? Timestamp {
            lastOnlineAt = ts.dateValue()
        } else {
            lastOnlineAt = Date()
        }
    }

    var isOnline: Bool {
        lastOnlineAt.timeIntervalSinceNow > -120
    }

    var lastOnlineLabel: String {
        if isOnline { return "announcements.chat.online".localized }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: lastOnlineAt, relativeTo: Date())
    }
}
