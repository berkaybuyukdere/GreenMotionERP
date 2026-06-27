import SwiftUI
import QuickLook
import PDFKit

// MARK: - Bundled General Rental Terms (Word)

enum TurkeyRentalTermsBundle {
    static func docURL(preferredEnglish: Bool) -> URL? {
        let base = preferredEnglish ? "rental_terms_en" : "rental_terms_tr"
        if let u = Bundle.main.url(forResource: base, withExtension: "docx") { return u }
        return Bundle.main.url(forResource: base, withExtension: "docx", subdirectory: "Resources/RentalTerms")
    }
}

// MARK: - Quick Look (Word preview)

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
}

// MARK: - Signature layout (matches TR form renter box)

enum TurkeyHandoverSignatureLayout {
    /// Same normalized box as `TRFormLayout.deliveredSignature` (customer / renter).
    private static let renterBox = nbox(0.092, 0.826, 0.386, 0.034)

    static func renterRect(forImageSize size: CGSize) -> CGRect {
        toPageRect(renterBox, pageRect: CGRect(origin: .zero, size: size))
    }
}

// MARK: - PDF page thumbnail

enum TurkeyHandoverPdfPreview {
    static func firstPageImage(data: Data, maxWidth: CGFloat) -> UIImage? {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        let media = page.bounds(for: .mediaBox)
        guard media.width > 1, media.height > 1 else { return nil }
        let scale = maxWidth / media.width
        let target = CGSize(width: maxWidth, height: media.height * scale)
        return page.thumbnail(of: target, for: .mediaBox)
    }
}

// MARK: - General terms + acceptance signature

struct TurkeyRentalTermsAcceptanceView: View {
    @Binding var isPresented: Bool
    var onAccepted: (_ languageCode: String, _ signaturePNG: Data) -> Void

    @State private var useEnglish = false
    @State private var termsStrokes: [[CGPoint]] = []
    @State private var termsCanvasSize: CGSize = CGSize(width: 320, height: 160)
    @State private var didAcceptRead = false

    private var termsDocURL: URL? {
        TurkeyRentalTermsBundle.docURL(preferredEnglish: useEnglish)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("tr_terms.legal_intro".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $useEnglish) {
                        Text("Türkçe").tag(false)
                        Text("English").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if let url = termsDocURL {
                        QuickLookPreview(url: url)
                            .id(useEnglish)
                            .frame(minHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                            )
                    } else {
                        Text("tr_terms.missing_docs".localized)
                            .foregroundStyle(.red)
                    }

                    Toggle("tr_terms.read_accept_toggle".localized, isOn: $didAcceptRead)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("tr_terms.sign_here".localized)
                            .font(.subheadline.weight(.semibold))
                        TurkeyTermsSignaturePad(strokes: $termsStrokes) { termsCanvasSize = $0 }
                            .frame(height: 160)

                        Button("tr_terms.clear_pad".localized) {
                            termsStrokes.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("tr_terms.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("tr_terms.continue".localized) {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var canSubmit: Bool {
        didAcceptRead && termsStrokes.reduce(0, { $0 + $1.count }) > 4 && termsDocURL != nil
    }

    private func submit() {
        guard let png = rasterizeTermsSignature() else { return }
        let lang = useEnglish ? "en" : "tr"
        onAccepted(lang, png)
    }

    private func rasterizeTermsSignature() -> Data? {
        TurkeyTermsSignaturePad.rasterizeSignaturePNG(strokes: termsStrokes, canvasSize: termsCanvasSize)
    }
}

// MARK: - Sign on PDF (first page, renter field)

struct TurkeyHandoverPdfSignatureSheet: View {
    let pageImage: UIImage
    @Binding var signatureImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [[CGPoint]] = []
    @State private var active: [CGPoint] = []

    private var targetWidth: CGFloat { min(UIScreen.main.bounds.width - 24, pageImage.size.width) }
    private var scale: CGFloat { targetWidth / max(pageImage.size.width, 1) }
    private var targetHeight: CGFloat { pageImage.size.height * scale }
    private var sigOrig: CGRect { TurkeyHandoverSignatureLayout.renterRect(forImageSize: pageImage.size) }
    private var sigScaled: CGRect {
        CGRect(
            x: sigOrig.minX * scale,
            y: sigOrig.minY * scale,
            width: sigOrig.width * scale,
            height: sigOrig.height * scale
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Text("tr_terms.sign_in_shaded_box".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: pageImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: targetWidth)

                        Rectangle()
                            .stroke(Color.blue.opacity(0.95), lineWidth: 2)
                            .background(Color.blue.opacity(0.06))
                            .frame(width: sigScaled.width, height: sigScaled.height)
                            .offset(x: sigScaled.minX, y: sigScaled.minY)
                            .allowsHitTesting(false)

                        inkLayer
                            .frame(width: targetWidth, height: targetHeight)
                    }
                    .frame(width: targetWidth, height: targetHeight)
                }
            }
            .navigationTitle("Customer Signature".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Signature".localized) {
                        signatureImage = rasterizeCustomerSignature()
                        dismiss()
                    }
                    .disabled(totalStrokePoints < 3)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear".localized) {
                        lines.removeAll()
                        active.removeAll()
                    }
                }
            }
        }
    }

    private var totalStrokePoints: Int {
        lines.reduce(0) { $0 + $1.count } + active.count
    }

    private var inkLayer: some View {
        Canvas { ctx, _ in
            var ink = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            for seg in lines {
                guard let first = seg.first else { continue }
                var p = Path()
                p.move(to: first)
                for pt in seg.dropFirst() {
                    p.addLine(to: pt)
                }
                ctx.stroke(p, with: .color(.black), style: ink)
            }
            if !active.isEmpty, let first = active.first {
                var p = Path()
                p.move(to: first)
                for pt in active.dropFirst() {
                    p.addLine(to: pt)
                }
                ctx.stroke(p, with: .color(.black), style: ink)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let x = g.location.x
                    let y = g.location.y
                    let r = sigScaled
                    guard x >= r.minX, x <= r.maxX, y >= r.minY, y <= r.maxY else { return }
                    active.append(g.location)
                }
                .onEnded { _ in
                    if active.count > 1 {
                        lines.append(active)
                    }
                    active.removeAll()
                }
        )
    }

    private func rasterizeCustomerSignature() -> UIImage? {
        let out = CGSize(width: 1200, height: 500)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        let r = sigScaled
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: out)).fill()
            let sx = out.width / max(r.width, 1)
            let sy = out.height / max(r.height, 1)
            let path = UIBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - r.minX) * sx, y: (p.y - r.minY) * sy)
            }
            for seg in lines {
                guard let f = seg.first else { continue }
                path.move(to: map(f))
                for p in seg.dropFirst() {
                    path.addLine(to: map(p))
                }
            }
            UIColor.black.setStroke()
            path.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
}
