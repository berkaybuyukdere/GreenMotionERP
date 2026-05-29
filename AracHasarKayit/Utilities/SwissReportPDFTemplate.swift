import UIKit

/// Green Motion branded report template for Switzerland (CH).
/// Faithful reproduction of the official HTML templates
/// (checkout = blue, return = orange, damage = red), with a dynamic
/// branch / franchise name (no hardcoded "Zürich").
/// Mirrors the web `swissPdfTemplate.js` so app + web produce the same document.
enum SwissReportPDFTemplate {

    // MARK: Geometry
    static let pageW: CGFloat = 595
    static let pageH: CGFloat = 842
    static let margin: CGFloat = 40
    static var contentW: CGFloat { pageW - margin * 2 }
    static let footerCopyright = "© Green Motion — Confidential. Unauthorized reproduction prohibited."

    // MARK: Palette
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
    static var white: UIColor { .white }
    static var gray50: UIColor { rgb(248, 249, 250) }
    static var gray100: UIColor { rgb(241, 243, 245) }
    static var gray200: UIColor { rgb(233, 236, 239) }
    static var gray300: UIColor { rgb(222, 226, 230) }
    static var gray400: UIColor { rgb(173, 181, 189) }
    static var gray500: UIColor { rgb(108, 117, 125) }
    static var gray700: UIColor { rgb(52, 58, 64) }
    static var gray900: UIColor { rgb(33, 37, 41) }
    static var accentBlue: UIColor { rgb(28, 109, 235) }
    static var accentBlueDark: UIColor { rgb(20, 81, 176) }
    static var green: UIColor { rgb(45, 139, 87) }
    static var orange: UIColor { rgb(192, 86, 42) }
    static var red: UIColor { rgb(192, 48, 43) }
    static var redLight: UIColor { rgb(254, 232, 232) }
    static var border: UIColor { rgb(221, 225, 231) }

    enum Kind {
        case checkout, returnReport, damage
        var accent: UIColor {
            switch self {
            case .checkout: return SwissReportPDFTemplate.accentBlue
            case .returnReport: return SwissReportPDFTemplate.orange
            case .damage: return SwissReportPDFTemplate.red
            }
        }
        var accentDark: UIColor {
            switch self {
            case .checkout: return SwissReportPDFTemplate.accentBlueDark
            default: return accent
            }
        }
        var badge: String {
            switch self {
            case .checkout: return "CHECK OUT REPORT"
            case .returnReport: return "RETURN REPORT"
            case .damage: return "DAMAGE REPORT"
            }
        }
    }

    enum CellStyle { case plain, accent, large, damage, mono }
    struct Cell { let label: String; let value: String; let style: CellStyle
        init(_ label: String, _ value: String, _ style: CellStyle = .plain) {
            self.label = label; self.value = value; self.style = style
        }
    }

    // MARK: Fonts
    private static func sans(_ size: CGFloat, bold: Bool = false) -> UIFont {
        bold ? (UIFont(name: "Helvetica-Bold", size: size) ?? .boldSystemFont(ofSize: size))
             : (UIFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size))
    }
    private static func mono(_ size: CGFloat, bold: Bool = false) -> UIFont {
        bold ? (UIFont(name: "Courier-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold))
             : (UIFont(name: "Courier", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular))
    }

    private static func dateFmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter(); f.dateFormat = pattern; return f
    }

    // MARK: Branch resolution
    static func branchName(franchiseId: String?, explicit: String?) -> String {
        if let e = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { return e }
        let id = (franchiseId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let map: [String: String] = [
            "CH": "Zürich", "CH_ZURICH": "Zürich", "CH_ZUERICH": "Zürich",
            "CH_GENEVA": "Geneva", "CH_BASEL": "Basel", "CH_BERN": "Bern"
        ]
        if let m = map[id] { return m }
        if id.hasPrefix("CH_") {
            let tail = id.dropFirst(3).replacingOccurrences(of: "_", with: " ").lowercased()
            return tail.capitalized
        }
        return "Switzerland"
    }

    // MARK: Text helpers
    private static func draw(_ text: String, x: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        text.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }
    private static func drawRight(_ text: String, rightX: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let w = (text as NSString).size(withAttributes: attrs).width
        text.draw(at: CGPoint(x: rightX - w, y: y), withAttributes: attrs)
    }
    private static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func fillRect(_ rect: CGRect, _ color: UIColor, radius: CGFloat = 0) {
        color.setFill()
        if radius > 0 { UIBezierPath(roundedRect: rect, cornerRadius: radius).fill() }
        else { UIRectFill(rect) }
    }
    private static func strokeRect(_ rect: CGRect, _ color: UIColor, width: CGFloat = 0.5, radius: CGFloat = 0) {
        color.setStroke()
        let p = radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)
        p.lineWidth = width
        p.stroke()
    }
    private static func line(_ from: CGPoint, _ to: CGPoint, _ color: UIColor, width: CGFloat = 0.5) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width)
        ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
    }

    // MARK: Header
    @discardableResult
    private static func drawHeader(kind: Kind, branch: String,
                                   titlePre: String, titleStrong: String,
                                   plate: String?, compact: Bool) -> CGFloat {
        let top = margin
        // logo circle
        let cx = margin + 14, cy = top + 14, r: CGFloat = 14
        fillRect(CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), green, radius: r)
        let gm = "GM"
        let gmFont = mono(13, bold: true)
        let gmW = textWidth(gm, font: gmFont)
        draw(gm, x: cx - gmW / 2, y: cy - 8, font: gmFont, color: white)

        draw("Green Motion", x: margin + 34, y: top + 4, font: sans(15, bold: true), color: gray900)
        draw("CAR RENTAL · \(branch.uppercased())", x: margin + 34, y: top + 22, font: mono(8), color: gray500)

        drawRight(kind.badge, rightX: pageW - margin, y: top + 2, font: mono(8, bold: true), color: kind.accentDark)

        if compact, let plate = plate, !plate.isEmpty {
            drawRight(plate, rightX: pageW - margin, y: top + 14, font: sans(20, bold: true), color: kind.accent)
        } else if !compact {
            let preFont = sans(22), strongFont = sans(22, bold: true)
            let strongW = textWidth(titleStrong, font: strongFont)
            let titleY = top + 14
            drawRight(titlePre, rightX: pageW - margin - strongW - 4, y: titleY, font: preFont, color: gray900)
            drawRight(titleStrong, rightX: pageW - margin, y: titleY, font: strongFont, color: kind.accent)
        }

        let lineY = top + 40
        line(CGPoint(x: margin, y: lineY), CGPoint(x: pageW - margin, y: lineY), kind.accent, width: 1.6)
        return lineY + 16
    }

    // MARK: Section label
    @discardableResult
    private static func sectionLabel(_ text: String, y: CGFloat) -> CGFloat {
        draw(text.uppercased(), x: margin, y: y, font: mono(7.5, bold: true), color: gray400)
        line(CGPoint(x: margin, y: y + 13), CGPoint(x: margin + contentW, y: y + 13), gray200, width: 0.5)
        return y + 20
    }

    // MARK: Info grid
    @discardableResult
    private static func infoGrid(_ cells: [Cell], cols: Int, y: CGFloat) -> CGFloat {
        let rows = Int(ceil(Double(cells.count) / Double(cols)))
        let cellW = contentW / CGFloat(cols)
        let rowH: CGFloat = 44
        let gridH = CGFloat(rows) * rowH
        let rect = CGRect(x: margin, y: y, width: contentW, height: gridH)
        fillRect(rect, white, radius: 4)
        strokeRect(rect, border, width: 0.5, radius: 4)
        for c in 1..<max(cols, 1) {
            let lx = margin + CGFloat(c) * cellW
            line(CGPoint(x: lx, y: y), CGPoint(x: lx, y: y + gridH), border, width: 0.4)
        }
        if rows > 1 {
            for rr in 1..<rows {
                let ly = y + CGFloat(rr) * rowH
                line(CGPoint(x: margin, y: ly), CGPoint(x: margin + contentW, y: ly), border, width: 0.4)
            }
        }
        for (i, cell) in cells.enumerated() {
            let c = i % cols, rr = i / cols
            let cellX = margin + CGFloat(c) * cellW + 9
            let cellY = y + CGFloat(rr) * rowH
            draw(cell.label.uppercased(), x: cellX, y: cellY + 9, font: mono(6.5, bold: true), color: gray400)
            let valFont: UIFont
            let valColor: UIColor
            switch cell.style {
            case .accent: valFont = mono(13, bold: true); valColor = accentBlue
            case .damage: valFont = mono(13, bold: true); valColor = red
            case .large: valFont = sans(13, bold: true); valColor = gray900
            case .mono: valFont = mono(11, bold: true); valColor = gray900
            case .plain: valFont = sans(11); valColor = gray900
            }
            let maxW = cellW - 16
            let value = cell.value.isEmpty ? "N/A" : cell.value
            (value as NSString).draw(
                in: CGRect(x: cellX, y: cellY + 22, width: maxW, height: 18),
                withAttributes: [.font: valFont, .foregroundColor: valColor]
            )
        }
        return y + gridH + 16
    }

    // MARK: Signature
    @discardableResult
    private static func signatureBox(signature: UIImage?, caption: String, y: CGFloat) -> CGFloat {
        var yy = sectionLabel("Customer Signature", y: y)
        let boxH: CGFloat = 86
        let rect = CGRect(x: margin, y: yy, width: contentW, height: boxH)
        fillRect(rect, gray50, radius: 4)
        strokeRect(rect, border, width: 0.5, radius: 4)
        if let sig = signature {
            let inset = rect.insetBy(dx: 14, dy: 12)
            let target = aspectFit(imageSize: sig.size, in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: boxH - 34))
            UIGraphicsGetCurrentContext()?.interpolationQuality = .high
            sig.draw(in: target)
        } else {
            let wm = "SIGNED"
            let f = mono(30, bold: true)
            let w = textWidth(wm, font: f)
            draw(wm, x: rect.midX - w / 2, y: rect.midY - 18, font: f, color: gray200)
        }
        line(CGPoint(x: rect.minX + contentW * 0.1, y: rect.maxY - 18),
             CGPoint(x: rect.minX + contentW * 0.9, y: rect.maxY - 18), gray300, width: 0.5)
        let cf = mono(7)
        let cw = textWidth(caption.uppercased(), font: cf)
        draw(caption.uppercased(), x: rect.midX - cw / 2, y: rect.maxY - 12, font: cf, color: gray400)
        yy += boxH + 16
        return yy
    }

    // MARK: Photo grid
    private struct PhotoMetrics { let gap: CGFloat; let cardW: CGFloat; let headerH: CGFloat; let imgH: CGFloat; var cardH: CGFloat { headerH + imgH } }
    private static func photoMetrics() -> PhotoMetrics {
        let gap: CGFloat = 8
        let cardW = (contentW - gap) / 2
        let headerH: CGFloat = 16
        let imgH = cardW * 0.7
        return PhotoMetrics(gap: gap, cardW: cardW, headerH: headerH, imgH: imgH)
    }

    private static func drawPhotoCard(x: CGFloat, y: CGFloat, m: PhotoMetrics,
                                      number: String, date: String, image: UIImage?, danger: Bool) {
        let cardRect = CGRect(x: x, y: y, width: m.cardW, height: m.cardH)
        fillRect(cardRect, danger ? rgb(255, 245, 245) : gray100, radius: 4)
        strokeRect(cardRect, danger ? red : border, width: danger ? 1.0 : 0.5, radius: 4)
        // header bar
        let headerRect = CGRect(x: x, y: y, width: m.cardW, height: m.headerH)
        fillRect(headerRect, danger ? redLight : gray100)
        line(CGPoint(x: x, y: y + m.headerH), CGPoint(x: x + m.cardW, y: y + m.headerH), border, width: 0.4)
        draw(number.uppercased(), x: x + 5, y: y + 4, font: mono(6, bold: true), color: danger ? red : gray500)
        drawRight(date, rightX: x + m.cardW - 5, y: y + 4, font: mono(6), color: gray400)
        // image
        if let img = image {
            let area = CGRect(x: x, y: y + m.headerH, width: m.cardW, height: m.imgH)
            let target = aspectFit(imageSize: img.size, in: area)
            UIGraphicsGetCurrentContext()?.interpolationQuality = .high
            img.draw(in: target)
        }
    }

    private static func aspectFit(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let a = imageSize.width / imageSize.height
        var w = rect.width, h = rect.height
        if a > rect.width / rect.height { h = rect.width / a } else { w = rect.height * a }
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    // MARK: Footer (live, per page)
    private static func drawFooter(pageIndex: Int, generatedNote: String?) {
        let fy = pageH - 28
        line(CGPoint(x: margin, y: fy), CGPoint(x: pageW - margin, y: fy), gray200, width: 0.5)
        draw(footerCopyright, x: margin, y: fy + 5, font: mono(6), color: gray400)
        if let note = generatedNote {
            let f = mono(6)
            let w = textWidth(note, font: f)
            draw(note, x: pageW / 2 - w / 2, y: fy + 5, font: f, color: gray400)
        }
        drawRight("PAGE \(pageIndex)", rightX: pageW - margin, y: fy + 5, font: mono(6), color: gray400)
    }

    // MARK: - Public: Checkout / Return
    static func renderHandover(
        kind: Kind,
        branch: String,
        plate: String,
        vehicle: String,
        dateText: String,
        fuelText: String,
        photoCount: Int,
        customerName: String,
        customerEmail: String,
        signature: UIImage?,
        photos: [UIImage],
        photoStampDate: String,
        signatureCaption: String
    ) -> Data {
        let titlePre = kind == .checkout ? "Vehicle" : "Vehicle"
        let titleStrong = kind == .checkout ? "Handover" : "Return"
        let dateLabel = kind == .checkout ? "Check Out Date" : "Return Date & Time"
        let photosLabel = kind == .checkout ? "Vehicle Condition Photos" : "Return Condition Photos"

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { context in
            var pageIndex = 0
            func newPage(compact: Bool) -> CGFloat {
                if pageIndex > 0 { drawFooter(pageIndex: pageIndex, generatedNote: nil) }
                context.beginPage(); pageIndex += 1
                return drawHeader(kind: kind, branch: branch,
                                  titlePre: titlePre, titleStrong: titleStrong,
                                  plate: plate, compact: compact)
            }

            var y = newPage(compact: false)
            y = sectionLabel("Vehicle Details", y: y)
            y = infoGrid([
                Cell("License Plate", plate, .accent),
                Cell("Make & Model", vehicle, .large),
                Cell(dateLabel, dateText),
                Cell("Fuel Level", fuelText),
                Cell("Total Photos", "\(photoCount)", .large)
            ], cols: 5, y: y)

            y = sectionLabel("Customer Information", y: y)
            y = infoGrid([
                Cell("Customer Name", customerName.isEmpty ? "Not provided" : customerName, .large),
                Cell("Email Address", customerEmail.isEmpty ? "Not provided" : customerEmail),
                Cell("License Plate", plate, .accent)
            ], cols: 3, y: y)

            if signature != nil {
                y = signatureBox(signature: signature, caption: signatureCaption, y: y)
            }

            // photos
            let m = photoMetrics()
            var idx = 0
            var printed = 0
            while idx < photos.count {
                if y + m.cardH > pageH - 44 { y = newPage(compact: true) }
                if printed % 8 == 0 {
                    if y + 20 + m.cardH > pageH - 44 { y = newPage(compact: true) }
                    let from = idx + 1, to = min(idx + 8, photos.count)
                    let title = photos.count <= 8 ? photosLabel : "\(photosLabel) (\(from)–\(to))"
                    y = sectionLabel(title, y: y)
                }
                let rowCount = min(2, photos.count - idx)
                for c in 0..<rowCount {
                    let i = idx + c
                    let x = margin + CGFloat(c) * (m.cardW + m.gap)
                    drawPhotoCard(x: x, y: y, m: m,
                                  number: "PHOTO \(String(format: "%02d", i + 1))",
                                  date: photoStampDate, image: photos[i], danger: false)
                }
                idx += rowCount; printed += rowCount
                y += m.cardH + 8
            }
            drawFooter(pageIndex: pageIndex, generatedNote: nil)
        }
    }

    // MARK: - Public: Damage
    static func renderDamage(
        branch: String,
        plate: String,
        make: String,
        model: String,
        resLabel: String,
        resCode: String,
        handoverDate: Date,
        returnDate: Date,
        damageLocation: String,
        damageType: String,
        photos: [UIImage]
    ) -> Data {
        let kind = Kind.damage
        let df = dateFmt("dd.MM.yyyy")
        let generated = "Generated \(df.string(from: Date())) · Green Motion \(branch)"
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { context in
            var pageIndex = 0
            func newPage(compact: Bool) -> CGFloat {
                if pageIndex > 0 { drawFooter(pageIndex: pageIndex, generatedNote: generated) }
                context.beginPage(); pageIndex += 1
                return drawHeader(kind: kind, branch: branch,
                                  titlePre: "Damage", titleStrong: "Assessment",
                                  plate: plate, compact: compact)
            }

            var y = newPage(compact: false)
            y = sectionLabel("Vehicle Details", y: y)
            y = infoGrid([
                Cell("Make", make.isEmpty ? "—" : make, .large),
                Cell("Model", model.isEmpty ? "—" : model, .large),
                Cell("Plate", plate, .accent),
                Cell(resLabel, resCode.isEmpty ? "—" : resCode, .mono),
                Cell("Handover Date", df.string(from: handoverDate)),
                Cell("Return Date", df.string(from: returnDate), .damage)
            ], cols: 6, y: y)

            y = sectionLabel("Report Details", y: y)
            y = infoGrid([
                Cell("Location", branch, .large),
                Cell("Report Status", "Damage Detected", .damage),
                Cell("Generated", df.string(from: Date()))
            ], cols: 3, y: y)

            y = sectionLabel("Damage Summary", y: y)
            let headH: CGFloat = 18, rowH: CGFloat = 26
            let rect = CGRect(x: margin, y: y, width: contentW, height: headH + rowH)
            fillRect(rect, white, radius: 4)
            strokeRect(rect, border, width: 0.5, radius: 4)
            fillRect(CGRect(x: margin, y: y, width: contentW, height: headH), gray100)
            let colRefW: CGFloat = 60, colLocW: CGFloat = 150, colTypeW: CGFloat = 120
            let colDetW: CGFloat = 90
            var hx = margin + 8
            draw("REF", x: hx, y: y + 5, font: mono(6.5, bold: true), color: gray500); hx += colRefW
            draw("LOCATION", x: hx, y: y + 5, font: mono(6.5, bold: true), color: gray500); hx += colLocW
            draw("TYPE", x: hx, y: y + 5, font: mono(6.5, bold: true), color: gray500); hx += colTypeW
            draw("DETECTED", x: hx, y: y + 5, font: mono(6.5, bold: true), color: gray500)
            var rx = margin + 8
            let ry = y + headH + 6
            draw("DMG-01", x: rx, y: ry, font: mono(7, bold: true), color: gray500); rx += colRefW
            (damageLocation.isEmpty ? "—" : damageLocation).draw(
                in: CGRect(x: rx, y: ry, width: colLocW - 6, height: 14),
                withAttributes: [.font: sans(8), .foregroundColor: gray700]); rx += colLocW
            (damageType.isEmpty ? "Damage" : damageType).draw(
                in: CGRect(x: rx, y: ry, width: colTypeW - 6, height: 14),
                withAttributes: [.font: sans(8), .foregroundColor: gray700]); rx += colTypeW
            draw(df.string(from: returnDate), x: rx, y: ry, font: sans(8), color: gray700)
            y += headH + rowH + 16

            if !photos.isEmpty {
                let m = photoMetrics()
                var idx = 0
                var printed = 0
                let stamp = df.string(from: returnDate)
                while idx < photos.count {
                    if y + m.cardH > pageH - 44 { y = newPage(compact: true) }
                    if printed % 8 == 0 {
                        if y + 20 + m.cardH > pageH - 44 { y = newPage(compact: true) }
                        let from = idx + 1, to = min(idx + 8, photos.count)
                        let title = photos.count <= 8
                            ? "Damage Photographs"
                            : "Damage Photographs (\(from)–\(to))"
                        y = sectionLabel(title, y: y)
                    }
                    let rowCount = min(2, photos.count - idx)
                    for c in 0..<rowCount {
                        let i = idx + c
                        let x = margin + CGFloat(c) * (m.cardW + m.gap)
                        drawPhotoCard(x: x, y: y, m: m,
                                      number: "PHOTO \(String(format: "%02d", i + 1))",
                                      date: stamp, image: photos[i], danger: true)
                    }
                    idx += rowCount
                    printed += rowCount
                    y += m.cardH + 8
                }
            }

            drawFooter(pageIndex: pageIndex, generatedNote: generated)
        }
    }
}
