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
    static let footerCopyright = "© Confidential. Unauthorized reproduction prohibited."

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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = pattern
        return f
    }

    /// Draws value text without clipping the year (scales font down to fit cell width).
    private static func drawFittedValue(
        _ text: String,
        in rect: CGRect,
        baseFont: UIFont,
        color: UIColor,
        minPointSize: CGFloat = 7
    ) {
        let value = text.isEmpty ? "N/A" : text
        var size = baseFont.pointSize
        while size >= minPointSize {
            let font = baseFont.withSize(size)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let bounds = (value as NSString).boundingRect(
                with: CGSize(width: rect.width, height: rect.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            if bounds.width <= rect.width, bounds.height <= rect.height {
                (value as NSString).draw(in: rect, withAttributes: attrs)
                return
            }
            size -= 0.5
        }
        let font = baseFont.withSize(minPointSize)
        (value as NSString).draw(
            in: rect,
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }

    // MARK: Branch resolution
    static func branchName(franchiseId: String?, explicit: String?) -> String {
        let id = (franchiseId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if id.hasPrefix("DE") {
            return germanyDisplayName(franchiseId: id, explicit: explicit)
        }
        if id.hasPrefix("UK") || id.hasPrefix("GB") {
            return ukDisplayName(franchiseId: id, explicit: explicit)
        }
        if let e = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { return e }
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

    /// Germany PDFs / emails use this label only (no Green Motion branding).
    static func germanyDisplayName(franchiseId: String, explicit: String?) -> String {
        if let e = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            let lower = e.lowercased()
            if !lower.contains("green motion") { return e }
        }
        let id = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if id.contains("DUSSELDORF") || id == "DE" || id.hasPrefix("DE_") {
            return "Germany Düsseldorf"
        }
        return "Germany Düsseldorf"
    }

    static func ukDisplayName(franchiseId: String, explicit: String?) -> String {
        if let e = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            let lower = e.lowercased()
            if !lower.contains("green motion") { return e }
        }
        if franchiseId.contains("_") {
            let tail = franchiseId.split(separator: "_", maxSplits: 1).dropFirst().first
                .map { String($0).replacingOccurrences(of: "_", with: " ").capitalized }
            if let tail, !tail.isEmpty { return tail }
        }
        return "United Kingdom"
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
        draw(branch, x: margin, y: top + 8, font: mono(8), color: gray500)

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

    @discardableResult
    private static func drawDamageHeader(branch: String, plate: String?, compact: Bool) -> CGFloat {
        let top = margin
        // Palantir-style damage alert chip
        let iconSize: CGFloat = 22
        let iconRect = CGRect(x: margin, y: top + 2, width: iconSize, height: iconSize)
        fillRect(iconRect, redLight, radius: 4)
        strokeRect(iconRect, red, width: 0.8, radius: 4)
        draw("!", x: iconRect.midX - 3, y: iconRect.minY + 4, font: sans(14, bold: true), color: red)

        draw(branch, x: margin + iconSize + 8, y: top + 8, font: mono(8), color: gray500)

        if compact, let plate = plate, !plate.isEmpty {
            drawRight(plate, rightX: pageW - margin, y: top + 14, font: sans(20, bold: true), color: red)
        } else {
            drawRight("Damage Report", rightX: pageW - margin, y: top + 14, font: sans(20, bold: true), color: gray900)
        }

        let lineY = top + 40
        line(CGPoint(x: margin, y: lineY), CGPoint(x: pageW - margin, y: lineY), red, width: 1.6)
        return lineY + 20
    }

    // MARK: Section label
    @discardableResult
    private static func sectionLabel(_ text: String, y: CGFloat, compact: Bool = false) -> CGFloat {
        draw(text.uppercased(), x: margin, y: y, font: mono(7.5, bold: true), color: gray400)
        line(CGPoint(x: margin, y: y + 13), CGPoint(x: margin + contentW, y: y + 13), gray200, width: 0.5)
        return y + (compact ? 16 : 20)
    }

    // MARK: Info grid
    @discardableResult
    private static func infoGrid(_ cells: [Cell], cols: Int, y: CGFloat, compact: Bool = false) -> CGFloat {
        let rows = Int(ceil(Double(cells.count) / Double(cols)))
        let cellW = contentW / CGFloat(cols)
        let rowH: CGFloat = compact ? 38 : 44
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
            drawFittedValue(
                cell.value,
                in: CGRect(x: cellX, y: cellY + 20, width: maxW, height: 20),
                baseFont: valFont,
                color: valColor
            )
        }
        return y + gridH + (compact ? 10 : 16)
    }

    // MARK: Signature
    @discardableResult
    private static func signatureBox(signature: UIImage?, caption: String, y: CGFloat, compact: Bool = false) -> CGFloat {
        var yy = sectionLabel("Customer Signature", y: y, compact: compact)
        let boxH: CGFloat = compact ? 74 : 86
        let rect = CGRect(x: margin, y: yy, width: contentW, height: boxH)
        fillRect(rect, gray50, radius: 4)
        strokeRect(rect, border, width: 0.5, radius: 4)
        if let sig = signature {
            let padX: CGFloat = compact ? 12 : 14
            let padY: CGFloat = compact ? 10 : 12
            let inset = rect.insetBy(dx: padX, dy: padY)
            let target = aspectFit(imageSize: sig.size, in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: boxH - (compact ? 30 : 34)))
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
        yy += boxH + (compact ? 6 : 16)
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

    /// 2×2 grid sized to keep four condition photos on one page (Germany reports).
    private static func photoMetricsFourGrid() -> PhotoMetrics {
        let gap: CGFloat = 12
        let cardW = (contentW - gap) / 2
        let headerH: CGFloat = 12
        let imgH = cardW * 0.76
        return PhotoMetrics(gap: gap, cardW: cardW, headerH: headerH, imgH: imgH)
    }

    private static func drawPhotoCard(x: CGFloat, y: CGFloat, m: PhotoMetrics,
                                      number: String, date: String, image: UIImage?, danger: Bool,
                                      imageInset: CGFloat = 0,
                                      stampTime: String? = nil,
                                      stampBlue: Bool = false) {
        let cardRect = CGRect(x: x, y: y, width: m.cardW, height: m.cardH)
        fillRect(cardRect, white, radius: 4)
        strokeRect(cardRect, danger ? red : border, width: danger ? 1.0 : 0.5, radius: 4)
        // header bar
        let headerRect = CGRect(x: x, y: y, width: m.cardW, height: m.headerH)
        fillRect(headerRect, danger ? redLight : gray100)
        line(CGPoint(x: x, y: y + m.headerH), CGPoint(x: x + m.cardW, y: y + m.headerH), border, width: 0.4)
        let labelText = number.uppercased()
        draw(labelText, x: x + 6, y: y + 3, font: mono(6, bold: true), color: danger ? red : gray500)
        let stampText: String
        if stampBlue, let t = stampTime, !t.isEmpty {
            stampText = "\(date) \(t)"
        } else {
            stampText = date
        }
        // Right-align full date so 4-digit years are never clipped (e.g. 25.06.2026).
        drawRight(
            stampText,
            rightX: x + m.cardW - 6,
            y: y + 3,
            font: mono(5.5),
            color: stampBlue ? accentBlue : gray400
        )
        // image — aspect-fit within frame (never stretch)
        let imageArea = CGRect(x: x, y: y + m.headerH, width: m.cardW, height: m.imgH)
            .insetBy(dx: imageInset, dy: imageInset)
        fillRect(imageArea, danger ? rgb(255, 245, 245) : gray50, radius: imageInset > 0 ? 3 : 0)
        if let img = image {
            let inner = imageArea.insetBy(dx: 4, dy: 4)
            let target = aspectFit(imageSize: img.size, in: inner)
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
        photoHandoverDate: String,
        photoReturnDate: String,
        photoHandoverTime: String? = nil,
        photoReturnTime: String? = nil,
        photoStampBlue: Bool = false,
        signatureCaption: String,
        photosOnFirstPage: Int? = nil
    ) -> Data {
        let titlePre = kind == .checkout ? "Vehicle" : "Vehicle"
        let titleStrong = kind == .checkout ? "Handover" : "Return"
        let dateLabel = "Date"
        let photosLabel = "Condition Photos"
        let compactLayout = photosOnFirstPage == 4

        func photoStamp(for index: Int) -> (label: String, date: String, time: String?) {
            let dateStr = kind == .checkout ? photoHandoverDate : photoReturnDate
            let timeStr = kind == .checkout ? photoHandoverTime : photoReturnTime
            return (ProcessPhotoStampLabels.processPhotoIndexLabel(index), dateStr, timeStr)
        }

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
            y = sectionLabel("Vehicle Details", y: y, compact: compactLayout)
            y = infoGrid([
                Cell("License Plate", plate, .accent),
                Cell("Make & Model", vehicle, .large),
                Cell(dateLabel, dateText),
                Cell("Fuel Level", fuelText),
                Cell("Total Photos", "\(photoCount)", .large)
            ], cols: 5, y: y, compact: compactLayout)

            y = sectionLabel("Customer Information", y: y, compact: compactLayout)
            y = infoGrid([
                Cell("Customer Name", customerName.isEmpty ? "Not provided" : customerName, .large),
                Cell("Email Address", customerEmail.isEmpty ? "Not provided" : customerEmail),
                Cell("License Plate", plate, .accent)
            ], cols: 3, y: y, compact: compactLayout)

            if signature != nil {
                y = signatureBox(signature: signature, caption: signatureCaption, y: y, compact: compactLayout)
            }

            // photos — Germany: signature then 2×2 grid on the same page with tight spacing
            var idx = 0
            if photosOnFirstPage == 4, !photos.isEmpty {
                let m4 = photoMetricsFourGrid()
                let firstChunk = Array(photos.prefix(4))
                let photoBlockH = m4.cardH * 2 + 10
                let photosSectionH: CGFloat = compactLayout ? 14 : 20
                if y + photosSectionH + photoBlockH > pageH - 44 {
                    y = newPage(compact: true) + 4
                }
                y = sectionLabel(photosLabel, y: y, compact: true)
                for row in 0..<2 {
                    for col in 0..<2 {
                        let i = row * 2 + col
                        guard i < firstChunk.count else { continue }
                        let stamp = photoStamp(for: i)
                        let x = margin + CGFloat(col) * (m4.cardW + m4.gap)
                        drawPhotoCard(
                            x: x,
                            y: y,
                            m: m4,
                            number: stamp.label,
                            date: stamp.date,
                            image: firstChunk[i],
                            danger: false,
                            imageInset: 5,
                            stampTime: stamp.time,
                            stampBlue: photoStampBlue
                        )
                    }
                    y += m4.cardH + 10
                }
                idx = firstChunk.count
            }

            let m = photoMetrics()
            var printed = 0
            while idx < photos.count {
                if y + m.cardH > pageH - 44 { y = newPage(compact: true) + 4 }
                if printed % 8 == 0 {
                    if y + 24 + m.cardH > pageH - 44 { y = newPage(compact: true) + 4 }
                    let from = idx + 1, to = min(idx + 8, photos.count)
                    let title = photos.count <= 8 ? photosLabel : "\(photosLabel) (\(from)–\(to))"
                    y = sectionLabel(title, y: y)
                }
                let rowCount = min(2, photos.count - idx)
                for c in 0..<rowCount {
                    let i = idx + c
                    let stamp = photoStamp(for: i)
                    let x = margin + CGFloat(c) * (m.cardW + m.gap)
                    drawPhotoCard(x: x, y: y, m: m,
                                  number: stamp.label,
                                  date: stamp.date, image: photos[i], danger: false,
                                  stampTime: stamp.time,
                                  stampBlue: photoStampBlue)
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
        _ = damageLocation
        _ = damageType
        // Full 4-digit year; drawFittedValue scales font to fit narrow grid cells.
        let dfFull = dateFmt("dd.MM.yyyy")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { context in
            var pageIndex = 0
            func newPage(compact: Bool) -> CGFloat {
                if pageIndex > 0 { drawFooter(pageIndex: pageIndex, generatedNote: nil) }
                context.beginPage(); pageIndex += 1
                return drawDamageHeader(branch: branch, plate: plate, compact: compact)
            }

            var y = newPage(compact: false)
            y = sectionLabel("Vehicle Details", y: y)
            y = infoGrid([
                Cell("Make", make.isEmpty ? "—" : make, .large),
                Cell("Model", model.isEmpty ? "—" : model, .large),
                Cell("Plate", plate, .accent),
                Cell(resLabel, resCode.isEmpty ? "—" : resCode, .mono),
                Cell("Handover Date", dfFull.string(from: handoverDate)),
                Cell("Date", dfFull.string(from: returnDate), .damage)
            ], cols: 6, y: y)

            y = sectionLabel("Report Details", y: y)
            y = infoGrid([
                Cell("Location", branch, .large),
                Cell("Report Status", "Damage Detected", .damage)
            ], cols: 2, y: y)

            if !photos.isEmpty {
                let m = photoMetrics()
                var idx = 0
                var printed = 0
                while idx < photos.count {
                    if y + m.cardH > pageH - 44 { y = newPage(compact: true) + 4 }
                    if printed % 8 == 0 {
                        if y + 24 + m.cardH > pageH - 44 { y = newPage(compact: true) + 4 }
                        let from = idx + 1, to = min(idx + 8, photos.count)
                        let title = photos.count <= 8
                            ? "Damage Photographs"
                            : "Damage Photographs (\(from)–\(to))"
                        y = sectionLabel(title, y: y)
                    }
                    let rowCount = min(2, photos.count - idx)
                    for c in 0..<rowCount {
                        let i = idx + c
                        let isHandover = i == 0
                        let stampDate = isHandover ? handoverDate : returnDate
                        let stampLabel = isHandover ? "HANDOVER" : "RETURN"
                        let x = margin + CGFloat(c) * (m.cardW + m.gap)
                        drawPhotoCard(x: x, y: y, m: m,
                                      number: stampLabel,
                                      date: dfFull.string(from: stampDate), image: photos[i], danger: true)
                    }
                    idx += rowCount
                    printed += rowCount
                    y += m.cardH + 8
                }
            }

            drawFooter(pageIndex: pageIndex, generatedNote: nil)
        }
    }
}
