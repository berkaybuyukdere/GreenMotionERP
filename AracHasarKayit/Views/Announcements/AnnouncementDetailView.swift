import SwiftUI
import Kingfisher
import FirebaseAuth

struct AnnouncementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @ObservedObject var store: AnnouncementStore
    let announcement: FranchiseAnnouncement

    @State private var selectedHasar: HasarKaydi?
    @State private var selectedHasarAracId: UUID?
    @State private var selectedHasarPlaka: String?
    @State private var selectedVehicle: Arac?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var previewAttachment: AttachmentPreviewItem?

    private var nav: FleetTokenNavigationHandler { FleetTokenNavigationHandler(viewModel: viewModel) }
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    private var canManage: Bool { authManager.userProfile?.canPublishAnnouncements == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                VStack(alignment: .leading, spacing: 10) {
                    Text("announcements.composer.body_section".localized)
                        .font(PalantirTheme.labelFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .textCase(.uppercase)

                    FleetRichTextView(
                        text: announcement.body,
                        vehicles: viewModel.araclar,
                        style: .standard,
                        onOpenPlate: openPlate,
                        onOpenRES: openRES
                    )
                    .font(.system(size: 17))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !announcement.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("announcements.composer.attachments".localized)
                            .font(PalantirTheme.labelFont(11))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .textCase(.uppercase)
                        AnnouncementAttachmentStrip(attachments: announcement.attachments, onTap: { att in
                            previewAttachment = AttachmentPreviewItem(attachment: att)
                        })
                    }
                }

                reactionBar
                if canManage { readReceiptsSection }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit".localized) { showEdit = true }
                        Button(
                            announcement.pinned ? "announcements.unpin".localized : "announcements.pin".localized
                        ) {
                            Task {
                                try? await store.setPinned(announcementId: announcement.id, pinned: !announcement.pinned)
                            }
                        }
                        Button("Delete".localized, role: .destructive) { showDeleteConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            Task {
                await store.markRead(
                    announcementId: announcement.id,
                    userId: uid,
                    userName: authManager.userProfile?.displayName ?? ""
                )
            }
        }
        .sheet(isPresented: $showEdit) {
            AnnouncementComposerView(store: store, editing: announcement)
                .environmentObject(authManager)
        }
        .fullScreenCover(item: $previewAttachment) { item in
            AttachmentPreviewSheet(attachment: item.attachment)
        }
        .confirmationDialog("Delete".localized, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete".localized, role: .destructive) {
                Task {
                    try? await store.deleteAnnouncement(id: announcement.id)
                    dismiss()
                }
            }
            Button("Cancel".localized, role: .cancel) {}
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

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            AnnouncementIconPalette.badge(icon: announcement.icon, colorKey: announcement.iconColorKey, size: 56)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if announcement.pinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(announcement.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.blue)
                    Text(announcement.createdByName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Text(announcement.publishedAt?.formatted(date: .complete, time: .shortened) ?? "")
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var reactionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("announcements.reactions".localized)
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                ForEach(["👍", "❤️", "🎉", "👀", "✅"], id: \.self) { emoji in
                    Button {
                        Task {
                            await store.toggleReaction(
                                announcementId: announcement.id,
                                emoji: emoji,
                                userId: uid,
                                userName: authManager.userProfile?.displayName ?? ""
                            )
                        }
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            let summary = store.reactionSummary(for: announcement.id)
            if !summary.isEmpty {
                HStack(spacing: 12) {
                    ForEach(summary, id: \.emoji) { item in
                        Text("\(item.emoji) \(item.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
            }
        }
    }

    private var readReceiptsSection: some View {
        let receipts = store.readReceipts(for: announcement.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("announcements.read_by".localized)
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .textCase(.uppercase)

            if receipts.isEmpty {
                Text("announcements.no_reads_yet".localized)
                    .font(.subheadline)
                    .foregroundStyle(PalantirTheme.textMuted)
            } else {
                ForEach(receipts) { receipt in
                    HStack {
                        Text(receipt.userName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(receipt.readAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
