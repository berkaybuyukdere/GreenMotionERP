import Foundation
import UIKit

// MARK: - Regex (multi-slot PDF)

private enum TurkeyRentalTermsSigSlotRegex {
    static let pattern = try? NSRegularExpression(pattern: "<<<SIG_(\\d+)>>>", options: [])
}

/// Values substituted into bundled `rental_terms_*.txt` placeholders.
struct TurkeyRentalTermsFillContext {
    var customerFirstName: String
    var customerLastName: String
    var testDriverFirstName: String?
    var testDriverLastName: String?
    /// Date shown on forms (checkout date, return date, or “now”).
    var agreementDate: Date
    var localeIdentifier: String
    /// Shown for marketing consent lines when unknown.
    var permissionPlaceholder: String = "—"

    var customerFullName: String {
        [customerFirstName, customerLastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var deliveryFirst: String {
        let t = testDriverFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        return customerFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var deliveryLast: String {
        let t = testDriverLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        return customerLastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dateDDMMYYYY: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: localeIdentifier)
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: agreementDate)
    }

    static func localeForTermsLanguageCode(_ code: String?) -> String {
        (code?.lowercased() == "en") ? "en_US_POSIX" : "tr_TR"
    }
}

enum TurkeyRentalTermsPlaceholders {
    static let signatureSplitMarker = "<<<INLINE_SIGNATURE>>>"

    /// Number of `{signature}` placeholders in the bundled contract (each gets its own capture step).
    static func signaturePlaceholderCount(in raw: String) -> Int {
        max(0, raw.components(separatedBy: "{signature}").count - 1)
    }

    /// Titles for each `{signature}` slot: last substantive line(s) before that placeholder in the raw contract.
    static func signatureSlotContextTitles(in raw: String) -> [String] {
        var titles: [String] = []
        let marker = "{signature}"
        var search = raw.startIndex
        while let r = raw.range(of: marker, range: search..<raw.endIndex) {
            let prefix = String(raw[..<r.lowerBound])
            titles.append(titleBeforeSignaturePlaceholder(prefix: prefix))
            search = r.upperBound
        }
        return titles
    }

    private static func titleBeforeSignaturePlaceholder(prefix: String) -> String {
        let lines = prefix.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        func isNoise(_ line: String) -> Bool {
            let low = line.lowercased()
            if line.count < 56 {
                if low == "signature" || low == "imza" { return true }
                if low.hasPrefix("signature:") || low.hasPrefix("imza:") { return true }
            }
            if line.unicodeScalars.allSatisfy({ $0 == "_" || $0 == " " || $0 == "-" || $0 == "." }) {
                return true
            }
            return false
        }

        var picked: [String] = []
        for line in lines.reversed().prefix(12) {
            if isNoise(line) { continue }
            picked.append(line)
            if line.count >= 10 { break }
        }
        if picked.isEmpty {
            return String(lines[lines.count - 1].prefix(180))
        }
        let merged = picked.reversed().joined(separator: " — ")
        if merged.count > 220 {
            return String(merged.prefix(217)) + "…"
        }
        return merged
    }

    private static func signatureSlotMarker(_ index: Int) -> String {
        "<<<SIG_\(index)>>>"
    }

    /// Fills all placeholders except `{signature}` (left intact for per-slot markers).
    static func applyDataFieldsOnly(to raw: String, context: TurkeyRentalTermsFillContext) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "{dateDDMMYYYY}", with: context.dateDDMMYYYY)
        s = s.replacingOccurrences(of: "{deliveryDriverName}", with: context.deliveryFirst)
        s = s.replacingOccurrences(of: "{deliveryDriverLastName}", with: context.deliveryLast)
        let full = context.customerFullName
        let namePair = full.isEmpty ? "—" : full
        s = s.replacingOccurrences(of: "{ } { }", with: namePair)
        s = s.replacingOccurrences(of: "{callPermission}", with: context.permissionPlaceholder)
        s = s.replacingOccurrences(of: "{emailPermission}", with: context.permissionPlaceholder)
        s = s.replacingOccurrences(of: "{smsPermission}", with: context.permissionPlaceholder)
        s = s.replacingOccurrences(of: "{ }", with: "—")
        return s
    }

    /// Replaces each `{signature}` in order with `<<<SIG_i>>>` for PDF rendering.
    static func injectSignatureSlotMarkers(into s: String, slotCount: Int) -> String {
        var result = s
        for i in 0..<slotCount {
            guard let range = result.range(of: "{signature}") else { break }
            result.replaceSubrange(range, with: signatureSlotMarker(i))
        }
        return result
    }

    /// Data fields + numbered signature markers (one image slot per `{signature}` in source).
    static func applyForMultiSignaturePdf(to raw: String, context: TurkeyRentalTermsFillContext) -> String {
        let n = signaturePlaceholderCount(in: raw)
        let base = applyDataFieldsOnly(to: raw, context: context)
        guard n > 0 else { return apply(to: raw, context: context, embedSignatureMarker: false) }
        return injectSignatureSlotMarkers(into: base, slotCount: n)
    }

    /// Fills known `{…}` tokens. When `embedSignatureMarker` is true, replaces each `{signature}` with `signatureSplitMarker` for UI/PDF splitting.
    static func apply(
        to raw: String,
        context: TurkeyRentalTermsFillContext,
        embedSignatureMarker: Bool
    ) -> String {
        var s = applyDataFieldsOnly(to: raw, context: context)
        if embedSignatureMarker {
            s = s.replacingOccurrences(of: "{signature}", with: signatureSplitMarker)
        } else {
            s = s.replacingOccurrences(of: "{signature}", with: "________________________")
        }
        return s
    }

    static func loadBundledTermsText(preferredEnglish: Bool) -> String {
        let name = preferredEnglish ? "rental_terms_en" : "rental_terms_tr"
        if let url = Bundle.main.url(forResource: name, withExtension: "txt"),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            return str
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Resources/RentalTerms"),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            return str
        }
        return ""
    }

    /// Single tall PDF: text segments with optional repeated signature image where `{signature}` was.
    /// When `isTurkishLayout` is true, paragraph and line spacing are increased for readability.
    static func makePdfData(
        filledWithMarkers: String,
        signatureImage: UIImage?,
        isTurkishLayout: Bool = false
    ) -> Data? {
        let parts = filledWithMarkers.components(separatedBy: signatureSplitMarker)
        let pageWidth: CGFloat = 612
        let margin: CGFloat = 40
        let textWidth = pageWidth - margin * 2
        let bodyFont = UIFont(name: "Helvetica", size: 9.5) ?? UIFont.systemFont(ofSize: 9.5)
        let attrs = pdfBodyAttributes(font: bodyFont, isTurkishLayout: isTurkishLayout)
        enum Piece {
            case text(String, CGFloat)
            case image
        }
        var pieces: [Piece] = []
        var contentHeight: CGFloat = margin
        for (idx, part) in parts.enumerated() {
            if !part.isEmpty {
                let h = measureTextHeight(part, width: textWidth, attributes: attrs, isTurkishLayout: isTurkishLayout)
                pieces.append(.text(part, h))
                contentHeight += h
            }
            if idx < parts.count - 1, signatureImage != nil {
                pieces.append(.image)
                contentHeight += 64
            }
        }
        contentHeight += margin
        let pageHeight = max(792, contentHeight)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "General rental terms",
            kCGPDFContextAuthor: "AracHasarKayit",
        ] as [String: Any]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { pdfCtx in
            pdfCtx.beginPage(withBounds: pageRect, pageInfo: [:])
            var y: CGFloat = margin
            for p in pieces {
                switch p {
                case let .text(str, h):
                    let ns = NSString(string: str)
                    let r = CGRect(x: margin, y: y, width: textWidth, height: h)
                    ns.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                    y += h
                case .image:
                    if let sig = signatureImage {
                        let targetH: CGFloat = 52
                        let scale = targetH / max(sig.size.height, 1)
                        let w = min(textWidth, sig.size.width * scale)
                        sig.draw(in: CGRect(x: margin, y: y, width: w, height: targetH))
                        y += 64
                    }
                }
            }
        }
    }

    /// One scrollable PDF page: text segments alternate with per-slot signature images (markers `<<<SIG_i>>>`).
    static func makePdfDataMulti(
        filledWithSlotMarkers: String,
        signatureImages: [UIImage],
        isTurkishLayout: Bool = false
    ) -> Data? {
        guard !signatureImages.isEmpty, let regex = TurkeyRentalTermsSigSlotRegex.pattern else { return nil }
        let pageWidth: CGFloat = 612
        let margin: CGFloat = 40
        let textWidth = pageWidth - margin * 2
        let bodyFont = UIFont(name: "Helvetica", size: 9.5) ?? UIFont.systemFont(ofSize: 9.5)
        let attrs = pdfBodyAttributes(font: bodyFont, isTurkishLayout: isTurkishLayout)
        enum Piece {
            case text(String, CGFloat)
            case image(Int)
        }
        let nsFull = filledWithSlotMarkers as NSString
        let fullRange = NSRange(location: 0, length: nsFull.length)
        var pieces: [Piece] = []
        var contentHeight: CGFloat = margin
        var lastEnd = 0
        regex.enumerateMatches(in: filledWithSlotMarkers, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > lastEnd {
                let r = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let part = nsFull.substring(with: r)
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let h = measureTextHeight(part, width: textWidth, attributes: attrs, isTurkishLayout: isTurkishLayout)
                    pieces.append(.text(part, h))
                    contentHeight += h
                }
            }
            if match.numberOfRanges >= 2 {
                let idxStr = nsFull.substring(with: match.range(at: 1))
                if let idx = Int(idxStr), idx >= 0, idx < signatureImages.count {
                    pieces.append(.image(idx))
                    contentHeight += 64
                }
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsFull.length {
            let r = NSRange(location: lastEnd, length: nsFull.length - lastEnd)
            let part = nsFull.substring(with: r)
            if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let h = measureTextHeight(part, width: textWidth, attributes: attrs, isTurkishLayout: isTurkishLayout)
                pieces.append(.text(part, h))
                contentHeight += h
            }
        }
        contentHeight += margin
        let pageHeight = max(792, contentHeight)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "General rental terms",
            kCGPDFContextAuthor: "AracHasarKayit",
        ] as [String: Any]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { pdfCtx in
            pdfCtx.beginPage(withBounds: pageRect, pageInfo: [:])
            var y: CGFloat = margin
            for p in pieces {
                switch p {
                case let .text(str, h):
                    let ns = NSString(string: str)
                    let r = CGRect(x: margin, y: y, width: textWidth, height: h)
                    ns.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                    y += h
                case let .image(slotIdx):
                    let sig = signatureImages[slotIdx]
                    let targetH: CGFloat = 52
                    let scale = targetH / max(sig.size.height, 1)
                    let w = min(textWidth, sig.size.width * scale)
                    sig.draw(in: CGRect(x: margin, y: y, width: w, height: targetH))
                    y += 64
                }
            }
        }
    }

    private static func pdfBodyAttributes(font: UIFont, isTurkishLayout: Bool) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        if isTurkishLayout {
            p.lineSpacing = 4
            p.paragraphSpacing = 8
            p.paragraphSpacingBefore = 2
        } else {
            p.lineSpacing = 1
            p.paragraphSpacing = 3
        }
        return [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: p,
        ]
    }

    private static func measureTextHeight(
        _ part: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        isTurkishLayout: Bool
    ) -> CGFloat {
        let ns = NSString(string: part)
        let h = ceil(ns.boundingRect(
            with: CGSize(width: width, height: 50_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height)
        let bottomPad: CGFloat = isTurkishLayout ? 16 : 10
        return max(28, h + bottomPad)
    }

    static func isPdfDocumentData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46
    }

    /// Text / signature-slot segments in document order, matching `makePdfDataMulti` marker splits (for UI scroll sync).
    static func multiSignatureLayoutPieces(
        filledWithSlotMarkers: String,
        isTurkishLayout: Bool
    ) -> [TurkeyRentalTermsLayoutPiece] {
        _ = isTurkishLayout // Heights match PDF path; readable text view sizes itself.
        guard let regex = TurkeyRentalTermsSigSlotRegex.pattern else { return [] }
        var out: [TurkeyRentalTermsLayoutPiece] = []
        var idSeq = 0
        let nsFull = filledWithSlotMarkers as NSString
        let fullRange = NSRange(location: 0, length: nsFull.length)
        var lastEnd = 0
        regex.enumerateMatches(in: filledWithSlotMarkers, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > lastEnd {
                let r = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let part = nsFull.substring(with: r)
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(TurkeyRentalTermsLayoutPiece(id: idSeq, kind: .text(part)))
                    idSeq += 1
                }
            }
            if match.numberOfRanges >= 2 {
                let idxStr = nsFull.substring(with: match.range(at: 1))
                if let idx = Int(idxStr) {
                    out.append(TurkeyRentalTermsLayoutPiece(id: idSeq, kind: .signatureSlot(idx)))
                    idSeq += 1
                }
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsFull.length {
            let r = NSRange(location: lastEnd, length: nsFull.length - lastEnd)
            let part = nsFull.substring(with: r)
            if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(TurkeyRentalTermsLayoutPiece(id: idSeq, kind: .text(part)))
            }
        }
        return out
    }
}

/// One segment between / at `<<<SIG_n>>>` markers; used with ``TurkeyRentalTermsPlaceholders/multiSignatureLayoutPieces``.
struct TurkeyRentalTermsLayoutPiece: Identifiable {
    enum Kind {
        case text(String)
        case signatureSlot(Int)
    }
    let id: Int
    let kind: Kind
}

// MARK: - E-posta eki: genel kiralama koşulları PDF (Firestore’daki imza görseli ile)

enum TurkeyRentalTermsEmailAttachmentBuilder {

    static func makePdfDataForExit(_ exit: ExitIslemi, completion: @escaping (Data?) -> Void) {
        let lang = (exit.trRentalTermsLanguage ?? "tr").lowercased()
        let raw = TurkeyRentalTermsPlaceholders.loadBundledTermsText(preferredEnglish: lang == "en")
        guard !raw.isEmpty else {
            completion(nil)
            return
        }
        let ctx = TurkeyRentalTermsFillContext(
            customerFirstName: exit.customerFirstName ?? "",
            customerLastName: exit.customerLastName ?? "",
            testDriverFirstName: exit.testDriverFirstName,
            testDriverLastName: exit.testDriverLastName,
            agreementDate: exit.exitTarihi,
            localeIdentifier: TurkeyRentalTermsFillContext.localeForTermsLanguageCode(lang)
        )
        func assemble(sig: UIImage?) {
            DispatchQueue.global(qos: .userInitiated).async {
                let filled = TurkeyRentalTermsPlaceholders.apply(
                    to: raw,
                    context: ctx,
                    embedSignatureMarker: sig != nil
                )
                let data = TurkeyRentalTermsPlaceholders.makePdfData(
                    filledWithMarkers: filled,
                    signatureImage: sig,
                    isTurkishLayout: lang != "en"
                )
                DispatchQueue.main.async { completion(data) }
            }
        }
        if let u = exit.trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            if u.lowercased().hasSuffix(".pdf") || u.contains("tr_rental_terms_signed") {
                StorageImageLoader.shared.loadData(from: u) { data in
                    if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                        DispatchQueue.main.async { completion(data) }
                    } else {
                        assemble(sig: nil)
                    }
                }
            } else {
                StorageImageLoader.shared.loadImage(from: u) { img in
                    assemble(sig: img)
                }
            }
        } else {
            assemble(sig: nil)
        }
    }

    static func makePdfDataForIade(_ iade: IadeIslemi, completion: @escaping (Data?) -> Void) {
        let lang = (iade.trRentalTermsLanguage ?? "tr").lowercased()
        let raw = TurkeyRentalTermsPlaceholders.loadBundledTermsText(preferredEnglish: lang == "en")
        guard !raw.isEmpty else {
            completion(nil)
            return
        }
        let ctx = TurkeyRentalTermsFillContext(
            customerFirstName: iade.customerFirstName ?? "",
            customerLastName: iade.customerLastName ?? "",
            testDriverFirstName: iade.testDriverFirstName,
            testDriverLastName: iade.testDriverLastName,
            agreementDate: iade.iadeTarihi,
            localeIdentifier: TurkeyRentalTermsFillContext.localeForTermsLanguageCode(lang)
        )
        func assemble(sig: UIImage?) {
            DispatchQueue.global(qos: .userInitiated).async {
                let filled = TurkeyRentalTermsPlaceholders.apply(
                    to: raw,
                    context: ctx,
                    embedSignatureMarker: sig != nil
                )
                let data = TurkeyRentalTermsPlaceholders.makePdfData(
                    filledWithMarkers: filled,
                    signatureImage: sig,
                    isTurkishLayout: lang != "en"
                )
                DispatchQueue.main.async { completion(data) }
            }
        }
        if let u = iade.trRentalTermsSignatureURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            if u.lowercased().hasSuffix(".pdf") || u.contains("tr_rental_terms_signed") {
                StorageImageLoader.shared.loadData(from: u) { data in
                    if let data, TurkeyRentalTermsPlaceholders.isPdfDocumentData(data) {
                        DispatchQueue.main.async { completion(data) }
                    } else {
                        assemble(sig: nil)
                    }
                }
            } else {
                StorageImageLoader.shared.loadImage(from: u) { img in
                    assemble(sig: img)
                }
            }
        } else {
            assemble(sig: nil)
        }
    }
}
