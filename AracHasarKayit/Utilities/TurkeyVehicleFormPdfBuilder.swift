import UIKit

/// Programmatic A4 (595×842) Turkey franchise vehicle return / handover PDF — no bundled PDF templates.
/// Visual layout aligned with USave return / handover reference (dark headers, gold accent, bilingual labels).
enum TurkeyVehicleFormKind {
    case vehicleReturn
    case vehicleCheckout

    fileprivate var titleTR: String {
        switch self {
        case .vehicleReturn: return "ARAÇ İADE FORMU"
        case .vehicleCheckout: return "ARAÇ TESLİM FORMU"
        }
    }

    fileprivate var titleEN: String {
        switch self {
        case .vehicleReturn: return "VEHICLE RETURN FORM"
        case .vehicleCheckout: return "VEHICLE HANDOVER FORM"
        }
    }

    fileprivate var handoverSectionLabel: String {
        switch self {
        case .vehicleReturn: return "İADE  /  RETURN"
        case .vehicleCheckout: return "TESLİM  /  HANDOVER"
        }
    }
}

// MARK: - Theme (reference PDF)

private enum TurkeyFormColors {
    static let headerFill = UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
    static let accentGold = UIColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1)
    static let panelStroke = UIColor(white: 0.72, alpha: 1)
    static let placeholderText = UIColor(white: 0.62, alpha: 1)
    static let labelMuted = UIColor(white: 0.35, alpha: 1)
}

/// Normalized (0…1) geometry tuned to the RETURN reference (contract band, two columns, checklist, map, signatures, legal).
private enum TRFormLayout {
    static let contractNo = nbox(0.015, 0.108, 0.222, 0.038)
    static let contractDate = nbox(0.242, 0.108, 0.222, 0.038)
    static let contractPeriod = nbox(0.468, 0.108, 0.222, 0.038)
    static let branch = nbox(0.694, 0.108, 0.291, 0.038)

    static let customerHeader = nbox(0.018, 0.152, 0.455, 0.017)
    static let customerFullName = nbox(0.095, 0.173, 0.375, 0.022)
    static let customerId = nbox(0.095, 0.197, 0.375, 0.022)
    static let customerPhone = nbox(0.095, 0.221, 0.375, 0.022)
    static let customerAddress = nbox(0.095, 0.245, 0.375, 0.022)

    static let driverHeader = nbox(0.018, 0.272, 0.455, 0.017)
    static let driverName = nbox(0.095, 0.293, 0.375, 0.022)
    static let driverLicenseDate = nbox(0.095, 0.317, 0.375, 0.022)
    static let driverAddress = nbox(0.095, 0.341, 0.375, 0.022)
    /// Test sürücüsü (checkout/iade’de girildiyse).
    static let testDriverValue = nbox(0.095, 0.365, 0.375, 0.022)

    static let returnHeader = nbox(0.018, 0.392, 0.455, 0.017)
    static let returnDate = nbox(0.095, 0.413, 0.375, 0.022)
    static let returnTime = nbox(0.095, 0.437, 0.375, 0.022)
    static let returnLocation = nbox(0.095, 0.461, 0.375, 0.022)
    static let returnOdometer = nbox(0.095, 0.485, 0.375, 0.022)

    static let vehicleHeader = nbox(0.485, 0.152, 0.497, 0.017)
    /// Value fields sit further right inside the ARAÇ column so text aligns with the panel.
    static let vehicleModel = nbox(0.562, 0.173, 0.408, 0.022)
    static let vehiclePlate = nbox(0.562, 0.197, 0.408, 0.022)
    static let vehicleColor = nbox(0.562, 0.221, 0.408, 0.022)
    static let vehicleFuelType = nbox(0.562, 0.245, 0.408, 0.022)
    static let vehicleVIN = nbox(0.562, 0.269, 0.408, 0.022)

    /// Hasar başlığı yalnızca sağ blokta (sol sütun iade alanıyla çakışmaz).
    /// Harita üstte, hasar metni altta — tek sütun.
    static let damageHeader = nbox(0.505, 0.293, 0.461, 0.015)
    static let damageMapSquare = nbox(0.505, 0.311, 0.461, 0.205)
    static let damageDetailPanel = nbox(0.505, 0.519, 0.461, 0.120)

    /// Hasar altında checklist (EVET/HAYIR).
    static let checklistHeader = nbox(0.018, 0.646, 0.964, 0.016)
    /// checklistHeader altındaki EVET·YES satırı için Y (normalize).
    static let checklistYesNoRowY: CGFloat = 0.664

    static let deliveredCaption = nbox(0.038, 0.786, 0.44, 0.010)
    static let receivedCaption = nbox(0.518, 0.786, 0.44, 0.010)
    static let deliveredSigLabelStack = nbox(0.038, 0.822, 0.048, 0.032)
    static let receivedSigLabelStack = nbox(0.518, 0.822, 0.048, 0.032)

    static let deliveredInlineName = nbox(0.032, 0.804, 0.458, 0.016)
    static let receivedInlineName = nbox(0.512, 0.804, 0.458, 0.016)
    static let deliveredSignature = nbox(0.092, 0.826, 0.386, 0.034)
    static let receivedSignature = nbox(0.572, 0.826, 0.386, 0.034)

    static let legalTitle = nbox(0.028, 0.866, 0.5, 0.011)
    static let legalBlock = nbox(0.028, 0.880, 0.944, 0.042)
}

/// Builds USave-style two-page TR forms: page 1 data + checklist + map + signatures; page 2 photo grids (+ overflow pages).
final class TurkeyVehicleFormPdfBuilder {
    private enum Layout {
        static let pageWidth: CGFloat = 595
        static let pageHeight: CGFloat = 842
    }

    private static let placeholderLine = "…………………………………………"

    /// Normalized YES/NO column origins (matches `drawPage1Chrome` header cues).
    private enum TurkeyChecklistColumns {
        /// Wider YES / NO spacing so header labels and marks never overlap.
        static let yesNormX: [CGFloat] = [0.198, 0.428, 0.658]
        static let noNormX: [CGFloat] = [0.242, 0.472, 0.702]
    }

    /// Checklist YES/NO cells: catalog is column-major (6 rows × 3 columns).
    private static let trItemCells: [YesNoCell] = {
        var cells: [YesNoCell] = []
        let baseY0: CGFloat = 0.678
        let rowStep: CGFloat = 0.0155
        let yesX = TurkeyChecklistColumns.yesNormX
        let noX = TurkeyChecklistColumns.noNormX
        for i in 0 ..< 18 {
            let row = i % 6
            let col = i / 6
            let y = baseY0 + CGFloat(row) * rowStep
            cells.append(YesNoCell(
                yes: nbox(yesX[col], y, 0.022, 0.013),
                no: nbox(noX[col], y, 0.022, 0.013)
            ))
        }
        return cells
    }()

    /// Sayfa 2+: 2 sütun — çok dar dış/sütun boşluğu, çerçevesiz (aspect fit + damga görüntü üstünde).
    private static let trPhotoSlotsTwoCol: [NBox] = {
        var boxes: [NBox] = []
        let xMargin: CGFloat = 0.005
        let colGap: CGFloat = 0.0035
        let colW = (1 - 2 * xMargin - colGap) / 2
        let xL = xMargin
        let xR = xMargin + colW + colGap
        let y0: CGFloat = 0.042
        let gapY: CGFloat = 0.0035
        let bottomReserve: CGFloat = 0.032
        let rowH = max(0.162, (1 - y0 - bottomReserve - 4 * gapY) / 5)
        for row in 0 ..< 5 {
            let y = y0 + CGFloat(row) * (rowH + gapY)
            boxes.append(nbox(xL, y, colW, rowH))
            boxes.append(nbox(xR, y, colW, rowH))
        }
        return boxes
    }()


    /// Generates PDF `Data` (two or more A4 pages).
    func generatePdf(data: VehicleReturnPdfData, kind: TurkeyVehicleFormKind) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: Layout.pageWidth, height: Layout.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let safe = Self.validated(data)
        return renderer.pdfData { pdfContext in
            pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
            Self.drawPage1Chrome(kind: kind, data: safe, pageRect: pageRect, context: pdfContext.cgContext)
            Self.renderPage1Fields(safe, pageRect: pageRect, context: pdfContext.cgContext)
            Self.drawPage1FooterTimestamp(safe, pageRect: pageRect, context: pdfContext.cgContext)

            Self.drawPage2AndOverflow(safe, pageRect: pageRect, kind: kind, pdfContext: pdfContext)
        }
    }

    // MARK: - Validation

    private static func validated(_ data: VehicleReturnPdfData) -> VehicleReturnPdfData {
        var out = data
        if let ratio = out.fuelRatio {
            out.fuelRatio = min(1, max(0, ratio))
        }
        out.damagePoints = out.damagePoints.map {
            DamagePoint(
                x: min(1, max(0, $0.x)),
                y: min(1, max(0, $0.y)),
                label: clean($0.label)
            )
        }
        return out
    }

    // MARK: - Page 1 chrome

    private static func drawPage1Chrome(kind: TurkeyVehicleFormKind, data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext) {
        context.saveGState()

        // Outer frame
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.9)
        context.stroke(CGRect(x: 10, y: 10, width: pageRect.width - 20, height: pageRect.height - 20))

        // Top dark header bar
        let headerH: CGFloat = 52
        let headerRect = CGRect(x: 12, y: 12, width: pageRect.width - 24, height: headerH)
        context.setFillColor(TurkeyFormColors.headerFill.cgColor)
        context.fill(headerRect)
        context.setStrokeColor(TurkeyFormColors.accentGold.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: headerRect.minX, y: headerRect.maxY))
        context.addLine(to: CGPoint(x: headerRect.maxX, y: headerRect.maxY))
        context.strokePath()

        // Logo (transparent PNG — normal blend, left)
        if let logo = UIImage(named: "usave_3d_rgb") ?? UIImage(named: "usave_logo") {
            let maxLogoW: CGFloat = 118
            let maxLogoH: CGFloat = 34
            let ar = logo.size.width / max(logo.size.height, 1)
            var lw = maxLogoW
            var lh = lw / ar
            if lh > maxLogoH {
                lh = maxLogoH
                lw = lh * ar
            }
            let logoRect = CGRect(x: headerRect.minX + 10, y: headerRect.minY + 6, width: lw, height: lh)
            logo.draw(in: logoRect)
        }

        // Centered titles
        let centerX = headerRect.midX
        let trAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.white,
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                return p
            }()
        ]
        let enAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 9.5),
            .foregroundColor: TurkeyFormColors.accentGold,
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                return p
            }()
        ]
        let trTitle = kind.titleTR as NSString
        let enTitle = kind.titleEN as NSString
        let trSize = trTitle.size(withAttributes: trAttrs)
        let enSize = enTitle.size(withAttributes: enAttrs)
        let titleBlockH = trSize.height + 3 + enSize.height
        let titleY = headerRect.midY - titleBlockH / 2
        let titleW = pageRect.width * 0.62
        let titleX = centerX - titleW / 2
        trTitle.draw(in: CGRect(x: titleX, y: titleY, width: titleW, height: trSize.height + 2), withAttributes: trAttrs)
        enTitle.draw(in: CGRect(x: titleX, y: titleY + trSize.height + 3, width: titleW, height: enSize.height + 2), withAttributes: enAttrs)

        drawHeaderVehicleBadge(data: data, headerRect: headerRect, pageRect: pageRect)

        // Contract row (white band + cells)
        let contractBand = toPageRect(nbox(0.015, 0.074, 0.97, 0.048), pageRect: pageRect)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(contractBand)
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.6)
        context.stroke(contractBand)

        drawHeaderLessorLine(data: data, headerRect: headerRect, contractBand: contractBand, pageRect: pageRect)

        let navLabel = data.useNavContractFieldLabel ? "NAV No  /  NAV No" : "Kontrat No  /  Contract No"
        let periodCaption = kind == .vehicleReturn
            ? "Alınan şube / Pick-up"
            : "Esas  /  Period"
        let branchCaption = kind == .vehicleReturn
            ? "Bırakılan şube / Drop-off"
            : "Şube  /  Branch"
        let contractLabels: [(NBox, String)] = [
            (TRFormLayout.contractNo, navLabel),
            (TRFormLayout.contractDate, "Tarih  /  Date"),
            (TRFormLayout.contractPeriod, periodCaption),
            (TRFormLayout.branch, branchCaption)
        ]
        let cap: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.8),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let capPara = NSMutableParagraphStyle()
        capPara.lineBreakMode = .byWordWrapping
        capPara.alignment = .left
        var capAttrs = cap
        capAttrs[.paragraphStyle] = capPara
        for (box, text) in contractLabels {
            let r = toPageRect(box, pageRect: pageRect).insetBy(dx: 2, dy: 1)
            (text as NSString).draw(
                with: r,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: capAttrs,
                context: nil
            )
            context.stroke(toPageRect(box, pageRect: pageRect))
        }
        // Kontrat satırı dikey ayraçlar (hücre iç çizgileri tam yükseklikte)
        let band = toPageRect(nbox(0.015, 0.108, 0.97, 0.038), pageRect: pageRect)
        let sepX: [CGFloat] = [
            toPageRect(TRFormLayout.contractNo, pageRect: pageRect).maxX,
            toPageRect(TRFormLayout.contractDate, pageRect: pageRect).maxX,
            toPageRect(TRFormLayout.contractPeriod, pageRect: pageRect).maxX
        ]
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.6)
        for vx in sepX {
            context.move(to: CGPoint(x: vx, y: band.minY))
            context.addLine(to: CGPoint(x: vx, y: band.maxY))
            context.strokePath()
        }

        // Section headers (dark + gold line)
        func drawSectionHeaderBar(box: NBox, title: String) {
            let r = toPageRect(box, pageRect: pageRect)
            context.setFillColor(TurkeyFormColors.headerFill.cgColor)
            context.fill(r)
            context.setStrokeColor(TurkeyFormColors.accentGold.cgColor)
            context.setLineWidth(1.5)
            context.move(to: CGPoint(x: r.minX, y: r.maxY))
            context.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            context.strokePath()
            let a: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 7.2),
                .foregroundColor: UIColor.white
            ]
            (title as NSString).draw(in: r.insetBy(dx: 5, dy: 2), withAttributes: a)
        }

        drawSectionHeaderBar(box: TRFormLayout.customerHeader, title: "MÜŞTERİ  /  CUSTOMER")
        drawSectionHeaderBar(box: TRFormLayout.driverHeader, title: "SÜRÜCÜ  /  DRIVER")
        drawSectionHeaderBar(box: TRFormLayout.returnHeader, title: kind.handoverSectionLabel)
        drawSectionHeaderBar(box: TRFormLayout.vehicleHeader, title: "ARAÇ  /  VEHICLE")
        drawSectionHeaderBar(box: TRFormLayout.damageHeader, title: "HASAR HARİTASI VE KAYITLAR  /  DAMAGE MAP & RECORDS")
        drawSectionHeaderBar(box: TRFormLayout.checklistHeader, title: "ARAÇLA BİRLİKTE TESLİM EDİLENLER  /  ITEMS WITH VEHICLE")

        // Field captions (left column)
        let mini: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.0),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let customerAddrCaption = clean(data.customerBirth) != nil ? "E-posta / Email" : "Adres  /  Address"
        let leftCaptions: [(NBox, String)] = [
            (TRFormLayout.customerFullName, "Ad Soyad  /  Name"),
            (TRFormLayout.customerId, "T.C. / Pasaport No"),
            (TRFormLayout.customerPhone, "Telefon  /  Phone"),
            (TRFormLayout.customerAddress, customerAddrCaption),
            (TRFormLayout.driverName, "Ad Soyad  /  Name"),
            (TRFormLayout.driverLicenseDate, "Ehliyet Tarihi  /  License Date"),
            (TRFormLayout.driverAddress, "Adres  /  Address"),
            (TRFormLayout.testDriverValue, "Test sürücüsü  /  Test driver"),
            (TRFormLayout.returnDate, "Tarih  /  Date"),
            (TRFormLayout.returnTime, "Saat  /  Time"),
            (TRFormLayout.returnLocation, "Şube  /  Branch"),
            (TRFormLayout.returnOdometer, "KM  /  Odometer")
        ]
        for (box, t) in leftCaptions {
            let r = toPageRect(box, pageRect: pageRect)
            let labelR = CGRect(x: r.minX - 0.075 * pageRect.width, y: r.minY, width: 0.072 * pageRect.width, height: r.height)
            (t as NSString).draw(in: labelR, withAttributes: mini)
            strokeValueCell(r, context: context)
        }

        let vehicleCaptionRows: [(NBox, NBox, String)] = [
            (nbox(0.494, 0.173, 0.066, 0.022), TRFormLayout.vehicleModel, "Marka / Model"),
            (nbox(0.494, 0.197, 0.066, 0.022), TRFormLayout.vehiclePlate, "Plaka  /  Plate"),
            (nbox(0.494, 0.221, 0.066, 0.022), TRFormLayout.vehicleColor, "Renk  /  Color"),
            (nbox(0.494, 0.245, 0.066, 0.022), TRFormLayout.vehicleFuelType, "Yakıt Durumu  /  Fuel Status"),
            (nbox(0.494, 0.269, 0.066, 0.022), TRFormLayout.vehicleVIN, "Şase No  /  VIN")
        ]
        for (labelBox, valueBox, t) in vehicleCaptionRows {
            let lr = toPageRect(labelBox, pageRect: pageRect)
            (t as NSString).draw(in: lr.insetBy(dx: 2, dy: 2), withAttributes: mini)
            strokeValueCell(toPageRect(valueBox, pageRect: pageRect), context: context)
        }

        // Checklist column headers — stacked TR/EN above each box (no single long string squashed between columns).
        let ynTR: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.2, weight: .semibold),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let ynEN: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.0, weight: .regular),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let headerRowYNorm = TRFormLayout.checklistYesNoRowY - 0.014
        for col in 0 ..< 3 {
            let yesHeader = toPageRect(nbox(TurkeyChecklistColumns.yesNormX[col], headerRowYNorm, 0.038, 0.014), pageRect: pageRect)
            let noHeader = toPageRect(nbox(TurkeyChecklistColumns.noNormX[col], headerRowYNorm, 0.038, 0.014), pageRect: pageRect)
            drawStackedBilingualCaption(tr: "EVET", en: "YES", in: yesHeader, trAttrs: ynTR, enAttrs: ynEN)
            drawStackedBilingualCaption(tr: "HAYIR", en: "NO", in: noHeader, trAttrs: ynTR, enAttrs: ynEN)
        }

        // Item labels
        let itemAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5),
            .foregroundColor: UIColor.black
        ]
        for (item, cell) in zip(VehicleChecklistCatalog.items, trItemCells) {
            let lb = labelBox(for: cell)
            (item.title as NSString).draw(in: toPageRect(lb, pageRect: pageRect), withAttributes: itemAttrs)
            strokeYesNoBoxes(cell, pageRect: pageRect, context: context)
        }

        let mapSq = toPageRect(TRFormLayout.damageMapSquare, pageRect: pageRect)
        let detPn = toPageRect(TRFormLayout.damageDetailPanel, pageRect: pageRect)
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.45)
        context.addRect(mapSq.union(detPn))
        context.strokePath()

        // Signature section (isim satırı renderPage1Fields ile doldurulur)
        let sigCap: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        ("Teslim Eden  /  Delivered by" as NSString).draw(
            in: toPageRect(TRFormLayout.deliveredCaption, pageRect: pageRect),
            withAttributes: sigCap
        )
        ("Teslim Alan  /  Received by" as NSString).draw(
            in: toPageRect(TRFormLayout.receivedCaption, pageRect: pageRect),
            withAttributes: sigCap
        )
        let sigLabelTR: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 5.3),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let sigLabelEN: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.0),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        drawStackedBilingualCaption(
            tr: "İmza",
            en: "Signature",
            in: toPageRect(TRFormLayout.deliveredSigLabelStack, pageRect: pageRect),
            trAttrs: sigLabelTR,
            enAttrs: sigLabelEN
        )
        drawStackedBilingualCaption(
            tr: "İmza",
            en: "Signature",
            in: toPageRect(TRFormLayout.receivedSigLabelStack, pageRect: pageRect),
            trAttrs: sigLabelTR,
            enAttrs: sigLabelEN
        )

        strokeValueCell(toPageRect(TRFormLayout.deliveredInlineName, pageRect: pageRect), context: context)
        strokeValueCell(toPageRect(TRFormLayout.receivedInlineName, pageRect: pageRect), context: context)
        strokeValueCell(toPageRect(TRFormLayout.deliveredSignature, pageRect: pageRect), context: context)
        strokeValueCell(toPageRect(TRFormLayout.receivedSignature, pageRect: pageRect), context: context)

        // Legal block title (yasal kutu biraz aşağıda)
        ("Beyan ve taahhütler  /  Declarations" as NSString).draw(
            in: toPageRect(TRFormLayout.legalTitle, pageRect: pageRect),
            withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 6.5),
                .foregroundColor: TurkeyFormColors.labelMuted
            ]
        )
        strokeValueCell(toPageRect(TRFormLayout.legalBlock, pageRect: pageRect), context: context)

        drawTwoColumnGutter(pageRect: pageRect, context: context)

        context.restoreGState()
    }

    /// Müşteri / araç blokları arasında sürekli dikey çizgi (kesik görünümü azaltır).
    private static func drawTwoColumnGutter(pageRect: CGRect, context: CGContext) {
        let x = pageRect.minX + 0.483 * pageRect.width
        let y1 = pageRect.minY + 0.152 * pageRect.height
        let y2 = pageRect.minY + 0.507 * pageRect.height
        context.saveGState()
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.55)
        context.move(to: CGPoint(x: x, y: y1))
        context.addLine(to: CGPoint(x: x, y: y2))
        context.strokePath()
        context.restoreGState()
    }

    /// Kontrat üstü beyaz şerit: franchise ticari ünvanı (Kiraya Veren) — başlık bandının altında, koyu zemin dışında.
    private static func drawHeaderLessorLine(data: VehicleReturnPdfData, headerRect: CGRect, contractBand: CGRect, pageRect: CGRect) {
        guard let legal = clean(data.franchiseLegalTitle), !legal.isEmpty else { return }
        let label = "Kiraya Veren  /  Lessor:" as NSString
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.8, weight: .semibold),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let x0 = headerRect.minX + 10
        let cellBandTop = toPageRect(TRFormLayout.contractNo, pageRect: pageRect).minY
        let yBase = contractBand.minY + 14
        let maxBlockH = max(13, cellBandTop - yBase - 4)
        label.draw(at: CGPoint(x: x0, y: yBase), withAttributes: labelAttrs)
        let lw = label.size(withAttributes: labelAttrs).width
        let maxValueW = max(60, pageRect.maxX - (x0 + lw + 6) - 14)
        let valueRect = CGRect(x: x0 + lw + 5, y: yBase - 1, width: maxValueW, height: maxBlockH)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let vAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.2, weight: .medium),
            .foregroundColor: UIColor.black,
            .paragraphStyle: para
        ]
        (legal as NSString).draw(with: valueRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: vAttrs, context: nil)
    }

    private static func strokeValueCell(_ r: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.45)
        context.stroke(r)
        context.restoreGState()
    }

    /// İmza satırı: TR ve EN alt alta, dar sütunda taşma olmadan.
    private static func drawStackedBilingualCaption(
        tr: String,
        en: String,
        in rect: CGRect,
        trAttrs: [NSAttributedString.Key: Any],
        enAttrs: [NSAttributedString.Key: Any]
    ) {
        guard rect.width > 2, rect.height > 4 else { return }
        let trSize = (tr as NSString).size(withAttributes: trAttrs)
        let enSize = (en as NSString).size(withAttributes: enAttrs)
        let gap: CGFloat = 1
        let blockH = min(rect.height, trSize.height + gap + enSize.height)
        var y = rect.minY + max(0, (rect.height - blockH) / 2)
        (tr as NSString).draw(at: CGPoint(x: rect.minX, y: y), withAttributes: trAttrs)
        y += trSize.height + gap
        (en as NSString).draw(at: CGPoint(x: rect.minX, y: y), withAttributes: enAttrs)
    }

    private static func strokeYesNoBoxes(_ cell: YesNoCell, pageRect: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
        context.setLineWidth(0.35)
        context.stroke(toPageRect(cell.yes, pageRect: pageRect))
        context.stroke(toPageRect(cell.no, pageRect: pageRect))
        context.restoreGState()
    }

    private static func labelBox(for cell: YesNoCell) -> NBox {
        let col: CGFloat
        if cell.yes.x < 0.32 {
            col = 0.018
        } else if cell.yes.x < 0.55 {
            col = 0.258
        } else {
            col = 0.498
        }
        return nbox(col, cell.yes.y - 0.001, 0.136, 0.015)
    }

    /// Başlıkta form adının sağında: plaka (altın kalın) + marka/model (gri ince italik).
    private static func drawHeaderVehicleBadge(data: VehicleReturnPdfData, headerRect: CGRect, pageRect: CGRect) {
        guard let plate = clean(data.headerPlateAccent), !plate.isEmpty else { return }
        let modelLine = clean(data.headerVehicleModelGray) ?? ""
        let rightMargin: CGFloat = 14
        let maxW = pageRect.width * 0.34
        let plateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12.5),
            .foregroundColor: TurkeyFormColors.accentGold
        ]
        let modelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9.5),
            .foregroundColor: UIColor(white: 0.78, alpha: 1)
        ]
        let pPlate = (plate as NSString).size(withAttributes: plateAttrs)
        let pModel = (modelLine as NSString).size(withAttributes: modelAttrs)
        let blockH = pPlate.height + (modelLine.isEmpty ? 0 : 2 + pModel.height)
        let x0 = headerRect.maxX - rightMargin - min(maxW, max(pPlate.width, pModel.width))
        let y0 = headerRect.midY - blockH / 2
        (plate as NSString).draw(at: CGPoint(x: x0, y: y0), withAttributes: plateAttrs)
        if !modelLine.isEmpty {
            (modelLine as NSString).draw(at: CGPoint(x: x0, y: y0 + pPlate.height + 2), withAttributes: modelAttrs)
        }
    }

    // MARK: - Page 1 values

    private static func renderPage1Fields(_ data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext) {
        drawValueOrPlaceholder(data.contractNo, in: TRFormLayout.contractNo, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.contractDate, in: TRFormLayout.contractDate, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.contractPeriod, in: TRFormLayout.contractPeriod, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.branch, in: TRFormLayout.branch, pageRect: pageRect, context: context)

        drawValueOrPlaceholder(data.customerFullName, in: TRFormLayout.customerFullName, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.customerId, in: TRFormLayout.customerId, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.customerPhone, in: TRFormLayout.customerPhone, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.customerBirth, in: TRFormLayout.customerAddress, pageRect: pageRect, context: context)

        let driverDisplayName = clean(data.driverFullName) ?? clean(data.customerFullName)
        drawValueOrPlaceholder(driverDisplayName, in: TRFormLayout.driverName, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.driverLicenseDate, in: TRFormLayout.driverLicenseDate, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.driverAddress, in: TRFormLayout.driverAddress, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.testDriverFullName, in: TRFormLayout.testDriverValue, pageRect: pageRect, context: context)

        drawValueOrPlaceholder(data.returnDate, in: TRFormLayout.returnDate, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.returnTime, in: TRFormLayout.returnTime, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.returnLocation, in: TRFormLayout.returnLocation, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.odometer, in: TRFormLayout.returnOdometer, pageRect: pageRect, context: context)

        drawValueOrPlaceholder(data.vehicleModel, in: TRFormLayout.vehicleModel, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.vehiclePlate, in: TRFormLayout.vehiclePlate, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.vehicleColor, in: TRFormLayout.vehicleColor, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(vehicleFuelLevelDisplay(data), in: TRFormLayout.vehicleFuelType, pageRect: pageRect, context: context)
        drawValueOrPlaceholder(data.vehicleVIN, in: TRFormLayout.vehicleVIN, pageRect: pageRect, context: context)

        drawDamageMapInSquare(data: data, pageRect: pageRect, context: context)
        drawDamageDetailsPanel(lines: data.damageDetailLines, pageRect: pageRect, context: context)

        for (item, cell) in zip(VehicleChecklistCatalog.items, trItemCells) {
            drawYesNo(checklistState(data.items, key: item.key), cell: cell, pageRect: pageRect, context: context)
        }

        drawBranchCellExtras(data: data, pageRect: pageRect, context: context)

        // Teslim Eden = kiracı; Teslim Alan = şube personeli (varsa)
        drawInlineNameLabelRow(
            label: "Ad Soyad  /  Full Name",
            value: data.renterName,
            in: TRFormLayout.deliveredInlineName,
            pageRect: pageRect,
            context: context
        )
        drawInlineNameLabelRow(
            label: "Ad Soyad  /  Full Name",
            value: data.deliveredByName,
            in: TRFormLayout.receivedInlineName,
            pageRect: pageRect,
            context: context
        )
        drawSignatureImage(data.renterSignature, in: TRFormLayout.deliveredSignature, pageRect: pageRect, context: context)
        drawSignatureImage(data.deliveredSignature, in: TRFormLayout.receivedSignature, pageRect: pageRect, context: context)

        drawLegalPlaceholder(in: TRFormLayout.legalBlock, pageRect: pageRect, notes: data.notes)
    }

    private static func drawPage1FooterTimestamp(_ data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext) {
        guard let ts = clean(data.timestamp) else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7),
            .foregroundColor: UIColor.gray
        ]
        (ts as NSString).draw(
            at: CGPoint(x: pageRect.width - 210, y: pageRect.height - 22),
            withAttributes: attrs
        )
    }

    private static func drawDamageMapInSquare(data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext) {
        let rect = toPageRect(TRFormLayout.damageMapSquare, pageRect: pageRect)
        context.saveGState()
        context.clip(to: rect)
        let drawImageRect: CGRect
        if let mapImage = UIImage(named: "condition_vehicle_2d"), mapImage.size.width > 0, mapImage.size.height > 0 {
            drawImageRect = aspectFitRect(imageSize: mapImage.size, in: rect)
            mapImage.draw(in: drawImageRect)
        } else {
            drawImageRect = rect
            context.setStrokeColor(TurkeyFormColors.panelStroke.cgColor)
            context.stroke(rect)
        }
        for (idx, point) in data.damagePoints.enumerated() {
            let px = drawImageRect.minX + point.x * drawImageRect.width
            let py = drawImageRect.minY + point.y * drawImageRect.height
            let bubble = CGRect(x: px - 5, y: py - 5, width: 10, height: 10)
            context.setFillColor(UIColor.systemRed.cgColor)
            context.fillEllipse(in: bubble)
            let label = (point.label ?? "\(idx + 1)") as NSString
            label.draw(
                at: CGPoint(x: min(drawImageRect.maxX - 14, px + 6), y: py - 5),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: UIColor.systemRed
                ]
            )
        }
        context.restoreGState()
    }

    private static func drawDamageDetailsPanel(lines: [String], pageRect: CGRect, context: CGContext) {
        let panelRect = toPageRect(TRFormLayout.damageDetailPanel, pageRect: pageRect)
        let outer = panelRect.insetBy(dx: 3, dy: 3)
        guard outer.width > 6, outer.height > 6 else { return }
        context.saveGState()
        context.clip(to: outer)

        let title = "HASAR KAYIT DETAYLARI\n/ DAMAGE RECORDS" as NSString
        let titlePara = NSMutableParagraphStyle()
        titlePara.lineSpacing = 0.5
        titlePara.lineBreakMode = .byWordWrapping
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 5.9),
            .foregroundColor: TurkeyFormColors.labelMuted,
            .paragraphStyle: titlePara
        ]
        let titleH = title.boundingRect(
            with: CGSize(width: outer.width, height: 40),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttrs,
            context: nil
        ).height
        title.draw(
            with: CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: ceil(titleH)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttrs,
            context: nil
        )
        let titleBlockH = ceil(titleH)
        var y = outer.minY + titleBlockH + 3
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.8),
            .foregroundColor: UIColor.darkGray
        ]
        let usable = lines.isEmpty ? ["—"] : lines
        for line in usable.prefix(22) {
            if y > outer.maxY - 6 { break }
            let s = line as NSString
            let h = s.boundingRect(
                with: CGSize(width: outer.width, height: outer.maxY - y),
                options: [.usesLineFragmentOrigin],
                attributes: bodyAttrs,
                context: nil
            ).height
            s.draw(with: CGRect(x: outer.minX, y: y, width: outer.width, height: min(outer.maxY - y, ceil(h) + 1)),
                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                   attributes: bodyAttrs,
                   context: nil)
            y += ceil(h) + 2
        }
        context.restoreGState()
    }

    /// Öncelik `fuelRatio` (8 dilim), yoksa `vehicleFuelType` metni.
    private static func vehicleFuelLevelDisplay(_ data: VehicleReturnPdfData) -> String? {
        if let r = data.fuelRatio {
            let c = min(1, max(0, r))
            if c <= 0.001 { return "0/8" }
            let eighth = min(8, max(1, Int(round(c * 8))))
            return "\(eighth)/8"
        }
        return clean(data.vehicleFuelType)
    }

    private static func drawBranchCellExtras(data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext) {
        let cell = toPageRect(TRFormLayout.branch, pageRect: pageRect).insetBy(dx: 3, dy: 16)
        guard cell.width > 8, cell.height > 10 else { return }
        var y = cell.minY
        let micro: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.6),
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        if let legal = clean(data.franchiseLegalTitle) {
            let s = legal as NSString
            let h = s.boundingRect(with: CGSize(width: cell.width, height: 40), options: [.usesLineFragmentOrigin], attributes: micro, context: nil).height
            s.draw(with: CGRect(x: cell.minX, y: y, width: cell.width, height: min(36, ceil(h) + 2)),
                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                   attributes: micro,
                   context: nil)
            y += min(36, ceil(h) + 4)
        }
        if let route = clean(data.branchRoutingLine) {
            let s = route as NSString
            let h = s.boundingRect(with: CGSize(width: cell.width, height: cell.maxY - y), options: [.usesLineFragmentOrigin], attributes: micro, context: nil).height
            s.draw(with: CGRect(x: cell.minX, y: y, width: cell.width, height: min(cell.maxY - y, ceil(h) + 2)),
                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                   attributes: micro,
                   context: nil)
        }
    }

    // MARK: - Page 2 + overflow

    private static func drawPage2AndOverflow(
        _ data: VehicleReturnPdfData,
        pageRect: CGRect,
        kind _: TurkeyVehicleFormKind,
        pdfContext: UIGraphicsPDFRendererContext
    ) {
        let vehicles = data.vehiclePhotos
        let damages = data.damagePhotos
        guard !vehicles.isEmpty || !damages.isEmpty else {
            pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
            drawCopyrightFooter(pageRect: pageRect, context: pdfContext.cgContext)
            return
        }
        let perPage = trPhotoSlotsTwoCol.count
        if !vehicles.isEmpty {
            var idx = 0
            while idx < vehicles.count {
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                let slice = Array(vehicles[idx ..< min(idx + perPage, vehicles.count)])
                drawTitledPhotoGridPage(
                    title: "ARAÇ FOTOĞRAFLARI / VEHICLE PHOTOS",
                    images: slice,
                    timestamp: data.timestamp,
                    pageRect: pageRect,
                    context: pdfContext.cgContext
                )
                drawCopyrightFooter(pageRect: pageRect, context: pdfContext.cgContext)
                idx += perPage
            }
        }
        if !damages.isEmpty {
            var j = 0
            while j < damages.count {
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                let slice = Array(damages[j ..< min(j + perPage, damages.count)])
                drawTitledPhotoGridPage(
                    title: "HASAR FOTOĞRAFLARI / DAMAGE PHOTOS",
                    images: slice,
                    timestamp: data.timestamp,
                    pageRect: pageRect,
                    context: pdfContext.cgContext
                )
                drawCopyrightFooter(pageRect: pageRect, context: pdfContext.cgContext)
                j += perPage
            }
        }
    }

    private static func drawCopyrightFooter(pageRect: CGRect, context: CGContext) {
        let copyright = PDFExportBranding.copyrightLine
        let copyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.gray
        ]
        let sz = (copyright as NSString).size(withAttributes: copyAttrs)
        (copyright as NSString).draw(
            at: CGPoint(x: (pageRect.width - sz.width) / 2, y: pageRect.height - 22),
            withAttributes: copyAttrs
        )
    }

    private static func drawTitledPhotoGridPage(
        title: String,
        images: [UIImage],
        timestamp: String?,
        pageRect: CGRect,
        context: CGContext
    ) {
        let titlePara = NSMutableParagraphStyle()
        titlePara.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: UIColor(white: 0.28, alpha: 1),
            .kern: 0.4,
            .paragraphStyle: titlePara
        ]
        let titleRect = toPageRect(nbox(0.005, 0.020, 0.990, 0.020), pageRect: pageRect)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        for (idx, box) in trPhotoSlotsTwoCol.enumerated() {
            guard idx < images.count else { break }
            drawImageAspectFitLetterboxed(
                TurkeyCaptureImageOrientation.preparedForPdf(images[idx]),
                stamp: clean(timestamp),
                in: box,
                pageRect: pageRect,
                context: context
            )
        }
    }

    // MARK: - Drawing helpers

    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "-" { return nil }
        return t
    }

    /// Tek satırda solda etiket, sağda küçük punto ile isim (imza üstü).
    private static func drawInlineNameLabelRow(
        label: String,
        value: String?,
        in rowBox: NBox,
        pageRect: CGRect,
        context: CGContext
    ) {
        let r = toPageRect(rowBox, pageRect: pageRect).insetBy(dx: 3, dy: 1)
        guard r.width > 8, r.height > 4 else { return }
        let labelFont = UIFont.systemFont(ofSize: 5.2)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: TurkeyFormColors.labelMuted
        ]
        let gap: CGFloat = 2
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let vx = r.minX + labelSize.width + gap
        let valueRect = CGRect(x: vx, y: r.minY, width: max(4, r.maxX - vx), height: r.height)
        var valueFontSize: CGFloat = 6.8
        let text = clean(value) ?? ""
        let valueTextHeight: CGFloat
        if !text.isEmpty {
            while valueFontSize > 5.0 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: valueFontSize),
                    .foregroundColor: UIColor.black
                ]
                let w = (text as NSString).size(withAttributes: attrs).width
                if w <= valueRect.width - 1 { break }
                valueFontSize -= 0.35
            }
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: valueFontSize),
                .foregroundColor: UIColor.black
            ]
            valueTextHeight = (text as NSString).size(withAttributes: valueAttrs).height
        } else {
            valueTextHeight = (placeholderLine as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: 6.0),
                .foregroundColor: UIColor.black
            ]).height
        }
        let baselineY = r.midY - max(labelSize.height, valueTextHeight) / 2 + 0.5
        (label as NSString).draw(at: CGPoint(x: r.minX, y: baselineY), withAttributes: labelAttrs)
        if !text.isEmpty {
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: valueFontSize),
                .foregroundColor: UIColor.black
            ]
            context.saveGState()
            context.clip(to: valueRect)
            (text as NSString).draw(
                in: CGRect(x: vx, y: baselineY, width: valueRect.width, height: valueRect.height),
                withAttributes: valueAttrs
            )
            context.restoreGState()
        } else {
            let ph: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 5.2),
                .foregroundColor: TurkeyFormColors.placeholderText
            ]
            let shortDots = "……………" as NSString
            (shortDots).draw(at: CGPoint(x: vx, y: baselineY + 0.5), withAttributes: ph)
        }
    }

    private static func drawValueOrPlaceholder(
        _ rawText: String?,
        in box: NBox,
        pageRect: CGRect,
        context: CGContext,
        baseFont: UIFont = .systemFont(ofSize: 9)
    ) {
        let rect = toPageRect(box, pageRect: pageRect).insetBy(dx: 4, dy: 2)
        guard rect.width > 4, rect.height > 4 else { return }
        if let text = clean(rawText), !text.isEmpty {
            drawTextInBox(text, in: box, pageRect: pageRect, context: context, baseFont: baseFont, minFontSize: 7, color: .black)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: TurkeyFormColors.placeholderText
            ]
            context.saveGState()
            context.clip(to: rect)
            (placeholderLine as NSString).draw(in: rect, withAttributes: attrs)
            context.restoreGState()
        }
    }

    private static func defaultLegalDeclarationsTRSlashEN() -> String {
        """
        1) Kiracı, aracı teslim aldığı andaki haliyle iade ettiğini beyan eder. / The renter declares that the vehicle is returned in the same condition as when it was received.
        2) Eksik ve hasar beyanının doğruluğunu taahhüt eder. / The renter undertakes that the declared inventory and damage information is accurate.
        3) Şirket kayıtları ile ek ücretlendirme prosedürlerini kabul eder. / The renter accepts the company's records and supplementary charging procedures.
        (Otomatik form — ayrıntılı metin sözleşmede.) / (Auto-generated form — full terms in the rental agreement.)
        """
    }

    private static func drawLegalPlaceholder(in box: NBox, pageRect: CGRect, notes: String?) {
        let rect = toPageRect(box, pageRect: pageRect).insetBy(dx: 4, dy: 3)
        let declarations = defaultLegalDeclarationsTRSlashEN()
        let body: String
        if let n = clean(notes), !n.isEmpty {
            body = "Notlar / Notes: \(n)\n\n\(declarations)"
        } else {
            body = declarations
        }
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 1.5
        p.paragraphSpacing = 2.0
        p.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 5.6),
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: p
        ]
        (body as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }

    private static func drawTextInBox(
        _ rawText: String?,
        in box: NBox,
        pageRect: CGRect,
        context: CGContext,
        baseFont: UIFont = .systemFont(ofSize: 10),
        minFontSize: CGFloat = 7.5,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        paddingX: CGFloat = 3,
        paddingY: CGFloat = 2
    ) {
        guard let text = clean(rawText), !text.isEmpty else { return }
        let rect = toPageRect(box, pageRect: pageRect).insetBy(dx: paddingX, dy: paddingY)
        guard rect.width > 4, rect.height > 4 else { return }

        var font = baseFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        func height(for f: UIFont) -> CGFloat {
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .paragraphStyle: paragraph]
            let h = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            ).height
            return ceil(h)
        }
        while font.pointSize > minFontSize && (height(for: font) > rect.height || (text as NSString).size(withAttributes: [.font: font]).width > rect.width * 1.6) {
            font = font.withSize(font.pointSize - 0.5)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let textHeight = min(rect.height, height(for: font))
        let drawRect = CGRect(x: rect.minX, y: rect.minY + (rect.height - textHeight) / 2, width: rect.width, height: textHeight)
        context.saveGState()
        context.clip(to: rect)
        (text as NSString).draw(in: drawRect, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawCenteredX(in box: NBox, pageRect: CGRect, context: CGContext) {
        let rect = toPageRect(box, pageRect: pageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: min(rect.width, rect.height) * 0.72),
            .foregroundColor: UIColor.black
        ]
        let xText = "X" as NSString
        let size = xText.size(withAttributes: attrs)
        let drawRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        context.saveGState()
        context.clip(to: rect)
        xText.draw(in: drawRect, withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawYesNo(_ value: Bool?, cell: YesNoCell, pageRect: CGRect, context: CGContext) {
        guard let value else { return }
        drawCenteredX(in: value ? cell.yes : cell.no, pageRect: pageRect, context: context)
    }

    private static func drawImageAspectFillClipped(_ image: UIImage?, in box: NBox, pageRect: CGRect, context: CGContext) {
        guard let image else { return }
        let rect = toPageRect(box, pageRect: pageRect)
        guard rect.width > 0, rect.height > 0 else { return }

        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return }

        let scale = max(rect.width / iw, rect.height / ih)
        let targetW = iw * scale
        let targetH = ih * scale
        let drawRect = CGRect(
            x: rect.midX - targetW / 2,
            y: rect.midY - targetH / 2,
            width: targetW,
            height: targetH
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    /// PDF foto: kırpma ve stretch yok (aspect fit); çerçeve yok — hücreye tam oturur; damga görüntü üstünde.
    private static func drawImageAspectFitLetterboxed(
        _ image: UIImage,
        stamp: String?,
        in box: NBox,
        pageRect: CGRect,
        context: CGContext
    ) {
        let rect = toPageRect(box, pageRect: pageRect)
        guard rect.width > 1, rect.height > 1 else { return }
        let drawSize = TurkeyCaptureImageOrientation.logicalPixelSize(of: image)
        guard drawSize.width > 0, drawSize.height > 0 else { return }
        let fit = aspectFitRect(imageSize: drawSize, in: rect, scaleBoost: 1)
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: fit)
        if let ts = stamp, !ts.isEmpty {
            drawPhotoTimestampInsideImage(ts, imageRect: fit, context: context)
        }
        context.restoreGState()
    }

    private static func drawPhotoTimestampInsideImage(_ text: String, imageRect: CGRect, context: CGContext) {
        let pad: CGFloat = 6
        let origin = CGPoint(x: imageRect.minX + pad, y: imageRect.minY + 4)
        let outline: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.clear,
            .strokeColor: UIColor.black.withAlphaComponent(0.65),
            .strokeWidth: -3.0
        ]
        let fill: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: TurkeyFormColors.accentGold
        ]
        let s = text as NSString
        s.draw(at: origin, withAttributes: outline)
        s.draw(at: origin, withAttributes: fill)
    }

    private static func drawSignatureImage(_ image: UIImage?, in box: NBox, pageRect: CGRect, context: CGContext) {
        guard let image else { return }
        let rect = toPageRect(box, pageRect: pageRect).insetBy(dx: 2, dy: 2)
        guard rect.width > 0, rect.height > 0 else { return }
        let fit = aspectFitRect(imageSize: image.size, in: rect, scaleBoost: 1.08)
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: fit)
        context.restoreGState()
    }

    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect, scaleBoost: CGFloat = 1) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let sx = rect.width / imageSize.width
        let sy = rect.height / imageSize.height
        var scale = min(sx, sy) * scaleBoost
        let maxW = imageSize.width * scale
        let maxH = imageSize.height * scale
        if maxW > rect.width || maxH > rect.height {
            scale = min(sx, sy)
        }
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

// MARK: - VehicleItems key lookup

private func checklistState(_ items: VehicleItems, key: String) -> Bool? {
    switch key {
    case "anten": return items.antenna
    case "avadanlik": return items.jackSet
    case "yedek_lastik": return items.spareTire
    case "plakalik": return items.plateHolder
    case "trafik_seti": return items.safetyKit
    case "hgs_etiketi": return items.hgsTag
    case "yangin_tupu": return items.fireExt
    case "ruhsat": return items.registration
    case "trafik_policesi": return items.insurance
    case "paspas": return items.floorMats
    case "cam_suyu": return items.washerFluid
    case "pandizot": return items.underguard
    case "silecek": return items.wipers
    case "lastik_kompresoru": return items.pump
    case "navigasyon": return items.navigation
    case "cocuk_koltugu": return items.childSeat
    case "zincir": return items.chains
    case "lastik_markasi": return items.tireBrand
    default: return nil
    }
}
