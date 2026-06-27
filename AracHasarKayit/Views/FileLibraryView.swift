import SwiftUI
import QuickLook

struct FileLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FileLibraryViewModel()
    @State private var searchQuery = ""
    @State private var previewURL: URL?
    @State private var showPreview = false
    @State private var openingItemId: String?

    private var visibleItems: [FileLibraryItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return viewModel.items(inFolder: viewModel.currentFolderId, searchQuery: "")
        }
        return viewModel.items(inFolder: viewModel.currentFolderId, searchQuery: trimmed)
    }

    var body: some View {
        ZStack {
            PalantirTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                summaryRow
                breadcrumbRow
                searchRow
                fileList
            }
        }
        .navigationTitle("Files".localized)
        .navigationBarTitleDisplayMode(.inline)
        .palantirOpsScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) { dismiss() }
            }
        }
        .refreshable { viewModel.refresh() }
        .sheet(isPresented: $showPreview) {
            if let previewURL {
                FileLibraryQuickLookPreview(url: previewURL)
            }
        }
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            Spacer()
            ProgressView("files.loading".localized)
                .tint(PalantirTheme.accent)
            Spacer()
        } else if visibleItems.isEmpty {
            Spacer()
            ContentUnavailableView(
                "files.empty.title".localized,
                systemImage: "folder",
                description: Text("files.empty.subtitle".localized)
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        fileRow(for: item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func fileRow(for item: FileLibraryItem) -> some View {
        if item.type == .folder, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                viewModel.currentFolderId = item.id
            } label: {
                FileLibraryRow(item: item, isOpening: false)
            }
            .buttonStyle(.plain)
        } else if item.type == .file {
            Button {
                openFile(item)
            } label: {
                FileLibraryRow(item: item, isOpening: openingItemId == item.id)
            }
            .buttonStyle(.plain)
            .disabled(openingItemId == item.id)
        } else {
            FileLibraryRow(item: item, isOpening: false)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            fileSummaryChip(title: "files.summary.files".localized, value: "\(viewModel.fileCount)", tone: .neutral)
            fileSummaryChip(title: "files.summary.folders".localized, value: "\(viewModel.folderCount)", tone: .accent)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func fileSummaryChip(title: String, value: String, tone: FileLibraryTone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
            Text(value)
                .font(PalantirTheme.dataFont(22))
                .foregroundStyle(tone.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .palantirCard()
    }

    @ViewBuilder
    private var breadcrumbRow: some View {
        let crumbs = viewModel.folderPath(to: viewModel.currentFolderId)
        if !crumbs.isEmpty || !viewModel.currentFolderId.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.currentFolderId = ""
                    } label: {
                        Label("files.root".localized, systemImage: "house.fill")
                            .font(PalantirTheme.labelFont(11))
                            .foregroundStyle(PalantirTheme.accent)
                    }
                    ForEach(crumbs, id: \.id) { crumb in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(PalantirTheme.textMuted)
                        Button(crumb.name) {
                            viewModel.currentFolderId = crumb.id
                        }
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("files.search.placeholder".localized, text: $searchQuery)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textPrimary)
        }
        .padding(10)
        .background(PalantirTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(PalantirTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func openFile(_ item: FileLibraryItem) {
        openingItemId = item.id
        Task {
            defer { Task { @MainActor in openingItemId = nil } }
            do {
                let remote = try await FileLibraryOpenHelper.resolveDownloadURL(for: item)
                let local = try await FileLibraryOpenHelper.materializeLocalFile(
                    from: remote,
                    preferredName: item.fileName.isEmpty ? item.displayTitle : item.fileName
                )
                await MainActor.run {
                    previewURL = local
                    showPreview = true
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "files.open_failed".localized
                }
            }
        }
    }
}

private enum FileLibraryTone {
    case neutral, accent

    var color: Color {
        switch self {
        case .neutral: return PalantirTheme.accent
        case .accent: return PalantirTheme.warning
        }
    }
}

private struct FileLibraryRow: View {
    let item: FileLibraryItem
    let isOpening: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(PalantirTheme.heroFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if item.type == .file {
                        PalantirOpsBadge(text: item.categoryLabelKey.localized, tone: .accent)
                        Text(FileLibraryItem.formatByteCount(item.fileSize))
                            .font(PalantirTheme.dataFont(11))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    if !item.uploadedByName.isEmpty {
                        Text(item.uploadedByName)
                            .font(PalantirTheme.bodyFont(11))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }

                if !item.note.isEmpty {
                    Text(item.note)
                        .font(PalantirTheme.bodyFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isOpening {
                ProgressView()
                    .scaleEffect(0.85)
            } else if item.type == .folder {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            } else {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.accent)
            }
        }
        .palantirCard()
    }

    private var iconName: String {
        if item.type == .folder { return "folder.fill" }
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "zip": return "doc.zipper"
        case "png", "jpg", "jpeg", "webp": return "photo.fill"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        if item.type == .folder { return PalantirTheme.accent }
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return PalantirTheme.critical
        case "doc", "docx": return PalantirTheme.accent
        case "xls", "xlsx": return PalantirTheme.success
        case "zip": return PalantirTheme.warning
        case "png", "jpg", "jpeg", "webp": return PalantirTheme.warning
        default: return PalantirTheme.textMuted
        }
    }
}

private struct FileLibraryQuickLookPreview: UIViewControllerRepresentable {
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
