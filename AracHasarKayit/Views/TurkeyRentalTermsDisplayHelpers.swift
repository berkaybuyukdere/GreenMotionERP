import SwiftUI
import UIKit
import PDFKit

// MARK: - Filled terms (placeholders + optional inline signature image)

struct TurkeyRentalTermsFilledStackView: View {
    let rawTerms: String
    let context: TurkeyRentalTermsFillContext
    /// Strokes from the terms signature pad (used only when `showsInlineSignaturePreview` is true).
    let termsStrokes: [[CGPoint]]
    let termsCanvasSize: CGSize
    /// When false, the long terms body does not re-layout while signing (better scroll stability and FPS).
    var showsInlineSignaturePreview: Bool = true

    private var signatureImage: UIImage? {
        guard showsInlineSignaturePreview else { return nil }
        let total = termsStrokes.reduce(0) { $0 + $1.count }
        guard total > 4,
              let data = TurkeyTermsSignaturePad.rasterizeSignaturePNG(strokes: termsStrokes, canvasSize: termsCanvasSize),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    private var displayString: String {
        TurkeyRentalTermsPlaceholders.apply(
            to: rawTerms,
            context: context,
            embedSignatureMarker: signatureImage != nil
        )
    }

    var body: some View {
        let parts = displayString.components(separatedBy: TurkeyRentalTermsPlaceholders.signatureSplitMarker)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { idx, segment in
                if !segment.isEmpty {
                    TurkeyRentalTermsReadableText(text: segment)
                }
                if idx < parts.count - 1, let img = signatureImage {
                    Image(uiImage: img.withRenderingMode(.alwaysOriginal))
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 72)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Multi-slot signing: scrollable preview (same segment order as PDF `<<<SIG_n>>>`)

/// Scrolls so the active `{signature}` slot stays near the center while the customer signs on the pad below.
struct TurkeyTermsMultiSignatureScrollPreview: View {
    let filledWithSlotMarkers: String
    let isTurkishLayout: Bool
    let activeSlotIndex: Int
    let collectedSignatures: [UIImage]
    let totalSlots: Int
    var hasExistingSavedPdf: Bool = false

    private var pieces: [TurkeyRentalTermsLayoutPiece] {
        TurkeyRentalTermsPlaceholders.multiSignatureLayoutPieces(
            filledWithSlotMarkers: filledWithSlotMarkers,
            isTurkishLayout: isTurkishLayout
        )
    }

    private static func slotAnchor(_ slot: Int) -> String { "terms-sig-slot-\(slot)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasExistingSavedPdf {
                Text("tr_terms.existing_signed_replaced_hint".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("tr_terms.slot_preview_caption".localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pieces) { piece in
                            switch piece.kind {
                            case .text(let s):
                                TurkeyRentalTermsReadableText(text: s)
                            case .signatureSlot(let slotIdx):
                                signatureSlotCell(slotIdx: slotIdx)
                                    .id(Self.slotAnchor(slotIdx))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .onChange(of: activeSlotIndex) { _, new in
                    scrollToSlot(proxy: proxy, slot: new)
                }
                .onChange(of: collectedSignatures.count) { _, _ in
                    scrollToSlot(proxy: proxy, slot: activeSlotIndex)
                }
                .onAppear {
                    scrollToSlot(proxy: proxy, slot: activeSlotIndex)
                }
            }
        }
    }

    private func scrollToSlot(proxy: ScrollViewProxy, slot: Int) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(Self.slotAnchor(slot), anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func signatureSlotCell(slotIdx: Int) -> some View {
        let isPast = slotIdx < activeSlotIndex
        let isCurrent = slotIdx == activeSlotIndex
        let total = max(totalSlots, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "tr_terms.slot_chip".localized, slotIdx + 1, total))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isCurrent ? 0.14 : 0.06))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isCurrent ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: isCurrent ? 2.5 : 1
                    )
                if isPast, slotIdx < collectedSignatures.count {
                    Image(uiImage: collectedSignatures[slotIdx].withRenderingMode(.alwaysOriginal))
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 56)
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(4)
                } else if isCurrent {
                    Text("tr_terms.sign_here_short".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(8)
                } else {
                    Text("tr_terms.slot_pending".localized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 72, maxHeight: 88)
        }
    }
}

// MARK: - Readable contract body (plain .txt lines → spaced blocks)

struct TurkeyRentalTermsReadableText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum RowKind {
        case title
        case sectionHeader
        case body
        case bullet
    }

    private struct Row: Hashable {
        let kind: RowKind
        let string: String
    }

    private var rows: [Row] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")
        var out: [Row] = []
        for line in rawLines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                out.append(Row(kind: .body, string: ""))
                continue
            }
            let kind: RowKind
            if Self.isMainTitleLine(t) {
                kind = .title
            } else if Self.isNumberedSectionLine(t) {
                kind = .sectionHeader
            } else if Self.isLetterParenClauseLine(t) {
                kind = .bullet
            } else if Self.isBulletLine(line) {
                kind = .bullet
            } else {
                kind = .body
            }
            out.append(Row(kind: kind, string: t))
        }
        return out
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if row.string.isEmpty {
            Color.clear.frame(height: 10)
        } else {
            switch row.kind {
            case .title:
                Text(row.string)
                    .font(.custom("Helvetica-Bold", size: 17))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
            case .sectionHeader:
                Text(row.string)
                    .font(.custom("Helvetica-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            case .bullet:
                Text(row.string)
                    .font(.custom("Helvetica", size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            case .body:
                Text(row.string)
                    .font(.custom("Helvetica", size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .padding(.bottom, 10)
            }
        }
    }

    private static func isMainTitleLine(_ t: String) -> Bool {
        let lower = t.lowercased()
        if t == "Genel Kiralama Koşulları" || t.hasPrefix("Genel Kiralama Koşulları") { return true }
        if lower.contains("general rental terms") && lower.count < 80 { return true }
        return false
    }

    private static func isNumberedSectionLine(_ t: String) -> Bool {
        let range = NSRange(t.startIndex..<t.endIndex, in: t)
        guard let re = try? NSRegularExpression(pattern: "^\\d+\\.\\s+\\S") else { return false }
        return re.firstMatch(in: t, options: [], range: range) != nil
    }

    private static func isBulletLine(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("•") || t.hasPrefix("·") || raw.contains("\t•")
    }

    /// Sub-clauses like `a) ...` under a numbered article.
    private static func isLetterParenClauseLine(_ t: String) -> Bool {
        t.range(of: #"^[a-z]\)\s*\S"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - PDF preview (read-only; no on-PDF signature layer)

// MARK: - Full-screen PDF preview

struct TurkeyPdfPreviewItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}

struct TurkeyPdfFullScreenPreview: View {
    let pdfData: Data
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            TurkeyReadOnlyPdfRepresentable(pdfData: pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close".localized) { onDismiss() }
                    }
                }
        }
    }
}

struct TurkeyReadOnlyPdfRepresentable: UIViewRepresentable {
    let pdfData: Data

    final class Coordinator {
        var lastData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.usePageViewController(false, withViewOptions: nil)
        if let doc = PDFDocument(data: pdfData) {
            pdfView.document = doc
        }
        context.coordinator.lastData = pdfData
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        guard context.coordinator.lastData != pdfData else { return }
        context.coordinator.lastData = pdfData
        pdfView.document = PDFDocument(data: pdfData)
    }
}

// MARK: - Terms signature pad (UIKit strokes; SwiftUI binding updates once per stroke)

final class TurkeyTermsSignatureSurfaceView: UIView {
    private var lines: [[CGPoint]] = []
    private var current: [CGPoint] = []
    private var isTouching = false

    var onStrokeCommitted: (([[CGPoint]]) -> Void)?
    var onCanvasSizeChange: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        layer.masksToBounds = true
        layer.cornerRadius = 12
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func replaceStrokes(_ external: [[CGPoint]]) {
        guard !isTouching else { return }
        lines = external
        current.removeAll()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onCanvasSizeChange?(bounds.size)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
        UIColor.secondarySystemBackground.setFill()
        ctx.fill(bounds)
        ctx.setStrokeColor(UIColor.label.cgColor)
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func stroke(_ seg: [CGPoint]) {
            guard let f = seg.first else { return }
            ctx.move(to: f)
            for p in seg.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
        for seg in lines { stroke(seg) }
        if !current.isEmpty { stroke(current) }
        ctx.restoreGState()
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        return CGPoint(x: min(max(p.x, 0), w), y: min(max(p.y, 0), h))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = true
        current.removeAll()
        if let p = touches.first?.location(in: self) { current.append(clamp(p)) }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        current.append(clamp(p))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        commitStrokeIfNeeded()
        isTouching = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        commitStrokeIfNeeded()
        isTouching = false
    }

    private func commitStrokeIfNeeded() {
        if current.count > 1 { lines.append(current) }
        current.removeAll()
        setNeedsDisplay()
        onStrokeCommitted?(lines)
    }
}

struct TurkeyTermsSignaturePad: UIViewRepresentable {
    @Binding var strokes: [[CGPoint]]
    var onCanvasSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(strokes: $strokes, onCanvasSizeChange: onCanvasSizeChange)
    }

    final class Coordinator {
        var strokes: Binding<[[CGPoint]]>
        let onCanvasSizeChange: (CGSize) -> Void
        init(strokes: Binding<[[CGPoint]]>, onCanvasSizeChange: @escaping (CGSize) -> Void) {
            self.strokes = strokes
            self.onCanvasSizeChange = onCanvasSizeChange
        }
    }

    func makeUIView(context: Context) -> TurkeyTermsSignatureSurfaceView {
        let v = TurkeyTermsSignatureSurfaceView()
        v.replaceStrokes(strokes)
        v.onStrokeCommitted = { committed in
            context.coordinator.strokes.wrappedValue = committed
        }
        v.onCanvasSizeChange = { context.coordinator.onCanvasSizeChange($0) }
        return v
    }

    func updateUIView(_ uiView: TurkeyTermsSignatureSurfaceView, context: Context) {
        context.coordinator.strokes = $strokes
        uiView.onStrokeCommitted = { committed in
            context.coordinator.strokes.wrappedValue = committed
        }
        uiView.onCanvasSizeChange = { context.coordinator.onCanvasSizeChange($0) }
        // Only sync clears from SwiftUI; pushing full state mid-gesture would wipe the active stroke.
        if strokes.isEmpty {
            uiView.replaceStrokes([])
        }
    }
}

extension TurkeyTermsSignaturePad {
    /// Multi-stroke export for upload / PDF embedding.
    static func rasterizeSignaturePNG(strokes: [[CGPoint]], canvasSize: CGSize) -> Data? {
        let total = strokes.reduce(0) { $0 + $1.count }
        guard total > 4, canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        let out = CGSize(width: 1200, height: 500)
        let renderer = UIGraphicsImageRenderer(size: out)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: out)).fill()
            let path = UIBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let sx = out.width / canvasSize.width
            let sy = out.height / canvasSize.height
            func map(_ p: CGPoint) -> CGPoint {
                let cx = min(max(p.x, 0), canvasSize.width)
                let cy = min(max(p.y, 0), canvasSize.height)
                return CGPoint(x: cx * sx, y: cy * sy)
            }
            for seg in strokes {
                guard let first = seg.first else { continue }
                path.move(to: map(first))
                for p in seg.dropFirst() {
                    path.addLine(to: map(p))
                }
            }
            UIColor.black.setStroke()
            path.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal).pngData()
    }

    /// Single continuous stroke (legacy).
    static func rasterizeSignaturePNG(points: [CGPoint], canvasSize: CGSize) -> Data? {
        guard !points.isEmpty else { return nil }
        return rasterizeSignaturePNG(strokes: [points], canvasSize: canvasSize)
    }
}
