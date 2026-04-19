import SwiftUI
import FirebaseFirestore
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Lists **front desk** kiosk customers (same collection as web) and attaches ID photos / PDFs into `customerDocuments`.
struct CustomerInfoScanView: View {
    /// When set (e.g. from Reports fullScreenCover), **Close** clears the presenter. Plain `dismiss()` is unreliable with nested `NavigationView` + `NavigationStack`.
    var onClose: (() -> Void)? = nil

    enum DocCategory: String, CaseIterable, Identifiable {
        case drivingLicense
        case nationalId
        case passport
        var id: String { rawValue }
        var title: String {
            switch self {
            case .drivingLicense: return "Driving License".localized
            case .nationalId: return "National ID".localized
            case .passport: return "Passport".localized
            }
        }
    }

    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var documents: [QueryDocumentSnapshot] = []
    @State private var listener: ListenerRegistration?
    @State private var searchText = ""

    private var filteredDocuments: [QueryDocumentSnapshot] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return documents }
        return documents.filter { matchesSearch($0, query: q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            contentList
        }
        .navigationTitle("Customer Info Scan".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close".localized) {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            listener?.remove()
            listener = FirebaseService.shared.observeFrontDeskCustomersForDocuments { snaps in
                DispatchQueue.main.async {
                    documents = snaps
                }
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("frontdesk.search.prompt".localized, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var contentList: some View {
        Group {
            if filteredDocuments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: documents.isEmpty ? "person.crop.rectangle.stack" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(documents.isEmpty ? "frontdesk.documents.empty".localized : "frontdesk.search.no_results".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredDocuments, id: \.documentID) { doc in
                        NavigationLink {
                            FrontDeskCustomerDocumentDetailView(documentId: doc.documentID)
                        } label: {
                            customerRow(doc)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func customerRow(_ doc: QueryDocumentSnapshot) -> some View {
        let plate = (doc.data()["vehiclePlate"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nav = (doc.data()["handoverNavKodu"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName(doc))
                    .font(.headline)
                Spacer(minLength: 8)
                if !plate.isEmpty {
                    Text(plate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                Text(doc.data()["email"] as? String ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !nav.isEmpty {
                    Text("NAV \(nav)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func matchesSearch(_ doc: QueryDocumentSnapshot, query: String) -> Bool {
        let q = query.lowercased()
        let qDigits = q.filter(\.isNumber)
        let d = doc.data()
        let plate = (d["vehiclePlate"] as? String ?? "").lowercased()
        if plate.contains(q) { return true }
        let navRaw = (d["handoverNavKodu"] as? String ?? "").lowercased()
        let navDigits = navRaw.filter(\.isNumber)
        if navRaw.contains(q) { return true }
        if !qDigits.isEmpty, navDigits.contains(qDigits) { return true }
        let fn = (d["firstName"] as? String ?? "").lowercased()
        let fam = (d["familyName"] as? String ?? "").lowercased()
        let ln = (d["lastName"] as? String ?? "").lowercased()
        let full = (d["fullName"] as? String ?? "").lowercased()
        let merged = [fn, fam].filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        if fn.contains(q) || fam.contains(q) || ln.contains(q) || full.contains(q) || merged.contains(q) { return true }
        let email = (d["email"] as? String ?? "").lowercased()
        if email.contains(q) { return true }
        return false
    }

    private func displayName(_ doc: QueryDocumentSnapshot) -> String {
        let d = doc.data()
        let fn = (d["firstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fam = (d["familyName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln = (d["lastName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = fam.isEmpty ? ln : fam
        let merged = [fn, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !merged.isEmpty { return merged }
        return (d["fullName"] as? String) ?? "—"
    }
}

private struct FrontDeskDocumentAsset: Identifiable {
    var id: String { "\(url)|\(fileName)" }
    let url: String
    let contentType: String
    let fileName: String
}

private struct FrontDeskCustomerDocumentDetailView: View {
    private static let maxAssetsPerCategory = 3

    let documentId: String
    @State private var busy = false
    @State private var pickers: [CustomerInfoScanView.DocCategory: PhotosPickerItem] = [:]
    @State private var pdfCategory: CustomerInfoScanView.DocCategory?
    @State private var showPdf = false
    @State private var docListener: ListenerRegistration?
    @State private var customerDocuments: [String: Any] = [:]

    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var cameraTargetCategory: CustomerInfoScanView.DocCategory?
    @State private var previewAsset: FrontDeskDocumentAsset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Documents".localized)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(CustomerInfoScanView.DocCategory.allCases) { cat in
                    docCategoryCard(cat)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Documents".localized)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .fileImporter(isPresented: $showPdf, allowedContentTypes: [.pdf]) { result in
            let cat = pdfCategory
            pdfCategory = nil
            switch result {
            case .success(let url):
                if let cat {
                    Task { await uploadPdf(url: url, category: cat) }
                }
            case .failure:
                break
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(selectedImage: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: showCamera) { _, isShown in
            if !isShown, cameraImage == nil {
                cameraTargetCategory = nil
            }
        }
        .onChange(of: cameraImage) { _, newVal in
            guard let img = newVal, let cat = cameraTargetCategory else { return }
            cameraTargetCategory = nil
            cameraImage = nil
            showCamera = false
            Task { await uploadUIImage(img, category: cat) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewAsset != nil },
            set: { if !$0 { previewAsset = nil } }
        )) {
            documentPreviewOverlay
        }
        .onAppear {
            docListener?.remove()
            docListener = FirebaseService.shared.observeFrontDeskCustomerDocument(documentId: documentId) { snap, _ in
                if let data = snap?.data() {
                    DispatchQueue.main.async {
                        customerDocuments = data["customerDocuments"] as? [String: Any] ?? [:]
                    }
                }
            }
        }
        .onDisappear {
            docListener?.remove()
            docListener = nil
        }
    }

    private func docCategoryCard(_ cat: CustomerInfoScanView.DocCategory) -> some View {
        let atLimit = assetsForCategory(cat).count >= Self.maxAssetsPerCategory
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(cat.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(String(format: "frontdesk.slots_used".localized, assetsForCategory(cat).count, Self.maxAssetsPerCategory))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(atLimit ? .orange : .secondary)
            }

            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        guard !atLimit else {
                            ToastManager.shared.show("frontdesk.max_assets".localized, type: .error)
                            return
                        }
                        cameraTargetCategory = cat
                        showCamera = true
                    } label: {
                        tileVisual(
                            title: "frontdesk.action.camera".localized,
                            systemImage: "camera.fill",
                            tint: .white,
                            background: LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || atLimit)
                }

                PhotosPicker(selection: binding(for: cat), matching: .images) {
                    tileVisual(
                        title: "frontdesk.action.gallery".localized,
                        systemImage: "photo.on.rectangle.angled",
                        tint: .primary,
                        background: LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemFill)], startPoint: .top, endPoint: .bottom)
                    )
                }
                .disabled(busy || atLimit)

                Button {
                    guard !atLimit else {
                        ToastManager.shared.show("frontdesk.max_assets".localized, type: .error)
                        return
                    }
                    pdfCategory = cat
                    showPdf = true
                } label: {
                    tileVisual(
                        title: "frontdesk.action.files".localized,
                        systemImage: "doc.fill",
                        tint: .white,
                        background: LinearGradient(colors: [Color(red: 0.45, green: 0.2, blue: 0.85), Color(red: 0.65, green: 0.35, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy || atLimit)
            }

            uploadedAssetsList(for: cat)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func tileVisual(title: String, systemImage: String, tint: Color, background: LinearGradient) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var documentPreviewOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let a = previewAsset, let u = URL(string: a.url) {
                let isPdf = assetLooksLikePdf(urlString: a.url, contentType: a.contentType)
                if isPdf {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(a.fileName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Link(destination: u) {
                            Label("frontdesk.open_browser".localized, systemImage: "safari")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.6))
                        case .empty:
                            ProgressView().tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button("Close".localized) {
                        previewAsset = nil
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(16)
                }
                Spacer()
            }
        }
    }

    private func assetLooksLikePdf(urlString: String, contentType: String) -> Bool {
        if contentType.lowercased().contains("pdf") { return true }
        return urlString.lowercased().hasSuffix(".pdf") || urlString.lowercased().contains(".pdf")
    }

    @ViewBuilder
    private func uploadedAssetsList(for cat: CustomerInfoScanView.DocCategory) -> some View {
        let assets = assetsForCategory(cat)
        if assets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(assets) { asset in
                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            previewAsset = asset
                        } label: {
                            previewThumb(for: asset)
                                .frame(width: 56, height: 56)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.fileName)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Saved".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            removeAsset(asset, category: cat)
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel("frontdesk.remove_photo".localized)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func removeAsset(_ asset: FrontDeskDocumentAsset, category: CustomerInfoScanView.DocCategory) {
        busy = true
        FirebaseService.shared.removeFrontDeskCustomerDocumentAsset(
            customerDocumentId: documentId,
            category: category.rawValue,
            url: asset.url
        ) { err in
            DispatchQueue.main.async {
                busy = false
                if let err {
                    ErrorManager.shared.showError(err, context: "Remove document")
                } else {
                    ToastManager.shared.show("frontdesk.removed".localized, type: .success)
                }
            }
        }
    }

    private func assetsForCategory(_ cat: CustomerInfoScanView.DocCategory) -> [FrontDeskDocumentAsset] {
        let raw = customerDocuments[cat.rawValue] as? [[String: Any]] ?? []
        return raw.compactMap { dict in
            guard let url = dict["url"] as? String, !url.isEmpty else { return nil }
            let ct = dict["contentType"] as? String ?? ""
            let name = (dict["fileName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = (name?.isEmpty == false) ? name! : (ct.contains("pdf") ? "document.pdf" : "image.jpg")
            return FrontDeskDocumentAsset(url: url, contentType: ct, fileName: fileName)
        }
    }

    @ViewBuilder
    private func previewThumb(for asset: FrontDeskDocumentAsset) -> some View {
        if asset.contentType.lowercased().contains("pdf") || asset.fileName.lowercased().hasSuffix(".pdf") {
            Image(systemName: "doc.richtext.fill")
                .font(.title2)
                .foregroundStyle(.red.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AsyncImage(url: URL(string: asset.url)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .clipped()
        }
    }

    private func binding(for cat: CustomerInfoScanView.DocCategory) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { pickers[cat] },
            set: { newVal in
                pickers[cat] = newVal
                if let newVal {
                    Task { await uploadPhoto(item: newVal, category: cat) }
                }
            }
        )
    }

    @MainActor
    private func uploadUIImage(_ image: UIImage, category: CustomerInfoScanView.DocCategory) async {
        if assetsForCategory(category).count >= Self.maxAssetsPerCategory {
            ToastManager.shared.show("frontdesk.max_assets".localized, type: .error)
            return
        }
        busy = true
        defer { busy = false }
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            ErrorManager.shared.showError(
                NSError(domain: "CustomerInfoScan", code: -4, userInfo: [NSLocalizedDescriptionKey: "Could not encode image"]),
                context: "Document upload"
            )
            return
        }
        await uploadJPEGData(data, category: category, fileName: "camera-\(UUID().uuidString.prefix(8)).jpg")
    }

    @MainActor
    private func uploadPhoto(item: PhotosPickerItem, category: CustomerInfoScanView.DocCategory) async {
        if assetsForCategory(category).count >= Self.maxAssetsPerCategory {
            ToastManager.shared.show("frontdesk.max_assets".localized, type: .error)
            pickers[category] = nil
            return
        }
        busy = true
        defer { busy = false }
        do {
            let data = try await normalizedJPEGData(from: item)
            await uploadJPEGData(data, category: category, fileName: "gallery-\(UUID().uuidString.prefix(8)).jpg")
        } catch {
            ErrorManager.shared.showError(error, context: "Document upload")
        }
    }

    /// Loads image data from the picker; re-encodes as JPEG when possible to avoid HEIC / transferable edge cases that can crash or fail.
    private func normalizedJPEGData(from item: PhotosPickerItem) async throws -> Data {
        if let raw = try await item.loadTransferable(type: Data.self), !raw.isEmpty {
            if let ui = UIImage(data: raw), let jpeg = ui.jpegData(compressionQuality: 0.88) {
                return jpeg
            }
            return raw
        }
        throw NSError(domain: "CustomerInfoScan", code: -5, userInfo: [NSLocalizedDescriptionKey: "Could not read photo"])
    }

    @MainActor
    private func uploadJPEGData(_ data: Data, category: CustomerInfoScanView.DocCategory, fileName: String) async {
        let path = "frontDeskCustomers/\(documentId)/\(category.rawValue)/\(UUID().uuidString).jpg"
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                FirebaseService.shared.uploadData(data, path: path, contentType: "image/jpeg") { url, err in
                    if let err { cont.resume(throwing: err); return }
                    guard let url else {
                        cont.resume(throwing: NSError(domain: "CustomerInfoScan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))
                        return
                    }
                    FirebaseService.shared.appendFrontDeskCustomerDocumentAsset(
                        customerDocumentId: documentId,
                        category: category.rawValue,
                        url: url,
                        contentType: "image/jpeg",
                        fileName: fileName
                    ) { err in
                        if let err { cont.resume(throwing: err) }
                        else { cont.resume() }
                    }
                }
            }
            ToastManager.shared.show("Saved".localized, type: .success)
        } catch {
            ErrorManager.shared.showError(error, context: "Document upload")
        }
    }

    @MainActor
    private func uploadPdf(url: URL, category: CustomerInfoScanView.DocCategory) async {
        if assetsForCategory(category).count >= Self.maxAssetsPerCategory {
            ToastManager.shared.show("frontdesk.max_assets".localized, type: .error)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("frontdesk-\(documentId)-\(UUID().uuidString).pdf")
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: url, to: tempURL)
            let data = try Data(contentsOf: tempURL, options: [.mappedIfSafe])
            try? FileManager.default.removeItem(at: tempURL)
            let safeName = url.lastPathComponent.isEmpty ? "document.pdf" : url.lastPathComponent
            let path = "frontDeskCustomers/\(documentId)/\(category.rawValue)/\(UUID().uuidString).pdf"
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                FirebaseService.shared.uploadData(data, path: path, contentType: "application/pdf") { remoteUrl, err in
                    if let err { cont.resume(throwing: err); return }
                    guard let remoteUrl else {
                        cont.resume(throwing: NSError(domain: "CustomerInfoScan", code: -2, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))
                        return
                    }
                    FirebaseService.shared.appendFrontDeskCustomerDocumentAsset(
                        customerDocumentId: documentId,
                        category: category.rawValue,
                        url: remoteUrl,
                        contentType: "application/pdf",
                        fileName: safeName
                    ) { err in
                        if let err { cont.resume(throwing: err) }
                        else { cont.resume() }
                    }
                }
            }
            ToastManager.shared.show("Saved".localized, type: .success)
        } catch {
            ErrorManager.shared.showError(error, context: "PDF upload")
        }
    }
}
