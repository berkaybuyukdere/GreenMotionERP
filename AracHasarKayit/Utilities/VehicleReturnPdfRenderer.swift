import Foundation
import UIKit
import PDFKit

struct NBox {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

struct PBox {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

func nbox(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NBox {
    NBox(x: x, y: y, w: w, h: h)
}

func toPageRect(_ box: NBox, pageRect: CGRect) -> CGRect {
    let px = pageRect.minX + box.x * pageRect.width
    let py = pageRect.minY + box.y * pageRect.height
    let pw = box.w * pageRect.width
    let ph = box.h * pageRect.height
    return CGRect(x: px, y: py, width: pw, height: ph)
}

enum VehicleReturnPdfLayout {
    // Contract header row (top of page, y≈0.095)
    static let contractNo     = nbox(0.02,  0.095, 0.23,  0.030)
    static let contractDate   = nbox(0.255, 0.095, 0.24,  0.030)
    static let contractPeriod = nbox(0.500, 0.095, 0.24,  0.030)
    static let branch         = nbox(0.745, 0.095, 0.24,  0.030)

    // Customer section – left column, 4 rows (y 0.182–0.254, spacing 0.024)
    static let customerFullName = nbox(0.131, 0.182, 0.322, 0.024)
    static let customerId       = nbox(0.131, 0.206, 0.322, 0.024)
    static let customerPhone    = nbox(0.131, 0.230, 0.322, 0.024)
    static let customerBirth    = nbox(0.131, 0.254, 0.322, 0.024)

    // Driver section – left column, 3 rows (y 0.299–0.347)
    static let driverLicenseNo   = nbox(0.131, 0.299, 0.322, 0.024)
    static let driverLicenseDate = nbox(0.131, 0.323, 0.322, 0.024)
    static let driverAddress     = nbox(0.131, 0.347, 0.322, 0.024)

    // Return details – left column, 4 rows (y 0.395–0.467)
    static let returnDate     = nbox(0.131, 0.395, 0.322, 0.024)
    static let returnTime     = nbox(0.131, 0.419, 0.322, 0.024)
    static let returnLocation = nbox(0.131, 0.443, 0.322, 0.024)
    static let returnOdometer = nbox(0.131, 0.467, 0.322, 0.024)

    // Vehicle section – right column, 6 rows (y 0.182–0.302)
    static let vehicleModel    = nbox(0.504, 0.182, 0.450, 0.024)
    static let vehiclePlate    = nbox(0.504, 0.206, 0.450, 0.024)
    static let vehicleColor    = nbox(0.504, 0.230, 0.450, 0.024)
    static let vehicleFuelType = nbox(0.504, 0.254, 0.450, 0.024)
    static let vehicleClass    = nbox(0.504, 0.278, 0.450, 0.024)
    static let vehicleVIN      = nbox(0.504, 0.302, 0.450, 0.024)

    // Fuel gauge – right, below vehicle rows
    static let fuelGaugeArea = nbox(0.565, 0.363, 0.285, 0.102)

    // Damage map – full-width band below checklist
    static let damageMapArea = nbox(0.108, 0.665, 0.783, 0.105)

    // Name labels above signatures
    static let renterName      = nbox(0.05, 0.848, 0.39, 0.026)
    static let deliveredByName = nbox(0.55, 0.848, 0.39, 0.026)

    // Signature image boxes
    static let renterSignature    = nbox(0.05, 0.875, 0.39, 0.052)
    static let deliveredSignature = nbox(0.55, 0.875, 0.39, 0.052)
}

struct YesNoCell {
    let yes: NBox
    let no: NBox
}

// YES/NO checkbox grid – 6 rows × 3 columns.
// Row y values start at 0.543 with 0.020 spacing so all 6 rows clear the
// damage map area which begins at y=0.665.
// Column x positions match the template's printed YES/NO header marks.
enum ItemBoxes {
    // Row 0 (y=0.543)
    static let antenna     = YesNoCell(yes: nbox(0.215, 0.543, 0.020, 0.016), no: nbox(0.262, 0.543, 0.020, 0.016))
    static let jackSet     = YesNoCell(yes: nbox(0.467, 0.543, 0.020, 0.016), no: nbox(0.515, 0.543, 0.020, 0.016))
    static let spareTire   = YesNoCell(yes: nbox(0.720, 0.543, 0.020, 0.016), no: nbox(0.767, 0.543, 0.020, 0.016))

    // Row 1 (y=0.563)
    static let plateHolder = YesNoCell(yes: nbox(0.215, 0.563, 0.020, 0.016), no: nbox(0.262, 0.563, 0.020, 0.016))
    static let safetyKit   = YesNoCell(yes: nbox(0.467, 0.563, 0.020, 0.016), no: nbox(0.515, 0.563, 0.020, 0.016))
    static let hgsTag      = YesNoCell(yes: nbox(0.720, 0.563, 0.020, 0.016), no: nbox(0.767, 0.563, 0.020, 0.016))

    // Row 2 (y=0.583)
    static let fireExt     = YesNoCell(yes: nbox(0.215, 0.583, 0.020, 0.016), no: nbox(0.262, 0.583, 0.020, 0.016))
    static let registration = YesNoCell(yes: nbox(0.467, 0.583, 0.020, 0.016), no: nbox(0.515, 0.583, 0.020, 0.016))
    static let insurance   = YesNoCell(yes: nbox(0.720, 0.583, 0.020, 0.016), no: nbox(0.767, 0.583, 0.020, 0.016))

    // Row 3 (y=0.603)
    static let floorMats   = YesNoCell(yes: nbox(0.215, 0.603, 0.020, 0.016), no: nbox(0.262, 0.603, 0.020, 0.016))
    static let washerFluid = YesNoCell(yes: nbox(0.467, 0.603, 0.020, 0.016), no: nbox(0.515, 0.603, 0.020, 0.016))
    static let underguard  = YesNoCell(yes: nbox(0.720, 0.603, 0.020, 0.016), no: nbox(0.767, 0.603, 0.020, 0.016))

    // Row 4 (y=0.623)
    static let wipers      = YesNoCell(yes: nbox(0.215, 0.623, 0.020, 0.016), no: nbox(0.262, 0.623, 0.020, 0.016))
    static let pump        = YesNoCell(yes: nbox(0.467, 0.623, 0.020, 0.016), no: nbox(0.515, 0.623, 0.020, 0.016))
    static let navigation  = YesNoCell(yes: nbox(0.720, 0.623, 0.020, 0.016), no: nbox(0.767, 0.623, 0.020, 0.016))

    // Row 5 (y=0.643)
    static let childSeat   = YesNoCell(yes: nbox(0.215, 0.643, 0.020, 0.016), no: nbox(0.262, 0.643, 0.020, 0.016))
    static let chains      = YesNoCell(yes: nbox(0.467, 0.643, 0.020, 0.016), no: nbox(0.515, 0.643, 0.020, 0.016))
    static let tireBrand   = YesNoCell(yes: nbox(0.720, 0.643, 0.020, 0.016), no: nbox(0.767, 0.643, 0.020, 0.016))
}

enum Page2Layout {
    static let vehiclePhotos: [NBox] = [
        nbox(0.02, 0.100, 0.45, 0.205),
        nbox(0.52, 0.100, 0.45, 0.205),
        nbox(0.02, 0.335, 0.45, 0.180),
        nbox(0.52, 0.335, 0.45, 0.180)
    ]

    static let damagePhotos: [NBox] = [
        nbox(0.02, 0.565, 0.30, 0.185),
        nbox(0.35, 0.565, 0.30, 0.185),
        nbox(0.68, 0.565, 0.30, 0.185),
        nbox(0.02, 0.775, 0.30, 0.185),
        nbox(0.35, 0.775, 0.30, 0.185),
        nbox(0.68, 0.775, 0.30, 0.185)
    ]
}

struct DamagePoint {
    let x: CGFloat
    let y: CGFloat
    let label: String?
}

struct VehicleItems {
    var antenna: Bool?
    var jackSet: Bool?
    var spareTire: Bool?
    var plateHolder: Bool?
    var safetyKit: Bool?
    var hgsTag: Bool?
    var fireExt: Bool?
    var registration: Bool?
    var insurance: Bool?
    var floorMats: Bool?
    var washerFluid: Bool?
    var underguard: Bool?
    var wipers: Bool?
    var pump: Bool?
    var navigation: Bool?
    var childSeat: Bool?
    var chains: Bool?
    var tireBrand: Bool?
}

struct VehicleReturnPdfData {
    var contractNo: String?
    var contractDate: String?
    var contractPeriod: String?
    var branch: String?
    /// Şirket ünvanı (franchise); PDF üst bant / şube hücresinde gösterilir.
    var franchiseLegalTitle: String?
    /// Örn. "Çıkış şubesi: …  →  İade şubesi: …" (Türkiye operasyonları).
    var branchRoutingLine: String?

    var customerFullName: String?
    var customerId: String?
    var customerPhone: String?
    var customerBirth: String?

    var driverLicenseNo: String?
    var driverLicenseDate: String?
    var driverAddress: String?

    var returnDate: String?
    var returnTime: String?
    var returnLocation: String?
    var odometer: String?

    var vehicleModel: String?
    var vehiclePlate: String?
    var vehicleColor: String?
    var vehicleFuelType: String?
    var vehicleClass: String?
    var vehicleVIN: String?

    var fuelRatio: CGFloat?
    var items: VehicleItems
    var damagePoints: [DamagePoint]

    var renterName: String?
    var deliveredByName: String?
    var renterSignature: UIImage?
    var deliveredSignature: UIImage?

    /// Free-form notes (e.g. TR exit / return remarks). Drawn on programmatic TR forms only.
    var notes: String?

    /// Header sağında: plaka (altın) + marka/model (gri ince italik).
    var headerPlateAccent: String?
    var headerVehicleModelGray: String?

    /// `true`: Kontrat alanı etiketi NAV olarak çizilir (Türkiye).
    var useNavContractFieldLabel: Bool = false

    /// Hasar haritası yanındaki metin satırları (#işaret, bölge, tip, şiddet).
    var damageDetailLines: [String] = []

    var vehiclePhotos: [UIImage]
    var damagePhotos: [UIImage]
    var timestamp: String?
}

enum VehicleReturnPdfRendererError: Error {
    case invalidTemplate
    case missingTemplatePage
}

final class VehicleReturnPdfRenderer {
    func generatePdf(templateData: Data, data: VehicleReturnPdfData, debugLayout: Bool = false) throws -> Data {
        guard let provider = CGDataProvider(data: templateData as CFData),
              let template = CGPDFDocument(provider) else {
            throw VehicleReturnPdfRendererError.invalidTemplate
        }
        let page1 = template.page(at: 1)
        guard let firstPage = page1 else {
            throw VehicleReturnPdfRendererError.missingTemplatePage
        }
        let firstMedia = firstPage.getBoxRect(.mediaBox)
        let renderer = UIGraphicsPDFRenderer(bounds: firstMedia)
        let safeData = validated(data)

        return renderer.pdfData { pdfContext in
            for pageIndex in 1...template.numberOfPages {
                guard let tPage = template.page(at: pageIndex) else { continue }
                let pageRect = tPage.getBoxRect(.mediaBox)
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                drawTemplatePage(tPage, in: UIGraphicsGetCurrentContext()!, pageRect: pageRect)

                if pageIndex == 1 {
                    renderPage1(safeData, pageRect: pageRect, context: UIGraphicsGetCurrentContext()!, debugLayout: debugLayout)
                } else if pageIndex == 2 {
                    renderPage2(safeData, pageRect: pageRect, context: UIGraphicsGetCurrentContext()!, debugLayout: debugLayout)
                }
            }
        }
    }

    private func validated(_ data: VehicleReturnPdfData) -> VehicleReturnPdfData {
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

    private func drawTemplatePage(_ page: CGPDFPage, in context: CGContext, pageRect: CGRect) {
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        let media = page.getBoxRect(.mediaBox)
        let sx = pageRect.width / max(media.width, 1)
        let sy = pageRect.height / max(media.height, 1)
        context.scaleBy(x: sx, y: sy)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private func renderPage1(_ data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext, debugLayout: Bool) {
        drawTextInBox(data.contractNo, in: VehicleReturnPdfLayout.contractNo, pageRect: pageRect, context: context)
        drawTextInBox(data.contractDate, in: VehicleReturnPdfLayout.contractDate, pageRect: pageRect, context: context)
        drawTextInBox(data.contractPeriod, in: VehicleReturnPdfLayout.contractPeriod, pageRect: pageRect, context: context)
        drawTextInBox(data.branch, in: VehicleReturnPdfLayout.branch, pageRect: pageRect, context: context)

        drawTextInBox(data.customerFullName, in: VehicleReturnPdfLayout.customerFullName, pageRect: pageRect, context: context)
        drawTextInBox(data.customerId, in: VehicleReturnPdfLayout.customerId, pageRect: pageRect, context: context)
        drawTextInBox(data.customerPhone, in: VehicleReturnPdfLayout.customerPhone, pageRect: pageRect, context: context)
        drawTextInBox(data.customerBirth, in: VehicleReturnPdfLayout.customerBirth, pageRect: pageRect, context: context)

        drawTextInBox(data.driverLicenseNo, in: VehicleReturnPdfLayout.driverLicenseNo, pageRect: pageRect, context: context)
        drawTextInBox(data.driverLicenseDate, in: VehicleReturnPdfLayout.driverLicenseDate, pageRect: pageRect, context: context)
        drawTextInBox(data.driverAddress, in: VehicleReturnPdfLayout.driverAddress, pageRect: pageRect, context: context)

        drawTextInBox(data.returnDate, in: VehicleReturnPdfLayout.returnDate, pageRect: pageRect, context: context)
        drawTextInBox(data.returnTime, in: VehicleReturnPdfLayout.returnTime, pageRect: pageRect, context: context)
        drawTextInBox(data.returnLocation, in: VehicleReturnPdfLayout.returnLocation, pageRect: pageRect, context: context)
        drawTextInBox(data.odometer, in: VehicleReturnPdfLayout.returnOdometer, pageRect: pageRect, context: context)

        drawTextInBox(data.vehicleModel, in: VehicleReturnPdfLayout.vehicleModel, pageRect: pageRect, context: context)
        drawTextInBox(data.vehiclePlate, in: VehicleReturnPdfLayout.vehiclePlate, pageRect: pageRect, context: context)
        drawTextInBox(data.vehicleColor, in: VehicleReturnPdfLayout.vehicleColor, pageRect: pageRect, context: context)
        drawTextInBox(data.vehicleFuelType, in: VehicleReturnPdfLayout.vehicleFuelType, pageRect: pageRect, context: context)
        drawTextInBox(data.vehicleClass, in: VehicleReturnPdfLayout.vehicleClass, pageRect: pageRect, context: context)
        drawTextInBox(data.vehicleVIN, in: VehicleReturnPdfLayout.vehicleVIN, pageRect: pageRect, context: context)

        drawYesNo(data.items.antenna, cell: ItemBoxes.antenna, pageRect: pageRect, context: context)
        drawYesNo(data.items.jackSet, cell: ItemBoxes.jackSet, pageRect: pageRect, context: context)
        drawYesNo(data.items.spareTire, cell: ItemBoxes.spareTire, pageRect: pageRect, context: context)
        drawYesNo(data.items.plateHolder, cell: ItemBoxes.plateHolder, pageRect: pageRect, context: context)
        drawYesNo(data.items.safetyKit, cell: ItemBoxes.safetyKit, pageRect: pageRect, context: context)
        drawYesNo(data.items.hgsTag, cell: ItemBoxes.hgsTag, pageRect: pageRect, context: context)
        drawYesNo(data.items.fireExt, cell: ItemBoxes.fireExt, pageRect: pageRect, context: context)
        drawYesNo(data.items.registration, cell: ItemBoxes.registration, pageRect: pageRect, context: context)
        drawYesNo(data.items.insurance, cell: ItemBoxes.insurance, pageRect: pageRect, context: context)
        drawYesNo(data.items.floorMats, cell: ItemBoxes.floorMats, pageRect: pageRect, context: context)
        drawYesNo(data.items.washerFluid, cell: ItemBoxes.washerFluid, pageRect: pageRect, context: context)
        drawYesNo(data.items.underguard, cell: ItemBoxes.underguard, pageRect: pageRect, context: context)
        drawYesNo(data.items.wipers, cell: ItemBoxes.wipers, pageRect: pageRect, context: context)
        drawYesNo(data.items.pump, cell: ItemBoxes.pump, pageRect: pageRect, context: context)
        drawYesNo(data.items.navigation, cell: ItemBoxes.navigation, pageRect: pageRect, context: context)
        drawYesNo(data.items.childSeat, cell: ItemBoxes.childSeat, pageRect: pageRect, context: context)
        drawYesNo(data.items.chains, cell: ItemBoxes.chains, pageRect: pageRect, context: context)
        drawYesNo(data.items.tireBrand, cell: ItemBoxes.tireBrand, pageRect: pageRect, context: context)

        drawFuelMarker(ratio: data.fuelRatio, in: VehicleReturnPdfLayout.fuelGaugeArea, pageRect: pageRect, context: context)
        for point in data.damagePoints {
            drawDamageMarker(point: point, in: VehicleReturnPdfLayout.damageMapArea, pageRect: pageRect, context: context)
        }

        drawTextInBox(data.renterName, in: VehicleReturnPdfLayout.renterName, pageRect: pageRect, context: context)
        drawTextInBox(data.deliveredByName, in: VehicleReturnPdfLayout.deliveredByName, pageRect: pageRect, context: context)

        drawSignatureImage(data.renterSignature, in: VehicleReturnPdfLayout.renterSignature, pageRect: pageRect, context: context)
        drawSignatureImage(data.deliveredSignature, in: VehicleReturnPdfLayout.deliveredSignature, pageRect: pageRect, context: context)

        if debugLayout {
            let page1Boxes: [NBox] = [
                VehicleReturnPdfLayout.contractNo, VehicleReturnPdfLayout.contractDate, VehicleReturnPdfLayout.contractPeriod, VehicleReturnPdfLayout.branch,
                VehicleReturnPdfLayout.customerFullName, VehicleReturnPdfLayout.customerId, VehicleReturnPdfLayout.customerPhone, VehicleReturnPdfLayout.customerBirth,
                VehicleReturnPdfLayout.driverLicenseNo, VehicleReturnPdfLayout.driverLicenseDate, VehicleReturnPdfLayout.driverAddress,
                VehicleReturnPdfLayout.returnDate, VehicleReturnPdfLayout.returnTime, VehicleReturnPdfLayout.returnLocation, VehicleReturnPdfLayout.returnOdometer,
                VehicleReturnPdfLayout.vehicleModel, VehicleReturnPdfLayout.vehiclePlate, VehicleReturnPdfLayout.vehicleColor, VehicleReturnPdfLayout.vehicleFuelType,
                VehicleReturnPdfLayout.vehicleClass, VehicleReturnPdfLayout.vehicleVIN,
                VehicleReturnPdfLayout.fuelGaugeArea, VehicleReturnPdfLayout.damageMapArea,
                VehicleReturnPdfLayout.renterName, VehicleReturnPdfLayout.deliveredByName,
                VehicleReturnPdfLayout.renterSignature, VehicleReturnPdfLayout.deliveredSignature
            ]
            page1Boxes.forEach { drawDebugBox($0, pageRect: pageRect, context: context, color: .red) }
        }
    }

    private func renderPage2(_ data: VehicleReturnPdfData, pageRect: CGRect, context: CGContext, debugLayout: Bool) {
        // Wipe any "photos placed by app" placeholder texts the template may contain
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.fill(toPageRect(nbox(0.10, 0.055, 0.80, 0.040), pageRect: pageRect))  // vehicle title area
        context.fill(toPageRect(nbox(0.10, 0.500, 0.80, 0.045), pageRect: pageRect))  // damage title area
        context.restoreGState()

        // Section title: vehicle photos
        let titleFont = UIFont.boldSystemFont(ofSize: 11)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.darkGray
        ]
        let vehicleTitleRect = toPageRect(nbox(0.02, 0.060, 0.96, 0.030), pageRect: pageRect)
        ("ARAÇ FOTOĞRAFLARI / VEHICLE PHOTOS" as NSString).draw(in: vehicleTitleRect, withAttributes: titleAttrs)

        for (idx, box) in Page2Layout.vehiclePhotos.enumerated() {
            guard idx < data.vehiclePhotos.count else { break }
            drawImageAspectFillClipped(data.vehiclePhotos[idx], in: box, pageRect: pageRect, context: context)
            if let timestamp = clean(data.timestamp) {
                let stampBox = nbox(box.x + 0.01, box.y + 0.01, box.w * 0.55, 0.022)
                drawTextInBox(timestamp, in: stampBox, pageRect: pageRect, context: context, baseFont: .boldSystemFont(ofSize: 9), minFontSize: 7, color: .white)
            }
        }

        // Section title: damage photos (only if there are damage photos)
        if !data.damagePhotos.isEmpty {
            let damageTitleRect = toPageRect(nbox(0.02, 0.505, 0.96, 0.030), pageRect: pageRect)
            ("HASAR FOTOĞRAFLARI / DAMAGE PHOTOS" as NSString).draw(in: damageTitleRect, withAttributes: titleAttrs)
        }

        for (idx, box) in Page2Layout.damagePhotos.enumerated() {
            guard idx < data.damagePhotos.count else { break }
            drawImageAspectFillClipped(data.damagePhotos[idx], in: box, pageRect: pageRect, context: context)
            if let timestamp = clean(data.timestamp) {
                let stampBox = nbox(box.x + 0.01, box.y + 0.01, box.w * 0.60, 0.022)
                drawTextInBox(timestamp, in: stampBox, pageRect: pageRect, context: context, baseFont: .boldSystemFont(ofSize: 9), minFontSize: 7, color: .white)
            }
        }

        if debugLayout {
            Page2Layout.vehiclePhotos.forEach { drawDebugBox($0, pageRect: pageRect, context: context, color: .red) }
            Page2Layout.damagePhotos.forEach { drawDebugBox($0, pageRect: pageRect, context: context, color: .orange) }
        }
    }

    private func drawTextInBox(
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

    private func drawCenteredX(in box: NBox, pageRect: CGRect, context: CGContext) {
        let rect = toPageRect(box, pageRect: pageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: min(rect.width, rect.height) * 0.78),
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

    private func drawYesNo(_ value: Bool?, cell: YesNoCell, pageRect: CGRect, context: CGContext) {
        guard let value else { return }
        drawCenteredX(in: value ? cell.yes : cell.no, pageRect: pageRect, context: context)
    }

    private func drawFuelMarker(ratio: CGFloat?, in area: NBox, pageRect: CGRect, context: CGContext) {
        guard let ratio else { return }
        let rect = toPageRect(area, pageRect: pageRect)
        let clamped = min(1, max(0, ratio))

        // Semi-circular gauge: arc bottom-centre, needle rotates from π (Empty) to 0 (Full)
        let cx = rect.midX
        let cy = rect.maxY - rect.height * 0.12
        let radius = min(rect.width * 0.36, rect.height * 0.70)

        context.saveGState()

        // Background arc track
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(3.5)
        context.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: .pi, endAngle: 0, clockwise: false)
        context.strokePath()

        // Tick marks at eigths
        context.setStrokeColor(UIColor.systemGray2.cgColor)
        context.setLineWidth(0.6)
        for i in 0...8 {
            let t = CGFloat(i) / 8.0
            let a: CGFloat = .pi - .pi * t
            let inner = radius - 4
            let outer = radius + 4
            context.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
            context.addLine(to: CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
            context.strokePath()
        }

        // Needle
        let needleAngle: CGFloat = .pi - .pi * clamped
        let needleLen = radius * 0.75
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(1.6)
        context.move(to: CGPoint(x: cx, y: cy))
        context.addLine(to: CGPoint(x: cx + cos(needleAngle) * needleLen, y: cy + sin(needleAngle) * needleLen))
        context.strokePath()

        // Center pivot dot
        context.setFillColor(UIColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5))

        // E / F labels
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 8),
            .foregroundColor: UIColor.darkGray
        ]
        ("E" as NSString).draw(at: CGPoint(x: rect.minX + 4, y: cy - 10), withAttributes: labelAttrs)
        ("F" as NSString).draw(at: CGPoint(x: rect.maxX - 12, y: cy - 10), withAttributes: labelAttrs)

        context.restoreGState()
    }

    private func drawDamageMarker(point: DamagePoint, in mapArea: NBox, pageRect: CGRect, context: CGContext) {
        let mapRect = toPageRect(mapArea, pageRect: pageRect)
        let px = mapRect.minX + mapRect.width * min(1, max(0, point.x))
        let py = mapRect.minY + mapRect.height * min(1, max(0, point.y))
        let markerRect = CGRect(x: px - 6, y: py - 6, width: 12, height: 12)
        context.saveGState()
        context.clip(to: mapRect)
        let box = NBox(
            x: (markerRect.minX - pageRect.minX) / pageRect.width,
            y: (markerRect.minY - pageRect.minY) / pageRect.height,
            w: markerRect.width / pageRect.width,
            h: markerRect.height / pageRect.height
        )
        drawCenteredX(in: box, pageRect: pageRect, context: context)
        context.restoreGState()
    }

    private func drawImageAspectFillClipped(_ image: UIImage?, in box: NBox, pageRect: CGRect, context: CGContext) {
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

    private func drawSignatureImage(_ image: UIImage?, in box: NBox, pageRect: CGRect, context: CGContext) {
        guard let image else { return }
        let rect = toPageRect(box, pageRect: pageRect).insetBy(dx: 2, dy: 2)
        guard rect.width > 0, rect.height > 0 else { return }
        let fit = aspectFitRect(imageSize: image.size, in: rect)
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: fit)
        context.restoreGState()
    }

    private func drawDebugBox(_ box: NBox, pageRect: CGRect, context: CGContext, color: UIColor) {
        let rect = toPageRect(box, pageRect: pageRect)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.8)
        context.stroke(rect)
        context.restoreGState()
    }

    private func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "-" { return nil }
        return t
    }

    private func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let sx = rect.width / imageSize.width
        let sy = rect.height / imageSize.height
        let scale = min(sx, sy)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
