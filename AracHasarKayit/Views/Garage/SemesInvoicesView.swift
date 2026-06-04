import SwiftUI
import QuickLook
import FirebaseStorage

struct SemesInvoicesView: View {
    @StateObject private var viewModel = SemesInvoicesViewModel()
    @State private var searchQuery = ""
    @State private var previewURL: URL?
    @State private var showPreview = false
    @State private var openingId: String?

    private var filtered: [SemesInvoiceItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.items }
        return viewModel.items.filter { $0.searchBlob.contains(q) }
    }

    var body: some View {
        ZStack {
            PalantirTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                summaryStrip
                searchRow
                invoiceList
            }
        }
        .navigationTitle("announcements.calculations".localized)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .refreshable { viewModel.refresh() }
        .sheet(isPresented: $showPreview) {
            if let previewURL {
                SemesQuickLookPreview(url: previewURL)
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

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            PalantirMetricTile(
                title: "semes.summary.total".localized,
                value: "\(viewModel.items.count)",
                icon: "doc.text.fill",
                tint: PalantirTheme.accent
            )
            PalantirMetricTile(
                title: "semes.summary.pending".localized,
                value: "\(viewModel.items.filter { $0.paymentStatus.lowercased() != "paid" }.count)",
                icon: "clock.fill",
                tint: PalantirTheme.warning
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("semes.search.placeholder".localized, text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(PalantirTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PalantirTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var invoiceList: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            Spacer()
            ProgressView("semes.loading".localized)
                .tint(PalantirTheme.accent)
            Spacer()
        } else if filtered.isEmpty {
            Spacer()
            ContentUnavailableView(
                "semes.empty.title".localized,
                systemImage: "doc.text",
                description: Text("semes.empty.subtitle".localized)
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { item in
                        invoiceRow(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func invoiceRow(_ item: SemesInvoiceItem) -> some View {
        let statusTint = paymentTint(item.paymentStatus)
        return HStack(spacing: 0) {
            if openingId == item.id {
                HStack {
                    Spacer()
                    ProgressView().tint(PalantirTheme.accent)
                    Spacer()
                }
                .padding(14)
            } else {
                VStack(spacing: 0) {
                    PalantirListRowAccent(
                        leadingIcon: item.fileType == "pdf" ? "doc.richtext.fill" : "doc.fill",
                        leadingTint: PalantirTheme.accent,
                        title: item.displayTitle,
                        subtitle: item.uploadedAt?.formatted(date: .abbreviated, time: .omitted) ?? item.invoiceId,
                        trailing: item.paymentStatus.capitalized,
                        trailingTint: statusTint
                    )

                    HStack(spacing: 12) {
                        Button {
                            Task { await open(item, share: false) }
                        } label: {
                            Label("semes.preview".localized, systemImage: "eye.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await open(item, share: true) }
                        } label: {
                            Label("semes.download".localized, systemImage: "arrow.down.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PalantirTheme.success)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func paymentTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "paid": return PalantirTheme.success
        case "unpaid": return PalantirTheme.critical
        default: return PalantirTheme.warning
        }
    }

    private func open(_ item: SemesInvoiceItem, share: Bool) async {
        openingId = item.id
        defer { openingId = nil }
        do {
            let remote = try await SemesInvoiceOpenHelper.resolveDownloadURL(for: item)
            let local = try await FileLibraryOpenHelper.materializeLocalFile(
                from: remote,
                preferredName: item.fileName.isEmpty ? item.invoiceId : item.fileName
            )
            if share {
                await MainActor.run {
                    let av = UIActivityViewController(activityItems: [local], applicationActivities: nil)
                    UIApplication.shared.firstKeyWindow?.rootViewController?.present(av, animated: true)
                }
            } else {
                previewURL = local
                showPreview = true
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class SemesInvoicesViewModel: ObservableObject {
    @Published private(set) var items: [SemesInvoiceItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func start() {
        isLoading = true
        FirebaseService.shared.observeSemesInvoices { [weak self] list in
            Task { @MainActor in
                self?.items = list
                self?.isLoading = false
            }
        }
    }

    func stop() {
        FirebaseService.shared.removeSemesInvoicesListener()
    }

    func refresh() {
        FirebaseService.shared.loadSemesInvoices { [weak self] list, error in
            Task { @MainActor in
                if let list { self?.items = list }
                if let error { self?.errorMessage = error.localizedDescription }
            }
        }
    }
}

enum SemesInvoiceOpenHelper {
    static func resolveDownloadURL(for item: SemesInvoiceItem) async throws -> URL {
        let trimmed = item.storageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           !trimmed.isEmpty,
           url.scheme?.hasPrefix("http") == true {
            return url
        }
        let path = item.storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw FileLibraryOpenHelper.OpenError.missingLocation }
        return try await Storage.storage().reference(withPath: path).downloadURL()
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct SemesQuickLookPreview: UIViewControllerRepresentable {
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
