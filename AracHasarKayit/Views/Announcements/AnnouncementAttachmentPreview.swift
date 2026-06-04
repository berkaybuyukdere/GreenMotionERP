import SwiftUI
import QuickLook
import Kingfisher

struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let attachment: AnnouncementAttachment
}

struct AnnouncementQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

@MainActor
enum AttachmentPreviewLoader {
    static func localURL(for attachment: AnnouncementAttachment) async -> URL? {
        if attachment.downloadURL.hasPrefix("file://"),
           let url = URL(string: attachment.downloadURL) {
            return url
        }
        guard let remote = URL(string: attachment.downloadURL), !attachment.downloadURL.isEmpty else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: remote)
            let ext = (attachment.fileName as NSString).pathExtension.isEmpty ? "bin" : (attachment.fileName as NSString).pathExtension
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-\(attachment.id).\(ext)")
            try data.write(to: local, options: .atomic)
            return local
        } catch {
            return nil
        }
    }

    static func isPDF(_ attachment: AnnouncementAttachment) -> Bool {
        attachment.mimeType == "application/pdf"
            || attachment.fileName.lowercased().hasSuffix(".pdf")
    }
}

struct AttachmentPreviewSheet: View {
    let attachment: AnnouncementAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("announcements.preview.loading".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else if loadFailed {
                    ContentUnavailableView("Error".localized, systemImage: "doc.fill")
                } else if attachment.isPhoto || attachment.mimeType.hasPrefix("image/"), let url = previewURL {
                    ZoomableFitImagePreview(url: url, remoteURL: URL(string: attachment.downloadURL))
                        .ignoresSafeArea(edges: .bottom)
                } else if let previewURL {
                    AnnouncementQuickLookPreview(url: previewURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Error".localized, systemImage: "doc.fill")
                }
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
                if let previewURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: previewURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        if let local = await AttachmentPreviewLoader.localURL(for: attachment) {
            previewURL = local
            loadFailed = false
        } else {
            loadFailed = true
        }
    }
}
