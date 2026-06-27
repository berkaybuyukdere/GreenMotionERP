import SwiftUI
import Kingfisher
import PhotosUI
import UniformTypeIdentifiers
import FirebaseAuth

struct AnnouncementAttachmentStrip: View {
    let attachments: [AnnouncementAttachment]
    var onRemove: ((String) -> Void)?
    var onTap: ((AnnouncementAttachment) -> Void)?

    private static let thumbSize: CGFloat = 72
    private static let rowHeight: CGFloat = 80

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { item in
                    attachmentCell(item)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: Self.rowHeight)
    }

    @ViewBuilder
    private func attachmentCell(_ item: AnnouncementAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onTap?(item)
            } label: {
                Group {
                    if item.isPhoto, let url = URL(string: item.downloadURL), !item.downloadURL.isEmpty {
                        KFImage(url)
                            .placeholder { Color.gray.opacity(0.15) }
                            .resizable()
                            .scaledToFill()
                    } else if item.isAudio {
                        VStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(MessagesTheme.iosBlue)
                            Text("announcements.chat.voice".localized)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MessagesTheme.iosGray6)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: item.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
                                .font(.title3)
                                .foregroundStyle(MessagesTheme.iosBlue)
                            Text(item.fileName)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MessagesTheme.iosGray6)
                    }
                }
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            if let onRemove {
                Button {
                    onRemove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .padding(2)
            }
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
    }
}

struct AnnouncementComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.palantirModeEnabled) private var palantirMode
    @ObservedObject var store: AnnouncementStore

    var editing: FranchiseAnnouncement?

    @State private var title = ""
    @State private var icon = "megaphone.fill"
    @State private var iconColorKey = "purple"
    @State private var bodyText = ""
    @State private var attachments: [AnnouncementAttachment] = []
    @State private var scheduleEnabled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var isSaving = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var galleryItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("announcements.composer.title_section".localized) {
                    TextField("announcements.composer.title".localized, text: $title)

                    HStack(spacing: 16) {
                        AnnouncementIconPalette.badge(icon: icon, colorKey: iconColorKey, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("announcements.composer.preview".localized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PalantirTheme.textMuted)
                            Text(title.isEmpty ? "announcements.composer.title".localized : title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)

                    Text("announcements.composer.color_section".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AnnouncementColorKey.allCases) { key in
                                Button {
                                    iconColorKey = key.rawValue
                                    HapticManager.shared.light()
                                } label: {
                                    Rectangle()
                                        .fill(key.color)
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if iconColorKey == key.rawValue {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .overlay {
                                            Rectangle()
                                                .strokeBorder(
                                                    iconColorKey == key.rawValue ? Color.primary : Color.clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-3)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("announcements.composer.icon_section".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AnnouncementIconPalette.iconChoices, id: \.self) { name in
                                Button {
                                    icon = name
                                    HapticManager.shared.light()
                                } label: {
                                    AnnouncementIconPalette.badge(
                                        icon: name,
                                        colorKey: iconColorKey,
                                        size: 44,
                                        dimmed: icon != name
                                    )
                                    .opacity(icon == name ? 1 : 0.55)
                                    .overlay {
                                        if icon == name {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .strokeBorder(Color.primary, lineWidth: 2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("announcements.composer.body_section".localized) {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                }

                Section("announcements.composer.attachments".localized) {
                    if !attachments.isEmpty {
                        AnnouncementAttachmentStrip(attachments: attachments) { id in
                            attachments.removeAll { $0.id == id }
                        }
                    }
                    ComposerMediaPickerBar(
                        galleryItems: $galleryItems,
                        maxSelection: 8,
                        onCamera: { showCamera = true },
                        onFileImport: { showFileImporter = true }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("announcements.composer.schedule".localized) {
                    Toggle("announcements.schedule_later".localized, isOn: $scheduleEnabled)
                    if scheduleEnabled {
                        DatePicker(
                            "announcements.scheduled_at".localized,
                            selection: $scheduledDate,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .palantirFormListStyleWhen(enabled: palantirMode)
            .scrollContentBackground(.hidden)
            .background(PalantirTheme.background)
            .navigationTitle(editing == nil ? "announcements.new".localized : "announcements.edit".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("announcements.publish".localized) {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: galleryItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importGallery(items) }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
                CameraPicker(selectedImage: $capturedImage)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .data, .image, .plainText], allowsMultipleSelection: true) { result in
                Task { await importFiles(result) }
            }
            .alert("Error".localized, isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK".localized, role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                guard let editing else { return }
                title = editing.title
                icon = editing.icon
                iconColorKey = editing.iconColorKey
                bodyText = editing.body
                attachments = editing.attachments
                if let scheduled = editing.scheduledAt, editing.status == .scheduled {
                    scheduleEnabled = true
                    scheduledDate = scheduled
                }
            }
        }
    }

    private func handleCameraDismiss() {
        guard let capturedImage else { return }
        self.capturedImage = nil
        Task {
            do {
                let att = try await store.uploadPhoto(capturedImage, folder: "announcements")
                attachments.append(att)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func importGallery(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            do {
                let att = try await store.uploadPhoto(image, folder: "announcements")
                attachments.append(att)
            } catch {
                errorText = error.localizedDescription
            }
        }
        galleryItems = []
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    let name = url.lastPathComponent
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let att = try await store.uploadAttachment(
                        data: data,
                        fileName: name,
                        mimeType: mime,
                        kind: mime.hasPrefix("image/") ? "photo" : "file",
                        folder: "announcements"
                    )
                    attachments.append(att)
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func save() async {
        guard let profile = authManager.userProfile,
              let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.publishAnnouncement(
                title: title,
                icon: icon,
                iconColorKey: iconColorKey,
                body: bodyText,
                attachments: attachments,
                scheduledAt: scheduleEnabled ? scheduledDate : nil,
                publisherUid: uid,
                publisherName: profile.displayName,
                editingId: editing?.id
            )
            HapticManager.shared.success()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
